BeforeAll {
    $solutionRoot = Split-Path -Parent $PSScriptRoot
    $scriptsRoot = Join-Path $solutionRoot 'scripts'

    . (Join-Path $scriptsRoot 'Get-AgentGenAISettings.ps1')
    Import-Module (Join-Path $scriptsRoot 'private\GACClient.psm1') -Force

    $script:previousModulePath = $env:PSModulePath
    $script:stubModuleRoot = Join-Path $TestDrive 'SharedModules'
    $stubModuleVersionRoot = Join-Path $script:stubModuleRoot 'MSAL.PS\4.37.0'
    New-Item -ItemType Directory -Path $stubModuleVersionRoot -Force | Out-Null
    @(
        'function Get-MsalToken {'
        "    [PSCustomObject]@{ AccessToken = 'test-token' }"
        '}'
        ''
        'Export-ModuleMember -Function Get-MsalToken'
    ) | Set-Content -Path (Join-Path $stubModuleVersionRoot 'MSAL.PS.psm1')
    New-ModuleManifest `
        -Path (Join-Path $stubModuleVersionRoot 'MSAL.PS.psd1') `
        -RootModule 'MSAL.PS.psm1' `
        -ModuleVersion '4.37.0' `
        -FunctionsToExport 'Get-MsalToken'
    $env:PSModulePath = "$script:stubModuleRoot;$script:previousModulePath"
    Import-Module (Join-Path $stubModuleVersionRoot 'MSAL.PS.psd1') -Force

    $azModuleVersionRoot = Join-Path $script:stubModuleRoot 'Az.Accounts\2.0.0'
    New-Item -ItemType Directory -Path $azModuleVersionRoot -Force | Out-Null
    @(
        'function Get-AzContext { [PSCustomObject]@{ Account = [PSCustomObject]@{ Id = ''operator@example.com'' }; Tenant = [PSCustomObject]@{ Id = ''tenant-id'' } } }'
        'function Get-AzAccessToken { [PSCustomObject]@{ Token = ''test-token''; ExpiresOn = (Get-Date).AddHours(1) } }'
        ''
        'Export-ModuleMember -Function Get-AzContext, Get-AzAccessToken'
    ) | Set-Content -Path (Join-Path $azModuleVersionRoot 'Az.Accounts.psm1')
    New-ModuleManifest `
        -Path (Join-Path $azModuleVersionRoot 'Az.Accounts.psd1') `
        -RootModule 'Az.Accounts.psm1' `
        -ModuleVersion '2.0.0' `
        -FunctionsToExport 'Get-AzContext', 'Get-AzAccessToken'
    Import-Module (Join-Path $azModuleVersionRoot 'Az.Accounts.psd1') -Force

    $script:capturedUris = @()
    $script:componentResponse = [PSCustomObject]@{ value = @() }

    Mock Get-AdminPowerAppEnvironment {
        [PSCustomObject]@{
            EnvironmentName = 'env-1'
            DisplayName = 'Test-zone1'
            EnvironmentType = 'Production'
            CreatedTime = (Get-Date).AddDays(-10)
            Internal = [PSCustomObject]@{
                properties = [PSCustomObject]@{
                    linkedEnvironmentMetadata = [PSCustomObject]@{
                        instanceUrl = 'https://env.crm.dynamics.com'
                    }
                }
            }
        }
    }

    Mock Get-AzContext {
        [PSCustomObject]@{
            Account = [PSCustomObject]@{ Id = 'operator@example.com' }
            Tenant = [PSCustomObject]@{ Id = 'tenant-id' }
        }
    }

    Mock Get-AzAccessToken {
        [PSCustomObject]@{
            Token = 'test-token'
            ExpiresOn = (Get-Date).AddHours(1)
        }
    }

    Mock Get-AgentBots {
        [PSCustomObject]@{
            botid = '11111111-1111-1111-1111-111111111111'
            name = 'Topic V2 bot'
            statecode = 0
            publishedon = (Get-Date).AddDays(-1)
        }
    }

    Mock Invoke-RestMethod {
        param([string]$Uri)
        $script:capturedUris += $Uri
        if ($Uri -like '*botcomponents*') {
            return $script:componentResponse
        }

        [PSCustomObject]@{ value = @() }
    }
}

AfterAll {
    $env:PSModulePath = $script:previousModulePath
}

Describe 'Topic V2 detection' {
    BeforeEach {
        $script:capturedUris = @()
        $script:componentResponse = [PSCustomObject]@{ value = @() }
    }

    It 'queries topic components for both content forms and stable component identity' {
        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')
        $componentUri = $script:capturedUris | Where-Object { $_ -like '*botcomponents*' } | Select-Object -First 1

        $componentUri | Should -Not -BeNullOrEmpty
        $componentUri | Should -Match '\$select=name,data,content,componenttype,botcomponentid'
        $componentUri | Should -Match 'componenttype eq 0 or componenttype eq 9'
        $result.Count | Should -Be 1
    }

    It 'detects SearchAndSummarizeContent from type-9 data-only YAML when an optional parser is available' {
        function ConvertFrom-Yaml {
            param([string]$Yaml)
            [PSCustomObject]@{
                kind = if ($Yaml -match 'SearchAndSummarizeContent') {
                    'SearchAndSummarizeContent'
                } else {
                    'OrdinaryTopic'
                }
            }
        }

        try {
            $script:componentResponse = [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Modern topic'
                        data = "kind: SearchAndSummarizeContent`n"
                        content = ''
                        componenttype = 9
                        botcomponentid = '22222222-2222-2222-2222-222222222222'
                    }
                )
            }

            $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

            $result[0].GenerativeAnswersNodeCount | Should -Be 1
            $result[0].TopicAssessmentStatus | Should -Be 'Determined'
        } finally {
            Remove-Item Function:\ConvertFrom-Yaml -ErrorAction SilentlyContinue
        }
    }

    It 'preserves legacy type-0 JSON content detection' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Legacy topic'
                    data = ' '
                    content = '{"kind":"GenerativeAnswers"}'
                    componenttype = 0
                    botcomponentid = '33333333-3333-3333-3333-333333333333'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 1
        $result[0].TopicAssessmentStatus | Should -Be 'Determined'
    }

    It 'treats an empty returned topic collection as a determined legitimate zero' {
        $script:componentResponse = [PSCustomObject]@{
            value = @()
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 0
        $result[0].TopicAssessmentStatus | Should -Be 'Determined'
        $result[0].TopicAssessmentDetails | Should -Be 'No topic components were returned.'
    }

    It 'does not treat parsed empty, null, scalar, or unrecognized payloads as a determined zero' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Empty object'
                    data = '{}'
                    content = ''
                    componenttype = 9
                    botcomponentid = '10101010-1010-1010-1010-101010101010'
                },
                [PSCustomObject]@{
                    name = 'Null payload'
                    data = 'null'
                    content = ''
                    componenttype = 9
                    botcomponentid = '20202020-2020-2020-2020-202020202020'
                },
                [PSCustomObject]@{
                    name = 'Scalar payload'
                    data = '"not a topic"'
                    content = ''
                    componenttype = 0
                    botcomponentid = '30303030-3030-3030-3030-303030303030'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 0
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $result[0].TopicAssessmentDetails | Should -Match 'recognizable topic/node structure'
    }

    It 'keeps a valid action-free AdaptiveDialog as a determined zero' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Action-free dialog'
                    data = '{"kind":"AdaptiveDialog","nodes":[]}'
                    content = ''
                    componenttype = 9
                    botcomponentid = '40404040-4040-4040-4040-404040404040'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 0
        $result[0].TopicAssessmentStatus | Should -Be 'Determined'
    }

    It 'applies the structure requirement to parsed JSON arrays' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Unrecognized JSON array'
                    data = '[{},{"value":"not a topic"}]'
                    content = ''
                    componenttype = 9
                    botcomponentid = '50505050-5050-5050-5050-505050505050'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 0
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
    }

    It 'applies the structure requirement to parsed YAML arrays' {
        function ConvertFrom-Yaml {
            param([string]$Yaml)
            [void]$Yaml
            @(
                [PSCustomObject]@{ value = 'not a topic' }
                [PSCustomObject]@{ anotherValue = 'still not a topic' }
            )
        }

        try {
            $script:componentResponse = [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Unrecognized YAML array'
                        data = '- value: not a topic'
                        content = ''
                        componenttype = 9
                        botcomponentid = '60606060-6060-6060-6060-606060606060'
                    }
                )
            }

            $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

            $result[0].GenerativeAnswersNodeCount | Should -Be 0
            $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        } finally {
            Remove-Item Function:\ConvertFrom-Yaml -ErrorAction SilentlyContinue
        }
    }

    It 'reports a topic query failure as indeterminate' {
        Mock Invoke-RestMethod {
            param([string]$Uri)
            if ($Uri -like '*botcomponents*') {
                throw 'simulated topic query failure'
            }

            [PSCustomObject]@{ value = @() }
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $result[0].TopicAssessmentDetails | Should -Match 'component query failed'
    }

    It 'uses populated data first, falls back from whitespace data, and never falls back after malformed data' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Data wins'
                    data = '{"kind":"Other"}'
                    content = '{"kind":"SearchAndSummarizeContent"}'
                    componenttype = 9
                    botcomponentid = '44444444-4444-4444-4444-444444444444'
                },
                [PSCustomObject]@{
                    name = 'Whitespace fallback'
                    data = '   '
                    content = '{"kind":"GenerativeAnswers"}'
                    componenttype = 0
                    botcomponentid = '55555555-5555-5555-5555-555555555555'
                },
                [PSCustomObject]@{
                    name = 'Malformed authoritative data'
                    data = '{"kind":'
                    content = '{"kind":"GenerativeAnswers"}'
                    componenttype = 9
                    botcomponentid = '66666666-6666-6666-6666-666666666666'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 1
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
    }

    It 'uses positive regex evidence but never reports a clean zero when the optional YAML parser is unavailable' {
        Mock Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' } {}
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Unparsed positive YAML'
                    data = "kind: SearchAndSummarizeContent`n"
                    content = ''
                    componenttype = 9
                    botcomponentid = '77777777-7777-7777-7777-777777777777'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 1
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
    }

    It 'counts safe positive regex occurrences while keeping the assessment indeterminate' {
        Mock Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' } {}
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Unparsed multiple modern nodes'
                    data = "kind: SearchAndSummarizeContent`n---`nkind: SearchAndSummarizeContent`n"
                    content = ''
                    componenttype = 9
                    botcomponentid = '12121212-1212-1212-1212-121212121212'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 2
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
    }

    It 'keeps an unrecognized YAML payload indeterminate with a zero count when no parser is available' {
        Mock Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' } {}
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Unrecognized YAML'
                    data = "kind: OrdinaryTopic`n"
                    content = ''
                    componenttype = 9
                    botcomponentid = '88888888-8888-8888-8888-888888888888'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 0
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
    }

    It 'marks blank, malformed, and mixed topic payloads indeterminate' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Blank topic'
                    data = ''
                    content = ' '
                    componenttype = 0
                    botcomponentid = '99999999-9999-9999-9999-999999999999'
                },
                [PSCustomObject]@{
                    name = 'Malformed topic'
                    data = '{"kind":'
                    content = ''
                    componenttype = 9
                    botcomponentid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                },
                [PSCustomObject]@{
                    name = 'Valid no-node topic'
                    data = '{"kind":"OrdinaryTopic"}'
                    content = ''
                    componenttype = 0
                    botcomponentid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 0
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $result[0].TopicAssessmentDetails | Should -Match 'no nonblank|could not be parsed'
    }

    It 'does not classify page one as complete when the topic response has a next link' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'First page topic'
                    data = '{"kind":"SearchAndSummarizeContent"}'
                    content = ''
                    componenttype = 9
                    botcomponentid = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
                }
            )
            '@odata.nextLink' = 'https://env.crm.dynamics.com/api/data/v9.2/botcomponents?$skiptoken=next'
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 1
        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $result[0].TopicAssessmentDetails | Should -Match '@odata.nextLink'
    }

    It 'recursively detects modern nodes and knowledge-source signals in parsed content' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Nested topic'
                    data = '{"nodes":[{"kind":"SearchAndSummarizeContent","knowledgeSources":[{"id":"one"},{"id":"two"}]}]}'
                    content = ''
                    componenttype = 9
                    botcomponentid = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 1
        $result[0].KnowledgeSourceCount | Should -Be 2
        $result[0].TopicAssessmentStatus | Should -Be 'Determined'
    }

    It 'counts each SearchAndSummarizeContent node in one topic' {
        $script:componentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Multiple modern nodes'
                    data = '{"kind":"AdaptiveDialog","nodes":[{"kind":"SearchAndSummarizeContent"},{"kind":"SearchAndSummarizeContent"}]}'
                    content = ''
                    componenttype = 9
                    botcomponentid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
                }
            )
        }

        $result = @(Get-AgentGenAISettings -IncludeEnvironments 'env-1')

        $result[0].GenerativeAnswersNodeCount | Should -Be 2
        $result[0].TopicAssessmentStatus | Should -Be 'Determined'
    }
}

Describe 'Topic assessment compliance semantics' {
    BeforeAll {
        . (Join-Path $scriptsRoot 'Compare-GenAIConfigCompliance.ps1')
    }

    It 'reports a prohibited positive node as a policy violation' {
        $agent = [PSCustomObject]@{
            AgentId                    = '11111111-1111-1111-1111-111111111111'
            AgentName                  = 'Positive node'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 1
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Determined'
            TopicAssessmentDetails     = 'All topics parsed.'
            AgentStatus                = 'Active'
        }

        $result = @(Compare-GenAIConfigCompliance -InputObject $agent)

        $result[0].IsCompliant | Should -BeFalse
        $result[0].ViolationType | Should -Be 'GenerativeAnswersNotAllowed'
        $result[0].TopicAssessmentStatus | Should -Be 'Determined'
    }

    It 'treats a parsed legitimate zero as compliant' {
        $agent = [PSCustomObject]@{
            AgentId                    = '22222222-2222-2222-2222-222222222222'
            AgentName                  = 'Parsed zero'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 0
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Determined'
            TopicAssessmentDetails     = 'All topics parsed; no generative-answer signals found.'
            AgentStatus                = 'Active'
        }

        $result = @(Compare-GenAIConfigCompliance -InputObject $agent -IncludeCompliant)

        $result[0].IsCompliant | Should -BeTrue
        $result[0].ViolationDetails.Count | Should -Be 0
    }

    It 'adds an indeterminate-topic warning even when other configuration signals are resolved' {
        $agent = [PSCustomObject]@{
            AgentId                    = '33333333-3333-3333-3333-333333333333'
            AgentName                  = 'Unknown topic posture'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 0
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Indeterminate'
            TopicAssessmentDetails     = 'One topic was malformed.'
            AgentStatus                = 'Active'
        }

        $result = @(Compare-GenAIConfigCompliance -InputObject $agent)

        $result[0].IsCompliant | Should -BeFalse
        $result[0].ViolationType | Should -Be 'IndeterminateTopicAssessment'
        $result[0].Severity | Should -Be 'Warning'
        @($result[0].ViolationDetails | Where-Object ViolationType -eq 'IndeterminateTopicAssessment').Count | Should -Be 1
    }

    It 'retains a positive policy violation alongside the indeterminate-topic warning' {
        $agent = [PSCustomObject]@{
            AgentId                    = '44444444-4444-4444-4444-444444444444'
            AgentName                  = 'Positive and unknown'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 1
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Indeterminate'
            TopicAssessmentDetails     = 'Parser unavailable.'
            AgentStatus                = 'Active'
        }

        $result = @(Compare-GenAIConfigCompliance -InputObject $agent)

        @($result[0].ViolationDetails | Where-Object ViolationType -eq 'GenerativeAnswersNotAllowed').Count | Should -Be 1
        @($result[0].ViolationDetails | Where-Object ViolationType -eq 'IndeterminateTopicAssessment').Count | Should -Be 1
        $result[0].Severity | Should -Be 'High'
        $result[0].ViolationType | Should -Be 'GenerativeAnswersNotAllowed'
    }
}

Describe 'Topic assessment persistence projection' {
    BeforeAll {
        . (Join-Path $scriptsRoot 'Test-GenAIConfigCompliance.ps1')
    }

    BeforeEach {
        Mock Import-Module {}
        Mock Connect-GACDataverse -ModuleName GACClient {}
        Mock Get-GACConnection -ModuleName GACClient {
            [PSCustomObject]@{
                DataverseUrl = 'https://governance.crm.dynamics.com'
                AccessToken  = 'test-token'
                IsConnected  = $true
            }
        }
        Mock Get-GACEnvironmentVariable -ModuleName GACClient {
            param([string]$Name, $DefaultValue)
            [void]$Name
            return $DefaultValue
        }
        Mock Invoke-DataverseRequest -ModuleName GACClient {
            [PSCustomObject]@{ value = @() }
        }
        Mock Invoke-RestMethod -ModuleName GACClient {
            throw 'Unexpected live Dataverse request in offline persistence test.'
        }
    }

    It 'projects an indeterminate topic assessment through the existing violation writer fields and Object output' {
        $script:writtenViolation = $null
        $agent = [PSCustomObject]@{
            AgentId                    = '55555555-5555-5555-5555-555555555555'
            AgentName                  = 'Persisted indeterminate'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 0
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Indeterminate'
            TopicAssessmentDetails     = 'Topic data was malformed and the optional parser was unavailable.'
            AgentStatus                = 'Active'
        }

        Mock Get-AgentGenAISettings { $agent }
        Mock Write-GACValidationHistory {}
        Mock Write-GACViolation {
            param([hashtable]$Violation)
            $script:writtenViolation = $Violation
        }

        $result = @(Test-GenAIConfigCompliance `
            -OutputFormat Object `
            -IncludeCompliant `
            -PersistResults `
            -DataverseUrl 'https://governance.crm.dynamics.com' `
            -DataverseToken 'test-token')

        $result[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $result[0].TopicAssessmentDetails | Should -Match 'malformed'
        $script:writtenViolation.FeatureType | Should -Be 'GenerativeAnswersNode'
        $script:writtenViolation.ExpectedState | Should -Be 'Determined'
        $script:writtenViolation.ActualState | Should -Be 'Indeterminate: Topic data was malformed and the optional parser was unavailable.'
    }

    It 'persists every coexisting violation detail with bounded Dataverse fields' {
        $script:writtenViolations = [System.Collections.Generic.List[object]]::new()
        $longDetails = 'Topic assessment detail. ' * 300
        $agent = [PSCustomObject]@{
            AgentId                    = '77777777-7777-7777-7777-777777777777'
            AgentName                  = 'Persisted coexisting violations'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 2
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Indeterminate'
            TopicAssessmentDetails     = $longDetails
            AgentStatus                = 'Active'
        }

        Mock Get-AgentGenAISettings { $agent }
        Mock Write-GACValidationHistory {}
        Mock Write-GACViolation {
            param([hashtable]$Violation)
            [void]$script:writtenViolations.Add($Violation)
        }

        $result = @(Test-GenAIConfigCompliance `
            -OutputFormat Object `
            -IncludeCompliant `
            -PersistResults `
            -DataverseUrl 'https://governance.crm.dynamics.com' `
            -DataverseToken 'test-token')

        $result[0].ViolationType | Should -Be 'GenerativeAnswersNotAllowed'
        $script:writtenViolations.Count | Should -Be 2
        Should -Invoke Write-GACViolation -Times 2 -Exactly
        Should -Invoke Invoke-RestMethod -ModuleName GACClient -Times 0 -Exactly
        @($script:writtenViolations | Where-Object ActualState -like 'Indeterminate:*').Count | Should -Be 1
        @($script:writtenViolations | Where-Object ExpectedState -eq 'Not permitted').Count | Should -Be 1

        foreach ($written in $script:writtenViolations) {
            ([string]$written.RegulatoryContext).Length | Should -BeLessOrEqual 2000
            ([string]$written.ExpectedState).Length | Should -BeLessOrEqual 500
            ([string]$written.ActualState).Length | Should -BeLessOrEqual 500
        }

        $script:writtenViolations |
            Where-Object ActualState -like 'Indeterminate:*' |
            Select-Object -ExpandProperty ActualState |
            Should -Match '^Indeterminate:'
    }

    It 'does not swallow an individual violation writer failure' {
        $agent = [PSCustomObject]@{
            AgentId                    = '78787878-7878-7878-7878-787878787878'
            AgentName                  = 'Writer failure'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 1
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Determined'
            TopicAssessmentDetails     = 'All topics parsed.'
            AgentStatus                = 'Active'
        }

        Mock Get-AgentGenAISettings { $agent }
        Mock Write-GACValidationHistory {}
        Mock Write-GACViolation {
            throw 'simulated violation writer failure'
        }

        {
            Test-GenAIConfigCompliance `
                -OutputFormat Object `
                -IncludeCompliant `
                -PersistResults `
                -DataverseUrl 'https://governance.crm.dynamics.com' `
                -DataverseToken 'test-token'
        } | Should -Throw
    }

    It 'carries topic assessment fields through JSON output' {
        $agent = [PSCustomObject]@{
            AgentId                    = '66666666-6666-6666-6666-666666666666'
            AgentName                  = 'JSON indeterminate'
            EnvironmentId              = 'env-1'
            EnvironmentDisplayName     = 'Test-zone1'
            Zone                       = 'Zone1'
            AzureOpenAIEnabled         = 'No'
            OrchestrationMode          = 'Classic'
            GenerativeAnswersNodeCount = 0
            AoaiConnectionId           = $null
            ModelKnowledgeEnabled      = 'No'
            SemanticSearchEnabled      = 'No'
            TopicAssessmentStatus      = 'Indeterminate'
            TopicAssessmentDetails     = 'Next page exists.'
            AgentStatus                = 'Active'
        }

        Mock Get-AgentGenAISettings { $agent }

        $json = Test-GenAIConfigCompliance -OutputFormat Json -IncludeCompliant
        $parsed = $json | ConvertFrom-Json

        $parsed.results[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $parsed.results[0].TopicAssessmentDetails | Should -Be 'Next page exists.'
    }
}

Describe 'Topic assessment runbook propagation' {
    It 'carries assessment fields and excludes an indeterminate count from drift comparison' {
        $scriptRoot = Join-Path $solutionRoot 'scripts'
        $runbookPath = Join-Path $scriptRoot 'Start-GenAIConfigValidationRunbook.ps1'
        $agentId = '77777777-7777-7777-7777-777777777777'

        if (-not (Get-Command Test-GenAIConfigCompliance -ErrorAction SilentlyContinue)) {
            function Test-GenAIConfigCompliance {}
        }

        Mock Get-Item -ParameterFilter { $Path -like 'Cert:\LocalMachine\My\*' } {
            [PSCustomObject]@{ Subject = 'CN=GAC test certificate' }
        }
        Mock Get-GACEnvironmentVariable {
            param([string]$Name, $DefaultValue)
            if ($Name -eq 'GracePeriodHours') {
                return $DefaultValue
            }
            return $DefaultValue
        }
        Mock Test-GenAIConfigCompliance {
            [PSCustomObject]@{
                AgentId                    = $agentId
                AgentName                  = 'Runbook indeterminate'
                EnvironmentId              = 'env-1'
                EnvironmentDisplayName     = 'Test-zone1'
                Zone                       = 'Zone1'
                AzureOpenAIEnabled         = 'No'
                OrchestrationMode          = 'Classic'
                GenerativeAnswersNodeCount = 0
                ModelKnowledgeEnabled      = 'No'
                SemanticSearchEnabled      = 'No'
                TopicAssessmentStatus      = 'Indeterminate'
                TopicAssessmentDetails     = 'Current topic set is incomplete.'
                IsCompliant                = $false
                Severity                   = 'Warning'
                ViolationType              = 'IndeterminateTopicAssessment'
                RegulatoryContext          = 'Manual review required.'
            }
        }
        Mock Get-GACBaseline {
            [PSCustomObject]@{
                AgentId                    = $agentId
                AgentName                  = 'Runbook indeterminate'
                EnvironmentGuid            = 'env-1'
                EnvironmentName            = 'Test-zone1'
                Zone                       = 'Zone1'
                AzureOpenAIEnabled         = 'No'
                OrchestrationMode          = 'Classic'
                GenerativeAnswersNodeCount = 1
                ModelKnowledgeEnabled      = 'No'
                SemanticSearchEnabled      = 'No'
            }
        }

        $json = & $runbookPath `
            -TenantId 'tenant-id' `
            -ClientId 'client-id' `
            -CertificateThumbprint 'thumbprint' `
            -DataverseUrl 'https://governance.crm.dynamics.com'
        $parsed = $json | ConvertFrom-Json

        $parsed.Violations[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $parsed.Violations[0].TopicAssessmentDetails | Should -Be 'Current topic set is incomplete.'
        $parsed.Drift.Details[0].CurrentTopicAssessmentStatus | Should -Be 'Indeterminate'
        $parsed.Drift.Details[0].CurrentTopicAssessmentDetails | Should -Be 'Current topic set is incomplete.'
        @($parsed.Drift.Details[0].Changes | Where-Object Field -eq 'GenerativeAnswersNodeCount').Count | Should -Be 0
        $parsed.Drift.Details[0].HasDrift | Should -BeFalse
    }
}

Describe 'Topic assessment baseline capture' {
    It 'skips indeterminate agents without saving and still captures determined agents' {
        $capturePath = Join-Path $scriptsRoot 'Invoke-GenAIBaselineCapture.ps1'

        if (-not (Get-Command Get-AgentGenAISettings -ErrorAction SilentlyContinue)) {
            function Get-AgentGenAISettings {}
        }

        $baselineBots = @(
            [PSCustomObject]@{
                botid = '88888888-8888-8888-8888-888888888888'
                name = 'Indeterminate baseline'
                statecode = 0
                configuration = '{}'
            },
            [PSCustomObject]@{
                botid = '99999999-9999-9999-9999-999999999999'
                name = 'Determined baseline'
                statecode = 0
                configuration = '{}'
            }
        )

        Mock Get-AgentBots { $baselineBots }

        $baselinePosts = [System.Collections.Generic.List[object]]::new()
        Mock Import-Module {}
        Mock Invoke-DataverseRequest -ModuleName GACClient {
            param(
                [string]$Uri,
                [string]$Method,
                $Body
            )

            if ($Uri -like '*fsi_gacbaselines*' -and $Method -eq 'Post') {
                [void]$baselinePosts.Add([PSCustomObject]@{
                    Uri = $Uri
                    Body = $Body
                })
            }

            if ($Method -eq 'Get') {
                return [PSCustomObject]@{ value = @() }
            }

            return [PSCustomObject]@{}
        }
        Mock Invoke-RestMethod {
            param([string]$Uri)

            if ($Uri -like '*botcomponents*') {
                if ($Uri -like '*88888888-8888-8888-8888-888888888888*') {
                    return [PSCustomObject]@{
                        value = @(
                            [PSCustomObject]@{
                                name = 'Indeterminate topic'
                                data = 'not-json'
                                content = ''
                                componenttype = 9
                                botcomponentid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                            }
                        )
                    }
                }

                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            name = 'Determined topic'
                            data = '{"kind":"OrdinaryTopic"}'
                            content = ''
                            componenttype = 0
                            botcomponentid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                        }
                    )
                }
            }

            [PSCustomObject]@{ value = @() }
        }

        $json = & $capturePath `
            -TenantId 'tenant-id' `
            -ClientId 'client-id' `
            -DataverseUrl 'https://governance.crm.dynamics.com' `
            -Interactive
        $parsed = $json | ConvertFrom-Json
        $baselinePosts.Count | Should -Be 1
        $savedBody = $baselinePosts[0].Body | ConvertFrom-Json
        $savedBody.fsi_agentid | Should -Be '99999999-9999-9999-9999-999999999999'
        $parsed.TotalCaptured | Should -Be 1
        $parsed.TotalSkipped | Should -Be 1
        $parsed.SkippedAgents[0].AgentName | Should -Be 'Indeterminate baseline'
        $parsed.SkippedAgents[0].TopicAssessmentStatus | Should -Be 'Indeterminate'
        $parsed.SkippedAgents[0].TopicAssessmentDetails | Should -Be 'Topic ''Indeterminate topic'' could not be parsed as JSON and the optional YAML parser is unavailable.'
    }
}
