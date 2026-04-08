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
    # Prefer environment variables (FSI_CLIENT_SECRET or AZURE_CLIENT_SECRET) over the -ClientSecret
    # parameter to avoid exposing secrets in process listings, shell history, and transcript logs.
    [ValidateNotNullOrEmpty()]
    [string]$ClientSecret = ($env:FSI_CLIENT_SECRET ?? $env:AZURE_CLIENT_SECRET)
)

#Requires -Version 7.1

$ErrorActionPreference = "Stop"

# Normalize: strip trailing slash to prevent double-slash in API URLs
$Environment = $Environment.TrimEnd('/')

# Import shared helper functions (Invoke-WithRetry, Get-AccessToken)
. (Join-Path $PSScriptRoot "SoDShared.ps1")

# Validate credentials
if (-not $TenantId -or -not $ClientId) {
    throw "TenantId and ClientId are required. Set AZURE_TENANT_ID / AZURE_CLIENT_ID environment variables or pass parameters."
}
if (-not $ClientSecret) {
    throw "ClientSecret is required. Set FSI_CLIENT_SECRET environment variable or pass -ClientSecret parameter."
}

# Default rule sets
$DefaultRules = @{
    MakerChecker = @(
        @{
            fsi_name = "Agent Developer cannot be Pipeline Approver"
            fsi_category = 1
            fsi_rolea = "Agent Developer"
            fsi_roleacontext = 4
            fsi_roleb = "Pipeline Approver"
            fsi_rolebcontext = 4
            fsi_severity = 1
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Prevents self-approval of agent changes in deployment pipelines"
        },
        @{
            fsi_name = "Solution Developer cannot be Solution Promoter"
            fsi_category = 1
            fsi_rolea = "Solution Developer"
            fsi_roleacontext = 4
            fsi_roleb = "Solution Promoter"
            fsi_rolebcontext = 4
            fsi_severity = 1
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Requires independent review for solution promotions"
        },
        @{
            fsi_name = "Flow Creator cannot be Flow Approver"
            fsi_category = 1
            fsi_rolea = "Flow Creator"
            fsi_roleacontext = 4
            fsi_roleb = "Flow Approver"
            fsi_rolebcontext = 4
            fsi_severity = 2
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Enforces flow change review process"
        },
        @{
            fsi_name = "DLP Policy Author cannot be DLP Policy Approver"
            fsi_category = 1
            fsi_rolea = "DLP Policy Author"
            fsi_roleacontext = 3
            fsi_roleb = "DLP Policy Approver"
            fsi_rolebcontext = 3
            fsi_severity = 1
            fsi_enabled = $true
            fsi_allowexception = $false
            fsi_description = "Prevents self-exemption from DLP policies"
        },
        @{
            fsi_name = "Connection Creator cannot be Connection Approver"
            fsi_category = 1
            fsi_rolea = "Connection Creator"
            fsi_roleacontext = 4
            fsi_roleb = "Connection Approver"
            fsi_rolebcontext = 4
            fsi_severity = 2
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Supports connection review by independent party"
        }
    )

    Segregation = @(
        @{
            fsi_name = "Environment Admin cannot be Agent Publisher (same environment)"
            fsi_category = 2
            fsi_rolea = "System Administrator"
            fsi_roleacontext = 4
            fsi_roleb = "Agent Publisher"
            fsi_rolebcontext = 4
            fsi_severity = 1
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Admin should not publish their own work"
        },
        @{
            fsi_name = "Security Administrator cannot be Agent Developer"
            fsi_category = 2
            fsi_rolea = "Security Administrator"
            fsi_roleacontext = 1
            fsi_roleb = "Agent Developer"
            fsi_rolebcontext = 4
            fsi_severity = 2
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Security role separation from development"
        },
        @{
            fsi_name = "Compliance Administrator cannot be Agent Developer"
            fsi_category = 2
            fsi_rolea = "Compliance Administrator"
            fsi_roleacontext = 1
            fsi_roleb = "Agent Developer"
            fsi_rolebcontext = 4
            fsi_severity = 2
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Compliance role separation from development"
        },
        @{
            fsi_name = "Environment Creator cannot be Environment Approver"
            fsi_category = 2
            fsi_rolea = "Environment Creator"
            fsi_roleacontext = 3
            fsi_roleb = "Environment Approver"
            fsi_rolebcontext = 3
            fsi_severity = 2
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Environment lifecycle separation"
        },
        @{
            fsi_name = "Data Steward cannot be Data Consumer for sensitive data"
            fsi_category = 2
            fsi_rolea = "Data Steward"
            fsi_roleacontext = 4
            fsi_roleb = "Data Consumer"
            fsi_rolebcontext = 4
            fsi_severity = 3
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Data access separation for sensitive data"
        }
    )

    Privileged = @(
        @{
            fsi_name = "Global Administrator should not have maker roles"
            fsi_category = 3
            fsi_rolea = "Global Administrator"
            fsi_roleacontext = 1
            fsi_roleb = "Agent Developer"
            fsi_rolebcontext = 4
            fsi_severity = 1
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Global admin should not be an agent developer"
        },
        @{
            fsi_name = "Power Platform Administrator should not be regular user"
            fsi_category = 3
            fsi_rolea = "Power Platform Administrator"
            fsi_roleacontext = 1
            fsi_roleb = "Basic User"
            fsi_rolebcontext = 4
            fsi_severity = 2
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Admin/user role separation"
        },
        @{
            fsi_name = "Privileged Role Administrator cannot be Application Administrator"
            fsi_category = 3
            fsi_rolea = "Privileged Role Administrator"
            fsi_roleacontext = 1
            fsi_roleb = "Application Administrator"
            fsi_rolebcontext = 1
            fsi_severity = 1
            fsi_enabled = $true
            fsi_allowexception = $false
            fsi_description = "Prevents privilege escalation paths"
        },
        @{
            # NOTE: "Break-Glass Account" is not a built-in Entra ID directory role.
            # Organizations must create a custom role with this exact name for this rule to match.
            fsi_name = "Break-Glass Account should not have non-emergency roles"
            fsi_category = 3
            fsi_rolea = "Break-Glass Account"
            fsi_roleacontext = 1
            fsi_roleb = "Basic User"
            fsi_rolebcontext = 4
            fsi_severity = 1
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
        $response = Invoke-WithRetry { Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body }
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
    $validCategories = 1..3
    $validSeverities = 1..4
    $validContexts = 1..5
    foreach ($r in $rulesToImport) {
        foreach ($field in $requiredFields) {
            if (-not $r.ContainsKey($field)) {
                throw "Rule '$($r.fsi_name ?? 'unknown')' is missing required field '$field'."
            }
        }
        if ($r.fsi_category -notin $validCategories) { throw "Rule '$($r.fsi_name)': fsi_category must be 1-3." }
        if ($r.fsi_severity -notin $validSeverities) { throw "Rule '$($r.fsi_name)': fsi_severity must be 1-4." }
        if ($r.fsi_roleacontext -notin $validContexts) { throw "Rule '$($r.fsi_name)': fsi_roleacontext must be 1-5." }
        if ($r.fsi_rolebcontext -notin $validContexts) { throw "Rule '$($r.fsi_name)': fsi_rolebcontext must be 1-5." }
        $unsupportedContexts = @(2, 5)
        if ($r.fsi_roleacontext -in $unsupportedContexts -or $r.fsi_rolebcontext -in $unsupportedContexts) {
            Write-Warning "Rule '$($r.fsi_name)' uses context 2 (Entra ID App Role) or 5 (Custom Application Role) which is not currently scanned by Invoke-SoDScan.ps1. This rule will not match any user until support is added."
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
$token = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
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
