<#
.SYNOPSIS
    Parameter validation helpers for GAC scripts.

.DESCRIPTION
    Provides validation functions for common GAC script parameters including
    environment filters, output formats, generative AI feature types,
    orchestration modes, and Dataverse connection settings.

.NOTES
    File: Test-ParameterValidation.ps1
    Version: 1.0.0
    Requires: PowerShell 7.0+
#>

#Requires -Version 7.4

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

function Test-GenAIFeatureType {
    <#
    .SYNOPSIS
        Validates and normalizes a generative AI feature type string.

    .DESCRIPTION
        Accepts various representations of generative AI feature types and normalizes
        them to canonical values. Returns 'Unknown' for unrecognized values.

        Canonical values:
        - AzureOpenAIIntegration
        - GenerativeOrchestration
        - GenerativeAnswersNode
        - SearchAndSummarize
        - GenerativeActions
        - KnowledgeSource

    .PARAMETER FeatureType
        The feature type string to validate.

    .OUTPUTS
        String - One of the canonical feature type values, or 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$FeatureType
    )

    if ([string]::IsNullOrWhiteSpace($FeatureType)) {
        return 'Unknown'
    }

    $normalized = $FeatureType.Trim().ToLower()

    # Map various representations to canonical values
    $featureMap = @{
        'azureopenaiintegration' = 'AzureOpenAIIntegration'
        'azureopenai'            = 'AzureOpenAIIntegration'
        'aoai'                   = 'AzureOpenAIIntegration'
        'openai'                 = 'AzureOpenAIIntegration'
        'generativeorchestration' = 'GenerativeOrchestration'
        'orchestration'          = 'GenerativeOrchestration'
        'genorch'                = 'GenerativeOrchestration'
        'generativeanswersnode'  = 'GenerativeAnswersNode'
        'generativeanswers'      = 'GenerativeAnswersNode'
        'genanswers'             = 'GenerativeAnswersNode'
        'searchandsummarize'     = 'SearchAndSummarize'
        'search'                 = 'SearchAndSummarize'
        'summarize'              = 'SearchAndSummarize'
        'generativeactions'      = 'GenerativeActions'
        'genactions'             = 'GenerativeActions'
        'actions'                = 'GenerativeActions'
        'knowledgesource'        = 'KnowledgeSource'
        'knowledge'              = 'KnowledgeSource'
        'datasource'             = 'KnowledgeSource'
    }

    if ($featureMap.ContainsKey($normalized)) {
        return $featureMap[$normalized]
    }

    Write-Warning "Unrecognized generative AI feature type: '$FeatureType'. Returning 'Unknown'."
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

function Test-OrchestrationMode {
    <#
    .SYNOPSIS
        Validates and normalizes an orchestration mode string.

    .DESCRIPTION
        Accepts various representations of orchestration modes and normalizes
        them to canonical values: Classic, Generative, Custom.
        Returns 'Unknown' for unrecognized values.

    .PARAMETER Mode
        The orchestration mode string to validate.

    .OUTPUTS
        String - One of: Classic, Generative, Custom, Unknown
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Mode
    )

    if ([string]::IsNullOrWhiteSpace($Mode)) {
        return 'Unknown'
    }

    $normalized = $Mode.Trim().ToLower()

    $modeMap = @{
        'classic'    = 'Classic'
        'generative' = 'Generative'
        'custom'     = 'Custom'
        'unified'    = 'Generative'
        'standard'   = 'Classic'
        'traditional' = 'Classic'
        'gen'        = 'Generative'
        'unable to determine' = 'Unknown'
    }

    if ($modeMap.ContainsKey($normalized)) {
        return $modeMap[$normalized]
    }

    Write-Warning "Unrecognized orchestration mode: '$Mode'. Returning 'Unknown'."
    return 'Unknown'
}
