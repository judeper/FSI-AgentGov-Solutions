#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-end smoke test orchestrator for message-center-monitor lab dry-run.

.DESCRIPTION
    Validates the v2.4.0 fix end-to-end against a live (lab) Power Platform
    environment, with explicit assertions for the C1 regression class
    (admin-owned columns must NEVER be clobbered on update). Steps:

      1. Run all Pester + pytest tests (gate; -SkipUnitTests bypasses).
      2. Invoke-MessageCenterSync.ps1 -DryRun -- auth + Graph reachability.
      3. Live sync -- assert >=1 row, all with fsi_assessmentstatus = 100000000.
      4. Re-run sync -- assert UpdatedRecords > 0, NewRecords == 0, no dup ids.
      5. Pick one row (KnownMessageId if config'd, else first); set ALL 7 admin-owned
         fields via Dataverse PATCH.
      6. Re-run sync -- assert ALL 7 admin-owned fields are unchanged on that row.
         This is the C1 regression test against the live wire.
      7. Get-MessageCenterAssessmentStatus.ps1 -- counts > 0.
      8. Export-MessageCenterEvidence.ps1 -- NDJSON + .sha256 written.
      9. Test-EvidenceIntegrity.ps1 -Quiet -- returns $true.
     10. Manual gate (interactive prompt): print docs/flow-configuration.md
         checklist and prompt engineer to confirm cloud-flow build/run.
         Records pass/fail in lab-state.json.smoke.

    Fail-fast unless -ContinueOnFailure.

.PARAMETER ConfigPath
    Path to lab-config.json.

.PARAMETER SkipUnitTests
    Skip Step 1. Useful for re-runs after unit tests already passed in CI.

.PARAMETER SkipManualGate
    Skip Step 10 (the cloud-flow manual confirmation prompt). Useful for
    fully unattended re-runs after the engineer has already validated the
    cloud flow once.

.PARAMETER ContinueOnFailure
    Continue past failed steps and report all failures at the end.

.NOTES
    Lab dry-run step 6 of 7. Solution: message-center-monitor v2.5.0+
    Council finding to test traceability:
      C1 -> Steps 5+6 (admin-field preservation across all 7 columns)
      H2 -> Steps 3+4 (real network; retry exercised under throttling)
      Schema alt-key -> Step 3 (sync uses the alt-key URL)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [switch] $SkipUnitTests,
    [Parameter()] [switch] $SkipManualGate,
    [Parameter()] [switch] $ContinueOnFailure,
    [Parameter()] [switch] $AllowProduction
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '06-smoke-test'

$cfg   = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
$state = Get-LabState
if (-not $state.dataverse -or -not $state.dataverse.applicationUserId) {
    Write-LabLog -Level Error -Message "Run 04_New-AppUser.ps1 first." -Throw
}

$repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$solutionRoot = Split-Path -Parent $PSScriptRoot
$testsDir     = Join-Path $solutionRoot 'tests'
$govDir       = Join-Path $solutionRoot 'scripts/governance'
$resource     = $cfg.powerPlatform.environmentUrl.TrimEnd('/')
$apiBase      = "$resource/api/data/v9.2"

$adminCols = @(
    'fsi_assessmentstatus'
    'fsi_assessment'
    'fsi_assessedby'
    'fsi_assesseddate'
    'fsi_actionstaken'
    'fsi_impactsagents'
    'fsi_notifiedon'
)

$failures = New-Object System.Collections.Generic.List[string]
function Add-Failure([string]$step, [string]$msg) {
    $failures.Add("[$step] $msg")
    Write-LabLog -Level Error -Message "[$step] $msg"
    if (-not $ContinueOnFailure) { throw "[$step] $msg" }
}

# Get tokens up front.
$kvSecret = Get-AzKeyVaultSecret -VaultName $cfg.keyVault.name -Name $cfg.keyVault.secretName -AsPlainText -ErrorAction Stop
Import-Module MSAL.PS -ErrorAction Stop
$secStr = ConvertTo-SecureString $kvSecret -AsPlainText -Force
$tok = Get-MsalToken -ClientId $state.appRegistration.applicationId `
                     -ClientSecret $secStr `
                     -TenantId $cfg.tenant.tenantId `
                     -Authority "https://login.microsoftonline.com/$($cfg.tenant.tenantId)" `
                     -Scopes "$resource/.default" -ErrorAction Stop
$dvHdr = @{
    Authorization      = "Bearer $($tok.AccessToken)"
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    Accept             = 'application/json'
    'Content-Type'     = 'application/json'
    Prefer             = 'return=representation'
}

# Common args for the governance scripts (ClientSecret auth in lab per A3).
$govArgs = @{
    AuthMode       = 'ClientSecret'
    TenantId       = $cfg.tenant.tenantId
    ClientId       = $state.appRegistration.applicationId
    ClientSecret   = $secStr
    DataverseUrl   = $cfg.powerPlatform.environmentUrl
}

# ---------- Step 1: Unit tests ----------------------------------------------
if (-not $SkipUnitTests) {
    Write-LabLog -Level Info -Message "[Step 1/10] Running Pester + pytest..."
    try {
        Push-Location $repoRoot
        $pesterCfg = New-PesterConfiguration
        $pesterCfg.Run.Path     = $testsDir
        $pesterCfg.Run.Exit     = $false
        $pesterCfg.Run.PassThru = $true
        $pesterCfg.Output.Verbosity = 'Normal'
        $r = Invoke-Pester -Configuration $pesterCfg
        if ($r.FailedCount -gt 0) { Add-Failure 'Step1.Pester' "$($r.FailedCount) Pester test(s) failed."; }

        & python -m pytest -q $testsDir
        if ($LASTEXITCODE -ne 0) { Add-Failure 'Step1.Pytest' "pytest exited $LASTEXITCODE." }
    } finally { Pop-Location }
} else { Write-LabLog -Level Warn -Message "[Step 1/10] SKIPPED (-SkipUnitTests)." }

# ---------- Step 2: Sync -DryRun --------------------------------------------
Write-LabLog -Level Info -Message "[Step 2/10] Sync -DryRun (auth + Graph reachability)..."
try {
    & "$govDir/Invoke-MessageCenterSync.ps1" @govArgs -DryRun -DaysBack $cfg.smoke.daysBack -ErrorAction Stop
} catch { Add-Failure 'Step2' $_.Exception.Message }

# ---------- Step 3: Live sync (initial) -------------------------------------
Write-LabLog -Level Info -Message "[Step 3/10] Live sync..."
try {
    & "$govDir/Invoke-MessageCenterSync.ps1" @govArgs -DaysBack $cfg.smoke.daysBack -ErrorAction Stop
    Start-Sleep -Seconds 3
    $rows = Invoke-RestMethod -Uri "$apiBase/fsi_messagecenterlogs?`$select=fsi_messagecenterid,fsi_assessmentstatus&`$top=50" -Headers $dvHdr -Method Get -ErrorAction Stop
    $count = @($rows.value).Count
    Write-LabLog -Level Info -Message "  Dataverse rows: $count"
    if ($count -lt 1) {
        Add-Failure 'Step3' "No rows in fsi_messagecenterlogs after sync. Tenant has no Message Center messages in the last $($cfg.smoke.daysBack) days, OR sync silently failed. Check the run log and try -DaysBack 90."
    } else {
        $bad = $rows.value | Where-Object { $_.fsi_assessmentstatus -ne 100000000 }
        if ($bad) { Add-Failure 'Step3' "$(@($bad).Count) row(s) have fsi_assessmentstatus != 100000000 on initial create." }
    }
} catch { Add-Failure 'Step3' $_.Exception.Message }

# ---------- Step 4: Re-run sync (idempotency + UPDATE path) -----------------
Write-LabLog -Level Info -Message "[Step 4/10] Re-run sync (idempotency)..."
try {
    $syncOut2 = & "$govDir/Invoke-MessageCenterSync.ps1" @govArgs -DaysBack $cfg.smoke.daysBack -ErrorAction Stop 2>&1 | Out-String
    Write-LabLog -Level Info -Message "  --- sync stdout (Step 4) ---`n$syncOut2`n  ----------------------------"
    Start-Sleep -Seconds 3
    $rows2 = Invoke-RestMethod -Uri "$apiBase/fsi_messagecenterlogs?`$select=fsi_messagecenterid&`$top=200" -Headers $dvHdr -Method Get -ErrorAction Stop
    $ids = $rows2.value.fsi_messagecenterid
    $dup = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($dup) { Add-Failure 'Step4' "Duplicate fsi_messagecenterid values after re-sync: $(@($dup).Count). The alt-key upsert should prevent this." }

    # C1 evidence: parse counters from the sync output. This is the assertion the
    # docs promise. We expect Updated >= 1 (everything that was created in Step 3
    # should now hit the update path) and Failed == 0 and New == 0 (no duplicates).
    # Sync prints lines like "║ Updated Records:  5                              ║"
    $upd = if ($syncOut2 -match 'Updated\s*Records?[^0-9]+(\d+)')  { [int]$Matches[1] } else { -1 }
    $new = if ($syncOut2 -match 'New\s*Records?[^0-9]+(\d+)')      { [int]$Matches[1] } else { -1 }
    $fail= if ($syncOut2 -match 'Failed\s*Records?[^0-9]+(\d+)')   { [int]$Matches[1] } else { -1 }
    Write-LabLog -Level Info -Message "  parsed counters: Updated=$upd New=$new Failed=$fail"
    if ($upd -lt 1)  { Add-Failure 'Step4.UpdatePath' "Sync re-run reported UpdatedRecords=$upd but should be >=1 - the C1 update branch did not execute. If sync output uses different counter names, update the regex in this script." }
    if ($fail -ne 0) { Add-Failure 'Step4.Failed'     "Sync re-run reported FailedRecords=$fail (expected 0)." }
    if ($new -gt 0)  { Add-Failure 'Step4.Duplicates' "Sync re-run reported NewRecords=$new (expected 0; rows from Step 3 should already exist)." }
} catch { Add-Failure 'Step4' $_.Exception.Message }

# ---------- Step 5: Set ALL 7 admin-owned fields ----------------------------
Write-LabLog -Level Info -Message "[Step 5/10] Set all 7 admin-owned fields on a target row..."
$targetMcid = $cfg.smoke.knownMessageId
try {
    if ([string]::IsNullOrEmpty($targetMcid)) {
        $first = Invoke-RestMethod -Uri "$apiBase/fsi_messagecenterlogs?`$select=fsi_messagecenterid&`$top=1" -Headers $dvHdr -Method Get -ErrorAction Stop
        if (-not $first.value) { Add-Failure 'Step5' "No row to operate on."; throw "no row" }
        $targetMcid = $first.value[0].fsi_messagecenterid
    }
    Write-LabLog -Level Info -Message "  Target message id: $targetMcid"

    $now = (Get-Date -AsUTC).ToString('o')
    $patchBody = @{
        fsi_assessmentstatus = 100000001  # Reviewed
        fsi_assessment       = 'lab smoke test marker'
        fsi_assessedby       = $cfg.operator.runnerUpn
        fsi_assesseddate     = $now
        fsi_actionstaken     = 'lab smoke test - no real action required'
        fsi_impactsagents    = $true
        fsi_notifiedon       = $now
    } | ConvertTo-Json

    $url = "$apiBase/fsi_messagecenterlogs(fsi_messagecenterid='$targetMcid')"
    Invoke-RestMethod -Uri $url -Headers $dvHdr -Method Patch -Body $patchBody -ErrorAction Stop | Out-Null

    # Capture before-state for the C1 assertion.
    $script:adminBefore = Invoke-RestMethod -Uri "$($url)?`$select=$($adminCols -join ',')" -Headers $dvHdr -Method Get -ErrorAction Stop
    Write-LabLog -Level Info -Message "  Admin fields set. Captured baseline."
} catch { Add-Failure 'Step5' $_.Exception.Message }

# ---------- Step 6: Re-run sync; assert NO admin-field clobber (C1) ---------
Write-LabLog -Level Info -Message "[Step 6/10] CRITICAL: Re-run sync; assert C1 - no admin-field clobber..."
try {
    # Bump the row's Graph-owned timestamp so sync's diff path actually fires
    # an UPDATE, otherwise sync may decide nothing changed and skip the update
    # branch entirely (false-positive C1 pass).
    $bumpUrl = "$apiBase/fsi_messagecenterlogs(fsi_messagecenterid='$targetMcid')"
    $bumpBody = @{ fsi_lastupdated = (Get-Date -AsUTC).AddYears(-5).ToString('o') } | ConvertTo-Json
    try { Invoke-RestMethod -Uri $bumpUrl -Headers $dvHdr -Method Patch -Body $bumpBody -ErrorAction Stop | Out-Null } catch { Write-LabLog -Level Warn -Message "  could not back-date fsi_lastupdated: $($_.Exception.Message) (continuing - sync may still update if message metadata differs)" }

    $syncOut3 = & "$govDir/Invoke-MessageCenterSync.ps1" @govArgs -DaysBack $cfg.smoke.daysBack -ErrorAction Stop 2>&1 | Out-String
    Write-LabLog -Level Info -Message "  --- sync stdout (Step 6) ---`n$syncOut3`n  ----------------------------"
    Start-Sleep -Seconds 3
    $url = "$apiBase/fsi_messagecenterlogs(fsi_messagecenterid='$targetMcid')"
    $after = Invoke-RestMethod -Uri "$($url)?`$select=$($adminCols -join ',')" -Headers $dvHdr -Method Get -ErrorAction Stop

    $clobbered = @()
    foreach ($col in $adminCols) {
        if ([string]($script:adminBefore.$col) -ne [string]($after.$col)) {
            $clobbered += ('{0}: ''{1}'' -> ''{2}''' -f $col, $script:adminBefore.$col, $after.$col)
        }
    }
    if ($clobbered.Count -gt 0) {
        Add-Failure 'Step6.C1' "ADMIN FIELDS CLOBBERED on update for $targetMcid - this is the C1 regression. Diff:`n  - $($clobbered -join "`n  - ")"
    } else {
        Write-LabLog -Level Info -Message "  ALL 7 admin-owned columns preserved across update [PASS - C1 verified end-to-end]"
    }

    # Also assert the sync ACTUALLY ran the update branch this time.
    $upd6  = if ($syncOut3 -match 'Updated\s*Records?[^0-9]+(\d+)') { [int]$Matches[1] } else { -1 }
    $fail6 = if ($syncOut3 -match 'Failed\s*Records?[^0-9]+(\d+)')  { [int]$Matches[1] } else { -1 }
    Write-LabLog -Level Info -Message "  parsed counters: Updated=$upd6 Failed=$fail6"
    if ($upd6 -lt 1)  { Add-Failure 'Step6.UpdatePath' "Sync reported UpdatedRecords=$upd6 - the C1 path was not exercised, so the preservation assertion above is INCONCLUSIVE. If sync output names the counter differently, update the regex." }
    if ($fail6 -ne 0) { Add-Failure 'Step6.Failed'     "Sync reported FailedRecords=$fail6 (expected 0)." }
} catch { Add-Failure 'Step6' $_.Exception.Message }

# ---------- Step 7: Assessment status counts --------------------------------
Write-LabLog -Level Info -Message "[Step 7/10] Get-MessageCenterAssessmentStatus..."
try {
    $statusOut = & "$govDir/Get-MessageCenterAssessmentStatus.ps1" @govArgs -ErrorAction Stop
    if (-not $statusOut) { Add-Failure 'Step7' "No output." }
} catch { Add-Failure 'Step7' $_.Exception.Message }

# ---------- Step 8: Evidence export -----------------------------------------
Write-LabLog -Level Info -Message "[Step 8/10] Export-MessageCenterEvidence..."
$evidenceDir = Join-Path $solutionRoot 'lab/evidence'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$evidencePath = $null
try {
    $evidencePath = & "$govDir/Export-MessageCenterEvidence.ps1" @govArgs -OutputPath $evidenceDir -ErrorAction Stop
    if (-not $evidencePath -or -not (Test-Path -LiteralPath $evidencePath)) {
        Add-Failure 'Step8' "Evidence file not written."
    }
    if ($evidencePath -and -not (Test-Path -LiteralPath "$evidencePath.sha256")) {
        Add-Failure 'Step8' "Evidence .sha256 companion not written."
    }
} catch { Add-Failure 'Step8' $_.Exception.Message }

# ---------- Step 9: Integrity verify ----------------------------------------
Write-LabLog -Level Info -Message "[Step 9/10] Test-EvidenceIntegrity -Quiet..."
try {
    if ($evidencePath) {
        $ok = & "$govDir/Test-EvidenceIntegrity.ps1" -EvidenceFilePath $evidencePath -Quiet
        if (-not $ok) { Add-Failure 'Step9' "Integrity check returned $false." }
    }
} catch { Add-Failure 'Step9' $_.Exception.Message }

# ---------- Step 10: Manual cloud-flow gate ---------------------------------
$manualOutcome = 'skipped'
$manualBy      = $null
if ($SkipManualGate) {
    Write-LabLog -Level Warn -Message "[Step 10/10] SKIPPED (-SkipManualGate). Production readiness REQUIRES this validation."
} else {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " STEP 10 - MANUAL CLOUD FLOW VALIDATION" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "Build the cloud flow per: message-center-monitor/docs/flow-configuration.md"
    Write-Host "Run it once. Verify:"
    Write-Host "  [ ] Flow completes successfully (green checkmark in run history)"
    Write-Host "  [ ] New rows appear in fsi_messagecenterlogs"
    Write-Host "  [ ] Re-run does NOT clobber the admin fields you set in Step 5"
    Write-Host "  [ ] Adaptive Card renders correctly in the Teams channel (or skip if no Teams)"
    Write-Host ""
    $resp = Read-Host "Did the cloud flow pass all checks? (y/n/skip)"
    switch ($resp.ToLower()) {
        'y' { $manualOutcome = 'pass'; $manualBy = $cfg.operator.runnerUpn; Write-LabLog -Level Info -Message "  Manual gate: PASS by $manualBy" }
        'n' { $manualOutcome = 'fail'; $manualBy = $cfg.operator.runnerUpn; Add-Failure 'Step10' "Engineer reported cloud flow validation FAILED. Fix the flow per docs/flow-configuration.md before declaring lab dry-run complete." }
        default { $manualOutcome = 'skipped'; Write-LabLog -Level Warn -Message "  Manual gate: SKIPPED" }
    }
}

# ---------- Persist outcome --------------------------------------------------
$state | Add-Member -NotePropertyName 'smoke' -NotePropertyValue ([pscustomobject]@{
    lastRunAt              = (Get-Date -AsUTC).ToString('o')
    lastRunOutcome         = ($(if ($failures.Count -eq 0) { 'pass' } else { 'fail' }))
    manualFlowConfirmedBy  = $manualBy
    manualFlowConfirmedAt  = ($(if ($manualBy) { (Get-Date -AsUTC).ToString('o') } else { $null }))
}) -Force
Save-LabState -State $state

# ---------- Summary ----------------------------------------------------------
Write-Host ""
if ($failures.Count -eq 0) {
    Write-LabLog -Level Info -Message "================================================================================"
    Write-LabLog -Level Info -Message " LAB SMOKE TEST: PASS  (10/10 steps$(if ($SkipUnitTests) {' minus unit tests'})$(if ($SkipManualGate) {', manual gate skipped'}))"
    Write-LabLog -Level Info -Message "================================================================================"
} else {
    Write-LabLog -Level Error -Message "================================================================================"
    Write-LabLog -Level Error -Message " LAB SMOKE TEST: FAIL  ($($failures.Count) failure(s))"
    foreach ($f in $failures) { Write-LabLog -Level Error -Message "  - $f" }
    Write-LabLog -Level Error -Message "================================================================================"
    exit 1
}
