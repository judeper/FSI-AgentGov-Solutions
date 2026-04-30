#Requires -Version 7.0
<#
.SYNOPSIS
    Lab logging helper with secret redaction. Writes to console and a per-step log file.
.DESCRIPTION
    Every lab automation script dot-sources this helper. It scrubs Bearer tokens,
    client_secret values, and Authorization headers before any text reaches disk
    or stdout. This complements `Write-McmRedacted` in the governance scripts.

    Usage:
        . $PSScriptRoot/Write-LabLog.ps1
        $script:LabLogPath = Initialize-LabLog -StepName '01-app-reg'
        Write-LabLog -Level Info -Message 'Starting...'
        Write-LabLog -Level Warn -Message 'Secret expires soon'
        Write-LabLog -Level Error -Message 'Consent failed' -Throw
.NOTES
    Redaction patterns are intentionally over-broad: it is acceptable to redact
    one too many things; it is NEVER acceptable to leak a secret to a log file.
#>

$script:LabLogPath = $null
$script:LabRunCorrelationId = $null

function Get-LabLogDirectory {
    [CmdletBinding()]
    param()
    # Default: lab/logs/ next to this lib/ folder.
    $labRoot = Split-Path -Parent $PSScriptRoot
    $logDir  = Join-Path $labRoot 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    return $logDir
}

function Initialize-LabLog {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $StepName,
        [Parameter()] [string] $LogDirectory
    )
    if (-not $LogDirectory) { $LogDirectory = Get-LabLogDirectory }
    $ts = (Get-Date -AsUTC).ToString('yyyyMMddTHHmmssZ')
    $script:LabLogPath = Join-Path $LogDirectory ("{0}-{1}.log" -f $StepName, $ts)
    $script:LabRunCorrelationId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $header = "=== Lab step '$StepName' started $ts (run=$($script:LabRunCorrelationId)) ==="
    Add-Content -LiteralPath $script:LabLogPath -Value $header -Encoding utf8NoBOM
    return $script:LabLogPath
}

function ConvertTo-RedactedString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [AllowEmptyString()] [string] $InputText
    )
    process {
        if ([string]::IsNullOrEmpty($InputText)) { return $InputText }
        $s = $InputText
        # Order matters: scrub the most specific patterns first so the broader
        # `Authorization:` rule does not over-redact a line we already scrubbed.
        $s = [regex]::Replace($s, '(?i)(Bearer\s+)[A-Za-z0-9\-_\.~\+/=]+',          '$1<REDACTED>')
        $s = [regex]::Replace($s, '(?i)(client_secret["'']?\s*[:=]\s*["'']?)[^"''\s,&}]+', '$1<REDACTED>')
        $s = [regex]::Replace($s, '(?i)(client_assertion["'']?\s*[:=]\s*["'']?)[^"''\s,&}]+', '$1<REDACTED>')
        $s = [regex]::Replace($s, '(?im)^(Authorization\s*:\s*).+$',                '$1<REDACTED>')
        $s = [regex]::Replace($s, '(?i)(["'']password["'']?\s*[:=]\s*["''])[^"'']+(["''])', '$1<REDACTED>$2')
        $s = [regex]::Replace($s, '(?i)("access_token"\s*:\s*")[^"]+(")',            '$1<REDACTED>$2')
        $s = [regex]::Replace($s, '(?i)("refresh_token"\s*:\s*")[^"]+(")',           '$1<REDACTED>$2')
        return $s
    }
}

function Write-LabLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Info', 'Warn', 'Error', 'Debug')] [string] $Level,
        [Parameter(Mandatory, ValueFromPipeline)] [AllowEmptyString()] [string] $Message,
        [Parameter()] [switch] $Throw
    )
    process {
        $redacted = ConvertTo-RedactedString -InputText $Message
        $ts       = (Get-Date -AsUTC).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $line     = "$ts [$Level] $redacted"

        switch ($Level) {
            'Info'  { Write-Host  $line -ForegroundColor Gray }
            'Warn'  { Write-Host  $line -ForegroundColor Yellow }
            'Error' { Write-Host  $line -ForegroundColor Red }
            'Debug' { Write-Verbose $line }
        }
        if ($script:LabLogPath) {
            Add-Content -LiteralPath $script:LabLogPath -Value $line -Encoding utf8NoBOM
        }
        if ($Throw -and $Level -eq 'Error') {
            throw $redacted
        }
    }
}

function Get-LabConfig {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()] [string] $ConfigPath
    )
    if (-not $ConfigPath) {
        $labRoot   = Split-Path -Parent $PSScriptRoot
        $ConfigPath = Join-Path $labRoot 'lab-config.json'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Lab config not found at '$ConfigPath'. Copy lab-config.example.json -> lab-config.json and fill it in."
    }
    return Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

function Get-LabState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()] [string] $StatePath)
    if (-not $StatePath) {
        $labRoot   = Split-Path -Parent $PSScriptRoot
        $StatePath = Join-Path $labRoot 'lab-state.json'
    }
    if (Test-Path -LiteralPath $StatePath) {
        return Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{
        schemaVersion = '1.0.0'
        createdAt     = (Get-Date -AsUTC).ToString('o')
        createdBy     = $env:USERNAME
        tenantId      = $null
    }
}

function Save-LabState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject] $State,
        [Parameter()] [string] $StatePath
    )
    if (-not $StatePath) {
        $labRoot   = Split-Path -Parent $PSScriptRoot
        $StatePath = Join-Path $labRoot 'lab-state.json'
    }
    $State | Add-Member -NotePropertyName 'lastUpdated' -NotePropertyValue (Get-Date -AsUTC).ToString('o') -Force
    if ($PSCmdlet.ShouldProcess($StatePath, 'Save lab state')) {
        $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding utf8NoBOM
    }
}

function Assert-NonProdAcknowledgement {
    <#
    .SYNOPSIS
        Hard non-prod safety guard. Refuses to proceed unless the engineer has
        explicitly acknowledged in lab-config.json that this is a non-prod target.

    .DESCRIPTION
        Every script that mutates tenant or environment state calls this before
        making changes. The check is literal-string-equal so a typo or generic
        "yes" cannot satisfy it. AllowProduction is an explicit override for the
        rare case where prod re-validation is intentional - it requires a separate
        log message and -AllowProduction switch on the caller.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter()] [switch] $AllowProduction
    )
    $expected = 'I understand this lab must not target production'
    $ack = $Config.nonProd.acknowledgement
    if ($AllowProduction) {
        Write-LabLog -Level Warn -Message "Non-prod guard BYPASSED via -AllowProduction. tenantId=$($Config.tenant.tenantId) env=$($Config.powerPlatform.environmentUrl)"
        return
    }
    if ($ack -ne $expected) {
        $msg = "Non-prod guard FAILED. lab-config.json must contain `"nonProd.acknowledgement`": `"$expected`" before any mutating step. " +
               "If you are intentionally re-running against a production tenant (NOT recommended), pass -AllowProduction to bypass."
        Write-LabLog -Level Error -Message $msg -Throw
    }
    Write-LabLog -Level Info -Message "Non-prod guard OK (target tenant=$($Config.tenant.tenantId), env=$($Config.powerPlatform.environmentUrl))"
}

function Set-LabHandoffSecret {
    <#
    .SYNOPSIS
        Stores a transient secret value in a gitignored handoff file readable
        only by the current user. Used by 01 to pass a freshly minted client
        secret to 02 across pwsh process boundaries when Key Vault does not
        yet exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SecretValue
    )
    $labRoot = Split-Path -Parent $PSScriptRoot
    $path    = Join-Path $labRoot '.secret-handoff'
    Set-Content -LiteralPath $path -Value $SecretValue -Encoding utf8NoBOM -NoNewline
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        # Restrict ACL: owner full control, no inherited perms.
        try {
            $acl = Get-Acl -LiteralPath $path
            $acl.SetAccessRuleProtection($true, $false)
            $owner = [System.Security.Principal.NTAccount]([Environment]::UserName)
            $rule  = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $owner, 'FullControl', 'Allow')
            $acl.AddAccessRule($rule)
            Set-Acl -LiteralPath $path -AclObject $acl
        } catch {
            Write-LabLog -Level Warn -Message "Could not restrict ACL on .secret-handoff: $($_.Exception.Message)"
        }
    } else {
        chmod 600 $path 2>$null
    }
    Write-LabLog -Level Info -Message ".secret-handoff written (gitignored, owner-only). The next script will consume and delete it."
}

function Get-LabHandoffSecret {
    <#
    .SYNOPSIS
        Reads (and DELETES) the transient .secret-handoff file written by 01.
        Returns $null if no handoff exists.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $labRoot = Split-Path -Parent $PSScriptRoot
    $path    = Join-Path $labRoot '.secret-handoff'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $val = Get-Content -LiteralPath $path -Raw
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    return $val
}
