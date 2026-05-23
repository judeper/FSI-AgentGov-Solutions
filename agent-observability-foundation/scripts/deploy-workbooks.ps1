<#
.SYNOPSIS
    Deploy Azure Monitor Workbook ARM templates for Agent Observability Foundation.

.DESCRIPTION
    This script provisions all 3 Azure Monitor Workbooks (Operational Health, Error Diagnostics,
    Usage Overview) to a target resource group with environment-specific parameters.

    Supports idempotent deployment using fixed workbookId GUIDs - re-running updates existing
    workbooks without creating duplicates, enabling safe CI/CD pipeline integration.

    Validates prerequisites (Azure CLI, authentication, resource group, Application Insights)
    before deployment and provides clear error messages with remediation guidance.

.PARAMETER ResourceGroup
    Target Azure resource group name for workbook deployment.

.PARAMETER ApplicationInsightsId
    Full resource ID of Application Insights component.
    Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/microsoft.insights/components/{name}

.PARAMETER Environment
    Environment name for parameter file selection. Valid values: dev, prod
    Default: dev

.PARAMETER DryRun
    Preview deployment without making changes. Shows what would be deployed.

.EXAMPLE
    .\deploy-workbooks.ps1 -ResourceGroup "rg-agent-observability-dev" `
                           -ApplicationInsightsId "/subscriptions/.../components/ai-aof-observability"

.EXAMPLE
    .\deploy-workbooks.ps1 -ResourceGroup "rg-agent-observability-prod" `
                           -ApplicationInsightsId "/subscriptions/.../components/ai-aof-prod" `
                           -Environment prod

.EXAMPLE
    .\deploy-workbooks.ps1 -ResourceGroup "rg-test" `
                           -ApplicationInsightsId "/subscriptions/.../components/ai-test" `
                           -DryRun

.NOTES
    Requirements:
    - Azure CLI 2.60.0 or higher
    - PowerShell 7.0 or higher
    - Authenticated Azure session (az login)
    - Contributor or Owner role on target resource group
    - Valid Application Insights resource

    IMPORTANT: Application Insights must exist before deploying workbooks.
               Workbooks query data from the Application Insights resource.

.LINK
    https://github.com/judeper/FSI-AgentGov-Solutions/tree/main/agent-observability-foundation
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$ApplicationInsightsId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("dev","prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script version
$SCRIPT_VERSION = "1.0.0"

# ANSI color codes for terminal output
$COLOR_CYAN = "`e[36m"
$COLOR_GREEN = "`e[32m"
$COLOR_RED = "`e[31m"
$COLOR_YELLOW = "`e[33m"
$COLOR_RESET = "`e[0m"

# ==============================================================================
# Helper Functions
# ==============================================================================

function Show-Banner {
    <#
    .SYNOPSIS
        Display deployment banner with script information.
    #>
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  Agent Observability Foundation - Workbook Deployment" -ForegroundColor Cyan
    Write-Host "  Version: $SCRIPT_VERSION" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  This script deploys Azure Monitor Workbooks:" -ForegroundColor White
    Write-Host "    - Operational Health (daily monitoring)" -ForegroundColor White
    Write-Host "    - Error Diagnostics (incident investigation)" -ForegroundColor White
    Write-Host "    - Usage Overview (adoption tracking)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Deployment uses fixed workbookId GUIDs for idempotent updates." -ForegroundColor White
    Write-Host "  Re-running this script updates existing workbooks (no duplicates)." -ForegroundColor White
    Write-Host ""
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validate prerequisites before deployment.

    .DESCRIPTION
        Checks:
        - Azure CLI is installed
        - Azure CLI version >= 2.50.0
        - Azure CLI is authenticated
        - Target resource group exists
        - Application Insights resource exists

    .OUTPUTS
        Boolean - $true if all checks pass, $false if any fail
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroup,

        [Parameter(Mandatory=$true)]
        [string]$ApplicationInsightsId
    )

    Write-Host "[Pre-flight Validation]" -ForegroundColor Cyan
    Write-Host ""

    $allChecksPassed = $true

    # Check 1: Azure CLI installed
    Write-Host "  Checking Azure CLI installation..." -ForegroundColor White
    try {
        $azVersion = az version 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ${COLOR_RED}✗ Azure CLI not found${COLOR_RESET}"
            Write-Host "    Install: https://aka.ms/install-azure-cli" -ForegroundColor Yellow
            $allChecksPassed = $false
        } else {
            Write-Host "    ${COLOR_GREEN}✓ Azure CLI installed${COLOR_RESET}"
        }
    } catch {
        Write-Host "    ${COLOR_RED}✗ Azure CLI not found or not in PATH${COLOR_RESET}"
        Write-Host "    Install: https://aka.ms/install-azure-cli" -ForegroundColor Yellow
        $allChecksPassed = $false
    }

    # Check 2: Azure CLI version >= 2.60.0
    if ($allChecksPassed) {
        Write-Host "  Checking Azure CLI version..." -ForegroundColor White
        $cliVersion = $azVersion.'azure-cli'
        $versionParts = $cliVersion -split '\.'
        $majorVersion = [int]$versionParts[0]
        $minorVersion = [int]$versionParts[1]

        if ($majorVersion -gt 2 -or ($majorVersion -eq 2 -and $minorVersion -ge 60)) {
            Write-Host "    ${COLOR_GREEN}✓ Azure CLI $cliVersion (>= 2.60.0)${COLOR_RESET}"
        } else {
            Write-Host "    ${COLOR_RED}✗ Azure CLI $cliVersion (< 2.60.0)${COLOR_RESET}"
            Write-Host "    Update: az upgrade" -ForegroundColor Yellow
            $allChecksPassed = $false
        }
    }

    # Check 3: Azure CLI authentication
    Write-Host "  Checking Azure authentication..." -ForegroundColor White
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ${COLOR_RED}✗ Not authenticated${COLOR_RESET}"
            Write-Host "    Login: az login" -ForegroundColor Yellow
            $allChecksPassed = $false
        } else {
            $subscriptionId = $account.id.Substring(0, 8)
            Write-Host "    ${COLOR_GREEN}✓ Authenticated to subscription $subscriptionId...${COLOR_RESET}"
        }
    } catch {
        Write-Host "    ${COLOR_RED}✗ Authentication check failed${COLOR_RESET}"
        Write-Host "    Login: az login" -ForegroundColor Yellow
        $allChecksPassed = $false
    }

    # Check 4: Resource group exists
    Write-Host "  Checking resource group..." -ForegroundColor White
    try {
        $rg = az group show --name $ResourceGroup 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ${COLOR_RED}✗ Resource group '$ResourceGroup' not found${COLOR_RESET}"
            Write-Host "    Create: az group create --name $ResourceGroup --location <location>" -ForegroundColor Yellow
            $allChecksPassed = $false
        } else {
            Write-Host "    ${COLOR_GREEN}✓ Resource group '$ResourceGroup' exists${COLOR_RESET}"
        }
    } catch {
        Write-Host "    ${COLOR_RED}✗ Cannot access resource group '$ResourceGroup'${COLOR_RESET}"
        $allChecksPassed = $false
    }

    # Check 5: Application Insights exists
    Write-Host "  Checking Application Insights..." -ForegroundColor White
    try {
        # Parse Application Insights resource ID
        # Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/microsoft.insights/components/{name}
        $resourceIdPattern = '/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/microsoft\.insights/components/(.+)'
        if ($ApplicationInsightsId -match $resourceIdPattern) {
            $aiName = $Matches[3]
            $aiResourceGroup = $Matches[2]

            $appInsights = az monitor app-insights component show --app $aiName --resource-group $aiResourceGroup 2>$null | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0) {
                Write-Host "    ${COLOR_RED}✗ Application Insights '$aiName' not found${COLOR_RESET}"
                Write-Host "    Verify resource ID: $ApplicationInsightsId" -ForegroundColor Yellow
                $allChecksPassed = $false
            } else {
                Write-Host "    ${COLOR_GREEN}✓ Application Insights '$aiName' exists${COLOR_RESET}"
            }
        } else {
            Write-Host "    ${COLOR_RED}✗ Invalid Application Insights resource ID format${COLOR_RESET}"
            Write-Host "    Expected: /subscriptions/{sub}/resourceGroups/{rg}/providers/microsoft.insights/components/{name}" -ForegroundColor Yellow
            $allChecksPassed = $false
        }
    } catch {
        Write-Host "    ${COLOR_RED}✗ Cannot verify Application Insights resource${COLOR_RESET}"
        $allChecksPassed = $false
    }

    Write-Host ""

    return $allChecksPassed
}

function Deploy-SingleWorkbook {
    <#
    .SYNOPSIS
        Deploy a single Azure Monitor Workbook using ARM template.

    .DESCRIPTION
        Deploys workbook using az deployment group create with Incremental mode
        for safe idempotent updates. Uses fixed workbookId from parameter file
        to update existing workbook instead of creating duplicate.

    .OUTPUTS
        Boolean - $true if deployment succeeds, $false on failure
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WorkbookName,

        [Parameter(Mandatory=$true)]
        [string]$DisplayName,

        [Parameter(Mandatory=$true)]
        [string]$TemplatePath,

        [Parameter(Mandatory=$true)]
        [string]$ParametersPath,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroup,

        [Parameter(Mandatory=$true)]
        [string]$ApplicationInsightsId,

        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )

    # Resolve paths relative to script location
    $scriptDir = Split-Path -Parent $PSCommandPath
    $templateFullPath = Join-Path $scriptDir $TemplatePath | Resolve-Path -ErrorAction Stop
    $parametersFullPath = Join-Path $scriptDir $ParametersPath | Resolve-Path -ErrorAction Stop

    # Verify files exist
    if (-not (Test-Path $templateFullPath)) {
        Write-Host "    ${COLOR_RED}✗ Template file not found: $templateFullPath${COLOR_RESET}"
        return $false
    }

    if (-not (Test-Path $parametersFullPath)) {
        Write-Host "    ${COLOR_RED}✗ Parameters file not found: $parametersFullPath${COLOR_RESET}"
        return $false
    }

    # DryRun mode: show what would be deployed
    if ($DryRun) {
        Write-Host "  ${COLOR_YELLOW}[DRY RUN]${COLOR_RESET} Workbook '$DisplayName'" -ForegroundColor Yellow
        Write-Host "    - Template: $templateFullPath" -ForegroundColor White
        Write-Host "    - Parameters: $parametersFullPath" -ForegroundColor White
        Write-Host "    - Resource Group: $ResourceGroup" -ForegroundColor White
        Write-Host "    - Application Insights: $ApplicationInsightsId" -ForegroundColor White
        Write-Host ""
        Write-Host "    Would execute:" -ForegroundColor Cyan
        Write-Host "      az deployment group create \" -ForegroundColor Gray
        Write-Host "        --resource-group $ResourceGroup \" -ForegroundColor Gray
        Write-Host "        --template-file `"$templateFullPath`" \" -ForegroundColor Gray
        Write-Host "        --parameters `"@$parametersFullPath`" \" -ForegroundColor Gray
        Write-Host "        --parameters applicationInsightsId=$ApplicationInsightsId \" -ForegroundColor Gray
        Write-Host "        --mode Incremental" -ForegroundColor Gray
        Write-Host ""
        return $true
    }

    # Deploy workbook
    Write-Host "  Deploying workbook '$DisplayName'..." -ForegroundColor Cyan

    if ($VerbosePreference -eq 'Continue') {
        Write-Host "    Template: $templateFullPath" -ForegroundColor Gray
        Write-Host "    Parameters: $parametersFullPath" -ForegroundColor Gray
    }

    try {
        # Execute az deployment group create
        # --mode Incremental: Safe default (adds/updates resources, doesn't delete)
        # --output json: Structured output for parsing
        $deploymentResult = az deployment group create `
            --resource-group $ResourceGroup `
            --template-file "$templateFullPath" `
            --parameters "@$parametersFullPath" `
            --parameters applicationInsightsId=$ApplicationInsightsId `
            --mode Incremental `
            --output json 2>&1

        # Check exit code (CRITICAL: Azure CLI doesn't throw exceptions on failure)
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ${COLOR_RED}✗ Deployment failed${COLOR_RESET}"
            Write-Host "    Error: $deploymentResult" -ForegroundColor Red
            return $false
        }

        # Parse deployment output
        $deployment = $deploymentResult | ConvertFrom-Json
        $workbookId = $deployment.properties.outputResources[0].id

        Write-Host "    ${COLOR_GREEN}✓ Workbook deployed successfully${COLOR_RESET}"
        Write-Host "    Workbook ID: $workbookId" -ForegroundColor White

        if ($VerbosePreference -eq 'Continue') {
            Write-Host "    Provisioning State: $($deployment.properties.provisioningState)" -ForegroundColor Gray
        }

        return $true

    } catch {
        Write-Host "    ${COLOR_RED}✗ Deployment error: $_${COLOR_RESET}"
        return $false
    }
}

# ==============================================================================
# Main Execution
# ==============================================================================

try {
    # Display banner
    Show-Banner

    # Show DryRun warning
    if ($DryRun) {
        Write-Host ("=" * 70) -ForegroundColor Yellow
        Write-Host "  *** DRY RUN MODE - No changes will be made ***" -ForegroundColor Yellow
        Write-Host ("=" * 70) -ForegroundColor Yellow
        Write-Host ""
    }

    # Run prerequisite checks
    $prereqsPass = Test-Prerequisites -ResourceGroup $ResourceGroup -ApplicationInsightsId $ApplicationInsightsId

    if (-not $prereqsPass) {
        Write-Host ""
        Write-Host "${COLOR_RED}Pre-flight validation failed. Exiting.${COLOR_RESET}" -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    Write-Host "[Deploying Workbooks]" -ForegroundColor Cyan
    Write-Host ""

    # Define workbook configurations
    $workbooks = @(
        @{
            Name = "operational-health"
            DisplayName = "Agent Operational Health"
            Description = "Daily agent health monitoring and performance tracking"
        },
        @{
            Name = "error-diagnostics"
            DisplayName = "Agent Error Diagnostics"
            Description = "Error triage and root cause analysis for incident investigation"
        },
        @{
            Name = "usage-overview"
            DisplayName = "Agent Usage Overview"
            Description = "Adoption metrics and user engagement analytics"
        }
    )

    # Track deployment results
    $deployedCount = 0
    $failedCount = 0
    $results = @()

    # Deploy each workbook
    foreach ($workbook in $workbooks) {
        $workbookName = $workbook.Name
        $displayName = $workbook.DisplayName

        # Build paths relative to script directory
        $templatePath = "../workbooks/$workbookName/workbook-template.json"
        $parametersPath = "../workbooks/$workbookName/workbook-parameters.$Environment.json"

        $success = Deploy-SingleWorkbook `
            -WorkbookName $workbookName `
            -DisplayName $displayName `
            -TemplatePath $templatePath `
            -ParametersPath $parametersPath `
            -ResourceGroup $ResourceGroup `
            -ApplicationInsightsId $ApplicationInsightsId `
            -DryRun:$DryRun

        if ($success) {
            $deployedCount++
            $results += @{
                Name = $displayName
                Status = "Success"
            }
        } else {
            $failedCount++
            $results += @{
                Name = $displayName
                Status = "Failed"
            }
        }
    }

    # Print deployment summary
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "  DRY RUN COMPLETE" -ForegroundColor Cyan
    } else {
        Write-Host "  DEPLOYMENT SUMMARY" -ForegroundColor Cyan
    }
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""

    if ($DryRun) {
        Write-Host "  Workbooks reviewed: $($workbooks.Count)" -ForegroundColor White
        Write-Host ""
        Write-Host "  No changes were made. Run without -DryRun to apply." -ForegroundColor Yellow
    } else {
        Write-Host "  Workbooks deployed: $deployedCount / $($workbooks.Count)" -ForegroundColor White

        if ($failedCount -gt 0) {
            Write-Host "  Failed deployments: $failedCount" -ForegroundColor Red
        }

        Write-Host ""
        Write-Host "  Deployment Results:" -ForegroundColor White
        Write-Host "  $("-" * 66)" -ForegroundColor Gray
        Write-Host "  $("{0,-50} {1,-14}" -f "Workbook", "Status")" -ForegroundColor White
        Write-Host "  $("-" * 66)" -ForegroundColor Gray

        foreach ($result in $results) {
            $statusColor = if ($result.Status -eq "Success") { "Green" } else { "Red" }
            $statusSymbol = if ($result.Status -eq "Success") { "✓" } else { "✗" }
            Write-Host "  $("{0,-50}" -f $result.Name) " -NoNewline -ForegroundColor White
            Write-Host "$statusSymbol $($result.Status)" -ForegroundColor $statusColor
        }

        Write-Host ""

        if ($failedCount -eq 0) {
            Write-Host "  Next Steps:" -ForegroundColor Cyan
            Write-Host "    1. Open Azure Portal → Monitor → Workbooks" -ForegroundColor White
            Write-Host "    2. Verify workbooks appear in 'My workbooks' or resource group" -ForegroundColor White
            Write-Host "    3. Test TimeRange and Zone parameters" -ForegroundColor White
            Write-Host "    4. Configure RBAC for workbook access (if needed)" -ForegroundColor White
        } else {
            Write-Host "  Troubleshooting:" -ForegroundColor Yellow
            Write-Host "    - Review error messages above" -ForegroundColor White
            Write-Host "    - Verify Application Insights resource ID is correct" -ForegroundColor White
            Write-Host "    - Check Azure RBAC permissions (need Contributor or Owner)" -ForegroundColor White
            Write-Host "    - Run with -Verbose for detailed output" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""

    # Exit with appropriate code
    if ($failedCount -gt 0) {
        exit 1
    } else {
        exit 0
    }

} catch {
    Write-Host ""
    Write-Host "${COLOR_RED}ERROR: Unexpected error occurred${COLOR_RESET}" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red

    if ($VerbosePreference -eq 'Continue') {
        Write-Host ""
        Write-Host "Stack trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    }

    Write-Host ""
    exit 1
}
