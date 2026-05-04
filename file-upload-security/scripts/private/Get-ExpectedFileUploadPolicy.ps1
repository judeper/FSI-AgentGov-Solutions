<#
.SYNOPSIS
    Evaluates expected file upload policy for a given zone.

.DESCRIPTION
    Loads the fileupload-baseline.json template and returns the expected
    file upload policy for a given zone, including whether file uploads
    should be allowed, minimum content moderation level, and violation
    severity if non-compliant.

.PARAMETER Zone
    The governance zone (Zone1, Zone2, Zone3, Unknown).

.PARAMETER FileUploadEnabled
    The actual file upload enabled status (boolean).

.PARAMETER ContentModerationLevel
    The actual content moderation level (Low, Medium, High, Highest, Unknown).

.PARAMETER BaselinePath
    Path to fileupload-baseline.json. Defaults to ../../templates/fileupload-baseline.json.

.OUTPUTS
    PSCustomObject with compliance evaluation results.

.NOTES
    File: Get-ExpectedFileUploadPolicy.ps1
    Version: 1.0.0
    Solution: File Upload Security Configurator (v8)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Zone,

    [Parameter(Mandatory)]
    [AllowNull()]
    [object]$FileUploadEnabled,

    [Parameter()]
    [string]$ContentModerationLevel = 'Unknown',

    [Parameter()]
    [string]$BaselinePath,

    [Parameter()]
    [object]$Baseline
)

#region Load Baseline

if ($Baseline) {
    $baseline = $Baseline
} else {
    if (-not $BaselinePath) {
        $BaselinePath = Join-Path $PSScriptRoot '..' '..' 'templates' 'fileupload-baseline.json'
    }

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaselinePath)

    if (-not (Test-Path $resolvedPath)) {
        throw "Baseline file not found: $resolvedPath"
    }

    $baseline = Get-Content $resolvedPath -Raw | ConvertFrom-Json
}

#endregion

#region Moderation Level Comparison

$moderationRank = @{
    'Unknown' = 0
    'Low'     = 1
    'Medium'  = 2
    'High'    = 3
    'Highest' = 4
}

function Test-ModerationSufficient {
    param([string]$Actual, [string]$Required)

    $actualRank = if ($moderationRank.ContainsKey($Actual)) { $moderationRank[$Actual] } else { 0 }
    $requiredRank = if ($moderationRank.ContainsKey($Required)) { $moderationRank[$Required] } else { 0 }

    return $actualRank -ge $requiredRank
}

#endregion

#region Evaluate Compliance

# Normalize zone name for baseline lookup
$zoneKey = switch ($Zone) {
    'Zone1'  { 'Zone 1' }
    'Zone 1' { 'Zone 1' }
    'Zone2'  { 'Zone 2' }
    'Zone 2' { 'Zone 2' }
    'Zone3'  { 'Zone 3' }
    'Zone 3' { 'Zone 3' }
    default  { $null }
}

# Handle unknown zone
if (-not $zoneKey -or -not ($baseline.zoneRequirements.PSObject.Properties.Name -contains $zoneKey)) {
    # $null FileUploadEnabled = indeterminate; fail closed per FUSClient.psm1 contract
    if ($null -eq $FileUploadEnabled) {
        return [PSCustomObject]@{
            Zone                    = $Zone
            ExpectedFileUpload      = 'Review Required'
            ActualFileUpload        = 'Indeterminate'
            ExpectedModeration      = 'Unknown'
            ActualModeration        = $ContentModerationLevel
            IsCompliant             = $false
            FileUploadCompliant     = $false
            ModerationCompliant     = $false
            Severity                = 'Medium'
            ViolationType           = 'Unknown_Zone_IndeterminateFileUpload'
            RegulatoryContext       = 'FINRA 4511 — File upload status could not be determined for agent in unclassified environment; manual review required'
        }
    }

    # Unknown zone with file uploads enabled is Medium severity
    if ($FileUploadEnabled -eq $true) {
        return [PSCustomObject]@{
            Zone                    = $Zone
            ExpectedFileUpload      = 'Review Required'
            ActualFileUpload        = 'Enabled'
            ExpectedModeration      = 'Unknown'
            ActualModeration        = $ContentModerationLevel
            IsCompliant             = $false
            FileUploadCompliant     = $false
            ModerationCompliant     = $false
            Severity                = 'Medium'
            ViolationType           = 'Unknown_Zone_FileUploadEnabled'
            RegulatoryContext       = 'FINRA 4511 — File upload enabled on agent in unclassified environment; zone classification required for governance policy validation'
        }
    }

    return [PSCustomObject]@{
        Zone                    = $Zone
        ExpectedFileUpload      = 'Review Required'
        ActualFileUpload        = 'Disabled'
        ExpectedModeration      = 'N/A'
        ActualModeration        = $ContentModerationLevel
        IsCompliant             = $true
        FileUploadCompliant     = $true
        ModerationCompliant     = $true
        Severity                = 'Info'
        ViolationType           = $null
        RegulatoryContext       = $null
    }
}

$zonePolicy = $baseline.zoneRequirements.$zoneKey

# Handle indeterminate file upload status — fail closed
if ($null -eq $FileUploadEnabled) {
    return [PSCustomObject]@{
        Zone                    = $Zone
        ExpectedFileUpload      = if ($zonePolicy.fileUploadAllowed) { 'Allowed' } else { 'Disabled' }
        ActualFileUpload        = 'Indeterminate'
        ExpectedModeration      = $zonePolicy.minimumModerationLevel
        ActualModeration        = $ContentModerationLevel
        IsCompliant             = $false
        FileUploadCompliant     = $false
        ModerationCompliant     = $false
        Severity                = 'High'
        ViolationType           = "${zoneKey}_IndeterminateFileUpload" -replace ' ', ''
        RegulatoryContext       = "FINRA 4511 — File upload status could not be determined for agent in $zoneKey; configuration may be missing or unparseable. Manual review required."
    }
}

$isFileUploadEnabled = $FileUploadEnabled -eq $true

# Determine file upload compliance
$fileUploadCompliant = $true
$moderationCompliant = $true
$severity = 'Info'
$violationType = $null
$regulatoryContext = $null

if (-not $zonePolicy.fileUploadAllowed -and $isFileUploadEnabled) {
    # Zone 3: file upload should be disabled but is enabled
    $fileUploadCompliant = $false

    # Check moderation level too
    $moderationSufficient = Test-ModerationSufficient -Actual $ContentModerationLevel -Required $zonePolicy.minimumModerationLevel
    if (-not $moderationSufficient) {
        $moderationCompliant = $false
        $severity = 'Critical'
        $violationType = 'Zone3_FileUploadEnabled_InsufficientModeration'
        $regulatoryContext = "FINRA 4511, SEC 17a-3, GLBA 501(b) — File upload enabled in $($zoneKey) (Enterprise Managed) without $($zonePolicy.minimumModerationLevel) content moderation; expands agent data intake beyond declared scope with insufficient content controls"
    } else {
        $severity = 'Critical'
        $violationType = 'Zone3_FileUploadEnabled_NoApproval'
        $regulatoryContext = "FINRA Regulatory Notice 25-07, FINRA Rule 4511, SEC Rule 17a-3, GLBA 501(b), 12 CFR 30 App. B — File upload enabled in $($zoneKey) (Enterprise Managed) without documented governance approval; data minimization requirements indicate file upload should remain disabled unless explicitly authorized"
    }
} elseif ($zonePolicy.fileUploadAllowed -and $zonePolicy.requiresApproval -and $isFileUploadEnabled) {
    # Zone 2: file upload allowed with restrictions
    $moderationSufficient = Test-ModerationSufficient -Actual $ContentModerationLevel -Required $zonePolicy.minimumModerationLevel
    if (-not $moderationSufficient) {
        $moderationCompliant = $false
        $severity = 'High'
        $violationType = 'Zone2_FileUploadEnabled_InsufficientModeration'
        $regulatoryContext = "FINRA 4511, SEC 17a-3 — File upload enabled in $($zoneKey) (Team Collaboration) without $($zonePolicy.minimumModerationLevel) content moderation minimum; user-uploaded content requires elevated content controls"
    }
    # Note: approval status cannot be verified programmatically — flagged for governance review
} elseif ($isFileUploadEnabled -and $zoneKey -eq 'Zone 1') {
    # Zone 1: allowed, but check minimum moderation
    $moderationSufficient = Test-ModerationSufficient -Actual $ContentModerationLevel -Required $zonePolicy.minimumModerationLevel
    if (-not $moderationSufficient) {
        $moderationCompliant = $false
        $severity = 'Warning'
        $violationType = 'Zone1_NoModeration'
        $regulatoryContext = "FINRA Regulatory Notice 25-07 — File upload enabled in $($zoneKey) (Personal Productivity) without content moderation configured; recommended for defense-in-depth"
    }
}

$isCompliant = $fileUploadCompliant -and $moderationCompliant

return [PSCustomObject]@{
    Zone                    = $Zone
    ExpectedFileUpload      = if ($zonePolicy.fileUploadAllowed) { 'Allowed' } else { 'Disabled' }
    ActualFileUpload        = if ($isFileUploadEnabled) { 'Enabled' } else { 'Disabled' }
    ExpectedModeration      = $zonePolicy.minimumModerationLevel
    ActualModeration        = $ContentModerationLevel
    IsCompliant             = $isCompliant
    FileUploadCompliant     = $fileUploadCompliant
    ModerationCompliant     = $moderationCompliant
    Severity                = $severity
    ViolationType           = $violationType
    RegulatoryContext       = $regulatoryContext
}

#endregion
