#Requires -Version 7.4
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit tests for Resolve-WiqConfiguredTier in Get-WorkIqConfigState.ps1.

.DESCRIPTION
    Dot-sources the Work IQ config-state script - which defines functions only
    and performs no work at load time - and asserts the Tier-A classification
    switch: a native Work IQ MCP tool resolves to NativeMcpCopilotStudio and
    takes precedence over every other signal; a direct Work IQ API operation
    resolves to NativeApiDirect; knowledge / connector / generative-AI
    configuration resolves to Adjacent; otherwise NotConfigured.

.NOTES
    Run with: Invoke-Pester -Path .\ResolveWiqConfiguredTier.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    . (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Get-WorkIqConfigState.ps1')).Path
}

Describe 'Resolve-WiqConfiguredTier' {
    It 'classifies <Name> as <Expected>' -ForEach @(
        @{ Name = 'a native MCP tool'; Mcp = $true; Api = $false; Adj = $false; Expected = 'NativeMcpCopilotStudio' }
        @{ Name = 'a native API-direct call'; Mcp = $false; Api = $true; Adj = $false; Expected = 'NativeApiDirect' }
        @{ Name = 'adjacent configuration'; Mcp = $false; Api = $false; Adj = $true; Expected = 'Adjacent' }
        @{ Name = 'no Work IQ configuration'; Mcp = $false; Api = $false; Adj = $false; Expected = 'NotConfigured' }
    ) {
        $tier = Resolve-WiqConfiguredTier -HasNativeMcpTool $Mcp -HasNativeApiDirect $Api -HasAdjacentConfig $Adj -CreatedIn 'Copilot Studio'
        $tier | Should -Be $Expected
    }

    It 'gives a native MCP tool precedence over every other signal' {
        $tier = Resolve-WiqConfiguredTier -HasNativeMcpTool $true -HasNativeApiDirect $true -HasAdjacentConfig $true -CreatedIn 'Copilot Studio'
        $tier | Should -Be 'NativeMcpCopilotStudio'
    }

    It 'gives a native API-direct call precedence over adjacent configuration' {
        $tier = Resolve-WiqConfiguredTier -HasNativeMcpTool $false -HasNativeApiDirect $true -HasAdjacentConfig $true
        $tier | Should -Be 'NativeApiDirect'
    }
}
