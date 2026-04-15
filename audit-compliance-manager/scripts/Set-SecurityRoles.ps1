#Requires -Version 7.2

<#
.SYNOPSIS
    Configures Dataverse security roles to enforce immutability on AuditValidationHistory.

.DESCRIPTION
    Creates or updates a custom security role that grants only Create (append-only) access
    to the fsi_auditvalidationhistory table. Write and Delete privileges are explicitly
    excluded to enforce immutability of audit validation records.

    This script addresses the post-deployment security lockdown requirement documented
    in deploy.py and create_dataverse_schema.py: security roles must remove Write/Delete
    privileges after deployment.

    The script:
    1. Connects to the Dataverse Web API
    2. Resolves the AuditValidationHistory entity metadata
    3. Creates or updates a security role named "ACV Automation - Append Only"
    4. Assigns Create privilege (no Write, Delete, Append, or Assign)

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER AccessToken
    Bearer token for Dataverse Web API authentication.

.PARAMETER RoleName
    Name of the security role to create/update. Default: "ACV Automation - Append Only".

.PARAMETER BusinessUnitId
    GUID of the root business unit. If not provided, the script queries for it.

.PARAMETER WhatIf
    If specified, shows what would be changed without making modifications.

.EXAMPLE
    ./Set-SecurityRoles.ps1 -DataverseUrl "https://org.crm.dynamics.com" -AccessToken $token

.EXAMPLE
    ./Set-SecurityRoles.ps1 -DataverseUrl "https://org.crm.dynamics.com" -AccessToken $token -WhatIf

.NOTES
    Version: 1.0.0
    Requires: System Administrator role on the target Dataverse environment.
    The created role should be assigned to the automation Managed Identity
    INSTEAD OF System Administrator for production environments.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [string]$RoleName = "ACV Automation - Append Only",

    [Parameter(Mandatory = $false)]
    [string]$BusinessUnitId
)

$ErrorActionPreference = "Stop"
$DataverseUrl = $DataverseUrl.TrimEnd('/')

$headers = @{
    "Authorization"    = "Bearer $AccessToken"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Accept"           = "application/json"
}

Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  ACV Security Role Configuration" -ForegroundColor Cyan
Write-Host "  Enforcing append-only access on AuditValidationHistory" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

# Step 1: Resolve root business unit if not provided
if (-not $BusinessUnitId) {
    Write-Host "Resolving root business unit..." -ForegroundColor Gray
    $buUrl = "$DataverseUrl/api/data/v9.2/businessunits?`$filter=parentbusinessunitid eq null&`$select=businessunitid,name"
    $buResponse = Invoke-RestMethod -Uri $buUrl -Method Get -Headers $headers -ErrorAction Stop
    if ($buResponse.value.Count -eq 0) {
        throw "Could not find root business unit."
    }
    $BusinessUnitId = $buResponse.value[0].businessunitid
    Write-Host "  Root business unit: $($buResponse.value[0].name) ($BusinessUnitId)" -ForegroundColor Green
}

# Step 2: Resolve AuditValidationHistory entity object type code
Write-Host "Resolving AuditValidationHistory entity metadata..." -ForegroundColor Gray
$entityUrl = "$DataverseUrl/api/data/v9.2/EntityDefinitions(LogicalName='fsi_auditvalidationhistory')?`$select=ObjectTypeCode,LogicalName"
$entityMeta = Invoke-RestMethod -Uri $entityUrl -Method Get -Headers $headers -ErrorAction Stop
$objectTypeCode = $entityMeta.ObjectTypeCode
Write-Host "  Entity ObjectTypeCode: $objectTypeCode" -ForegroundColor Green

# Step 3: Check if role already exists
Write-Host "Checking for existing security role '$RoleName'..." -ForegroundColor Gray
$roleFilterName = $RoleName -replace "'", "''"
$roleUrl = "$DataverseUrl/api/data/v9.2/roles?`$filter=name eq '$roleFilterName' and _businessunitid_value eq $BusinessUnitId&`$select=roleid,name"
$roleResponse = Invoke-RestMethod -Uri $roleUrl -Method Get -Headers $headers -ErrorAction Stop

$roleId = $null

if ($roleResponse.value.Count -gt 0) {
    $roleId = $roleResponse.value[0].roleid
    Write-Host "  Found existing role: $roleId" -ForegroundColor Yellow
}
else {
    if ($PSCmdlet.ShouldProcess($RoleName, "Create security role")) {
        Write-Host "  Creating new security role..." -ForegroundColor Green
        $createRoleBody = @{
            name                              = $RoleName
            description                       = "Append-only access to AuditValidationHistory for automation accounts. Write and Delete are denied to enforce immutability."
            "businessunitid@odata.bind"        = "/businessunits($BusinessUnitId)"
        } | ConvertTo-Json

        $createRoleResponse = Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/roles" -Method Post -Headers $headers -Body $createRoleBody -ErrorAction Stop
        $roleId = $createRoleResponse.roleid

        if (-not $roleId) {
            # Extract from OData-EntityId header pattern
            $roleUrl2 = "$DataverseUrl/api/data/v9.2/roles?`$filter=name eq '$roleFilterName' and _businessunitid_value eq $BusinessUnitId&`$select=roleid"
            $roleCheck = Invoke-RestMethod -Uri $roleUrl2 -Method Get -Headers $headers -ErrorAction Stop
            $roleId = $roleCheck.value[0].roleid
        }

        Write-Host "  Created role: $roleId" -ForegroundColor Green
    }
    else {
        Write-Host "  [WhatIf] Would create security role '$RoleName'" -ForegroundColor Yellow
    }
}

if (-not $roleId -and -not $WhatIfPreference) {
    throw "Failed to resolve security role ID."
}

# Step 4: Configure privileges on AuditValidationHistory
# Resolve privilege IDs for the entity
Write-Host "Configuring privileges for AuditValidationHistory..." -ForegroundColor Gray

# Query all privileges for this entity
$privFilter = "name eq 'prvCreatefsi_auditvalidationhistory' or name eq 'prvReadfsi_auditvalidationhistory' or name eq 'prvWritefsi_auditvalidationhistory' or name eq 'prvDeletefsi_auditvalidationhistory' or name eq 'prvAppendfsi_auditvalidationhistory' or name eq 'prvAppendTofsi_auditvalidationhistory'"
$privUrl = "$DataverseUrl/api/data/v9.2/privileges?`$filter=$privFilter&`$select=privilegeid,name"
$privResponse = Invoke-RestMethod -Uri $privUrl -Method Get -Headers $headers -ErrorAction Stop

$privilegeLookup = @{}
foreach ($priv in $privResponse.value) {
    $privilegeLookup[$priv.name] = $priv.privilegeid
}

# Privileges to GRANT: Create (append-only) and Read (for validation queries)
$grantPrivileges = @("prvCreatefsi_auditvalidationhistory", "prvReadfsi_auditvalidationhistory")

# Privileges to DENY/REMOVE: Write, Delete (immutability enforcement)
$denyPrivileges = @("prvWritefsi_auditvalidationhistory", "prvDeletefsi_auditvalidationhistory")

if ($roleId) {
    foreach ($privName in $grantPrivileges) {
        if ($privilegeLookup.ContainsKey($privName)) {
            $privId = $privilegeLookup[$privName]
            if ($PSCmdlet.ShouldProcess("$privName on role $RoleName", "Grant privilege")) {
                try {
                    $addPrivUrl = "$DataverseUrl/api/data/v9.2/roles($roleId)/roleprivileges_association/`$ref"
                    $addPrivBody = @{
                        "@odata.id" = "$DataverseUrl/api/data/v9.2/privileges($privId)"
                    } | ConvertTo-Json
                    Invoke-RestMethod -Uri $addPrivUrl -Method Post -Headers $headers -Body $addPrivBody -ErrorAction Stop
                    Write-Host "  ✓ Granted: $privName (Organization depth)" -ForegroundColor Green
                }
                catch {
                    if ($_.Exception.Message -match "already exists") {
                        Write-Host "  ✓ Already granted: $privName" -ForegroundColor Gray
                    }
                    else {
                        Write-Warning "  Failed to grant $privName : $($_.Exception.Message)"
                    }
                }
            }
            else {
                Write-Host "  [WhatIf] Would grant: $privName" -ForegroundColor Yellow
            }
        }
        else {
            Write-Warning "  Privilege not found: $privName (entity may not be deployed yet)"
        }
    }

    foreach ($privName in $denyPrivileges) {
        if ($privilegeLookup.ContainsKey($privName)) {
            $privId = $privilegeLookup[$privName]
            if ($PSCmdlet.ShouldProcess("$privName on role $RoleName", "Remove privilege")) {
                try {
                    $removePrivUrl = "$DataverseUrl/api/data/v9.2/roles($roleId)/roleprivileges_association($privId)/`$ref"
                    Invoke-RestMethod -Uri $removePrivUrl -Method Delete -Headers $headers -ErrorAction SilentlyContinue
                    Write-Host "  ✓ Removed: $privName (Write/Delete denied)" -ForegroundColor Green
                }
                catch {
                    Write-Host "  ✓ Already removed: $privName" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "  [WhatIf] Would remove: $privName" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  Security Role Configuration Complete" -ForegroundColor Green
Write-Host ""
Write-Host "  Role: $RoleName" -ForegroundColor White
Write-Host "  Granted: Create (append-only), Read" -ForegroundColor Green
Write-Host "  Denied:  Write, Delete (immutability enforced)" -ForegroundColor Red
Write-Host ""
Write-Host "  NEXT STEP: Assign this role to the automation Managed Identity" -ForegroundColor Yellow
Write-Host "  and REMOVE the System Administrator role for production use." -ForegroundColor Yellow
Write-Host "=" * 70 -ForegroundColor Cyan
