# MSAL.PS is required only for Interactive and legacy ServicePrincipal authentication.

<#
.SYNOPSIS
    Shared integration constants and translation functions for cross-solution governance integration.

.DESCRIPTION
    IntegrationConfig.psm1 provides canonical mappings, table configurations, and status translation
    functions used by Sync-SolutionAssessments.ps1 and Export-UnifiedComplianceEvidence.ps1.

    This module centralizes the data contract between the 6 Tier 2 governance solutions
    (ACV, SSC, AAM, CMM, FUS, CAA) and the Compliance Dashboard.

.NOTES
    Version: 2.0.3
    Date: 2026-05-22
    Solution: Cross-Solution Integration
#>

#region Constants

# Compliance Dashboard zone values (fsi_controlassessment.fsi_zone)
$script:ZoneValues = @{
    'Zone1' = 1
    'Zone2' = 2
    'Zone3' = 3
    'Unclassified' = 0
}

# Canonical severity values from the global option set fsi_acv_severity
# (defined in audit-compliance-manager/scripts/create_dataverse_schema.py).
# These integer values are the Dataverse-stored representation; they are
# normalized to dashboard status by ConvertTo-DashboardStatus.
$script:SeverityValues = @{
    'Passed'      = 100000000
    'Warning'     = 100000001
    'GracePeriod' = 100000002
    'Failed'      = 100000003
    'Error'       = 100000004
}

# Compliance Dashboard status values (fsi_status)
$script:DashboardStatus = @{
    'Compliant'     = 1
    'Partial'       = 2
    'NonCompliant'  = 3
    'NotApplicable' = 4
}

# Dashboard score values
$script:DashboardScores = @{
    1 = 100  # Compliant
    2 = 50   # Partial
    3 = 0    # Non-Compliant
}

# Evidence type for automated assessments
$script:EvidenceTypeTestResult = 5

# Zone value normalization. Tier 2 source tables store fsi_acv_zone option-set
# values (Unclassified=100000000, Zone1=100000001, ...). Compliance Dashboard
# assessments use their own fsi_zone choice values (Zone1=1, Zone2=2, Zone3=3).
# Map both conventions into the Compliance Dashboard 0/1/2/3 values for sync.
$script:ZoneNormalizationMap = @{
    100000000 = 0   # Unclassified
    100000001 = 1   # Zone1
    100000002 = 2   # Zone2
    100000003 = 3   # Zone3
    0         = 0
    1         = 1
    2         = 2
    3         = 3
}

# ACV environment registry uses the fsi_acv_zone option set, not the Compliance
# Dashboard fsi_zone values. Use this map when writing fsi_environmentregistry.
$script:AcvZoneOptionSetMap = @{
    0         = 100000000
    1         = 100000001
    2         = 100000002
    3         = 100000003
    100000000 = 100000000
    100000001 = 100000001
    100000002 = 100000002
    100000003 = 100000003
}

# ACV environment type option values (fsi_acv_environmenttype). The ELM
# request table uses a different option set, so 100000002/100000003 are
# translated from ELM Production/Developer into ACV Production/Developer.
# Legacy callers may pass 1=Production, 2=Sandbox, 3=Developer, 4=Trial,
# 5=Default to avoid ambiguity.
$script:AcvEnvironmentTypeMap = @{
    1         = 100000000  # Legacy Production -> ACV Production
    2         = 100000001  # Legacy Sandbox -> ACV Sandbox
    3         = 100000002  # Legacy Developer -> ACV Developer
    4         = 100000003  # Legacy Trial -> ACV Trial
    5         = 100000004  # Legacy Default -> ACV Default
    100000000 = 100000000  # ACV Production
    100000001 = 100000001  # ELM/ACV Sandbox
    100000002 = 100000000  # ELM Production -> ACV Production
    100000003 = 100000002  # ELM Developer -> ACV Developer
    100000004 = 100000004  # Default/fallback
}

#endregion

#region Authentication

function Connect-DataverseApi {
    <#
    .SYNOPSIS
        Authenticates to Dataverse and returns a connection hashtable.

    .PARAMETER Url
        The Dataverse environment URL.

    .PARAMETER TenantId
        The Microsoft Entra tenant ID.

    .PARAMETER ManagedIdentity
        Use system-assigned managed identity from an Azure-hosted worker.

    .PARAMETER ManagedIdentityClientId
        Optional user-assigned managed identity client ID.

    .PARAMETER ClientId
        App registration client ID for legacy service principal auth.

    .PARAMETER ClientSecret
        App registration client secret. Legacy dev-only fallback; use managed identity in production.

    .PARAMETER Interactive
        Use interactive (browser) authentication.

    .PARAMETER Cloud
        Sovereign cloud selector. Defaults to Public. Routes the OAuth authority
        and Dataverse base URL is taken from -Url (operators must supply the
        environment URL appropriate to the chosen cloud).

    .OUTPUTS
        Hashtable with BaseUrl and Headers for Dataverse API calls.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ManagedIdentity')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'PSScriptAnalyzer requires this rule suppression on the function param block; individual compatibility parameters carry specific justifications.'
    )]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
        [Parameter(ParameterSetName = 'Interactive', Mandatory)]
        [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
        [string]$TenantId,
        [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '',
            Justification = 'Required by the authentication parameter-set contract; the selected parameter set drives behavior in this implementation.'
        )]
        [switch]$ManagedIdentity,
        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [string]$ManagedIdentityClientId,
        [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
        [string]$ClientId,
        [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
        [SecureString]$ClientSecret,
        [Parameter(ParameterSetName = 'Interactive', Mandatory)]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '',
            Justification = 'Required by the authentication parameter-set contract; the selected parameter set drives behavior in this implementation.'
        )]
        [switch]$Interactive,
        [Parameter()]
        [ValidateSet('Public', 'USGov', 'USGovHigh', 'USGovDoD', 'China', 'Germany')]
        [string]$Cloud = 'Public'
    )

    $authorityHosts = @{
        'Public'    = 'https://login.microsoftonline.com'
        'USGov'     = 'https://login.microsoftonline.us'
        'USGovHigh' = 'https://login.microsoftonline.us'
        'USGovDoD'  = 'https://login.microsoftonline.us'
        'China'     = 'https://login.chinacloudapi.cn'
        'Germany'   = 'https://login.microsoftonline.de'
    }
    $authority = "$($authorityHosts[$Cloud])/$TenantId"
    $resource = $Url.TrimEnd('/')
    $scope = "$resource/.default"
    $accessToken = $null

    if ($PSCmdlet.ParameterSetName -eq 'ManagedIdentity') {
        Write-Verbose "Authenticating with managed identity to $Url (cloud=$Cloud)"
        $encodedResource = [System.Uri]::EscapeDataString($resource)
        if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
            $identityEndpoint = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$encodedResource"
            if ($ManagedIdentityClientId) {
                $identityEndpoint += "&client_id=$([System.Uri]::EscapeDataString($ManagedIdentityClientId))"
            }
            $miResponse = Invoke-RestMethod -Method Get -Uri $identityEndpoint -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER } -TimeoutSec 10
        } else {
            $identityEndpoint = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encodedResource"
            if ($ManagedIdentityClientId) {
                $identityEndpoint += "&client_id=$([System.Uri]::EscapeDataString($ManagedIdentityClientId))"
            }
            $miResponse = Invoke-RestMethod -Method Get -Uri $identityEndpoint -Headers @{ Metadata = 'true' } -TimeoutSec 10
        }
        $accessToken = $miResponse.access_token
    } elseif ($PSCmdlet.ParameterSetName -eq 'Interactive') {
        if (-not (Get-Command Get-MsalToken -ErrorAction SilentlyContinue)) {
            throw "MSAL.PS is required for interactive authentication. Install MSAL.PS or use -ManagedIdentity from Azure-hosted automation."
        }
        Write-Verbose "Authenticating interactively to $Url (cloud=$Cloud)"
        $interactiveClientId = if ($env:FSI_INT_InteractiveClientId) { $env:FSI_INT_InteractiveClientId } else { '51f81489-12ee-4a9e-aaae-a2591f45987d' }
        $token = Get-MsalToken -TenantId $TenantId -ClientId $interactiveClientId -Authority $authority -Scopes $scope -Interactive
        $accessToken = $token.AccessToken
    } else {
        if (-not (Get-Command Get-MsalToken -ErrorAction SilentlyContinue)) {
            throw "MSAL.PS is required for legacy service principal authentication. Install MSAL.PS or use -ManagedIdentity from Azure-hosted automation."
        }
        # legacy: dev-only — replace with managed identity in production
        Write-Verbose "Authenticating with legacy service principal secret to $Url (cloud=$Cloud)"
        $credential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
        $token = Get-MsalToken -TenantId $TenantId -ClientId $ClientId -Authority $authority -ClientCredential $credential -Scopes $scope
        $accessToken = $token.AccessToken
    }

    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw "Authentication failed: no access token was returned for $Url using parameter set '$($PSCmdlet.ParameterSetName)'."
    }

    return @{
        BaseUrl = "$resource/api/data/v9.2"
        Headers = @{
            'Authorization'    = "Bearer $accessToken"
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
            'Accept'           = 'application/json'
            'Content-Type'     = 'application/json'
            'Prefer'           = 'return=representation'
        }
    }
}

#endregion

#region Solution-to-Control Mapping

function Get-SolutionControlMapping {
    <#
    .SYNOPSIS
        Returns the mapping of solutions to their target control IDs.

    .DESCRIPTION
        Each Tier 2 solution feeds specific controls in the Compliance Dashboard.
        This function returns the canonical mapping.

    .OUTPUTS
        Hashtable with solution abbreviation as key and array of control IDs as value.

    .EXAMPLE
        $mapping = Get-SolutionControlMapping
        $mapping['ACV']  # Returns @('1.7')
    #>
    [CmdletBinding()]
    param()

    return @{
        'ACV' = @('1.7')
        'SSC' = @('1.23', '1.11')
        'AAM' = @('3.8')
        'CMM' = @('1.8')
        'FUS' = @('1.14')
        'CAA' = @('1.11', '1.23', '1.18')
    }
}

#endregion

#region Table Configuration

function Get-SolutionTableConfig {
    <#
    .SYNOPSIS
        Returns Dataverse table names and key columns for each Tier 2 solution.

    .DESCRIPTION
        Provides the entity set names, key fields, and query patterns needed to
        read validation history from each Tier 2 solution.

    .OUTPUTS
        Hashtable with solution abbreviation as key and configuration object as value.

    .EXAMPLE
        $config = Get-SolutionTableConfig
        $acv = $config['ACV']
        $acv.EntitySet       # 'fsi_auditvalidationhistories'
        $acv.StatusField     # 'fsi_severity'
    #>
    [CmdletBinding()]
    param()

    return @{
        'ACV' = @{
            EntitySet       = 'fsi_auditvalidationhistories'
            StatusField     = 'fsi_severity'
            StatusType      = 'Choice'          # Global option set fsi_acv_severity (100000000-based)
            TimestampField  = 'fsi_timestamp'
            RunIdField      = 'fsi_runid'
            ZoneField       = 'fsi_zone'
            FilterLatest    = "`$orderby=fsi_timestamp desc&`$top=1"
            SolutionName    = 'Audit Configuration Validator'
            SolutionVersion = 'v1.0.4'
        }
        'SSC' = @{
            EntitySet       = 'fsi_validationhistories'
            StatusField     = 'fsi_severity'
            StatusType      = 'Choice'          # Global option set fsi_acv_severity (100000000-based)
            TimestampField  = 'fsi_timestamp'
            RunIdField      = 'fsi_runid'
            ZoneField       = 'fsi_zone'
            FilterLatest    = "`$orderby=fsi_timestamp desc&`$top=1"
            SolutionName    = 'Session Security Configurator'
            SolutionVersion = 'v1.1.1'
        }
        'AAM' = @{
            # Explicit singular EntitySetName per AAM schema to avoid auto-plural
            EntitySet       = 'fsi_accessvalidationhistory'
            StatusField     = 'fsi_overallstatus'
            StatusType      = 'String'          # String: Compliant/Warning/NonCompliant/Critical
            TimestampField  = 'fsi_validationtime'
            RunIdField      = 'fsi_runid'
            ZoneField       = 'fsi_zone'
            FilterLatest    = "`$orderby=fsi_validationtime desc&`$top=1"
            SolutionName    = 'Agent Access Governance Monitor'
            SolutionVersion = 'v1.1.1'
        }
        'CMM' = @{
            # Explicit singular EntitySetName per CMM schema to avoid auto-plural
            EntitySet        = 'fsi_moderationvalidationhistory'
            StatusField      = 'fsi_overallstatus'
            StatusType       = 'Percentage'     # Derived from fsi_compliantcount / fsi_totalagents
            CompliantField   = 'fsi_compliantcount'
            TotalField       = 'fsi_totalagents'
            TimestampField   = 'fsi_validationtime'
            RunIdField       = 'fsi_runid'
            ZoneField        = 'fsi_zone'
            FilterLatest     = "`$orderby=fsi_validationtime desc&`$top=1"
            SolutionName     = 'Content Moderation Governance Monitor'
            SolutionVersion  = 'v1.1.1'
        }
        'FUS' = @{
            EntitySet        = 'fsi_fileuploadvalidationhistories'
            StatusField      = 'fsi_compliancerate'
            StatusType       = 'Percentage'     # Direct percentage field
            TimestampField   = 'fsi_validationtime'
            RunIdField       = 'fsi_runid'
            ZoneField        = 'fsi_zone'
            FilterLatest     = "`$orderby=fsi_validationtime desc&`$top=1"
            SolutionName     = 'File Upload Security Configurator'
            SolutionVersion  = 'v1.1.1'
        }
        'CAA' = @{
            EntitySet       = 'fsi_capolicyvalidationhistories'
            StatusField     = 'fsi_overallseverity'
            StatusType      = 'Choice'          # Global option set fsi_acv_severity (100000000-based)
            TimestampField  = 'fsi_validationtime'
            RunIdField      = 'fsi_runid'
            ZoneField       = 'fsi_zone'
            FilterLatest    = "`$orderby=fsi_validationtime desc&`$top=1"
            SolutionName    = 'Conditional Access Automation'
            SolutionVersion = 'v2.0.1'
        }
    }
}

#endregion

#region Status Translation

function ConvertTo-DashboardStatus {
    <#
    .SYNOPSIS
        Translates a Tier 2 solution's validation status to a Compliance Dashboard status value.

    .DESCRIPTION
        Each solution uses different status representations. This function normalizes them
        to the CD's fsi_status choice values (1=Compliant, 2=Partial, 3=Non-Compliant).

    .PARAMETER Solution
        The solution abbreviation: ACV, SSC, AAM, CMM, FUS, CAA.

    .PARAMETER Severity
        The solution's severity or status value (integer for Choice types, string for AAM).

    .PARAMETER ComplianceRate
        The compliance percentage (0-100) for CMM and FUS solutions.

    .PARAMETER TotalAgents
        Total agents scanned (used with CompliantCount for CMM).

    .PARAMETER CompliantCount
        Count of compliant agents (used with TotalAgents for CMM).

    .OUTPUTS
        Hashtable with Status (int), Score (int), and StatusLabel (string).

    .EXAMPLE
        ConvertTo-DashboardStatus -Solution 'ACV' -Severity 100000000
        # Returns @{ Status = 1; Score = 100; StatusLabel = 'Compliant' }

    .EXAMPLE
        ConvertTo-DashboardStatus -Solution 'CMM' -ComplianceRate 85
        # Returns @{ Status = 2; Score = 85; StatusLabel = 'Partial' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ACV', 'SSC', 'AAM', 'CMM', 'FUS', 'CAA')]
        [string]$Solution,

        [Parameter()]
        [object]$Severity,

        [Parameter()]
        [decimal]$ComplianceRate = -1,

        [Parameter()]
        [int]$TotalAgents = -1,

        [Parameter()]
        [int]$CompliantCount = -1
    )

    switch ($Solution) {
        { $_ -in 'ACV', 'SSC', 'CAA' } {
            # Choice-based severity stored as 100000000-based option set values
            # (global option set fsi_acv_severity).
            $sevInt = [int]$Severity
            switch ($sevInt) {
                100000000 { return @{ Status = 1; Score = 100; StatusLabel = 'Compliant' } }      # Passed
                100000001 { return @{ Status = 2; Score = 50;  StatusLabel = 'Partial' } }         # Warning
                100000002 { return @{ Status = 2; Score = 50;  StatusLabel = 'Partial' } }         # GracePeriod
                100000003 { return @{ Status = 3; Score = 0;   StatusLabel = 'Non-Compliant' } }   # Failed
                100000004 { return @{ Status = 3; Score = 0;   StatusLabel = 'Non-Compliant' } }   # Error
                default {
                    Write-Warning "Unknown severity value '$sevInt' for solution $Solution — defaulting to Non-Compliant"
                    return @{ Status = 3; Score = 0; StatusLabel = 'Non-Compliant' }
                }
            }
        }
        'AAM' {
            # String-based status
            $statusStr = [string]$Severity
            switch -Wildcard ($statusStr.ToLower()) {
                'compliant'    { return @{ Status = 1; Score = 100; StatusLabel = 'Compliant' } }
                'warning'      { return @{ Status = 2; Score = 50;  StatusLabel = 'Partial' } }
                'noncompliant' { return @{ Status = 3; Score = 0;   StatusLabel = 'Non-Compliant' } }
                'critical'     { return @{ Status = 3; Score = 0;   StatusLabel = 'Non-Compliant' } }
                default        { return @{ Status = 3; Score = 0;   StatusLabel = 'Non-Compliant' } }
            }
        }
        'CMM' {
            # Percentage-based (from compliant count / total agents)
            if ($TotalAgents -ge 0 -and $CompliantCount -ge 0) {
                if ($TotalAgents -eq 0) {
                    return @{ Status = 4; Score = $null; StatusLabel = 'Not Applicable' }
                }
                $ComplianceRate = ($CompliantCount / $TotalAgents) * 100
            }

            if ($ComplianceRate -lt 0) {
                return @{ Status = 3; Score = 0; StatusLabel = 'Non-Compliant' }
            }

            $score = [math]::Round($ComplianceRate)
            if ($ComplianceRate -ge 100) {
                return @{ Status = 1; Score = $score; StatusLabel = 'Compliant' }
            } elseif ($ComplianceRate -ge 80) {
                return @{ Status = 2; Score = $score; StatusLabel = 'Partial' }
            } else {
                return @{ Status = 3; Score = $score; StatusLabel = 'Non-Compliant' }
            }
        }
        'FUS' {
            # Direct compliance rate percentage
            if ($ComplianceRate -lt 0 -and $null -ne $Severity) {
                $ComplianceRate = [decimal]$Severity
            }

            if ($ComplianceRate -lt 0) {
                return @{ Status = 3; Score = 0; StatusLabel = 'Non-Compliant' }
            }

            $score = [math]::Round($ComplianceRate)
            if ($ComplianceRate -ge 100) {
                return @{ Status = 1; Score = $score; StatusLabel = 'Compliant' }
            } elseif ($ComplianceRate -ge 80) {
                return @{ Status = 2; Score = $score; StatusLabel = 'Partial' }
            } else {
                return @{ Status = 3; Score = $score; StatusLabel = 'Non-Compliant' }
            }
        }
    }
}

#endregion

#region Zone Normalization

function Get-CanonicalZoneValue {
    <#
    .SYNOPSIS
        Normalizes zone values to the Compliance Dashboard fsi_zone convention.

    .PARAMETER ZoneValue
        The zone value from any solution (may be 1, 2, 3 or 100000001, 100000002, 100000003).

    .OUTPUTS
        Integer — Compliance Dashboard zone value (1, 2, or 3). Returns 0 for unknown/unclassified.

    .EXAMPLE
        Get-CanonicalZoneValue -ZoneValue 100000002  # Returns 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ZoneValue
    )

    if ($script:ZoneNormalizationMap.ContainsKey($ZoneValue)) {
        return $script:ZoneNormalizationMap[$ZoneValue]
    }

    Write-Warning "Unknown zone value: $ZoneValue — returning 0 (Unclassified)"
    return 0
}

function ConvertTo-AcvZoneValue {
    <#
    .SYNOPSIS
        Converts a zone value to the ACV fsi_acv_zone option-set value.

    .PARAMETER ZoneValue
        Zone as Compliance Dashboard value (1/2/3) or ACV/ELM option-set value (100000001..100000003).

    .OUTPUTS
        Integer — ACV fsi_acv_zone option-set value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ZoneValue
    )

    if ($script:AcvZoneOptionSetMap.ContainsKey($ZoneValue)) {
        return $script:AcvZoneOptionSetMap[$ZoneValue]
    }

    Write-Warning "Unknown ACV zone value: $ZoneValue — returning 100000000 (Unclassified)"
    return 100000000
}

function ConvertTo-AcvEnvironmentTypeValue {
    <#
    .SYNOPSIS
        Converts environment type values to the ACV fsi_acv_environmenttype option-set value.

    .PARAMETER EnvironmentType
        Environment type value to convert.

    .PARAMETER Source
        Source value convention. Use LegacyOrElm for legacy small integers or ELM request option-set values; use Acv to pass through ACV option-set values.

    .OUTPUTS
        Integer — ACV fsi_acv_environmenttype option-set value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$EnvironmentType,

        [Parameter()]
        [ValidateSet('LegacyOrElm', 'Acv')]
        [string]$Source = 'LegacyOrElm'
    )

    if ($Source -eq 'Acv') {
        if (@(100000000, 100000001, 100000002, 100000003, 100000004) -contains $EnvironmentType) {
            return $EnvironmentType
        }
        throw "Invalid ACV environment type value: $EnvironmentType. Expected 100000000..100000004."
    }

    if ($script:AcvEnvironmentTypeMap.ContainsKey($EnvironmentType)) {
        return $script:AcvEnvironmentTypeMap[$EnvironmentType]
    }

    Write-Warning "Unknown ELM/legacy environment type: $EnvironmentType — returning 100000001 (Sandbox)"
    return 100000001
}

#endregion

#region UTC Time Helpers

function Get-IsoUtcTimestamp {
    <#
    .SYNOPSIS
        Returns the current UTC time as an ISO-8601 string with trailing Z.

    .DESCRIPTION
        Used by all sync/export scripts so that values written to Dataverse
        DateTime columns are unambiguously UTC. Wraps [DateTime]::UtcNow to
        avoid the local-time-with-literal-Z bug from
        (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ').

    .OUTPUTS
        String formatted as yyyy-MM-ddTHH:mm:ss.fffZ.
    #>
    [CmdletBinding()]
    param()

    return [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

function Get-IsoUtcDate {
    <#
    .SYNOPSIS
        Returns today's date in UTC as yyyy-MM-dd.

    .DESCRIPTION
        Used to build same-day OData filters that span midnight correctly.
        Local-time date can drift by one day around midnight UTC, causing
        duplicate-row creation and lost upserts.

    .OUTPUTS
        String formatted as yyyy-MM-dd (UTC calendar date).
    #>
    [CmdletBinding()]
    param()

    return [DateTime]::UtcNow.ToString('yyyy-MM-dd')
}

#endregion

#region Evidence Helpers

function Get-EvidenceTypeId {
    <#
    .SYNOPSIS
        Returns the Compliance Dashboard evidence type choice value for automated assessments.

    .OUTPUTS
        Integer — evidence type value (5 = Test Result).
    #>
    [CmdletBinding()]
    param()

    return $script:EvidenceTypeTestResult
}

function Get-EvidenceExportScripts {
    <#
    .SYNOPSIS
        Returns the evidence export script names per solution.

    .OUTPUTS
        Hashtable with solution abbreviation as key and script filename as value.
    #>
    [CmdletBinding()]
    param()

    return @{
        'ACV' = 'Export-AuditValidationEvidence.ps1'
        'SSC' = 'Export-SessionSecurityEvidence.ps1'
        'AAM' = 'Export-AgentAccessEvidence.ps1'
        'CMM' = 'Export-ContentModerationEvidence.ps1'
        'FUS' = 'Export-FileUploadEvidence.ps1'
        'CAA' = 'Export-CAAComplianceEvidence.ps1'
    }
}

function Get-SolutionDirectories {
    <#
    .SYNOPSIS
        Returns the solution directory names in FSI-AgentGov-Solutions per solution.

    .OUTPUTS
        Hashtable with solution abbreviation and directory name.
    #>
    [CmdletBinding()]
    param()

    return @{
        'ACV' = 'audit-compliance-manager'
        'SSC' = 'session-security-configurator'
        'AAM' = 'agent-access-monitor'
        'CMM' = 'content-moderation-monitor'
        'FUS' = 'file-upload-security'
        'CAA' = 'conditional-access-automation'
        'ELM' = 'environment-lifecycle-management'
        'CD'  = 'compliance-dashboard'
        'INT' = 'cross-solution-integration'
    }
}

#endregion

#region Dashboard Entity Sets

function Get-DashboardTableConfig {
    <#
    .SYNOPSIS
        Returns Compliance Dashboard table configuration for assessment and evidence operations.

    .OUTPUTS
        Hashtable with table names and key fields.
    #>
    [CmdletBinding()]
    param()

    return @{
        ControlMaster = @{
            EntitySet  = 'fsi_controlmasters'
            KeyField   = 'fsi_controlid'
            GuidField  = 'fsi_controlmasterid'
        }
        Assessment = @{
            EntitySet  = 'fsi_controlassessments'
            KeyField   = 'fsi_controlassessmentid'
            StatusField = 'fsi_status'
            ScoreField  = 'fsi_score'
            DateField   = 'fsi_assessmentdate'
            NotesField  = 'fsi_notes'
            ZoneField   = 'fsi_zone'
        }
        Evidence = @{
            EntitySet  = 'fsi_complianceevidences'
            KeyField   = 'fsi_complianceevidenceid'
            TypeField  = 'fsi_evidencetype'
            HashField  = 'fsi_hash'
            DateField  = 'fsi_collecteddate'
        }
        Score = @{
            EntitySet  = 'fsi_compliancescores'
        }
    }
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    'Connect-DataverseApi'
    'Get-SolutionControlMapping'
    'Get-SolutionTableConfig'
    'ConvertTo-DashboardStatus'
    'Get-CanonicalZoneValue'
    'ConvertTo-AcvZoneValue'
    'ConvertTo-AcvEnvironmentTypeValue'
    'Get-EvidenceTypeId'
    'Get-EvidenceExportScripts'
    'Get-SolutionDirectories'
    'Get-DashboardTableConfig'
    'Get-IsoUtcTimestamp'
    'Get-IsoUtcDate'
)
