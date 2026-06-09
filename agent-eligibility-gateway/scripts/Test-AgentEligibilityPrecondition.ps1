<#
.SYNOPSIS
    Asserts the Microsoft Entra ID authentication precondition an agent must meet
    before it can be fronted by the Agent Eligibility Gateway.

.DESCRIPTION
    Sharing-based audience control on owned custom-web / Direct Line channels
    depends on the agent being configured with Microsoft Entra ID authentication
    AND require-users-to-sign-in enabled. This verified precondition means:

      - bot.authenticationmode is Integrated (2) or Custom Azure Active Directory (3)
        (the two Microsoft Entra ID modes), AND
      - bot.authenticationtrigger is Always (1), i.e. authentication is enforced at
        the agent entry point ("Require users to sign in" = ON).

    Agents using No authentication (mode 1) or Generic OAuth2 (mode 4) CANNOT use
    sharing for audience control and therefore do not satisfy the gateway
    precondition. "Authenticated" alone is NOT sufficient - Generic OAuth2 is
    authenticated but not Microsoft Entra ID.

    The bot table option values are sourced from the Microsoft Dataverse Copilot
    (bot) table reference:
    https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot

    The cmdlet runs in two modes:
      - Explicit (default): pass the agent's configured -AuthenticationMode and
        -RequireUsersToSignIn directly (offline assertion; no tenant required).
      - Live: pass -EnvironmentUrl and -AgentSchemaName to read the values from the
        Dataverse bot table. Authentication is managed-identity-first via
        -AccessToken; an Az.Accounts fallback is provided for dev-only use.

    It writes a result object and sets the process exit code to 0 (Pass) or 1 (Fail)
    so it can gate a CI step or an onboarding script.

.PARAMETER AuthenticationMode
    Explicit mode. The agent's configured authentication mode, using the canonical
    Dataverse bot.authenticationmode labels: Unspecified, None, Integrated,
    CustomAzureActiveDirectory, GenericOAuth2. Integrated and
    CustomAzureActiveDirectory are the Microsoft Entra ID modes.

.PARAMETER RequireUsersToSignIn
    Explicit mode. Present when authentication is enforced at the agent entry point
    (bot.authenticationtrigger = Always). Omit when set to As Needed.

.PARAMETER EnvironmentUrl
    Live mode. The Dataverse environment URL hosting the agent's bot record
    (for example https://org.crm.dynamics.com).

.PARAMETER AgentSchemaName
    Live mode. The bot.schemaname of the agent to inspect.

.PARAMETER AccessToken
    Live mode. A Dataverse bearer token. Managed-identity-first: acquire it from a
    managed identity or workload identity in the caller and pass it here. When
    omitted, the cmdlet falls back to Get-AzAccessToken (dev-only; requires
    Az.Accounts and an interactive/CLI sign-in).

.PARAMETER AgentId
    Optional friendly identifier echoed in the result object and decision context.
    Defaults to AgentSchemaName in Live mode.

.EXAMPLE
    PS> .\Test-AgentEligibilityPrecondition.ps1 -AuthenticationMode Integrated -RequireUsersToSignIn
    Offline assertion. Exit code 0 and Precondition = Pass.

.EXAMPLE
    PS> .\Test-AgentEligibilityPrecondition.ps1 -AuthenticationMode GenericOAuth2 -RequireUsersToSignIn
    Offline assertion. Exit code 1 and Precondition = Fail (Generic OAuth2 is not
    Microsoft Entra ID, so sharing-based audience control is unavailable).

.EXAMPLE
    PS> $token = (Get-AzAccessToken -ResourceUrl 'https://org.crm.dynamics.com' -AsSecureString).Token | ConvertFrom-SecureString -AsPlainText
    PS> .\Test-AgentEligibilityPrecondition.ps1 -EnvironmentUrl 'https://org.crm.dynamics.com' -AgentSchemaName 'contoso_kbAssistant' -AccessToken $token
    Live read of the bot table, then asserts the precondition.

.NOTES
    bot.authenticationmode:    0 Unspecified | 1 None | 2 Integrated | 3 Custom Azure Active Directory | 4 Generic OAuth2
    bot.authenticationtrigger: 0 As Needed   | 1 Always
    The gateway applies only to owned custom-web / Direct Line channels. First-party
    Teams / Microsoft 365 Copilot / SharePoint surfaces cannot host middleware and
    rely on native sharing controls plus telemetry drift detection.
#>
[CmdletBinding(DefaultParameterSetName = 'Explicit')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Explicit')]
    [ValidateSet('Unspecified', 'None', 'Integrated', 'CustomAzureActiveDirectory', 'GenericOAuth2')]
    [string]$AuthenticationMode,

    [Parameter(ParameterSetName = 'Explicit')]
    [switch]$RequireUsersToSignIn,

    [Parameter(Mandatory, ParameterSetName = 'Live')]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory, ParameterSetName = 'Live')]
    [ValidateNotNullOrEmpty()]
    [string]$AgentSchemaName,

    [Parameter(ParameterSetName = 'Live')]
    [string]$AccessToken,

    [Parameter()]
    [string]$AgentId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Canonical Dataverse bot.authenticationmode integer values.
$script:AuthModeValues = @{
    'Unspecified'                = 0
    'None'                       = 1
    'Integrated'                 = 2
    'CustomAzureActiveDirectory' = 3
    'GenericOAuth2'              = 4
}
$script:AuthModeLabels = @{
    0 = 'Unspecified'
    1 = 'None'
    2 = 'Integrated'
    3 = 'CustomAzureActiveDirectory'
    4 = 'GenericOAuth2'
}

function Test-EligibilityPrecondition {
    <#
    .SYNOPSIS
        Core assertion: returns a result hashtable from the two integer bot values.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][int]$AuthModeValue,
        [Parameter(Mandatory)][int]$AuthTriggerValue
    )

    $entraModes = @(2, 3)  # Integrated, Custom Azure Active Directory
    $isEntraAuth = $entraModes -contains $AuthModeValue
    $requireSignIn = ($AuthTriggerValue -eq 1)  # Always

    $pass = $false
    $reason = ''

    if (-not $isEntraAuth) {
        switch ($AuthModeValue) {
            1 { $reason = 'No authentication (mode 1): the agent has no sign-in, so there is no Microsoft Entra identity to evaluate and sharing-based audience control is unavailable.' }
            4 { $reason = 'Generic OAuth2 (mode 4): a non-Microsoft identity provider. "Authenticated" is not sufficient - Microsoft Entra ID is required for sharing-based audience control.' }
            0 { $reason = 'Unspecified authentication (mode 0): configure Microsoft Entra ID authentication (Integrated or Custom Azure Active Directory).' }
            default { $reason = "Authentication mode $AuthModeValue is not a Microsoft Entra ID mode." }
        }
    }
    elseif (-not $requireSignIn) {
        $reason = 'Require-users-to-sign-in is OFF (authenticationtrigger = As Needed). Set authentication to trigger at the agent entry point (Always) so every request carries a signed-in user.'
    }
    else {
        $pass = $true
        $reason = 'Microsoft Entra ID authentication with require-users-to-sign-in enabled.'
    }

    return @{
        Pass   = $pass
        Reason = $reason
    }
}

function Get-BotAuthConfiguration {
    <#
    .SYNOPSIS
        Live mode: read authenticationmode / authenticationtrigger from the bot table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentUrl,
        [Parameter(Mandatory)][string]$AgentSchemaName,
        [string]$AccessToken
    )

    $token = $AccessToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        # legacy: dev-only - replace with a managed-identity-supplied -AccessToken in production
        Write-Verbose 'No -AccessToken supplied; falling back to Get-AzAccessToken (dev-only).'
        if (-not (Get-Command -Name Get-AzAccessToken -ErrorAction SilentlyContinue)) {
            throw 'No -AccessToken provided and Az.Accounts (Get-AzAccessToken) is not available. Supply a managed-identity token via -AccessToken, or install Az.Accounts and sign in.'
        }
        $secure = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl -AsSecureString).Token
        $token = $secure | ConvertFrom-SecureString -AsPlainText
    }

    $base = $EnvironmentUrl.TrimEnd('/')
    $escaped = $AgentSchemaName.Replace("'", "''")
    $select = 'schemaname,name,authenticationmode,authenticationtrigger,authorizedsecuritygroupids'
    $uri = "$base/api/data/v9.2/bots?`$select=$select&`$filter=schemaname eq '$escaped'"

    $headers = @{
        'Authorization'    = "Bearer $token"
        'Accept'           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }

    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    if (-not $response.value -or $response.value.Count -eq 0) {
        throw "No bot found with schemaname '$AgentSchemaName' in $EnvironmentUrl."
    }
    return $response.value[0]
}

# --- Resolve the two integer inputs from whichever parameter set is active ---
$authModeValue = $null
$authTriggerValue = $null
$audienceGroupCount = $null
$resolvedAgentId = $AgentId

if ($PSCmdlet.ParameterSetName -eq 'Explicit') {
    $authModeValue = $script:AuthModeValues[$AuthenticationMode]
    if ($RequireUsersToSignIn) { $authTriggerValue = 1 } else { $authTriggerValue = 0 }
}
else {
    $bot = Get-BotAuthConfiguration -EnvironmentUrl $EnvironmentUrl -AgentSchemaName $AgentSchemaName -AccessToken $AccessToken
    $authModeValue = [int]$bot.authenticationmode
    $authTriggerValue = [int]$bot.authenticationtrigger
    if ([string]::IsNullOrWhiteSpace($resolvedAgentId)) { $resolvedAgentId = $AgentSchemaName }

    # Informational: audience (Viewers) security groups configured on the agent.
    $hasGroupsProp = $bot.PSObject.Properties.Name -contains 'authorizedsecuritygroupids'
    if ($hasGroupsProp -and -not [string]::IsNullOrWhiteSpace($bot.authorizedsecuritygroupids)) {
        $audienceGroupCount = @($bot.authorizedsecuritygroupids -split '[;,]' | Where-Object { $_ -ne '' }).Count
    }
    else {
        $audienceGroupCount = 0
    }
}

$assertion = Test-EligibilityPrecondition -AuthModeValue $authModeValue -AuthTriggerValue $authTriggerValue

$preconditionText = 'Fail'
if ($assertion.Pass) { $preconditionText = 'Pass' }

$result = [pscustomobject]@{
    AgentId                    = $resolvedAgentId
    AuthenticationMode         = $script:AuthModeLabels[$authModeValue]
    AuthenticationModeValue    = $authModeValue
    RequireUsersToSignIn       = ($authTriggerValue -eq 1)
    AuthenticationTriggerValue = $authTriggerValue
    AudienceGroupCount         = $audienceGroupCount
    Precondition               = $preconditionText
    Reason                     = $assertion.Reason
}

Write-Output $result

if ($assertion.Pass) {
    Write-Verbose "Precondition PASS for agent '$resolvedAgentId'."
    exit 0
}
else {
    Write-Warning "Precondition FAIL for agent '$resolvedAgentId': $($assertion.Reason)"
    exit 1
}
