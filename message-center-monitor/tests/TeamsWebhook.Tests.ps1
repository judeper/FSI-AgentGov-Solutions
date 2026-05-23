#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Pester 5 unit tests for Send-McmTeamsWebhook and Expand-McmCardTokens
    in _Common.ps1.

.DESCRIPTION
    Coverage:
      - Expand-McmCardTokens walks the parsed PSObject tree recursively
        and substitutes {token} placeholders in strings (inside hashtables
        and arrays at any depth).
      - Special-char safety: tokens containing double-quotes, newlines,
        backslashes, angle brackets, and unicode round-trip correctly
        through ConvertTo-Json / ConvertFrom-Json.
      - Send-McmTeamsWebhook loads the shared adaptive card template,
        strips the _comment field, wraps the rendered card in the Teams
        Workflows incoming-webhook envelope, and posts via Invoke-McmRest.
      - Returns Success on 2xx; returns Success=$false (no throw) when
        Invoke-McmRest throws after exhausted retries.
      - Throws on hard failures (template file missing).

    The webhook helper is intended to never block the sync loop on a single
    failed POST. Tests assert the no-throw behavior explicitly.

.NOTES
    Run with: Invoke-Pester -Path .\TeamsWebhook.Tests.ps1 -Output Detailed
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'governance' '_Common.ps1')

    $script:cardPath = Join-Path $PSScriptRoot '..' 'templates' 'teams-notification-card.json'

    function New-StandardTokens {
        @{
            severity                 = 'High'
            title                    = 'Test message'
            category                 = 'Admin'
            services                 = 'Exchange, Teams'
            startDateTime            = '2026-04-16T00:00:00Z'
            actionRequiredByDateTime = '2026-04-30T00:00:00Z'
            id                       = 'MC123456'
            environment              = 'contoso'
            appId                    = '00000000-0000-0000-0000-000000000001'
            publisherPrefix          = 'fsi'
            recordId                 = '11111111-2222-3333-4444-555555555555'
        }
    }
}

Describe 'Expand-McmCardTokens - simple substitution' {

    It 'substitutes a single token in a string value' {
        $node = @{ greeting = 'Hello {name}!' }
        $out = Expand-McmCardTokens -Node $node -Tokens @{ name = 'World' }
        $out.greeting | Should -Be 'Hello World!'
    }

    It 'substitutes multiple tokens in one string' {
        $node = @{ url = 'https://{env}.example.com/app/{appId}' }
        $out = Expand-McmCardTokens -Node $node -Tokens @{ env = 'contoso'; appId = 'abc' }
        $out.url | Should -Be 'https://contoso.example.com/app/abc'
    }

    It 'leaves unknown tokens as literal placeholders' {
        $node = @{ text = 'known={known} unknown={notReplaced}' }
        $out = Expand-McmCardTokens -Node $node -Tokens @{ known = 'yes' }
        $out.text | Should -Be 'known=yes unknown={notReplaced}'
    }

    It 'returns null when Node is null' {
        $out = Expand-McmCardTokens -Node $null -Tokens @{}
        $out | Should -BeNullOrEmpty
    }

    It 'returns scalars unchanged when not a string' {
        Expand-McmCardTokens -Node 42       -Tokens @{} | Should -Be 42
        Expand-McmCardTokens -Node $true    -Tokens @{} | Should -Be $true
    }

    It 'leaves strings without tokens untouched' {
        $node = @{ text = 'no tokens here' }
        $out = Expand-McmCardTokens -Node $node -Tokens @{ name = 'x' }
        $out.text | Should -Be 'no tokens here'
    }
}

Describe 'Expand-McmCardTokens - recursive structures' {

    It 'recurses into nested hashtables' {
        $node = @{
            level1 = @{
                level2 = @{
                    leaf = 'deep {token}'
                }
            }
        }
        $out = Expand-McmCardTokens -Node $node -Tokens @{ token = 'value' }
        $out.level1.level2.leaf | Should -Be 'deep value'
    }

    It 'recurses into arrays of strings' {
        $node = @{ items = @('a={x}', 'b={x}', 'c={x}') }
        $out = Expand-McmCardTokens -Node $node -Tokens @{ x = 'OK' }
        $out.items[0] | Should -Be 'a=OK'
        $out.items[1] | Should -Be 'b=OK'
        $out.items[2] | Should -Be 'c=OK'
    }

    It 'recurses into arrays of hashtables (typical Adaptive Card body)' {
        $node = @{
            body = @(
                @{ type = 'TextBlock'; text = '{title}' },
                @{ type = 'TextBlock'; text = '{subtitle}' }
            )
        }
        $out = Expand-McmCardTokens -Node $node -Tokens @{ title = 'Hello'; subtitle = 'World' }
        $out.body[0].text | Should -Be 'Hello'
        $out.body[1].text | Should -Be 'World'
    }
}

Describe 'Expand-McmCardTokens - special character safety' {

    It 'preserves double quotes in token values through JSON round-trip' {
        $node = @{ title = '{value}' }
        $tokens = @{ value = 'has "quoted" text' }
        $out = Expand-McmCardTokens -Node $node -Tokens $tokens
        $json = $out | ConvertTo-Json -Depth 5 -Compress
        $reparsed = $json | ConvertFrom-Json
        $reparsed.title | Should -Be 'has "quoted" text'
    }

    It 'preserves newlines in token values through JSON round-trip' {
        $node = @{ title = '{value}' }
        $tokens = @{ value = "line1`nline2" }
        $out = Expand-McmCardTokens -Node $node -Tokens $tokens
        $json = $out | ConvertTo-Json -Depth 5 -Compress
        $reparsed = $json | ConvertFrom-Json
        $reparsed.title | Should -Be "line1`nline2"
    }

    It 'preserves backslashes in token values through JSON round-trip' {
        $node = @{ title = '{value}' }
        $tokens = @{ value = 'path\to\file' }
        $out = Expand-McmCardTokens -Node $node -Tokens $tokens
        $json = $out | ConvertTo-Json -Depth 5 -Compress
        $reparsed = $json | ConvertFrom-Json
        $reparsed.title | Should -Be 'path\to\file'
    }

    It 'preserves angle brackets without HTML-escaping' {
        $node = @{ title = '{value}' }
        $tokens = @{ value = '<service> & "stuff"' }
        $out = Expand-McmCardTokens -Node $node -Tokens $tokens
        $json = $out | ConvertTo-Json -Depth 5 -Compress
        $reparsed = $json | ConvertFrom-Json
        $reparsed.title | Should -Be '<service> & "stuff"'
    }

    It 'preserves unicode characters through JSON round-trip' {
        $node = @{ title = '{value}' }
        $tokens = @{ value = 'caf' + [char]0x00E9 + ' uses ' + [char]0x4F60 + [char]0x597D }
        $out = Expand-McmCardTokens -Node $node -Tokens $tokens
        $json = $out | ConvertTo-Json -Depth 5 -Compress
        $reparsed = $json | ConvertFrom-Json
        $reparsed.title | Should -Be ('caf' + [char]0x00E9 + ' uses ' + [char]0x4F60 + [char]0x597D)
    }
}

Describe 'Send-McmTeamsWebhook - happy path' {

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

    It 'returns Success=$true on a successful POST' {
        $result = Send-McmTeamsWebhook -WebhookUrl 'https://outlook.office.com/webhook/x' `
            -CardTokens (New-StandardTokens) `
            -AdaptiveCardTemplatePath $script:cardPath
        $result.Success | Should -BeTrue
        $result.Error | Should -BeNullOrEmpty
    }

    It 'sends exactly one POST' {
        Send-McmTeamsWebhook -WebhookUrl 'https://outlook.office.com/webhook/x' `
            -CardTokens (New-StandardTokens) `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null
        $script:capturedCalls.Count | Should -Be 1
        $script:capturedCalls[0].Method | Should -Be 'Post'
    }

    It 'posts to the supplied webhook URL' {
        $url = 'https://outlook.office.com/webhook/abcdef'
        Send-McmTeamsWebhook -WebhookUrl $url `
            -CardTokens (New-StandardTokens) `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null
        $script:capturedCalls[0].Uri | Should -Be $url
    }

    It 'sends application/json Content-Type header' {
        Send-McmTeamsWebhook -WebhookUrl 'https://outlook.office.com/webhook/x' `
            -CardTokens (New-StandardTokens) `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null
        $script:capturedCalls[0].Headers['Content-Type'] | Should -Match 'application/json'
    }
}

Describe 'Send-McmTeamsWebhook - payload shape' {

    BeforeEach {
        $script:capturedCalls = [System.Collections.Generic.List[hashtable]]::new()
        Mock -CommandName Invoke-McmRest -MockWith {
            $script:capturedCalls.Add(@{
                Uri = $Uri; Headers = $Headers; Method = $Method; Body = $Body
            })
            return $null
        }
    }

    It 'wraps the card in Teams Workflows envelope (type=message, attachments[])' {
        Send-McmTeamsWebhook -WebhookUrl 'https://x' `
            -CardTokens (New-StandardTokens) `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null

        $body = $script:capturedCalls[0].Body | ConvertFrom-Json
        $body.type | Should -Be 'message'
        $body.attachments | Should -Not -BeNullOrEmpty
        $body.attachments.Count | Should -Be 1
        $body.attachments[0].contentType | Should -Be 'application/vnd.microsoft.card.adaptive'
        $body.attachments[0].content | Should -Not -BeNullOrEmpty
        $body.attachments[0].content.type | Should -Be 'AdaptiveCard'
    }

    It 'strips the _comment field from the card body' {
        Send-McmTeamsWebhook -WebhookUrl 'https://x' `
            -CardTokens (New-StandardTokens) `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null

        $body = $script:capturedCalls[0].Body | ConvertFrom-Json
        $card = $body.attachments[0].content
        $cardProperties = $card.PSObject.Properties.Name
        $cardProperties | Should -Not -Contain '_comment'
    }

    It 'substitutes standard tokens into the rendered card body' {
        Send-McmTeamsWebhook -WebhookUrl 'https://x' `
            -CardTokens (New-StandardTokens) `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null

        $script:capturedCalls[0].Body | ConvertFrom-Json | Out-Null
        # The serialized body string must contain the substituted concrete
        # values, and must NOT contain any unsubstituted {tokenName}
        # placeholders from the template's standard token vocabulary.
        $rawBody = $script:capturedCalls[0].Body
        $rawBody | Should -Match 'Test message'
        $rawBody | Should -Match 'MC123456'
        $rawBody | Should -Match '11111111-2222-3333-4444-555555555555'

        foreach ($tokenName in (New-StandardTokens).Keys) {
            $rawBody | Should -Not -Match ('\{' + [regex]::Escape($tokenName) + '\}') `
                -Because "token '{$tokenName}' must be substituted in the rendered payload"
        }
    }

    It 'handles a title with embedded double quotes safely' {
        $tokens = New-StandardTokens
        $tokens.title = 'Action required: "MC123" outage'
        Send-McmTeamsWebhook -WebhookUrl 'https://x' `
            -CardTokens $tokens `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null

        # The captured body must be parseable JSON (object substitution
        # preserves quote escaping; naive string.Replace would not).
        $body = $script:capturedCalls[0].Body | ConvertFrom-Json
        $body | Should -Not -BeNullOrEmpty

        # And the title must be intact end-to-end.
        $rawBody = $script:capturedCalls[0].Body
        $rawBody | Should -Match 'Action required'
        $rawBody | Should -Match 'outage'
    }

    It 'handles a title with embedded newlines safely' {
        $tokens = New-StandardTokens
        $tokens.title = "Line A`nLine B"
        Send-McmTeamsWebhook -WebhookUrl 'https://x' `
            -CardTokens $tokens `
            -AdaptiveCardTemplatePath $script:cardPath | Out-Null

        $body = $script:capturedCalls[0].Body | ConvertFrom-Json
        $body | Should -Not -BeNullOrEmpty
    }
}

Describe 'Send-McmTeamsWebhook - failure handling (no-throw contract)' {

    It 'returns Success=$false on HTTP failure without throwing' {
        Mock -CommandName Invoke-McmRest -MockWith {
            throw 'Invoke-McmRest failed: status=400 method=Post uri=https://x error=Bad Request'
        }

        # Capture both the result AND any exception in one go - the
        # scriptblock + pipeline pattern creates a child scope, so use a
        # try/catch and let the test fail loudly if the helper throws.
        $threw = $false
        $result = $null
        try {
            $result = Send-McmTeamsWebhook -WebhookUrl 'https://x' `
                -CardTokens (New-StandardTokens) `
                -AdaptiveCardTemplatePath $script:cardPath
        } catch {
            $threw = $true
        }

        $threw          | Should -BeFalse -Because 'Send-McmTeamsWebhook must never throw on HTTP failure'
        $result         | Should -Not -BeNullOrEmpty
        $result.Success | Should -BeFalse
        $result.Error   | Should -Not -BeNullOrEmpty
        $result.Error   | Should -Match 'status=400'
    }

    It 'returns Success=$false on persistent 5xx after retries' {
        Mock -CommandName Invoke-McmRest -MockWith {
            throw 'Invoke-McmRest failed: status=503 method=Post uri=https://x error=Service Unavailable'
        }

        $threw = $false
        $result = $null
        try {
            $result = Send-McmTeamsWebhook -WebhookUrl 'https://x' `
                -CardTokens (New-StandardTokens) `
                -AdaptiveCardTemplatePath $script:cardPath
        } catch {
            $threw = $true
        }

        $threw          | Should -BeFalse -Because 'Send-McmTeamsWebhook must never throw on HTTP failure'
        $result         | Should -Not -BeNullOrEmpty
        $result.Success | Should -BeFalse
        $result.Error   | Should -Match 'status=503'
    }
}

Describe 'Send-McmTeamsWebhook - hard failures (throw)' {

    It 'throws when the template file does not exist' {
        Mock -CommandName Invoke-McmRest -MockWith { return $null }
        $missing = Join-Path $PSScriptRoot 'definitely-not-a-real-template.json'
        { Send-McmTeamsWebhook -WebhookUrl 'https://x' `
                -CardTokens (New-StandardTokens) `
                -AdaptiveCardTemplatePath $missing } | Should -Throw
    }
}
