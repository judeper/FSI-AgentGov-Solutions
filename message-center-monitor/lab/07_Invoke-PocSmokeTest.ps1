#Requires -Version 7.0
<#
.SYNOPSIS
    POC-journey smoke test for message-center-monitor. Mirrors the customer
    Phase 1 deployment defined in docs/poc-quickstart.md.

.DESCRIPTION
    Where lab/06 exercises the assessment / evidence / C1 admin-column-
    preservation paths end-to-end, lab/07 mirrors what an FSI customer
    actually runs during their POC: preflight -> alt-key wait gate -> one
    real sync that posts a Teams notification and writes fsi_notifiedon ->
    a second sync that proves cross-run idempotency.

    Steps:

      1. Run Test-McmPrerequisites.ps1; assert all checks PASS (or PASS+SKIP).
      2. Poll the fsi_MessageCenterIdKey alternate key for Active status
         (preflight check 9 catches "not yet Active" but in a CI loop the
         alt-key can race; this step is the documented wait gate from
         docs/poc-quickstart.md Step 1.3).
      3. Start a local HTTP listener as a background job; capture every
         POST body to a temp file (one JSON record per POST).
      4. Set $env:MCM_TEAMS_WEBHOOK_URL to the listener URL and run
         Invoke-MessageCenterSync.ps1 once.
      5. Assert the listener captured >=1 POST AND each captured payload
         parses as JSON with the expected envelope shape:
            type=message
            attachments[0].contentType=application/vnd.microsoft.card.adaptive
            attachments[0].content.type=AdaptiveCard
      6. Query Dataverse: assert >=1 row in fsi_messagecenterlogs has a
         non-empty fsi_notifiedon.
      7. Capture the (fsi_messagecenterid, fsi_notifiedon) pairs from the
         set notified in step 6. Re-run sync.
      8. Assert the listener capture count is UNCHANGED between sync 1
         and sync 2 (per-row idempotency via fsi_notifiedon).
      9. Assert every (fsi_messagecenterid, fsi_notifiedon) pair from
         step 7 is byte-identical after sync 2 (admin-owned column
         protection - the C1 invariant - extended to the new fsi_notifiedon
         write-back path).
     10. Tear down: clear $env:MCM_TEAMS_WEBHOOK_URL; stop the listener
         job; delete the capture file. Do NOT delete the synced rows -
         lab/99 owns full teardown.

.PARAMETER ConfigPath
    Path to lab-config.json (defaults to lab/lab-config.json next to this
    script).

.PARAMETER ListenerPort
    TCP port for the local HTTP listener that captures Teams POSTs.
    Defaults to 18765 (high port unlikely to conflict). The script will
    fail fast if the port is in use.

.PARAMETER MaxPostWaitSeconds
    Maximum seconds to wait after each sync for the listener to receive
    expected POST(s) before failing. Default 60.

.PARAMETER MaxAltKeyWaitSeconds
    Maximum seconds to wait for the alternate key to reach Active.
    Default 300.

.PARAMETER SkipPreflight
    Skip Step 1 (preflight). Useful for re-runs when preflight has already
    passed in the same shell session.

.PARAMETER ContinueOnFailure
    Continue past failed steps and report all failures at the end.

.NOTES
    Lab dry-run step 7 of 7. Solution: message-center-monitor v2.5.1+
    Mirrors the docs/poc-quickstart.md Phase 1 customer journey.

    The local listener uses System.Net.HttpListener at http://localhost:<port>/
    so no firewall ACL is required on Windows. CI runners on Linux honor
    the same URL prefix via dotnet's cross-platform HttpListener
    implementation.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [int]    $ListenerPort = 18765,
    [Parameter()] [int]    $MaxPostWaitSeconds  = 60,
    [Parameter()] [int]    $MaxAltKeyWaitSeconds = 300,
    [Parameter()] [switch] $SkipPreflight,
    [Parameter()] [switch] $ContinueOnFailure,
    [Parameter()] [switch] $AllowProduction
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '07-poc-smoke-test'

$cfg   = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
$state = Get-LabState

if (-not $state.dataverse -or -not $state.dataverse.applicationUserId) {
    Write-LabLog -Level Error -Message "Run 04_New-AppUser.ps1 first." -Throw
}

$solutionRoot = Split-Path -Parent $PSScriptRoot
$govDir       = Join-Path $solutionRoot 'scripts/governance'
$resource     = $cfg.powerPlatform.environmentUrl.TrimEnd('/')
$apiBase      = "$resource/api/data/v9.2"

$listenerUrl  = "http://localhost:$ListenerPort/"
$captureFile  = Join-Path $env:TEMP "mcm-poc-smoke-capture-$([guid]::NewGuid().ToString('N')).jsonl"

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$step, [string]$msg) {
    $failures.Add("[$step] $msg")
    Write-LabLog -Level Error -Message "[$step] $msg"
    if (-not $ContinueOnFailure) { throw "[$step] $msg" }
}

# Resolve auth state ----------------------------------------------------------
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
}

$govArgs = @{
    AuthMode     = 'ClientSecret'
    TenantId     = $cfg.tenant.tenantId
    ClientId     = $state.appRegistration.applicationId
    ClientSecret = $secStr
    DataverseUrl = $cfg.powerPlatform.environmentUrl
}

# ---------- Step 1: Preflight ----------------------------------------------
if (-not $SkipPreflight) {
    Write-LabLog -Level Info -Message "[Step 1/10] Running Test-McmPrerequisites.ps1..."
    try {
        $preArgs = @{
            TenantId     = $cfg.tenant.tenantId
            ClientId     = $state.appRegistration.applicationId
            ClientSecret = $secStr
            AuthMode     = 'ClientSecret'
            DataverseUrl = $cfg.powerPlatform.environmentUrl
        }
        if ($cfg.keyVault.name)       { $preArgs.KeyVaultName       = $cfg.keyVault.name }
        if ($cfg.keyVault.secretName) { $preArgs.KeyVaultSecretName = $cfg.keyVault.secretName }
        # Phase 1 webhook is what this smoke test exercises; pass the listener URL
        # so the mutual-exclusion check (#11) sees a Phase 1 path but no Phase 3.
        $preArgs.TeamsWebhookUrl = $listenerUrl

        & "$govDir/Test-McmPrerequisites.ps1" @preArgs
        if ($LASTEXITCODE -ne 0) {
            Add-Failure 'Step1.Preflight' "Test-McmPrerequisites.ps1 exited with $LASTEXITCODE (one or more checks FAILED). Inspect the preflight output above."
        }
    } catch { Add-Failure 'Step1.Preflight' $_.Exception.Message }
} else { Write-LabLog -Level Warn -Message "[Step 1/10] SKIPPED (-SkipPreflight)." }

# ---------- Step 2: Alt-key Active wait gate -------------------------------
Write-LabLog -Level Info -Message "[Step 2/10] Polling fsi_MessageCenterIdKey for Active status (max $MaxAltKeyWaitSeconds s)..."
$altKeyUrl = "$apiBase/EntityDefinitions(LogicalName='fsi_messagecenterlog')/Keys"
$altKeyDeadline = (Get-Date).AddSeconds($MaxAltKeyWaitSeconds)
$altKeyActive = $false
$altKeyBackoff = 5
$altKeyAttempt = 0
while ((Get-Date) -lt $altKeyDeadline) {
    $altKeyAttempt++
    try {
        $altResp = Invoke-RestMethod -Uri $altKeyUrl -Headers $dvHdr -Method Get -ErrorAction Stop
        $altKey  = $altResp.value | Where-Object { $_.SchemaName -eq 'fsi_MessageCenterIdKey' } | Select-Object -First 1
        $altStatus = if ($altKey) { [int]$altKey.EntityKeyIndexStatus } else { -1 }
        $statusLabel = switch ($altStatus) {
            0 { 'Pending' }
            1 { 'InProgress' }
            2 { 'Active' }
            3 { 'Failed' }
            default { "Unknown($altStatus)" }
        }
        Write-LabLog -Level Info -Message "  attempt ${altKeyAttempt}: alt-key status=$statusLabel"
        if ($altStatus -eq 2) { $altKeyActive = $true; break }
        if ($altStatus -eq 3) { Add-Failure 'Step2.AltKey' "Alt-key activation FAILED (status=3). Inspect Power Apps maker portal -> Tables -> Message Center Log -> Keys." }
    } catch {
        Write-LabLog -Level Warn -Message "  attempt ${altKeyAttempt}: poll error $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $altKeyBackoff
    $altKeyBackoff = [Math]::Min($altKeyBackoff * 2, 30)
}
if (-not $altKeyActive) { Add-Failure 'Step2.AltKey' "Alt-key did not reach Active within $MaxAltKeyWaitSeconds s. Re-run with -MaxAltKeyWaitSeconds 900 or wait and retry." }

# ---------- Step 3: Start the local HTTP capture listener -----------------
#
# Steps 3-9 are wrapped in a single try/finally so that Add-Failure's throw
# (when -ContinueOnFailure is NOT supplied) still leaves the listener job
# and the capture file in a clean state. Step 10's teardown lives in the
# finally block; without that, a Step 4 abort would silently leak port
# 18765 (forcing manual `Stop-Job` / `Remove-Item` cleanup) and the next
# lab/07 run would FAIL Step 3 with "Address already in use".
$listenerJob = $null
$probePathFilter = '"path":\s*"/(ping|probe-[a-z]+)"'
try {

Write-LabLog -Level Info -Message "[Step 3/10] Starting local HTTP listener at $listenerUrl (capture -> $captureFile)..."
if (Test-Path -LiteralPath $captureFile) { Remove-Item -LiteralPath $captureFile -Force }
try {
    $listenerJob = Start-Job -Name 'mcm-poc-smoke-listener' -ScriptBlock {
        param($Url, $LogFile)
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add($Url)
        try {
            $listener.Start()
        } catch {
            # Surface the failure as a single JSON record so the parent
            # can detect it via the capture file even after the job exits.
            ([pscustomobject]@{
                timestamp = (Get-Date).ToString('o')
                listener_error = $_.Exception.Message
            } | ConvertTo-Json -Compress) | Out-File -FilePath $LogFile -Append -Encoding utf8
            return
        }
        while ($listener.IsListening) {
            try {
                $context = $listener.GetContext()
                $reader  = [System.IO.StreamReader]::new($context.Request.InputStream)
                $body    = $reader.ReadToEnd()
                $reader.Dispose()
                ([pscustomobject]@{
                    timestamp     = (Get-Date).ToString('o')
                    method        = $context.Request.HttpMethod
                    path          = $context.Request.Url.AbsolutePath
                    contentLength = $context.Request.ContentLength64
                    body          = $body
                } | ConvertTo-Json -Compress -Depth 5) | Out-File -FilePath $LogFile -Append -Encoding utf8
                $context.Response.StatusCode = 202
                $context.Response.OutputStream.Close()
            } catch {
                break
            }
        }
        try { $listener.Stop(); $listener.Close() } catch {}
    } -ArgumentList $listenerUrl, $captureFile

    # Give the listener a beat to bind
    Start-Sleep -Seconds 2

    # Verify the listener is up by hitting it ourselves. -NoProxy bypasses any
    # system proxy so localhost POSTs are not routed through a corporate gateway.
    # Self-ping (and the liveness probes below) write to the same capture
    # file as real Teams POSTs; we filter them out via $probePathFilter at
    # every read site rather than mutating the file in place.
    $pingOk = $false
    try {
        $pingResp = Invoke-WebRequest -Uri ($listenerUrl + 'ping') -Method Post -Body 'ping' -ContentType 'text/plain' -UseBasicParsing -TimeoutSec 5 -NoProxy
        if ($pingResp.StatusCode -eq 202) { $pingOk = $true }
    } catch {
        Write-LabLog -Level Warn -Message "  listener self-ping failed: $($_.Exception.Message)"
    }
    if (-not $pingOk) { Add-Failure 'Step3.Listener' "Local HTTP listener did not respond. Check port $ListenerPort is free and the job is still running." }

    # Allow the listener's background job to flush /ping to disk
    Start-Sleep -Milliseconds 500
} catch {
    Add-Failure 'Step3.Listener' $_.Exception.Message
}

# ---------- Step 4: Sync run 1 (with TeamsWebhookUrl pointed at listener) --
Write-LabLog -Level Info -Message "[Step 4/10] Sync run 1 (will POST to listener)..."
try {
    & "$govDir/Invoke-MessageCenterSync.ps1" @govArgs `
        -DaysBack $cfg.smoke.daysBack `
        -TeamsWebhookUrl $listenerUrl `
        -ErrorAction Stop
    # Allow time for in-flight POSTs to land in the capture file
    Start-Sleep -Seconds 5
} catch {
    Add-Failure 'Step4.Sync1' $_.Exception.Message
}

# ---------- Step 5: Assert capture shape -----------------------------------
Write-LabLog -Level Info -Message "[Step 5/10] Asserting captured payload shape..."
$capturedAfterSync1 = @()
try {
    if (Test-Path -LiteralPath $captureFile) {
        # Filter at read time (not in-place file rewrite) so the probe
        # records the liveness checks emit between syncs don't pollute counts.
        $capturedAfterSync1 = Get-Content -LiteralPath $captureFile |
            Where-Object { $_ -and $_.Trim() -and ($_ -notmatch $probePathFilter) } |
            ForEach-Object { $_ | ConvertFrom-Json }
    }
    Write-LabLog -Level Info -Message "  captured POSTs after sync 1: $($capturedAfterSync1.Count)"
    if ($capturedAfterSync1.Count -lt 1) {
        Add-Failure 'Step5.CaptureCount' "Expected >=1 captured POST after sync 1. The tenant has no high/critical Message Center posts in the last $($cfg.smoke.daysBack) days, OR the webhook integration did not fire. Confirm the tenant has eligible messages and check sync logs."
    }
    foreach ($cap in $capturedAfterSync1) {
        if ($cap.PSObject.Properties.Name -contains 'listener_error') {
            Add-Failure 'Step5.ListenerError' "Listener failed to start: $($cap.listener_error)"
            continue
        }
        try {
            $payload = $cap.body | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Add-Failure 'Step5.PayloadJson' "Captured POST body is not valid JSON. body=$($cap.body)"
            continue
        }
        if ($payload.type -ne 'message') {
            Add-Failure 'Step5.PayloadEnvelope' "Captured payload.type='$($payload.type)' (expected 'message')."
        }
        if (-not $payload.attachments -or $payload.attachments.Count -lt 1) {
            Add-Failure 'Step5.PayloadAttachments' "Captured payload missing attachments[]."
            continue
        }
        $att = $payload.attachments[0]
        if ($att.contentType -ne 'application/vnd.microsoft.card.adaptive') {
            Add-Failure 'Step5.AttachmentType' "attachments[0].contentType='$($att.contentType)' (expected 'application/vnd.microsoft.card.adaptive')."
        }
        if (-not $att.content -or $att.content.type -ne 'AdaptiveCard') {
            Add-Failure 'Step5.CardType' "attachments[0].content.type='$($att.content.type)' (expected 'AdaptiveCard')."
        }
    }
} catch { Add-Failure 'Step5' $_.Exception.Message }

# ---------- Step 6: Assert fsi_notifiedon populated in Dataverse -----------
Write-LabLog -Level Info -Message "[Step 6/10] Querying fsi_messagecenterlogs for notified rows..."
$notifiedSnapshot = @{}
try {
    # Fetch rows with non-empty fsi_notifiedon (Dataverse OData treats empty
    # DateTime as null; we use 'ne null' filter syntax)
    $notifyQuery = "$apiBase/fsi_messagecenterlogs?`$select=fsi_messagecenterid,fsi_notifiedon,fsi_severity&`$filter=fsi_notifiedon ne null&`$top=200"
    $notifyResp  = Invoke-RestMethod -Uri $notifyQuery -Headers $dvHdr -Method Get -ErrorAction Stop
    $notifiedRows = @($notifyResp.value)
    Write-LabLog -Level Info -Message "  notified rows: $($notifiedRows.Count)"
    if ($notifiedRows.Count -lt 1) {
        Add-Failure 'Step6.NotifiedCount' "Expected >=1 row with non-empty fsi_notifiedon after sync 1. Check that sync 1's notifyCount > 0 in the script output."
    }
    foreach ($row in $notifiedRows) {
        $notifiedSnapshot[$row.fsi_messagecenterid] = $row.fsi_notifiedon
    }
} catch { Add-Failure 'Step6' $_.Exception.Message }

# ---------- Liveness probe (mid): prove the listener is still receiving ----
#
# Without this, Step 8's "capture count unchanged" assertion can FALSE-PASS
# if the listener job crashed silently between sync 1 and sync 2: sync 2's
# Send-McmTeamsWebhook is no-throw by contract, so failed POSTs would be
# logged as warnings (not errors) and the capture file would stay frozen
# at the sync-1 count for the WRONG reason. The probe POST going through
# end-to-end proves the listener was alive at this moment in time.
Write-LabLog -Level Info -Message "  liveness probe (mid): POST /probe-mid..."
$probeMidOk = $false
try {
    $probeMidResp = Invoke-WebRequest -Uri ($listenerUrl + 'probe-mid') -Method Post -Body 'probe' -ContentType 'text/plain' -UseBasicParsing -TimeoutSec 5 -NoProxy
    if ($probeMidResp.StatusCode -eq 202) { $probeMidOk = $true }
} catch {
    Write-LabLog -Level Warn -Message "  probe-mid POST failed: $($_.Exception.Message)"
}
if (-not $probeMidOk) {
    Add-Failure 'Step6.ListenerLiveness' "Listener did not accept the mid-syncs liveness probe. Sync 2's count-unchanged assertion would FALSE-PASS; aborting before that point."
}
Start-Sleep -Milliseconds 500

# ---------- Step 7+8+9: Sync run 2 -> cross-run idempotency ----------------
Write-LabLog -Level Info -Message "[Step 7/10] Sync run 2 (idempotency: notify count and fsi_notifiedon must not change)..."
$captureCountBeforeSync2 = $capturedAfterSync1.Count
try {
    & "$govDir/Invoke-MessageCenterSync.ps1" @govArgs `
        -DaysBack $cfg.smoke.daysBack `
        -TeamsWebhookUrl $listenerUrl `
        -ErrorAction Stop
    Start-Sleep -Seconds 5
} catch { Add-Failure 'Step7.Sync2' $_.Exception.Message }

# ---------- Liveness probe (end): prove the listener survived sync 2 ------
Write-LabLog -Level Info -Message "  liveness probe (end): POST /probe-end..."
$probeEndOk = $false
try {
    $probeEndResp = Invoke-WebRequest -Uri ($listenerUrl + 'probe-end') -Method Post -Body 'probe' -ContentType 'text/plain' -UseBasicParsing -TimeoutSec 5 -NoProxy
    if ($probeEndResp.StatusCode -eq 202) { $probeEndOk = $true }
} catch {
    Write-LabLog -Level Warn -Message "  probe-end POST failed: $($_.Exception.Message)"
}
if (-not $probeEndOk) {
    Add-Failure 'Step7.ListenerLiveness' "Listener died sometime during sync 2. Cannot trust Step 8's count-unchanged assertion (any sync-2 POSTs that arrived after the death are missing from the capture file)."
}
Start-Sleep -Milliseconds 500

Write-LabLog -Level Info -Message "[Step 8/10] Asserting capture count unchanged..."
$capturedAfterSync2 = @()
try {
    if (Test-Path -LiteralPath $captureFile) {
        $capturedAfterSync2 = Get-Content -LiteralPath $captureFile |
            Where-Object { $_ -and $_.Trim() -and ($_ -notmatch $probePathFilter) } |
            ForEach-Object { $_ | ConvertFrom-Json }
    }
    Write-LabLog -Level Info -Message "  captured POSTs after sync 2: $($capturedAfterSync2.Count) (before sync 2: $captureCountBeforeSync2)"
    if ($capturedAfterSync2.Count -ne $captureCountBeforeSync2) {
        Add-Failure 'Step8.DedupCount' "Sync 2 produced $($capturedAfterSync2.Count - $captureCountBeforeSync2) additional POST(s) (expected 0). fsi_notifiedon idempotency gate did not fire."
    }
} catch { Add-Failure 'Step8' $_.Exception.Message }

Write-LabLog -Level Info -Message "[Step 9/10] Asserting fsi_notifiedon byte-identical (C1 invariant)..."
try {
    $notifyQuery2 = "$apiBase/fsi_messagecenterlogs?`$select=fsi_messagecenterid,fsi_notifiedon&`$filter=fsi_notifiedon ne null&`$top=200"
    $notifyResp2  = Invoke-RestMethod -Uri $notifyQuery2 -Headers $dvHdr -Method Get -ErrorAction Stop
    $notifyRows2  = @($notifyResp2.value)
    $clobbered = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $notifyRows2) {
        $mcid = $row.fsi_messagecenterid
        if (-not $notifiedSnapshot.ContainsKey($mcid)) { continue }
        $expected = [string]$notifiedSnapshot[$mcid]
        $actual   = [string]$row.fsi_notifiedon
        if ($expected -ne $actual) {
            $clobbered.Add("${mcid}: expected=$expected actual=$actual")
        }
    }
    if ($clobbered.Count -gt 0) {
        Add-Failure 'Step9.NotifiedOnClobbered' "$($clobbered.Count) row(s) had fsi_notifiedon CHANGED by sync 2 (C1 admin-column-preservation violation): $($clobbered -join '; ')"
    }
} catch { Add-Failure 'Step9' $_.Exception.Message }

}
finally {
    # ---------- Step 10: Teardown (runs even when Add-Failure throws) ------
    Write-LabLog -Level Info -Message "[Step 10/10] Tearing down listener and capture file..."
    if ($listenerJob) {
        try {
            Stop-Job -Job $listenerJob -ErrorAction SilentlyContinue
            Remove-Job -Job $listenerJob -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    if (Test-Path -LiteralPath $captureFile) {
        try { Remove-Item -LiteralPath $captureFile -Force -ErrorAction SilentlyContinue } catch {}
    }
}

# ---------- Summary --------------------------------------------------------
Write-LabLog -Level Info -Message "============================================================"
if ($failures.Count -eq 0) {
    Write-LabLog -Level Info -Message "POC SMOKE TEST: PASS"
    Write-LabLog -Level Info -Message "============================================================"
    exit 0
} else {
    Write-LabLog -Level Error -Message "POC SMOKE TEST: FAIL ($($failures.Count) failure(s))"
    foreach ($f in $failures) { Write-LabLog -Level Error -Message "  $f" }
    Write-LabLog -Level Error -Message "============================================================"
    exit 1
}
