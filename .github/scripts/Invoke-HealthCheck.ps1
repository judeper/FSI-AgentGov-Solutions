#Requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter()] [string] $Repository = $env:GITHUB_REPOSITORY,
    [Parameter()] [string] $LatestTag = $env:LATEST_TAG,
    [Parameter()] [string] $RunUrl = $env:GITHUB_RUN_URL,
    [Parameter()] [int] $MaxAttempts = 4,
    [Parameter()] [int] $BaseDelaySeconds = 2,
    [Parameter()] [int] $MaxDelaySeconds = 30,
    [Parameter()] [int] $MinSolutions = 36,
    [Parameter()] [switch] $ManageIssues,
    [Parameter()] [string] $OutputPath = $env:GITHUB_OUTPUT
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-HealthHeaderValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] $Headers,
        [Parameter(Mandatory)] [string] $Name
    )

    if (-not $Headers) { return $null }
    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $value = $Headers[$key]
                if ($value -is [array]) { return [string]$value[0] }
                return [string]$value
            }
        }
        return $null
    }

    $property = $Headers.PSObject.Properties |
        Where-Object { [string]::Equals($_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if (-not $property) { return $null }
    if ($property.Value -is [array]) { return [string]$property.Value[0] }
    return [string]$property.Value
}

function Get-HealthRetryDelaySeconds {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()] $Headers,
        [Parameter(Mandatory)] [int] $Attempt,
        [Parameter(Mandatory)] [int] $BaseDelaySeconds,
        [Parameter(Mandatory)] [int] $MaxDelaySeconds
    )

    $retryAfter = Get-HealthHeaderValue -Headers $Headers -Name 'Retry-After'
    if (-not [string]::IsNullOrWhiteSpace($retryAfter)) {
        $seconds = 0
        if ([int]::TryParse($retryAfter, [ref]$seconds)) {
            return [Math]::Max(0, [Math]::Min($seconds, $MaxDelaySeconds))
        }

        $retryDate = [datetime]::MinValue
        if ([datetime]::TryParse($retryAfter, [ref]$retryDate)) {
            $delta = [int][Math]::Ceiling(($retryDate.ToUniversalTime() - (Get-Date).ToUniversalTime()).TotalSeconds)
            return [Math]::Max(0, [Math]::Min($delta, $MaxDelaySeconds))
        }
    }

    $delay = $BaseDelaySeconds * [Math]::Pow(2, [Math]::Max(0, $Attempt - 1))
    return [Math]::Min([int]$delay, $MaxDelaySeconds)
}

function Invoke-HealthHttpRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url
    )

    Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 20 -SkipHttpErrorCheck
}

function Test-PublishedArtifactUrl {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $Url,
        [Parameter()] [int] $ExpectedStatusCode = 200,
        [Parameter()] [int] $MaxAttempts = 4,
        [Parameter()] [int] $BaseDelaySeconds = 2,
        [Parameter()] [int] $MaxDelaySeconds = 30
    )

    $transientStatuses = @(429, 502, 503, 504)
    $attemptStatuses = [System.Collections.Generic.List[string]]::new()
    $response = $null
    $errorText = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $response = Invoke-HealthHttpRequest -Url $Url
            $statusCode = [int]$response.StatusCode
        } catch {
            $statusCode = 0
            $errorText = $_.Exception.Message
        }

        $attemptStatuses.Add([string]$statusCode)
        if ($statusCode -eq $ExpectedStatusCode) {
            return [pscustomobject]@{
                Label           = $Label
                Url             = $Url
                Expected        = [string]$ExpectedStatusCode
                FinalStatus     = [string]$statusCode
                AttemptStatuses = @($attemptStatuses)
                Passed          = $true
                Content         = if ($response) { [string]$response.Content } else { '' }
                Errors          = @()
            }
        }

        if (($statusCode -notin $transientStatuses) -or ($attempt -eq $MaxAttempts)) {
            break
        }

        $delay = Get-HealthRetryDelaySeconds -Headers $response.Headers -Attempt $attempt -BaseDelaySeconds $BaseDelaySeconds -MaxDelaySeconds $MaxDelaySeconds
        Write-Host "$Label transient HTTP $statusCode on attempt $attempt/$MaxAttempts; retrying in ${delay}s"
        if ($delay -gt 0) {
            Start-Sleep -Seconds $delay
        }
    }

    $errors = @("$Label expected $ExpectedStatusCode got $($attemptStatuses[-1]) after attempts [$($attemptStatuses -join ' -> ')] -- $Url")
    if ($errorText) {
        $errors += "$Label request error: $errorText"
    }

    return [pscustomobject]@{
        Label           = $Label
        Url             = $Url
        Expected        = [string]$ExpectedStatusCode
        FinalStatus     = [string]$attemptStatuses[-1]
        AttemptStatuses = @($attemptStatuses)
        Passed          = $false
        Content         = if ($response) { [string]$response.Content } else { '' }
        Errors          = $errors
    }
}

function Get-PublishedArtifactTargets {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string] $LatestTag
    )

    @(
        [pscustomobject]@{ Label = 'site-home'; Url = 'https://judeper.github.io/FSI-AgentGov-Solutions/' }
        [pscustomobject]@{ Label = 'site-catalog'; Url = 'https://judeper.github.io/FSI-AgentGov-Solutions/solutions/' }
        [pscustomobject]@{ Label = 'site-detail'; Url = 'https://judeper.github.io/FSI-AgentGov-Solutions/solutions/agent-observability-foundation/' }
        [pscustomobject]@{ Label = 'site-mapping'; Url = 'https://judeper.github.io/FSI-AgentGov-Solutions/reference/control-mapping/' }
        [pscustomobject]@{ Label = 'raw-lock'; Url = "https://raw.githubusercontent.com/judeper/FSI-AgentGov-Solutions/$LatestTag/solutions.json" }
    )
}

function Add-SolutionsLockValidation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $RawLockResult,
        [Parameter(Mandatory)] [int] $MinSolutions
    )

    if (-not $RawLockResult.Passed) { return $RawLockResult }

    $errors = @()
    try {
        $lock = $RawLockResult.Content | ConvertFrom-Json
        $solutions = $lock.solutions
        $solutionProperties = @($solutions.PSObject.Properties)
        if ($solutionProperties.Count -lt $MinSolutions) {
            $errors += "raw-lock solutions.json count below floor: got $($solutionProperties.Count), expected >= $MinSolutions (catalog regression)"
        }
        if (($lock.PSObject.Properties.Name -notcontains 'schemaVersion') -or (-not $lock.schemaVersion)) {
            $errors += 'raw-lock solutions.json missing schemaVersion'
        }
        $missingControls = @($solutionProperties | Where-Object { -not $_.Value.controls }).Count
        if ($missingControls -ne 0) {
            $errors += "raw-lock solutions.json: $missingControls entries missing controls[]"
        }
    } catch {
        $errors += "raw-lock solutions.json parse failed: $($_.Exception.Message)"
    }

    if ($errors.Count -eq 0) { return $RawLockResult }

    return [pscustomobject]@{
        Label           = $RawLockResult.Label
        Url             = $RawLockResult.Url
        Expected        = '200 and valid solutions.json'
        FinalStatus     = 'shape-invalid'
        AttemptStatuses = $RawLockResult.AttemptStatuses
        Passed          = $false
        Content         = $RawLockResult.Content
        Errors          = $errors
    }
}

function Invoke-PublishedArtifactHealthProbe {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string] $LatestTag,
        [Parameter()] [int] $MaxAttempts = 4,
        [Parameter()] [int] $BaseDelaySeconds = 2,
        [Parameter()] [int] $MaxDelaySeconds = 30,
        [Parameter()] [int] $MinSolutions = 36
    )

    $results = foreach ($target in (Get-PublishedArtifactTargets -LatestTag $LatestTag)) {
        $result = Test-PublishedArtifactUrl -Label $target.Label -Url $target.Url -ExpectedStatusCode 200 -MaxAttempts $MaxAttempts -BaseDelaySeconds $BaseDelaySeconds -MaxDelaySeconds $MaxDelaySeconds
        if ($target.Label -eq 'raw-lock') {
            Add-SolutionsLockValidation -RawLockResult $result -MinSolutions $MinSolutions
        } else {
            $result
        }
    }

    return @($results)
}

function Format-HealthIssueBody {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Result,
        [Parameter(Mandatory)] [string] $RunUrl
    )

    $errorLines = @($Result.Errors | ForEach-Object { "- $_" }) -join "`n"
    $attempts = $Result.AttemptStatuses -join ' -> '
    return "Automated probe detected failures:`n`n$errorLines`n`nAttempts: $($Result.Label) $attempts`n`nRun: $RunUrl"
}

function Format-HealthRecoveryComment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Result,
        [Parameter(Mandatory)] [string] $RunUrl
    )

    $attempts = $Result.AttemptStatuses -join ' -> '
    return "Health check target '$($Result.Label)' is healthy again. Attempts: $attempts -- $($Result.Url)`n`nAuto-closing after successful probe.`n`nRun: $RunUrl"
}

function Invoke-HealthGh {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string[]] $ArgumentList
    )

    $output = & gh @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE"
    }
    return $output
}

function Find-OpenHealthIssueForTarget {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $TargetLabel
    )

    $title = 'Health check failure: published artifacts not healthy'
    $search = "`"$title`" in:title `"$TargetLabel`" in:body"
    $json = Invoke-HealthGh -ArgumentList @('issue', 'list', '-R', $Repository, '--state', 'open', '--search', $search, '--json', 'number,updatedAt,body', '--jq', '.')
    $jsonText = @($json) -join "`n"
    if ([string]::IsNullOrWhiteSpace($jsonText)) { return @() }
    return @($jsonText | ConvertFrom-Json)
}

function Sync-PublishedArtifactHealthIssues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [pscustomobject[]] $Results,
        [Parameter(Mandatory)] [string] $RunUrl
    )

    $title = 'Health check failure: published artifacts not healthy'
    foreach ($result in $Results) {
        $openIssues = @(Find-OpenHealthIssueForTarget -Repository $Repository -TargetLabel $result.Label)
        if ($result.Passed) {
            foreach ($issue in $openIssues) {
                $comment = Format-HealthRecoveryComment -Result $result -RunUrl $RunUrl
                Invoke-HealthGh -ArgumentList @('issue', 'close', ([string]$issue.number), '-R', $Repository, '--comment', $comment) | Out-Null
            }
            continue
        }

        $body = Format-HealthIssueBody -Result $result -RunUrl $RunUrl
        if ($openIssues.Count -gt 0) {
            Invoke-HealthGh -ArgumentList @('issue', 'comment', ([string]$openIssues[0].number), '-R', $Repository, '--body', $body) | Out-Null
            if ($openIssues.Count -gt 1) {
                foreach ($duplicate in @($openIssues | Select-Object -Skip 1)) {
                    $comment = "Duplicate health-check issue for target '$($result.Label)' superseded by #$($openIssues[0].number)."
                    Invoke-HealthGh -ArgumentList @('issue', 'close', ([string]$duplicate.number), '-R', $Repository, '--comment', $comment) | Out-Null
                }
            }
        } else {
            Invoke-HealthGh -ArgumentList @('issue', 'create', '-R', $Repository, '--title', $title, '--body', $body, '--label', 'bug') | Out-Null
        }
    }
}

function Write-HealthOutputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject[]] $Results,
        [Parameter()] [string] $OutputPath
    )

    $failed = @($Results | Where-Object { -not $_.Passed })
    $reportLines = @($Results | ForEach-Object { "$($_.Label)  $($_.AttemptStatuses -join ' -> ')  $($_.Url)" })
    $errorLines = @($failed | ForEach-Object { $_.Errors } | ForEach-Object { "- $_" })

    $reportLines | ForEach-Object { Write-Host $_ }
    if (-not $OutputPath) { return }

    Add-Content -LiteralPath $OutputPath -Value "fail=$(if ($failed.Count -gt 0) { '1' } else { '0' })" -Encoding utf8NoBOM
    Add-Content -LiteralPath $OutputPath -Value 'errors<<EOF' -Encoding utf8NoBOM
    $errorLines | Add-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    Add-Content -LiteralPath $OutputPath -Value 'EOF' -Encoding utf8NoBOM
    Add-Content -LiteralPath $OutputPath -Value 'report<<EOF' -Encoding utf8NoBOM
    $reportLines | Add-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    Add-Content -LiteralPath $OutputPath -Value 'EOF' -Encoding utf8NoBOM
}

function Invoke-PublishedArtifactHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $LatestTag,
        [Parameter(Mandatory)] [string] $RunUrl,
        [Parameter()] [int] $MaxAttempts = 4,
        [Parameter()] [int] $BaseDelaySeconds = 2,
        [Parameter()] [int] $MaxDelaySeconds = 30,
        [Parameter()] [int] $MinSolutions = 36,
        [Parameter()] [switch] $ManageIssues,
        [Parameter()] [string] $OutputPath
    )

    $results = Invoke-PublishedArtifactHealthProbe -LatestTag $LatestTag -MaxAttempts $MaxAttempts -BaseDelaySeconds $BaseDelaySeconds -MaxDelaySeconds $MaxDelaySeconds -MinSolutions $MinSolutions
    Write-HealthOutputs -Results $results -OutputPath $OutputPath
    if ($ManageIssues) {
        Sync-PublishedArtifactHealthIssues -Repository $Repository -Results $results -RunUrl $RunUrl
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-PublishedArtifactHealthCheck @PSBoundParameters
}
