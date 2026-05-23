#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit tests for _Common.ps1 helpers (formatters, REST retry,
    auth-mode dispatch, secret redaction).

.DESCRIPTION
    Council findings covered:
      - H2: Invoke-McmRest retries on 5xx (not just 429)
      - H3: Invoke-McmRest reads Retry-After on PS7 HttpResponseException
            via reflection or hashtable fallback
      - H1: Get-McmAccessToken dispatches correctly for each AuthMode
            (ManagedIdentity, WorkloadIdentity, Interactive, DeviceCode,
            ClientSecret) and validates required parameters

    Plus general formatter and redaction coverage.

.NOTES
    Run with: Invoke-Pester -Path .\Common.Tests.ps1 -Output Detailed
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Pester test fixture credential — never used against production. Required to exercise SecureString-accepting code paths.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'Pester test doubles in this file mirror mocked command signatures; unused parameters satisfy the signature contract, not the test body.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'governance' '_Common.ps1')

    function New-McmFakeException {
        param(
            [int]$Status,
            [hashtable]$ResponseHeaders = @{}
        )
        $ex = [System.Exception]::new("simulated http $Status")
        Add-Member -InputObject $ex -MemberType NoteProperty -Name Response `
            -Value ([pscustomobject]@{
                StatusCode = $Status
                Headers    = $ResponseHeaders
            })
        $ex
    }
}

Describe 'Format-McmODataLiteral' {
    It 'doubles single quotes for OData escape' {
        Format-McmODataLiteral "O'Brien" | Should -Be "O''Brien"
    }
    It 'returns empty string unchanged' {
        Format-McmODataLiteral '' | Should -Be ''
    }
    It 'leaves non-quote characters intact' {
        Format-McmODataLiteral 'MC123456' | Should -Be 'MC123456'
    }
    It 'escapes multiple quotes' {
        Format-McmODataLiteral "a'b'c" | Should -Be "a''b''c"
    }
}

Describe 'Format-McmODataDate' {
    It 'returns ISO-8601 UTC format' {
        $d = [datetime]::new(2026, 4, 16, 12, 0, 0, [System.DateTimeKind]::Utc)
        Format-McmODataDate $d | Should -Match '^2026-04-16T12:00:00(\.0+)?Z$'
    }
    It 'converts local time to UTC' {
        $d = [datetime]::new(2026, 4, 16, 12, 0, 0, [System.DateTimeKind]::Local)
        $result = Format-McmODataDate $d
        $result | Should -Match 'Z$'
    }
}

Describe 'Format-McmSafeUri (council round 2 - HIGH: redact bearer-secret URLs in log paths)' {

    # Background: Teams Workflows incoming webhook URLs, Logic Apps SAS URLs,
    # and any URL with a sig= / code= query parameter carry the *credential*
    # in the URL itself. Invoke-McmRest's error message previously embedded
    # the raw URI on failure (line 224), which leaked the bearer secret into
    # console output and any downstream log pipeline. Format-McmSafeUri is
    # the single redaction point - these tests pin its behavior so future
    # contributors don't regress the leak.

    It 'redacts a Teams Workflows webhook URL with a sig= query param' {
        $url = 'https://prod-12.northeurope.logic.azure.com:443/workflows/abc123/triggers/manual/paths/invoke?api-version=2016-06-01&sig=SUPER_SECRET_BEARER_TOKEN'
        $safe = Format-McmSafeUri $url
        $safe | Should -Be 'https://prod-12.northeurope.logic.azure.com/<redacted>'
        $safe | Should -Not -Match 'SUPER_SECRET_BEARER_TOKEN'
        $safe | Should -Not -Match 'sig='
    }

    It 'redacts a webhook.office.com URL even without a sig= parameter' {
        $url = 'https://contoso.webhook.office.com/webhookb2/abc-def-ghi/IncomingWebhook/123/456'
        $safe = Format-McmSafeUri $url
        $safe | Should -Be 'https://contoso.webhook.office.com/<redacted>'
        $safe | Should -Not -Match 'webhookb2'
    }

    It 'leaves a Dataverse OData URL completely unchanged' {
        # Authorization is in the bearer token header, NOT the URL. Log-time
        # redaction of Dataverse URLs would actively impede troubleshooting
        # (which entity set? which $filter clause?).
        $url = 'https://contoso.crm.dynamics.com/api/data/v9.2/fsi_messagecenterlogs?$select=fsi_messagecenterid&$filter=fsi_severity eq 100000000'
        Format-McmSafeUri $url | Should -Be $url
    }

    It 'leaves a Microsoft Graph URL completely unchanged' {
        $url = 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?$top=1'
        Format-McmSafeUri $url | Should -Be $url
    }

    It 'redacts an azure-apim.net URL with a code= parameter' {
        $url = 'https://contoso.azure-apim.net/api/v1/notify?code=SUPER_SECRET_FUNCTION_KEY&category=high'
        $safe = Format-McmSafeUri $url
        $safe | Should -Be 'https://contoso.azure-apim.net/<redacted>'
        $safe | Should -Not -Match 'SUPER_SECRET_FUNCTION_KEY'
        $safe | Should -Not -Match 'category=high'
    }

    It 'returns the unparseable-uri sentinel for a non-URI string (does not leak garbage)' {
        Format-McmSafeUri 'not a url at all' | Should -Be '<unparseable-uri>'
    }

    It 'returns empty string for empty input' {
        Format-McmSafeUri '' | Should -Be ''
    }
}

Describe 'Format-McmSafeErrorBody (council round 3 - defense in depth)' {

    # Some APIs echo the original request URL inside their error response body.
    # Even after the URI argument is redacted via Format-McmSafeUri, the body
    # itself can re-leak sig= / code= bearer credentials. This helper scrubs
    # those query parameters anywhere in a free-text body string.

    It 'scrubs sig= even when embedded inside a JSON error body' {
        $body = '{"error":"Forbidden","requestUrl":"https://prod-01.westus.logic.azure.com/workflows/abc/triggers/manual/paths/invoke?api-version=2016-06-01&sig=SUPER_SECRET_BEARER_TOKEN"}'
        $safe = Format-McmSafeErrorBody $body
        $safe | Should -Not -Match 'SUPER_SECRET_BEARER_TOKEN'
        $safe | Should -Match 'sig=<redacted>'
        # other diagnostic context preserved
        $safe | Should -Match 'Forbidden'
        $safe | Should -Match 'logic.azure.com'
    }

    It 'scrubs code= regardless of host' {
        $body = 'Request to https://my-function.azurewebsites.net/api/notify?code=FUNCTION_KEY_HERE failed: 401 Unauthorized'
        $safe = Format-McmSafeErrorBody $body
        $safe | Should -Not -Match 'FUNCTION_KEY_HERE'
        $safe | Should -Match 'code=<redacted>'
        $safe | Should -Match '401 Unauthorized'
    }

    It 'scrubs both sig= and code= in the same body' {
        $body = 'url1=...sig=AAA&...; url2=...code=BBB&...'
        $safe = Format-McmSafeErrorBody $body
        $safe | Should -Not -Match 'AAA'
        $safe | Should -Not -Match 'BBB'
        $safe | Should -Match 'sig=<redacted>'
        $safe | Should -Match 'code=<redacted>'
    }

    It 'is case-insensitive (SIG= and Code= must also be scrubbed)' {
        $body = 'request?SIG=upper&Code=mixed'
        $safe = Format-McmSafeErrorBody $body
        $safe | Should -Not -Match 'upper'
        $safe | Should -Not -Match 'mixed'
    }

    It 'leaves a clean Dataverse error body unchanged' {
        $body = '{"error":{"code":"0x8004431a","message":"The given key was not present in the dictionary."}}'
        Format-McmSafeErrorBody $body | Should -Be $body
    }

    It 'returns empty string for null input' {
        Format-McmSafeErrorBody $null | Should -Be ''
    }

    It 'returns empty string for empty input' {
        Format-McmSafeErrorBody '' | Should -Be ''
    }
}

Describe 'Invoke-McmRest - retry behaviour (H2/H3)' {

    Context 'success on first try' {
        It 'returns the response without retry' {
            Mock -CommandName Invoke-RestMethod -MockWith { return @{ value = 'ok' } }
            $r = Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get
            $r.value | Should -Be 'ok'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }

    Context 'retries on 429 (H2)' {
        It 'retries then succeeds, honouring Retry-After: 1' {
            $script:n = 0
            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:n++
                if ($script:n -lt 3) { throw (New-McmFakeException -Status 429 -ResponseHeaders @{ 'Retry-After' = '1' }) }
                return @{ value = 'ok' }
            }
            $r = Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get -BaseDelaySeconds 1 -MaxDelaySeconds 1
            $r.value | Should -Be 'ok'
            Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        }
    }

    Context 'retries on 500/502/503/504 (H2 - 5xx not just 429)' {
        It 'retries on 503 then succeeds' {
            $script:n = 0
            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:n++
                if ($script:n -eq 1) { throw (New-McmFakeException -Status 503) }
                return @{ value = 'ok' }
            }
            Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get -BaseDelaySeconds 1 -MaxDelaySeconds 1 | Out-Null
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
        }
        It 'retries on 502 then succeeds' {
            $script:n = 0
            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:n++
                if ($script:n -eq 1) { throw (New-McmFakeException -Status 502) }
                return @{ ok = $true }
            }
            Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get -BaseDelaySeconds 1 -MaxDelaySeconds 1 | Out-Null
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
        }
    }

    Context 'no retry on non-retryable status' {
        It 'does not retry on 400' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (New-McmFakeException -Status 400) }
            { Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get } | Should -Throw
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
        It 'does not retry on 404' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (New-McmFakeException -Status 404) }
            { Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get } | Should -Throw
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
        It 'does not retry on 401' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (New-McmFakeException -Status 401) }
            { Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get } | Should -Throw
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }

    Context 'max-retry termination' {
        It 'gives up after MaxRetries+1 attempts' {
            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Invoke-RestMethod -MockWith { throw (New-McmFakeException -Status 503) }
            { Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get -MaxRetries 2 -BaseDelaySeconds 1 -MaxDelaySeconds 1 } | Should -Throw
            # The retry loop attempts MaxRetries+1 times (initial + MaxRetries retries)
            Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        }
        It 'final error message contains the status code' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw (New-McmFakeException -Status 503) }
            { Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get -MaxRetries 0 } | Should -Throw -ExpectedMessage '*status=503*'
        }
    }

    Context 'Retry-After header parsing (H3 fallback path)' {
        # H3 covers PS7 HttpResponseException whose .Headers is HttpResponseHeaders
        # (with TryGetValues). Constructing a real one in a unit test is heavy.
        # Here we exercise the elseif branch using a hashtable, which catches the
        # equivalent regression: "Retry-After is consulted at all rather than
        # ignored when present."
        It 'reads Retry-After integer from hashtable headers' {
            $script:n = 0
            $script:slept = $null
            Mock -CommandName Start-Sleep -MockWith { $script:slept = $Seconds }
            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:n++
                if ($script:n -eq 1) { throw (New-McmFakeException -Status 429 -ResponseHeaders @{ 'Retry-After' = '7' }) }
                return @{ ok = $true }
            }
            Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get -BaseDelaySeconds 1 | Out-Null
            $script:slept | Should -Be 7
        }
        It 'falls back to exponential backoff when Retry-After absent' {
            $script:n = 0
            $script:slept = $null
            Mock -CommandName Start-Sleep -MockWith { $script:slept = $Seconds }
            Mock -CommandName Invoke-RestMethod -MockWith {
                $script:n++
                if ($script:n -eq 1) { throw (New-McmFakeException -Status 503) }
                return @{ ok = $true }
            }
            Invoke-McmRest -Uri 'https://x' -Headers @{} -Method Get -BaseDelaySeconds 3 -MaxDelaySeconds 60 | Out-Null
            # On attempt 1 the delay is BaseDelaySeconds * 2^0 = 3
            $script:slept | Should -Be 3
        }
    }
}

Describe 'Get-McmAccessToken - auth-mode dispatch (H1)' {

    BeforeAll {
        # Stub MSAL.PS so tests can run without it installed. We define
        # Import-Module / Get-MsalToken / Get-Module as functions in script
        # scope so Pester's Mock can target them by name.
        function script:Import-Module { param($Name, [switch]$ErrorAction) }
        function script:Get-Module {
            param($Name, [switch]$ListAvailable)
            return [pscustomobject]@{ Name = 'MSAL.PS'; Version = [Version]'4.37.0.0' }
        }
        function script:Get-MsalToken {
            [CmdletBinding()]
            param(
                [string]$TenantId,
                [string]$ClientId,
                [SecureString]$ClientSecret,
                [string]$ClientAssertion,
                [string]$Resource,
                [string[]]$Scopes,
                [switch]$ManagedIdentity,
                [switch]$Interactive,
                [switch]$DeviceCode
            )
            return [pscustomobject]@{
                AccessToken = 'fake.access.token'
                ExpiresOn   = (Get-Date).AddHours(1)
            }
        }
    }

    Context 'ManagedIdentity' {
        It 'calls Get-MsalToken with -ManagedIdentity and resource form (no /.default)' {
            Mock -CommandName Get-MsalToken -MockWith {
                return [pscustomobject]@{ AccessToken = 'mi.token'; ExpiresOn = (Get-Date).AddHours(1) }
            }
            $t = Get-McmAccessToken -AuthMode ManagedIdentity -Scope 'https://x.crm.dynamics.com/.default'
            $t.AccessToken | Should -Be 'mi.token'
            Should -Invoke Get-MsalToken -ParameterFilter {
                $ManagedIdentity.IsPresent -and $Resource -eq 'https://x.crm.dynamics.com'
            } -Times 1
        }
    }

    Context 'ClientSecret' {
        It 'requires TenantId / ClientId / ClientSecret' {
            { Get-McmAccessToken -AuthMode ClientSecret -Scope 'https://x' } | Should -Throw -ExpectedMessage '*ClientId is required*'
            { Get-McmAccessToken -AuthMode ClientSecret -Scope 'https://x' -ClientId 'cid' } | Should -Throw -ExpectedMessage '*TenantId is required*'
            { Get-McmAccessToken -AuthMode ClientSecret -Scope 'https://x' -ClientId 'cid' -TenantId 'tid' } | Should -Throw -ExpectedMessage '*ClientSecret is required*'
        }
        It 'dispatches to Get-MsalToken with all credentials' {
            Mock -CommandName Get-MsalToken -MockWith {
                return [pscustomobject]@{ AccessToken = 'cs.token'; ExpiresOn = (Get-Date).AddHours(1) }
            }
            $secret = ConvertTo-SecureString 'sekret' -AsPlainText -Force
            $t = Get-McmAccessToken -AuthMode ClientSecret -Scope 'https://x' `
                -TenantId 'tid' -ClientId 'cid' -ClientSecret $secret
            $t.AccessToken | Should -Be 'cs.token'
            Should -Invoke Get-MsalToken -ParameterFilter {
                $TenantId -eq 'tid' -and $ClientId -eq 'cid' -and $ClientSecret -ne $null -and $Scopes -contains 'https://x'
            } -Times 1
        }
    }

    Context 'WorkloadIdentity' {
        It 'fails when no federated token source is available' {
            $oldFt   = $env:AZURE_FEDERATED_TOKEN
            $oldFtFn = $env:AZURE_FEDERATED_TOKEN_FILE
            $oldUrl  = $env:ACTIONS_ID_TOKEN_REQUEST_URL
            $oldTok  = $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN
            try {
                Remove-Item Env:AZURE_FEDERATED_TOKEN -ErrorAction SilentlyContinue
                Remove-Item Env:AZURE_FEDERATED_TOKEN_FILE -ErrorAction SilentlyContinue
                Remove-Item Env:ACTIONS_ID_TOKEN_REQUEST_URL -ErrorAction SilentlyContinue
                Remove-Item Env:ACTIONS_ID_TOKEN_REQUEST_TOKEN -ErrorAction SilentlyContinue
                { Get-McmAccessToken -AuthMode WorkloadIdentity -Scope 'https://x' -ClientId 'cid' -TenantId 'tid' } |
                    Should -Throw -ExpectedMessage '*WorkloadIdentity auth requires*'
            }
            finally {
                if ($oldFt)   { $env:AZURE_FEDERATED_TOKEN = $oldFt }
                if ($oldFtFn) { $env:AZURE_FEDERATED_TOKEN_FILE = $oldFtFn }
                if ($oldUrl)  { $env:ACTIONS_ID_TOKEN_REQUEST_URL = $oldUrl }
                if ($oldTok)  { $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN = $oldTok }
            }
        }
        It 'uses AZURE_FEDERATED_TOKEN env var as ClientAssertion' {
            $old = $env:AZURE_FEDERATED_TOKEN
            try {
                $env:AZURE_FEDERATED_TOKEN = 'fed.assert.token'
                Mock -CommandName Get-MsalToken -MockWith {
                    return [pscustomobject]@{ AccessToken = 'wi.token'; ExpiresOn = (Get-Date).AddHours(1) }
                }
                $t = Get-McmAccessToken -AuthMode WorkloadIdentity -Scope 'https://x' -ClientId 'cid' -TenantId 'tid'
                $t.AccessToken | Should -Be 'wi.token'
                Should -Invoke Get-MsalToken -ParameterFilter {
                    $ClientAssertion -eq 'fed.assert.token' -and $TenantId -eq 'tid' -and $ClientId -eq 'cid'
                } -Times 1
            }
            finally {
                if ($old) { $env:AZURE_FEDERATED_TOKEN = $old }
                else { Remove-Item Env:AZURE_FEDERATED_TOKEN -ErrorAction SilentlyContinue }
            }
        }
    }

    Context 'Interactive / DeviceCode' {
        It 'Interactive requires ClientId and TenantId' {
            { Get-McmAccessToken -AuthMode Interactive -Scope 'https://x' } | Should -Throw -ExpectedMessage '*ClientId is required*'
            { Get-McmAccessToken -AuthMode Interactive -Scope 'https://x' -ClientId 'cid' } | Should -Throw -ExpectedMessage '*TenantId is required*'
        }
        It 'DeviceCode requires ClientId and TenantId' {
            { Get-McmAccessToken -AuthMode DeviceCode -Scope 'https://x' } | Should -Throw -ExpectedMessage '*ClientId is required*'
            { Get-McmAccessToken -AuthMode DeviceCode -Scope 'https://x' -ClientId 'cid' } | Should -Throw -ExpectedMessage '*TenantId is required*'
        }
    }
}

Describe 'Write-McmRedacted' {
    It 'redacts Bearer tokens (token value never leaks)' {
        $msg = (Write-McmRedacted 'log line: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig more text' *>&1) -join "`n"
        $msg | Should -Match 'Bearer <REDACTED>'
        $msg | Should -Not -Match 'eyJhbGc'
    }
    It 'redacts a Bearer token even when on an Authorization line' {
        # Either redaction style is acceptable; the contract is "the raw token must never appear in the output."
        $msg = (Write-McmRedacted 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig' *>&1) -join "`n"
        $msg | Should -Not -Match 'eyJhbGc'
        $msg | Should -Match '<REDACTED>'
    }
    It 'redacts JSON access_token' {
        $msg = (Write-McmRedacted '{"access_token":"abc.def.ghi","other":"keep"}' *>&1) -join "`n"
        $msg | Should -Match '"access_token":"<REDACTED>"'
        $msg | Should -Match '"other":"keep"'
        $msg | Should -Not -Match 'abc\.def\.ghi'
    }
    It 'redacts form-encoded client_secret' {
        $msg = (Write-McmRedacted 'client_secret=topsecret123&grant_type=client_credentials' *>&1) -join "`n"
        $msg | Should -Match 'client_secret=<REDACTED>'
        $msg | Should -Not -Match 'topsecret123'
    }
    It 'redacts JSON client_secret' {
        $msg = (Write-McmRedacted '{"client_secret":"oops"}' *>&1) -join "`n"
        $msg | Should -Match '"client_secret":"<REDACTED>"'
        $msg | Should -Not -Match 'oops'
    }
    It 'redacts Authorization header on its own line' {
        $msg = (Write-McmRedacted "GET /x`nAuthorization: foo`nAccept: application/json" *>&1) -join "`n"
        $msg | Should -Match 'Authorization: <REDACTED>'
        $msg | Should -Match 'Accept: application/json'
    }
    It 'leaves non-secret content untouched' {
        $msg = (Write-McmRedacted 'normal log line with no secrets' *>&1) -join "`n"
        $msg | Should -Match 'normal log line with no secrets'
    }
}
