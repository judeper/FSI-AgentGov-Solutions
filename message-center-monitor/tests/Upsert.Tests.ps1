#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit tests for Invoke-McmDvUpsertMessage (C1 fix surface).

.DESCRIPTION
    Validates the conditional create -> 412 -> update branching that protects
    admin-owned columns from being clobbered on subsequent syncs.

    Each test captures the actual JSON body sent to Invoke-McmRest, parses it
    with ConvertFrom-Json, and asserts via SET INTERSECTION (not string match)
    that admin-owned columns are absent on the update branch and present-with-
    correct-default-value on the create branch.

    Council finding C1 -> these tests.

.NOTES
    Run with: Invoke-Pester -Path .\Upsert.Tests.ps1 -Output Detailed
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'governance' '_Common.ps1')

    $script:adminOwnedColumns = @(
        'fsi_assessmentstatus'
        'fsi_assessment'
        'fsi_assessedby'
        'fsi_assesseddate'
        'fsi_actionstaken'
        'fsi_impactsagents'
        'fsi_notifiedon'
    )

    $script:graphOwnedColumns = @(
        'fsi_messagecenterid'
        'fsi_title'
        'fsi_category'
        'fsi_severity'
        'fsi_services'
        'fsi_startdatetime'
        'fsi_lastmodifieddatetime'
        'fsi_ismajorchange'
        'fsi_body'
        'fsi_tags'
        'fsi_hasattachments'
    )

    function Get-FakeRecord {
        # Mirrors the $record hashtable built in Invoke-MessageCenterSync.ps1.
        # Deliberately EXCLUDES admin-owned columns - the function under test
        # relies on this contract.
        @{
            fsi_messagecenterid      = 'MC123456'
            fsi_title                = "Test 'tricky' message"
            fsi_category             = 100000001
            fsi_severity             = 100000001
            fsi_services             = 'Exchange, Teams'
            fsi_startdatetime        = '2026-04-16T00:00:00Z'
            fsi_lastmodifieddatetime = '2026-04-16T01:00:00Z'
            fsi_ismajorchange        = $true
            fsi_body                 = 'body content'
            fsi_tags                 = 'tag1, tag2'
            fsi_hasattachments       = $false
        }
    }

    function Get-FakeHeaders {
        @{
            Authorization      = 'Bearer fake'
            'Content-Type'     = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
            Prefer             = 'return=representation,odata.maxpagesize=500'
        }
    }

    function Get-McmHttpException {
        param([int]$Status, [string]$Message)
        # The function under test inspects the exception MESSAGE for status
        # tokens because Invoke-McmRest rethrows wrapped errors with text like
        # "Invoke-McmRest failed: status=412 method=Patch ...". We mimic that.
        [System.Exception]::new("Invoke-McmRest failed: status=$Status method=Patch uri=http://x error=$Message")
    }
}

Describe 'Invoke-McmDvUpsertMessage - create branch (row does not exist)' {

    BeforeEach {
        $script:capturedCalls = [System.Collections.Generic.List[hashtable]]::new()
        Mock -CommandName Invoke-McmRest -MockWith {
            $script:capturedCalls.Add(@{
                Uri     = $Uri
                Headers = $Headers
                Method  = $Method
                Body    = $Body
            })
            return $null
        }
    }

    It 'sends a single PATCH with If-None-Match: * on success' {
        $r = Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000

        $r.Action | Should -Be 'Created'
        $r.MessageId | Should -Be 'MC123456'
        $script:capturedCalls.Count | Should -Be 1
        $script:capturedCalls[0].Method | Should -Be 'Patch'
        $script:capturedCalls[0].Headers['If-None-Match'] | Should -Be '*'
    }

    It 'create payload includes fsi_assessmentstatus = NotAssessed' {
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $body = $script:capturedCalls[0].Body | ConvertFrom-Json -AsHashtable
        $body.fsi_assessmentstatus | Should -Be 100000000
    }

    It 'create payload includes ALL Graph-owned columns' {
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $body = $script:capturedCalls[0].Body | ConvertFrom-Json -AsHashtable
        foreach ($col in $script:graphOwnedColumns) {
            $body.ContainsKey($col) | Should -BeTrue -Because "create payload must include Graph-owned column $col"
        }
    }

    It 'URL uses alternate-key OData syntax with single-quote-escaped id' {
        $tricky = "MC'one"
        $rec = Get-FakeRecord
        $rec.fsi_messagecenterid = $tricky
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId $tricky `
            -Record $rec `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $script:capturedCalls[0].Uri | Should -Match "fsi_messagecenterlogs\(fsi_messagecenterid='MC''one'\)"
    }

    It 'does not mutate the caller-provided $Record hashtable' {
        $rec = Get-FakeRecord
        $beforeKeys = ($rec.Keys | Sort-Object) -join ','
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record $rec `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $afterKeys = ($rec.Keys | Sort-Object) -join ','
        $afterKeys | Should -Be $beforeKeys
        $rec.ContainsKey('fsi_assessmentstatus') | Should -BeFalse -Because 'caller record must remain pristine'
    }
}

Describe 'Invoke-McmDvUpsertMessage - update branch (row exists, 412)' {

    BeforeEach {
        $script:capturedCalls = [System.Collections.Generic.List[hashtable]]::new()
        $script:invocation = 0
        Mock -CommandName Invoke-McmRest -MockWith {
            $script:invocation++
            $script:capturedCalls.Add(@{
                Uri     = $Uri
                Headers = $Headers
                Method  = $Method
                Body    = $Body
            })
            if ($script:invocation -eq 1) {
                throw (Get-McmHttpException -Status 412 -Message 'PreconditionFailed')
            }
            return $null
        }
    }

    It 'returns Action=Updated and makes exactly two calls' {
        $r = Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000

        $r.Action | Should -Be 'Updated'
        $script:capturedCalls.Count | Should -Be 2
    }

    It 'second call OMITS If-None-Match header' {
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $script:capturedCalls[1].Headers.ContainsKey('If-None-Match') | Should -BeFalse `
            -Because 'update PATCH must not carry the create-only header or it would 412 again'
    }

    It 'update payload EXCLUDES every admin-owned column (set intersection)' {
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $body = $script:capturedCalls[1].Body | ConvertFrom-Json -AsHashtable
        $sentColumns = $body.Keys
        $admin = $script:adminOwnedColumns
        $intersection = @($sentColumns | Where-Object { $_ -in $admin })
        $intersection.Count | Should -Be 0 `
            -Because "update payload must not contain any admin-owned column. Found: $($intersection -join ', ')"
    }

    It 'update payload INCLUDES every Graph-owned column' {
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $body = $script:capturedCalls[1].Body | ConvertFrom-Json -AsHashtable
        foreach ($col in $script:graphOwnedColumns) {
            $body.ContainsKey($col) | Should -BeTrue -Because "update payload must refresh Graph-owned column $col"
        }
    }

    It 'update PATCH is sent to the SAME alternate-key URL as the create attempt' {
        Invoke-McmDvUpsertMessage `
            -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
            -MessageId 'MC123456' `
            -Record (Get-FakeRecord) `
            -DataverseHeaders (Get-FakeHeaders) `
            -AssessmentNotAssessedValue 100000000 | Out-Null

        $script:capturedCalls[0].Uri | Should -Be $script:capturedCalls[1].Uri
    }
}

Describe 'Invoke-McmDvUpsertMessage - failure paths' {

    It 'throws a helpful error when alternate key is missing (404)' {
        Mock -CommandName Invoke-McmRest -MockWith {
            throw (Get-McmHttpException -Status 404 -Message 'Resource not found for the segment')
        }

        {
            Invoke-McmDvUpsertMessage `
                -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
                -MessageId 'MC123456' `
                -Record (Get-FakeRecord) `
                -DataverseHeaders (Get-FakeHeaders) `
                -AssessmentNotAssessedValue 100000000
        } | Should -Throw -ExpectedMessage '*Alternate key fsi_MessageCenterIdKey not found*'
    }

    It 'rethrows on non-412/404 create failures' {
        Mock -CommandName Invoke-McmRest -MockWith {
            throw (Get-McmHttpException -Status 500 -Message 'Internal server error')
        }

        {
            Invoke-McmDvUpsertMessage `
                -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
                -MessageId 'MC123456' `
                -Record (Get-FakeRecord) `
                -DataverseHeaders (Get-FakeHeaders) `
                -AssessmentNotAssessedValue 100000000
        } | Should -Throw -ExpectedMessage '*Create failed for MC123456*'
    }

    It 'rethrows on update failure (412 then non-2xx on second call)' {
        $script:invocation = 0
        Mock -CommandName Invoke-McmRest -MockWith {
            $script:invocation++
            if ($script:invocation -eq 1) {
                throw (Get-McmHttpException -Status 412 -Message 'PreconditionFailed')
            }
            throw (Get-McmHttpException -Status 500 -Message 'Internal server error')
        }

        {
            Invoke-McmDvUpsertMessage `
                -DataverseBaseUrl 'https://x.crm.dynamics.com/api/data/v9.2' `
                -MessageId 'MC123456' `
                -Record (Get-FakeRecord) `
                -DataverseHeaders (Get-FakeHeaders) `
                -AssessmentNotAssessedValue 100000000
        } | Should -Throw -ExpectedMessage '*Update failed for MC123456*'
    }
}
