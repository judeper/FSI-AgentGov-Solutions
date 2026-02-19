<#
.SYNOPSIS
    Parameter validation helpers for FUS scripts.

.DESCRIPTION
    Provides validation functions for common File Upload Security script parameters.

.NOTES
    File: Test-ParameterValidation.ps1
    Version: 0.1.0
    Solution: File Upload Security Configurator (v8)
#>

function Test-EnvironmentFilter {
    <#
    .SYNOPSIS
        Validates environment filter parameters.
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
        [int]$GracePeriodHours = 24
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
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Table', 'JSON', 'CSV', 'Object')]
        [string]$Format = 'Table'
    )

    [PSCustomObject]@{
        Format         = $Format
        IsInteractive  = $Format -eq 'Table'
        IsPipeline     = $Format -eq 'Object'
        IsSerializable = $Format -eq 'JSON' -or $Format -eq 'CSV'
    }
}

function Test-FileUploadStatus {
    <#
    .SYNOPSIS
        Validates and normalizes a file upload enabled status value.

    .DESCRIPTION
        Accepts various representations of file upload status and normalizes
        to boolean True/False. Returns $null for unrecognized values.

    .PARAMETER Status
        The file upload status value to validate.

    .OUTPUTS
        Boolean - $true (enabled), $false (disabled), or $null (unknown)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        $Status
    )

    if ($null -eq $Status) {
        return $null
    }

    if ($Status -is [bool]) {
        return $Status
    }

    if ($Status -is [string]) {
        $normalized = $Status.Trim().ToLower()

        $enabledValues = @('true', 'yes', 'enabled', '1', 'on')
        $disabledValues = @('false', 'no', 'disabled', '0', 'off')

        if ($enabledValues -contains $normalized) { return $true }
        if ($disabledValues -contains $normalized) { return $false }
    }

    if ($Status -is [int]) {
        if ($Status -eq 1) { return $true }
        if ($Status -eq 0) { return $false }
    }

    Write-Warning "Unrecognized file upload status: '$Status'. Returning `$null."
    return $null
}

function Test-DataverseConnection {
    <#
    .SYNOPSIS
        Validates Dataverse connection parameters.
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
