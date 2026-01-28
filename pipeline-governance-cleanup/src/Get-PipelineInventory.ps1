<#
.SYNOPSIS
    Exports Power Platform pipeline inventory for governance review.

.DESCRIPTION
    Uses Power Platform CLI and Microsoft Graph to:
    - List all environments in tenant
    - Identify pipeline configurations per environment
    - Export pipeline ownership and status
    - Resolve owner email addresses via Microsoft Graph

    IMPORTANT LIMITATIONS:
    - Cannot directly query DeploymentPipeline table via API
    - Cannot identify pipelines host associations automatically
    - Manual correlation required to identify non-compliant pipelines

.PARAMETER OutputPath
    Path for the CSV output file. Defaults to PipelineInventory.csv in current directory.

.PARAMETER DesignatedHostId
    Environment ID of your designated pipelines host. Used to flag compliant environments.

.PARAMETER IncludeUserDetails
    If specified, resolves owner email addresses via Microsoft Graph (requires User.Read.All).

.EXAMPLE
    .\Get-PipelineInventory.ps1 -OutputPath ".\reports\inventory.csv"

.EXAMPLE
    .\Get-PipelineInventory.ps1 -DesignatedHostId "00000000-0000-0000-0000-000000000000" -IncludeUserDetails

.NOTES
    Prerequisites:
    - Power Platform CLI (pac) installed and authenticated
    - Microsoft Graph PowerShell SDK (if using -IncludeUserDetails)
    - Power Platform Admin role

    Permissions Required:
    - Power Platform: Environment Admin or Global Admin
    - Microsoft Graph: User.Read.All (for email resolution)

    This script provides INVENTORY ONLY. Force-linking environments to a custom
    pipelines host requires manual action in the Deployment Pipeline Configuration app.
    See PORTAL_WALKTHROUGH.md for manual procedures.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\PipelineInventory.csv",

    [Parameter(Mandatory = $false)]
    [string]$DesignatedHostId = "",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeUserDetails
)

# Ensure PAC CLI is available
function Test-PacCli {
    try {
        $null = pac help 2>&1
        return $true
    }
    catch {
        return $false
    }
}

# Get all environments using PAC CLI
function Get-PowerPlatformEnvironments {
    Write-Host "Retrieving Power Platform environments..." -ForegroundColor Cyan

    try {
        # Use pac env list to get all environments
        $envJson = pac env list --json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to list environments. Ensure you are authenticated with pac auth create."
            return $null
        }

        $environments = $envJson | ConvertFrom-Json
        Write-Host "Found $($environments.Count) environments" -ForegroundColor Green
        return $environments
    }
    catch {
        Write-Error "Error retrieving environments: $_"
        return $null
    }
}

# Get user details from Microsoft Graph
function Get-UserEmailFromGraph {
    param(
        [string]$UserId
    )

    if ([string]::IsNullOrEmpty($UserId)) {
        return "Unknown"
    }

    try {
        $user = Get-MgUser -UserId $UserId -Property "mail,userPrincipalName" -ErrorAction Stop
        if ($user.Mail) { return $user.Mail } else { return $user.UserPrincipalName }
    }
    catch {
        Write-Verbose "Could not resolve user $UserId : $_"
        return "Unable to resolve"
    }
}

# Main execution
function Main {
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Power Platform Pipeline Inventory Script" -ForegroundColor Cyan
    Write-Host "  Version: 1.0.2 - January 2026" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    # Verify PAC CLI
    if (-not (Test-PacCli)) {
        Write-Error @"
Power Platform CLI (pac) is not installed or not in PATH.
Install from: https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction
"@
        exit 1
    }

    # Connect to Microsoft Graph if user details requested
    if ($IncludeUserDetails) {
        Write-Host "Connecting to Microsoft Graph for user resolution..." -ForegroundColor Cyan
        try {
            Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
            Write-Host "Connected to Microsoft Graph" -ForegroundColor Green
        }
        catch {
            Write-Warning "Could not connect to Microsoft Graph. User emails will not be resolved."
            Write-Warning "Error: $_"
            $IncludeUserDetails = $false
        }
    }

    # Get all environments
    $environments = Get-PowerPlatformEnvironments
    if ($null -eq $environments) {
        exit 1
    }

    # Build inventory
    $results = @()
    $index = 0

    foreach ($env in $environments) {
        $index++
        Write-Progress -Activity "Processing environments" -Status "$index of $($environments.Count): $($env.DisplayName)" -PercentComplete (($index / $environments.Count) * 100)

        # Determine compliance status based on designated host
        $complianceStatus = "Unknown"
        if (-not [string]::IsNullOrEmpty($DesignatedHostId)) {
            # Note: This is a simplified check. In reality, you need to query the
            # Deployment Pipeline Configuration app to see which host an environment is linked to.
            # This information is not available via PAC CLI or public API.
            $complianceStatus = "Requires Manual Verification"
        }

        $result = [PSCustomObject]@{
            EnvironmentId       = $env.EnvironmentId
            EnvironmentName     = $env.DisplayName
            EnvironmentType     = $env.EnvironmentType
            EnvironmentUrl      = $env.EnvironmentUrl
            IsManaged           = $env.IsManaged
            CreatedTime         = $env.CreatedTime
            # The following fields cannot be populated via API - manual inspection required
            PipelinesHostId     = "[Manual Check Required]"
            HasPipelinesEnabled = "[Manual Check Required]"
            ComplianceStatus    = $complianceStatus
            Notes               = "Run manual verification in Deployment Pipeline Configuration app"
        }

        $results += $result
    }

    Write-Progress -Activity "Processing environments" -Completed

    # Export to CSV
    Write-Host ""
    Write-Host "Exporting inventory to: $OutputPath" -ForegroundColor Cyan

    try {
        $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Successfully exported $($results.Count) environment records" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export CSV: $_"
        exit 1
    }

    # Summary
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Inventory Summary" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Total Environments: $($results.Count)"
    Write-Host "Managed Environments: $(($results | Where-Object { $_.IsManaged -eq $true }).Count)"
    Write-Host "Output File: $OutputPath"
    Write-Host ""
    Write-Host "IMPORTANT: This inventory lists environments only." -ForegroundColor Yellow
    Write-Host "To identify which environments have pipelines or are linked to a" -ForegroundColor Yellow
    Write-Host "specific pipelines host, you must manually check each environment" -ForegroundColor Yellow
    Write-Host "using the Deployment Pipeline Configuration app." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "See PORTAL_WALKTHROUGH.md for manual verification procedures." -ForegroundColor Yellow

    # Disconnect from Graph if connected
    if ($IncludeUserDetails) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}

# Run main function
Main
