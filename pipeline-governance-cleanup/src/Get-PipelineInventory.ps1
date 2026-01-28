<#
.SYNOPSIS
    Exports Power Platform Dataverse environment inventory for governance review.

.DESCRIPTION
    Uses Power Platform CLI to:
    - List all Dataverse environments in tenant
    - Optionally probe each environment for pipeline configurations

    IMPORTANT LIMITATIONS:
    - Cannot identify pipelines host associations automatically
    - Cannot query DeploymentPipeline table directly
    - Manual correlation required for non-compliant pipeline identification

.PARAMETER OutputPath
    Path for the CSV output file. Defaults to PipelineInventory.csv in current directory.

.PARAMETER DesignatedHostId
    Environment ID of your designated pipelines host. Used to flag compliant environments.

.PARAMETER ProbePipelines
    If specified, probes each environment to check for pipeline configurations using
    'pac pipeline list --environment'. This can detect whether pipelines deploy TO an
    environment but cannot determine the host environment association.

.EXAMPLE
    .\Get-PipelineInventory.ps1 -OutputPath ".\reports\inventory.csv"

.EXAMPLE
    .\Get-PipelineInventory.ps1 -OutputPath ".\reports\inventory.csv" -ProbePipelines

.EXAMPLE
    .\Get-PipelineInventory.ps1 -DesignatedHostId "00000000-0000-0000-0000-000000000000" -ProbePipelines

.NOTES
    Prerequisites:
    - Power Platform CLI (pac) installed and authenticated
    - Power Platform Admin role

    Permissions Required:
    - Power Platform: Environment Admin or Global Admin

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
    [switch]$ProbePipelines
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

# Probe an environment for pipeline configurations
function Test-EnvironmentPipelines {
    param(
        [string]$EnvironmentId
    )

    try {
        $result = pac pipeline list --environment $EnvironmentId --json 2>&1

        if ($LASTEXITCODE -ne 0) {
            # Check if it's a "no pipelines" message vs actual error
            $resultText = $result -join " "
            if ($resultText -match "No pipelines found" -or $resultText -match "no records") {
                return @{ HasPipelines = "No"; Notes = "" }
            }
            return @{ HasPipelines = "Unknown"; Notes = "Unable to query: $resultText" }
        }

        $pipelines = $result | ConvertFrom-Json

        if ($null -eq $pipelines -or $pipelines.Count -eq 0) {
            return @{ HasPipelines = "No"; Notes = "" }
        }

        return @{ HasPipelines = "Yes"; Notes = "$($pipelines.Count) pipeline(s) found" }
    }
    catch {
        return @{ HasPipelines = "Unknown"; Notes = "Error: $_" }
    }
}

# Main execution
function Main {
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Power Platform Environment Inventory Script" -ForegroundColor Cyan
    Write-Host "  Version: 1.0.3 - January 2026" -ForegroundColor Cyan
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

    if ($ProbePipelines) {
        Write-Host "Pipeline probing enabled - will check each environment for pipelines" -ForegroundColor Yellow
        Write-Host ""
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

        # Probe for pipelines if requested
        $pipelineStatus = @{ HasPipelines = "[Not Probed]"; Notes = "" }
        if ($ProbePipelines) {
            Write-Verbose "Probing pipelines for $($env.DisplayName)..."
            $pipelineStatus = Test-EnvironmentPipelines -EnvironmentId $env.EnvironmentId
        }

        # Build notes field
        $notes = if ($pipelineStatus.Notes) {
            $pipelineStatus.Notes
        }
        elseif (-not $ProbePipelines) {
            "Run with -ProbePipelines or verify manually"
        }
        else {
            ""
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
            HasPipelinesEnabled = $pipelineStatus.HasPipelines
            ComplianceStatus    = $complianceStatus
            Notes               = $notes
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

    if ($ProbePipelines) {
        $withPipelines = ($results | Where-Object { $_.HasPipelinesEnabled -eq "Yes" }).Count
        $withoutPipelines = ($results | Where-Object { $_.HasPipelinesEnabled -eq "No" }).Count
        $unknown = ($results | Where-Object { $_.HasPipelinesEnabled -eq "Unknown" }).Count
        Write-Host "Environments with Pipelines: $withPipelines"
        Write-Host "Environments without Pipelines: $withoutPipelines"
        if ($unknown -gt 0) {
            Write-Host "Unable to Probe: $unknown" -ForegroundColor Yellow
        }
    }

    Write-Host "Output File: $OutputPath"
    Write-Host ""

    if (-not $ProbePipelines) {
        Write-Host "TIP: Run with -ProbePipelines to detect pipeline configurations automatically" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "IMPORTANT: This inventory lists environments and pipeline presence only." -ForegroundColor Yellow
    Write-Host "To identify which PIPELINES HOST an environment is linked to," -ForegroundColor Yellow
    Write-Host "you must manually check using the Deployment Pipeline Configuration app." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "See PORTAL_WALKTHROUGH.md for manual verification procedures." -ForegroundColor Yellow
}

# Run main function
Main
