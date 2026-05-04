<#
.SYNOPSIS
    Parameter validation helpers for ACRD scripts.

.DESCRIPTION
    Provides validation functions for common ACRD script parameters including
    environment filters, output formats, communication violation types,
    communication routes, and Dataverse connection settings.

.NOTES
    File: Test-ParameterValidation.ps1
    Version: 1.1.0
    Requires: Windows PowerShell 5.1+
#>

#Requires -Version 5.1

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

function Test-ViolationType {
    <#
    .SYNOPSIS
        Validates and normalizes an ACRD violation type string.

    .DESCRIPTION
        Accepts various representations of communication violation types and normalizes
        them to canonical values. Returns 'Unknown' for unrecognized values.

        Canonical values:
        - ZONE_BOUNDARY_VIOLATION
        - CROSS_TENANT_VIOLATION
        - CROSS_ENVIRONMENT_UNAPPROVED
        - MAKER_CHECKER_VIOLATION

    .PARAMETER ViolationType
        The violation type string to validate.

    .OUTPUTS
        String - One of the canonical violation type values, or 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ViolationType
    )

    if ([string]::IsNullOrWhiteSpace($ViolationType)) {
        return 'Unknown'
    }

    $normalized = $ViolationType.Trim().ToUpper()

    # Map various representations to canonical values
    $violationMap = @{
        'ZONE_BOUNDARY_VIOLATION'      = 'ZONE_BOUNDARY_VIOLATION'
        'ZONEBOUNDARY'                 = 'ZONE_BOUNDARY_VIOLATION'
        'ZONE_BOUNDARY'                = 'ZONE_BOUNDARY_VIOLATION'
        'BOUNDARY'                     = 'ZONE_BOUNDARY_VIOLATION'
        'CROSS_TENANT_VIOLATION'       = 'CROSS_TENANT_VIOLATION'
        'CROSSTENANT'                  = 'CROSS_TENANT_VIOLATION'
        'CROSS_TENANT'                 = 'CROSS_TENANT_VIOLATION'
        'TENANT'                       = 'CROSS_TENANT_VIOLATION'
        'CROSS_ENVIRONMENT_UNAPPROVED' = 'CROSS_ENVIRONMENT_UNAPPROVED'
        'CROSSENVIRONMENT'             = 'CROSS_ENVIRONMENT_UNAPPROVED'
        'CROSS_ENVIRONMENT'            = 'CROSS_ENVIRONMENT_UNAPPROVED'
        'CROSS_ENV'                    = 'CROSS_ENVIRONMENT_UNAPPROVED'
        'MAKER_CHECKER_VIOLATION'      = 'MAKER_CHECKER_VIOLATION'
        'MAKERCHECKER'                 = 'MAKER_CHECKER_VIOLATION'
        'MAKER_CHECKER'                = 'MAKER_CHECKER_VIOLATION'
    }

    if ($violationMap.ContainsKey($normalized)) {
        return $violationMap[$normalized]
    }

    Write-Warning "Unrecognized violation type: '$ViolationType'. Returning 'Unknown'."
    return 'Unknown'
}

function Test-CommunicationRoute {
    <#
    .SYNOPSIS
        Validates a zone-to-zone communication route specification.

    .DESCRIPTION
        Checks that source and target zones are valid governance zones and that
        the direction type is recognized. Returns a normalized route object.

    .PARAMETER SourceZone
        The source governance zone (Zone1, Zone2, Zone3).

    .PARAMETER TargetZone
        The target governance zone (Zone1, Zone2, Zone3).

    .PARAMETER DirectionType
        The communication direction: OneWay or Bidirectional.

    .OUTPUTS
        PSCustomObject with normalized route specification and route classification.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceZone,

        [Parameter(Mandatory)]
        [string]$TargetZone,

        [Parameter()]
        [ValidateSet('OneWay', 'Bidirectional')]
        [string]$DirectionType = 'OneWay'
    )

    $validZones = @('Zone1', 'Zone2', 'Zone3', 'Unknown')

    if ($SourceZone -notin $validZones) {
        throw "Invalid SourceZone '$SourceZone'. Valid values: $($validZones -join ', ')"
    }

    if ($TargetZone -notin $validZones) {
        throw "Invalid TargetZone '$TargetZone'. Valid values: $($validZones -join ', ')"
    }

    # Determine route classification
    $zoneRank = @{ 'Zone1' = 1; 'Zone2' = 2; 'Zone3' = 3; 'Unknown' = 0 }
    $sourceRank = $zoneRank[$SourceZone]
    $targetRank = $zoneRank[$TargetZone]

    $routeType = if ($SourceZone -eq $TargetZone) {
        'SameZone'
    } elseif ($sourceRank -gt $targetRank) {
        'HigherToLower'
    } elseif ($sourceRank -lt $targetRank) {
        'LowerToHigher'
    } else {
        'CrossZone'
    }

    [PSCustomObject]@{
        SourceZone    = $SourceZone
        TargetZone    = $TargetZone
        DirectionType = $DirectionType
        RouteType     = $routeType
        SourceRank    = $sourceRank
        TargetRank    = $targetRank
        IsCrossZone   = $SourceZone -ne $TargetZone
    }
}
