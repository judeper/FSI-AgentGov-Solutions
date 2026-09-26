#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\lab\lib\Write-LabLog.ps1')
    . (Join-Path $PSScriptRoot '..\lab\lib\PaygEnvironmentProvisioning.ps1')

    function Get-PaygPollResponse {
        param(
            [Parameter(Mandatory)] [int] $StatusCode,
            [Parameter(Mandatory)] [string] $State,
            [Parameter()] [hashtable] $Headers = @{}
        )

        [pscustomobject]@{
            StatusCode = $StatusCode
            Headers    = $Headers
            Content    = (@{ state = @{ id = $State } } | ConvertTo-Json -Depth 5)
        }
    }

    function Get-PaygEnvironmentList {
        param(
            [Parameter()] [switch] $WithMetadata
        )

        $properties = [ordered]@{
            displayName  = 'UnitTestEnv'
            databaseType = if ($WithMetadata) { 'CommonDataService' } else { 'None' }
        }
        if ($WithMetadata) {
            $properties.linkedEnvironmentMetadata = @{
                instanceUrl = 'https://unit.crm.dynamics.com'
            }
        }

        [pscustomobject]@{
            value = @(
                [pscustomobject]@{
                    name       = 'unit-env-id'
                    properties = [pscustomobject]$properties
                }
            )
        }
    }
}

Describe 'Invoke-PaygLifecycleOperationPoll' {
    BeforeEach {
        Mock -CommandName Start-Sleep -MockWith { }
        Mock -CommandName Write-LabLog -MockWith {
            if ($Throw) { throw $Message }
        }
    }

    It 'keeps polling when HTTP 200 still reports Running before Succeeded' {
        $script:i = 0
        $responses = @(
            (Get-PaygPollResponse -StatusCode 200 -State 'Running'),
            (Get-PaygPollResponse -StatusCode 200 -State 'Running'),
            (Get-PaygPollResponse -StatusCode 200 -State 'Succeeded')
        )
        Mock -CommandName Invoke-WebRequest -MockWith {
            $response = $responses[$script:i]
            $script:i++
            return $response
        }

        Invoke-PaygLifecycleOperationPoll -OperationUri 'https://unit/operation' -Headers @{} -PollIntervalSeconds 0 |
            Should -Be 'Succeeded'
        Should -Invoke Invoke-WebRequest -Times 3 -Exactly
    }

    It 'keeps polling accepted 202 lifecycle responses until Succeeded' {
        $script:i = 0
        $responses = @(
            (Get-PaygPollResponse -StatusCode 202 -State 'NotStarted'),
            (Get-PaygPollResponse -StatusCode 202 -State 'Running'),
            (Get-PaygPollResponse -StatusCode 200 -State 'Succeeded')
        )
        Mock -CommandName Invoke-WebRequest -MockWith {
            $response = $responses[$script:i]
            $script:i++
            return $response
        }

        Invoke-PaygLifecycleOperationPoll -OperationUri 'https://unit/operation' -Headers @{} -PollIntervalSeconds 0 |
            Should -Be 'Succeeded'
        Should -Invoke Invoke-WebRequest -Times 3 -Exactly
    }

    It 'honors Retry-After before the next non-terminal poll' {
        $script:i = 0
        $responses = @(
            (Get-PaygPollResponse -StatusCode 200 -State 'Running' -Headers @{ 'Retry-After' = '7' }),
            (Get-PaygPollResponse -StatusCode 200 -State 'Succeeded')
        )
        Mock -CommandName Invoke-WebRequest -MockWith {
            $response = $responses[$script:i]
            $script:i++
            return $response
        }

        Invoke-PaygLifecycleOperationPoll -OperationUri 'https://unit/operation' -Headers @{} | Should -Be 'Succeeded'
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
    }

    It 'throws when the lifecycle operation fails' {
        Mock -CommandName Invoke-WebRequest -MockWith {
            Get-PaygPollResponse -StatusCode 200 -State 'Failed'
        }

        { Invoke-PaygLifecycleOperationPoll -OperationUri 'https://unit/operation' -Headers @{} } |
            Should -Throw "*state 'Failed'*"
    }

    It 'throws on a bounded timeout instead of polling forever' {
        Mock -CommandName Invoke-WebRequest -MockWith {
            Get-PaygPollResponse -StatusCode 200 -State 'Running'
        }

        { Invoke-PaygLifecycleOperationPoll -OperationUri 'https://unit/operation' -Headers @{} -TimeoutSeconds 0 -PollIntervalSeconds 0 } |
            Should -Throw "*Timed out*Running*"
    }
}

Describe 'Wait-PaygEnvironmentLinkedMetadata' {
    BeforeEach {
        Mock -CommandName Start-Sleep -MockWith { }
        Mock -CommandName Write-LabLog -MockWith {
            if ($Throw) { throw $Message }
        }
    }

    It 'waits for the environment shell to include linked Dataverse metadata' {
        $script:i = 0
        $result = Wait-PaygEnvironmentLinkedMetadata -DisplayName 'UnitTestEnv' -PollIntervalSeconds 0 -GetEnvironments {
            $script:i++
            if ($script:i -lt 3) { return Get-PaygEnvironmentList }
            return Get-PaygEnvironmentList -WithMetadata
        }

        $result.properties.linkedEnvironmentMetadata.instanceUrl | Should -Be 'https://unit.crm.dynamics.com'
        $script:i | Should -Be 3
    }

    It 'throws when linked Dataverse metadata never appears' {
        { Wait-PaygEnvironmentLinkedMetadata -DisplayName 'UnitTestEnv' -TimeoutSeconds 0 -PollIntervalSeconds 0 -GetEnvironments { Get-PaygEnvironmentList } } |
            Should -Throw '*linkedEnvironmentMetadata*'
    }
}
