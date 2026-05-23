#Requires -Version 7.1

<#
.SYNOPSIS
    Imports conflict rules into the Segregation of Duties Detector.

.DESCRIPTION
    Loads predefined conflict rules from JSON files or the default rule set
    into the Dataverse fsi_conflictrule table.

.PARAMETER Environment
    The Dataverse environment URL.

.PARAMETER RuleSet
    Predefined rule set to import: Default, MakerChecker, Segregation, Privileged

.PARAMETER RuleFile
    Path to custom JSON rules file.

.PARAMETER AuthMode
    Authentication mode. Defaults to ManagedIdentity. Use WorkloadIdentity for federated CI runners or ClientSecret only as a legacy dev fallback.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. If not specified, uses AZURE_CLIENT_ID when AuthMode is ManagedIdentity.

.PARAMETER FederatedTokenFile
    Federated token file path for WorkloadIdentity auth. If not specified, uses AZURE_FEDERATED_TOKEN_FILE.

.EXAMPLE
    .\Import-ConflictRules.ps1 -Environment "https://contoso.crm.dynamics.com" -RuleSet "Default"

.EXAMPLE
    .\Import-ConflictRules.ps1 -Environment "https://contoso.crm.dynamics.com" -RuleFile "my-rules.json"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^https://[\w.-]+\.(crm(?!9\b)\d*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)/?$')]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Default", "MakerChecker", "Segregation", "Privileged")]
    [string]$RuleSet = "Default",

    [Parameter(Mandatory = $false)]
    [string]$RuleFile,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [ValidateSet("ManagedIdentity", "WorkloadIdentity", "ClientSecret")]
    [string]$AuthMode = ($env:FSI_AUTH_MODE ?? "ManagedIdentity"),

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityClientId = ($env:MANAGED_IDENTITY_CLIENT_ID ?? $env:AZURE_CLIENT_ID),

    [Parameter(Mandatory = $false)]
    [string]$FederatedTokenFile = $env:AZURE_FEDERATED_TOKEN_FILE,

    [Parameter(Mandatory = $false)]
    # legacy: dev-only -- replace with managed identity in production
    # Prefer environment variables (FSI_CLIENT_SECRET or AZURE_CLIENT_SECRET) over the -ClientSecret
    # parameter to avoid exposing secrets in process listings, shell history, and transcript logs.
    # Note: do NOT use [ValidateNotNullOrEmpty()] here -- the validator runs at parameter binding
    # and would mask the actionable "FSI_CLIENT_SECRET / AZURE_CLIENT_SECRET" guidance below.
    # (Council Opus #6)
    [string]$ClientSecret = ($env:FSI_CLIENT_SECRET ?? $env:AZURE_CLIENT_SECRET)
)

$ErrorActionPreference = "Stop"

# Normalize: strip trailing slash to prevent double-slash in API URLs
$Environment = $Environment.TrimEnd('/')

# Import shared helper functions (Invoke-WithRetry, Get-AccessToken)
. (Join-Path $PSScriptRoot "SoDShared.ps1")
$script:SoDChoices = Get-SoDChoiceValues
$Category = $script:SoDChoices.Category
$Context = $script:SoDChoices.RoleContext
$Severity = $script:SoDChoices.Severity

# Validate authentication parameters
switch ($AuthMode) {
    "ManagedIdentity" {
        Write-Verbose "Using managed identity authentication."
    }
    "WorkloadIdentity" {
        if (-not $TenantId -or -not $ClientId) {
            throw "TenantId and ClientId are required for WorkloadIdentity auth. Set AZURE_TENANT_ID / AZURE_CLIENT_ID or pass parameters."
        }
        if (-not $FederatedTokenFile) {
            throw "FederatedTokenFile is required for WorkloadIdentity auth. Set AZURE_FEDERATED_TOKEN_FILE or pass -FederatedTokenFile."
        }
    }
    "ClientSecret" {
        # legacy: dev-only -- replace with managed identity in production
        if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
            throw "TenantId, ClientId, and ClientSecret are required for legacy ClientSecret auth. Prefer -AuthMode ManagedIdentity or WorkloadIdentity for production."
        }
        Write-Warning "ClientSecret auth is legacy dev-only. Use ManagedIdentity for Azure-hosted runs or WorkloadIdentity for federated CI."
    }
}

# Default rule sets
$DefaultRules = @{
    MakerChecker = @(
        @{
            fsi_name = "Agent Developer cannot be Pipeline Approver"
            fsi_category = $Category['MakerChecker']
            fsi_rolea = "Agent Developer"
            fsi_roleacontext = $Context['DataverseSecurityRole']
            fsi_roleb = "Pipeline Approver"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['Critical']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Flags potential self-approval of agent changes in deployment pipelines"
        },
        @{
            fsi_name = "Solution Developer cannot be Solution Promoter"
            fsi_category = $Category['MakerChecker']
            fsi_rolea = "Solution Developer"
            fsi_roleacontext = $Context['DataverseSecurityRole']
            fsi_roleb = "Solution Promoter"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['Critical']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Requires independent review for solution promotions"
        },
        @{
            fsi_name = "Flow Creator cannot be Flow Approver"
            fsi_category = $Category['MakerChecker']
            fsi_rolea = "Flow Creator"
            fsi_roleacontext = $Context['DataverseSecurityRole']
            fsi_roleb = "Flow Approver"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['High']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Supports flow change review by flagging creator/approver overlap"
        },
        @{
            fsi_name = "DLP Policy Author cannot be DLP Policy Approver"
            fsi_category = $Category['MakerChecker']
            fsi_rolea = "DLP Policy Author"
            fsi_roleacontext = $Context['PowerPlatformEnvironmentRole']
            fsi_roleb = "DLP Policy Approver"
            fsi_rolebcontext = $Context['PowerPlatformEnvironmentRole']
            fsi_severity = $Severity['Critical']
            # Disabled by default: no public Power Platform role names "DLP Policy Author"
            # or "DLP Policy Approver" exist in the BAP role-assignment API surface that this
            # solution queries. Enable only after wiring a custom collector that emits these
            # role names (e.g., by inspecting DLP policy creator/approver metadata in the
            # tenant). (Council Goldeneye #3)
            fsi_enabled = $false
            fsi_allowexception = $false
            fsi_description = "Flags potential self-exemption from DLP policies (DISABLED -- requires custom DLP policy ownership collector; not produced by Power Platform BAP role-assignment API)"
        },
        @{
            fsi_name = "Connection Creator cannot be Connection Approver"
            fsi_category = $Category['MakerChecker']
            fsi_rolea = "Connection Creator"
            fsi_roleacontext = $Context['DataverseSecurityRole']
            fsi_roleb = "Connection Approver"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['High']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Supports connection review by independent party"
        }
    )

    Segregation = @(
        @{
            fsi_name = "Environment Admin cannot be Agent Publisher (same environment)"
            fsi_category = $Category['Segregation']
            fsi_rolea = "System Administrator"
            fsi_roleacontext = $Context['DataverseSecurityRole']
            fsi_roleb = "Agent Publisher"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['Critical']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Admin should not publish their own work"
        },
        @{
            fsi_name = "Security Administrator cannot be Agent Developer"
            fsi_category = $Category['Segregation']
            fsi_rolea = "Security Administrator"
            fsi_roleacontext = $Context['EntraDirectoryRole']
            fsi_roleb = "Agent Developer"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['High']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Security role separation from development"
        },
        @{
            fsi_name = "Compliance Administrator cannot be Agent Developer"
            fsi_category = $Category['Segregation']
            fsi_rolea = "Compliance Administrator"
            fsi_roleacontext = $Context['EntraDirectoryRole']
            fsi_roleb = "Agent Developer"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['High']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Compliance role separation from development"
        },
        @{
            fsi_name = "Environment Creator cannot be Environment Approver"
            fsi_category = $Category['Segregation']
            fsi_rolea = "Environment Creator"
            fsi_roleacontext = $Context['PowerPlatformEnvironmentRole']
            fsi_roleb = "Environment Approver"
            fsi_rolebcontext = $Context['PowerPlatformEnvironmentRole']
            fsi_severity = $Severity['High']
            # Disabled by default: "Environment Approver" is not a Power Platform built-in
            # role name returned by the BAP role-assignment API. "Environment Maker" and
            # "Environment Admin" are the actual role names. Enable only after the customer
            # operationalizes an explicit "approver" group in their tenant and adapts the
            # collector. (Council Goldeneye #3)
            fsi_enabled = $false
            fsi_allowexception = $true
            fsi_description = "Environment lifecycle separation (DISABLED -- 'Environment Approver' is not a Power Platform BAP built-in role; rename to your tenant's approval group before enabling)"
        },
        @{
            fsi_name = "Data Steward cannot be Data Consumer for sensitive data"
            fsi_category = $Category['Segregation']
            fsi_rolea = "Data Steward"
            fsi_roleacontext = $Context['DataverseSecurityRole']
            fsi_roleb = "Data Consumer"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['Medium']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Data access separation for sensitive data"
        }
    )

    Privileged = @(
        @{
            fsi_name = "Global Administrator should not have maker roles"
            fsi_category = $Category['PrivilegedAccess']
            fsi_rolea = "Global Administrator"
            fsi_roleacontext = $Context['EntraDirectoryRole']
            fsi_roleb = "Agent Developer"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['Critical']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Global admin should not be an agent developer"
        },
        @{
            fsi_name = "Power Platform Administrator should not be regular user"
            fsi_category = $Category['PrivilegedAccess']
            fsi_rolea = "Power Platform Administrator"
            fsi_roleacontext = $Context['EntraDirectoryRole']
            fsi_roleb = "Basic User"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['High']
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Admin/user role separation"
        },
        @{
            fsi_name = "Privileged Role Administrator cannot be Application Administrator"
            fsi_category = $Category['PrivilegedAccess']
            fsi_rolea = "Privileged Role Administrator"
            fsi_roleacontext = $Context['EntraDirectoryRole']
            fsi_roleb = "Application Administrator"
            fsi_rolebcontext = $Context['EntraDirectoryRole']
            fsi_severity = $Severity['Critical']
            fsi_enabled = $true
            fsi_allowexception = $false
            fsi_description = "Flags potential privilege escalation paths"
        },
        @{
            # NOTE: "Break-Glass Account" is not a built-in Entra ID directory role.
            # Organizations must create a custom role with this exact name for this rule to match.
            fsi_name = "Break-Glass Account should not have non-emergency roles"
            fsi_category = $Category['PrivilegedAccess']
            fsi_rolea = "Break-Glass Account"
            fsi_roleacontext = $Context['EntraDirectoryRole']
            fsi_roleb = "Basic User"
            fsi_rolebcontext = $Context['DataverseSecurityRole']
            fsi_severity = $Severity['Critical']
            fsi_enabled = $true
            fsi_allowexception = $false
            fsi_description = "Emergency access accounts must not be used for routine operations"
        }
    )
}

function Get-ExistingRules {
    param(
        [string]$Environment,
        [string]$Token
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "Content-Type"     = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $nextLink = "$Environment/api/data/v9.2/fsi_conflictrules?`$select=fsi_rolea,fsi_roleb,fsi_category,fsi_roleacontext,fsi_rolebcontext"
    while ($nextLink) {
        try {
            $response = Invoke-WithRetry { Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get }
        } catch {
            Write-Warning "Failed to query existing conflict rules: $($_.Exception.Message)"
            throw
        }
        $results.AddRange([object[]]$response.value)
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
}

function Import-Rule {
    param(
        [string]$Environment,
        [string]$Token,
        [hashtable]$Rule
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_conflictrules"
    $body = $Rule | ConvertTo-Json -Depth 5

    try {
        Invoke-WithRetry { Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body } | Out-Null
        return @{ Success = $true; Rule = $Rule.fsi_name }
    } catch {
        return @{ Success = $false; Rule = $Rule.fsi_name; Error = $_.Exception.Message }
    }
}

# Main script
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Conflict Rules Importer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get rules to import
$rulesToImport = @()

if ($RuleFile) {
    Write-Host "Loading rules from: $RuleFile"
    $rulesToImport = Get-Content $RuleFile -Raw | ConvertFrom-Json -AsHashtable
    # Wrap single rule object in an array so .Count reports correctly
    if ($rulesToImport -is [hashtable]) {
        $rulesToImport = @($rulesToImport)
    }

    # Validate required fields in each rule from the JSON file
    $requiredFields = @('fsi_name', 'fsi_category', 'fsi_rolea', 'fsi_roleacontext', 'fsi_roleb', 'fsi_rolebcontext', 'fsi_severity', 'fsi_enabled', 'fsi_allowexception')
    $validCategories = @($Category.Values)
    $validSeverities = @($Severity.Values)
    $validContexts = @($Context.Values)
    foreach ($r in $rulesToImport) {
        foreach ($field in $requiredFields) {
            if (-not $r.ContainsKey($field)) {
                throw "Rule '$($r.fsi_name ?? 'unknown')' is missing required field '$field'."
            }
        }
        if ($r.fsi_category -notin $validCategories) { throw "Rule '$($r.fsi_name)': fsi_category must use the Dataverse choice values from dataverse-schema.md." }
        if ($r.fsi_severity -notin $validSeverities) { throw "Rule '$($r.fsi_name)': fsi_severity must use the Dataverse choice values from dataverse-schema.md." }
        if ($r.fsi_roleacontext -notin $validContexts) { throw "Rule '$($r.fsi_name)': fsi_roleacontext must use the Dataverse choice values from dataverse-schema.md." }
        if ($r.fsi_rolebcontext -notin $validContexts) { throw "Rule '$($r.fsi_name)': fsi_rolebcontext must use the Dataverse choice values from dataverse-schema.md." }
        $unsupportedContexts = @($Context['EntraAppRole'], $Context['CustomApplicationRole'])
        if ($r.fsi_roleacontext -in $unsupportedContexts -or $r.fsi_rolebcontext -in $unsupportedContexts) {
            Write-Warning "Rule '$($r.fsi_name)' uses Entra ID App Role or Custom Application Role context values, which Invoke-SoDScan.ps1 does not currently query. This rule will not match any user until support is added."
        }
    }
    Write-Host "  Schema validation passed" -ForegroundColor Green
} else {
    Write-Host "Loading rule set: $RuleSet"

    switch ($RuleSet) {
        "Default" {
            $rulesToImport += $DefaultRules.MakerChecker
            $rulesToImport += $DefaultRules.Segregation
            $rulesToImport += $DefaultRules.Privileged
        }
        "MakerChecker" { $rulesToImport = $DefaultRules.MakerChecker }
        "Segregation" { $rulesToImport = $DefaultRules.Segregation }
        "Privileged" { $rulesToImport = $DefaultRules.Privileged }
    }
}

Write-Host "  Found $($rulesToImport.Count) rules to import"
Write-Host ""

# Get token
Write-Host "Authenticating..." -ForegroundColor Gray
$tokenParams = @{
    TenantId                = $TenantId
    ClientId                = $ClientId
    ClientSecret            = $ClientSecret
    AuthMode                = $AuthMode
    ManagedIdentityClientId = $ManagedIdentityClientId
    FederatedTokenFile      = $FederatedTokenFile
}
$token = Get-AccessToken @tokenParams -Scope "$Environment/.default"
Write-Host "  Authenticated successfully" -ForegroundColor Green
Write-Host ""

# Query existing rules for duplicate detection
Write-Host "Checking for existing rules..." -ForegroundColor Gray
$existingRules = Get-ExistingRules -Environment $Environment -Token $token
Write-Host "  Found $($existingRules.Count) existing rules" -ForegroundColor Green
Write-Host ""

# Import rules
Write-Host "Importing rules..." -ForegroundColor Gray
$imported = 0
$failed = 0
$skipped = 0

foreach ($rule in $rulesToImport) {
    # Check for duplicates by role pair and category
    $isDuplicate = $existingRules | Where-Object {
        (
            $_.fsi_rolea -eq $rule.fsi_rolea -and
            $_.fsi_roleb -eq $rule.fsi_roleb -and
            $_.fsi_category -eq $rule.fsi_category -and
            $_.fsi_roleacontext -eq $rule.fsi_roleacontext -and
            $_.fsi_rolebcontext -eq $rule.fsi_rolebcontext
        ) -or (
            $_.fsi_rolea -eq $rule.fsi_roleb -and
            $_.fsi_roleb -eq $rule.fsi_rolea -and
            $_.fsi_category -eq $rule.fsi_category -and
            $_.fsi_roleacontext -eq $rule.fsi_rolebcontext -and
            $_.fsi_rolebcontext -eq $rule.fsi_roleacontext
        )
    }
    if ($isDuplicate) {
        $skipped++
        Write-Host "  Skipped (duplicate): $($rule.fsi_name)" -ForegroundColor Yellow
        continue
    }

    if ($PSCmdlet.ShouldProcess("Rule: $($rule.fsi_name)", "Import to $Environment")) {
        $result = Import-Rule -Environment $Environment -Token $token -Rule $rule

        if ($result.Success) {
            $imported++
            Write-Host "  Imported: $($result.Rule)" -ForegroundColor Green
        } else {
            $failed++
            Write-Host "  Failed: $($result.Rule) - $($result.Error)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Import Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Imported: $imported"
Write-Host "Skipped:  $skipped"
Write-Host "Failed:   $failed"
