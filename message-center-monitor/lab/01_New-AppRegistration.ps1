#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications
<#
.SYNOPSIS
    Creates or rotates the message-center-monitor lab app registration with admin consent.

.DESCRIPTION
    Idempotent: if an app reg with the configured display name exists, it is
    reused. A new client secret is created only when no existing credential is
    valid for at least 30 days. Required permissions are resolved DYNAMICALLY
    from the Microsoft Graph and Dataverse service principals (no hardcoded
    GUIDs), then admin-consented. After consent, oauth2PermissionGrants and
    appRoleAssignments are polled to confirm the grants landed before returning.

.PARAMETER ConfigPath
    Path to lab-config.json. Defaults to ./lab-config.json relative to this script.

.PARAMETER MinSecretValidityDays
    Minimum remaining validity of an existing client secret. If the existing
    secret has fewer than this many days left, a new secret is generated and
    pushed to Key Vault on the next 02_New-KeyVault.ps1 run. Default: 30.

.PARAMETER ConsentPollSeconds
    Total time to wait for admin consent to propagate. Default: 60.

.OUTPUTS
    Writes appRegistration block of lab-state.json. The new client secret value
    is returned via $env:MCM_LAB_LAST_SECRET for the immediate next step
    (02_New-KeyVault.ps1) to pick up. The secret value is NEVER logged.

.NOTES
    Lab dry-run step 1 of 7. Requires Application Administrator + Cloud
    Application Administrator (or Global Administrator) for admin consent.
    Solution: message-center-monitor v2.5.0+
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab provisioning script run interactively by tenant admin. Operator pastes a temporary secret for one-time setup; not invoked in production.'
)]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [int]    $MinSecretValidityDays = 30,
    [Parameter()] [int]    $ConsentPollSeconds    = 60,
    [Parameter()] [switch] $ForceRotate,
    [Parameter()] [switch] $AllowProduction
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '01-app-reg'

$cfg = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
$state = Get-LabState
if (-not $state.tenantId) { $state | Add-Member -NotePropertyName tenantId -NotePropertyValue $cfg.tenant.tenantId -Force }

# Well-known service principal app IDs (these are tenant-invariant constants
# defined by Microsoft, NOT object IDs - resolution to per-tenant SP object IDs
# happens below).
$GraphAppId     = '00000003-0000-0000-c000-000000000000'  # Microsoft Graph
$DataverseAppId = '00000007-0000-0000-c000-000000000000'  # Common Data Service / Dataverse

Write-LabLog -Level Info -Message "Connecting to Microsoft Graph (tenant=$($cfg.tenant.tenantId))..."
# Idempotency: if Mg context already exists (e.g. caller pre-authenticated via
# Connect-MgGraph -UseDeviceCode, or via az CLI token forwarded with
# Connect-MgGraph -AccessToken), reuse it as long as it covers the scopes we
# need. This makes the script reusable in CI/automation contexts where the
# default WAM-interactive flow is unavailable.
$requiredScopes = @(
    'Application.ReadWrite.All'
    'AppRoleAssignment.ReadWrite.All'
    'DelegatedPermissionGrant.ReadWrite.All'
    'Directory.Read.All'
)
$existingCtx = Get-MgContext
$needConnect = $true
if ($existingCtx -and $existingCtx.TenantId -eq $cfg.tenant.tenantId) {
    # Treat broader scopes as covering their narrower equivalents. az CLI's
    # default first-party app grants Directory.AccessAsUser.All which subsumes
    # Directory.Read.All for the calls this script makes (Get-MgServicePrincipal
    # / app reg CRUD); accept it as a substitute.
    $scopeAliases = @{
        'Directory.Read.All' = @('Directory.AccessAsUser.All','Directory.ReadWrite.All')
    }
    $missing = @()
    foreach ($req in $requiredScopes) {
        if ($req -in $existingCtx.Scopes) { continue }
        $alts = $scopeAliases[$req]
        if ($alts -and ($alts | Where-Object { $_ -in $existingCtx.Scopes })) { continue }
        $missing += $req
    }
    if ($missing.Count -eq 0) {
        Write-LabLog -Level Info -Message "  Reusing existing Mg context ($($existingCtx.Account))"
        $needConnect = $false
    } else {
        Write-LabLog -Level Info -Message "  Existing Mg context missing scopes: $($missing -join ', '). Re-connecting."
    }
}
if ($needConnect) {
    Connect-MgGraph -Scopes $requiredScopes -TenantId $cfg.tenant.tenantId -NoWelcome -ErrorAction Stop | Out-Null
}

try {
    # --- 1. Resolve required permissions DYNAMICALLY (no hardcoded GUIDs) ----
    Write-LabLog -Level Info -Message "Resolving Graph and Dataverse service principals..."
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'" -ErrorAction Stop
    if (-not $graphSp) {
        Write-LabLog -Level Error -Message "Microsoft Graph service principal not found in tenant. This is unexpected." -Throw
    }
    $dvSp = Get-MgServicePrincipal -Filter "appId eq '$DataverseAppId'" -ErrorAction Stop
    if (-not $dvSp) {
        Write-LabLog -Level Error -Message "Dataverse / Common Data Service service principal not found. Provision a Power Platform environment first." -Throw
    }

    $graphAppRole = $graphSp.AppRoles | Where-Object { $_.Value -eq 'ServiceMessage.Read.All' -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $graphAppRole) {
        Write-LabLog -Level Error -Message "AppRole 'ServiceMessage.Read.All' not found on Microsoft Graph SP." -Throw
    }
    $dvScope = $dvSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq 'user_impersonation' }
    if (-not $dvScope) {
        Write-LabLog -Level Error -Message "Delegated scope 'user_impersonation' not found on Dataverse SP." -Throw
    }

    # --- 2. Find or create app registration ----------------------------------
    $appName = $cfg.appRegistration.displayName
    $existingApp = Get-MgApplication -Filter "displayName eq '$appName'" -ErrorAction Stop
    if ($existingApp.Count -gt 1) {
        Write-LabLog -Level Error -Message "Multiple app registrations match '$appName'. Resolve manually before re-running." -Throw
    }

    if ($existingApp) {
        $app = $existingApp | Select-Object -First 1
        Write-LabLog -Level Info -Message "App reg '$appName' already exists (objectId=$($app.Id), appId=$($app.AppId)). Reusing."
        $appCreated = $false
    } else {
        Write-LabLog -Level Info -Message "Creating app reg '$appName'..."
        if ($PSCmdlet.ShouldProcess($appName, 'New-MgApplication')) {
            $appBody = @{
                displayName            = $appName
                signInAudience         = 'AzureADMyOrg'
                requiredResourceAccess = @(
                    @{
                        resourceAppId  = $GraphAppId
                        resourceAccess = @(@{ id = $graphAppRole.Id; type = 'Role' })
                    },
                    @{
                        resourceAppId  = $DataverseAppId
                        resourceAccess = @(@{ id = $dvScope.Id; type = 'Scope' })
                    }
                )
            }
            $app = New-MgApplication -BodyParameter $appBody -ErrorAction Stop
            $appCreated = $true
        }
    }

    # --- 3. Service principal ------------------------------------------------
    $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
    if (-not $sp) {
        Write-LabLog -Level Info -Message "Creating service principal for $($app.AppId)..."
        if ($PSCmdlet.ShouldProcess($app.AppId, 'New-MgServicePrincipal')) {
            $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
        }
    }
    Write-LabLog -Level Info -Message "  servicePrincipalObjectId=$($sp.Id)"

    # --- 4. Client secret rotation (only if needed) --------------------------
    $newSecretGenerated = $false
    $secretKeyId        = $null
    $secretExpiresOn    = $null
    $newSecretValue     = $null

    $validCreds = @($app.PasswordCredentials | Where-Object {
        $_.EndDateTime -and ($_.EndDateTime - (Get-Date)).TotalDays -ge $MinSecretValidityDays
    })

    if ($validCreds.Count -gt 0 -and -not $ForceRotate) {
        $newest = $validCreds | Sort-Object EndDateTime -Descending | Select-Object -First 1
        $secretKeyId     = $newest.KeyId
        $secretExpiresOn = $newest.EndDateTime
        Write-LabLog -Level Info -Message "Existing client secret keyId=$secretKeyId is valid until $($secretExpiresOn.ToString('o')); not rotating."
        Write-LabLog -Level Warn -Message "  No new secret VALUE is available (Microsoft Entra never returns existing secret values). If Key Vault is empty or stale, re-run with -ForceRotate."
    } else {
        if ($ForceRotate) { Write-LabLog -Level Info -Message "-ForceRotate set; generating a new client secret regardless of existing credential validity..." }
        else              { Write-LabLog -Level Info -Message "No client secret with >=$MinSecretValidityDays days remaining; generating a new one..." }
        if ($PSCmdlet.ShouldProcess($app.AppId, 'Add-MgApplicationPassword')) {
            $passBody = @{
                passwordCredential = @{
                    displayName   = "lab-rotation-$(Get-Date -Format yyyyMMdd)"
                    endDateTime   = (Get-Date).AddYears(1).ToString('o')
                }
            }
            $newPwd = Add-MgApplicationPassword -ApplicationId $app.Id -BodyParameter $passBody -ErrorAction Stop
            $secretKeyId     = $newPwd.KeyId
            $secretExpiresOn = $newPwd.EndDateTime
            $newSecretValue  = $newPwd.SecretText
            $newSecretGenerated = $true
            Write-LabLog -Level Info -Message "  new secret keyId=$secretKeyId expires=$($secretExpiresOn.ToString('o'))"
        }
    }

    # --- 5. Admin consent (Graph AppRole + Dataverse delegated scope) --------
    Write-LabLog -Level Info -Message "Granting admin consent..."

    # 5a. Graph application permission via appRoleAssignment
    $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue
    if (-not ($existingAssignments | Where-Object { $_.AppRoleId -eq $graphAppRole.Id -and $_.ResourceId -eq $graphSp.Id })) {
        if ($PSCmdlet.ShouldProcess('Microsoft Graph - ServiceMessage.Read.All', 'New-MgServicePrincipalAppRoleAssignment')) {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $sp.Id `
                -PrincipalId $sp.Id `
                -ResourceId $graphSp.Id `
                -AppRoleId $graphAppRole.Id `
                -ErrorAction Stop | Out-Null
        }
    } else {
        Write-LabLog -Level Info -Message "  Graph ServiceMessage.Read.All already consented."
    }

    # 5b. Dataverse delegated scope via oauth2PermissionGrant
    $existingGrants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($sp.Id)' and resourceId eq '$($dvSp.Id)'" -ErrorAction SilentlyContinue
    $needsDvGrant = -not ($existingGrants | Where-Object { $_.Scope -match '\buser_impersonation\b' })
    if ($needsDvGrant) {
        if ($PSCmdlet.ShouldProcess('Dataverse - user_impersonation', 'New-MgOauth2PermissionGrant')) {
            New-MgOauth2PermissionGrant -BodyParameter @{
                clientId    = $sp.Id
                consentType = 'AllPrincipals'
                resourceId  = $dvSp.Id
                scope       = 'user_impersonation'
            } -ErrorAction Stop | Out-Null
        }
    } else {
        Write-LabLog -Level Info -Message "  Dataverse user_impersonation already consented."
    }

    # --- 6. Poll for consent confirmation ------------------------------------
    Write-LabLog -Level Info -Message "Verifying consent landed (poll up to $ConsentPollSeconds s)..."
    $deadline = (Get-Date).AddSeconds($ConsentPollSeconds)
    $graphOk = $false
    $dvOk    = $false
    while ((Get-Date) -lt $deadline -and (-not ($graphOk -and $dvOk))) {
        if (-not $graphOk) {
            $a = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue
            $graphOk = [bool]($a | Where-Object { $_.AppRoleId -eq $graphAppRole.Id -and $_.ResourceId -eq $graphSp.Id })
        }
        if (-not $dvOk) {
            $g = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($sp.Id)' and resourceId eq '$($dvSp.Id)'" -ErrorAction SilentlyContinue
            $dvOk = [bool]($g | Where-Object { $_.Scope -match '\buser_impersonation\b' })
        }
        if (-not ($graphOk -and $dvOk)) { Start-Sleep -Seconds 3 }
    }

    if (-not $graphOk) { Write-LabLog -Level Error -Message "Graph ServiceMessage.Read.All consent NOT confirmed after $ConsentPollSeconds s. Verify in Microsoft Entra admin center > Enterprise applications > $appName > Permissions." -Throw }
    if (-not $dvOk)    { Write-LabLog -Level Error -Message "Dataverse user_impersonation consent NOT confirmed after $ConsentPollSeconds s." -Throw }
    Write-LabLog -Level Info -Message "  Both permissions consented [OK]"

    # --- 7. Persist state ----------------------------------------------------
    $state | Add-Member -NotePropertyName 'appRegistration' -NotePropertyValue ([pscustomobject]@{
        applicationId             = $app.AppId
        objectId                  = $app.Id
        displayName               = $app.DisplayName
        servicePrincipalObjectId  = $sp.Id
        secretKeyId               = $secretKeyId
        secretExpiresOn           = $secretExpiresOn.ToString('o')
        consentedPermissions      = @('Microsoft Graph: ServiceMessage.Read.All (Application)', 'Dataverse: user_impersonation (Delegated)')
    }) -Force
    Save-LabState -State $state

    # --- 8. Hand off the secret value (NEVER logged) -------------------------
    if ($newSecretGenerated) {
        # Cross-process safe: persist the new secret to a gitignored, owner-only
        # handoff file under lab/. The next script (02_New-KeyVault.ps1) reads
        # and DELETES it. If 02_New-KeyVault.ps1 has already created the vault
        # AND we have rights to write directly, push there too.
        Set-LabHandoffSecret -SecretValue $newSecretValue
        try {
            if ($state.keyVault -and $state.keyVault.name) {
                Write-LabLog -Level Info -Message "Existing Key Vault '$($state.keyVault.name)' detected; uploading rotated secret directly..."
                if (-not (Get-Module -Name Az.KeyVault -ListAvailable)) { Import-Module Az.KeyVault -ErrorAction Stop }
                $secVal = ConvertTo-SecureString $newSecretValue -AsPlainText -Force
                Set-AzKeyVaultSecret -VaultName $state.keyVault.name -Name $state.keyVault.secretName -SecretValue $secVal -ErrorAction Stop | Out-Null
                Write-LabLog -Level Info -Message "  Secret pushed directly to Key Vault. .secret-handoff still present as a fallback."
            }
        } catch {
            Write-LabLog -Level Warn -Message "Direct Key Vault upload failed: $($_.Exception.Message). Run 02_New-KeyVault.ps1 next; it will read the .secret-handoff file."
        }
        # Defensively clear the local variable.
        $newSecretValue = $null
    } else {
        Write-LabLog -Level Info -Message "No new secret generated. If Key Vault is empty/stale, re-run this script with -ForceRotate."
    }

    Write-LabLog -Level Info -Message "App registration ready. Next: pwsh ./02_New-KeyVault.ps1"
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
}
