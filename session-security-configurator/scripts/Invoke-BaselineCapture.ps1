#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Identity.SignIns, MSAL.PS

<#
.SYNOPSIS
    Captures live Conditional Access session controls as baseline in Dataverse.

.DESCRIPTION
    Operator-initiated script that snapshots current Conditional Access policy
    session control settings and writes them to Dataverse as a SessionBaseline record.

    This baseline serves as the approved configuration that future drift detection
    will compare against. When validation results deviate from the baseline,
    alerting workflows trigger operator notifications.

    Key features:
    - Queries enabled CA policies with session controls via Microsoft Graph
    - Extracts signInFrequency, authenticationStrength, and device compliance settings
    - Normalizes sign-in frequency to minutes for consistent storage
    - Deactivates any existing active baselines for the zone (single active baseline per zone)
    - Writes new SessionBaseline record to Dataverse with fsi_isactive=true
    - Supports both interactive and certificate-based authentication
    - WhatIf mode for safe preview without writing to Dataverse

.PARAMETER Zone
    Governance zone for this baseline. Required.
    Valid values: Zone1 (Personal Productivity), Zone2 (Team Collaboration),
    Zone3 (Enterprise Managed)

.PARAMETER DataverseUrl
    Dataverse environment URL where baseline will be stored. Required.
    Example: https://governance.crm.dynamics.com

.PARAMETER TenantId
    Azure AD tenant ID. Required.

.PARAMETER ClientId
    Azure AD application (client) ID. Required.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Required unless
    -Interactive is specified.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of certificate.
    Useful for manual baseline captures by operators.

.PARAMETER WhatIf
    Preview mode. Shows what would be captured without writing to Dataverse.
    Displays formatted output to console for operator review.

.EXAMPLE
    .\Invoke-BaselineCapture.ps1 `
        -Zone Zone3 `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456"

    Captures Zone3 baseline using certificate authentication and writes to Dataverse.

.EXAMPLE
    .\Invoke-BaselineCapture.ps1 `
        -Zone Zone2 `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -Interactive

    Captures Zone2 baseline using interactive authentication.

.EXAMPLE
    .\Invoke-BaselineCapture.ps1 `
        -Zone Zone3 `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -Interactive `
        -WhatIf

    Preview mode - shows what would be captured without writing to Dataverse.

.OUTPUTS
    JSON object with properties:
    - BaselineId: GUID of created SessionBaseline record
    - Zone: Zone1 | Zone2 | Zone3
    - CapturedOn: ISO 8601 UTC timestamp
    - SignInFrequencyMinutes: Normalized sign-in frequency in minutes
    - AuthStrength: Authentication strength policy name
    - PoliciesCaptured: Count of CA policies with session controls
    - PreviousBaselinesDeactivated: Count of previous active baselines deactivated

.NOTES
    Version: 1.0.0

    Requires:
    - Microsoft.Graph.Identity.SignIns module v2.35.1 or later
    - MSAL.PS module v4.37.0 or later
    - PowerShell 7.0 or later
    - Policy.Read.All permission for Microsoft Graph
    - Dataverse write permissions for fsi_sessionbaselines table

    Baseline management:
    - Only one active baseline per zone at any time
    - Previous active baselines are automatically deactivated (fsi_isactive=false)
    - Deactivated baselines remain in Dataverse for historical audit
    - Use WhatIf to preview before committing

    This script is typically invoked manually by operators after deploying or
    updating Conditional Access policies. It captures the "known good" state
    that automated validation will compare against.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive

)

$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting baseline capture for zone: $Zone"
    Write-Verbose "DataverseUrl: $DataverseUrl"

    # Validate authentication parameters
    if (-not $Interactive -and -not $CertificateThumbprint) {
        throw "CertificateThumbprint is required when -Interactive is not specified."
    }

    # Connect to Microsoft Graph
    Write-Verbose "Connecting to Microsoft Graph..."

    if ($Interactive) {
        Connect-MgGraph -TenantId $TenantId -Scopes "Policy.Read.All" -NoWelcome -ErrorAction Stop
    }
    else {
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop
    }

    Write-Verbose "Connected to Microsoft Graph"

    # Query enabled CA policies with session controls
    Write-Verbose "Querying CA policies with session controls..."

    $policies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop | Where-Object {
        $_.State -eq "enabled" -and
        $_.SessionControls -and
        $_.SessionControls.SignInFrequency
    }

    Write-Verbose "Found $($policies.Count) enabled policy(ies) with session controls"

    if (-not $policies -or $policies.Count -eq 0) {
        throw "No enabled CA policies with session controls found. Cannot capture baseline."
    }

    # Extract session control settings per policy
    $sessionSettings = @()

    foreach ($policy in $policies) {
        $settings = @{
            PolicyId                 = $policy.Id
            PolicyName               = $policy.DisplayName
            SignInFrequencyValue     = $policy.SessionControls.SignInFrequency.Value
            SignInFrequencyType      = $policy.SessionControls.SignInFrequency.Type
            PersistentBrowserMode    = $policy.SessionControls.PersistentBrowser.Mode
            AuthenticationStrengthId = $policy.GrantControls.AuthenticationStrength.Id
            RequireCompliantDevice   = ($policy.GrantControls.BuiltInControls -contains "compliantDevice")
            State                    = $policy.State
        }

        $sessionSettings += $settings

        Write-Verbose "Captured: $($policy.DisplayName)"
    }

    # Normalize sign-in frequency to minutes
    # Zone defaults (used if no matching policies found)
    $zoneDefaults = @{
        "Zone1" = @{ SignInFrequencyMinutes = 480; AuthStrength = "standard" }
        "Zone2" = @{ SignInFrequencyMinutes = 240; AuthStrength = "passwordless" }
        "Zone3" = @{ SignInFrequencyMinutes = 60;  AuthStrength = "phishing-resistant" }
    }

    # Extract actual settings from first policy with session controls
    # (Assumes consistent settings across zone policies)
    $firstPolicy = $sessionSettings | Select-Object -First 1

    $signInFrequencyMinutes = if ($firstPolicy.SignInFrequencyType -eq "hours") {
        $firstPolicy.SignInFrequencyValue * 60
    }
    elseif ($firstPolicy.SignInFrequencyType -eq "days") {
        $firstPolicy.SignInFrequencyValue * 60 * 24
    }
    else {
        # Assume minutes
        $firstPolicy.SignInFrequencyValue
    }

    # Get auth strength (use first policy with auth strength, or default)
    $authStrength = if ($firstPolicy.AuthenticationStrengthId) {
        # Query auth strength name
        try {
            $authStrengthPolicy = Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy -AuthenticationStrengthPolicyId $firstPolicy.AuthenticationStrengthId -ErrorAction Stop
            $authStrengthPolicy.DisplayName
        }
        catch {
            Write-Warning "Could not resolve authentication strength ID: $($firstPolicy.AuthenticationStrengthId)"
            $zoneDefaults[$Zone].AuthStrength
        }
    }
    else {
        $zoneDefaults[$Zone].AuthStrength
    }

    $requireCompliantDevice = $firstPolicy.RequireCompliantDevice -eq $true

    # Capture timestamp
    $capturedOn = Get-Date -AsUTC -Format "o"

    # Build baseline name
    $baselineName = "$Zone-$capturedOn"

    # If WhatIf mode, display preview and exit
    if ($WhatIfPreference) {
        Write-Host "`n═════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  BASELINE CAPTURE PREVIEW (WhatIf Mode)" -ForegroundColor Cyan
        Write-Host "═════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Zone:                      $Zone" -ForegroundColor Cyan
        Write-Host "Baseline Name:             $baselineName" -ForegroundColor Cyan
        Write-Host "Sign-In Frequency:         $signInFrequencyMinutes minutes" -ForegroundColor Cyan
        Write-Host "Authentication Strength:   $authStrength" -ForegroundColor Cyan
        Write-Host "Require Compliant Device:  $requireCompliantDevice" -ForegroundColor Cyan
        Write-Host "Policies Captured:         $($sessionSettings.Count)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Policies:" -ForegroundColor Yellow
        foreach ($setting in $sessionSettings) {
            Write-Host "  - $($setting.PolicyName)" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "═════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "No changes written (WhatIf mode)" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Map zone to option set value
    $zoneOptionSetMap = @{
        "Zone1" = 100000001
        "Zone2" = 100000002
        "Zone3" = 100000003
    }
    $zoneOptionSetValue = $zoneOptionSetMap[$Zone]

    # Acquire Dataverse token
    Write-Verbose "Acquiring Dataverse token..."

    Import-Module MSAL.PS -ErrorAction Stop

    if ($Interactive) {
        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -TenantId $TenantId `
            -Scopes "$($DataverseUrl.TrimEnd('/'))/.default" `
            -Interactive `
            -ErrorAction Stop
    }
    else {
        $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -ClientCertificate $cert `
            -TenantId $TenantId `
            -Scopes "$($DataverseUrl.TrimEnd('/'))/.default" `
            -ErrorAction Stop
    }

    $dataverseToken = $tokenResult.AccessToken
    Write-Verbose "Dataverse token acquired"

    # Prepare headers for Dataverse API calls
    $headers = @{
        "Authorization"    = "Bearer $dataverseToken"
        "Accept"           = "application/json"
        "Content-Type"     = "application/json; charset=utf-8"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        "Prefer"           = "return=representation"
    }

    # Deactivate existing active baselines for this zone
    Write-Verbose "Querying existing active baselines for $Zone..."

    $filterQuery = "fsi_zone eq $zoneOptionSetValue and fsi_isactive eq true"
    $queryUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_sessionbaselines?`$filter=$filterQuery&`$select=fsi_sessionbaselineid,fsi_name"

    $existingBaselines = Invoke-RestMethod `
        -Uri $queryUrl `
        -Method Get `
        -Headers $headers `
        -ErrorAction Stop

    $deactivatedCount = 0

    if ($existingBaselines.value -and $existingBaselines.value.Count -gt 0) {
        Write-Verbose "Found $($existingBaselines.value.Count) existing active baseline(s). Deactivating..."

        foreach ($baseline in $existingBaselines.value) {
            $baselineId = $baseline.fsi_sessionbaselineid
            $patchUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_sessionbaselines($baselineId)"

            $patchBody = @{
                fsi_isactive = $false
            } | ConvertTo-Json

            Invoke-RestMethod `
                -Uri $patchUrl `
                -Method Patch `
                -Headers $headers `
                -Body $patchBody `
                -ErrorAction Stop | Out-Null

            Write-Verbose "Deactivated baseline: $($baseline.fsi_name)"
            $deactivatedCount++
        }
    }
    else {
        Write-Verbose "No existing active baselines found for $Zone"
    }

    # Create new SessionBaseline record
    Write-Verbose "Creating new SessionBaseline record..."

    $createUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_sessionbaselines"

    $baselineRecord = @{
        fsi_name                   = $baselineName
        fsi_zone                   = $zoneOptionSetValue
        fsi_signinfrequencyminutes = $signInFrequencyMinutes
        fsi_authstrength           = $authStrength
        fsi_requirecompliantdevice = $requireCompliantDevice
        fsi_pimmaxactivationhours  = $null
        fsi_pimrequireapproval     = $null
        fsi_pimrequireauthcontext  = $null
        fsi_isactive               = $true
        fsi_capturedon             = $capturedOn
        fsi_rawjson                = ($sessionSettings | ConvertTo-Json -Depth 5 -Compress)
    } | ConvertTo-Json

    $createResponse = Invoke-RestMethod `
        -Uri $createUrl `
        -Method Post `
        -Headers $headers `
        -Body $baselineRecord `
        -ErrorAction Stop

    # Extract baseline ID from response
    $baselineId = $createResponse.fsi_sessionbaselineid

    Write-Verbose "SessionBaseline created with ID: $baselineId"

    # Build output object
    $result = [PSCustomObject]@{
        BaselineId                   = $baselineId
        Zone                         = $Zone
        CapturedOn                   = $capturedOn
        SignInFrequencyMinutes       = $signInFrequencyMinutes
        AuthStrength                 = $authStrength
        RequireCompliantDevice       = $requireCompliantDevice
        PoliciesCaptured             = $sessionSettings.Count
        PreviousBaselinesDeactivated = $deactivatedCount
    }

    # Output JSON to pipeline
    $result | ConvertTo-Json -Depth 5
}
catch {
    Write-Error "Baseline capture failed: $($_.Exception.Message)"
    throw
}
finally {
    # Disconnect from Graph
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # Ignore disconnect errors
    }
}
