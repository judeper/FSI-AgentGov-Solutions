#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.17.0' }

<#
.SYNOPSIS
    Audit cross-tenant access baseline before activating governance flows.

.DESCRIPTION
    Scans all three governance layers (Power Platform Tenant Isolation, Entra CTA,
    Guest Users) to establish baseline state. Run this script and populate
    fsi_approvedexternaltenant for all identified tenants BEFORE setting
    fsi_CTSG_IsCrossTenantGovernanceEnabled to "true". Activating flows against an empty
    registry generates false positives for every existing cross-tenant relationship.

    Authentication: System-Assigned Managed Identity (MI-CrossTenantReadOnly) only.
    Run from: Azure Automation Runbook or local PowerShell with Az module.

.PARAMETER DataverseEnvironmentUrl
    Target Dataverse environment URL (e.g., https://org.crm.dynamics.com)

.PARAMETER OutputPath
    File path for the baseline JSON export (default: .\ctsg-baseline-{timestamp}.json)

.EXAMPLE
    .\Deploy-CrossTenantBaseline.ps1 -DataverseEnvironmentUrl "https://myorg.crm.dynamics.com"

.EXAMPLE
    .\Deploy-CrossTenantBaseline.ps1 -DataverseEnvironmentUrl "https://myorg.crm.dynamics.com" -OutputPath ".\baseline.json"

.NOTES
    FSI Agent Governance Framework - Cross-Tenant External Sharing Governance
    Run BEFORE enabling governance flows. See DELIVERY-CHECKLIST.md for API schema confirmation steps.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseEnvironmentUrl,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if (-not $OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = ".\ctsg-baseline-$timestamp.json"
}

# --- Authentication ---
Connect-AzAccount -Identity | Out-Null

# Az.Accounts >= 2.17 returns SecureString by default; force SecureString and convert.
$graphResp  = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -AsSecureString
$ppResp     = Get-AzAccessToken -ResourceUrl "https://service.powerapps.com/" -AsSecureString
$graphToken = $graphResp.Token | ConvertFrom-SecureString -AsPlainText
$ppToken    = $ppResp.Token    | ConvertFrom-SecureString -AsPlainText

$graphHeaders = @{
    Authorization    = "Bearer $graphToken"
    "Content-Type"   = "application/json"
    "OData-Version"  = "4.0"
}
$ppHeaders = @{
    Authorization    = "Bearer $ppToken"
    "Content-Type"   = "application/json"
}

Write-Host "`n=== CROSS-TENANT GOVERNANCE BASELINE ===" -ForegroundColor Cyan
Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')" -ForegroundColor Cyan
Write-Host "Target:    $DataverseEnvironmentUrl" -ForegroundColor Cyan
Write-Warning "Authentication: System-Assigned Managed Identity (MI-CrossTenantReadOnly)"

$deliveryChecklistItems = [System.Collections.ArrayList]::new()
$baselineTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# =============================================================================
# LAYER 1: Power Platform Tenant Isolation
# =============================================================================
Write-Host "`n--- Layer 1: Power Platform Tenant Isolation ---" -ForegroundColor Yellow
Write-Warning "DELIVERY-CHECKLIST: Confirm API endpoint and response schema before activating Flow 1."
Write-Warning "Validate tenant isolation with Get-PowerAppTenantIsolationPolicy first; confirm any automated response shape against the delivery checklist."

$layer1Result = @{
    IsolationEnabled = $null
    AllowListCount   = 0
    AllowListEntries = @()
    ApiConfirmed     = $false
    Errors           = @()
}

# 1a. Tenant isolation status
# NOTE: Tenant isolation is exposed via the BAP (Business Application Platform)
# admin API, not the public api.powerplatform.com endpoint surface. The accurate
# endpoints are:
#   GET /providers/Microsoft.BusinessAppPlatform/scopes/admin/tenantSettings
#       ?api-version=2020-10-01
#   GET /providers/Microsoft.BusinessAppPlatform/scopes/admin/crossTenantConnectionAllowPolicy
#       ?api-version=2020-10-01
# The BAP token audience is https://service.powerapps.com/. Re-authenticate the
# managed identity against that resource and replace $ppHeaders below before
# enabling Flow 1 in production. Property name on the policy object is
# 'isolationEnabled' (not 'tenantIsolationEnabled') — confirm in your tenant.
try {
    $tenantSettings = Invoke-RestMethod `
        -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/tenantSettings?api-version=2020-10-01" `
        -Headers $ppHeaders `
        -Method Get

    if ($null -eq $tenantSettings.isolationEnabled -and $null -eq $tenantSettings.tenantIsolationEnabled) {
        Write-Warning "SCHEMA MISMATCH: neither 'isolationEnabled' nor 'tenantIsolationEnabled' found in BAP response."
        Write-Warning "Inspect the actual response and update the property name in DELIVERY-CHECKLIST.md."
        Write-Host "  Raw response properties: $($tenantSettings.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
        [void]$deliveryChecklistItems.Add("Layer1-TenantSettings: Confirm property name for isolation flag. Found: $($tenantSettings.PSObject.Properties.Name -join ', ')")
    } else {
        $isolationFlag = if ($null -ne $tenantSettings.isolationEnabled) { $tenantSettings.isolationEnabled } else { $tenantSettings.tenantIsolationEnabled }
        $layer1Result.IsolationEnabled = $isolationFlag
        $layer1Result.ApiConfirmed = $true
        Write-Host "  Tenant isolation enabled: $isolationFlag" `
            -ForegroundColor $(if ($isolationFlag) { "Green" } else { "Red" })
        if (-not $isolationFlag) {
            Write-Warning "ACTION REQUIRED: Tenant isolation is OFF. Enable in PPAC before activating Flow 1."
            [void]$deliveryChecklistItems.Add("Layer1-IsolationOff: Enable tenant isolation in Power Platform Admin Center")
        }
    }
} catch {
    $layer1Result.Errors += "TenantSettings API failed: $($_.Exception.Message)"
    Write-Warning "API 1 failed: $($_.Exception.Message)"
    Write-Warning "Validate BAP endpoint and audience https://service.powerapps.com/ for the managed identity."
    [void]$deliveryChecklistItems.Add("Layer1-TenantSettingsAPI: Validate BAP endpoint accessibility for Managed Identity (audience https://service.powerapps.com/)")
}

# 1b. Cross-tenant allow-list policies
try {
    $allowList = Invoke-RestMethod `
        -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/crossTenantConnectionAllowPolicy?api-version=2020-10-01" `
        -Headers $ppHeaders `
        -Method Get

    if ($null -eq $allowList.value) {
        Write-Warning "SCHEMA MISMATCH: 'value' array not found in API 2 response."
        Write-Warning "Inspect and document confirmed structure in DELIVERY-CHECKLIST.md."
        Write-Host "  Raw response properties: $($allowList.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
        [void]$deliveryChecklistItems.Add("Layer1-CrossTenantPolicies: Confirm response schema. Found: $($allowList.PSObject.Properties.Name -join ', ')")
    } else {
        $layer1Result.AllowListCount = $allowList.value.Count
        $layer1Result.AllowListEntries = $allowList.value | ForEach-Object {
            @{
                TenantId  = $_.tenantId
                Direction = $_.direction
                TenantName = if ($_.tenantName) { $_.tenantName } else { "Unknown" }
            }
        }
        Write-Host "  Allow-list entries: $($allowList.value.Count)"
        if ($allowList.value.Count -gt 0) {
            Write-Warning "ACTION REQUIRED: Register all allow-list tenants in fsi_approvedexternaltenant."
            $allowList.value | Select-Object tenantId, direction | Format-Table -AutoSize
        } else {
            Write-Host "  No allow-list entries found (isolation may block all cross-tenant connectors)." -ForegroundColor Gray
        }
    }
} catch {
    $layer1Result.Errors += "CrossTenantPolicies API failed: $($_.Exception.Message)"
    Write-Warning "API 2 failed: $($_.Exception.Message)"
    Write-Warning "Validate tenant isolation policy with Get-PowerAppTenantIsolationPolicy and PPAC; confirm any automation endpoint before use"
    [void]$deliveryChecklistItems.Add("Layer1-CrossTenantPoliciesAPI: Validate endpoint accessibility for Managed Identity")
}

# =============================================================================
# LAYER 2: Entra Cross-Tenant Access Settings
# =============================================================================
Write-Host "`n--- Layer 2: Entra Cross-Tenant Access Settings ---" -ForegroundColor Yellow
Write-Warning "DELIVERY-CHECKLIST: Confirm Graph API permissions: Policy.Read.All required."

$layer2Result = @{
    DefaultPolicy    = $null
    PartnerCount     = 0
    PartnerEntries   = @()
    Errors           = @()
}

# 2a. Default cross-tenant access policy
try {
    $defaultPolicy = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy" `
        -Headers $graphHeaders `
        -Method Get

    $layer2Result.DefaultPolicy = @{
        AllowedCloudEndpoints = $defaultPolicy.allowedCloudEndpoints
        IsServiceDefault      = $defaultPolicy.isServiceDefault
    }
    Write-Host "  Default CTA policy retrieved successfully." -ForegroundColor Green

    # 2a-ii. Default inbound/outbound settings
    try {
        $defaultConfig = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default" `
            -Headers $graphHeaders `
            -Method Get

        $inboundTrust = $defaultConfig.inboundTrust
        $b2bInbound = $defaultConfig.b2bCollaborationInbound
        $b2bOutbound = $defaultConfig.b2bCollaborationOutbound
        $b2bDirectInbound = $defaultConfig.b2bDirectConnectInbound
        $b2bDirectOutbound = $defaultConfig.b2bDirectConnectOutbound

        $layer2Result.DefaultPolicy.InboundTrust = $inboundTrust
        $layer2Result.DefaultPolicy.B2BCollaborationInbound = $b2bInbound
        $layer2Result.DefaultPolicy.B2BCollaborationOutbound = $b2bOutbound
        $layer2Result.DefaultPolicy.B2BDirectConnectInbound = $b2bDirectInbound
        $layer2Result.DefaultPolicy.B2BDirectConnectOutbound = $b2bDirectOutbound

        Write-Host "  Default inbound trust: $(if ($inboundTrust) { 'Configured' } else { 'Not configured' })"
        Write-Host "  B2B collaboration inbound:  $(if ($b2bInbound.accessType) { $b2bInbound.accessType } else { 'Default' })"
        Write-Host "  B2B collaboration outbound: $(if ($b2bOutbound.accessType) { $b2bOutbound.accessType } else { 'Default' })"
        Write-Host "  B2B direct connect inbound:  $(if ($b2bDirectInbound.accessType) { $b2bDirectInbound.accessType } else { 'Default' })"
        Write-Host "  B2B direct connect outbound: $(if ($b2bDirectOutbound.accessType) { $b2bDirectOutbound.accessType } else { 'Default' })"
    } catch {
        $layer2Result.Errors += "Default CTA config API failed: $($_.Exception.Message)"
        Write-Warning "Default config retrieval failed: $($_.Exception.Message)"
    }
} catch {
    $layer2Result.Errors += "Default CTA policy API failed: $($_.Exception.Message)"
    Write-Warning "Default CTA policy API failed: $($_.Exception.Message)"
    [void]$deliveryChecklistItems.Add("Layer2-DefaultPolicy: Grant Policy.Read.All to Managed Identity")
}

# 2b. Partner-specific cross-tenant access policies
try {
    $partnerUrl = "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners"
    $allPartners = [System.Collections.ArrayList]::new()

    while ($partnerUrl) {
        $partnerResponse = Invoke-RestMethod `
            -Uri $partnerUrl `
            -Headers $graphHeaders `
            -Method Get

        foreach ($partner in $partnerResponse.value) {
            [void]$allPartners.Add(@{
                TenantId                   = $partner.tenantId
                IsServiceProvider          = $partner.isServiceProvider
                IsInMultiTenantOrganization = $partner.isInMultiTenantOrganization
                B2BCollaborationInbound    = $partner.b2bCollaborationInbound
                B2BCollaborationOutbound   = $partner.b2bCollaborationOutbound
                B2BDirectConnectInbound    = $partner.b2bDirectConnectInbound
                B2BDirectConnectOutbound   = $partner.b2bDirectConnectOutbound
                InboundTrust               = $partner.inboundTrust
                AutomaticUserConsentSettings = $partner.automaticUserConsentSettings
            })
        }
        $partnerUrl = $partnerResponse.'@odata.nextLink'
    }

    $layer2Result.PartnerCount = $allPartners.Count
    $layer2Result.PartnerEntries = $allPartners.ToArray()

    Write-Host "  Partner CTA policies: $($allPartners.Count)"
    if ($allPartners.Count -gt 0) {
        Write-Warning "ACTION REQUIRED: Register all partner tenants in fsi_approvedexternaltenant."
        $allPartners | ForEach-Object {
            Write-Host "    TenantId: $($_.TenantId) | ServiceProvider: $($_.IsServiceProvider)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  No partner-specific CTA policies found (default policy applies to all)." -ForegroundColor Gray
    }
} catch {
    $layer2Result.Errors += "Partner CTA API failed: $($_.Exception.Message)"
    Write-Warning "Partner CTA API failed: $($_.Exception.Message)"
    [void]$deliveryChecklistItems.Add("Layer2-PartnerPolicies: Validate Graph API partner endpoint accessibility")
}

# =============================================================================
# LAYER 3: Guest Users
# =============================================================================
Write-Host "`n--- Layer 3: Guest Users ---" -ForegroundColor Yellow
Write-Warning "DELIVERY-CHECKLIST: Confirm Graph API permissions: User.Read.All required."

$layer3Result = @{
    GuestUserCount      = 0
    GuestUsers          = @()
    UniqueTenantIds     = @()
    CreationTypeBreakdown = @{}
    Errors              = @()
}

$guestHeaders = @{
    Authorization      = "Bearer $graphToken"
    "Content-Type"     = "application/json"
    "ConsistencyLevel" = "eventual"
}

# Three-method fallback chain for guest user enumeration
$guestUsers = [System.Collections.ArrayList]::new()
$guestRetrieved = $false

# Method 1: Filter with $count and ConsistencyLevel: eventual
if (-not $guestRetrieved) {
    try {
        Write-Host "  Method 1: Filtered query with ConsistencyLevel header..." -ForegroundColor Gray
        $guestUrl = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,mail,userPrincipalName,creationType,externalUserState,createdDateTime&`$count=true&`$top=999"

        while ($guestUrl) {
            $guestResponse = Invoke-RestMethod `
                -Uri $guestUrl `
                -Headers $guestHeaders `
                -Method Get

            foreach ($guest in $guestResponse.value) {
                [void]$guestUsers.Add($guest)
            }
            $guestUrl = $guestResponse.'@odata.nextLink'
        }
        $guestRetrieved = $true
        Write-Host "  Method 1 succeeded: $($guestUsers.Count) guest users." -ForegroundColor Green
    } catch {
        Write-Warning "Method 1 failed: $($_.Exception.Message)"
    }
}

# Method 2: Fallback without $count
if (-not $guestRetrieved) {
    try {
        Write-Host "  Method 2: Filtered query without `$count..." -ForegroundColor Gray
        $guestUrl = "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,mail,userPrincipalName,creationType,externalUserState,createdDateTime&`$top=999"

        while ($guestUrl) {
            $guestResponse = Invoke-RestMethod `
                -Uri $guestUrl `
                -Headers $graphHeaders `
                -Method Get

            foreach ($guest in $guestResponse.value) {
                [void]$guestUsers.Add($guest)
            }
            $guestUrl = $guestResponse.'@odata.nextLink'
        }
        $guestRetrieved = $true
        Write-Host "  Method 2 succeeded: $($guestUsers.Count) guest users." -ForegroundColor Green
    } catch {
        Write-Warning "Method 2 failed: $($_.Exception.Message)"
    }
}

# Method 3: Retrieve all users and filter client-side
if (-not $guestRetrieved) {
    try {
        Write-Host "  Method 3: Full user list with client-side filter..." -ForegroundColor Gray
        $allUserUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,mail,userPrincipalName,userType,creationType,externalUserState,createdDateTime&`$top=999"

        while ($allUserUrl) {
            $allUserResponse = Invoke-RestMethod `
                -Uri $allUserUrl `
                -Headers $graphHeaders `
                -Method Get

            foreach ($user in $allUserResponse.value) {
                if ($user.userType -eq "Guest") {
                    [void]$guestUsers.Add($user)
                }
            }
            $allUserUrl = $allUserResponse.'@odata.nextLink'
        }
        $guestRetrieved = $true
        Write-Host "  Method 3 succeeded: $($guestUsers.Count) guest users." -ForegroundColor Green
    } catch {
        $layer3Result.Errors += "All guest user retrieval methods failed: $($_.Exception.Message)"
        Write-Warning "All three guest retrieval methods failed: $($_.Exception.Message)"
        [void]$deliveryChecklistItems.Add("Layer3-GuestUsers: Grant User.Read.All to Managed Identity")
    }
}

if ($guestRetrieved) {
    $layer3Result.GuestUserCount = $guestUsers.Count

    # Extract unique tenant IDs from UPNs (format: user_externaldomain#EXT#@tenant.onmicrosoft.com)
    $tenantDomains = @{}
    foreach ($guest in $guestUsers) {
        $upn = $guest.userPrincipalName
        # Anchor on the LAST underscore before '#EXT#' so UPNs like
        # 'john_doe_example.com#EXT#@tenant.onmicrosoft.com' resolve to
        # 'example.com' (the domain), not 'doe_example.com'.
        if ($upn -match '^.+_([^_#]+)#EXT#@') {
            $externalDomain = $Matches[1]
            if (-not $tenantDomains.ContainsKey($externalDomain)) {
                $tenantDomains[$externalDomain] = 0
            }
            $tenantDomains[$externalDomain]++
        }
    }
    $layer3Result.UniqueTenantIds = $tenantDomains.Keys | Sort-Object

    # CreationType breakdown
    $creationTypes = @{}
    foreach ($guest in $guestUsers) {
        $ct = if ($guest.creationType) { $guest.creationType } else { "Unknown" }
        if (-not $creationTypes.ContainsKey($ct)) {
            $creationTypes[$ct] = 0
        }
        $creationTypes[$ct]++
    }
    $layer3Result.CreationTypeBreakdown = $creationTypes

    # Summarize guest users per entry (limit stored detail for large tenants)
    $layer3Result.GuestUsers = $guestUsers | Select-Object id, displayName, mail, userPrincipalName, creationType, externalUserState, createdDateTime

    Write-Host "  Total guest users: $($guestUsers.Count)"
    Write-Host "  Unique external domains: $($tenantDomains.Count)"
    if ($tenantDomains.Count -gt 0) {
        Write-Warning "ACTION REQUIRED: Register external domains in fsi_approvedexternaltenant."
        $tenantDomains.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object {
            Write-Host "    $($_.Key): $($_.Value) guest(s)" -ForegroundColor Gray
        }
        if ($tenantDomains.Count -gt 20) {
            Write-Host "    ... and $($tenantDomains.Count - 20) more domains (see baseline JSON)" -ForegroundColor Gray
        }
    }

    Write-Host "  Creation type breakdown:"
    foreach ($entry in $creationTypes.GetEnumerator() | Sort-Object Value -Descending) {
        Write-Host "    $($entry.Key): $($entry.Value)" -ForegroundColor Gray
    }
}

# =============================================================================
# Deduplicate all discovered tenants across layers
# =============================================================================
Write-Host "`n--- Cross-Layer Tenant Summary ---" -ForegroundColor Yellow

$allDiscoveredTenants = [System.Collections.ArrayList]::new()

# From Layer 1 allow-list
foreach ($entry in $layer1Result.AllowListEntries) {
    [void]$allDiscoveredTenants.Add(@{
        Source   = "PowerPlatformAllowList"
        TenantId = $entry.TenantId
        Name     = $entry.TenantName
    })
}

# From Layer 2 partner CTA
foreach ($entry in $layer2Result.PartnerEntries) {
    [void]$allDiscoveredTenants.Add(@{
        Source   = "EntraCTAPartner"
        TenantId = $entry.TenantId
        Name     = "CTA Partner"
    })
}

# From Layer 3 guest user domains
foreach ($domain in $layer3Result.UniqueTenantIds) {
    [void]$allDiscoveredTenants.Add(@{
        Source   = "GuestUserDomain"
        TenantId = $null
        Name     = $domain
    })
}

$uniqueSources = $allDiscoveredTenants | Group-Object { $_.TenantId ?? $_.Name } | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "  Total tenant references discovered: $($allDiscoveredTenants.Count)"
Write-Host "  Unique tenant/domain identifiers:   $uniqueSources"

if ($allDiscoveredTenants.Count -gt 0) {
    Write-Warning "Register ALL discovered tenants in fsi_approvedexternaltenant before enabling governance flows."
    [void]$deliveryChecklistItems.Add("Pre-Activation: Register $($allDiscoveredTenants.Count) discovered tenant references in fsi_approvedexternaltenant")
}

# =============================================================================
# Delivery Checklist Items (always include baseline items)
# =============================================================================
$standardChecklistItems = @(
    "Confirm Get-PowerAppTenantIsolationPolicy output property name for isolation state"
    "Confirm tenant isolation allow-list/rules response schema"
    "Confirm Graph API partner CTA endpoint response schema"
    "Verify Managed Identity has Policy.Read.All and User.Read.All Graph permissions"
    "Verify Managed Identity has Power Platform governance reader permissions"
    "Populate fsi_approvedexternaltenant with all discovered tenants BEFORE enabling flows"
    "Set fsi_CTSG_IsCrossTenantGovernanceEnabled environment variable to 'true' only after baseline review"
    "Confirm OptionSet integer values match deployed solution XML for all status/severity fields"
)

foreach ($item in $standardChecklistItems) {
    if ($item -notin $deliveryChecklistItems) {
        [void]$deliveryChecklistItems.Add($item)
    }
}

# =============================================================================
# Export Baseline JSON
# =============================================================================
Write-Host "`n--- Exporting Baseline JSON ---" -ForegroundColor Yellow

$baseline = @{
    MetaData = @{
        GeneratedAt          = $baselineTimestamp
        ScriptVersion        = "1.0.0"
        DataverseEnvironment = $DataverseEnvironmentUrl
        Authentication       = "System-Assigned Managed Identity (MI-CrossTenantReadOnly)"
    }
    Layer1_PowerPlatformTenantIsolation = @{
        IsolationEnabled = $layer1Result.IsolationEnabled
        AllowListCount   = $layer1Result.AllowListCount
        AllowListEntries = $layer1Result.AllowListEntries
        ApiConfirmed     = $layer1Result.ApiConfirmed
        Errors           = $layer1Result.Errors
    }
    Layer2_EntraCrossTenantAccess = @{
        DefaultPolicy  = $layer2Result.DefaultPolicy
        PartnerCount   = $layer2Result.PartnerCount
        PartnerEntries = $layer2Result.PartnerEntries
        Errors         = $layer2Result.Errors
    }
    Layer3_GuestUsers = @{
        GuestUserCount        = $layer3Result.GuestUserCount
        UniqueExternalDomains = $layer3Result.UniqueTenantIds
        CreationTypeBreakdown = $layer3Result.CreationTypeBreakdown
        GuestUsers            = $layer3Result.GuestUsers
        Errors                = $layer3Result.Errors
    }
    CrossLayerSummary = @{
        TotalTenantReferences       = $allDiscoveredTenants.Count
        UniqueIdentifiers           = $uniqueSources
        DiscoveredTenants           = $allDiscoveredTenants.ToArray()
    }
    DeliveryChecklistItems = $deliveryChecklistItems.ToArray()
}

$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$baseline | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host "  Baseline exported: $OutputPath" -ForegroundColor Green

# --- Final Summary ---
Write-Host "`n=== BASELINE SUMMARY ===" -ForegroundColor Cyan
Write-Host "  Layer 1 - PP Isolation:   $(if ($layer1Result.IsolationEnabled) { 'ENABLED' } elseif ($null -eq $layer1Result.IsolationEnabled) { 'UNKNOWN' } else { 'DISABLED' })" `
    -ForegroundColor $(if ($layer1Result.IsolationEnabled) { "Green" } else { "Red" })
Write-Host "  Layer 1 - Allow-list:     $($layer1Result.AllowListCount) entries"
Write-Host "  Layer 2 - CTA Partners:   $($layer2Result.PartnerCount) entries"
Write-Host "  Layer 3 - Guest Users:    $($layer3Result.GuestUserCount) users from $($layer3Result.UniqueTenantIds.Count) domains"
Write-Host "  Delivery Checklist:       $($deliveryChecklistItems.Count) items" -ForegroundColor Yellow
Write-Host ""
Write-Warning "NEXT STEPS:"
Write-Warning "  1. Review baseline JSON: $OutputPath"
Write-Warning "  2. Register all discovered tenants in fsi_approvedexternaltenant"
Write-Warning "  3. Confirm API schemas in DELIVERY-CHECKLIST.md"
Write-Warning "  4. Set fsi_CTSG_IsCrossTenantGovernanceEnabled to 'true' ONLY after completing steps 1-3"
Write-Host "`n  Baseline audit: COMPLETE" -ForegroundColor Green
