# Service Principal Setup

Register and configure the Service Principal for automated environment provisioning.

## Overview

The provisioning flows use a Service Principal (app-only identity) to:

- Create Power Platform environments
- Enable Managed Environments
- Assign environments to groups
- Bind security groups
- Apply baseline configurations

## Architecture

```
Azure Key Vault
    |
    | (Get Secret)
    v
Power Automate Flow
    |
    | (Bearer Token)
    v
Service Principal ──────────────────────────────────────────┐
    |                                                        |
    |── api.bap.microsoft.com (Power Platform Admin API)     |
    |── *.crm.dynamics.com (Dataverse Web API)               |
    └── graph.microsoft.com (Microsoft Graph)                |
                                                             |
    Power Platform Management App Registration ◄─────────────┘
    (admin.powerplatform.microsoft.com)
```

## Prerequisites

- Entra ID Application Administrator role
- Power Platform Admin role
- Azure Key Vault Secrets Officer role
- `azure-identity` and `msal` Python packages installed

## Automated Registration

### Using the Script

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Dry run (validates without creating)
python scripts/register_service_principal.py \
  --tenant-id <your-tenant-id> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <your-keyvault-name> \
  --secret-name ELM-ServicePrincipal-Secret \
  --dry-run

# Execute registration
python scripts/register_service_principal.py \
  --tenant-id <your-tenant-id> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <your-keyvault-name> \
  --secret-name ELM-ServicePrincipal-Secret

# With verbose output (shows stack traces on error)
python scripts/register_service_principal.py \
  --tenant-id <your-tenant-id> \
  --app-name ELM-Provisioning-ServicePrincipal \
  --key-vault-name <your-keyvault-name> \
  --secret-name ELM-ServicePrincipal-Secret \
  --verbose
```

### Script Output

```
ELM Service Principal Registration
==================================

[1/4] Creating Entra ID application...
      Application ID: 12345678-1234-1234-1234-123456789012
      Object ID: 87654321-4321-4321-4321-210987654321

[2/4] Creating client secret...
      Secret ID: secret-id-guid
      Expiry: 2026-04-29 (90 days)

[3/4] Storing secret in Key Vault...
      Vault: your-keyvault-name
      Secret: ELM-ServicePrincipal-Secret
      Version: abc123...

[4/4] Summary
      ========
      Application Name: ELM-Provisioning-ServicePrincipal
      Application ID: 12345678-1234-1234-1234-123456789012
      Tenant ID: <your-tenant-id>
      Key Vault: your-keyvault-name
      Secret Name: ELM-ServicePrincipal-Secret

      NEXT STEP (MANUAL):
      Register as Power Platform Management Application:
      1. Go to admin.powerplatform.microsoft.com
      2. Settings > Admin settings > Power Platform settings
      3. Service principal > New service principal
      4. Enter Application ID: 12345678-1234-1234-1234-123456789012
      5. Click Create
```

---

## Manual Registration Steps

If not using the script, follow these steps:

### Step 1: Register Application in Entra ID

1. Open [Entra admin center](https://entra.microsoft.com)
2. Navigate to: Applications > App registrations > New registration

| Setting | Value |
|---------|-------|
| Name | ELM-Provisioning-ServicePrincipal |
| Supported account types | Accounts in this organizational directory only |
| Redirect URI | (leave blank) |

3. Click **Register**
4. Record these values:
   - **Application (client) ID**: `________-____-____-____-____________`
   - **Directory (tenant) ID**: `________-____-____-____-____________`

### Step 2: Create Client Secret

1. In the app registration, go to **Certificates & secrets**
2. Click **New client secret**

| Setting | Value |
|---------|-------|
| Description | ELM Provisioning Secret |
| Expires | 6 months |

3. Click **Add**
4. **Immediately copy the secret value** - it won't display again

> **Production Recommendation:** Use certificates instead of secrets for better security. See [Certificate Configuration](#certificate-configuration-production) below.

### Step 3: Store Secret in Azure Key Vault

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to your Key Vault
3. Go to **Secrets** > **Generate/Import**

| Setting | Value |
|---------|-------|
| Upload options | Manual |
| Name | ELM-ServicePrincipal-Secret |
| Value | (paste client secret) |
| Content type | text/plain |

4. Click **Create**

### Step 4: Grant Key Vault Access to Power Automate

1. In Key Vault, go to **Access policies** (or **Access control (IAM)** for RBAC)
2. Add access policy:

| Setting | Value |
|---------|-------|
| Secret permissions | Get |
| Principal | (search for Power Automate connection identity) |

> **Note:** The exact principal depends on how you configure the Power Automate Key Vault connection. You may need to grant access to a user-assigned managed identity or the flow creator's identity.

### Step 5: Register as Power Platform Management Application

1. Open [Power Platform admin center](https://admin.powerplatform.microsoft.com)
2. Navigate to: Settings > Admin settings > Power Platform settings
3. Select **Service principal** > **New service principal**
4. Enter the **Application (client) ID** from Step 1
5. Click **Create**
6. Verify status shows **Enabled**

### Permissions Granted Implicitly

When registered as a Management Application, the SP receives:

| Permission | Granted |
|------------|---------|
| Create environments | Yes |
| Read environment properties | Yes |
| Update environment settings | Yes |
| Enable Managed Environments | Yes |
| Add to Environment Groups | Yes |
| Delete environments | **No** |
| Modify DLP policies | **No** |
| Access environment data | **No** |

This follows the principle of least privilege.

---

## Certificate Configuration (Production)

For production deployments, use certificates instead of secrets:

### Generate Certificate

```powershell
$cert = New-SelfSignedCertificate `
    -Subject "CN=ELM-Provisioning-ServicePrincipal" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(1)

# Export public key (.cer) for upload to Entra
Export-Certificate -Cert $cert -FilePath "ELM-SP.cer"

# Export private key (.pfx) for Key Vault
$pwd = ConvertTo-SecureString -String "YourPassword" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "ELM-SP.pfx" -Password $pwd
```

### Upload to Entra ID

1. App registration > Certificates & secrets > Certificates
2. Upload certificate: `ELM-SP.cer`

### Store in Key Vault

1. Key Vault > Certificates > Generate/Import
2. Import `ELM-SP.pfx` with password
3. Update Power Automate connection to use certificate

---

## Power Automate Connection Setup

### Create Service Principal Connection

1. Open [Power Automate](https://make.powerautomate.com)
2. Go to **Connections** > **New connection**
3. Search for **Power Platform for Admins V2**
4. Select **Connect with Service Principal**

| Field | Value |
|-------|-------|
| Tenant ID | (your tenant ID) |
| Client ID | (application ID) |
| Client Secret | (from Key Vault - see below) |

### Retrieve Secret from Key Vault in Flow

Add this action before using the SP connection:

**Action: Azure Key Vault - Get secret**

| Parameter | Value |
|-----------|-------|
| Vault name | your-keyvault-name |
| Secret name | ELM-ServicePrincipal-Secret |

**Secure the output:**

```json
"runtimeConfiguration": {
  "secureData": {
    "properties": ["inputs", "outputs"]
  }
}
```

---

## Credential Rotation

### Rotation Schedule

| Credential Type | Rotation Period | Lead Time |
|-----------------|-----------------|-----------|
| Client Secret | 90 days | 14 days |
| Certificate | 1 year | 30 days |

### Rotation Procedure

1. **Generate new credential** in Entra ID (keep old active)
2. **Update Key Vault** with new value
3. **Test** provisioning flow with new credential
4. **Verify** successful environment creation
5. **Revoke old credential** in Entra ID
6. **Log rotation** in ProvisioningLog (optional)

### Automated Rotation Reminder

Set up a recurrence flow to remind administrators:

```
Trigger: Recurrence (daily at 9:00 AM)
Action: Calculate days until expiry
Condition: Days remaining < 14
Action: Send Teams/email notification
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Expired secret | Rotate credential, update Key Vault |
| 403 Forbidden | Not registered as Management App | Complete Step 5 in PPAC |
| Environment creation fails | Insufficient permissions | Verify Management App registration |
| Key Vault access denied | Missing access policy | Grant Get permission to correct principal |

### Verify Registration

1. **Entra ID:** App registrations > Search for app name
2. **PPAC:** Settings > Service principal > Verify "Enabled" status
3. **Key Vault:** Secrets > Verify secret exists and is not expired

### Test Script

```bash
python scripts/elm_client.py \
  --tenant-id <tenant-id> \
  --client-id <app-id> \
  --environment-url https://<org>.crm.dynamics.com \
  --test-connection
```

Expected output:

```
Testing Dataverse connection...
  Token acquired: ✓
  API accessible: ✓
  Organization: Your Org Name
Connection test: PASSED
```

---

## Security Considerations

### Principle of Least Privilege

- SP cannot delete environments
- SP cannot modify DLP policies
- SP cannot access environment data beyond metadata
- SP actions logged in ProvisioningLog

### Monitoring

Monitor for suspicious activity:

- Failed authentication attempts
- Unusual creation patterns
- Off-hours activity

### Revocation

If SP is compromised:

1. Immediately revoke credentials in Entra ID
2. Disable Management App registration in PPAC
3. Rotate Key Vault secret
4. Audit ProvisioningLog for unauthorized actions
5. Generate new SP with new credentials

---

## Next Steps

After Service Principal setup:

1. [Configure Power Automate flows](./flow-configuration.md)
2. [Build Copilot Studio agent](./copilot-agent-setup.md)
