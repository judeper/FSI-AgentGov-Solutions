#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit tests for AuditComplianceHelpers module.

.DESCRIPTION
    Tests retry behavior, Managed Identity token acquisition, Dataverse upsert logic,
    compliance notification payload construction, and status option set mapping.

.NOTES
    Run with: Invoke-Pester -Path .\AuditComplianceHelpers.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot 'AuditComplianceHelpers.psm1'
    Import-Module $modulePath -Force
}

Describe "Invoke-WithRetry" {
    Context "Successful execution" {
        It "Returns result on first attempt when no error" {
            $result = Invoke-WithRetry -ScriptBlock { "success" } -OperationName "Test"
            $result | Should -Be "success"
        }

        It "Returns complex objects" {
            $result = Invoke-WithRetry -ScriptBlock { @{ Key = "Value"; Count = 42 } }
            $result.Key | Should -Be "Value"
            $result.Count | Should -Be 42
        }
    }

    Context "Retry behavior for retryable errors" {
        It "Retries on HTTP 429 and eventually succeeds" {
            $script:callCount = 0
            $result = Invoke-WithRetry -ScriptBlock {
                $script:callCount++
                if ($script:callCount -lt 3) {
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("429 Too Many Requests", $response)
                    throw $ex
                }
                "recovered"
            } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "RetryTest"

            $result | Should -Be "recovered"
            $script:callCount | Should -Be 3
        }

        It "Retries on HTTP 503 (Service Unavailable)" {
            $script:callCount = 0
            $result = Invoke-WithRetry -ScriptBlock {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::ServiceUnavailable)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("503 Service Unavailable", $response)
                    throw $ex
                }
                "ok"
            } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "503Test"

            $result | Should -Be "ok"
            $script:callCount | Should -Be 2
        }

        It "Retries on HTTP 504 (Gateway Timeout)" {
            $script:callCount = 0
            $result = Invoke-WithRetry -ScriptBlock {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::GatewayTimeout)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("504 Gateway Timeout", $response)
                    throw $ex
                }
                "ok"
            } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "504Test"

            $result | Should -Be "ok"
            $script:callCount | Should -Be 2
        }

        It "Throws after exhausting max retries" {
            $script:callCount = 0
            {
                Invoke-WithRetry -ScriptBlock {
                    $script:callCount++
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("429 Too Many Requests", $response)
                    throw $ex
                } -MaxRetries 2 -InitialDelaySeconds 0 -OperationName "ExhaustTest"
            } | Should -Throw

            # Should attempt initial + MaxRetries
            $script:callCount | Should -Be 3
        }
    }

    Context "Non-retryable errors" {
        It "Throws immediately on HTTP 400 (Bad Request)" {
            $script:callCount = 0
            {
                Invoke-WithRetry -ScriptBlock {
                    $script:callCount++
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("400 Bad Request", $response)
                    throw $ex
                } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "400Test"
            } | Should -Throw

            $script:callCount | Should -Be 1
        }

        It "Throws immediately on HTTP 401 (Unauthorized)" {
            $script:callCount = 0
            {
                Invoke-WithRetry -ScriptBlock {
                    $script:callCount++
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Unauthorized)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("401 Unauthorized", $response)
                    throw $ex
                } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "401Test"
            } | Should -Throw

            $script:callCount | Should -Be 1
        }

        It "Throws immediately on HTTP 403 (Forbidden)" {
            $script:callCount = 0
            {
                Invoke-WithRetry -ScriptBlock {
                    $script:callCount++
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("403 Forbidden", $response)
                    throw $ex
                } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "403Test"
            } | Should -Throw

            $script:callCount | Should -Be 1
        }

        It "Throws immediately on HTTP 404 (Not Found)" {
            $script:callCount = 0
            {
                Invoke-WithRetry -ScriptBlock {
                    $script:callCount++
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound)
                    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("404 Not Found", $response)
                    throw $ex
                } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "404Test"
            } | Should -Throw

            $script:callCount | Should -Be 1
        }

        It "Throws immediately on non-HTTP errors" {
            $script:callCount = 0
            {
                Invoke-WithRetry -ScriptBlock {
                    $script:callCount++
                    throw "Generic error with no HTTP status"
                } -MaxRetries 3 -InitialDelaySeconds 0 -OperationName "GenericTest"
            } | Should -Throw

            $script:callCount | Should -Be 1
        }
    }
}

Describe "Get-ManagedIdentityToken" {
    Context "Missing environment variables" {
        It "Throws when IDENTITY_ENDPOINT is not set" {
            $script:originalEndpoint = $env:IDENTITY_ENDPOINT
            $script:originalHeader = $env:IDENTITY_HEADER
            try {
                $env:IDENTITY_ENDPOINT = $null
                $env:IDENTITY_HEADER = "test-header"

                { Get-ManagedIdentityToken -Resource "https://graph.microsoft.com" } | Should -Throw "*Managed Identity environment variables not found*"
            }
            finally {
                $env:IDENTITY_ENDPOINT = $originalEndpoint
                $env:IDENTITY_HEADER = $originalHeader
            }
        }

        It "Throws when IDENTITY_HEADER is not set" {
            $script:originalEndpoint = $env:IDENTITY_ENDPOINT
            $script:originalHeader = $env:IDENTITY_HEADER
            try {
                $env:IDENTITY_ENDPOINT = "https://localhost/token"
                $env:IDENTITY_HEADER = $null

                { Get-ManagedIdentityToken -Resource "https://graph.microsoft.com" } | Should -Throw "*Managed Identity environment variables not found*"
            }
            finally {
                $env:IDENTITY_ENDPOINT = $originalEndpoint
                $env:IDENTITY_HEADER = $originalHeader
            }
        }
    }

    Context "Successful token acquisition" {
        It "Calls IDENTITY_ENDPOINT with correct parameters" {
            $script:originalEndpoint = $env:IDENTITY_ENDPOINT
            $script:originalHeader = $env:IDENTITY_HEADER
            try {
                $env:IDENTITY_ENDPOINT = "https://localhost/msi/token"
                $env:IDENTITY_HEADER = "test-secret-header"

                Mock Invoke-RestMethod {
                    return @{ access_token = "mock-token-12345" }
                } -ModuleName AuditComplianceHelpers

                $token = Get-ManagedIdentityToken -Resource "https://graph.microsoft.com"
                $token | Should -Be "mock-token-12345"

                Should -Invoke Invoke-RestMethod -Times 1 -ModuleName AuditComplianceHelpers -ParameterFilter {
                    $Uri -like "*resource=https://graph.microsoft.com*" -and
                    $Headers["X-IDENTITY-HEADER"] -eq "test-secret-header" -and
                    $Headers["Metadata"] -eq "true"
                }
            }
            finally {
                $env:IDENTITY_ENDPOINT = $originalEndpoint
                $env:IDENTITY_HEADER = $originalHeader
            }
        }
    }
}

Describe "Get-DataverseToken" {
    It "Normalizes trailing slash in URL" {
        $originalEndpoint = $env:IDENTITY_ENDPOINT
        $originalHeader = $env:IDENTITY_HEADER
        try {
            $env:IDENTITY_ENDPOINT = "https://localhost/msi/token"
            $env:IDENTITY_HEADER = "test-header"

            Mock Invoke-RestMethod {
                return @{ access_token = "dv-token" }
            } -ModuleName AuditComplianceHelpers

            $token = Get-DataverseToken -DataverseEnvironmentUrl "https://org.crm.dynamics.com/"
            $token | Should -Be "dv-token"

            Should -Invoke Invoke-RestMethod -Times 1 -ModuleName AuditComplianceHelpers -ParameterFilter {
                # URL should not have trailing slash in resource parameter
                $Uri -like "*resource=https://org.crm.dynamics.com*" -and
                $Uri -notlike "*resource=https://org.crm.dynamics.com/*"
            }
        }
        finally {
            $env:IDENTITY_ENDPOINT = $script:originalEndpoint
            $env:IDENTITY_HEADER = $script:originalHeader
        }
    }
}

Describe "Write-DataverseComplianceRecord" {
    BeforeEach {
        $script:dvUrl = "https://org.crm.dynamics.com"
        $script:dvToken = "mock-token"

        $originalEndpoint = $env:IDENTITY_ENDPOINT
        $originalHeader = $env:IDENTITY_HEADER
        $env:IDENTITY_ENDPOINT = "https://localhost/msi/token"
        $env:IDENTITY_HEADER = "test-header"
    }

    AfterEach {
        $env:IDENTITY_ENDPOINT = $originalEndpoint
        $env:IDENTITY_HEADER = $originalHeader
    }

    Context "Upsert logic — create new record" {
        It "Upserts via alternate key PATCH (atomic create-or-update)" {
            $script:apiCalls = @()

            Mock Invoke-RestMethod {
                $script:apiCalls += @{ Uri = $Uri; Method = $Method; Body = $Body }

                if ($Method -eq "PATCH") {
                    return @{ fsi_auditenvironmentcomplianceid = "new-guid-123" }
                }
            } -ModuleName AuditComplianceHelpers

            Write-DataverseComplianceRecord `
                -EnvironmentUrl $script:dvUrl `
                -Token $script:dvToken `
                -EnvironmentId "env-001" `
                -EnvironmentName "Production" `
                -AuditEnabled $true `
                -DataverseAuditEnabled $false `
                -ComplianceStatus "Non-Compliant"

            # Should use a single PATCH with alternate key (no GET query)
            $patchCalls = $script:apiCalls | Where-Object { $_.Method -eq "PATCH" }
            $patchCalls.Count | Should -Be 1
            $patchUri = ($patchCalls | Select-Object -First 1).Uri
            $patchUri | Should -BeLike "*fsi_environmentid='env-001'*"
        }
    }

    Context "Upsert logic — update existing record" {
        It "Uses alternate key PATCH for updates (same mechanism as create)" {
            $script:apiCalls = @()

            Mock Invoke-RestMethod {
                $script:apiCalls += @{ Uri = $Uri; Method = $Method; Body = $Body }

                if ($Method -eq "PATCH") {
                    return @{ fsi_auditenvironmentcomplianceid = "existing-guid-456" }
                }
            } -ModuleName AuditComplianceHelpers

            Write-DataverseComplianceRecord `
                -EnvironmentUrl $script:dvUrl `
                -Token $script:dvToken `
                -EnvironmentId "env-002" `
                -EnvironmentName "Staging" `
                -AuditEnabled $true `
                -DataverseAuditEnabled $true `
                -ComplianceStatus "Compliant"

            # Should use a single PATCH with alternate key (no GET query)
            $patchCalls = $script:apiCalls | Where-Object { $_.Method -eq "PATCH" }
            $patchCalls.Count | Should -Be 1
            $patchUri = ($patchCalls | Select-Object -First 1).Uri
            $patchUri | Should -BeLike "*fsi_environmentid='env-002'*"
        }
    }
}

Describe "Send-ComplianceNotification" {
    Context "Payload construction" {
        It "Builds correct Graph sendMail payload" {
            $script:capturedBody = $null

            $env:IDENTITY_ENDPOINT = "https://localhost/msi/token"
            $env:IDENTITY_HEADER = "test-header"

            Mock Invoke-RestMethod {
                if ($Uri -like "*msi/token*") {
                    return @{ access_token = "graph-token" }
                }
                if ($Uri -like "*sendMail*") {
                    $script:capturedBody = $Body
                    return $null
                }
            } -ModuleName AuditComplianceHelpers

            Send-ComplianceNotification `
                -FromAddress "governance@example.com" `
                -ToAddresses @("admin@example.com", "compliance@example.com") `
                -Subject "Test Compliance Report" `
                -HtmlBody "<h1>Report</h1><p>Test body</p>"

            # Verify sendMail was called
            Should -Invoke Invoke-RestMethod -ModuleName AuditComplianceHelpers -ParameterFilter {
                $Uri -like "*sendMail*"
            }

            # Verify payload structure
            $payload = $script:capturedBody | ConvertFrom-Json
            $payload.message.subject | Should -Be "Test Compliance Report"
            $payload.message.body.contentType | Should -Be "HTML"
            $payload.message.toRecipients.Count | Should -Be 2
            $payload.saveToSentItems | Should -Be $false
        }

        It "Includes attachment when file path provided" {
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                "test,data`ncol1,col2" | Set-Content $tempFile -Encoding UTF8

                $script:capturedBody = $null

                $env:IDENTITY_ENDPOINT = "https://localhost/msi/token"
                $env:IDENTITY_HEADER = "test-header"

                Mock Invoke-RestMethod {
                    if ($Uri -like "*msi/token*") {
                        return @{ access_token = "graph-token" }
                    }
                    if ($Uri -like "*sendMail*") {
                        $script:capturedBody = $Body
                        return $null
                    }
                } -ModuleName AuditComplianceHelpers

                Send-ComplianceNotification `
                    -FromAddress "governance@example.com" `
                    -ToAddresses @("admin@example.com") `
                    -Subject "Report with Attachment" `
                    -HtmlBody "<p>See attached</p>" `
                    -AttachmentPath $tempFile `
                    -AttachmentName "report.csv"

                $payload = $script:capturedBody | ConvertFrom-Json
                $payload.message.attachments.Count | Should -Be 1
                $payload.message.attachments[0].name | Should -Be "report.csv"
                $payload.message.attachments[0].'@odata.type' | Should -Be "#microsoft.graph.fileAttachment"
                $payload.message.attachments[0].contentBytes | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "ComplianceStatusMap" {
    Context "Status string to option set mapping" {
        It "Maps 'Compliant' to 100000000" {
            $ComplianceStatusMap['Compliant'] | Should -Be 100000000
        }

        It "Maps 'Non-Compliant' to 100000001" {
            $ComplianceStatusMap['Non-Compliant'] | Should -Be 100000001
        }

        It "Maps 'Remediation Pending' to 100000002" {
            $ComplianceStatusMap['Remediation Pending'] | Should -Be 100000002
        }

        It "Maps 'Error' to 100000003" {
            $ComplianceStatusMap['Error'] | Should -Be 100000003
        }

        It "Contains exactly 4 status values" {
            $ComplianceStatusMap.Count | Should -Be 4
        }
    }

    Context "Reverse mapping (option set to string)" {
        It "Maps 100000000 to 'Compliant'" {
            $ComplianceStatusReverseMap[100000000] | Should -Be 'Compliant'
        }

        It "Maps 100000001 to 'Non-Compliant'" {
            $ComplianceStatusReverseMap[100000001] | Should -Be 'Non-Compliant'
        }

        It "Maps 100000002 to 'Remediation Pending'" {
            $ComplianceStatusReverseMap[100000002] | Should -Be 'Remediation Pending'
        }

        It "Maps 100000003 to 'Error'" {
            $ComplianceStatusReverseMap[100000003] | Should -Be 'Error'
        }
    }
}

Describe "Write-DataverseComplianceRecord — Status Validation" {
    It "Rejects invalid ComplianceStatus values" {
        {
            Write-DataverseComplianceRecord `
                -EnvironmentUrl "https://org.crm.dynamics.com" `
                -Token "test" `
                -EnvironmentId "env-x" `
                -EnvironmentName "Test" `
                -AuditEnabled $true `
                -DataverseAuditEnabled $true `
                -ComplianceStatus "InvalidStatus"
        } | Should -Throw
    }
}
