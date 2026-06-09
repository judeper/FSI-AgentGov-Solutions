<#
.SYNOPSIS
    Tier-A (configuration) detector for Microsoft 365 Work IQ usage across
    Copilot Studio and Copilot agents.

.DESCRIPTION
    Reads the agent master record (fsi_copilotagent, owned by the
    copilot-agent-inventory solution) and, for each agent, samples Dataverse
    botcomponent and aipluginoperation metadata to classify the agent's Work IQ
    configuration pathway (configuredTier). The agent master carries
    fsi_environmentid (the source-environment GUID) but not that environment's
    Dataverse URL; the per-environment URL is resolved from the sibling
    fsi_caienvironment table (fsi_environmenturl) so each botcomponent sample runs
    against the agent's own environment, never the governance environment. This is
    the configuration tier only;
    it deliberately does NOT assert that Work IQ was invoked at runtime. Observed
    usage is established by joining this output with the Tier-B telemetry queries
    (scripts/kql/workiq-tierB-*.kql) in the nightly classify flow, which then
    writes the canonical four-state fsi_wiqstate rows.

    Two-tier rule (never conflate configured vs invoked):
      Tier-A (this script)  -> configuredTier from Dataverse metadata.
      Tier-B (KQL/Audit)    -> invocation signals from runtime telemetry.

    configuredTier values:
      NativeMcpCopilotStudio - native Work IQ MCP tool identifiers present in
                               botcomponent / aipluginoperation; keyed on the
                               Azure Resource Graph createdIn value supplied by
                               copilot-agent-inventory.
      NativeApiDirect        - native Work IQ API invocation configured directly
                               (not via Copilot Studio authoring).
      Adjacent               - no native Work IQ tool, but knowledge components
                               (componenttype 16) referencing SharePoint / Graph /
                               M365 connectors, botcomponent dvtablesearch, or
                               generative-AI configuration are present.
      NotConfigured          - none of the above.

    Build-time guard (verified): bot.generativeaiconfiguration is NOT a real
    Dataverse column. Work IQ configuration is sampled from botcomponent
    component types 18 / 15 / 16 (and, where needed, bot.configuration), not from
    a generativeaiconfiguration column.

    All Dataverse OData ($select / $filter) uses logical names (all-lowercase,
    no underscores between words).

.PARAMETER DataverseUrl
    URL of the governance Dataverse environment that hosts fsi_copilotagent
    (e.g. https://org.crm.dynamics.com).

.PARAMETER WorkIqMcpToolNames
    One or more Work IQ MCP tool identifiers to match in botcomponent /
    aipluginoperation content. Defaults to the verified preview identifier
    'use-work-iq'. Build GA-ready: update after Work IQ GA (2026-06-16).

.PARAMETER AuthMode
    Authentication mode, managed-identity-first. One of ManagedIdentity,
    WorkloadIdentity, Interactive, ClientSecret. Defaults to ManagedIdentity.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for Interactive and ClientSecret modes.

.PARAMETER ClientId
    App registration or user-assigned managed identity client ID.

.PARAMETER ClientSecret
    Client secret as a SecureString. Legacy dev-only fallback; prefer a managed
    identity in production.

.PARAMETER Top
    Optional safety cap on the number of agents processed (0 = no cap).

.EXAMPLE
    . ./Get-WorkIqConfigState.ps1
    Get-WorkIqConfigState -DataverseUrl 'https://org.crm.dynamics.com'

    Classifies every fsi_copilotagent using the default managed identity.

.EXAMPLE
    . ./Get-WorkIqConfigState.ps1
    Get-WorkIqConfigState -DataverseUrl 'https://org.crm.dynamics.com' `
        -AuthMode Interactive -TenantId $env:WIQ_TENANT_ID |
        ConvertTo-Json -Depth 6 | Out-File tierA-config.json

    Emits Tier-A configuration objects ready to join with Tier-B telemetry.

.NOTES
    File: Get-WorkIqConfigState.ps1
    Solution: Work IQ Usage Detection (work-iq-usage-detection)
    Controls: 2.24 (primary), 3.2, 2.9
    Status: 0.1.0-preview skeleton. Deep content parsing of MCP tool identifiers
            inside botcomponent payloads is marked as an extension point.
    Authentication: managed-identity-first (see AGENTS.md Coding Patterns).

.LINK
    https://github.com/judeper/FSI-AgentGov
#>

#Requires -Version 7.4

[CmdletBinding()]
param()

# Verified botcomponent component types to sample for Work IQ configuration.
# 16 = Knowledge source; 15 and 18 are the generative/config-bearing component
# types. bot.generativeaiconfiguration is NOT a column (build-time verified).
$script:WiqBotComponentTypes = @(18, 15, 16)

function Get-WiqDataverseToken {
    <#
    .SYNOPSIS
        Acquires a Dataverse bearer token, managed-identity-first.

    .DESCRIPTION
        Resolves a token using the strongest available authentication method:
        system/user-assigned managed identity first, then workload identity
        federation, then interactive, then (dev-only legacy) client secret.

    .PARAMETER ResourceUrl
        Dataverse environment URL the token is scoped to.

    .PARAMETER AuthMode
        ManagedIdentity, WorkloadIdentity, Interactive, or ClientSecret.

    .PARAMETER TenantId
        Entra ID tenant ID (required for Interactive and ClientSecret).

    .PARAMETER ClientId
        App / user-assigned managed identity client ID.

    .PARAMETER ClientSecret
        SecureString client secret (legacy dev-only fallback).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceUrl,

        [Parameter()]
        [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'ClientSecret')]
        [string]$AuthMode = 'ManagedIdentity',

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [securestring]$ClientSecret
    )

    Write-Verbose "Acquiring Dataverse token for $ResourceUrl using $AuthMode."

    # Auth contract: tenant-scoped modes need a TenantId.
    if ($AuthMode -in @('Interactive', 'ClientSecret') -and [string]::IsNullOrWhiteSpace($TenantId)) {
        throw [System.ArgumentException]::new(
            "TenantId is required for AuthMode '$AuthMode'.")
    }

    # Managed-identity-first. Az.Accounts surfaces managed identity and workload
    # identity federation without handling any plaintext secret.
    switch ($AuthMode) {
        'ManagedIdentity' {
            # Connect-AzAccount -Identity [-AccountId $ClientId for user-assigned]
            # then Get-AzAccessToken -ResourceUrl $ResourceUrl; return .Token.
            $assigned = if ($ClientId) { "user-assigned ($ClientId)" } else { 'system-assigned' }
            throw [System.NotImplementedException]::new(
                "Skeleton: wire Connect-AzAccount -Identity ($assigned) + Get-AzAccessToken -ResourceUrl $ResourceUrl here.")
        }
        'WorkloadIdentity' {
            # GitHub Actions OIDC -> Entra app (federated credential for $ClientId).
            throw [System.NotImplementedException]::new(
                "Skeleton: wire workload identity federation for client $ClientId here.")
        }
        'Interactive' {
            # Interactive / device-code for one-off admin-workstation runs.
            throw [System.NotImplementedException]::new(
                "Skeleton: wire interactive auth (tenant $TenantId, client $ClientId) here.")
        }
        'ClientSecret' {
            # legacy: dev-only -- replace with managed identity in production.
            # ClientSecret stays a SecureString; convert only at the MSAL call site.
            if ($null -eq $ClientSecret) {
                throw [System.ArgumentException]::new(
                    'ClientSecret (SecureString) is required for AuthMode ClientSecret.')
            }
            throw [System.NotImplementedException]::new(
                "Skeleton: dev-only client-secret token acquisition for tenant $TenantId, client $ClientId.")
        }
    }
}

function Invoke-WiqDataverseQuery {
    <#
    .SYNOPSIS
        Runs a read-only Dataverse Web API OData query and returns the value set.

    .PARAMETER BaseUrl
        Dataverse environment URL.

    .PARAMETER Query
        OData query path relative to /api/data/v9.2/ (logical names only).

    .PARAMETER AccessToken
        Bearer token from Get-WiqDataverseToken.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IEnumerable])]
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [string]$AccessToken
    )

    $uri = "{0}/api/data/v9.2/{1}" -f $BaseUrl.TrimEnd('/'), $Query.TrimStart('/')
    $headers = @{
        Authorization    = "Bearer $AccessToken"
        Accept           = 'application/json'
        'OData-Version'  = '4.0'
        'OData-MaxVersion' = '4.0'
        Prefer           = 'odata.maxpagesize=500'
    }

    Write-Verbose "GET $uri"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    return $response.value
}

function Resolve-WiqEnvironment {
    <#
    .SYNOPSIS
        Resolves a source environment's Dataverse URL and name from the sibling
        fsi_caienvironment table.

    .DESCRIPTION
        The agent master (fsi_copilotagent) carries fsi_environmentid but not the
        environment's Dataverse URL. Per-environment details -- including
        fsi_environmenturl -- live on fsi_caienvironment (entity set
        fsi_caienvironments), owned by copilot-agent-inventory and co-located in
        the governance Dataverse. This filters that table on fsi_environmentid and
        caches the result so each environment is resolved at most once per run.

        When the environment row or its fsi_environmenturl is absent, EnvironmentUrl
        is returned null so the caller can skip that environment's component scan
        instead of scanning the wrong (governance) environment.

    .PARAMETER GovernanceUrl
        Governance Dataverse URL hosting fsi_copilotagent and fsi_caienvironment.

    .PARAMETER EnvironmentId
        Power Platform environment GUID (fsi_environmentid) to resolve.

    .PARAMETER AccessToken
        Bearer token from Get-WiqDataverseToken.

    .PARAMETER Cache
        Hashtable used to memoize resolved environments across agents.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$GovernanceUrl,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    if ([string]::IsNullOrWhiteSpace($EnvironmentId)) {
        return [pscustomobject]@{
            EnvironmentId   = $EnvironmentId
            EnvironmentName = $null
            EnvironmentUrl  = $null
        }
    }

    if ($Cache.ContainsKey($EnvironmentId)) {
        return $Cache[$EnvironmentId]
    }

    # Logical names only. Filter fsi_caienvironments on fsi_environmentid; single
    # quotes in the value are escaped per the OData string-literal rule.
    $escapedId = $EnvironmentId.Replace("'", "''")
    $envQuery = "fsi_caienvironments?`$select=fsi_environmentid,fsi_environmentname,fsi_environmenturl&`$filter=fsi_environmentid eq '$escapedId'"

    $resolved = [pscustomobject]@{
        EnvironmentId   = $EnvironmentId
        EnvironmentName = $null
        EnvironmentUrl  = $null
    }
    try {
        $row = @(Invoke-WiqDataverseQuery -BaseUrl $GovernanceUrl -Query $envQuery -AccessToken $AccessToken) |
            Select-Object -First 1
        if ($row) {
            $resolved.EnvironmentName = [string]$row.fsi_environmentname
            $resolved.EnvironmentUrl  = [string]$row.fsi_environmenturl
        }
    }
    catch {
        Write-Warning "Failed to resolve environment '$EnvironmentId' from fsi_caienvironment: $($_.Exception.Message)"
    }

    $Cache[$EnvironmentId] = $resolved
    return $resolved
}

function Resolve-WiqConfiguredTier {
    <#
    .SYNOPSIS
        Classifies an agent's Work IQ configuration pathway from sampled metadata.

    .DESCRIPTION
        Applies the Tier-A classification switch. Native Work IQ MCP tool
        identifiers win first (NativeMcpCopilotStudio keys on the createdIn value);
        a direct Work IQ API operation maps to NativeApiDirect; knowledge /
        connector / generative-AI configuration maps to Adjacent; otherwise
        NotConfigured.

    .PARAMETER HasNativeMcpTool
        True when a Work IQ MCP tool identifier was found in botcomponent /
        aipluginoperation content.

    .PARAMETER HasNativeApiDirect
        True when a direct Work IQ API operation was found.

    .PARAMETER HasAdjacentConfig
        True when knowledge (componenttype 16) / connector / generative-AI
        configuration referencing SharePoint / Graph / M365 was found.

    .PARAMETER CreatedIn
        Azure Resource Graph createdIn value for the agent.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [bool]$HasNativeMcpTool,

        [Parameter()]
        [bool]$HasNativeApiDirect,

        [Parameter()]
        [bool]$HasAdjacentConfig,

        [Parameter()]
        [string]$CreatedIn
    )

    # native-mcp keys on createdIn (Copilot Studio authoring surface).
    if ($HasNativeMcpTool) {
        Write-Verbose "Native MCP Work IQ tool detected (createdIn=$CreatedIn)."
        return 'NativeMcpCopilotStudio'
    }
    if ($HasNativeApiDirect) {
        return 'NativeApiDirect'
    }
    if ($HasAdjacentConfig) {
        return 'Adjacent'
    }
    return 'NotConfigured'
}

function Get-WorkIqConfigState {
    <#
    .SYNOPSIS
        Classifies the Tier-A Work IQ configuration pathway for every agent.

    .DESCRIPTION
        Reads fsi_copilotagent (the copilot-agent-inventory master; not
        duplicated here), samples botcomponent / aipluginoperation per agent, and
        emits one Tier-A configuration object per agent ready to join with Tier-B
        telemetry. Read-only: it does not write fsi_wiqstate (the nightly flow
        does, after the join).

    .PARAMETER DataverseUrl
        Governance Dataverse URL hosting fsi_copilotagent.

    .PARAMETER WorkIqMcpToolNames
        Work IQ MCP tool identifiers to match. Default 'use-work-iq' (preview).

    .PARAMETER AuthMode
        Managed-identity-first authentication mode.

    .PARAMETER TenantId
        Entra ID tenant ID (Interactive / ClientSecret).

    .PARAMETER ClientId
        App / user-assigned managed identity client ID.

    .PARAMETER ClientSecret
        SecureString client secret (legacy dev-only fallback).

    .PARAMETER Top
        Safety cap on agents processed (0 = no cap).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://')]
        [string]$DataverseUrl,

        [Parameter()]
        [string[]]$WorkIqMcpToolNames = @('use-work-iq'),

        [Parameter()]
        [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'ClientSecret')]
        [string]$AuthMode = 'ManagedIdentity',

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [securestring]$ClientSecret,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Top = 0
    )

    $tokenParams = @{
        ResourceUrl  = $DataverseUrl
        AuthMode     = $AuthMode
        TenantId     = $TenantId
        ClientId     = $ClientId
        ClientSecret = $ClientSecret
    }
    $token = Get-WiqDataverseToken @tokenParams

    # Read the agent master. Logical names only. fsi_copilotagent is owned by
    # copilot-agent-inventory; we read it, never write it.
    # ASSUMPTION: exact column logical names resolve from the inventory schema.
    $agentSelect = @(
        'fsi_agentid',
        'fsi_agentname',
        'fsi_environmentid',
        'fsi_createdin'
    ) -join ','
    $agentQuery = "fsi_copilotagents?`$select=$agentSelect"
    if ($Top -gt 0) {
        $agentQuery += "&`$top=$Top"
    }

    $agents = Invoke-WiqDataverseQuery -BaseUrl $DataverseUrl -Query $agentQuery -AccessToken $token

    # Cache fsi_caienvironment lookups so each source environment is resolved once.
    $envCache = @{}

    foreach ($agent in $agents) {
        $environmentId = [string]$agent.fsi_environmentid

        # Resolve the agent's source-environment Dataverse URL from the sibling
        # fsi_caienvironment table. The agent master does NOT carry an env URL.
        $resolvedEnv = Resolve-WiqEnvironment -GovernanceUrl $DataverseUrl `
            -EnvironmentId $environmentId -AccessToken $token -Cache $envCache
        $agentEnvUrl = $resolvedEnv.EnvironmentUrl

        # No resolvable source-environment URL: do NOT fall back to the governance
        # $DataverseUrl (that would scan the wrong environment). Skip the component
        # scan and mark the agent Exception-unknown -- the honest "cannot determine"
        # state. WIQ depends on copilot-agent-inventory publishing
        # fsi_caienvironment.fsi_environmenturl (see docs/prerequisites.md).
        if ([string]::IsNullOrWhiteSpace($agentEnvUrl)) {
            Write-Warning ("No fsi_caienvironment.fsi_environmenturl resolved for " +
                "environment '$environmentId' (agent $($agent.fsi_agentid)); " +
                'skipping component scan and marking Exception-unknown.')
            [pscustomobject]@{
                AgentId             = [string]$agent.fsi_agentid
                AgentName           = [string]$agent.fsi_agentname
                EnvironmentGuid     = $environmentId
                EnvironmentName     = $resolvedEnv.EnvironmentName
                CreatedIn           = [string]$agent.fsi_createdin
                ConfiguredTier      = $null
                ConfigComponentType = $null
                ConfigEvidence      = ("Source-environment Dataverse URL " +
                    "(fsi_caienvironment.fsi_environmenturl) unavailable for " +
                    "environment '$environmentId'; component scan skipped.")
                TelemetrySource     = $null
                ObservedStatus      = 'ExceptionUnknown'
                ScanTime            = (Get-Date).ToUniversalTime().ToString('o')
            }
            continue
        }

        # Sample botcomponent for the verified Work IQ-bearing component types.
        # Logical names only. componenttype is a standard botcomponent column.
        $typeFilter = ($script:WiqBotComponentTypes |
            ForEach-Object { "componenttype eq $_" }) -join ' or '
        $botCompQuery = "botcomponents?`$select=botcomponentid,name,schemaname,componenttype,_parentbotid_value&`$filter=($typeFilter)"

        $botComponents = @()
        $aiPluginOps = @()
        try {
            $botComponents = @(Invoke-WiqDataverseQuery -BaseUrl $agentEnvUrl -Query $botCompQuery -AccessToken $token)
            # aipluginoperation carries MCP / connector operation identifiers.
            $aiPluginOps = @(Invoke-WiqDataverseQuery -BaseUrl $agentEnvUrl -Query 'aipluginoperations?$select=aipluginoperationid,name,schemaname,_aipluginid_value' -AccessToken $token)
        }
        catch {
            Write-Warning "Failed to sample components for agent $($agent.fsi_agentid): $($_.Exception.Message)"
        }

        # --- Extension point -------------------------------------------------
        # Deep-parse botcomponent payloads (data/content) and aipluginoperation
        # names for the Work IQ MCP tool identifiers in $WorkIqMcpToolNames.
        # The skeleton scans available name/schemaname fields; production should
        # also inspect bot.configuration JSON. bot.generativeaiconfiguration is
        # NOT a column -- do not query it.
        $namePool = @()
        $namePool += ($botComponents | ForEach-Object { @($_.name, $_.schemaname) })
        $namePool += ($aiPluginOps | ForEach-Object { @($_.name, $_.schemaname) })
        $namePool = $namePool | Where-Object { $_ }

        $hasNativeMcpTool = $false
        foreach ($tool in $WorkIqMcpToolNames) {
            if ($namePool | Where-Object { $_ -match [regex]::Escape($tool) }) {
                $hasNativeMcpTool = $true
                break
            }
        }

        # NativeApiDirect and Adjacent are extension points; default false /
        # presence-of-knowledge heuristic for the skeleton.
        $hasNativeApiDirect = $false
        $hasAdjacentConfig = [bool]($botComponents | Where-Object { $_.componenttype -eq 16 })

        $configuredTier = Resolve-WiqConfiguredTier `
            -HasNativeMcpTool $hasNativeMcpTool `
            -HasNativeApiDirect $hasNativeApiDirect `
            -HasAdjacentConfig $hasAdjacentConfig `
            -CreatedIn ([string]$agent.fsi_createdin)

        $sampledType = ($botComponents | Select-Object -First 1 -ExpandProperty componenttype -ErrorAction SilentlyContinue)
        $evidence = ($namePool | Select-Object -First 5) -join '; '

        [pscustomobject]@{
            AgentId             = [string]$agent.fsi_agentid
            AgentName           = [string]$agent.fsi_agentname
            EnvironmentGuid     = $environmentId
            EnvironmentName     = $resolvedEnv.EnvironmentName
            CreatedIn           = [string]$agent.fsi_createdin
            ConfiguredTier      = $configuredTier
            ConfigComponentType = $sampledType
            ConfigEvidence      = $evidence
            # Tier-B fields are intentionally null here; the nightly flow joins
            # telemetry and computes the canonical four-state observedstatus.
            TelemetrySource     = $null
            ObservedStatus      = $null
            ScanTime            = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}
