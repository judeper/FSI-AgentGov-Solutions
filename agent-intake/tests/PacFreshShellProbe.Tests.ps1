BeforeAll {
    . (Join-Path $PSScriptRoot '..\lab\private\PacFreshShellProbe.ps1')

    function Get-PacProbeShim {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [int]$ExitCode,

            [Parameter(Mandatory)]
            [string]$Message
        )

        if ($IsWindows) {
            $shimPath = Join-Path $Path 'pac-probe.cmd'
            @(
                '@echo off'
                "echo $Message"
                "exit /b $ExitCode"
            ) | Set-Content -Path $shimPath -Encoding ascii
        }
        else {
            $shimPath = Join-Path $Path 'pac-probe'
            @(
                '#!/bin/sh'
                "echo '$Message'"
                "exit $ExitCode"
            ) | Set-Content -Path $shimPath -Encoding utf8NoBOM
            & chmod +x $shimPath
        }

        return $shimPath
    }
}

Describe 'Invoke-PacAuthWhoProbe' {
    It 'returns the native PAC exit code and output' {
        $shim = Get-PacProbeShim -Path $TestDrive -ExitCode 7 -Message 'WAM browser required'

        $result = Invoke-PacAuthWhoProbe -PacCommand $shim

        $result.ExitCode | Should -Be 7
        ($result.Output -join "`n") | Should -Match 'WAM browser required'
    }

    It 'reports success only when PAC exits successfully' {
        $shim = Get-PacProbeShim -Path $TestDrive -ExitCode 0 -Message 'authenticated'

        $result = Invoke-PacAuthWhoProbe -PacCommand $shim

        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n") | Should -Match 'authenticated'
    }
}
