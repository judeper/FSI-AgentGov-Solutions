<#
.SYNOPSIS
    Sample Azure Automation runbook demonstrating managed identity authentication
    for action confirmation validation.

.DESCRIPTION
    Demonstrates the recommended migration from deprecated RunAs accounts to
    managed identity (system-assigned or user-assigned) for Azure Automation
    runbook authentication.

    This sample:
    1. Authenticates using system-assigned managed identity (default) or
       user-assigned managed identity (via -ManagedIdentityClientId)
    2. Connects to Microsoft Graph and Power Platform admin APIs
    3. Runs the action confirmation compliance scan
    4. Outputs structured JSON for downstream Power Automate consumption

    Migration from RunAs accounts:
    - RunAs accounts were deprecated by Microsoft on September 30, 2023
    - System-assigned MI is created automatically when enabled on the
      Automation account
    - User-assigned MI allows sharing identity across multiple Automation
      accounts
    - No certificate rotation required — Azure manages the credentials

    Reference: https://learn.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity

.PARAMETER DataverseUrl
    Central Dataverse organization URL where validation history is stored.

.PARAMETER ManagedIdentityClientId
    Client ID for user-assigned managed identity. When omitted, the
    system-assigned managed identity is used (recommended).

.PARAMETER Zone
    Governance zone to validate (1, 2, or 3). Default: all zones.

.PARAMETER IncludeSandbox
    Include Sandbox type environments in compliance scan.

.NOTES
    File: Start-ActionConfirmationRunbook-MI.ps1
    Version: 1.2.0
    Solution: Action Confirmation Auditor (ACA)
    Controls: 2.12, 1.10

    Part of FSI Agent Governance Framework

    MIGRATION GUIDE (RunAs → Managed Identity):
    1. Enable system-assigned MI on your Automation account
       (Portal → Automation Account → Identity → System assigned → On)
    2. Grant the MI the following roles:
       - Power Platform admin role (via Entra ID role assignment)
       - Dataverse System Administrator on the governance environment
       - Microsoft Graph: Application.Read.All, Directory.Read.All
    3. Replace Start-ActionConfirmationValidationRunbook.ps1 with this
       runbook (or update existing to use Connect-AzAccount -Identity)
    4. Remove the RunAs account from the Automation account
    5. Remove the certificate-based app registration if no longer needed
#>

#Requires -Version 7.1
#Requires -Modules Az.Accounts, Az.Automation

param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://[a-zA-Z0-9\-]+\.crm[0-9]*\.dynamics\.com')]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$ManagedIdentityClientId,

    [ValidateSet('1', '2', '3', 'All')]
    [string]$Zone = 'All',

    [switch]$IncludeSandbox
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ===================================================================
# Step 1: Authenticate with Managed Identity
# ===================================================================
Write-Verbose "Authenticating with managed identity..."

$connectParams = @{ Identity = $true }
if ($ManagedIdentityClientId) {
    # User-assigned managed identity
    $connectParams['AccountId'] = $ManagedIdentityClientId
    Write-Verbose "Using user-assigned MI: $ManagedIdentityClientId"
} else {
    Write-Verbose "Using system-assigned managed identity."
}

try {
    Connect-AzAccount @connectParams | Out-Null
    $context = Get-AzContext
    Write-Verbose "Authenticated as: $($context.Account.Id) (Type: $($context.Account.Type))"
} catch {
    $errorOutput = @{
        Status   = 'Error'
        Stage    = 'Authentication'
        Error    = $_.Exception.Message
        Guidance = 'Verify managed identity is enabled on the Automation account and has required role assignments.'
    } | ConvertTo-Json -Depth 3
    Write-Output $errorOutput
    throw
}

# ===================================================================
# Step 2: Acquire tokens for Graph and Dataverse
# ===================================================================
Write-Verbose "Acquiring tokens for Graph and Dataverse..."

try {
    $graphToken = (Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com').Token
    $dvToken = (Get-AzAccessToken -ResourceUrl "$($DataverseUrl.TrimEnd('/'))").Token
} catch {
    $errorOutput = @{
        Status   = 'Error'
        Stage    = 'TokenAcquisition'
        Error    = $_.Exception.Message
        Guidance = 'Verify the managed identity has API permissions: Graph (Application.Read.All) and Dataverse (user_impersonation).'
    } | ConvertTo-Json -Depth 3
    Write-Output $errorOutput
    throw
}

# ===================================================================
# Step 3: Connect to Power Platform admin
# ===================================================================
Write-Verbose "Connecting to Power Platform admin APIs..."
try {
    Add-PowerAppsAccount -AccessToken $graphToken -ErrorAction Stop
} catch {
    Write-Warning "Power Platform admin connection: $_ — continuing with Graph-only mode."
}

# ===================================================================
# Step 4: Run compliance scan (dot-source main validator)
# ===================================================================
$scriptRoot = $PSScriptRoot
$mainScript = Join-Path $scriptRoot 'Test-ActionConfirmationCompliance.ps1'
if (-not (Test-Path $mainScript)) {
    throw "Test-ActionConfirmationCompliance.ps1 not found at $scriptRoot"
}

. $mainScript

$scanParams = @{
    OutputFormat = 'Object'
}

if ($Zone -ne 'All') {
    $scanParams['Zone'] = $Zone
}

if ($IncludeSandbox) {
    $scanParams['IncludeSandbox'] = $true
}

Write-Verbose "Starting action confirmation compliance scan..."
$scanResults = Test-ActionConfirmationCompliance @scanParams

# ===================================================================
# Step 5: Build structured output
# ===================================================================
$output = @{
    Status                    = 'OK'
    RunType                   = 'ManagedIdentity'
    Timestamp                 = (Get-Date -AsUTC -Format 'o')
    AuthenticationMethod      = if ($ManagedIdentityClientId) { 'UserAssignedMI' } else { 'SystemAssignedMI' }
    Zone                      = $Zone
    TotalAgents               = ($scanResults | Measure-Object).Count
    ActionsMissingConfirmation = ($scanResults | Where-Object Severity -ne 'Passed' | Measure-Object).Count
    ActionsWithConfirmation    = ($scanResults | Where-Object Severity -eq 'Passed' | Measure-Object).Count
    Results                   = $scanResults
    MigrationNote             = 'This runbook uses managed identity authentication. RunAs accounts were deprecated September 2023.'
    Reference                 = 'https://learn.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity'
}

$outputJson = $output | ConvertTo-Json -Depth 10
Write-Output $outputJson

Write-Verbose "Scan complete. Total agents: $($output.TotalAgents), Missing confirmations: $($output.ActionsMissingConfirmation)"
