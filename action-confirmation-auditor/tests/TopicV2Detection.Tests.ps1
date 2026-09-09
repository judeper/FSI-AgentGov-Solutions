#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Offline regressions for ACA Topic V2 botcomponent detection.

.DESCRIPTION
    Exercises the actual ACA detector/helper function bodies with mocked Dataverse
    boundaries and the exported ACAClient module behavior. No tenant, credential,
    authentication, or persistence access is performed.

.NOTES
    Run with:
        Invoke-Pester -Path .\TopicV2Detection.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $script:SolutionRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:DetectorPath = Join-Path $script:SolutionRoot 'scripts' 'Get-AgentActionSettings.ps1'
    $script:UdamPath = Join-Path $script:SolutionRoot 'scripts' 'governance' 'Test-UserDefinedActionMessages.ps1'
    $script:ClientPath = Join-Path $script:SolutionRoot 'scripts' 'private' 'ACAClient.psm1'
    $script:PolicyPath = Join-Path $script:SolutionRoot 'scripts' 'private' 'Get-ExpectedConfirmationPolicy.ps1'

    function Get-AcaFunctionText {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Name
        )

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path,
            [ref]$tokens,
            [ref]$errors
        )
        if ($errors.Count -gt 0) {
            throw "Unable to parse ${Path}: $($errors -join '; ')"
        }

        $functionDefinitions = $ast.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $Name
            },
            $true
        )
        if ($functionDefinitions.Count -ne 1) {
            throw "Expected exactly one $Name function in $Path; found $($functionDefinitions.Count)."
        }

        return $functionDefinitions[0].Extent.Text
    }

    . ([scriptblock]::Create(
        (Get-AcaFunctionText -Path $script:DetectorPath -Name 'Get-BotActionConfig')
    ))
    . ([scriptblock]::Create(
        (Get-AcaFunctionText -Path $script:UdamPath -Name 'Test-BotHasUserDefinedActionMessages')
    ))

    function New-AcaPublicHarness {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Creates only isolated Pester TestDrive harness files.'
        )]
        param(
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [ValidateSet('Detector', 'Udam')]
            [string]$Kind
        )

        $scriptsRoot = Join-Path $Root 'scripts'
        $moduleRoot = if ($Kind -eq 'Udam') {
            Join-Path $scriptsRoot 'governance'
        } else {
            $scriptsRoot
        }
        $privateRoot = Join-Path $scriptsRoot 'private'
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        Copy-Item -Path (Join-Path $script:SolutionRoot 'scripts' 'private') -Destination $scriptsRoot -Recurse

        @'
function Get-AgentBots {
    [CmdletBinding()]
    param(
        [string]$DataverseUrl,
        [string]$AccessToken,
        [switch]$IncludeDrafts
    )

    return [PSCustomObject]@{
        botid = '11111111-1111-1111-1111-111111111111'
        name = 'ACA offline fixture'
        statecode = 0
        publishedon = $null
    }
}

Export-ModuleMember -Function Get-AgentBots
'@ | Set-Content -Path (Join-Path $privateRoot 'ACAClient.psm1') -Encoding utf8

        @'
param([string]$DataverseUrl)
'offline-token'
'@ | Set-Content -Path (Join-Path $privateRoot 'Connect-EnvironmentDataverse.ps1') -Encoding utf8

        @'
param(
    [string]$EnvironmentId,
    [string]$EnvironmentDisplayName,
    [string]$DataverseUrl,
    [string]$AccessToken
)
'Zone1'
'@ | Set-Content -Path (Join-Path $privateRoot 'Get-ZoneClassification.ps1') -Encoding utf8

        $functionName = if ($Kind -eq 'Udam') {
            'Test-UserDefinedActionMessages'
        } else {
            'Get-AgentActionSettings'
        }
        $sourcePath = if ($Kind -eq 'Udam') {
            $script:UdamPath
        } else {
            $script:DetectorPath
        }
        $modulePath = Join-Path $moduleRoot "Aca${Kind}Harness.psm1"
        $moduleContent = @'
function Get-AdminPowerAppEnvironment {
    throw 'Get-AdminPowerAppEnvironment must be mocked by the offline test harness.'
}

'@ + (Get-AcaFunctionText -Path $sourcePath -Name $functionName)
        $moduleContent | Set-Content -Path $modulePath -Encoding utf8

        return $modulePath
    }

    $script:DetectorHarnessPath = New-AcaPublicHarness -Root (Join-Path $TestDrive 'detector') -Kind Detector
    $script:UdamHarnessPath = New-AcaPublicHarness -Root (Join-Path $TestDrive 'udam') -Kind Udam
    Import-Module $script:DetectorHarnessPath -Force
    Import-Module $script:UdamHarnessPath -Force

    $script:Bot = [PSCustomObject]@{
        botid     = '11111111-1111-1111-1111-111111111111'
        name      = 'ACA offline fixture'
        statecode = 0
    }

    $script:PresentYaml = @'
kind: AdaptiveDialog
beginDialog:
  kind: OnRecognizedIntent
  actions:
    - kind: Question
      prompt: Are you sure you want to send the test notification?
    - kind: HttpRequest
      name: Send test notification
      method: POST
'@

    $script:MissingYaml = @'
kind: AdaptiveDialog
beginDialog:
  kind: OnRecognizedIntent
  actions:
    - kind: HttpRequest
      name: Send test notification
      method: POST
'@

    $script:MessageYaml = @'
kind: AdaptiveDialog
beginDialog:
  actions:
    - kind: Message
      text: About to run the requested action.
    - kind: InvokeConnectorAction
      name: Run connector
'@

    $yamlCommand = Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue
    $script:YamlParserEvidence = if ($yamlCommand) {
        $module = $yamlCommand.Module
        if ($module) {
            "$($module.Name) $($module.Version)"
        } else {
            "available without module metadata"
        }
    } else {
        'unavailable'
    }
    Write-Host "ConvertFrom-Yaml parser evidence: $script:YamlParserEvidence"
}

Describe 'Public ACA scan result envelopes' {
    BeforeAll {
        $script:AcaTestEnvironment = [PSCustomObject]@{
            EnvironmentName = 'env-offline'
            DisplayName = 'ACA Offline Environment'
            EnvironmentType = 'Production'
            CreatedTime = (Get-Date).AddDays(-30)
            Internal = [PSCustomObject]@{
                properties = [PSCustomObject]@{
                    linkedEnvironmentMetadata = [PSCustomObject]@{
                        instanceUrl = 'https://example.crm.dynamics.com'
                    }
                }
            }
        }
    }

    BeforeEach {
        Mock Get-AdminPowerAppEnvironment -ModuleName AcaDetectorHarness {
            @($script:AcaTestEnvironment)
        }
        Mock Invoke-RestMethod -ModuleName AcaDetectorHarness {
            $script:AcaComponentResponse
        }

        Mock Get-AdminPowerAppEnvironment -ModuleName AcaUdamHarness {
            @($script:AcaTestEnvironment)
        }
        Mock Invoke-RestMethod -ModuleName AcaUdamHarness {
            $script:AcaComponentResponse
        }
    }

    It 'returns the public agent envelope with Topic V2 Present and Missing actions' {
        $script:AcaComponentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Confirmed topic'
                    botcomponentid = '18181818-1818-1818-1818-181818181818'
                    componenttype = 9
                    data = $script:PresentYaml
                    content = $null
                },
                [PSCustomObject]@{
                    name = 'Unconfirmed topic'
                    botcomponentid = '19191919-1919-1919-1919-191919191919'
                    componenttype = 9
                    data = $script:MissingYaml
                    content = $null
                }
            )
        }

        $result = @(AcaDetectorHarness\Get-AgentActionSettings -GracePeriodHours 0)

        $result.Count | Should -Be 1
        $result[0].TotalActions | Should -Be 2
        $result[0].ActionsWithConfirmation | Should -Be 1
        $result[0].ActionsMissingConfirmation | Should -Be 1
        @($result[0].Actions | Select-Object -ExpandProperty ConfirmationStatus) |
            Should -Be @('Present', 'Missing')
    }

    It 'returns the public UDAM envelope as noncompliant for mixed assessable and empty topics' {
        $script:AcaComponentResponse = [PSCustomObject]@{
            value = @(
                [PSCustomObject]@{
                    name = 'Message topic'
                    botcomponentid = '21212121-2121-2121-2121-212121212121'
                    componenttype = 9
                    data = $script:MessageYaml
                    content = $null
                },
                [PSCustomObject]@{
                    name = 'Empty topic'
                    botcomponentid = '22222222-2222-2222-2222-222222222222'
                    componenttype = 9
                    data = $null
                    content = $null
                }
            )
        }

        $result = @(AcaUdamHarness\Test-UserDefinedActionMessages -OutputFormat Object -GracePeriodHours 0)

        $result.Count | Should -Be 1
        $result[0].HasUserDefinedActionMessages | Should -BeFalse
        $result[0].IsCompliant | Should -BeFalse
        $result[0].Severity | Should -Be 'Critical'
        $result[0].Details | Should -Match 'Incomplete assessment'
    }
}

Describe 'Get-BotActionConfig Topic V2 behavior' {
    BeforeEach {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ value = @() }
        }
    }

    It 'queries Topic V2 and legacy topic rows and selects data plus content' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{ value = @() }
        }

        Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline' | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -match 'componenttype eq 9 or componenttype eq 0' -and
            $Uri -match '\$select=name,data,content,componenttype,botcomponentid'
        }
    }

    It 'detects Present from an authentic-shape type-9 data-only topic' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Confirmed topic'
                        botcomponentid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                        componenttype = 9
                        data = $script:PresentYaml
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ConfirmationStatus | Should -Be 'Present'
        $result[0].ActionType | Should -Be 'HttpRequest'
    }

    It 'detects Missing from an authentic-shape type-9 data-only topic' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Unconfirmed topic'
                        botcomponentid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                        componenttype = 9
                        data = $script:MissingYaml
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ConfirmationStatus | Should -Be 'Missing'
    }

    It 'falls back to legacy content for a type-0 topic' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Legacy topic'
                        botcomponentid = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
                        componenttype = 0
                        data = $null
                        content = $script:PresentYaml
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result[0].ConfirmationStatus | Should -Be 'Present'
    }

    It 'uses populated data instead of populated content' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Dual payload topic'
                        botcomponentid = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
                        componenttype = 9
                        data = $script:MissingYaml
                        content = $script:PresentYaml
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result[0].ConfirmationStatus | Should -Be 'Missing'
    }

    It 'falls back to content when data contains only whitespace' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Whitespace data topic'
                        botcomponentid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
                        componenttype = 9
                        data = " `t`r`n"
                        content = $script:PresentYaml
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result[0].ConfirmationStatus | Should -Be 'Present'
    }

    It 'returns an inconclusive marker for an empty topic' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Empty topic'
                        botcomponentid = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
                        componenttype = 9
                        data = ' '
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ConfirmationStatus | Should -Be 'UnableToDetermine'
    }

    It 'keeps an inconclusive marker when a Present topic is mixed with an empty topic' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Confirmed topic'
                        botcomponentid = '10101010-1010-1010-1010-101010101010'
                        componenttype = 9
                        data = $script:PresentYaml
                        content = $null
                    },
                    [PSCustomObject]@{
                        name = 'Empty topic'
                        botcomponentid = '20202020-2020-2020-2020-202020202020'
                        componenttype = 9
                        data = $null
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        @($result | Where-Object ConfirmationStatus -eq 'Present').Count | Should -Be 1
        @($result | Where-Object ConfirmationStatus -eq 'UnableToDetermine').Count | Should -Be 1
    }

    It 'does not mark a parsed action-free topic indeterminate when another topic is assessable' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Action-free JSON topic'
                        botcomponentid = '30303030-3030-3030-3030-303030303030'
                        componenttype = 9
                        data = '{"kind":"AdaptiveDialog","nodes":[]}'
                        content = $null
                    },
                    [PSCustomObject]@{
                        name = 'Action topic'
                        botcomponentid = '40404040-4040-4040-4040-404040404040'
                        componenttype = 9
                        data = $script:MissingYaml
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ConfirmationStatus | Should -Be 'Missing'
    }

    It 'fails closed when YAML parsing is unavailable and the payload is otherwise unassessable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' }
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Action-free YAML topic'
                        botcomponentid = '50505050-5050-5050-5050-505050505050'
                        componenttype = 9
                        data = "kind: AdaptiveDialog`ndisplayName: Offline fixture"
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result[0].ConfirmationStatus | Should -Be 'UnableToDetermine'
    }

    It 'fails closed instead of classifying page one when a nextLink is present' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Page-one confirmed topic'
                        botcomponentid = '60606060-6060-6060-6060-606060606060'
                        componenttype = 9
                        data = $script:PresentYaml
                        content = $null
                    }
                )
                '@odata.nextLink' = 'https://example.crm.dynamics.com/api/data/v9.2/botcomponents?$skiptoken=next'
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ConfirmationStatus | Should -Be 'UnableToDetermine'
    }

    It 'classifies an ordinary single page normally' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Single-page topic'
                        botcomponentid = '70707070-7070-7070-7070-707070707070'
                        componenttype = 9
                        data = $script:MissingYaml
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result[0].ConfirmationStatus | Should -Be 'Missing'
    }

    It 'does not fall back to valid content when nonblank authoritative data is malformed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' }
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Malformed authoritative data'
                        botcomponentid = '80808080-8080-8080-8080-808080808080'
                        componenttype = 9
                        data = '{'
                        content = $script:PresentYaml
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ConfirmationStatus | Should -Be 'UnableToDetermine'
    }

    It 'characterizes regex-recognizable malformed input without claiming semantic YAML validation' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' }
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Regex-only malformed topic'
                        botcomponentid = '90909090-9090-9090-9090-909090909090'
                        componenttype = 9
                        data = 'not-valid: [ ::: kind: HttpRequest'
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ActionType | Should -Be 'HttpRequest'
        $result[0].ConfirmationStatus | Should -Be 'Missing'
    }

    It 'preserves the fail-closed result for a <Failure> query failure' -ForEach @(
        @{ Failure = '401 Unauthorized' }
        @{ Failure = '403 Forbidden' }
        @{ Failure = 'The operation timed out' }
        @{ Failure = '429 Too Many Requests' }
        @{ Failure = '503 Service Unavailable' }
    ) {
        Mock Invoke-RestMethod { throw $Failure }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')

        $result.Count | Should -Be 1
        $result[0].ConfirmationStatus | Should -Be 'UnableToDetermine'
    }

    It 'preserves action result property names and core property types' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Contract topic'
                        botcomponentid = 'abababab-abab-abab-abab-abababababab'
                        componenttype = 9
                        data = $script:PresentYaml
                        content = $null
                    }
                )
            }
        }

        $result = @(Get-BotActionConfig -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline')
        $propertyNames = @($result[0].PSObject.Properties.Name)

        $propertyNames | Should -Be @(
            'ActionName',
            'ActionType',
            'ConnectorName',
            'HttpMethod',
            'ConfirmationStatus',
            'TopicName',
            'TopicId'
        )
        $result[0].ActionName | Should -BeOfType [string]
        $result[0].ActionType | Should -BeOfType [string]
        $result[0].ConfirmationStatus | Should -BeOfType [string]
        $result[0].TopicName | Should -BeOfType [string]
        $result[0].TopicId | Should -BeOfType [string]
    }

    It 'keeps UnableToDetermine strict in Zone 1 and advisory in Zone 3 policy treatment' {
        $zone1 = & $script:PolicyPath -Zone 'Zone1'
        $zone3 = & $script:PolicyPath -Zone 'Zone3'
        $status = 'UnableToDetermine'

        ($zone1.AdvisoryOnly -eq $false -and $status -in @('Missing', 'Partial', 'UnableToDetermine')) | Should -BeTrue
        ($zone3.AdvisoryOnly -eq $true -and $status -in @('Missing', 'Partial', 'UnableToDetermine')) | Should -BeTrue
    }
}

Describe 'Test-BotHasUserDefinedActionMessages Topic V2 behavior' {
    It 'detects a user message from type-9 data-only content' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Message topic'
                        botcomponentid = '12121212-1212-1212-1212-121212121212'
                        componenttype = 9
                        data = $script:MessageYaml
                        content = $null
                    }
                )
            }
        }

        $result = Test-BotHasUserDefinedActionMessages -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline'

        $result.HasUserDefinedActionMessages | Should -BeTrue
        $result.ActionComponentCount | Should -Be 1
        $result.ComponentsWithMessages | Should -Be 1
    }

    It 'returns its four-property failure shape for an incomplete page' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Page-one message topic'
                        botcomponentid = '13131313-1313-1313-1313-131313131313'
                        componenttype = 9
                        data = $script:MessageYaml
                        content = $null
                    }
                )
                '@odata.nextLink' = 'https://example.crm.dynamics.com/api/data/v9.2/botcomponents?$skiptoken=next'
            }
        }

        $result = Test-BotHasUserDefinedActionMessages -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline'

        @($result.PSObject.Properties.Name) | Should -Be @(
            'HasUserDefinedActionMessages',
            'ActionComponentCount',
            'ComponentsWithMessages',
            'Details'
        )
        $result.HasUserDefinedActionMessages | Should -BeFalse
        $result.Details | Should -Match 'Incomplete scan'
    }

    It 'forces false when an assessable message topic is mixed with an empty topic' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Message topic'
                        botcomponentid = '14141414-1414-1414-1414-141414141414'
                        componenttype = 9
                        data = $script:MessageYaml
                        content = $null
                    },
                    [PSCustomObject]@{
                        name = 'Empty topic'
                        botcomponentid = '15151515-1515-1515-1515-151515151515'
                        componenttype = 9
                        data = $null
                        content = ' '
                    }
                )
            }
        }

        $result = Test-BotHasUserDefinedActionMessages -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline'

        $result.HasUserDefinedActionMessages | Should -BeFalse
        $result.ActionComponentCount | Should -Be 1
        $result.ComponentsWithMessages | Should -Be 1
        $result.Details | Should -Match 'Incomplete assessment'
    }

    It 'forces false when a valid message topic is mixed with malformed nonblank no-action data and YAML parsing is unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' }
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Message topic'
                        botcomponentid = '23232323-2323-2323-2323-232323232323'
                        componenttype = 9
                        data = $script:MessageYaml
                        content = $null
                    },
                    [PSCustomObject]@{
                        name = 'Malformed no-action topic'
                        botcomponentid = '24242424-2424-2424-2424-242424242424'
                        componenttype = 9
                        data = '{'
                        content = $null
                    }
                )
            }
        }

        $result = Test-BotHasUserDefinedActionMessages -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline'

        $result.HasUserDefinedActionMessages | Should -BeFalse
        $result.ActionComponentCount | Should -Be 1
        $result.ComponentsWithMessages | Should -Be 1
        $result.Details | Should -Match 'Incomplete assessment'
    }

    It 'remains true when a valid message topic is mixed with successfully parsed action-free content' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Message topic'
                        botcomponentid = '25252525-2525-2525-2525-252525252525'
                        componenttype = 9
                        data = $script:MessageYaml
                        content = $null
                    },
                    [PSCustomObject]@{
                        name = 'Action-free JSON topic'
                        botcomponentid = '26262626-2626-2626-2626-262626262626'
                        componenttype = 9
                        data = '{"kind":"AdaptiveDialog","nodes":[]}'
                        content = $null
                    }
                )
            }
        }

        $result = Test-BotHasUserDefinedActionMessages -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline'

        $result.HasUserDefinedActionMessages | Should -BeTrue
        $result.ActionComponentCount | Should -Be 1
        $result.ComponentsWithMessages | Should -Be 1
        $result.Details | Should -Match 'All 1 action component\(s\) have user-defined messages'
    }

    It 'remains true when optional YAML parsing is available and action-free YAML is parseable' {
        try {
            $script:YamlParseCalls = 0
            function ConvertFrom-Yaml {
                param(
                    [Parameter(ValueFromPipeline)]
                    [AllowNull()]
                    [object]$InputObject
                )

                process {
                    $script:YamlParseCalls++
                    [PSCustomObject]@{ kind = 'AdaptiveDialog'; nodes = @() }
                }
            }

            Mock Invoke-RestMethod {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            name = 'Message topic'
                            botcomponentid = '2a2a2a2a-2a2a-2a2a-2a2a-2a2a2a2a2a2a'
                            componenttype = 9
                            data = $script:MessageYaml
                            content = $null
                        },
                        [PSCustomObject]@{
                            name = 'Action-free YAML topic'
                            botcomponentid = '2b2b2b2b-2b2b-2b2b-2b2b-2b2b2b2b2b2b'
                            componenttype = 9
                            data = "kind: AdaptiveDialog`nactions: []"
                            content = $null
                        }
                    )
                }
            }

            $result = Test-BotHasUserDefinedActionMessages -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline'

            $result.HasUserDefinedActionMessages | Should -BeTrue
            $result.ActionComponentCount | Should -Be 1
            $result.ComponentsWithMessages | Should -Be 1
            $result.Details | Should -Match 'All 1 action component\(s\) have user-defined messages'
            $script:YamlParseCalls | Should -Be 2
        } finally {
            Remove-Item Function:\ConvertFrom-Yaml -ErrorAction SilentlyContinue
        }
    }

    It 'does not fall back to valid legacy content after malformed nonblank data and returns incomplete assessment' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' }
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        name = 'Message topic'
                        botcomponentid = '27272727-2727-2727-2727-272727272727'
                        componenttype = 9
                        data = $script:MessageYaml
                        content = $null
                    },
                    [PSCustomObject]@{
                        name = 'Malformed authoritative data topic'
                        botcomponentid = '28282828-2828-2828-2828-282828282828'
                        componenttype = 9
                        data = '{'
                        content = $script:MessageYaml
                    }
                )
            }
        }

        $result = Test-BotHasUserDefinedActionMessages -Bot $script:Bot -EnvDataverseUrl 'https://example.crm.dynamics.com' -EnvToken 'offline'

        $result.HasUserDefinedActionMessages | Should -BeFalse
        $result.ActionComponentCount | Should -Be 1
        $result.ComponentsWithMessages | Should -Be 1
        $result.Details | Should -Match 'Incomplete assessment'
    }
}

Describe 'ACAClient Topic V2 behavior' {
    BeforeAll {
        Get-Module ACAClient -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $script:ClientPath -Force
    }

    It 'retains pagination and aggregates an action found only on page two' {
        $script:ClientResponses = [System.Collections.Generic.Queue[object]]::new()
        $script:ClientResponses.Enqueue(
            [PSCustomObject]@{
                value = @()
                '@odata.nextLink' = 'https://example.crm.dynamics.com/api/data/v9.2/botcomponents?$skiptoken=next'
            }
        )
        $script:ClientResponses.Enqueue(
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        botcomponentid = '16161616-1616-1616-1616-161616161616'
                        name = 'Page two action'
                        componenttype = 9
                        data = '{"actions":[{"type":"InvokeConnectorAction","name":"Page Two","requiresConfirmation":true}]}'
                        content = $null
                        _parentbotid_value = $script:Bot.botid
                    }
                )
            }
        )
        Mock Invoke-DataverseRequest -ModuleName ACAClient {
            $script:ClientResponses.Dequeue()
        }

        $result = @(Get-BotActionSettings -DataverseUrl 'https://example.crm.dynamics.com' -AccessToken 'offline' -BotId $script:Bot.botid)

        $result.Count | Should -Be 1
        $result[0].ActionName | Should -Be 'Page Two'
        $result[0].HasConfirmation | Should -BeTrue
        Should -Invoke Invoke-DataverseRequest -ModuleName ACAClient -Times 2
    }

    It 'does not fall back to content after selecting malformed nonblank data' {
        Mock Invoke-DataverseRequest -ModuleName ACAClient {
            [PSCustomObject]@{
                value = @(
                    [PSCustomObject]@{
                        botcomponentid = '17171717-1717-1717-1717-171717171717'
                        name = 'Malformed data component'
                        componenttype = 9
                        data = '{'
                        content = '{"actions":[{"type":"InvokeConnectorAction","name":"Legacy fallback","requiresConfirmation":true}]}'
                        _parentbotid_value = $script:Bot.botid
                    }
                )
            }
        }

        $result = @(Get-BotActionSettings -DataverseUrl 'https://example.crm.dynamics.com' -AccessToken 'offline' -BotId $script:Bot.botid)

        $result.Count | Should -Be 0
    }
}
