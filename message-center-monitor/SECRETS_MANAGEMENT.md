# Secrets Management Guide

This guide explains how to securely store and access the client secret for the Message Center Monitor solution using Azure Key Vault.

## Why Use Key Vault?

- **Security:** Secrets are encrypted at rest and in transit
- **Auditing:** All access is logged
- **Rotation:** Easy to rotate secrets without updating flows
- **Compliance:** Meets security requirements for secret storage

## Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Power Automate  │────▶│  Azure Key Vault │────▶│ Client Secret   │
│     Flow        │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │
        ▼
┌─────────────────┐
│ Microsoft Graph │
│      API        │
└─────────────────┘
```

## Step 1: Create Azure Key Vault

### Via Azure Portal

1. Go to [Azure Portal](https://portal.azure.com)
2. Click **Create a resource**
3. Search for "Key Vault" and select it
4. Click **Create**

Configure:
- **Subscription:** Your subscription
- **Resource group:** Create new or use existing
- **Key vault name:** `kv-messagecenter-monitor` (must be globally unique)
- **Region:** Same region as your Power Platform environment
- **Pricing tier:** Standard
- **Soft-delete:** Enabled (default)
- **Purge protection:** Enable for production

5. Click **Review + create** > **Create**

### Via Azure CLI

```bash
# Create resource group (if needed)
az group create --name rg-messagecenter-monitor --location eastus

# Create Key Vault
az keyvault create \
  --name kv-messagecenter-monitor \
  --resource-group rg-messagecenter-monitor \
  --location eastus \
  --enable-soft-delete true \
  --enable-purge-protection true
```

## Step 2: Add Client Secret to Key Vault

### Via Azure Portal

1. Open your Key Vault
2. Go to **Secrets** in the left menu
3. Click **+ Generate/Import**

Configure:
- **Upload options:** Manual
- **Name:** `MessageCenterClientSecret`
- **Secret value:** Paste your app registration client secret
- **Content type:** (optional) `text/plain`
- **Enabled:** Yes

4. Click **Create**

### Via Azure CLI

```bash
az keyvault secret set \
  --vault-name kv-messagecenter-monitor \
  --name MessageCenterClientSecret \
  --value "your-client-secret-value"
```

## Step 3: Grant Power Automate Access

Power Automate needs permission to read secrets from Key Vault.

### Option A: Access Policy (Classic)

1. Open your Key Vault
2. Go to **Access policies**
3. Click **+ Add Access Policy**

Configure:
- **Secret permissions:** Get
- **Select principal:** Search for the identity running your flow

For flows running as a user:
- Search for and select your user account

For flows using a service principal:
- Search for the service principal name

4. Click **Add** > **Save**

### Option B: RBAC (Recommended)

1. Open your Key Vault
2. Go to **Access control (IAM)**
3. Click **+ Add** > **Add role assignment**

Configure:
- **Role:** Key Vault Secrets User
- **Assign access to:** User, group, or service principal
- **Members:** Select the identity running your flow

4. Click **Review + assign**

## Step 4: Create Power Automate Connection

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Click **Data** > **Connections** in the left menu
3. Click **+ New connection**
4. Search for "Azure Key Vault"
5. Select **Azure Key Vault**
6. Configure:
   - **Authentication type:** Default Azure AD application
   - **Vault name:** Your Key Vault name
7. Click **Create**
8. Sign in with your Microsoft 365 account

## Step 5: Use Key Vault in Your Flow

1. In your flow, add the action: **Azure Key Vault - Get secret**
2. Configure:
   - **Vault name:** Select your Key Vault
   - **Secret name:** `MessageCenterClientSecret`
3. The action outputs a `value` containing your secret
4. Use this value in the HTTP action's authentication:
   - **Secret:** `@{body('Get_secret')?['value']}`

## Security Best Practices

### Least Privilege

- Only grant "Get" permission for secrets (not List, Set, Delete)
- Use separate Key Vaults for different environments (dev/prod)

### Secret Rotation

When rotating the client secret:

1. Create new secret in Azure AD app registration
2. Add new secret to Key Vault (can use same name - it creates a new version)
3. Verify flow works with new secret
4. Delete old secret from Azure AD

### Monitoring

Enable diagnostics on Key Vault:

1. Open Key Vault > **Diagnostic settings**
2. Add diagnostic setting
3. Enable:
   - **AuditEvent** logs
   - **AllMetrics**
4. Send to Log Analytics workspace

### Alert on Access Anomalies

Create alert for unusual access patterns:

1. Go to Key Vault > **Alerts**
2. Create rule for failed access attempts
3. Configure notification to security team

## Cost Estimate

Azure Key Vault pricing (as of January 2026):

| Component | Cost |
|-----------|------|
| Secrets operations | $0.03 per 10,000 operations |
| Secret storage | Included |

**Monthly estimate for this solution:**
- Daily polling = ~30 operations/month
- Cost: < $0.01/month

## Alternative: Dataverse Environment Variables

If Key Vault is not available, you can store the secret in a Dataverse Environment Variable (not recommended for production):

1. Go to Power Apps > Solutions
2. Create or open your solution
3. Add > Environment variable
4. Configure:
   - Display name: `MessageCenterClientSecret`
   - Type: Secret
   - Data source: Azure Key Vault (preferred) or None

**Note:** Storing secrets in Dataverse without Key Vault backing is less secure. The secret is stored encrypted but is accessible to solution owners.

## Troubleshooting

### "Access denied" error

- Verify access policy or RBAC assignment is correct
- Ensure the identity running the flow has Get permission
- Check that the secret name is spelled correctly

### "Key Vault not found"

- Verify Key Vault name is correct (case-sensitive)
- Ensure Key Vault is in the same tenant
- Check network restrictions (if using private endpoints)

### "Secret not found"

- Verify secret name is correct (case-sensitive)
- Check that the secret is enabled (not disabled)
- Ensure the secret hasn't been purged

### Connection issues

- Re-authenticate the Key Vault connection in Power Automate
- Verify your account has access to the Key Vault
- Check if there are conditional access policies blocking access
