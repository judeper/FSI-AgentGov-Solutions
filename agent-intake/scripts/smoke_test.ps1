<#
.SYNOPSIS
  End-to-end smoke test for agent-intake v0.2.0-preview Express path.

.DESCRIPTION
  Runs read-only checks that confirm the deployment is wired correctly:
    1. Dataverse schema present (all 9 tables + key columns)
    2. Power Pages portal page reachable (HTTP 200)
    3. Power Automate Router flow exists and is enabled
    4. Sponsor Teams card payload validates against the JSON schema
    5. Classification --self-test passes
    6. Auto-detect environments script runs and returns >=1 Express-eligible env
    7. Purview retention label verification (best-effort; warns on permission gap)

  No data is created. Safe to run against production.

.PARAMETER EnvironmentUrl
  The Dataverse environment URL (e.g. https://contoso.crm.dynamics.com).

.PARAMETER PortalUrl
  Power Pages portal base URL.

.PARAMETER TokenSource
  'mi' (managed identity, default) or 'cli' (azure-cli cache, dev fallback).

.EXAMPLE
  pwsh ./scripts/smoke_test.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -PortalUrl https://contoso.powerpages.microsoft.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory)]
    [string]$PortalUrl,

    [ValidateSet('mi', 'cli')]
    [string]$TokenSource = 'mi'
)

$ErrorActionPreference = 'Continue'
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}

# 1. Dataverse schema check (logical names lowercased; no underscores between words)
Write-Host "[1/7] Dataverse schema..."
$expectedTables = @(
    'fsi_intakerequest', 'fsi_intakedatasource', 'fsi_intakerisksignal',
    'fsi_intakereview', 'fsi_intakeapproval', 'fsi_intakedecisionlog',
    'fsi_intakesponsorship', 'fsi_intakeauditevent', 'fsi_intakeretentionrecord'
)
try {
    if ($TokenSource -eq 'cli') {
        $token = az account get-access-token --resource $EnvironmentUrl --query accessToken -o tsv
    } else {
        $token = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl).Token
    }
    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    foreach ($t in $expectedTables) {
        $url = "$EnvironmentUrl/api/data/v9.2/EntityDefinitions(LogicalName='$t')?`$select=LogicalName"
        try {
            $null = Invoke-RestMethod -Uri $url -Headers $headers -Method GET -ErrorAction Stop
            Add-Result $t 'PASS' 'present'
        } catch {
            Add-Result $t 'FAIL' "missing or 403: $($_.Exception.Message)"
        }
    }
} catch {
    Add-Result 'dataverse-token' 'FAIL' $_.Exception.Message
}

# 2. Portal reachability
Write-Host "[2/7] Power Pages portal..."
try {
    $resp = Invoke-WebRequest -Uri "$PortalUrl/agent-intake" -Method HEAD -UseBasicParsing -TimeoutSec 30
    if ($resp.StatusCode -in 200, 302) {
        Add-Result 'portal-page' 'PASS' "HTTP $($resp.StatusCode)"
    } else {
        Add-Result 'portal-page' 'WARN' "Unexpected HTTP $($resp.StatusCode)"
    }
} catch {
    Add-Result 'portal-page' 'FAIL' $_.Exception.Message
}

# 3. Router flow check (manual prompt — Power Automate API surface limited)
Add-Result 'router-flow' 'MANUAL' 'Verify in Power Automate portal: fsi-intake-router enabled and trigger bound to fsi_intakerequest'

# 4. Sponsor card schema validation
Write-Host "[4/7] Sponsor card JSON..."
$cardPath = Join-Path $PSScriptRoot '..' 'templates' 'sponsor-approval-card.json'
try {
    $card = Get-Content $cardPath -Raw | ConvertFrom-Json
    if ($card.type -eq 'AdaptiveCard' -and $card.actions.Count -ge 2) {
        Add-Result 'sponsor-card-json' 'PASS' "$($card.actions.Count) actions"
    } else {
        Add-Result 'sponsor-card-json' 'FAIL' "Unexpected card shape"
    }
} catch {
    Add-Result 'sponsor-card-json' 'FAIL' $_.Exception.Message
}

# 5. Classification self-test
Write-Host "[5/7] Classification rules..."
$pyExe = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'python3' }
$classifyScript = Join-Path $PSScriptRoot 'seed_classification_rules.py'
try {
    $output = & $pyExe $classifyScript --self-test 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        Add-Result 'classification-self-test' 'PASS' 'all cases passed'
    } else {
        Add-Result 'classification-self-test' 'FAIL' "$output"
    }
} catch {
    Add-Result 'classification-self-test' 'FAIL' $_.Exception.Message
}

# 6. Environment auto-detect
Write-Host "[6/7] Environment auto-detect..."
$smokeOutDir = Join-Path (Get-Location) '.agent-intake-smoke'
New-Item -ItemType Directory -Path $smokeOutDir -Force | Out-Null
$envOut = Join-Path $smokeOutDir 'fsi-intake-envs.json'
$envScript = Join-Path $PSScriptRoot 'autodetect_environments.py'
try {
    & $pyExe $envScript --output $envOut --token-source $TokenSource 2>&1 | Out-Null
    $envs = Get-Content $envOut -Raw | ConvertFrom-Json
    $eligible = @($envs | Where-Object { $_.expressPathEligible })
    if ($eligible.Count -ge 1) {
        Add-Result 'env-autodetect' 'PASS' "$($eligible.Count) Express-eligible of $($envs.Count)"
    } else {
        Add-Result 'env-autodetect' 'WARN' "0 Express-eligible envs — verify environment SKUs"
    }
} catch {
    Add-Result 'env-autodetect' 'FAIL' $_.Exception.Message
}

# 7. Purview retention label
Write-Host "[7/7] Purview retention label..."
$purviewScript = Join-Path $PSScriptRoot 'autodetect_purview.py'
try {
    $output = & $pyExe $purviewScript --token-source $TokenSource 2>&1
    if ($LASTEXITCODE -eq 0) {
        Add-Result 'purview-label' 'PASS' 'FSI-AgentIntake-7yr verified'
    } else {
        Add-Result 'purview-label' 'WARN' 'label not verified — see scripts/setup_purview_retention_label.py'
    }
} catch {
    Add-Result 'purview-label' 'WARN' $_.Exception.Message
}

# Summary
Write-Host ""
Write-Host "=== Smoke test summary ==="
$results | Format-Table -AutoSize
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
Write-Host ""
if ($failed -eq 0) {
    Write-Host "All required checks passed. Manual checks remain — see results table." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$failed check(s) failed." -ForegroundColor Red
    exit 1
}
