<#
.SYNOPSIS
    Deploy alert infrastructure for FSI Agent Observability Foundation.

.DESCRIPTION
    Deploys alert infrastructure in 3-phase dependency order:

    Phase 1: Logic App (Teams notification schema transformer)
    Phase 2: Action Groups (3 zone-specific groups referencing Logic App callback URL)
    Phase 3: Alert Rules (ALRT-01, ALRT-02, ALRT-03 referencing Action Groups)

    This sequencing is CRITICAL because:
    - Action Groups require Logic App callback URL (from Phase 1 outputs)
    - Alert Rules require Action Group resource IDs (from Phase 2 outputs)

    Dynamic threshold baselines require 10-14 days of telemetry data before alerts
    become active. During this "Learning" period, alerts are visible but do not fire.

.PARAMETER ResourceGroup
    Azure resource group name where alert infrastructure will be deployed.

.PARAMETER ApplicationInsightsId
    Full resource ID of the Application Insights instance to monitor.
    Format: /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{name}

.PARAMETER Environment
    Environment name (dev or prod). Used for resource naming and parameter file selection.

.PARAMETER DryRun
    Preview deployment without making changes. Shows what would be deployed.

.PARAMETER Force
    Skip confirmation prompt. Use with caution in production environments.

.EXAMPLE
    .\deploy-alerts.ps1 -ResourceGroup "rg-agent-observability-dev" `
                        -ApplicationInsightsId "/subscriptions/.../components/appi-agent-dev" `
                        -Environment "dev"

.EXAMPLE
    .\deploy-alerts.ps1 -ResourceGroup "rg-agent-observability-dev" `
                        -ApplicationInsightsId "/subscriptions/.../components/appi-agent-dev" `
                        -Environment "dev" `
                        -DryRun

.NOTES
    Version: 1.0.0
    Prerequisites:
    - Azure CLI 2.60.0 or later
    - Authenticated Azure session (az login)
    - Contributor or Owner role on target resource group
    - Application Insights instance already deployed

    For troubleshooting, see: /agent-observability-foundation/alerts/README.md
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
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script-scoped variables
$ScriptRoot = $PSScriptRoot
$AlertsDir = Join-Path $ScriptRoot ".." "alerts"
$SharedParametersPath = Join-Path $AlertsDir "shared-parameters.$Environment.json"

#region Functions

function Show-Banner {
    <#
    .SYNOPSIS
        Display script banner with deployment phase diagram.
    #>
    Write-Host ""
    Write-Host "=" -NoNewline -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor Cyan
    Write-Host "  FSI Agent Observability - Alert Infrastructure Deployment" -ForegroundColor Cyan
    Write-Host "=" -NoNewline -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  3-Phase Deployment Order (CRITICAL sequencing):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Phase 1: Logic App" -ForegroundColor White
    Write-Host "             └─> Obtain callback URL" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Phase 2: Action Groups (3 zones)" -ForegroundColor White
    Write-Host "             ├─> Zone 1: Personal Productivity" -ForegroundColor Gray
    Write-Host "             ├─> Zone 2: Team Collaboration" -ForegroundColor Gray
    Write-Host "             └─> Zone 3: Enterprise Managed" -ForegroundColor Gray
    Write-Host "             └─> Pass Logic App callback URL" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Phase 3: Alert Rules (3 types × 3 zones = 9 rules)" -ForegroundColor White
    Write-Host "             ├─> ALRT-01: High Failure Rate" -ForegroundColor Gray
    Write-Host "             ├─> ALRT-02: Latency Regression" -ForegroundColor Gray
    Write-Host "             └─> ALRT-03: Abnormal Usage" -ForegroundColor Gray
    Write-Host "             └─> Pass Action Group IDs" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Dynamic Threshold Baseline: 10-14 days (Learning period)" -ForegroundColor Yellow
    Write-Host ""
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validate prerequisites before deployment.
    .DESCRIPTION
        Checks:
        - Azure CLI version (2.60.0+)
        - Azure authentication status
        - Resource group existence
        - Application Insights resource existence
        - ARM template file existence
    .OUTPUTS
        Boolean indicating whether prerequisites are satisfied
    #>
    Write-Host "[Prerequisites Validation]" -ForegroundColor Cyan
    Write-Host ""

    # Check Azure CLI version
    Write-Host "  Checking Azure CLI version..." -NoNewline
    try {
        $azVersion = az version --query '"azure-cli"' -o tsv 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "    Azure CLI is not installed or not in PATH" -ForegroundColor Red
            Write-Host "    Install from: https://aka.ms/InstallAzureCLI" -ForegroundColor Yellow
            return $false
        }
        Write-Host " $azVersion" -ForegroundColor Green
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        return $false
    }

    # Check authentication
    Write-Host "  Checking Azure authentication..." -NoNewline
    try {
        $account = az account show --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "    Not authenticated. Run: az login" -ForegroundColor Yellow
            return $false
        }
        Write-Host " $account" -ForegroundColor Green
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        return $false
    }

    # Check resource group
    Write-Host "  Checking resource group..." -NoNewline
    try {
        $rgExists = az group exists --name $ResourceGroup 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "    Error checking resource group: $ResourceGroup" -ForegroundColor Red
            return $false
        }
        if ($rgExists -eq "false") {
            Write-Host " NOT FOUND" -ForegroundColor Red
            Write-Host "    Resource group does not exist: $ResourceGroup" -ForegroundColor Red
            return $false
        }
        Write-Host " EXISTS" -ForegroundColor Green
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        return $false
    }

    # Check Application Insights
    Write-Host "  Checking Application Insights..." -NoNewline
    try {
        $appInsightsName = ($ApplicationInsightsId -split '/')[-1]
        # Parse resource group from the Application Insights resource ID
        $appInsightsRg = $ResourceGroup
        if ($ApplicationInsightsId -match '/subscriptions/[^/]+/resourceGroups/([^/]+)/') {
            $appInsightsRg = $Matches[1]
        }
        $appInsightsCheck = az monitor app-insights component show `
            --app $appInsightsName `
            --resource-group $appInsightsRg `
            --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host " NOT FOUND" -ForegroundColor Red
            Write-Host "    Application Insights does not exist: $appInsightsName" -ForegroundColor Red
            Write-Host "    Resource ID: $ApplicationInsightsId" -ForegroundColor Red
            return $false
        }
        Write-Host " $appInsightsCheck" -ForegroundColor Green
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        return $false
    }

    # Check ARM template files exist
    Write-Host "  Checking ARM template files..." -NoNewline
    $requiredTemplates = @(
        "action-groups/logic-app-teams-notification.json",
        "action-groups/action-group-zone1.json",
        "action-groups/action-group-zone2.json",
        "action-groups/action-group-zone3.json",
        "ALRT-01-high-failure-rate.json",
        "ALRT-02-latency-regression.json",
        "ALRT-03-abnormal-usage.json"
    )

    $missingTemplates = @()
    foreach ($template in $requiredTemplates) {
        $templatePath = Join-Path $AlertsDir $template
        if (-not (Test-Path $templatePath)) {
            $missingTemplates += $template
        }
    }

    if ($missingTemplates.Count -gt 0) {
        Write-Host " MISSING" -ForegroundColor Red
        Write-Host "    Missing template files:" -ForegroundColor Red
        foreach ($missing in $missingTemplates) {
            Write-Host "      - $missing" -ForegroundColor Red
        }
        return $false
    }
    Write-Host " ALL FOUND" -ForegroundColor Green

    # Check shared parameters file
    Write-Host "  Checking shared parameters file..." -NoNewline
    if (-not (Test-Path $SharedParametersPath)) {
        Write-Host " NOT FOUND" -ForegroundColor Red
        Write-Host "    Missing: $SharedParametersPath" -ForegroundColor Red
        Write-Host "    Create from shared-parameters.dev.json or shared-parameters.prod.json" -ForegroundColor Yellow
        return $false
    }
    Write-Host " EXISTS" -ForegroundColor Green

    Write-Host ""
    Write-Host "  All prerequisites satisfied" -ForegroundColor Green
    Write-Host ""
    return $true
}

function Deploy-LogicApp {
    <#
    .SYNOPSIS
        Deploy Logic App for Teams notification schema transformation.
    .DESCRIPTION
        Phase 1 of 3-phase deployment.
        Deploys Logic App that transforms Azure Monitor common alert schema
        to Microsoft Teams message format.
    .OUTPUTS
        Hashtable with LogicAppCallbackUrl property
    #>
    param(
        [bool]$IsDryRun = $false
    )

    Write-Host "[Phase 1/3: Logic App Deployment]" -ForegroundColor Cyan
    Write-Host ""

    $logicAppName = "fsi-agent-alert-teams-notification-$Environment"
    $templatePath = Join-Path $AlertsDir "action-groups" "logic-app-teams-notification.json"

    if ($IsDryRun) {
        Write-Host "  Logic App: $logicAppName (DRY RUN - would be deployed)" -ForegroundColor Yellow
        Write-Host "    Template: $templatePath" -ForegroundColor Gray
        return @{ LogicAppCallbackUrl = "https://dryrun.example.com/callback"; LogicAppId = "/subscriptions/dry-run/resourceGroups/$ResourceGroup/providers/Microsoft.Logic/workflows/$logicAppName" }
    }

    Write-Host "  Deploying Logic App: $logicAppName..." -NoNewline

    try {
        $deploymentName = "logic-app-teams-notification-$(Get-Date -Format 'yyyyMMddHHmmss')"

        az deployment group create `
            --resource-group $ResourceGroup `
            --name $deploymentName `
            --template-file $templatePath `
            --parameters logicAppName=$logicAppName `
            --query "properties.outputs" `
            --output json | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            throw "Logic App deployment failed (exit code: $LASTEXITCODE)"
        }

        Write-Host " DEPLOYED" -ForegroundColor Green

        # Retrieve callback URL from deployment outputs
        Write-Host "  Retrieving Logic App callback URL..." -NoNewline

        $outputs = az deployment group show `
            --resource-group $ResourceGroup `
            --name $deploymentName `
            --query "properties.outputs" `
            --output json 2>$null | ConvertFrom-Json

        if ($LASTEXITCODE -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            throw "Failed to retrieve deployment outputs (exit code: $LASTEXITCODE)"
        }

        $callbackUrl = $outputs.logicAppCallbackUrl.value

        if ([string]::IsNullOrWhiteSpace($callbackUrl)) {
            Write-Host " FAILED" -ForegroundColor Red
            throw "Logic App callback URL is empty or null"
        }

        Write-Host " RETRIEVED" -ForegroundColor Green
        Write-Host "    URL: [REDACTED - contains SAS signature]" -ForegroundColor Gray
        Write-Host ""

        return @{ LogicAppCallbackUrl = $callbackUrl; LogicAppId = $outputs.logicAppId.value }
    }
    catch {
        Write-Host ""
        Write-Host "  ERROR: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Troubleshooting:" -ForegroundColor Yellow
        Write-Host "    - Verify Logic App template syntax" -ForegroundColor Yellow
        Write-Host "    - Check Azure subscription quota limits" -ForegroundColor Yellow
        Write-Host "    - Ensure Contributor or Owner role on resource group" -ForegroundColor Yellow
        Write-Host ""
        throw
    }
}

function Deploy-ActionGroups {
    <#
    .SYNOPSIS
        Deploy 3 zone-specific Action Groups.
    .DESCRIPTION
        Phase 2 of 3-phase deployment.
        Deploys Action Groups for Zone 1, 2, and 3 with Logic App callback URL.
    .PARAMETER LogicAppCallbackUrl
        Callback URL from Phase 1 Logic App deployment
    .PARAMETER LogicAppId
        Resource ID of the Logic App from Phase 1 deployment output
    .OUTPUTS
        Hashtable with Zone1Id, Zone2Id, Zone3Id properties
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogicAppCallbackUrl,

        [Parameter(Mandatory=$true)]
        [string]$LogicAppId,

        [bool]$IsDryRun = $false
    )

    Write-Host "[Phase 2/3: Action Groups Deployment]" -ForegroundColor Cyan
    Write-Host ""

    if ($IsDryRun) {
        Write-Host "  Action Groups (DRY RUN - would be deployed):" -ForegroundColor Yellow
        Write-Host "    - Zone 1: Personal Productivity" -ForegroundColor Gray
        Write-Host "    - Zone 2: Team Collaboration" -ForegroundColor Gray
        Write-Host "    - Zone 3: Enterprise Managed" -ForegroundColor Gray
        return @{
            Zone1Id = "/subscriptions/dryrun/resourceGroups/dryrun/providers/Microsoft.Insights/actionGroups/zone1"
            Zone2Id = "/subscriptions/dryrun/resourceGroups/dryrun/providers/Microsoft.Insights/actionGroups/zone2"
            Zone3Id = "/subscriptions/dryrun/resourceGroups/dryrun/providers/Microsoft.Insights/actionGroups/zone3"
        }
    }

    $actionGroupIds = @{}
    $zones = @("zone1", "zone2", "zone3")
    $zoneLabels = @{
        "zone1" = "Personal Productivity"
        "zone2" = "Team Collaboration"
        "zone3" = "Enterprise Managed"
    }

    foreach ($zone in $zones) {
        $templatePath = Join-Path $AlertsDir "action-groups" "action-group-$zone.json"
        $deploymentName = "action-group-$zone-$(Get-Date -Format 'yyyyMMddHHmmss')"

        Write-Host "  Deploying Action Group: Zone $(($zone -replace 'zone','')) ($($zoneLabels[$zone]))..." -NoNewline

        try {
            # Deploy with shared parameters + Logic App callback URL and ID overrides
            az deployment group create `
                --resource-group $ResourceGroup `
                --name $deploymentName `
                --template-file $templatePath `
                --parameters "@$SharedParametersPath" `
                --parameters teamsLogicAppCallbackUrl=$LogicAppCallbackUrl `
                --parameters teamsLogicAppId=$LogicAppId `
                --query "properties.outputs" `
                --output json | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Write-Host " FAILED" -ForegroundColor Red
                throw "Action Group deployment failed for $zone (exit code: $LASTEXITCODE)"
            }

            Write-Host " DEPLOYED" -ForegroundColor Green

            # Retrieve Action Group resource ID
            $outputs = az deployment group show `
                --resource-group $ResourceGroup `
                --name $deploymentName `
                --query "properties.outputs.actionGroupId.value" `
                --output tsv 2>$null

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to retrieve Action Group ID for $zone (exit code: $LASTEXITCODE)"
            }

            $actionGroupIds["Zone$($zone -replace 'zone','')Id"] = $outputs
        }
        catch {
            Write-Host ""
            Write-Host "  ERROR: $_" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Troubleshooting:" -ForegroundColor Yellow
            Write-Host "    - Verify Action Group template syntax" -ForegroundColor Yellow
            Write-Host "    - Check shared parameters file for valid values" -ForegroundColor Yellow
            Write-Host "    - Ensure Logic App callback URL is valid" -ForegroundColor Yellow
            Write-Host ""
            throw
        }
    }

    Write-Host ""
    Write-Host "  All Action Groups deployed successfully" -ForegroundColor Green
    Write-Host ""

    return $actionGroupIds
}

function Deploy-AlertRules {
    <#
    .SYNOPSIS
        Deploy alert rules (ALRT-01, ALRT-02, ALRT-03).
    .DESCRIPTION
        Phase 3 of 3-phase deployment.
        Deploys 3 alert rule templates, each creating 3 zone-specific rules.
    .PARAMETER ActionGroupIds
        Hashtable with Zone1Id, Zone2Id, Zone3Id from Phase 2
    .OUTPUTS
        None
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$ActionGroupIds,

        [bool]$IsDryRun = $false
    )

    Write-Host "[Phase 3/3: Alert Rules Deployment]" -ForegroundColor Cyan
    Write-Host ""

    if ($IsDryRun) {
        Write-Host "  Alert Rules (DRY RUN - would be deployed):" -ForegroundColor Yellow
        Write-Host "    - ALRT-01: High Failure Rate (3 zones)" -ForegroundColor Gray
        Write-Host "    - ALRT-02: Latency Regression (3 zones)" -ForegroundColor Gray
        Write-Host "    - ALRT-03: Abnormal Usage (3 zones)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Note: Dynamic thresholds require 10-14 days baseline" -ForegroundColor Yellow
        Write-Host "        Alerts enter 'Learning' state initially" -ForegroundColor Yellow
        return
    }

    $alertTemplates = @(
        @{ File = "ALRT-01-high-failure-rate.json"; Name = "High Failure Rate" },
        @{ File = "ALRT-02-latency-regression.json"; Name = "Latency Regression" },
        @{ File = "ALRT-03-abnormal-usage.json"; Name = "Abnormal Usage" }
    )

    foreach ($alert in $alertTemplates) {
        $templatePath = Join-Path $AlertsDir $alert.File
        $deploymentName = "$($alert.File -replace '.json','')-$(Get-Date -Format 'yyyyMMddHHmmss')"

        Write-Host "  Deploying Alert: $($alert.Name)..." -NoNewline

        try {
            # Deploy with shared parameters + Action Group IDs override
            az deployment group create `
                --resource-group $ResourceGroup `
                --name $deploymentName `
                --template-file $templatePath `
                --parameters "@$SharedParametersPath" `
                --parameters applicationInsightsId=$ApplicationInsightsId `
                --parameters actionGroupZone1Id=$($ActionGroupIds.Zone1Id) `
                --parameters actionGroupZone2Id=$($ActionGroupIds.Zone2Id) `
                --parameters actionGroupZone3Id=$($ActionGroupIds.Zone3Id) `
                --mode Incremental `
                --output json | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Write-Host " FAILED" -ForegroundColor Red
                throw "Alert Rule deployment failed for $($alert.Name) (exit code: $LASTEXITCODE)"
            }

            Write-Host " DEPLOYED (3 zones)" -ForegroundColor Green
        }
        catch {
            Write-Host ""
            Write-Host "  ERROR: $_" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Troubleshooting:" -ForegroundColor Yellow
            Write-Host "    - Verify Alert Rule template syntax" -ForegroundColor Yellow
            Write-Host "    - Check Application Insights resource ID is valid" -ForegroundColor Yellow
            Write-Host "    - Ensure Action Group IDs are correct" -ForegroundColor Yellow
            Write-Host "    - Review KQL query syntax in template" -ForegroundColor Yellow
            Write-Host ""
            throw
        }
    }

    Write-Host ""
    Write-Host "  All Alert Rules deployed successfully (9 total)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Dynamic Threshold Note:" -ForegroundColor Yellow
    Write-Host "    Alerts require 10-14 days of telemetry data to establish baselines." -ForegroundColor Yellow
    Write-Host "    During this 'Learning' period, alerts are visible but do not fire." -ForegroundColor Yellow
    Write-Host "    This is NORMAL and expected behavior for dynamic thresholds." -ForegroundColor Yellow
    Write-Host ""
}

function Show-DeploymentSummary {
    <#
    .SYNOPSIS
        Display deployment summary with resource inventory.
    #>
    param(
        [hashtable]$ActionGroupIds,
        [bool]$IsDryRun = $false
    )

    Write-Host ""
    Write-Host "=" -NoNewline -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor Cyan
    if ($IsDryRun) {
        Write-Host "  DRY RUN COMPLETE - No Resources Deployed" -ForegroundColor Yellow
    }
    else {
        Write-Host "  DEPLOYMENT SUMMARY" -ForegroundColor Green
    }
    Write-Host "=" -NoNewline -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor Cyan
    Write-Host ""

    if ($IsDryRun) {
        Write-Host "  Run without -DryRun to deploy resources." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Resources Deployed:" -ForegroundColor White
        Write-Host ""
        Write-Host "    Logic App:" -ForegroundColor Cyan
        Write-Host "      - fsi-agent-alert-teams-notification-$Environment" -ForegroundColor Gray
        Write-Host ""
        Write-Host "    Action Groups:" -ForegroundColor Cyan
        Write-Host "      - ag-agent-zone1-general-$Environment (Personal Productivity)" -ForegroundColor Gray
        Write-Host "      - ag-agent-zone2-team-ops-$Environment (Team Collaboration)" -ForegroundColor Gray
        Write-Host "      - ag-agent-zone3-ent-ops-$Environment (Enterprise Managed)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "    Alert Rules (9 total = 3 types × 3 zones):" -ForegroundColor Cyan
        Write-Host "      - ALRT-01: High Failure Rate" -ForegroundColor Gray
        Write-Host "        ├─ Zone 1 (Severity: Warning)" -ForegroundColor DarkGray
        Write-Host "        ├─ Zone 2 (Severity: Error)" -ForegroundColor DarkGray
        Write-Host "        └─ Zone 3 (Severity: Critical)" -ForegroundColor DarkGray
        Write-Host "      - ALRT-02: Latency Regression" -ForegroundColor Gray
        Write-Host "        ├─ Zone 1 (Severity: Warning)" -ForegroundColor DarkGray
        Write-Host "        ├─ Zone 2 (Severity: Error)" -ForegroundColor DarkGray
        Write-Host "        └─ Zone 3 (Severity: Critical)" -ForegroundColor DarkGray
        Write-Host "      - ALRT-03: Abnormal Usage" -ForegroundColor Gray
        Write-Host "        ├─ Zone 1 (Severity: Informational)" -ForegroundColor DarkGray
        Write-Host "        ├─ Zone 2 (Severity: Warning)" -ForegroundColor DarkGray
        Write-Host "        └─ Zone 3 (Severity: Error)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "  Next Steps:" -ForegroundColor White
    Write-Host ""
    Write-Host "    1. Configure Teams channel IDs in Logic App workflow" -ForegroundColor Gray
    Write-Host "       (Edit Logic App in Azure Portal → Designer → Post to Teams action)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    2. Wait 10-14 days for dynamic threshold baseline learning" -ForegroundColor Gray
    Write-Host "       (Alerts show 'Learning' state during this period)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    3. Test alert notifications with intentional error spike" -ForegroundColor Gray
    Write-Host "       (After baseline period completes)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    4. Review alert firing history in Azure Monitor" -ForegroundColor Gray
    Write-Host "       (Monitor → Alerts → Alert Rules)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "=" -NoNewline -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor Cyan
    Write-Host ""
}

#endregion

#region Main Execution

try {
    # Show banner
    Show-Banner

    # Dry run indicator
    if ($DryRun) {
        Write-Host "*** DRY RUN MODE - No resources will be deployed ***" -ForegroundColor Yellow
        Write-Host ""
    }

    # Prerequisites check
    if (-not (Test-Prerequisites)) {
        Write-Host "Prerequisites validation failed. Exiting." -ForegroundColor Red
        exit 1
    }

    # Configuration summary
    Write-Host "[Configuration]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Resource Group:       $ResourceGroup" -ForegroundColor Gray
    Write-Host "  Environment:          $Environment" -ForegroundColor Gray
    Write-Host "  App Insights:         $ApplicationInsightsId" -ForegroundColor Gray
    Write-Host "  Shared Parameters:    $SharedParametersPath" -ForegroundColor Gray
    Write-Host ""

    # Confirmation prompt (unless -Force or -DryRun)
    if (-not $DryRun -and -not $Force) {
        Write-Host "  Alert deployment affects production monitoring." -ForegroundColor Yellow
        Write-Host "  Type 'yes' to continue: " -NoNewline -ForegroundColor Yellow
        $confirmation = Read-Host
        if ($confirmation -ne "yes") {
            Write-Host ""
            Write-Host "  Deployment cancelled." -ForegroundColor Yellow
            exit 0
        }
        Write-Host ""
    }

    # Phase 1: Deploy Logic App
    $logicAppResult = Deploy-LogicApp -IsDryRun $DryRun
    $logicAppCallbackUrl = $logicAppResult.LogicAppCallbackUrl

    # Phase 2: Deploy Action Groups
    $actionGroupIds = Deploy-ActionGroups -LogicAppCallbackUrl $logicAppCallbackUrl -LogicAppId $logicAppResult.LogicAppId -IsDryRun $DryRun

    # Phase 3: Deploy Alert Rules
    Deploy-AlertRules -ActionGroupIds $actionGroupIds -IsDryRun $DryRun

    # Show deployment summary
    Show-DeploymentSummary -ActionGroupIds $actionGroupIds -IsDryRun $DryRun

    exit 0
}
catch {
    Write-Host ""
    Write-Host "=" -NoNewline -ForegroundColor Red
    Write-Host ("=" * 68) -ForegroundColor Red
    Write-Host "  DEPLOYMENT FAILED" -ForegroundColor Red
    Write-Host "=" -NoNewline -ForegroundColor Red
    Write-Host ("=" * 68) -ForegroundColor Red
    Write-Host ""
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  For troubleshooting guidance, see:" -ForegroundColor Yellow
    Write-Host "    /agent-observability-foundation/alerts/README.md" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

#endregion
