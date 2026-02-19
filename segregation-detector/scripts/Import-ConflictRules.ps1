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
    [string]$ClientSecret = ($env:FSI_CLIENT_SECRET ?? $env:AZURE_CLIENT_SECRET)
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

function Invoke-RestMethodWithRetry {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Method = "Get",
        $Body,
        [string]$ContentType,
        [int]$MaxRetries = 3
    )
    $attempt = 0
    while ($true) {
        try {
            $params = @{
                Uri     = $Uri
                Headers = $Headers
                Method  = $Method
            }
            if ($Body) { $params.Body = $Body }
            if ($ContentType) { $params.ContentType = $ContentType }
            return Invoke-RestMethod @params
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if (($statusCode -eq 429 -or $statusCode -ge 500) -and $attempt -lt $MaxRetries) {
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                $wait = if ($retryAfter) { [int]$retryAfter } else { [math]::Pow(2, $attempt + 1) }
                Write-Warning "HTTP $statusCode. Retrying after $wait seconds (attempt $($attempt+1)/$MaxRetries)..."
                Start-Sleep -Seconds $wait
                $attempt++
            } else {
                throw
            }
        }
    }
}

# Validate required parameters
if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    throw "TenantId, ClientId, and ClientSecret are required. Set AZURE_TENANT_ID / AZURE_CLIENT_ID / AZURE_CLIENT_SECRET (or FSI_CLIENT_SECRET) environment variables or pass parameters."
}
Write-Warning "For production use, store secrets in Azure Key Vault and use Managed Identity."

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
            fsi_name = "Connection Creator cannot be Connection Approver"
            fsi_category = 1
            fsi_rolea = "Connection Creator"
            fsi_roleacontext = 4
            fsi_roleb = "Connection Approver"
            fsi_rolebcontext = 4
            fsi_severity = 2
            fsi_enabled = $true
            fsi_allowexception = $true
            fsi_description = "Ensures connection review process"
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
            fsi_name = "Data Steward cannot be Data Consumer (sensitive)"
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
            fsi_name = "Break-Glass Account cannot be used for non-emergency operations"
            fsi_category = 3
            fsi_rolea = "Break-Glass Account"
            fsi_roleacontext = 1
            fsi_roleb = "Any Non-Emergency Use"
            fsi_rolebcontext = 4
            fsi_severity = 1
            fsi_enabled = $true
            fsi_allowexception = $false
            fsi_description = "Emergency access accounts restricted to emergency use only"
        }
    )
}

function Get-AccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$Scope
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethodWithRetry -Uri $tokenUrl -Headers @{} -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    return $response.access_token
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

    # Check for existing rule by name (idempotency)
    $escapedName = $Rule.fsi_name -replace "'", "''"
    $checkUri = "$Environment/api/data/v9.2/fsi_conflictrules?`$filter=fsi_name eq '$escapedName'"
    try {
        $existing = Invoke-RestMethodWithRetry -Uri $checkUri -Headers $headers -Method Get
        if ($existing.value.Count -gt 0) {
            return @{ Success = $true; Rule = $Rule.fsi_name; Skipped = $true }
        }
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 404) {
            Write-Warning "Existence check failed for '$($Rule.fsi_name)': $($_.Exception.Message)"
            throw
        }
    }

    $uri = "$Environment/api/data/v9.2/fsi_conflictrules"
    $body = $Rule | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethodWithRetry -Uri $uri -Headers $headers -Method Post -Body $body
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

# Import rules
Write-Host "Importing rules..." -ForegroundColor Gray
$imported = 0
$skipped = 0
$failed = 0

foreach ($rule in $rulesToImport) {
    if ($PSCmdlet.ShouldProcess("Rule: $($rule.fsi_name)", "Import to $Environment")) {
        $result = Import-Rule -Environment $Environment -Token $token -Rule $rule

        if ($result.Success -and $result.Skipped) {
            $skipped++
            Write-Host "  Skipped (exists): $($result.Rule)" -ForegroundColor Yellow
        } elseif ($result.Success) {
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
