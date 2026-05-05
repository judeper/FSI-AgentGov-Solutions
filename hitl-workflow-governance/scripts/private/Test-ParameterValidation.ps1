<#
.SYNOPSIS
    Parameter validation helpers for HWG scripts.

.DESCRIPTION
    Provides validation functions for common HWG script parameters including
    environment filters, output formats, HITL checkpoint types, action categories,
    and Dataverse connection settings.

.NOTES
    File: Test-ParameterValidation.ps1
    Version: 1.0.0
    Requires: PowerShell 7.0+
#>

#requires -Version 7.0

function Test-EnvironmentFilter {
    <#
    .SYNOPSIS
        Validates environment filter parameters.

    .PARAMETER IncludeEnvironments
        Array of environment IDs or names to include.

    .PARAMETER ExcludeEnvironments
        Array of environment IDs or names to exclude.

    .PARAMETER ExcludeSandbox
        Whether to exclude Sandbox environments.

    .PARAMETER ExcludeDefault
        Whether to exclude Default environment.

    .PARAMETER ExcludeTrial
        Whether to exclude Trial environments.

    .PARAMETER GracePeriodHours
        Hours to exclude newly created environments.

    .OUTPUTS
        PSCustomObject with validated filter configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$IncludeEnvironments,

        [Parameter()]
        [string[]]$ExcludeEnvironments,

        [Parameter()]
        [switch]$ExcludeSandbox,

        [Parameter()]
        [switch]$ExcludeDefault,

        [Parameter()]
        [switch]$ExcludeTrial,

        [Parameter()]
        [int]$GracePeriodHours = 48
    )

    # Mutual exclusivity check
    if ($IncludeEnvironments -and $ExcludeEnvironments) {
        throw "IncludeEnvironments and ExcludeEnvironments are mutually exclusive. Use one or the other."
    }

    # Grace period validation
    if ($GracePeriodHours -lt 0 -or $GracePeriodHours -gt 168) {
        throw "GracePeriodHours must be between 0 and 168 (1 week). Got: $GracePeriodHours"
    }

    # Calculate grace cutoff time
    $graceCutoff = if ($GracePeriodHours -gt 0) {
        (Get-Date).AddHours(-$GracePeriodHours)
    } else {
        $null
    }

    [PSCustomObject]@{
        IncludeEnvironments = $IncludeEnvironments
        ExcludeEnvironments = $ExcludeEnvironments
        ExcludeSandbox      = $ExcludeSandbox.IsPresent
        ExcludeDefault      = $ExcludeDefault.IsPresent
        ExcludeTrial        = $ExcludeTrial.IsPresent
        GracePeriodHours    = $GracePeriodHours
        GraceCutoff         = $graceCutoff
        FilterMode          = if ($IncludeEnvironments) { 'Include' }
                              elseif ($ExcludeEnvironments) { 'Exclude' }
                              else { 'TypeFilter' }
    }
}

function Test-OutputFormat {
    <#
    .SYNOPSIS
        Validates output format parameter.

    .PARAMETER Format
        Output format: Table, JSON, or Object.

    .OUTPUTS
        PSCustomObject with format settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Table', 'JSON', 'Object')]
        [string]$Format = 'Table'
    )

    [PSCustomObject]@{
        Format         = $Format
        IsInteractive  = $Format -eq 'Table'
        IsPipeline     = $Format -eq 'Object'
        IsSerializable = $Format -eq 'JSON'
    }
}

function Test-CheckpointType {
    <#
    .SYNOPSIS
        Validates and normalizes a HITL checkpoint type string.

    .DESCRIPTION
        Accepts various representations of HITL checkpoint types and normalizes them
        to canonical values. Returns 'Unknown' for unrecognized values.

        Canonical values:
        - RequestForInformation
        - MultistageApproval
        - CustomHitl
        - AdvancedApprovalsGeneric
        - NotApplicable

    .PARAMETER CheckpointType
        The checkpoint type string to validate.

    .OUTPUTS
        String - One of the canonical checkpoint type values, or 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CheckpointType
    )

    if ([string]::IsNullOrWhiteSpace($CheckpointType)) {
        return 'Unknown'
    }

    $normalized = $CheckpointType.Trim().ToLower() -replace '[\s_-]+', ''

    $typeMap = @{
        'requestforinformation'  = 'RequestForInformation'
        'rfi'                    = 'RequestForInformation'
        'informationrequest'     = 'RequestForInformation'
        'multistageapproval'     = 'MultistageApproval'
        'runmultistageapproval'  = 'MultistageApproval'
        'runamultistageapproval' = 'MultistageApproval'
        'startandwaitforanapprovalprocess' = 'MultistageApproval'
        'approval'               = 'MultistageApproval'
        'approvalflow'           = 'MultistageApproval'
        'manualreview'           = 'CustomHitl'
        'review'                 = 'CustomHitl'
        'humanreview'            = 'CustomHitl'
        'customhitl'             = 'CustomHitl'
        'custom'                 = 'CustomHitl'
        'advancedapprovalsgeneric' = 'AdvancedApprovalsGeneric'
        'advancedapprovals'      = 'AdvancedApprovalsGeneric'
        'notapplicable'          = 'NotApplicable'
        'na'                     = 'NotApplicable'
    }

    if ($typeMap.ContainsKey($normalized)) {
        return $typeMap[$normalized]
    }

    Write-Warning "Unrecognized checkpoint type: '$CheckpointType'. Returning 'Unknown'."
    return 'Unknown'
}

function Test-ActionCategory {
    <#
    .SYNOPSIS
        Validates and normalizes an action category string.

    .DESCRIPTION
        Accepts various representations of action categories and normalizes them
        to canonical values used in HITL policy evaluation.

        Canonical values:
        - Write
        - Financial
        - ExternalSharing
        - PiiProcessing
        - CustomerFacing
        - InternalReadOnly

    .PARAMETER Category
        The action category string to validate.

    .OUTPUTS
        String - One of the canonical action category values, or 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Category
    )

    if ([string]::IsNullOrWhiteSpace($Category)) {
        return 'Unknown'
    }

    $normalized = $Category.Trim().ToLower() -replace '[\s_-]+', ''

    $categoryMap = @{
        'write'            = 'Write'
        'create'           = 'Write'
        'update'           = 'Write'
        'delete'           = 'Write'
        'modify'           = 'Write'
        'financial'        = 'Financial'
        'payment'          = 'Financial'
        'transaction'      = 'Financial'
        'billing'          = 'Financial'
        'externalsharing'  = 'ExternalSharing'
        'external'         = 'ExternalSharing'
        'sharing'          = 'ExternalSharing'
        'export'           = 'ExternalSharing'
        'piiprocessing'    = 'PiiProcessing'
        'pii'              = 'PiiProcessing'
        'personaldata'     = 'PiiProcessing'
        'customerfacing'   = 'CustomerFacing'
        'customer'         = 'CustomerFacing'
        'clientfacing'     = 'CustomerFacing'
        'internalreadonly'  = 'InternalReadOnly'
        'internal'         = 'InternalReadOnly'
        'readonly'         = 'InternalReadOnly'
        'read'             = 'InternalReadOnly'
    }

    if ($categoryMap.ContainsKey($normalized)) {
        return $categoryMap[$normalized]
    }

    Write-Warning "Unrecognized action category: '$Category'. Returning 'Unknown'."
    return 'Unknown'
}

function Test-CheckpointStatus {
    <#
    .SYNOPSIS
        Validates and normalizes a checkpoint status string.

    .DESCRIPTION
        Accepts various representations of checkpoint statuses and normalizes
        them to canonical values: Present, Missing, Partial, UnableToDetermine.
        Returns 'UnableToDetermine' for unrecognized values.

    .PARAMETER Status
        The checkpoint status string to validate.

    .OUTPUTS
        String - One of: Present, Missing, Partial, UnableToDetermine
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Status
    )

    if ([string]::IsNullOrWhiteSpace($Status)) {
        return 'UnableToDetermine'
    }

    $normalized = $Status.Trim().ToLower()

    $statusMap = @{
        'present'             = 'Present'
        'configured'          = 'Present'
        'enabled'             = 'Present'
        'yes'                 = 'Present'
        'true'                = 'Present'
        'missing'             = 'Missing'
        'absent'              = 'Missing'
        'disabled'            = 'Missing'
        'no'                  = 'Missing'
        'false'               = 'Missing'
        'none'                = 'Missing'
        'partial'             = 'Partial'
        'incomplete'          = 'Partial'
        'some'                = 'Partial'
        'unabletodetermine'   = 'UnableToDetermine'
        'unable to determine' = 'UnableToDetermine'
        'unknown'             = 'UnableToDetermine'
        'undetermined'        = 'UnableToDetermine'
    }

    if ($statusMap.ContainsKey($normalized)) {
        return $statusMap[$normalized]
    }

    Write-Warning "Unrecognized checkpoint status: '$Status'. Returning 'UnableToDetermine'."
    return 'UnableToDetermine'
}

function Test-DataverseConnection {
    <#
    .SYNOPSIS
        Validates Dataverse connection parameters.

    .PARAMETER DataverseUrl
        Dataverse environment URL.

    .PARAMETER RequireConnection
        Whether connection is required.

    .OUTPUTS
        PSCustomObject with connection settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [switch]$RequireConnection
    )

    $isConfigured = -not [string]::IsNullOrWhiteSpace($DataverseUrl)

    if ($RequireConnection -and -not $isConfigured) {
        throw "DataverseUrl is required for this operation."
    }

    # Validate URL format if provided
    if ($isConfigured) {
        if (-not ($DataverseUrl -match '^https://.*\.crm.*\.dynamics\.com/?$')) {
            Write-Warning "DataverseUrl format may be incorrect. Expected: https://org.crm.dynamics.com"
        }
    }

    [PSCustomObject]@{
        DataverseUrl  = $DataverseUrl
        IsConfigured  = $isConfigured
        NormalizedUrl = if ($isConfigured) { $DataverseUrl.TrimEnd('/') } else { $null }
    }
}

function Test-ZoneFilter {
    <#
    .SYNOPSIS
        Validates a zone filter value.

    .DESCRIPTION
        Accepts a zone string and validates it against the known set of governance zones.
        Returns the validated zone or throws on invalid input.

    .PARAMETER Zone
        The zone string to validate.

    .PARAMETER AllowEmpty
        When specified, allows null/empty values (returns $null).

    .OUTPUTS
        String - Validated zone value, or $null if AllowEmpty and input is empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Zone,

        [Parameter()]
        [switch]$AllowEmpty
    )

    if ([string]::IsNullOrWhiteSpace($Zone)) {
        if ($AllowEmpty) { return $null }
        throw "Zone parameter is required."
    }

    $validZones = @('Zone1', 'Zone2', 'Zone3', 'Unknown')
    if ($Zone -notin $validZones) {
        throw "Invalid zone: '$Zone'. Valid values: $($validZones -join ', ')"
    }

    return $Zone
}

function Test-GuidParameter {
    <#
    .SYNOPSIS
        Validates a GUID format parameter.

    .PARAMETER Value
        The string value to validate as a GUID.

    .PARAMETER ParameterName
        Name of the parameter (used in error messages).

    .PARAMETER AllowEmpty
        When specified, allows null/empty values.

    .OUTPUTS
        String - Validated GUID string, or $null if AllowEmpty and input is empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter()]
        [string]$ParameterName = 'Value',

        [Parameter()]
        [switch]$AllowEmpty
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ($AllowEmpty) { return $null }
        throw "$ParameterName is required."
    }

    $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    if ($Value -notmatch $guidPattern) {
        throw "$ParameterName '$Value' is not a valid GUID format. Expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    }

    return $Value
}
