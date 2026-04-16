<#
.SYNOPSIS
    Enumerates item-level permissions in agent knowledge source SharePoint libraries.

.DESCRIPTION
    Scans SharePoint document libraries connected to Copilot Studio agents as
    knowledge sources and identifies files with overshared permissions.

    Key capabilities:
    - Enumerates all items in agent-connected SharePoint libraries
    - Detects items with permissions broader than the agent's intended user group
    - Cross-references sensitivity labels to identify high-risk oversharing
    - Produces a risk-scored CSV report for compliance review

    Risk scoring (agent knowledge source context — stricter than general SharePoint):
    - CRITICAL: High-sensitivity label AND accessible outside agent user group
    - HIGH: Anyone link OR external user on any knowledge source item
    - MEDIUM: Org-wide link with Edit access on a knowledge source item
    - LOW: Item accessible to a broader internal group than agent's target audience

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

.PARAMETER ConfigPath
    Path to the item-scope-config.json configuration file.
    Defaults to ../templates/item-scope-config.sample.json relative to script.

.PARAMETER MaxItemsPerLibrary
    Maximum number of items to scan per library. Defaults to 10000.
    Override with config file or this parameter.

.PARAMETER OutputPath
    Path for the output CSV report. Defaults to ./output/item-permissions-report.csv.

.PARAMETER IncludeCompliant
    When specified, includes compliant (no-risk) items in the output report.
    By default, only items with identified risks are included.

.EXAMPLE
    .\Get-KnowledgeSourceItemPermissions.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/AgentKB" -LibraryName "Documents" -AgentName "HR-Agent" -AgentUserGroupId "00000000-0000-0000-0000-000000000001"

    Scans a single library for the HR Agent's knowledge source.

.EXAMPLE
    .\Get-KnowledgeSourceItemPermissions.ps1 -LibraryList "./output/agent-knowledge-sources.csv" -AgentUserGroupId "00000000-0000-0000-0000-000000000001" -OutputPath "./output/item-risk-report.csv"

    Scans all libraries from a prior knowledge source scan output.

.EXAMPLE
    .\Get-KnowledgeSourceItemPermissions.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/AgentKB" -AgentUserGroupMembers @("user1@contoso.com","user2@contoso.com") -WhatIf

    Dry-run scan showing what would be checked without making changes.

.OUTPUTS
    CSV file with columns: AgentName, KnowledgeSourceSite, LibraryName,
    ItemPath, ItemTitle, SensitivityLabel, BroadPermission, PermissionType,
    AffectedUsers, RiskScore

.NOTES
    Version:    1.0.1
    Author:     FSI Agent Governance
    Requires:   PnP.PowerShell 2.5.0+
    Requires:   PowerShell 7.0+
    Framework:  FSI Agent Governance
    Controls:   4.3, 1.4, 1.5
#>

#Requires -Version 7.0
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
    [ValidatePattern('^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$')]
    [string]$AgentUserGroupId,

    [Parameter(Mandatory = $false)]
    [string[]]$AgentUserGroupMembers,

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
            $groupMembers = Get-PnPEntraIDGroupMember -Identity $GroupId
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
        [bool]$OutsideAgentScope
    )

    # CRITICAL: High-sensitivity label AND accessible outside agent user group
    if ($SensitivityTier -in @("CRITICAL", "HIGH") -and $OutsideAgentScope) {
        return "CRITICAL"
    }

    # HIGH: AnyoneLink OR ExternalUser on any knowledge source item
    if ($PermissionType -in @("AnonymousLink", "ExternalUser", "GuestUser")) {
        return "HIGH"
    }

    # MEDIUM: Org-wide link with Edit access
    if ($PermissionType -eq "OrganizationLink") {
        return "MEDIUM"
    }

    # LOW: Item accessible to broader internal group than agent's target
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
                $permissionType = "EveryoneExceptExternal"
                $affectedUsers = "Everyone except external users"
            }

            # Check if outside agent scope
            $outsideScope = $false
            if ($AgentUserScope.Count -gt 0) {
                if ($permissionType -in @("AnonymousLink", "OrganizationLink", "EveryoneExceptExternal")) {
                    $outsideScope = $true
                }
                elseif ($permissionType -eq "DirectPermission" -and $member.PrincipalType -eq "User") {
                    $upn = $memberLoginName -replace "^i:0#\.f\|membership\|", ""
                    if (-not $AgentUserScope.Contains($upn)) {
                        $outsideScope = $true
                    }
                }
                elseif ($permissionType -in @("ExternalUser", "GuestUser")) {
                    $outsideScope = $true
                }
            }

            $riskScore = Get-ItemRiskScore -PermissionType $permissionType `
                -SensitivityTier $sensitivityTier `
                -OutsideAgentScope $outsideScope

            # Determine the permission level (Read, Edit, Full Control, etc.)
            $permLevels = @()
            foreach ($roleDef in $roleAssignment.RoleDefinitionBindings) {
                $permLevels += $roleDef.Name
            }
            $broadPermission = $permLevels -join ", "

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
    Write-Host "║   FSI Agent Governance Framework v1.0.1                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Load configuration
    $configFilePath = $ConfigPath
    if (-not $configFilePath) {
        $configFilePath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" "item-scope-config.sample.json"
    }
    $config = Get-ScanConfig -Path $configFilePath

    if ($MaxItemsPerLibrary -ne 10000) {
        $config.maxItemsPerLibrary = $MaxItemsPerLibrary
    }

    # Resolve scan targets
    $targets = Get-LibraryTargets -SiteUrls $SiteUrl -DefaultLibraryName $LibraryName `
        -DefaultAgentName $AgentName -ListPath $LibraryList

    Write-AuditLog "Scan targets: $($targets.Count) libraries"

    # Resolve agent user scope
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
                Connect-PnPOnline -Url $target.SiteUrl -Interactive -ErrorAction Stop
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
                    Get-PnPProperty -ClientObject $item -Property "HasUniqueRoleAssignments" | Out-Null

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
                try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch { }
            }
        }
    }

    # Export results
    if ($allResults.Count -gt 0) {
        $allResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-AuditLog "Report exported to $OutputPath" "SUCCESS"
    }
    else {
        Write-AuditLog "No permission issues found across $($scanSummary.TotalItems) items" "SUCCESS"
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
    try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch { }
}

#endregion
