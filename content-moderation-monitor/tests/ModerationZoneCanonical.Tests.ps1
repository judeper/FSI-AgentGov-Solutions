#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit assertions proving the canonical (Option A) zone semantics for
    the Content Moderation Monitor: strictest moderation maps to Zone 1 / 100000001.

.DESCRIPTION
    The canonical zone reconciliation (accepted Option A, 2026-06-13) establishes that on
    the lab validation tenant Zone 1 (Enterprise) is the MOST-restrictive tier and Zone 3
    (Personal) the LEAST. These tests lock that contract in three places that must
    agree, per Discipline Rule 1 (propagate the amendment to ALL downstream surfaces):

      1. Policy table        templates/moderation-baseline.json
      2. Expected-level gate  scripts/private/Get-ExpectedModerationLevel.ps1
      3. Integer write map    scripts/private/CMMClient.psm1 (ZoneToInt map)

    They also guard the detector-schema re-path: Get-BotModerationLevel must read the
    NESTED aISettings.contentModeration key (confirmed live 2026-06-13) and must return
    'Unknown' (never a false-Compliant) when the nested node is absent or only the
    legacy flat top-level key is present.

.NOTES
    Run with:
        Invoke-Pester -Path .\ModerationZoneCanonical.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $script:SolutionRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:GetExpected   = (Resolve-Path (Join-Path $script:SolutionRoot 'scripts' 'private' 'Get-ExpectedModerationLevel.ps1')).Path
    $script:BaselinePath  = (Resolve-Path (Join-Path $script:SolutionRoot 'templates' 'moderation-baseline.json')).Path
    $script:CMMClientPath = (Resolve-Path (Join-Path $script:SolutionRoot 'scripts' 'private' 'CMMClient.psm1')).Path

    Import-Module $script:CMMClientPath -Force

    $script:Baseline  = Get-Content $script:BaselinePath -Raw | ConvertFrom-Json
    $script:LevelRank = @{ 'Low' = 1; 'Medium' = 2; 'High' = 3 }
}

Describe 'Canonical zone semantics (Option A): strictest moderation maps to Zone 1 and 100000001' {

    It 'attaches the strictest minimum moderation to Zone 1 (policy table)' {
        $z1 = $script:LevelRank[$script:Baseline.zones.Zone1.minimumModerationLevel]
        $z2 = $script:LevelRank[$script:Baseline.zones.Zone2.minimumModerationLevel]
        $z3 = $script:LevelRank[$script:Baseline.zones.Zone3.minimumModerationLevel]
        $z1 | Should -BeGreaterOrEqual $z2
        $z1 | Should -BeGreaterOrEqual $z3
    }

    It 'sets Zone 1 (Enterprise) minimum to High' {
        $script:Baseline.zones.Zone1.minimumModerationLevel | Should -Be 'High'
    }

    It 'sets Zone 3 (Personal) as the least restrictive tier (Medium minimum)' {
        $script:Baseline.zones.Zone3.minimumModerationLevel | Should -Be 'Medium'
        $z1 = $script:LevelRank[$script:Baseline.zones.Zone1.minimumModerationLevel]
        $z3 = $script:LevelRank[$script:Baseline.zones.Zone3.minimumModerationLevel]
        $z3 | Should -BeLessThan $z1
    }

    It 'flags a Low-moderation agent in Zone 1 as a Critical, non-compliant violation' {
        $result = & $script:GetExpected -Zone 'Zone1' -ActualLevel 'Low'
        $result.IsCompliant       | Should -BeFalse
        $result.ExpectedLevel     | Should -Be 'High'
        $result.Severity          | Should -Be 'Critical'
        $result.RegulatoryContext | Should -Match 'FINRA 3110'
    }

    It 'treats a High-moderation agent in Zone 1 as compliant' {
        $result = & $script:GetExpected -Zone 'Zone1' -ActualLevel 'High'
        $result.IsCompliant | Should -BeTrue
    }

    It 'treats a Medium-moderation agent in Zone 3 (Personal) as compliant' {
        $result = & $script:GetExpected -Zone 'Zone3' -ActualLevel 'Medium'
        $result.IsCompliant | Should -BeTrue
    }

    It 'maps Zone 1 to 100000001 (strictest tier, lowest-numbered integer)' {
        InModuleScope CMMClient { $script:ZoneToInt['Zone1'] } | Should -Be 100000001
    }

    It 'maps Zone 2 to 100000002 and Zone 3 to 100000003' {
        InModuleScope CMMClient { $script:ZoneToInt['Zone2'] } | Should -Be 100000002
        InModuleScope CMMClient { $script:ZoneToInt['Zone3'] } | Should -Be 100000003
    }

    It 'round-trips 100000001 back to Zone 1' {
        InModuleScope CMMClient { $script:IntToZone[100000001] } | Should -Be 'Zone1'
    }
}

Describe 'Detector re-path: Get-BotModerationLevel reads nested aISettings.contentModeration defensively' {

    It 'returns the level from the nested aISettings.contentModeration key' {
        $bot = [PSCustomObject]@{ name = 'bot-nested'; configuration = '{"aISettings":{"contentModeration":"High"}}' }
        Get-BotModerationLevel -Bot $bot | Should -Be 'High'
    }

    It 'returns Unknown when aISettings is present but contentModeration is absent (never a false Compliant)' {
        $bot = [PSCustomObject]@{ name = 'bot-absent'; configuration = '{"aISettings":{"useModelKnowledge":true}}' }
        Get-BotModerationLevel -Bot $bot | Should -Be 'Unknown'
    }

    It 'returns Unknown for a legacy flat top-level ContentModeration key (no tautological green)' {
        $bot = [PSCustomObject]@{ name = 'bot-flat'; configuration = '{"ContentModeration":"High"}' }
        Get-BotModerationLevel -Bot $bot | Should -Be 'Unknown'
    }

    It 'returns Unknown when configuration is missing entirely' {
        $bot = [PSCustomObject]@{ name = 'bot-empty'; configuration = $null }
        Get-BotModerationLevel -Bot $bot | Should -Be 'Unknown'
    }
}
