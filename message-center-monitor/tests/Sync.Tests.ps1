#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

<#
.SYNOPSIS
    Pester 5 orchestration tests for Invoke-MessageCenterSync.ps1.

.DESCRIPTION
    The C1 branching is unit-tested in Upsert.Tests.ps1 (against the extracted
    Invoke-McmDvUpsertMessage function). This file covers the remaining sync
    script responsibilities that are best validated by static-content checks
    against the script source: refactor wiring, body-truncation constant,
    category/severity defaults, and that admin-owned columns never appear in
    the $record literal.
#>

BeforeAll {
    $script:syncScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'governance' 'Invoke-MessageCenterSync.ps1')).Path
    $script:syncContent = Get-Content -LiteralPath $script:syncScript -Raw
}

Describe 'Invoke-MessageCenterSync.ps1 - refactor wiring' {
    It 'dot-sources _Common.ps1' {
        $script:syncContent | Should -Match '\.\s+\$PSScriptRoot.*_Common\.ps1|\.\s+(?:["'']|Join-Path)[^\n]*_Common\.ps1'
    }
    It 'invokes Invoke-McmDvUpsertMessage (C1 logic was extracted)' {
        $script:syncContent | Should -Match 'Invoke-McmDvUpsertMessage'
    }
    It 'no longer constructs the create payload inline (logic moved to helper)' {
        $script:syncContent | Should -Not -Match "createPayload\['fsi_assessmentstatus'\]"
    }
    It 'still parses cleanly' {
        $tk = $null; $pe = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:syncScript, [ref]$tk, [ref]$pe) | Out-Null
        $pe.Count | Should -Be 0
    }
}

Describe 'Invoke-MessageCenterSync.ps1 - $record literal hygiene' {

    It 'the $record hashtable does not assign any admin-owned column' {
        # Locate the $record = @{ ... } block and verify no admin-owned
        # column key appears inside it.
        $admin = @(
            'fsi_assessmentstatus'
            'fsi_assessment'
            'fsi_assessedby'
            'fsi_assesseddate'
            'fsi_actionstaken'
            'fsi_impactsagents'
            'fsi_notifiedon'
        )

        $blockMatch = [regex]::Match($script:syncContent, '(?ms)\$record\s*=\s*@\{(.+?)^\s*\}')
        $blockMatch.Success | Should -BeTrue -Because 'sync script must define a $record hashtable'

        $block = $blockMatch.Groups[1].Value
        foreach ($col in $admin) {
            $block | Should -Not -Match "\b$col\s*=" -Because "the per-message `$record literal must not include admin-owned column $col (it would be sent on the update path and clobber assessments)"
        }
    }
}

Describe 'Invoke-MessageCenterSync.ps1 - direct PATCH body invariant (council round 2 MEDIUM)' {

    # Background: the council-round-1 fix introduced a direct PATCH against
    # fsi_notifiedon AFTER a successful Teams webhook POST (sync.ps1 ~ line 471).
    # That direct PATCH deliberately bypasses Invoke-McmDvUpsertMessage and
    # therefore bypasses the C1 guard inside it. The $record literal hygiene
    # test above ($record = @{...}) does NOT catch a new admin column added
    # to this direct-PATCH body, because the direct-PATCH body is assigned
    # to a different variable (currently $dvPatchBody). A future contributor
    # who adds, say, fsi_assessmentstatus to the post-notify PATCH would
    # silently clobber every admin assessment on the next sync.
    #
    # This AST-based check enumerates every Invoke-McmRest call with
    # -Method matching PATCH, traces the -Body argument to its nearest
    # preceding hashtable assignment, and asserts no admin-owned column
    # other than fsi_notifiedon appears among the keys.

    It 'no Invoke-McmRest PATCH body writes any key except fsi_notifiedon (allowlist of one)' {
        # Round-3 strengthening: previously this test only forbade admin-owned
        # columns, which would let a non-admin key like fsi_title slip through.
        # The stated round-2 invariant is "the direct-PATCH path writes exactly
        # one key, fsi_notifiedon" - enforce that allowlist-of-one literally.
        $allowedInDirectPatch = @('fsi_notifiedon')

        $tk = $null; $pe = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:syncScript, [ref]$tk, [ref]$pe)
        $pe.Count | Should -Be 0

        $invokeMcmCalls = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Invoke-McmRest'
        }, $true)

        $checkedPatchCalls = 0
        foreach ($call in $invokeMcmCalls) {
            $isPatch         = $false
            $bodyArg         = $null
            $expectingMethod = $false
            $expectingBody   = $false

            foreach ($elem in $call.CommandElements) {
                if ($expectingMethod) {
                    if ($elem -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        $elem.Value -match '^patch$') {
                        $isPatch = $true
                    }
                    $expectingMethod = $false
                    continue
                }
                if ($expectingBody) {
                    $bodyArg = $elem
                    $expectingBody = $false
                    continue
                }
                if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                    switch ($elem.ParameterName) {
                        'Method' { $expectingMethod = $true }
                        'Body'   { $expectingBody   = $true }
                    }
                }
            }

            if (-not $isPatch -or -not $bodyArg) { continue }

            $bodyHashtable = $null
            if ($bodyArg -is [System.Management.Automation.Language.HashtableAst]) {
                $bodyHashtable = $bodyArg
            }
            elseif ($bodyArg -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $varName = $bodyArg.VariablePath.UserPath
                $assignment = $ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $n.Left.VariablePath.UserPath -eq $varName
                }, $true) |
                    Where-Object { $_.Extent.EndOffset -le $bodyArg.Extent.StartOffset } |
                    Sort-Object { $_.Extent.EndOffset } -Descending |
                    Select-Object -First 1

                if ($assignment) {
                    # Right side may be one of:
                    #   - HashtableAst              :  $b = @{...}
                    #   - CommandExpressionAst      :  $b = @{...}     (parsed as expression statement)
                    #   - PipelineAst with N elements:  $b = @{...} | ConvertTo-Json -Compress
                    # In all cases we look for a HashtableAst in the FIRST pipeline
                    # element so the C1 guard still inspects the keys regardless of
                    # whether the body is later piped to ConvertTo-Json.
                    $rhs = $assignment.Right
                    $firstExpr = $null
                    if ($rhs -is [System.Management.Automation.Language.PipelineAst]) {
                        $firstElem = $rhs.PipelineElements[0]
                        if ($firstElem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                            $firstExpr = $firstElem.Expression
                        }
                    }
                    elseif ($rhs -is [System.Management.Automation.Language.CommandExpressionAst]) {
                        $firstExpr = $rhs.Expression
                    }
                    elseif ($rhs -is [System.Management.Automation.Language.HashtableAst]) {
                        $firstExpr = $rhs
                    }
                    if ($firstExpr -is [System.Management.Automation.Language.HashtableAst]) {
                        $bodyHashtable = $firstExpr
                    }
                }
            }

            if (-not $bodyHashtable) {
                # Body is computed dynamically (splat, helper, etc.) and the
                # static check can't see the keys. Force a contributor adding
                # such a pattern to make the keys statically inspectable.
                throw "Invoke-McmRest PATCH at line $($call.Extent.StartLineNumber) has a non-hashtable -Body argument the AST guard cannot inspect. Rewrite the call so -Body is either an inline hashtable or a named variable assigned to a literal hashtable in the same script."
            }

            $checkedPatchCalls++
            $keys = @($bodyHashtable.KeyValuePairs | ForEach-Object { $_.Item1.Value })
            $keys | Should -HaveCount 1 -Because "direct PATCH at sync line $($call.Extent.StartLineNumber) must write exactly one key (the round-2 invariant). Found $($keys.Count) keys: $($keys -join ', '). If you genuinely need to write more columns, route them through Invoke-McmDvUpsertMessage (which enforces the C1 admin-column guard) instead of adding them to the direct-PATCH body."
            $keys[0] | Should -BeIn $allowedInDirectPatch -Because "direct PATCH at sync line $($call.Extent.StartLineNumber) writes key '$($keys[0])'; only $($allowedInDirectPatch -join ', ') is allowed on the direct-PATCH path. If you genuinely need to write '$($keys[0])', route it through Invoke-McmDvUpsertMessage or update the allowlist with a comment explaining why."
        }

        # Sanity: we expect at least one PATCH (the fsi_notifiedon write-back).
        # If the count drops to zero, either someone removed the write-back
        # (in which case re-syncs will re-post the same Teams alerts) or the
        # AST traversal broke - either way, fail loud.
        $checkedPatchCalls | Should -BeGreaterThan 0 -Because 'sync script must perform at least one Invoke-McmRest PATCH for the fsi_notifiedon write-back; the round-2 guard found none'
    }
}

Describe 'Invoke-MessageCenterSync.ps1 - Object output path exit-code invariant (council round 3 HIGH)' {

    # Background: round-2 added a $terminalFailures aggregate to gate `exit 1`
    # on notify failures. The first implementation handled the Object branch
    # separately - it set $global:LASTEXITCODE = 1 and then `return`ed early,
    # which BYPASSED the unified `exit 1` at the bottom of the script. For
    # `pwsh -File script.ps1`, $LASTEXITCODE does NOT propagate to the host
    # process exit code; only an explicit `exit N` statement does. Scheduled
    # callers using -OutputFormat Object would therefore see process exit = 0
    # even when notifications failed.
    #
    # This AST-based check enforces two invariants on the Object branch:
    #   (a) the Object branch contains no `return` statement
    #   (b) the file ends with `if ($terminalFailures -gt 0) { exit 1 }` at
    #       script scope (so all formats - Table, JSON, Object - flow through
    #       the unified exit-code logic).

    It 'the Object switch branch does not contain a return statement' {
        $tk = $null; $pe = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:syncScript, [ref]$tk, [ref]$pe)
        $pe.Count | Should -Be 0

        # Find the SwitchStatementAst that switches on $OutputFormat
        $switchStmt = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.SwitchStatementAst] -and
            $n.Condition -and
            $n.Condition.Extent.Text -match 'OutputFormat'
        }, $true) | Select-Object -First 1

        $switchStmt | Should -Not -BeNullOrEmpty -Because 'expected to find `switch ($OutputFormat) { ... }` in sync script'

        # Switch clauses are pairs of (condition, body). Find the 'Object' clause body.
        $objectClause = $null
        foreach ($pair in $switchStmt.Clauses) {
            $clauseLabel = $pair.Item1
            if ($clauseLabel -and $clauseLabel.Extent.Text -match "Object") {
                $objectClause = $pair.Item2  # StatementBlockAst
                break
            }
        }

        $objectClause | Should -Not -BeNullOrEmpty -Because 'expected `Object` clause in switch ($OutputFormat) { ... }'

        $returnInObject = $objectClause.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.ReturnStatementAst]
        }, $true)

        $returnInObject.Count | Should -Be 0 -Because "the Object branch must NOT contain a 'return' statement - 'return' here bypasses the unified `if (`$terminalFailures -gt 0) { exit 1 }` at the bottom of the script, causing scheduled -OutputFormat Object callers to see process exit = 0 even on notify failures. Emit `$summary` to the pipeline (without 'return') and let the fall-through exit logic run."
    }

    It 'the script ends with a unified exit-code gate on $terminalFailures' {
        $syncBody = Get-Content -LiteralPath $script:syncScript -Raw
        # The unified gate must appear AFTER the switch (i.e. it must run for
        # all OutputFormat values, including Object). We assert presence and
        # that there is no earlier `return` inside the switch that would
        # bypass it (covered by the test above).
        $syncBody | Should -Match 'if\s*\(\s*\$terminalFailures\s*-gt\s*0\s*\)\s*\{\s*exit\s+1\s*\}'
    }
}

Describe 'Invoke-MessageCenterSync.ps1 - constants and defaults' {
    It 'body truncation upper bound is 99990' {
        $script:syncContent | Should -Match '\$bodyMaxLength\s*=\s*99990'
    }
    It 'category default falls back to Admin (100000001) when category not in map' {
        $script:syncContent | Should -Match 'categoryValue\s*=\s*100000001'
    }
    It 'severity default falls back to Normal (100000001) when severity not in map' {
        $script:syncContent | Should -Match 'severityValue\s*=\s*100000001'
    }
    It 'truncation marker preserves original length' {
        $script:syncContent | Should -Match 'truncated.+original length'
    }
}
