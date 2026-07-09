#Requires -Version 7.2

<#
.SYNOPSIS
    Converts owner-attestation responses into the CAI People-capability artifact shape the
    Find-No-Filter (FNF) People-Sweep lens consumes, stamping peopleCapableSource = attested.

.DESCRIPTION
    For the manifest-opaque tier of FNF declarative agents (the Agent-Builder "shared by
    creator" long tail whose declarativeAgent.json cannot be read by any supported admin API or
    telemetry signal - see SPIKE-manifest-acquisition and R6-people-telemetry-signal), the only
    path to a People (Org Chart & Profile) capability determination is MANUAL OWNER ATTESTATION.

    This converter takes the owners' yes/no responses - keyed by the REAL Dataverse bot / Entra
    Agent ID from the Microsoft 365 Agent Registry CSV export, NOT a provisional manifest stem -
    and emits a capability artifact that is shape-compatible with detect_people_capability.py
    (copilot-agent-inventory). Each affirmative response becomes an fsi_caiagentfeature row with
    fsi_featuretype = "People (Org Chart & Profile)", fsi_isenabled = $true, and the attested
    provenance markers (fsi_detectionsource = "Owner Attestation", fsi_detectionconfidence =
    "Attested (owner attestation)"). The FNF lens classifier Get-FnfPeopleCapabilitySource reads
    those markers and reports peopleCapableSource = attested, so attestation-covered agents flow
    into the same per-agent FNF People-Sweep report as manifest-detected agents - and the lens
    folds the gap manifest-opaque-attestation-pending into each such agent's coverageStatus, so
    an attested determination is never presented with the same confidence as a manifest read.

    The conversion is defensive by design (mirroring the lens's never-silent posture):

      - The agent id MUST be the real Registry id. An empty id, or the literal provisional
        manifest stem "declarativeAgent", is rejected (never silently joined to a real agent).
      - An unrecognized people-capable answer is rejected (never silently coerced to "no",
        which would under-report People-capable agents - the same silent-zero failure mode the
        lens guards against).
      - Conflicting duplicate responses for one agent (one "yes", one "no") are rejected;
        agreeing duplicates are collapsed.
      - All row errors are collected and reported together so the operator fixes the response
        file in one pass rather than one row at a time.

    By default a "no" response is emitted as a declared-but-disabled row (fsi_isenabled = $false)
    so the artifact is a complete record of the attestation campaign; the lens skips disabled
    rows. Use -PeopleCapableOnly to emit only affirmative rows.

    This script writes a report/inventory artifact (JSON), NOT Dataverse rows or any Power
    Platform runtime artifact. Persistence is performed by the consuming CAI/CBG flow.

    The functions are defined at top level so the script can be dot-sourced (with a placeholder
    argument) in Pester tests; the main body runs only on direct invocation.

.PARAMETER ResponsePath
    Path to the attestation responses file. CSV or JSON (see -Format). The canonical response
    columns / keys are: agentId (required, the real Registry bot/agent id), agentName,
    peopleCapable (required, yes/no), environmentId, attestedBy, attestedAt, attestationId,
    notes. See templates/owner-attestation-responses.sample.csv / .json.

.PARAMETER Format
    Input format: Auto (default, by file extension), Csv, or Json. JSON accepts a bare array, a
    { "responses": [...] } wrapper, or a { "value": [...] } envelope.

.PARAMETER OutputPath
    Optional path to write the capability artifact JSON. When omitted the artifact object is
    written to the pipeline only.

.PARAMETER RunId
    Optional run id stamped onto fsi_runid and summary.runId. Defaults to
    fnf-attestation-<unix-seconds>.

.PARAMETER DetectionSource
    The provenance label stamped onto fsi_detectionsource (and summary.detectionSource). Must
    contain "attest" so the lens classifies the rows as attested. Default "Owner Attestation".

.PARAMETER EnvironmentId
    Optional default fsi_environmentid stamped onto rows whose response omits environmentId.

.PARAMETER PeopleCapableOnly
    Emit only affirmative (People-capable) rows. By default "no" responses are emitted as
    declared-but-disabled (fsi_isenabled = $false) rows for a complete attestation record.

.EXAMPLE
    PS> .\Convert-AttestationToCapabilityRows.ps1 -ResponsePath .\responses.csv `
            -OutputPath .\cai-people-attested.json
    Converts a CSV of owner responses into the attested capability artifact, ready to pass to
    Get-FnfPeopleSweepReport.ps1 -CapabilityArtifactPath.

.EXAMPLE
    PS> .\Convert-AttestationToCapabilityRows.ps1 -ResponsePath .\responses.json -PeopleCapableOnly |
            ConvertTo-Json -Depth 12
    Emits only People-capable attested rows to the pipeline.

.NOTES
    Field names under features[] are Dataverse LOGICAL names for fsi_caiagentfeature rows;
    picklist fields carry the option-set LABEL (the CAI convention - the writer resolves the
    label to the integer value at upsert time). Authentication is not required: this is a pure
    local file transform.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResponsePath,

    [Parameter()]
    [ValidateSet('Auto', 'Csv', 'Json')]
    [string]$Format = 'Auto',

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$RunId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DetectionSource = 'Owner Attestation',

    [Parameter()]
    [string]$EnvironmentId,

    [Parameter()]
    [switch]$PeopleCapableOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------------------
# Constants (mirror detect_people_capability.py so attested rows match the manifest-detected
# row shape the FNF lens consumes).
# --------------------------------------------------------------------------------------

# The declarative-agent People capability feature-type label (CAI PEOPLE_FEATURE_TYPE). MUST
# match the lens constant $script:PeopleFeatureType exactly or the lens will not select the row.
$script:AttPeopleFeatureType = 'People (Org Chart & Profile)'

# CAI fsi_caiagentfeature constants for a People row (mirror detect_people_capability.py).
$script:AttPeopleSourceObjectId = 'capability:People'
$script:AttPeopleSourceObjectName = 'People'
$script:AttPeopleRelationship = 'declarativeAgent.capabilities'

# Attested confidence label. Contains "Attested" so Get-FnfPeopleCapabilitySource (which matches
# (?i)attest on fsi_detectionconfidence or fsi_detectionsource) classifies the row as attested.
$script:AttPeopleConfidence = 'Attested (owner attestation)'

# Artifact schema version (mirrors the CAI detect_people_capability.py output).
$script:AttSchemaVersion = '0.2.0-preview'

# Provisional manifest stems that are NOT real agent ids. The Toolkit emits the literal
# "declarativeAgent" id for every appPackage/declarativeAgent.json, so it is identical across
# distinct agents and must never be used as a join key (SEAM 1). An attestation MUST carry the
# real Registry bot/agent id instead.
$script:AttProvisionalStems = @('declarativeAgent')

# Accepted people-capable answer tokens (trimmed, case-insensitive).
$script:AttAffirmative = @('yes', 'y', 'true', 't', '1', 'enabled', 'people-capable', 'capable')
$script:AttNegative = @('no', 'n', 'false', 'f', '0', 'disabled', 'not-capable', 'not-people-capable')

# --------------------------------------------------------------------------------------
# Safe, case-insensitive field access under Set-StrictMode -Version Latest. Accepts one or more
# candidate names (aliases) and returns the first that exists; tolerates PSCustomObject (JSON /
# CSV import) and IDictionary (in-memory hashtable) inputs.
# --------------------------------------------------------------------------------------
function Get-FnfAttField {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string[]]$Name,
        [Parameter()]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    foreach ($n in $Name) {
        if ($InputObject -is [System.Collections.IDictionary]) {
            foreach ($k in @($InputObject.Keys)) {
                if ([string]$k -ieq $n) { return $InputObject[$k] }
            }
        }
        else {
            $prop = $InputObject.PSObject.Properties | Where-Object { $_.Name -ieq $n } | Select-Object -First 1
            if ($null -ne $prop) { return $prop.Value }
        }
    }
    return $Default
}

# --------------------------------------------------------------------------------------
# Normalize a people-capable answer token to $true (capable) / $false (not capable) / $null
# (unrecognized - the caller MUST treat $null as a validation error, never as "no").
# --------------------------------------------------------------------------------------
function ConvertTo-FnfAttestationBool {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter()][AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    $token = ([string]$Value).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($token)) { return $null }
    if ($script:AttAffirmative -contains $token) { return $true }
    if ($script:AttNegative -contains $token) { return $false }
    return $null
}

# --------------------------------------------------------------------------------------
# Read attestation responses from a CSV or JSON file into a flat list of response objects.
# JSON accepts a bare array, a { responses: [...] } wrapper, or a { value: [...] } envelope.
# --------------------------------------------------------------------------------------
function Get-FnfAttestationResponse {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][ValidateSet('Auto', 'Csv', 'Json')][string]$Format = 'Auto'
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Attestation response file not found: $Path" }

    $effectiveFormat = $Format
    if ($effectiveFormat -eq 'Auto') {
        $ext = [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()
        $effectiveFormat = if ($ext -eq 'csv') { 'Csv' } elseif ($ext -in @('json', 'jsonl')) { 'Json' } else { 'Csv' }
    }

    if ($effectiveFormat -eq 'Csv') {
        return @(Import-Csv -LiteralPath $Path)
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json

    # Unwrap a { responses: [...] } or { value: [...] } envelope; otherwise treat as an array.
    $responses = $parsed
    if ($parsed -isnot [System.Array]) {
        $wrapped = Get-FnfAttField -InputObject $parsed -Name @('responses', 'value')
        if ($null -ne $wrapped) { $responses = $wrapped }
    }
    return @($responses)
}

# --------------------------------------------------------------------------------------
# Build one fsi_caiagentfeature People row from a single attestation response. The shape mirrors
# detect_people_capability.py exactly so the row is indistinguishable to the lens except for the
# attested provenance markers (which drive peopleCapableSource = attested).
# --------------------------------------------------------------------------------------
function New-FnfAttestedCapabilityRow {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'New-FnfAttestedCapabilityRow is a pure builder: it folds already-validated response fields into an in-memory hashtable and changes no system state. ShouldProcess is not applicable.')]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter()][AllowNull()][string]$AgentName,
        [Parameter()][AllowNull()][string]$EnvironmentId,
        [Parameter(Mandatory)][bool]$IsEnabled,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$DetectionSource,
        [Parameter()][AllowNull()][string]$AttestedBy,
        [Parameter()][AllowNull()][string]$AttestedAt,
        [Parameter()][AllowNull()][string]$AttestationId,
        [Parameter()][AllowNull()][string]$Notes
    )

    $display = if (-not [string]::IsNullOrWhiteSpace($AgentName)) { $AgentName } else { $AgentId }
    $scannedAt = if (-not [string]::IsNullOrWhiteSpace($AttestedAt)) { $AttestedAt } else { (Get-Date).ToUniversalTime().ToString('o') }

    $detail = [ordered]@{
        source              = $DetectionSource
        capabilityName      = $script:AttPeopleSourceObjectName
        attestedVia         = 'owner-attestation'
        attestedBy          = $AttestedBy
        attestedAt          = $AttestedAt
        attestationId       = $AttestationId
        notes               = $Notes
        agentRefProvisional = $false
        peopleCapable       = $IsEnabled
    }

    return [ordered]@{
        fsi_name                = "$($script:AttPeopleFeatureType): $display"
        fsi_agentid             = $AgentId
        fsi_environmentid       = $EnvironmentId
        fsi_featuretype         = $script:AttPeopleFeatureType
        fsi_componenttype       = $null
        fsi_componentversion    = 'Not Applicable'
        fsi_sourceobjectid      = $script:AttPeopleSourceObjectId
        fsi_sourceobjectname    = $script:AttPeopleSourceObjectName
        fsi_relationshipname    = $script:AttPeopleRelationship
        fsi_detectionsource     = $DetectionSource
        fsi_detectionconfidence = $script:AttPeopleConfidence
        fsi_detectiondetail     = ($detail | ConvertTo-Json -Compress -Depth 5)
        fsi_agentrefprovisional = $false
        fsi_isenabled           = $IsEnabled
        fsi_lastscannedat       = $scannedAt
        fsi_runid               = $RunId
    }
}

# --------------------------------------------------------------------------------------
# Validate and convert a list of attestation responses into the capability artifact object
# ({ schemaVersion, summary, agents[], features[] }). All row-level errors are collected and
# thrown together. Conflicting duplicate responses for one agent are an error; agreeing
# duplicates are collapsed.
# --------------------------------------------------------------------------------------
function ConvertTo-FnfAttestationArtifact {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()][object[]]$Response = @(),
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$DetectionSource,
        [Parameter()][AllowNull()][string]$DefaultEnvironmentId,
        [Parameter()][switch]$PeopleCapableOnly
    )

    if ($DetectionSource -notmatch '(?i)attest') {
        throw "DetectionSource '$DetectionSource' must contain 'attest' so the FNF lens classifies the rows as peopleCapableSource=attested."
    }

    $errors = New-Object System.Collections.Generic.List[string]
    # Map of normalized-lowercase agent id -> @{ AgentId; IsEnabled; rows[] } for duplicate folding.
    $byAgent = [ordered]@{}

    $rowIndex = 0
    foreach ($resp in @($Response)) {
        $rowIndex++
        $agentIdRaw = Get-FnfAttField -InputObject $resp -Name @('agentId', 'fsi_agentid', 'botId', 'agentid')
        $agentId = if ($null -ne $agentIdRaw) { ([string]$agentIdRaw).Trim() } else { '' }
        $peopleRaw = Get-FnfAttField -InputObject $resp -Name @('peopleCapable', 'people_capable', 'hasPeople', 'answer', 'response')

        if ([string]::IsNullOrWhiteSpace($agentId)) {
            $errors.Add("row ${rowIndex}: missing agentId (the real Microsoft 365 Agent Registry bot/agent id is required).")
            continue
        }
        if ($script:AttProvisionalStems -contains $agentId) {
            $errors.Add("row ${rowIndex}: agentId '$agentId' is a provisional manifest stem, not a real agent id. Use the agent's real bot/agent id from the Agent Registry CSV export.")
            continue
        }

        $state = ConvertTo-FnfAttestationBool -Value $peopleRaw
        if ($null -eq $state) {
            $shown = if ($null -ne $peopleRaw) { [string]$peopleRaw } else { '' }
            $errors.Add("row ${rowIndex} (agent '$agentId'): unrecognized peopleCapable value '$shown'. Expected yes/no (also accepted: $([string]::Join(', ', $script:AttAffirmative)) / $([string]::Join(', ', $script:AttNegative))).")
            continue
        }

        $agentName = [string](Get-FnfAttField -InputObject $resp -Name @('agentName', 'fsi_agentname', 'name'))
        $envId = [string](Get-FnfAttField -InputObject $resp -Name @('environmentId', 'fsi_environmentid', 'environment'))
        if ([string]::IsNullOrWhiteSpace($envId)) { $envId = [string]$DefaultEnvironmentId }
        $attestedBy = [string](Get-FnfAttField -InputObject $resp -Name @('attestedBy', 'owner', 'ownerUpn', 'respondent'))
        $attestedAt = [string](Get-FnfAttField -InputObject $resp -Name @('attestedAt', 'respondedAt', 'timestamp', 'date'))
        $attestationId = [string](Get-FnfAttField -InputObject $resp -Name @('attestationId', 'responseId', 'ticket', 'caseId'))
        $notes = [string](Get-FnfAttField -InputObject $resp -Name @('notes', 'comment', 'comments'))

        $key = $agentId.ToLowerInvariant()
        $record = [pscustomobject]@{
            AgentId       = $agentId
            AgentName     = $agentName
            EnvironmentId = $envId
            IsEnabled     = $state
            AttestedBy    = $attestedBy
            AttestedAt    = $attestedAt
            AttestationId = $attestationId
            Notes         = $notes
        }

        if ($byAgent.Contains($key)) {
            $existing = $byAgent[$key]
            if ($existing.Record.IsEnabled -ne $state) {
                $errors.Add("agent '$agentId': conflicting attestation responses (both People-capable=yes and =no). Resolve the duplicate before converting.")
            }
            $existing.Count++
            continue
        }
        $byAgent[$key] = [pscustomobject]@{ Record = $record; Count = 1 }
    }

    if ($errors.Count -gt 0) {
        $cap = [Math]::Min($errors.Count, 25)
        $sample = [string]::Join([Environment]::NewLine + '  - ', @($errors)[0..($cap - 1)])
        $more = if ($errors.Count -gt $cap) { "$([Environment]::NewLine)  ... and $($errors.Count - $cap) more." } else { '' }
        throw "Attestation response file has $($errors.Count) invalid row(s); no artifact was produced:$([Environment]::NewLine)  - $sample$more"
    }

    $features = New-Object System.Collections.Generic.List[object]
    $agents = New-Object System.Collections.Generic.List[object]
    $enabledCount = 0
    $disabledCount = 0
    $duplicatesCollapsed = 0

    foreach ($entry in $byAgent.Values) {
        $r = $entry.Record
        $duplicatesCollapsed += ($entry.Count - 1)
        if ($r.IsEnabled) { $enabledCount++ } else { $disabledCount++ }

        if ($PeopleCapableOnly -and -not $r.IsEnabled) { continue }

        $features.Add((New-FnfAttestedCapabilityRow `
                    -AgentId $r.AgentId -AgentName $r.AgentName -EnvironmentId $r.EnvironmentId `
                    -IsEnabled $r.IsEnabled -RunId $RunId -DetectionSource $DetectionSource `
                    -AttestedBy $r.AttestedBy -AttestedAt $r.AttestedAt -AttestationId $r.AttestationId `
                    -Notes $r.Notes))

        $agents.Add([ordered]@{
                agentId            = $r.AgentId
                agentName          = if (-not [string]::IsNullOrWhiteSpace($r.AgentName)) { $r.AgentName } else { $r.AgentId }
                agentIdProvisional = $false
                peopleCapable      = $r.IsEnabled
                attestationSource  = $DetectionSource
                attestedBy         = $r.AttestedBy
                attestedAt         = $r.AttestedAt
                attestationId      = $r.AttestationId
            })
    }

    return [pscustomobject]@{
        schemaVersion = $script:AttSchemaVersion
        summary       = [ordered]@{
            runId                 = $RunId
            detectionSource       = $DetectionSource
            attestationSource     = $DetectionSource
            generatedAt           = (Get-Date).ToUniversalTime().ToString('o')
            responsesProcessed    = @($Response).Count
            uniqueAgents          = $byAgent.Count
            peopleDetected        = $enabledCount
            notPeopleCapableCount = $disabledCount
            duplicatesCollapsed   = $duplicatesCollapsed
            provisionalAgentIds   = 0
            peopleCapableOnly     = [bool]$PeopleCapableOnly
        }
        agents        = $agents.ToArray()
        features      = $features.ToArray()
    }
}

# ======================================================================================
# Main (runs only on direct invocation; dot-sourcing for tests skips this block).
# ======================================================================================
if ($MyInvocation.InvocationName -ne '.') {

    $effectiveRunId = if (-not [string]::IsNullOrWhiteSpace($RunId)) { $RunId } else { "fnf-attestation-$([int][double]::Parse((Get-Date -UFormat %s)))" }

    $responses = @(Get-FnfAttestationResponse -Path $ResponsePath -Format $Format)
    if ($responses.Count -eq 0) {
        Write-Warning "No attestation responses found in '$ResponsePath'; an empty capability artifact will be produced."
    }

    $artifact = ConvertTo-FnfAttestationArtifact -Response $responses -RunId $effectiveRunId `
        -DetectionSource $DetectionSource -DefaultEnvironmentId $EnvironmentId -PeopleCapableOnly:$PeopleCapableOnly

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $artifact | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        Write-Verbose "Wrote attested capability artifact to $OutputPath."
    }

    $s = $artifact.summary
    Write-Host "FNF owner attestation: $($s.responsesProcessed) response(s) -> $($s.uniqueAgents) unique agent(s); $($s.peopleDetected) People-capable (attested), $($s.notPeopleCapableCount) not, $($s.duplicatesCollapsed) duplicate(s) collapsed."
    Write-Host "These rows carry peopleCapableSource=attested; the FNF lens reports each as coverageStatus=Partial with gap 'manifest-opaque-attestation-pending' (attested != manifest-confirmed)."

    Write-Output $artifact
}
