<#
.SYNOPSIS
    Scans item-level permissions via Microsoft Graph v1.0 with JSON batching.

.DESCRIPTION
    Companion scanner for Get-KnowledgeSourceItemPermissions.ps1 that uses
    the Microsoft Graph v1.0 /drives/{driveId}/items/{itemId}/permissions
    endpoint instead of PnP/CSOM role assignments.

    Key capabilities:
    - Uses Graph v1.0 (not beta) for all permission reads
    - JSON batching with ≤20 requests per batch (Graph documented limit)
    - Retry-After header handling for 429/503 responses
    - Exponential backoff when Retry-After is absent
    - Resolves grantedToIdentitiesV2 for specific-people (FlexibleLink) shares

    This script requires Microsoft Graph application or delegated permissions
    and is designed for high-volume scans where PnP item-by-item enumeration
    is too slow.

.PARAMETER DriveId
    SharePoint document library drive ID (Graph drive resource ID).

.PARAMETER ItemIds
    Array of Graph driveItem IDs to scan for permissions.

.PARAMETER AccessToken
    OAuth 2.0 bearer token with required Graph permissions.

.PARAMETER GraphBaseUrl
    Microsoft Graph base URL. Defaults to https://graph.microsoft.com.
    Use https://graph.microsoft.us for GCC High/DoD or
    https://microsoftgraph.chinacloudapi.cn for 21Vianet.

.PARAMETER BatchSize
    Maximum requests per JSON batch. Capped at 20 (Graph limit).
    Defaults to 20.

.PARAMETER MaxRetries
    Maximum retry attempts for throttled requests. Defaults to 5.

.EXAMPLE
    $token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
    .\Invoke-GraphPermissionScan.ps1 -DriveId "b!abc123" -ItemIds @("01ABC","02DEF") -AccessToken $token

.NOTES
    Version:    1.1.2
    Author:     FSI Agent Governance
    Framework:  FSI Agent Governance
    Controls:   4.3, 1.4, 1.5

    Required Microsoft Graph permissions (application or delegated):
    - Sites.Read.All  — Read site and drive metadata
    - Files.Read.All  — Read file content and permissions
    - Group.Read.All  — Resolve group-based permission grants

    For delegated flows, the signed-in user must also have access to the
    target SharePoint site.
#>

#Requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DriveId,

    [Parameter(Mandatory = $true)]
    [string[]]$ItemIds,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [string]$GraphBaseUrl = "https://graph.microsoft.com",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 20)]
    [int]$BatchSize = 20,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 5
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$GRAPH_BATCH_LIMIT = 20
if ($BatchSize -gt $GRAPH_BATCH_LIMIT) {
    Write-Warning "BatchSize $BatchSize exceeds Graph limit of $GRAPH_BATCH_LIMIT. Clamping to $GRAPH_BATCH_LIMIT."
    $BatchSize = $GRAPH_BATCH_LIMIT
}

$script:Headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

# ---------------------------------------------------------------------------
# Retry logic
# ---------------------------------------------------------------------------

function Invoke-GraphRequestWithRetry {
    <#
    .SYNOPSIS
        Invokes a Graph REST call with Retry-After and exponential backoff.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [string]$Method,
        [object]$Body,
        [int]$MaxAttempts = 5
    )

    $attempt = 0
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            $invokeParams = @{
                Uri     = $Uri
                Method  = $Method
                Headers = $script:Headers
            }
            if ($Body) {
                $invokeParams["Body"] = ($Body | ConvertTo-Json -Depth 20 -Compress)
            }
            $response = Invoke-RestMethod @invokeParams -ResponseHeadersVariable responseHeaders
            return $response
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($statusCode -in @(429, 503) -and $attempt -lt $MaxAttempts) {
                $retryAfter = $null

                # Check Retry-After header
                if ($responseHeaders -and $responseHeaders.ContainsKey("Retry-After")) {
                    $retryAfterValue = $responseHeaders["Retry-After"] | Select-Object -First 1
                    if ([int]::TryParse($retryAfterValue, [ref]$retryAfter)) {
                        Write-Verbose "Throttled ($statusCode). Retry-After: ${retryAfter}s (attempt $attempt/$MaxAttempts)"
                    }
                }

                # Exponential backoff if no Retry-After
                if (-not $retryAfter -or $retryAfter -le 0) {
                    $retryAfter = [math]::Pow(2, $attempt)
                    Write-Verbose "Throttled ($statusCode). No Retry-After header; backing off ${retryAfter}s (attempt $attempt/$MaxAttempts)"
                }

                Start-Sleep -Seconds $retryAfter
                continue
            }

            throw
        }
    }

    throw "Graph request to $Uri failed after $MaxAttempts attempts."
}

# ---------------------------------------------------------------------------
# Batching
# ---------------------------------------------------------------------------

function Invoke-GraphBatch {
    <#
    .SYNOPSIS
        Sends a JSON batch request to Microsoft Graph with ≤20 requests.
    .DESCRIPTION
        Implements Microsoft Graph JSON batching per
        https://learn.microsoft.com/graph/json-batching.
        Each batch contains up to 20 individual requests. Throttled
        sub-requests (429/503) are retried individually with Retry-After
        handling.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Requests,

        [int]$MaxSubRequestRetries = 5
    )

    if ($Requests.Count -gt $GRAPH_BATCH_LIMIT) {
        throw "Batch contains $($Requests.Count) requests, exceeding the Graph limit of $GRAPH_BATCH_LIMIT."
    }

    $batchPayload = @{
        requests = $Requests
    }

    $batchUri = "$GraphBaseUrl/v1.0/`$batch"
    $batchResponse = Invoke-GraphRequestWithRetry -Uri $batchUri -Method "POST" -Body $batchPayload -MaxAttempts $MaxRetries

    $results = @{}
    $retryQueue = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($resp in $batchResponse.responses) {
        $id = $resp.id
        $status = [int]$resp.status

        if ($status -in @(429, 503)) {
            # Extract per-request Retry-After from the sub-response headers
            $subRetryAfter = $null
            if ($resp.headers -and $resp.headers.'Retry-After') {
                [int]::TryParse($resp.headers.'Retry-After', [ref]$subRetryAfter) | Out-Null
            }

            $originalRequest = $Requests | Where-Object { $_.id -eq $id } | Select-Object -First 1
            if ($originalRequest) {
                $retryQueue.Add(@{
                    Request    = $originalRequest
                    RetryAfter = if ($subRetryAfter -and $subRetryAfter -gt 0) { $subRetryAfter } else { $null }
                    Attempt    = 1
                })
            }
        }
        else {
            $results[$id] = $resp
        }
    }

    # Retry throttled sub-requests individually
    foreach ($retry in $retryQueue) {
        $req = $retry.Request
        $attempt = $retry.Attempt

        while ($attempt -le $MaxSubRequestRetries) {
            $sleepSeconds = if ($retry.RetryAfter) { $retry.RetryAfter } else { [math]::Pow(2, $attempt) }
            Write-Verbose "Retrying batch sub-request $($req.id) after ${sleepSeconds}s (attempt $attempt/$MaxSubRequestRetries)"
            Start-Sleep -Seconds $sleepSeconds

            $individualUri = "$GraphBaseUrl/$($req.url)"
            try {
                $individualResponse = Invoke-GraphRequestWithRetry -Uri $individualUri -Method $req.method -MaxAttempts 1
                $results[$req.id] = @{
                    id     = $req.id
                    status = 200
                    body   = $individualResponse
                }
                break
            }
            catch {
                $attempt++
                $retry.RetryAfter = $null  # Use backoff for subsequent retries
            }
        }

        if (-not $results.ContainsKey($req.id)) {
            Write-Warning "Sub-request $($req.id) failed after $MaxSubRequestRetries retries."
            $results[$req.id] = @{
                id     = $req.id
                status = 429
                body   = @{ error = @{ message = "Exhausted retries for throttled sub-request" } }
            }
        }
    }

    return $results
}

# ---------------------------------------------------------------------------
# Permission scanning
# ---------------------------------------------------------------------------

function Get-DriveItemPermissionsBatched {
    <#
    .SYNOPSIS
        Retrieves permissions for multiple drive items using Graph JSON batching.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$DriveId,
        [Parameter(Mandatory)] [string[]]$ItemIds,
        [int]$BatchSize = 20
    )

    $allPermissions = @{}
    $batches = [System.Collections.Generic.List[hashtable[]]]::new()

    # Split ItemIds into batches of $BatchSize
    for ($i = 0; $i -lt $ItemIds.Count; $i += $BatchSize) {
        $batchItems = $ItemIds[$i..([math]::Min($i + $BatchSize - 1, $ItemIds.Count - 1))]
        $requests = @()
        $idx = 0
        foreach ($itemId in $batchItems) {
            $idx++
            $requests += @{
                id     = "$($i + $idx)"
                method = "GET"
                url    = "v1.0/drives/$DriveId/items/$itemId/permissions"
            }
        }
        $batches.Add($requests)
    }

    $batchIndex = 0
    foreach ($batch in $batches) {
        $batchIndex++
        Write-Verbose "Processing batch $batchIndex/$($batches.Count) ($($batch.Count) requests)"

        $results = Invoke-GraphBatch -Requests $batch -MaxSubRequestRetries $MaxRetries

        # Map results back to item IDs.
        # ID-to-index contract: batch request IDs are generated above as "$($i + $idx)"
        # where $i is the batch offset into $ItemIds and $idx is 1-based within the batch,
        # producing 1-based sequential IDs across all batches. Subtracting 1 recovers the
        # 0-based $ItemIds index. If either the ID generator above OR this consumer is
        # modified, both sides MUST be updated together.
        for ($j = 0; $j -lt $batch.Count; $j++) {
            $req = $batch[$j]
            $itemId = $ItemIds[[int]$req.id - 1]
            $resp = $results[$req.id]

            if ($resp -and [int]$resp.status -eq 200) {
                $permissions = if ($resp.body.value) { $resp.body.value } else { @() }
                $allPermissions[$itemId] = $permissions
            }
            else {
                Write-Warning "Failed to retrieve permissions for item $itemId (status: $($resp.status))"
                $allPermissions[$itemId] = @()
            }
        }
    }

    return $allPermissions
}

function ConvertTo-PermissionReport {
    <#
    .SYNOPSIS
        Converts Graph permission responses to risk-scored report entries.
    .DESCRIPTION
        Processes grantedToIdentitiesV2 for specific-people links, resolving
        the FlexibleLink limitation of the PnP-based scanner.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ItemId,
        [Parameter(Mandatory)] [object[]]$Permissions
    )

    $entries = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($perm in $Permissions) {
        $permType = "DirectPermission"
        $affectedUsers = ""
        $roles = ($perm.roles -join ", ")

        if ($perm.link) {
            $scope = $perm.link.scope
            switch ($scope) {
                "anonymous"    { $permType = "AnonymousLink"; $affectedUsers = "Anyone with the link" }
                "organization" { $permType = "OrganizationLink"; $affectedUsers = "All organization members" }
                "users" {
                    $permType = "SpecificPeopleLink"
                    # Resolve grantedToIdentitiesV2 for specific-people grants
                    if ($perm.grantedToIdentitiesV2) {
                        $identities = @()
                        foreach ($identity in $perm.grantedToIdentitiesV2) {
                            if ($identity.user -and $identity.user.displayName) {
                                $identities += $identity.user.displayName
                            }
                            elseif ($identity.user -and $identity.user.email) {
                                $identities += $identity.user.email
                            }
                            elseif ($identity.group -and $identity.group.displayName) {
                                $identities += "Group: $($identity.group.displayName)"
                            }
                        }
                        $affectedUsers = $identities -join "; "
                    }
                    else {
                        $affectedUsers = "Specific people (details unavailable)"
                    }
                }
                default { $permType = "OtherLink"; $affectedUsers = "Link scope: $scope" }
            }
        }
        elseif ($perm.grantedToV2) {
            if ($perm.grantedToV2.user) {
                $affectedUsers = $perm.grantedToV2.user.displayName
            }
            elseif ($perm.grantedToV2.group) {
                $permType = "GroupPermission"
                $affectedUsers = "Group: $($perm.grantedToV2.group.displayName)"
            }
        }

        $entries.Add(@{
            ItemId        = $ItemId
            PermissionId  = $perm.id
            PermissionType = $permType
            Roles         = $roles
            AffectedUsers = $affectedUsers
        })
    }

    return $entries
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

try {
    Write-Host ""
    Write-Host "Agent Knowledge Source Scanner — Graph v1.0 Permission Scan" -ForegroundColor Cyan
    Write-Host "  Drive:      $DriveId" -ForegroundColor White
    Write-Host "  Items:      $($ItemIds.Count)" -ForegroundColor White
    Write-Host "  Batch size: $BatchSize (Graph limit: $GRAPH_BATCH_LIMIT)" -ForegroundColor White
    Write-Host ""

    $permissionMap = Get-DriveItemPermissionsBatched -DriveId $DriveId -ItemIds $ItemIds -BatchSize $BatchSize

    $allEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($itemId in $permissionMap.Keys) {
        $permissions = $permissionMap[$itemId]
        $entries = ConvertTo-PermissionReport -ItemId $itemId -Permissions $permissions

        foreach ($entry in $entries) {
            $allEntries.Add([PSCustomObject]@{
                ItemId         = $entry.ItemId
                PermissionId   = $entry.PermissionId
                PermissionType = $entry.PermissionType
                Roles          = $entry.Roles
                AffectedUsers  = $entry.AffectedUsers
            })
        }
    }

    Write-Host "Scan complete: $($allEntries.Count) permission entries across $($ItemIds.Count) items" -ForegroundColor Green

    # Return structured results for pipeline consumption
    $allEntries
}
catch {
    Write-Error "Graph permission scan failed: $($_.Exception.Message)"
    exit 1
}
