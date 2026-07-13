function Invoke-PacAuthWhoProbe {
    [CmdletBinding()]
    param(
        [string]$PacCommand = 'pac'
    )

    $pacOutput = & $PacCommand auth who 2>&1
    $pacExitCode = $LASTEXITCODE
    if ($null -eq $pacExitCode) {
        $pacExitCode = 1
    }

    [pscustomobject]@{
        ExitCode = [int]$pacExitCode
        Output   = @($pacOutput | ForEach-Object { $_.ToString() })
    }
}
