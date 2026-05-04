<#
.SYNOPSIS
    Retrieves expected moderation level and severity classification for a zone.

.DESCRIPTION
    Loads zone configuration from moderation-baseline.json and determines whether
    a given moderation level is compliant for the specified zone. Returns the
    expected level, compliance status, severity classification, and regulatory
    context for any violations.

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.PARAMETER ActualLevel
    The actual content moderation level detected: Lowest, Low, Medium, High, Highest, or Unknown.

.PARAMETER BaselinePath
    Path to moderation-baseline.json file. Defaults to templates/ in the solution root.

.OUTPUTS
    PSCustomObject with properties:
    - Zone: The governance zone
    - ExpectedLevel: Minimum required moderation level for the zone
    - ActualLevel: The actual level provided
    - IsCompliant: Boolean indicating compliance
    - Severity: Violation severity (Critical/High/Medium/Warning) or $null if compliant
    - RegulatoryContext: Regulatory reference string or $null if compliant

.EXAMPLE
    $result = & ./Get-ExpectedModerationLevel.ps1 -Zone "Zone3" -ActualLevel "Low"
    $result.Severity  # Returns: Critical
    $result.IsCompliant  # Returns: False

.EXAMPLE
    $result = & ./Get-ExpectedModerationLevel.ps1 -Zone "Zone1" -ActualLevel "High"
    $result.IsCompliant  # Returns: True

.NOTES
    File: Get-ExpectedModerationLevel.ps1
    Version: 1.0.1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone,

    [Parameter(Mandatory)]
    [ValidateSet('Lowest', 'Low', 'Medium', 'High', 'Highest', 'Unknown')]
    [string]$ActualLevel,

    [Parameter()]
    [string]$BaselinePath = "$PSScriptRoot/../../templates/moderation-baseline.json"
)

# Resolve path
$resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaselinePath)

if (-not (Test-Path $resolvedPath)) {
    throw "Baseline file not found: $resolvedPath. Expected at: $BaselinePath"
}

# Load baseline
$baseline = Get-Content $resolvedPath -Raw | ConvertFrom-Json

# Get zone configuration
$zoneConfig = $baseline.zones.$Zone

if (-not $zoneConfig) {
    throw "Zone configuration not found for: $Zone"
}

$expectedLevel = $zoneConfig.minimumModerationLevel

# Normalize current Copilot Studio labels to CMM's canonical three-level scale.
$levelAliases = @{
    'Lowest'  = 'Low'
    'Low'     = 'Low'
    'Medium'  = 'Medium'
    'High'    = 'High'
    'Highest' = 'High'
    'Unknown' = 'Unknown'
}
$canonicalActualLevel = $levelAliases[$ActualLevel]

# Define level ordering for comparison
$levelOrder = @{
    'Low'     = 1
    'Medium'  = 2
    'High'    = 3
    'Unknown' = 0
}

# Determine compliance
$actualRank = $levelOrder[$canonicalActualLevel]
$expectedRank = $levelOrder[$expectedLevel]
$isCompliant = $actualRank -ge $expectedRank

# Determine severity and regulatory context
$severity = $null
$regulatoryContext = $null

if (-not $isCompliant) {
    if ($canonicalActualLevel -eq 'Unknown') {
        # Unknown actual level in a known zone - treat as worst case
        $severity = 'Warning'
        $regulatoryContext = 'Governance gap - Unable to determine content moderation level'
    } else {
        # Look up specific violation
        $violation = $zoneConfig.violations.$canonicalActualLevel
        if ($violation) {
            $severity = $violation.severity
            $regulatoryContext = $violation.regulatory
        } else {
            $severity = 'Warning'
            $regulatoryContext = "Moderation level '$canonicalActualLevel' below minimum '$expectedLevel' for $Zone"
        }
    }
}

# Return result
[PSCustomObject]@{
    Zone              = $Zone
    ExpectedLevel     = $expectedLevel
    ActualLevel       = $canonicalActualLevel
    IsCompliant       = $isCompliant
    Severity          = $severity
    RegulatoryContext = $regulatoryContext
}
