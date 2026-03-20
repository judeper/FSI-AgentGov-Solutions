# Prerequisites

## Required Solutions

Deploy these solutions before activating Cross-Tenant External Sharing Governance:

| Solution | Required Version | Purpose |
|----------|-----------------|---------|
| `agent-registry-automation` | v1.0.0+ | Provides `fsi_agentinventory.fsi_zone` for severity assignment |
| `unrestricted-agent-sharing-detector` | v1.0.0+ | Covers internal oversharing; this solution covers external |

## Managed Identity Setup

This solution uses two System-Assigned Managed Identities to enforce least-privilege separation.

### MI-CrossTenantReadOnly

Used by: Flow 1, Flow 2, Flow 3, Flow 6, PowerShell scripts

| Permission | Type | Scope | Purpose |
|------------|------|-------|---------|
| `Policy.Read.All` | Application | Microsoft Graph | Read Entra CTA policies |
| `User.Read.All` | Application | Microsoft Graph | Read guest user profiles |
| `CrossTenantInformation.ReadBasic.All` | Application | Microsoft Graph | Resolve tenant IDs to display names |
| `Organization.Read.All` | Application | Microsoft Graph | Read home tenant organization details |
| `PowerPlatform.Admin.Read.All` | Application | Power Platform API | Read tenant isolation, agent shares, environments |

### MI-CrossTenantReadWrite

Used by: Flow 4, Flow 5 only

| Permission | Type | Scope | Purpose |
|------------|------|-------|---------|
| `Policy.ReadWrite.CrossTenantAccess` | Application | Microsoft Graph | Update Entra CTA partner policies |
| `User.Read.All` | Application | Microsoft Graph | Resolve user profiles during onboarding |
| `CrossTenantInformation.ReadBasic.All` | Application | Microsoft Graph | Resolve tenant IDs during onboarding |
| `PowerPlatform.Admin.ReadWrite.All` | Application | Power Platform API | Remove agent role assignments |

> **IAM Note:** `Policy.ReadWrite.CrossTenantAccess` is a highly privileged Graph permission that may require Entra Global Admin approval in FSI tenants. If approval is delayed, Flows 4 and 5 can operate in manual-instruction-only mode.

## Provisioning Steps

### Step 1: Create Managed Identities in Azure Portal

1. Navigate to **Azure Portal** > **Managed Identities**
2. Create **MI-CrossTenantReadOnly**:
   - Resource group: Use your governance resource group
   - Region: Same region as your Power Platform environment
   - Name: `MI-CrossTenantReadOnly`
3. Create **MI-CrossTenantReadWrite**:
   - Resource group: Same as above
   - Name: `MI-CrossTenantReadWrite`
4. Record the **Object (principal) ID** for each identity

### Step 2: Assign Graph API Permissions

Use Azure CLI or PowerShell to assign application roles to each Managed Identity. Example using Azure CLI:

```bash
# Get the Microsoft Graph service principal
graphSpId=$(az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query '[0].id' -o tsv)

# Assign permissions to MI-CrossTenantReadOnly
# Repeat for each permission: Policy.Read.All, User.Read.All,
# CrossTenantInformation.ReadBasic.All, Organization.Read.All
az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<MI-ReadOnly-ObjectId>/appRoleAssignments" \
  --body '{"principalId":"<MI-ReadOnly-ObjectId>","resourceId":"'"$graphSpId"'","appRoleId":"<RoleId>"}'
```

Refer to [Microsoft Graph permission reference](https://learn.microsoft.com/en-us/graph/permissions-reference) for app role IDs.

### Step 3: Assign Power Platform Admin API Permissions

1. Register each Managed Identity as a service principal in the Power Platform admin center
2. Assign `PowerPlatform.Admin.Read.All` to **MI-CrossTenantReadOnly**
3. Assign `PowerPlatform.Admin.ReadWrite.All` to **MI-CrossTenantReadWrite**

### Step 4: Validate Permissions

Run test API calls to confirm access before enabling flows:

```powershell
# Test MI-CrossTenantReadOnly — should return CTA policies
Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners" `
  -Headers @{ Authorization = "Bearer $readOnlyToken" }

# Test MI-CrossTenantReadWrite — should return 200 on a GET
Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy" `
  -Headers @{ Authorization = "Bearer $readWriteToken" }
```

If any call returns `403 Forbidden`, verify that the app role assignments have propagated (this can take up to 30 minutes after assignment).

## Environment Requirements

- Power Platform environment with Dataverse
- Microsoft 365 E5 or equivalent (for Graph API access)
- Azure subscription (for Managed Identities and Azure Automation)
- Power Automate Premium license (for HTTP connector in flows)

## Network Requirements

- Access to `https://graph.microsoft.com`
- Access to `https://api.powerplatform.com`
- Access to Dataverse environment URL
