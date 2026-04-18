<#
.SYNOPSIS
    Parameter validation helpers for ACA scripts.

.DESCRIPTION
    Provides validation functions for common ACA script parameters including
    environment filters, output formats, action types, confirmation statuses,
    and Dataverse connection settings.

.NOTES
    File: Test-ParameterValidation.ps1
    Version: 1.1.0
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

function Test-ActionType {
    <#
    .SYNOPSIS
        Validates and normalizes an action type string.

    .DESCRIPTION
        Accepts various representations of action types and normalizes them to
        canonical values. Returns 'Unknown' for unrecognized values.

        Canonical values:
        - ConnectorAction
        - CloudFlowAction
        - PluginAction
        - CustomAction
        - HttpRequest

    .PARAMETER ActionType
        The action type string to validate.

    .OUTPUTS
        String - One of the canonical action type values, or 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ActionType
    )

    if ([string]::IsNullOrWhiteSpace($ActionType)) {
        return 'Unknown'
    }

    $normalized = $ActionType.Trim().ToLower()

    # Map various representations to canonical values
    $actionMap = @{
        'connectoraction'  = 'ConnectorAction'
        'connector'        = 'ConnectorAction'
        'connectoractions' = 'ConnectorAction'
        'cloudflowaction'  = 'CloudFlowAction'
        'cloudflow'        = 'CloudFlowAction'
        'flow'             = 'CloudFlowAction'
        'flowaction'       = 'CloudFlowAction'
        'pluginaction'     = 'PluginAction'
        'plugin'           = 'PluginAction'
        'plugins'          = 'PluginAction'
        'customaction'     = 'CustomAction'
        'custom'           = 'CustomAction'
        'customapi'        = 'CustomAction'
        'httprequest'      = 'HttpRequest'
        'http'             = 'HttpRequest'
        'httpaction'       = 'HttpRequest'
        'webrequest'       = 'HttpRequest'
    }

    if ($actionMap.ContainsKey($normalized)) {
        return $actionMap[$normalized]
    }

    Write-Warning "Unrecognized action type: '$ActionType'. Returning 'Unknown'."
    return 'Unknown'
}

function Test-ConfirmationStatus {
    <#
    .SYNOPSIS
        Validates and normalizes a confirmation status string.

    .DESCRIPTION
        Accepts various representations of confirmation statuses and normalizes
        them to canonical values: Present, Missing, Partial, UnableToDetermine.
        Returns 'UnableToDetermine' for unrecognized values.

    .PARAMETER Status
        The confirmation status string to validate.

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
        'present'            = 'Present'
        'confirmed'          = 'Present'
        'enabled'            = 'Present'
        'yes'                = 'Present'
        'true'               = 'Present'
        'missing'            = 'Missing'
        'absent'             = 'Missing'
        'disabled'           = 'Missing'
        'no'                 = 'Missing'
        'false'              = 'Missing'
        'none'               = 'Missing'
        'partial'            = 'Partial'
        'incomplete'         = 'Partial'
        'some'               = 'Partial'
        'unabletodetermine'  = 'UnableToDetermine'
        'unable to determine' = 'UnableToDetermine'
        'unknown'            = 'UnableToDetermine'
        'undetermined'       = 'UnableToDetermine'
    }

    if ($statusMap.ContainsKey($normalized)) {
        return $statusMap[$normalized]
    }

    Write-Warning "Unrecognized confirmation status: '$Status'. Returning 'UnableToDetermine'."
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
