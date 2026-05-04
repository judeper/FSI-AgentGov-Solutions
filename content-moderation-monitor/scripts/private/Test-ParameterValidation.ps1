<#
.SYNOPSIS
    Parameter validation helpers for CMM scripts.

.DESCRIPTION
    Provides validation functions for common CMM script parameters.

.NOTES
    File: Test-ParameterValidation.ps1
    Version: 0.1.0
#>

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

function Test-ModerationLevel {
    <#
    .SYNOPSIS
        Validates and normalizes a content moderation level.

    .DESCRIPTION
        Accepts various representations of moderation levels and normalizes
        them to canonical values: Low, Medium, High. Copilot Studio labels
        Lowest and Highest are mapped to Low and High. Returns 'Unknown' for
        unrecognized values.

    .PARAMETER Level
        The moderation level string to validate.

    .OUTPUTS
        String - One of: Low, Medium, High, Unknown
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Level
    )

    if ([string]::IsNullOrWhiteSpace($Level)) {
        return 'Unknown'
    }

    $normalized = $Level.Trim().ToLower()

    $levelMap = @{
        'lowest'   = 'Low'
        'low'      = 'Low'
        'medium'   = 'Medium'
        'high'     = 'High'
        'highest'  = 'High'
        'strict'   = 'High'
        'none'     = 'Low'
        'standard' = 'Medium'
        'off'      = 'Low'
        'moderate' = 'Medium'
    }

    if ($levelMap.ContainsKey($normalized)) {
        return $levelMap[$normalized]
    }

    Write-Warning "Unrecognized moderation level: '$Level'. Returning 'Unknown'."
    return 'Unknown'
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
