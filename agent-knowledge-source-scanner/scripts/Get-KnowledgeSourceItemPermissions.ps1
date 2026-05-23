<#
.SYNOPSIS
    Enumerates item-level permissions in agent knowledge source SharePoint libraries.

.DESCRIPTION
    Scans SharePoint libraries backing Copilot Studio agent knowledge sources
    and identifies files with overshared permissions.

    Key capabilities:
    - Enumerates all items in agent-connected SharePoint libraries
    - Detects items with permissions broader than the agent's intended user group
    - Cross-references sensitivity labels to identify high-risk oversharing
    - Produces a risk-scored CSV report for compliance review

    Risk scoring (agent knowledge source context — stricter than general SharePoint):
    - CRITICAL: CRITICAL-tier sensitivity label AND accessible outside agent user group
    - HIGH: Anyone link, external/guest user, OR HIGH-tier sensitivity label out-of-scope
    - MEDIUM: Org-wide link with write-equivalent access (Edit/Contribute/Full Control)
    - LOW: Item accessible to a broader internal group than agent's target audience,
           read-only org-wide link, or FlexibleLink (per-recipient grants we cannot enumerate)

    An agent returns exact document content, not site-level summaries. Item-level
    oversharing in a knowledge source library creates a direct data exposure path
    through the agent.

.PARAMETER SiteUrl
    SharePoint site URL containing the knowledge source library.
    Can be specified multiple times or combined with -LibraryList.

.PARAMETER LibraryName
    Name of the document library to scan. Defaults to "Documents".

.PARAMETER LibraryList
    Path to a CSV or JSON file listing agent knowledge source libraries.
    CSV format: SiteUrl,LibraryName,AgentName
    JSON format: array of objects with siteUrl, libraryName, agentName properties.

.PARAMETER AgentName
    Name of the agent using this knowledge source (for report labeling).

.PARAMETER AgentUserGroupId
    Object ID of the Entra security group representing the agent's intended
    user audience. Items accessible to users outside this group are flagged.

.PARAMETER AgentUserGroupMembers
    Array of UPNs representing the agent's intended user audience.
    Alternative to -AgentUserGroupId when group membership is known.

.PARAMETER ClientId
    Entra app registration Client ID for PnP.PowerShell authentication.
    Required for PnP.PowerShell 3.x interactive authentication unless an
    ENTRAID_CLIENT_ID / ENTRAID_APP_ID environment variable
    supplies the client ID. Required for certificate authentication.

.PARAMETER AuthenticationMode
    Authentication mode for Connect-PnPOnline. Use ManagedIdentity for Azure
    Automation, Azure Functions, or other managed identity-capable hosts; use
    Certificate for legacy unattended jobs; use Interactive for admin workstation
    scans. Defaults to Interactive for backward compatibility.

.PARAMETER Tenant
    Microsoft Entra tenant name or ID. Required for certificate authentication.

.PARAMETER ManagedIdentityClientId
    Client ID of a user-assigned managed identity. Use only with
    -AuthenticationMode ManagedIdentity.

.PARAMETER ManagedIdentityObjectId
    Object/principal ID of a user-assigned managed identity. Use only with
    -AuthenticationMode ManagedIdentity.

.PARAMETER ManagedIdentityAzureResourceId
    Azure resource ID of a user-assigned managed identity. Use only with
    -AuthenticationMode ManagedIdentity.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for app-only PnP authentication. Use only with
    -AuthenticationMode Certificate.

.PARAMETER CertificatePath
    Path to a PFX certificate for app-only PnP authentication. Use only with
    -AuthenticationMode Certificate.

.PARAMETER CertificateBase64Encoded
    Base64-encoded PFX certificate for app-only PnP authentication. Use only
    with -AuthenticationMode Certificate.

.PARAMETER CertificatePassword
    Password for CertificatePath or CertificateBase64Encoded when required.

.PARAMETER ConfigPath
    Path to the item-scope-config.json configuration file.
    Defaults to ../templates/item-scope-config.sample.json relative to script.

.PARAMETER MaxItemsPerLibrary
    Maximum number of items to scan per library. Defaults to 10000.
    Override with config file or this parameter.

.PARAMETER OutputPath
    Path for the output CSV report. Defaults to ./output/item-permissions-report.csv.
    A header-only CSV is always written, even when no findings are detected,
    so downstream automation can rely on the artifact existing.

.PARAMETER IncludeCompliant
    When specified, includes compliant (no-risk) items in the output report.
    By default, only items with identified risks are included.

.EXAMPLE
    .\Get-KnowledgeSourceItemPermissions.ps1 -SiteUrl "https://example.sharepoint.com/sites/AgentKB" -LibraryName "Documents" -AgentName "HR-Agent" -AgentUserGroupId "00000000-0000-0000-0000-000000000001" -AuthenticationMode ManagedIdentity

    Scans a single library for the HR Agent's knowledge source from a managed identity-capable host.

.EXAMPLE
    .\Get-KnowledgeSourceItemPermissions.ps1 -SiteUrl "https://example.sharepoint.com/sites/AgentKB" -LibraryName "Documents" -AgentName "HR-Agent" -AgentUserGroupId "00000000-0000-0000-0000-000000000001" -ClientId "00000000-0000-0000-0000-000000000099"

    Scans a single library for the HR Agent's knowledge source using interactive authentication and a tenant-specific app registration.

.EXAMPLE
    .\Get-KnowledgeSourceItemPermissions.ps1 -LibraryList "./output/agent-knowledge-sources.csv" -AgentUserGroupId "00000000-0000-0000-0000-000000000001" -ClientId "00000000-0000-0000-0000-000000000099" -OutputPath "./output/item-risk-report.csv"

    Scans all libraries from a prior knowledge source scan output.

.EXAMPLE
    .\Get-KnowledgeSourceItemPermissions.ps1 -SiteUrl "https://example.sharepoint.com/sites/AgentKB" -AgentUserGroupMembers @("user1@example.com","user2@example.com") -ClientId "00000000-0000-0000-0000-000000000099" -WhatIf

    Dry-run scan showing what would be checked without making changes.

.OUTPUTS
    CSV file with columns: AgentName, KnowledgeSourceSite, LibraryName,
    ItemPath, ItemTitle, SensitivityLabel, BroadPermission, PermissionType,
    AffectedUsers, RiskScore

.NOTES
    Version:    1.1.2
    Author:     FSI Agent Governance
    Requires:   PnP.PowerShell 2.5.0+ (3.x supported with -ClientId)
    Requires:   PowerShell 7.2+ (7.4+ for PnP.PowerShell 3.x)
    Framework:  FSI Agent Governance
    Controls:   4.3, 1.4, 1.5

    Known limitations (documented in .ralph-config.json and docs/troubleshooting.md):
    - PnP.PowerShell 3.x uses Get-PnPEntraIDGroupMember -Transitive for nested
      group expansion. PnP.PowerShell 2.x fallback uses Get-PnPAzureADGroupMember
      and reports direct members only.
    - SensitivityLabel comparison matches against display names. If your tenant
      labels store as GUIDs in `_SensitivityLabel`, populate
      `sensitivityLabelRiskTiers` with the GUID values rather than display names.
    - Specific-people sharing links are surfaced as FlexibleLink via PnP role
      assignments. Microsoft Graph driveItem permissions can provide richer
      grantedToIdentitiesV2 details for future correlation.
#>

#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "PnP.PowerShell"; ModuleVersion = "2.5.0" }

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$SiteUrl,

    [Parameter(Mandatory = $false)]
    [string]$LibraryName = "Documents",

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ })]
    [string]$LibraryList,

    [Parameter(Mandatory = $false)]
    [string]$AgentName = "Unknown",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$')]
    [string]$AgentUserGroupId,

    [Parameter(Mandatory = $false)]
    [string[]]$AgentUserGroupMembers,

    [Parameter(Mandatory = $false, HelpMessage = "Entra app registration Client ID for PnP.PowerShell authentication. Required for PnP.PowerShell 3.x interactive auth and certificate auth.")]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Interactive", "ManagedIdentity", "Certificate")]
    [string]$AuthenticationMode = "Interactive",

    [Parameter(Mandatory = $false)]
    [string]$Tenant,

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityClientId,

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityObjectId,

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityAzureResourceId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$CertificatePath,

    [Parameter(Mandatory = $false)]
    [string]$CertificateBase64Encoded,

    [Parameter(Mandatory = $false)]
    [securestring]$CertificatePassword,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100000)]
    [int]$MaxItemsPerLibrary = 10000,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\output\item-permissions-report.csv",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCompliant
)

$ErrorActionPreference = "Stop"
$script:CorrelationId = [guid]::NewGuid().ToString("N").Substring(0, 8)

#region Configuration

function Write-AuditLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host "[$timestamp] [$Level] [$script:CorrelationId] $Message" -ForegroundColor $color
}

function Get-ScanConfig {
    param([string]$Path)

    $defaults = @{
        scanScope                  = "agent-knowledge-sources-only"
        sensitivityLabelRiskTiers  = @{
            CRITICAL = @("Highly Confidential", "Restricted")
            HIGH     = @("Confidential", "Internal Confidential")
            MEDIUM   = @("Internal")
            LOW      = @("Public", "General")
        }
        agentUserScopeResolution   = "from-parameter"
        maxItemsPerLibrary         = 10000
        outputPath                 = ".\output\item-permissions-report.csv"
    }

    if ($Path -and (Test-Path $Path)) {
        try {
            $fileConfig = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
            foreach ($key in $fileConfig.Keys) {
                $defaults[$key] = $fileConfig[$key]
            }
            Write-AuditLog "Loaded configuration from $Path"
        }
        catch {
            Write-AuditLog "Failed to parse config file '$Path': $($_.Exception.Message)" "WARN"
        }
    }

    return $defaults
}

#endregion

#region Functions

function Get-LibraryTargets {
    param(
        [string[]]$SiteUrls,
        [string]$DefaultLibraryName,
        [string]$DefaultAgentName,
        [string]$ListPath
    )

    $targets = [System.Collections.Generic.List[hashtable]]::new()

    if ($ListPath) {
        $extension = [System.IO.Path]::GetExtension($ListPath).ToLower()
        if ($extension -eq ".csv") {
            $csvData = Import-Csv -Path $ListPath
            foreach ($row in $csvData) {
                $targets.Add(@{
                    SiteUrl     = $row.SiteUrl
                    LibraryName = if ($row.LibraryName) { $row.LibraryName } else { $DefaultLibraryName }
                    AgentName   = if ($row.AgentName) { $row.AgentName } else { $DefaultAgentName }
                })
            }
        }
        elseif ($extension -eq ".json") {
            try {
                $jsonData = Get-Content $ListPath -Raw | ConvertFrom-Json
                if ($null -eq $jsonData) {
                    throw "JSON file is empty or contains null"
                }
            } catch {
                throw "Failed to parse JSON file '$ListPath': $($_.Exception.Message)"
            }
            foreach ($item in $jsonData) {
                $targets.Add(@{
                    SiteUrl     = $item.siteUrl
                    LibraryName = if ($item.libraryName) { $item.libraryName } else { $DefaultLibraryName }
                    AgentName   = if ($item.agentName) { $item.agentName } else { $DefaultAgentName }
                })
            }
        }
        else {
            throw "Unsupported file format '$extension'. Use .csv or .json."
        }
    }

    if ($SiteUrls) {
        foreach ($url in $SiteUrls) {
            $targets.Add(@{
                SiteUrl     = $url
                LibraryName = $DefaultLibraryName
                AgentName   = $DefaultAgentName
            })
        }
    }

    if ($targets.Count -eq 0) {
        throw "No scan targets specified. Provide -SiteUrl, -LibraryList, or both."
    }

    return $targets
}

function Get-SelectedValueCount {
    param([object[]]$Values)

    return @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
}

function Connect-KnowledgeSourceScanner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Interactive", "ManagedIdentity", "Certificate")]
        [string]$Mode,

        [string]$ClientId,
        [string]$Tenant,
        [string]$ManagedIdentityClientId,
        [string]$ManagedIdentityObjectId,
        [string]$ManagedIdentityAzureResourceId,
        [string]$CertificateThumbprint,
        [string]$CertificatePath,
        [string]$CertificateBase64Encoded,
        [securestring]$CertificatePassword
    )

    $connectParams = @{ Url = $Url }

    switch ($Mode) {
        "ManagedIdentity" {
            $identitySelectors = Get-SelectedValueCount -Values @(
                $ManagedIdentityClientId,
                $ManagedIdentityObjectId,
                $ManagedIdentityAzureResourceId
            )
            if ($identitySelectors -gt 1) {
                throw "Specify only one user-assigned managed identity selector: -ManagedIdentityClientId, -ManagedIdentityObjectId, or -ManagedIdentityAzureResourceId."
            }

            $connectParams["ManagedIdentity"] = $true
            if ($ManagedIdentityClientId) {
                $connectParams["UserAssignedManagedIdentityClientId"] = $ManagedIdentityClientId
            }
            if ($ManagedIdentityObjectId) {
                $connectParams["UserAssignedManagedIdentityObjectId"] = $ManagedIdentityObjectId
            }
            if ($ManagedIdentityAzureResourceId) {
                $connectParams["UserAssignedManagedIdentityAzureResourceId"] = $ManagedIdentityAzureResourceId
            }
        }
        "Certificate" {
            if (-not $ClientId -or -not $Tenant) {
                throw "Certificate authentication requires -ClientId and -Tenant."
            }

            $certificateSelectors = Get-SelectedValueCount -Values @(
                $CertificateThumbprint,
                $CertificatePath,
                $CertificateBase64Encoded
            )
            if ($certificateSelectors -ne 1) {
                throw "Certificate authentication requires exactly one of -CertificateThumbprint, -CertificatePath, or -CertificateBase64Encoded."
            }

            $connectParams["ClientId"] = $ClientId
            $connectParams["Tenant"] = $Tenant
            if ($CertificateThumbprint) { $connectParams["Thumbprint"] = $CertificateThumbprint }
            if ($CertificatePath) { $connectParams["CertificatePath"] = $CertificatePath }
            if ($CertificateBase64Encoded) {
                $connectParams["CertificateBase64Encoded"] = $CertificateBase64Encoded
            }
            if (($CertificatePath -or $CertificateBase64Encoded) -and $CertificatePassword) {
                $connectParams["CertificatePassword"] = $CertificatePassword
            }
        }
        default {
            $connectParams["Interactive"] = $true
            if ($ClientId) { $connectParams["ClientId"] = $ClientId }
        }
    }

    Connect-PnPOnline @connectParams -ErrorAction Stop
}

function Get-EntraGroupMembersForScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId
    )

    try {
        return @(Get-PnPEntraIDGroupMember -Identity $GroupId -Transitive -ErrorAction Stop)
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        Write-AuditLog "Get-PnPEntraIDGroupMember is not available; falling back to Get-PnPAzureADGroupMember direct membership." "WARN"
        return @(Get-PnPAzureADGroupMember -Identity $GroupId -ErrorAction Stop)
    }
    catch [System.Management.Automation.ParameterBindingException] {
        Write-AuditLog "Get-PnPEntraIDGroupMember in this module version does not support -Transitive; falling back to direct membership." "WARN"
        return @(Get-PnPEntraIDGroupMember -Identity $GroupId -ErrorAction Stop)
    }
}

function Get-AgentUserScope {
    param(
        [string]$GroupId,
        [string[]]$Members
    )

    $scope = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    if ($Members) {
        foreach ($m in $Members) { [void]$scope.Add($m) }
        Write-AuditLog "Agent user scope: $($scope.Count) members from parameter"
        return $scope
    }

    if ($GroupId) {
        try {
            $groupMembers = Get-EntraGroupMembersForScope -GroupId $GroupId
            foreach ($member in $groupMembers) {
                if ($member.UserPrincipalName) {
                    [void]$scope.Add($member.UserPrincipalName)
                }
            }
            Write-AuditLog "Agent user scope: $($scope.Count) members from group $GroupId"
        }
        catch {
            Write-AuditLog "Failed to resolve group '$GroupId': $($_.Exception.Message)" "WARN"
            Write-AuditLog "Continuing without agent user scope comparison" "WARN"
        }
    }

    return $scope
}

function Get-SensitivityRiskTier {
    param(
        [string]$Label,
        [hashtable]$Tiers
    )

    if (-not $Label) { return $null }

    foreach ($tier in @("CRITICAL", "HIGH", "MEDIUM", "LOW")) {
        if ($Tiers.ContainsKey($tier)) {
            foreach ($labelName in $Tiers[$tier]) {
                if ($Label -ieq $labelName) { return $tier }
            }
        }
    }

    return $null
}

function Get-ItemRiskScore {
    param(
        [string]$PermissionType,
        [string]$SensitivityTier,
        [bool]$OutsideAgentScope,
        [string]$BroadPermission
    )

    # CRITICAL: high-sensitivity (CRITICAL tier) AND accessible outside the agent user group.
    # Note: HIGH-tier labels with out-of-scope access are reported as HIGH below; only the
    # CRITICAL tier escalates the finding to CRITICAL.
    if ($SensitivityTier -eq "CRITICAL" -and $OutsideAgentScope) {
        return "CRITICAL"
    }

    # HIGH: AnyoneLink / external grant / HIGH-sensitivity item exposed outside scope
    if ($PermissionType -in @("AnonymousLink", "ExternalUser", "GuestUser")) {
        return "HIGH"
    }
    if ($SensitivityTier -eq "HIGH" -and $OutsideAgentScope) {
        return "HIGH"
    }

    # MEDIUM: Org-wide link only when it grants write-equivalent permission
    if ($PermissionType -eq "OrganizationLink") {
        $writeRoles = @("Edit", "Contribute", "Full Control", "Design", "Manage Hierarchy")
        $isWrite = $false
        if ($BroadPermission) {
            foreach ($r in $writeRoles) {
                if ($BroadPermission -match [regex]::Escape($r)) { $isWrite = $true; break }
            }
        }
        if ($isWrite) { return "MEDIUM" }
        # Read-only org-wide link: still oversharing, but not write-grade
        return "LOW"
    }

    # LOW: any item accessible to a principal outside the agent user scope
    if ($OutsideAgentScope) {
        return "LOW"
    }

    return $null
}

function Get-ItemPermissionDetails {
    param(
        [object]$Item,
        [System.Collections.Generic.HashSet[string]]$AgentUserScope,
        [hashtable]$SensitivityTiers
    )

    $results = [System.Collections.Generic.List[hashtable]]::new()
    $itemPath = "Unknown"
    $itemTitle = "Unknown"
    $sensitivityLabel = $null

    if ($Item.FieldValues) {
        $itemPath = $Item.FieldValues["FileRef"]
        $itemTitle = $Item.FieldValues["Title"]
        $sensitivityLabel = $Item.FieldValues["_SensitivityLabel"]
    }

    if (-not $sensitivityLabel -and $Item.FieldValues) {
        $sensitivityLabel = $Item.FieldValues["_ComplianceTag"]
    }

    $sensitivityTier = Get-SensitivityRiskTier -Label $sensitivityLabel -Tiers $SensitivityTiers

    try {
        Get-PnPProperty -ClientObject $Item -Property "RoleAssignments" | Out-Null

        foreach ($roleAssignment in $Item.RoleAssignments) {
            Get-PnPProperty -ClientObject $roleAssignment -Property "Member", "RoleDefinitionBindings" | Out-Null
            $member = $roleAssignment.Member
            $memberLoginName = $member.LoginName
            $memberTitle = $member.Title

            $permissionType = "DirectPermission"
            $affectedUsers = $memberTitle

            # Detect sharing link types
            if ($memberLoginName -match "SharingLinks\.([a-f0-9\-]+)\.Anonymous") {
                $permissionType = "AnonymousLink"
                $affectedUsers = "Anyone with the link"
            }
            elseif ($memberLoginName -match "SharingLinks\.([a-f0-9\-]+)\.Organization") {
                $permissionType = "OrganizationLink"
                $affectedUsers = "All organization members"
            }
            elseif ($memberLoginName -match "SharingLinks\.([a-f0-9\-]+)\.Flexible") {
                $permissionType = "FlexibleLink"
                $affectedUsers = "Specific people (flexible link)"
            }
            elseif ($memberLoginName -match "c:0[%-]\.c\|federateddirectoryclaimprovider\|(.+)") {
                $permissionType = "ExternalUser"
                $affectedUsers = $Matches[1]
            }
            elseif ($memberLoginName -match "#ext#") {
                $permissionType = "GuestUser"
                $affectedUsers = $memberTitle
            }
            elseif ($memberLoginName -eq "c:0(.s|true") {
                # SharePoint claims encoding for the built-in "Everyone except external users" group.
                $permissionType = "EveryoneExceptExternal"
                $affectedUsers = "Everyone except external users"
            }

            # Determine the permission level (Read, Edit, Full Control, etc.)
            $permLevels = @()
            foreach ($roleDef in $roleAssignment.RoleDefinitionBindings) {
                $permLevels += $roleDef.Name
            }
            $broadPermission = $permLevels -join ", "

            # Check if outside agent scope
            $outsideScope = $false
            if ($AgentUserScope.Count -gt 0) {
                if ($permissionType -in @("AnonymousLink", "OrganizationLink", "EveryoneExceptExternal", "FlexibleLink")) {
                    # FlexibleLink encapsulates per-recipient grants we cannot enumerate
                    # without resolving the SharingLink object's grantees. Treat as out-of-scope
                    # so scoring assigns at least LOW; documented limitation in .ralph-config.json.
                    $outsideScope = $true
                }
                elseif ($permissionType -in @("ExternalUser", "GuestUser")) {
                    $outsideScope = $true
                }
                elseif ($permissionType -eq "DirectPermission") {
                    if ($member.PrincipalType -eq "User") {
                        $upn = $memberLoginName -replace "^i:0#\.f\|membership\|", ""
                        if (-not $AgentUserScope.Contains($upn)) {
                            $outsideScope = $true
                        }
                    }
                    elseif ($member.PrincipalType -eq "SecurityGroup" -or $member.PrincipalType -eq "FederatedUser") {
                        # Entra ID security group assigned directly. PnP.PowerShell 3.x
                        # resolves transitive members; PnP 2.x fallback is direct-only.
                        $groupId = $null
                        if ($memberLoginName -match "c:0[ot]\.t\|tenant\|([0-9a-f\-]{36})") { $groupId = $Matches[1] }
                        if ($groupId) {
                            try {
                                $grpMembers = $null
                                $grpMembers = Get-EntraGroupMembersForScope -GroupId $groupId
                                $allInScope = $true
                                foreach ($gm in $grpMembers) {
                                    if ($gm.UserPrincipalName -and -not $AgentUserScope.Contains($gm.UserPrincipalName)) {
                                        $allInScope = $false; break
                                    }
                                }
                                if (-not $allInScope) { $outsideScope = $true }
                            } catch {
                                Write-AuditLog "Could not enumerate Entra group $groupId for scope comparison: $($_.Exception.Message)" "WARN"
                                $outsideScope = $true
                            }
                        } else {
                            # Cannot extract group id — assume out-of-scope to err on side of disclosure
                            $outsideScope = $true
                        }
                    }
                    elseif ($member.PrincipalType -eq "SharePointGroup") {
                        try {
                            $spGroupMembers = Get-PnPGroupMember -Group $member.Title -ErrorAction Stop
                            $allInScope = $true
                            foreach ($gm in $spGroupMembers) {
                                $upn = $gm.LoginName -replace "^i:0#\.f\|membership\|", ""
                                if ($upn -and -not $AgentUserScope.Contains($upn)) {
                                    $allInScope = $false; break
                                }
                            }
                            if (-not $allInScope) { $outsideScope = $true }
                        } catch {
                            Write-AuditLog "Could not enumerate SharePoint group '$($member.Title)' for scope comparison: $($_.Exception.Message)" "WARN"
                            $outsideScope = $true
                        }
                    }
                }
            }

            $riskScore = Get-ItemRiskScore -PermissionType $permissionType `
                -SensitivityTier $sensitivityTier `
                -OutsideAgentScope $outsideScope `
                -BroadPermission $broadPermission

            if ($riskScore -or $IncludeCompliant) {
                $results.Add(@{
                    ItemPath         = $itemPath
                    ItemTitle        = if ($itemTitle) { $itemTitle } else { [System.IO.Path]::GetFileName($itemPath) }
                    SensitivityLabel = if ($sensitivityLabel) { $sensitivityLabel } else { "None" }
                    BroadPermission  = $broadPermission
                    PermissionType   = $permissionType
                    AffectedUsers    = $affectedUsers
                    RiskScore        = if ($riskScore) { $riskScore } else { "NONE" }
                    OutsideScope     = $outsideScope
                })
            }
        }
    }
    catch {
        Write-AuditLog "Failed to read permissions for '$itemPath': $($_.Exception.Message)" "WARN"
        $results.Add(@{
            ItemPath         = $itemPath
            ItemTitle        = if ($itemTitle) { $itemTitle } else { "Unknown" }
            SensitivityLabel = if ($sensitivityLabel) { $sensitivityLabel } else { "None" }
            BroadPermission  = "ERROR"
            PermissionType   = "ScanError"
            AffectedUsers    = $_.Exception.Message
            RiskScore        = "UNKNOWN"
            OutsideScope     = $false
        })
    }

    return $results
}

#endregion

#region Main Execution

try {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   Agent Knowledge Source — Item Permission Scanner       ║" -ForegroundColor Cyan
    Write-Host "║   FSI Agent Governance Framework v1.1.2                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Load configuration
    $configFilePath = $ConfigPath
    if (-not $configFilePath) {
        $configFilePath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" "item-scope-config.sample.json"
    }
    $config = Get-ScanConfig -Path $configFilePath

    if ($PSBoundParameters.ContainsKey('MaxItemsPerLibrary')) {
        $config.maxItemsPerLibrary = $MaxItemsPerLibrary
    }

    # Resolve scan targets
    $targets = Get-LibraryTargets -SiteUrls $SiteUrl -DefaultLibraryName $LibraryName `
        -DefaultAgentName $AgentName -ListPath $LibraryList

    Write-AuditLog "Scan targets: $($targets.Count) libraries"

    # Detect PnP.PowerShell version once before scanning
    $pnpModule = Get-Module PnP.PowerShell -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($pnpModule -and $pnpModule.Version.Major -ge 3 -and
        $AuthenticationMode -eq "Interactive" -and -not $ClientId -and
        -not $env:ENTRAID_CLIENT_ID -and -not $env:ENTRAID_APP_ID) {
        Write-AuditLog "PnP.PowerShell $($pnpModule.Version) detected. Interactive authentication requires -ClientId or an ENTRAID_CLIENT_ID / ENTRAID_APP_ID environment variable. Use Register-PnPEntraIDAppForInteractiveLogin to create a tenant-specific app registration." "ERROR"
        throw "PnP.PowerShell 3.x interactive authentication requires a tenant-specific client ID. See docs/prerequisites.md for setup instructions."
    }

    $authOptions = @{
        Mode                           = $AuthenticationMode
        ClientId                       = $ClientId
        Tenant                         = $Tenant
        ManagedIdentityClientId        = $ManagedIdentityClientId
        ManagedIdentityObjectId        = $ManagedIdentityObjectId
        ManagedIdentityAzureResourceId = $ManagedIdentityAzureResourceId
        CertificateThumbprint          = $CertificateThumbprint
        CertificatePath                = $CertificatePath
        CertificateBase64Encoded       = $CertificateBase64Encoded
        CertificatePassword            = $CertificatePassword
    }

    # Bootstrap a PnP connection BEFORE resolving the agent user scope. Get-PnPEntraIDGroupMember
    # requires an active PnP/Graph context; calling it cold previously failed silently and produced
    # an empty scope (disabling out-of-scope detection entirely).
    $bootstrapTarget = $targets | Select-Object -First 1
    if ($bootstrapTarget -and $AgentUserGroupId -and -not $AgentUserGroupMembers) {
        try {
            Connect-KnowledgeSourceScanner -Url $bootstrapTarget.SiteUrl @authOptions
            Write-AuditLog "Bootstrap connection established for scope resolution" "SUCCESS"
        } catch {
            Write-AuditLog "Bootstrap connection failed; agent user scope cannot be resolved from -AgentUserGroupId: $($_.Exception.Message)" "WARN"
        }
    }

    # Resolve agent user scope (now with PnP context available if -AgentUserGroupId was used)
    $agentScope = Get-AgentUserScope -GroupId $AgentUserGroupId -Members $AgentUserGroupMembers

    if ($agentScope.Count -eq 0) {
        Write-AuditLog "No agent user scope defined — scope comparison will be skipped" "WARN"
    }

    # Prepare output
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-AuditLog "Created output directory: $outputDir"
    }

    $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    $scanSummary = @{
        TotalLibraries = $targets.Count
        TotalItems     = 0
        CriticalCount  = 0
        HighCount      = 0
        MediumCount    = 0
        LowCount       = 0
        ErrorCount     = 0
    }

    # Scan each library
    $libraryIndex = 0
    foreach ($target in $targets) {
        $libraryIndex++
        Write-AuditLog ("Scanning library $libraryIndex/$($targets.Count): " +
            "$($target.SiteUrl) / $($target.LibraryName)")

        if ($PSCmdlet.ShouldProcess("$($target.SiteUrl)/$($target.LibraryName)", "Scan item permissions")) {
            try {
                Connect-KnowledgeSourceScanner -Url $target.SiteUrl @authOptions
                Write-AuditLog "Connected to $($target.SiteUrl)" "SUCCESS"

                $items = Get-PnPListItem -List $target.LibraryName `
                    -Fields "FileRef", "Title", "_SensitivityLabel", "_ComplianceTag" `
                    -PageSize 500 |
                    Select-Object -First $config.maxItemsPerLibrary

                $itemCount = @($items).Count
                Write-AuditLog "Retrieved $itemCount items from $($target.LibraryName)"
                $scanSummary.TotalItems += $itemCount

                $itemIndex = 0
                foreach ($item in $items) {
                    $itemIndex++
                    if ($itemIndex % 100 -eq 0) {
                        Write-AuditLog "Processing item $itemIndex/$itemCount..."
                    }

                    # Only scan items with unique permissions (HasUniqueRoleAssignments)
                    try {
                        Get-PnPProperty -ClientObject $item -Property "HasUniqueRoleAssignments" | Out-Null
                    } catch {
                        Write-Verbose "Could not load permissions for item $($item.Id): $($_.Exception.Message)"
                        continue
                    }

                    if (-not $item.HasUniqueRoleAssignments -and -not $IncludeCompliant) {
                        continue
                    }

                    $permResults = Get-ItemPermissionDetails -Item $item `
                        -AgentUserScope $agentScope `
                        -SensitivityTiers $config.sensitivityLabelRiskTiers

                    foreach ($result in $permResults) {
                        $allResults.Add([PSCustomObject]@{
                            AgentName           = $target.AgentName
                            KnowledgeSourceSite = $target.SiteUrl
                            LibraryName         = $target.LibraryName
                            ItemPath            = $result.ItemPath
                            ItemTitle           = $result.ItemTitle
                            SensitivityLabel    = $result.SensitivityLabel
                            BroadPermission     = $result.BroadPermission
                            PermissionType      = $result.PermissionType
                            AffectedUsers       = $result.AffectedUsers
                            RiskScore           = $result.RiskScore
                        })

                        switch ($result.RiskScore) {
                            "CRITICAL" { $scanSummary.CriticalCount++ }
                            "HIGH"     { $scanSummary.HighCount++ }
                            "MEDIUM"   { $scanSummary.MediumCount++ }
                            "LOW"      { $scanSummary.LowCount++ }
                            "UNKNOWN"  { $scanSummary.ErrorCount++ }
                        }
                    }
                }

                Disconnect-PnPOnline -ErrorAction SilentlyContinue
            }
            catch {
                Write-AuditLog "Failed to scan $($target.SiteUrl)/$($target.LibraryName): $($_.Exception.Message)" "ERROR"
                $scanSummary.ErrorCount++
                try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch {
                    Write-Verbose ("PnP Online disconnect after scanning {0}/{1} failed (non-fatal): {2}" -f $target.SiteUrl, $target.LibraryName, $_.Exception.Message)
                }
            }
        }
    }

    # Export results — always emit a CSV file (header-only when no findings) so downstream
    # automation and audit packaging can rely on the artifact existing.
    if ($allResults.Count -gt 0) {
        $allResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-AuditLog "Report exported to $OutputPath" "SUCCESS"
    }
    else {
        $headerOnly = [PSCustomObject]@{
            AgentName=''; KnowledgeSourceSite=''; LibraryName=''; ItemPath=''; ItemTitle='';
            SensitivityLabel=''; BroadPermission=''; PermissionType=''; AffectedUsers=''; RiskScore=''
        }
        @($headerOnly) | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        # Strip the placeholder row, keep only the header
        $csvLines = Get-Content -Path $OutputPath
        if ($csvLines.Count -ge 1) {
            Set-Content -Path $OutputPath -Value $csvLines[0] -Encoding UTF8
        }
        Write-AuditLog "No permission findings — wrote header-only CSV to $OutputPath ($($scanSummary.TotalItems) items scanned)" "SUCCESS"
    }

    # Summary
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      Scan Summary                        ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  Libraries scanned:   $($scanSummary.TotalLibraries)" -ForegroundColor White
    Write-Host "  Items scanned:       $($scanSummary.TotalItems)" -ForegroundColor White
    Write-Host "  CRITICAL findings:   $($scanSummary.CriticalCount)" -ForegroundColor $(if ($scanSummary.CriticalCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  HIGH findings:       $($scanSummary.HighCount)" -ForegroundColor $(if ($scanSummary.HighCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  MEDIUM findings:     $($scanSummary.MediumCount)" -ForegroundColor $(if ($scanSummary.MediumCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  LOW findings:        $($scanSummary.LowCount)" -ForegroundColor $(if ($scanSummary.LowCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Scan errors:         $($scanSummary.ErrorCount)" -ForegroundColor $(if ($scanSummary.ErrorCount -gt 0) { "Red" } else { "Green" })
    Write-Host ""

    # Return structured summary for pipeline consumption
    [PSCustomObject]@{
        CorrelationId  = $script:CorrelationId
        ScanDate       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        LibraryCount   = $scanSummary.TotalLibraries
        ItemCount      = $scanSummary.TotalItems
        CriticalCount  = $scanSummary.CriticalCount
        HighCount      = $scanSummary.HighCount
        MediumCount    = $scanSummary.MediumCount
        LowCount       = $scanSummary.LowCount
        ErrorCount     = $scanSummary.ErrorCount
        OutputFile     = $OutputPath
    }

    exit 0
}
catch {
    Write-AuditLog "Scan failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch {
        Write-Verbose ("Final PnP Online disconnect for knowledge source scan output {0} failed (non-fatal): {1}" -f $OutputPath, $_.Exception.Message)
    }
}

#endregion
