#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 tests for Convert-AttestationToCapabilityRows.ps1 - the owner-attestation
    converter that turns owners' yes/no People-capability responses into the CAI
    People-capability artifact shape the Find-No-Filter (FNF) People-Sweep lens consumes,
    stamping peopleCapableSource = attested.

.DESCRIPTION
    Both the converter and the FNF lens are defined with top-level functions and a guarded
    main, so each is dot-sourced with a placeholder argument: the functions load at script
    scope and the main body never runs. The converter functions are exercised directly over
    in-memory responses and over temp CSV/JSON files written into $TestDrive.

    The pivotal Describe ("schema compatibility with the FNF lens") closes the loop: it builds
    an attested artifact, round-trips it through JSON exactly as the lens would read it from
    -CapabilityArtifactPath, then drives the lens's own Get-FnfPeopleCapabilitySource and
    Resolve-FnfPeopleAgentSet over it - proving an attested row keys on the REAL agent id
    (never the provisional stem) and is classified peopleCapableSource = attested.

.NOTES
    Run with: Invoke-Pester -Path .\ConvertAttestationToCapabilityRows.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $script:ConverterScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Convert-AttestationToCapabilityRows.ps1')).Path
    $script:FnfScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Get-FnfPeopleSweepReport.ps1')).Path

    # Dot-source the converter (guarded main) so its functions + $script:Att* constants load.
    . $script:ConverterScript -ResponsePath 'placeholder'
    # Dot-source the lens (guarded main) so Get-FnfPeopleCapabilitySource / Resolve-FnfPeopleAgentSet
    # and $script:PeopleFeatureType load into the same scope for the cross-check Describe.
    . $script:FnfScript -CapabilityArtifactPath 'placeholder' -AudienceArtifactPath 'placeholder'

    $script:RunId = 'fnf-attestation-test'
    $script:Source = 'Owner Attestation'

    # The attested confidence/source markers the lens classifier matches on (?i)attest.
    $script:ExpectedConfidence = 'Attested (owner attestation)'
    $script:ExpectedFeatureType = 'People (Org Chart & Profile)'
}

Describe 'ConvertTo-FnfAttestationBool - answer-token normalization' {
    It 'maps affirmative token <Token> to $true' -ForEach @(
        @{ Token = 'yes' }, @{ Token = 'Yes' }, @{ Token = 'Y' }, @{ Token = 'true' },
        @{ Token = '1' }, @{ Token = 'enabled' }, @{ Token = ' people-capable ' }
    ) {
        ConvertTo-FnfAttestationBool -Value $Token | Should -BeTrue
    }

    It 'maps negative token <Token> to $false' -ForEach @(
        @{ Token = 'no' }, @{ Token = 'No' }, @{ Token = 'N' }, @{ Token = 'false' },
        @{ Token = '0' }, @{ Token = 'disabled' }, @{ Token = 'not-capable' }
    ) {
        ConvertTo-FnfAttestationBool -Value $Token | Should -BeFalse
    }

    It 'returns $null for an unrecognized token <Token> (never silently "no")' -ForEach @(
        @{ Token = 'maybe' }, @{ Token = '' }, @{ Token = '   ' }, @{ Token = 'tbd' }
    ) {
        $null -eq (ConvertTo-FnfAttestationBool -Value $Token) | Should -BeTrue
    }

    It 'returns $null for a null input' {
        $null -eq (ConvertTo-FnfAttestationBool -Value $null) | Should -BeTrue
    }
}

Describe 'New-FnfAttestedCapabilityRow - row shape matches the CAI People row the lens consumes' {
    BeforeAll {
        $script:Row = New-FnfAttestedCapabilityRow -AgentId 'bot-REAL-1001' -AgentName 'Org Helper' `
            -EnvironmentId 'env-001' -IsEnabled $true -RunId $script:RunId -DetectionSource $script:Source `
            -AttestedBy 'owner@contoso.com' -AttestedAt '2026-05-19T12:00:00Z' -AttestationId 'TKT-77' -Notes 'confirmed'
    }

    It 'keys on the real agent id (not a provisional stem)' {
        $script:Row['fsi_agentid'] | Should -Be 'bot-REAL-1001'
        $script:Row['fsi_agentid'] | Should -Not -Be 'declarativeAgent'
    }

    It 'carries the People feature-type label the lens selects on' {
        $script:Row['fsi_featuretype'] | Should -Be $script:ExpectedFeatureType
    }

    It 'is non-provisional so the lens skips id-map reconciliation' {
        $script:Row['fsi_agentrefprovisional'] | Should -BeFalse
    }

    It 'stamps the attested provenance markers the lens classifier reads' {
        $script:Row['fsi_detectionconfidence'] | Should -Be $script:ExpectedConfidence
        $script:Row['fsi_detectionsource'] | Should -Be $script:Source
        $script:Row['fsi_detectionconfidence'] | Should -Match '(?i)attest'
    }

    It 'mirrors the CAI capability source-object identity' {
        $script:Row['fsi_sourceobjectid'] | Should -Be 'capability:People'
        $script:Row['fsi_sourceobjectname'] | Should -Be 'People'
        $script:Row['fsi_relationshipname'] | Should -Be 'declarativeAgent.capabilities'
    }

    It 'sets fsi_isenabled from the attested answer' {
        $script:Row['fsi_isenabled'] | Should -BeTrue
        $disabled = New-FnfAttestedCapabilityRow -AgentId 'bot-REAL-1002' -IsEnabled $false `
            -RunId $script:RunId -DetectionSource $script:Source
        $disabled['fsi_isenabled'] | Should -BeFalse
    }

    It 'emits fsi_detectiondetail as valid JSON recording the attestation provenance' {
        $detail = $script:Row['fsi_detectiondetail'] | ConvertFrom-Json
        $detail.attestedVia | Should -Be 'owner-attestation'
        $detail.attestedBy | Should -Be 'owner@contoso.com'
        $detail.attestationId | Should -Be 'TKT-77'
    }

    It 'falls back to the agent id for the display name when none is given' {
        $r = New-FnfAttestedCapabilityRow -AgentId 'bot-REAL-1003' -IsEnabled $true `
            -RunId $script:RunId -DetectionSource $script:Source
        $r['fsi_name'] | Should -Be "$($script:ExpectedFeatureType): bot-REAL-1003"
    }
}

Describe 'ConvertTo-FnfAttestationArtifact - validation + artifact assembly' {
    It 'produces the { schemaVersion, summary, agents, features } artifact shape' {
        $art = ConvertTo-FnfAttestationArtifact -Response @(
            [pscustomobject]@{ agentId = 'bot-REAL-1'; peopleCapable = 'yes' }
        ) -RunId $script:RunId -DetectionSource $script:Source
        $art.schemaVersion | Should -Be '0.2.0-preview'
        $art.PSObject.Properties.Name | Should -Contain 'summary'
        $art.PSObject.Properties.Name | Should -Contain 'agents'
        $art.PSObject.Properties.Name | Should -Contain 'features'
        $art.features.Count | Should -Be 1
        $art.summary.peopleDetected | Should -Be 1
    }

    It 'rejects a row with a missing agent id' {
        { ConvertTo-FnfAttestationArtifact -Response @(
                [pscustomobject]@{ agentId = ''; peopleCapable = 'yes' }
            ) -RunId $script:RunId -DetectionSource $script:Source } |
            Should -Throw '*missing agentId*'
    }

    It 'rejects the provisional manifest stem "declarativeAgent" as an agent id' {
        { ConvertTo-FnfAttestationArtifact -Response @(
                [pscustomobject]@{ agentId = 'declarativeAgent'; peopleCapable = 'yes' }
            ) -RunId $script:RunId -DetectionSource $script:Source } |
            Should -Throw '*provisional manifest stem*'
    }

    It 'rejects an unrecognized peopleCapable answer (never coerces to "no")' {
        { ConvertTo-FnfAttestationArtifact -Response @(
                [pscustomobject]@{ agentId = 'bot-REAL-1'; peopleCapable = 'maybe' }
            ) -RunId $script:RunId -DetectionSource $script:Source } |
            Should -Throw '*unrecognized peopleCapable*'
    }

    It 'rejects a DetectionSource that would not classify as attested' {
        { ConvertTo-FnfAttestationArtifact -Response @(
                [pscustomobject]@{ agentId = 'bot-REAL-1'; peopleCapable = 'yes' }
            ) -RunId $script:RunId -DetectionSource 'Manifest Scan' } |
            Should -Throw "*must contain 'attest'*"
    }

    It 'collects all row errors and reports them together' {
        { ConvertTo-FnfAttestationArtifact -Response @(
                [pscustomobject]@{ agentId = ''; peopleCapable = 'yes' }
                [pscustomobject]@{ agentId = 'bot-REAL-2'; peopleCapable = 'maybe' }
            ) -RunId $script:RunId -DetectionSource $script:Source } |
            Should -Throw '*2 invalid row(s)*'
    }

    It 'rejects conflicting duplicate responses for one agent' {
        { ConvertTo-FnfAttestationArtifact -Response @(
                [pscustomobject]@{ agentId = 'bot-REAL-9'; peopleCapable = 'yes' }
                [pscustomobject]@{ agentId = 'bot-REAL-9'; peopleCapable = 'no' }
            ) -RunId $script:RunId -DetectionSource $script:Source } |
            Should -Throw '*conflicting attestation responses*'
    }

    It 'collapses agreeing duplicate responses for one agent' {
        $art = ConvertTo-FnfAttestationArtifact -Response @(
            [pscustomobject]@{ agentId = 'bot-REAL-9'; peopleCapable = 'yes' }
            [pscustomobject]@{ agentId = 'BOT-real-9'; peopleCapable = 'true' }
        ) -RunId $script:RunId -DetectionSource $script:Source
        $art.summary.uniqueAgents | Should -Be 1
        $art.summary.duplicatesCollapsed | Should -Be 1
        $art.features.Count | Should -Be 1
    }

    It 'emits a "no" response as a declared-but-disabled row by default (full audit trail)' {
        $art = ConvertTo-FnfAttestationArtifact -Response @(
            [pscustomobject]@{ agentId = 'bot-REAL-1'; peopleCapable = 'yes' }
            [pscustomobject]@{ agentId = 'bot-REAL-2'; peopleCapable = 'no' }
        ) -RunId $script:RunId -DetectionSource $script:Source
        $art.features.Count | Should -Be 2
        $art.summary.peopleDetected | Should -Be 1
        $art.summary.notPeopleCapableCount | Should -Be 1
        ($art.features | Where-Object { $_['fsi_agentid'] -eq 'bot-REAL-2' })['fsi_isenabled'] | Should -BeFalse
    }

    It 'omits "no" rows entirely under -PeopleCapableOnly' {
        $art = ConvertTo-FnfAttestationArtifact -Response @(
            [pscustomobject]@{ agentId = 'bot-REAL-1'; peopleCapable = 'yes' }
            [pscustomobject]@{ agentId = 'bot-REAL-2'; peopleCapable = 'no' }
        ) -RunId $script:RunId -DetectionSource $script:Source -PeopleCapableOnly
        $art.features.Count | Should -Be 1
        $art.features[0]['fsi_agentid'] | Should -Be 'bot-REAL-1'
        $art.summary.peopleCapableOnly | Should -BeTrue
    }

    It 'applies the default environment id when a response omits one' {
        $art = ConvertTo-FnfAttestationArtifact -Response @(
            [pscustomobject]@{ agentId = 'bot-REAL-1'; peopleCapable = 'yes' }
        ) -RunId $script:RunId -DetectionSource $script:Source -DefaultEnvironmentId 'env-default'
        $art.features[0]['fsi_environmentid'] | Should -Be 'env-default'
    }
}

Describe 'Get-FnfAttestationResponse - CSV and JSON intake' {
    It 'reads a CSV of responses' {
        $csv = Join-Path $TestDrive 'responses.csv'
        @(
            'agentId,agentName,peopleCapable'
            'bot-REAL-1,Org Helper,yes'
            'bot-REAL-2,Sales Bot,no'
        ) | Set-Content -LiteralPath $csv -Encoding UTF8
        $rows = Get-FnfAttestationResponse -Path $csv
        $rows.Count | Should -Be 2
        $rows[0].agentId | Should -Be 'bot-REAL-1'
    }

    It 'reads a bare JSON array' {
        $json = Join-Path $TestDrive 'bare.json'
        '[{"agentId":"bot-REAL-1","peopleCapable":"yes"}]' | Set-Content -LiteralPath $json -Encoding UTF8
        $rows = Get-FnfAttestationResponse -Path $json
        $rows.Count | Should -Be 1
        $rows[0].peopleCapable | Should -Be 'yes'
    }

    It 'unwraps a { responses: [...] } JSON wrapper' {
        $json = Join-Path $TestDrive 'wrapped.json'
        '{"responses":[{"agentId":"bot-REAL-1","peopleCapable":"yes"},{"agentId":"bot-REAL-2","peopleCapable":"no"}]}' |
            Set-Content -LiteralPath $json -Encoding UTF8
        (Get-FnfAttestationResponse -Path $json).Count | Should -Be 2
    }

    It 'unwraps a { value: [...] } OData envelope' {
        $json = Join-Path $TestDrive 'value.json'
        '{"value":[{"agentId":"bot-REAL-1","peopleCapable":"yes"}]}' | Set-Content -LiteralPath $json -Encoding UTF8
        (Get-FnfAttestationResponse -Path $json).Count | Should -Be 1
    }

    It 'throws when the response file does not exist' {
        { Get-FnfAttestationResponse -Path (Join-Path $TestDrive 'nope.csv') } | Should -Throw '*not found*'
    }

    It 'converts an imported CSV end-to-end into an attested artifact' {
        $csv = Join-Path $TestDrive 'e2e.csv'
        @(
            'agentId,peopleCapable'
            'bot-REAL-1,yes'
            'bot-REAL-2,no'
        ) | Set-Content -LiteralPath $csv -Encoding UTF8
        $rows = Get-FnfAttestationResponse -Path $csv
        $art = ConvertTo-FnfAttestationArtifact -Response $rows -RunId $script:RunId -DetectionSource $script:Source
        $art.summary.uniqueAgents | Should -Be 2
        $art.summary.peopleDetected | Should -Be 1
    }
}

Describe 'Schema compatibility with the FNF lens (attested rows join the same report)' {
    BeforeAll {
        # Build an attested artifact: one People-capable agent + one not-capable agent.
        $artObj = ConvertTo-FnfAttestationArtifact -Response @(
            [pscustomobject]@{ agentId = 'bot-REAL-AAA'; agentName = 'Org Helper'; peopleCapable = 'yes'; environmentId = 'env-1' }
            [pscustomobject]@{ agentId = 'bot-REAL-BBB'; agentName = 'Sales Bot'; peopleCapable = 'no'; environmentId = 'env-1' }
        ) -RunId $script:RunId -DetectionSource $script:Source

        # Round-trip through JSON exactly as the lens reads it from -CapabilityArtifactPath.
        $artPath = Join-Path $TestDrive 'cai-people-attested.json'
        $artObj | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $artPath -Encoding UTF8
        $script:LensArtifact = Get-Content -LiteralPath $artPath -Raw | ConvertFrom-Json
    }

    It 'the lens classifier reports peopleCapableSource = attested for an attested row' {
        $enabled = $script:LensArtifact.features | Where-Object { $_.fsi_agentid -eq 'bot-REAL-AAA' }
        Get-FnfPeopleCapabilitySource -Feature $enabled | Should -Be 'attested'
    }

    It 'the lens resolver selects the People-capable attested agent, keyed on the REAL agent id' {
        $set = Resolve-FnfPeopleAgentSet -CapabilityArtifact $script:LensArtifact
        $set.Resolved.Count | Should -Be 1
        $set.Resolved[0].agentId | Should -Be 'bot-REAL-AAA'
        $set.Resolved[0].agentId | Should -Not -Be 'declarativeAgent'
        $set.Resolved[0].source | Should -Be 'attested'
    }

    It 'the resolved attested agent is non-provisional (no id-map reconciliation needed)' {
        $set = Resolve-FnfPeopleAgentSet -CapabilityArtifact $script:LensArtifact
        $set.Resolved[0].reconciled | Should -BeFalse
        $set.ProvisionalUnreconciled.Count | Should -Be 0
        $set.Collisions.Count | Should -Be 0
    }

    It 'the lens skips the not-capable (disabled) attested row' {
        $set = Resolve-FnfPeopleAgentSet -CapabilityArtifact $script:LensArtifact
        ($set.Resolved | Where-Object { $_.agentId -eq 'bot-REAL-BBB' }) | Should -BeNullOrEmpty
        $set.SourceMap['bot-REAL-AAA'] | Should -Be 'attested'
    }

    It 'the attested feature carries the exact feature-type label the lens selects on' {
        $script:LensArtifact.features[0].fsi_featuretype | Should -Be $script:PeopleFeatureType
    }
}
