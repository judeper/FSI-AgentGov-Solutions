#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Microsoft.PowerApps.Administration.PowerShell'; ModuleVersion = '2.0' }
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.0' }

<#
.SYNOPSIS
    Enables audit logging on non-compliant Power Platform environments.

.DESCRIPTION
    Remediation runbook for the Audit Logging Compliance Automation (ALCA) solution.
    Enables org-level and entity-level Dataverse auditing on environments that are
    marked as non-compliant in the fsi_auditenvironmentcompliance Dataverse table.

    Supports:
    - Tenant-wide Purview unified audit enablement
    - Per-environment Dataverse org-level audit enablement
    - Entity-level audit on 6 Copilot Studio entities
    - WhatIf simulation mode
    - Post-remediation validation
    - CSV export of results

    Authentication: System-Assigned Managed Identity in Azure Automation.
    NEVER uses interactive auth or hardcoded credentials.

.PARAMETER DataverseEnvironmentUrl
    Mandatory. The Dataverse environment URL hosting the compliance table.
    Example: https://org.crm.dynamics.com

.PARAMETER TenantDomain
    Mandatory. The tenant domain for Exchange Online connection.
    Example: contoso.onmicrosoft.com

.PARAMETER EnvironmentId
    Optional. Target a specific environment by GUID. If omitted, queries
    Dataverse for all environments with fsi_compliancestatus = Non-Compliant (100000001).

.PARAMETER EnableTenantUnifiedAudit
    Switch. If set, enables tenant-wide Purview unified audit via Set-AdminConfig.
    Default: $true. This is a tenant-wide change — use with caution.

.PARAMETER WhatIf
    Switch. If set, simulates remediation without making changes.
    Outputs "[WHATIF] Would enable..." messages.

.NOTES
    Version: 1.0.0
    Requires: PowerShell 7.2+, Azure Automation with System-Assigned MI
    Modules: Microsoft.PowerApps.Administration.PowerShell 2.0+, ExchangeOnlineManagement 3.0+
    ALCA Solution: Audit Logging Compliance Automation

.EXAMPLE
    # Remediate all non-compliant environments
    .\Enable-AuditLogging.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com" -TenantDomain "contoso.onmicrosoft.com"

.EXAMPLE
    # WhatIf mode — simulate without changes
    .\Enable-AuditLogging.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com" -TenantDomain "contoso.onmicrosoft.com" -WhatIf

.EXAMPLE
    # Target a specific environment
    .\Enable-AuditLogging.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com" -TenantDomain "contoso.onmicrosoft.com" -EnvironmentId "abc-123-def"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseEnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantDomain,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $false)]
    [switch]$EnableTenantUnifiedAudit = $true
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Continue"

# 6 Copilot Studio entities requiring entity-level audit
$CopilotStudioEntities = @(
    "bot",
    "botcomponent",
    "connectionreference",
    "environmentvariablevalue",
    "workflow",
    "systemuser"
)

# Propagation wait time after enablement (seconds)
$ValidationWaitSeconds = 5

# ============================================================================
# Import Helper Module
# ============================================================================

$modulePath = Join-Path $PSScriptRoot "AuditComplianceHelpers.psm1"
if (-not (Test-Path $modulePath)) {
    throw "Helper module not found at: $modulePath. Ensure AuditComplianceHelpers.psm1 is in the same directory."
}
Import-Module $modulePath -Force

# ============================================================================
# Helper Functions
# ============================================================================

function Get-EnvironmentOrgId {
    <#
    .SYNOPSIS
        Gets the Dataverse organization ID for an environment.
    #>
    param(
        [string]$EnvUrl,
        [string]$Token
    )

    $result = Invoke-DataverseRequest -EnvironmentUrl $EnvUrl `
        -RelativeUri "/api/data/v9.2/organizations?`$select=organizationid,isauditenabled" `
        -Token $Token -Method GET

    if ($result.value -and $result.value.Count -gt 0) {
        return $result.value[0]
    }
    return $null
}

function Enable-OrgLevelAudit {
    <#
    .SYNOPSIS
        Enables org-level Dataverse auditing on an environment.
    #>
    param(
        [string]$EnvUrl,
        [string]$Token,
        [string]$OrgId,
        [bool]$IsWhatIf
    )

    if ($IsWhatIf) {
        Write-Output "      [WHATIF] Would enable org-level Dataverse auditing (PATCH organizations($OrgId) isauditenabled=true)"
        return $true
    }

    $body = @{ isauditenabled = $true }
    Invoke-DataverseRequest -EnvironmentUrl $EnvUrl `
        -RelativeUri "/api/data/v9.2/organizations($OrgId)" `
        -Token $Token -Method PATCH -Body $body

    return $true
}

function Enable-EntityLevelAudit {
    <#
    .SYNOPSIS
        Enables auditing on a specific Dataverse entity.
    #>
    param(
        [string]$EnvUrl,
        [string]$Token,
        [string]$EntityLogicalName,
        [bool]$IsWhatIf
    )

    if ($IsWhatIf) {
        Write-Output "      [WHATIF] Would enable entity-level audit on: $EntityLogicalName"
        return $true
    }

    $body = @{
        IsAuditEnabled = @{ Value = $true }
    }

    Invoke-DataverseRequest -EnvironmentUrl $EnvUrl `
        -RelativeUri "/api/data/v9.2/EntityDefinitions(LogicalName='$EntityLogicalName')" `
        -Token $Token -Method PUT -Body $body

    return $true
}

function Test-OrgAuditEnabled {
    <#
    .SYNOPSIS
        Validates that org-level auditing is enabled.
    #>
    param(
        [string]$EnvUrl,
        [string]$Token
    )

    $result = Invoke-DataverseRequest -EnvironmentUrl $EnvUrl `
        -RelativeUri "/api/data/v9.2/organizations?`$select=isauditenabled" `
        -Token $Token -Method GET

    if ($result.value -and $result.value.Count -gt 0) {
        return [bool]$result.value[0].isauditenabled
    }
    return $false
}

function Test-EntityAuditEnabled {
    <#
    .SYNOPSIS
        Validates that entity-level auditing is enabled.
    #>
    param(
        [string]$EnvUrl,
        [string]$Token,
        [string]$EntityLogicalName
    )

    $result = Invoke-DataverseRequest -EnvironmentUrl $EnvUrl `
        -RelativeUri "/api/data/v9.2/EntityDefinitions(LogicalName='$EntityLogicalName')?`$select=IsAuditEnabled" `
        -Token $Token -Method GET

    if ($result.IsAuditEnabled) {
        return [bool]$result.IsAuditEnabled.Value
    }
    return $false
}

# ============================================================================
# Main Execution
# ============================================================================

$startTime = Get-Date
$isWhatIf = $WhatIfPreference

# Results tracking
$results = [System.Collections.Generic.List[PSObject]]::new()

# Counters
$envProcessed = 0
$envSuccessful = 0
$envNoChanges = 0
$envFailed = 0

try {
    # =========================================================================
    # Step 1: Authentication
    # =========================================================================
    Write-Output "`n[Step 1/6] Authenticating via Managed Identity..."

    if ($isWhatIf) {
        Write-Output "  [WHATIF] Would authenticate to Power Platform, Exchange Online, and Dataverse"
    }
    else {
        # Power Platform authentication
        $ppToken = Get-ManagedIdentityToken -Resource "https://api.bap.microsoft.com"
        Add-PowerAppsAccount -Endpoint prod -TenantID $TenantDomain
        Write-Output "  Power Platform: Connected"

        # Exchange Online authentication
        Connect-ExchangeOnline -ManagedIdentity -Organization $TenantDomain -ShowBanner:$false
        Write-Output "  Exchange Online: Connected"
    }

    # Dataverse token for compliance table operations
    $dvToken = if (-not $isWhatIf) {
        Get-DataverseToken -DataverseEnvironmentUrl $DataverseEnvironmentUrl
    } else { "WHATIF-TOKEN" }
    Write-Output "  Dataverse: $(if ($isWhatIf) { '[WHATIF] Would connect' } else { 'Connected' })"

    # =========================================================================
    # Step 2: Determine Targets
    # =========================================================================
    Write-Output "`n[Step 2/6] Determining remediation targets..."

    $targetEnvironments = @()

    if ($EnvironmentId) {
        # Specific environment requested
        Write-Output "  Target: Specific environment $EnvironmentId"

        if ($isWhatIf) {
            $targetEnvironments = @([PSCustomObject]@{
                EnvironmentId   = $EnvironmentId
                EnvironmentName = "(WhatIf - name lookup skipped)"
                EnvironmentUrl  = $null
            })
        }
        else {
            # Look up environment details from Power Platform
            $env = Get-AdminPowerAppEnvironment -EnvironmentName $EnvironmentId -ErrorAction SilentlyContinue
            if ($env) {
                $envUrl = $env.Internal.Properties.linkedEnvironmentMetadata.instanceUrl
                $targetEnvironments = @([PSCustomObject]@{
                    EnvironmentId   = $EnvironmentId
                    EnvironmentName = $env.DisplayName
                    EnvironmentUrl  = $envUrl
                })
            }
            else {
                Write-Warning "Environment $EnvironmentId not found via Power Platform Admin. Attempting Dataverse lookup..."
                $filterUri = "/api/data/v9.2/fsi_auditenvironmentcompliances?`$filter=fsi_environmentid eq '$EnvironmentId'"
                $dvRecord = Invoke-DataverseRequest -EnvironmentUrl $DataverseEnvironmentUrl -RelativeUri $filterUri -Token $dvToken -Method GET
                if ($dvRecord.value -and $dvRecord.value.Count -gt 0) {
                    $targetEnvironments = @([PSCustomObject]@{
                        EnvironmentId   = $EnvironmentId
                        EnvironmentName = $dvRecord.value[0].fsi_environmentname
                        EnvironmentUrl  = $null
                    })
                }
                else {
                    throw "Environment $EnvironmentId not found in Power Platform or Dataverse compliance table."
                }
            }
        }
    }
    else {
        # Query Dataverse for all non-compliant environments
        Write-Output "  Target: All non-compliant environments (fsi_compliancestatus = 100000001)"

        if ($isWhatIf) {
            Write-Output "  [WHATIF] Would query Dataverse for non-compliant environments"
            $targetEnvironments = @()
        }
        else {
            $filterUri = "/api/data/v9.2/fsi_auditenvironmentcompliances?`$filter=fsi_compliancestatus eq 100000001&`$select=fsi_environmentid,fsi_environmentname"
            $nonCompliant = Invoke-DataverseRequest -EnvironmentUrl $DataverseEnvironmentUrl -RelativeUri $filterUri -Token $dvToken -Method GET

            if ($nonCompliant.value -and $nonCompliant.value.Count -gt 0) {
                foreach ($record in $nonCompliant.value) {
                    # Look up environment URL from Power Platform
                    $env = Get-AdminPowerAppEnvironment -EnvironmentName $record.fsi_environmentid -ErrorAction SilentlyContinue
                    $envUrl = if ($env) { $env.Internal.Properties.linkedEnvironmentMetadata.instanceUrl } else { $null }

                    $targetEnvironments += [PSCustomObject]@{
                        EnvironmentId   = $record.fsi_environmentid
                        EnvironmentName = $record.fsi_environmentname
                        EnvironmentUrl  = $envUrl
                    }
                }
            }
        }
    }

    Write-Output "  Found $($targetEnvironments.Count) environment(s) to remediate"

    if ($targetEnvironments.Count -eq 0 -and -not $isWhatIf) {
        Write-Output "`n  No non-compliant environments found. Nothing to remediate."
    }

    # =========================================================================
    # Step 3: Tenant-Wide Purview Unified Audit
    # =========================================================================
    Write-Output "`n[Step 3/6] Tenant-wide Purview unified audit..."

    if ($EnableTenantUnifiedAudit) {
        if ($isWhatIf) {
            Write-Output "  [WHATIF] Would enable tenant-wide Purview unified audit via Set-AdminConfig"
            Write-Output "  [WHATIF] WARNING: This is a TENANT-WIDE change affecting all environments"
        }
        else {
            Write-Output "  WARNING: Enabling tenant-wide Purview unified audit (tenant-wide change)"
            if ($PSCmdlet.ShouldProcess("Tenant: $TenantDomain", "Enable Purview Unified Audit Logging")) {
                try {
                    $currentConfig = Get-AdminPowerAppTenantSettings
                    if ($currentConfig.powerPlatform.governance.disableAuditLogging -eq $false) {
                        Write-Output "  Purview unified audit: Already enabled"
                    }
                    else {
                        $settings = @{
                            powerPlatform = @{
                                governance = @{
                                    disableAuditLogging = $false
                                }
                            }
                        }
                        Set-AdminPowerAppTenantSettings -RequestBody $settings
                        Write-Output "  Purview unified audit: ENABLED"
                    }
                }
                catch {
                    Write-Warning "  Failed to enable tenant-wide Purview audit: $($_.Exception.Message)"
                }
            }
        }
    }
    else {
        Write-Output "  Skipped (EnableTenantUnifiedAudit not set)"
    }

    # =========================================================================
    # Step 4: Per-Environment Remediation
    # =========================================================================
    Write-Output "`n[Step 4/6] Remediating environments..."

    $envIndex = 0
    foreach ($targetEnv in $targetEnvironments) {
        $envIndex++
        $envProcessed++
        $envId = $targetEnv.EnvironmentId
        $envName = $targetEnv.EnvironmentName
        $envUrl = $targetEnv.EnvironmentUrl

        Write-Output "`n  --- Environment $envIndex/$($targetEnvironments.Count): $envName ($envId) ---"

        $envResult = [PSCustomObject]@{
            EnvironmentId   = $envId
            EnvironmentName = $envName
            OrgAudit        = "N/A"
            EntityAudit     = "N/A"
            Validation      = "N/A"
            Status          = "Pending"
            ErrorMessage    = ""
        }

        try {
            if (-not $envUrl) {
                if ($isWhatIf) {
                    Write-Output "    [WHATIF] Would resolve environment URL for $envId"
                    $envResult.OrgAudit = "WhatIf"
                    $envResult.EntityAudit = "WhatIf"
                    $envResult.Validation = "WhatIf"
                    $envResult.Status = "WhatIf - Simulated"
                    $envSuccessful++
                    $results.Add($envResult)
                    continue
                }
                else {
                    throw "No Dataverse URL available for environment $envId. Environment may not have Dataverse provisioned."
                }
            }

            # Get environment-specific Dataverse token
            $envToken = if (-not $isWhatIf) {
                Get-DataverseToken -DataverseEnvironmentUrl $envUrl
            } else { "WHATIF-TOKEN" }

            # -----------------------------------------------------------------
            # Step 4a: Enable org-level Dataverse audit
            # -----------------------------------------------------------------
            Write-Output "    [4a] Org-level Dataverse audit..."

            if (-not $isWhatIf) {
                $orgInfo = Get-EnvironmentOrgId -EnvUrl $envUrl -Token $envToken
                if (-not $orgInfo) {
                    throw "Could not retrieve organization info for environment $envId"
                }

                $orgId = $orgInfo.organizationid
                $alreadyEnabled = [bool]$orgInfo.isauditenabled

                if ($alreadyEnabled) {
                    Write-Output "      Org-level audit: Already enabled"
                    $envResult.OrgAudit = "Already Enabled"
                }
                else {
                    if ($PSCmdlet.ShouldProcess("Environment: $envName ($envId)", "Enable org-level Dataverse auditing")) {
                        Enable-OrgLevelAudit -EnvUrl $envUrl -Token $envToken -OrgId $orgId -IsWhatIf $false
                        Write-Output "      Org-level audit: ENABLED"
                        $envResult.OrgAudit = "Enabled"
                    }
                }
            }
            else {
                Enable-OrgLevelAudit -EnvUrl $envUrl -Token $envToken -OrgId "WHATIF-ORG" -IsWhatIf $true
                $envResult.OrgAudit = "WhatIf"
            }

            # -----------------------------------------------------------------
            # Step 4b: Enable entity-level audit on 6 Copilot Studio entities
            # -----------------------------------------------------------------
            Write-Output "    [4b] Entity-level audit (6 Copilot Studio entities)..."

            $entityResults = @()
            foreach ($entity in $CopilotStudioEntities) {
                try {
                    if ($isWhatIf) {
                        Enable-EntityLevelAudit -EnvUrl $envUrl -Token $envToken -EntityLogicalName $entity -IsWhatIf $true
                        $entityResults += "$entity=WhatIf"
                    }
                    else {
                        if ($PSCmdlet.ShouldProcess("Entity: $entity in $envName", "Enable entity-level auditing")) {
                            Enable-EntityLevelAudit -EnvUrl $envUrl -Token $envToken -EntityLogicalName $entity -IsWhatIf $false
                            Write-Output "      $entity : ENABLED"
                            $entityResults += "$entity=Enabled"
                        }
                    }
                }
                catch {
                    Write-Warning "      $entity : FAILED - $($_.Exception.Message)"
                    $entityResults += "$entity=Failed"
                }
            }
            $envResult.EntityAudit = ($entityResults -join "; ")

            # -----------------------------------------------------------------
            # Step 4c: Validation after propagation wait
            # -----------------------------------------------------------------
            Write-Output "    [4c] Validation (waiting ${ValidationWaitSeconds}s for propagation)..."

            if ($isWhatIf) {
                Write-Output "      [WHATIF] Would wait ${ValidationWaitSeconds}s then validate org + entity audit settings"
                $envResult.Validation = "WhatIf"
                $envResult.Status = "WhatIf - Simulated"
                $envSuccessful++
            }
            else {
                Start-Sleep -Seconds $ValidationWaitSeconds

                # Validate org-level
                $orgValid = Test-OrgAuditEnabled -EnvUrl $envUrl -Token $envToken
                Write-Output "      Org-level audit validation: $(if ($orgValid) { 'PASS' } else { 'FAIL' })"

                # Validate entity-level
                $entityValidCount = 0
                $entityTotalCount = $CopilotStudioEntities.Count
                foreach ($entity in $CopilotStudioEntities) {
                    try {
                        $entityValid = Test-EntityAuditEnabled -EnvUrl $envUrl -Token $envToken -EntityLogicalName $entity
                        if ($entityValid) { $entityValidCount++ }
                    }
                    catch {
                        Write-Verbose "      Validation check failed for $entity : $($_.Exception.Message)"
                    }
                }
                Write-Output "      Entity-level audit validation: $entityValidCount/$entityTotalCount passed"

                if ($orgValid -and $entityValidCount -eq $entityTotalCount) {
                    $envResult.Validation = "PASS"
                    $envResult.Status = "Remediated"
                    $envSuccessful++

                    # Update Dataverse compliance record to Compliant
                    Write-Output "    [4d] Updating compliance record to Compliant..."
                    try {
                        Write-DataverseComplianceRecord -EnvironmentUrl $DataverseEnvironmentUrl `
                            -Token $dvToken -EnvironmentId $envId -EnvironmentName $envName `
                            -AuditEnabled $true -DataverseAuditEnabled $true `
                            -ComplianceStatus "Compliant" -RemediatedBy "ALCA-ManagedIdentity"
                        Write-Output "      Compliance record: Updated to Compliant"
                    }
                    catch {
                        Write-Warning "      Failed to update compliance record: $($_.Exception.Message)"
                    }
                }
                elseif (-not $orgValid) {
                    $envResult.Validation = "FAIL - Org-level"
                    $envResult.Status = "Validation Failed"
                    $envFailed++

                    # Update Dataverse with Remediation Pending
                    try {
                        Write-DataverseComplianceRecord -EnvironmentUrl $DataverseEnvironmentUrl `
                            -Token $dvToken -EnvironmentId $envId -EnvironmentName $envName `
                            -AuditEnabled $false -DataverseAuditEnabled $false `
                            -ComplianceStatus "Remediation Pending" `
                            -ErrorMessage "Validation failed: org-level audit not confirmed after remediation"
                    }
                    catch {
                        Write-Verbose "Failed to update compliance record: $($_.Exception.Message)"
                    }
                }
                else {
                    $envResult.Validation = "PARTIAL - $entityValidCount/$entityTotalCount entities"
                    $envResult.Status = "Validation Failed"
                    $envFailed++

                    try {
                        Write-DataverseComplianceRecord -EnvironmentUrl $DataverseEnvironmentUrl `
                            -Token $dvToken -EnvironmentId $envId -EnvironmentName $envName `
                            -AuditEnabled $orgValid -DataverseAuditEnabled $orgValid `
                            -ComplianceStatus "Remediation Pending" `
                            -ErrorMessage "Validation partial: $entityValidCount/$entityTotalCount entity audits confirmed"
                    }
                    catch {
                        Write-Verbose "Failed to update compliance record: $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "  Environment $envId FAILED: $errorMsg"

            $envResult.Status = "Error"
            $envResult.ErrorMessage = $errorMsg
            $envFailed++

            # Update Dataverse with Error status
            if (-not $isWhatIf) {
                try {
                    Write-DataverseComplianceRecord -EnvironmentUrl $DataverseEnvironmentUrl `
                        -Token $dvToken -EnvironmentId $envId -EnvironmentName $envName `
                        -AuditEnabled $false -DataverseAuditEnabled $false `
                        -ComplianceStatus "Error" -ErrorMessage $errorMsg
                }
                catch {
                    Write-Verbose "Failed to update compliance record on error: $($_.Exception.Message)"
                }
            }
        }

        $results.Add($envResult)
    }

    # =========================================================================
    # Step 5: Remediation Summary
    # =========================================================================
    Write-Output "`n[Step 5/6] Remediation Summary"
    Write-Output "  =========================================="
    Write-Output "  Total Processed:  $envProcessed"
    Write-Output "  Successful:       $envSuccessful"
    Write-Output "  No Changes:       $envNoChanges"
    Write-Output "  Failed:           $envFailed"
    Write-Output "  =========================================="

    if ($isWhatIf) {
        Write-Output "`n  *** WHATIF MODE — No actual changes were made ***"
    }

    if ($results.Count -gt 0) {
        Write-Output "`n  Per-Environment Results:"
        Write-Output "  $('-' * 100)"
        foreach ($r in $results) {
            Write-Output "  $($r.EnvironmentName.PadRight(30)) | Status: $($r.Status.PadRight(20)) | Validation: $($r.Validation)"
        }
    }

    # =========================================================================
    # Step 6: CSV Export
    # =========================================================================
    Write-Output "`n[Step 6/6] Exporting results..."

    if ($results.Count -gt 0) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $csvPath = Join-Path $env:TEMP "ALCA-Remediation-$timestamp.csv"

        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Output "  CSV exported: $csvPath"
    }
    else {
        Write-Output "  No results to export."
    }

    # Duration
    $duration = (Get-Date) - $startTime
    Write-Output "`n  Completed in $([Math]::Round($duration.TotalSeconds, 1)) seconds"
}
catch {
    # Fatal error (auth failure or unexpected)
    Write-Error "FATAL ERROR: $($_.Exception.Message)"
    throw
}
finally {
    # =========================================================================
    # Cleanup: Disconnect sessions
    # =========================================================================
    if (-not $isWhatIf) {
        try {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            Write-Verbose "Exchange Online: Disconnected"
        }
        catch {
            Write-Verbose "Exchange Online disconnect: $($_.Exception.Message)"
        }

        try {
            Remove-PowerAppsAccount -ErrorAction SilentlyContinue
            Write-Verbose "Power Platform: Disconnected"
        }
        catch {
            Write-Verbose "Power Platform disconnect: $($_.Exception.Message)"
        }
    }
}
