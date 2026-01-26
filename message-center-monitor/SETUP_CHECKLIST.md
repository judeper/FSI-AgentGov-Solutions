# Setup Checklist

Quick 10-step checklist for deploying the Message Center Monitor solution.

## Prerequisites

- [ ] Microsoft 365 tenant with admin access
- [ ] Power Platform environment with Dataverse
- [ ] Azure subscription (for Key Vault - optional but recommended)

---

## Checklist

### Step 1: Create Azure AD App Registration

- [ ] Go to Azure Portal > Azure Active Directory > App Registrations
- [ ] Click "New registration"
- [ ] Name: `Message Center Monitor`
- [ ] Account type: Single tenant
- [ ] Click "Register"

**Details:** [README.md - Prerequisites](./README.md#prerequisites)

---

### Step 2: Configure API Permissions

- [ ] In your app registration, go to "API permissions"
- [ ] Click "Add a permission"
- [ ] Select "Microsoft Graph"
- [ ] Choose "Application permissions" (NOT Delegated)
- [ ] Search for and add `ServiceMessage.Read.All`
- [ ] Click "Grant admin consent"

**Details:** [README.md - Azure AD App Registration](./README.md#1-azure-ad-app-registration)

---

### Step 3: Create Client Secret

- [ ] In your app registration, go to "Certificates & secrets"
- [ ] Click "New client secret"
- [ ] Add description: `Message Center Monitor Flow`
- [ ] Choose expiration (recommended: 12 months)
- [ ] Copy the secret value immediately (you won't see it again)

---

### Step 4: Set Up Azure Key Vault (Recommended)

- [ ] Create Key Vault in Azure Portal
- [ ] Add client secret as a secret
- [ ] Grant Power Automate access to read secrets

**Details:** [SECRETS_MANAGEMENT.md](./SECRETS_MANAGEMENT.md)

---

### Step 5: Create Dataverse Table

- [ ] Go to Power Apps > Tables
- [ ] Create table: `MessageCenterLog`
- [ ] Add columns per data model in README

**Columns:**
| Column | Type |
|--------|------|
| messagecenterId | Text (Primary) |
| title | Text (500) |
| category | Choice |
| severity | Choice |
| services | Text (2000) |
| startDateTime | DateTime |
| actionRequiredByDateTime | DateTime |
| lastModifiedDateTime | DateTime |
| isMajorChange | Yes/No |
| body | Multiline Text |
| assessmentStatus | Choice |
| assessment | Multiline Text |
| impactsAgents | Yes/No |
| assessedBy | Lookup (User) |
| assessedDate | DateTime |
| actionsTaken | Multiline Text |

**Choice Values:**
| Choice Column | Values |
|---------------|--------|
| category | Feature, Admin, Security |
| severity | High, Normal, Critical |
| assessmentStatus | Not Assessed, Reviewed, Impacts Agents, No Impact |

**Details:** [README.md - Data Model](./README.md#data-model)

---

### Step 6: Check DLP Policy

- [ ] Go to Power Platform Admin Center > Data policies
- [ ] Find policy for your environment
- [ ] Verify HTTP connector can access `graph.microsoft.com`
- [ ] If blocked, add to allowed endpoints or move to "Business" group

---

### Step 7: Create Power Automate Flow

- [ ] Go to Power Automate > Create > Scheduled cloud flow
- [ ] Set daily recurrence (e.g., 9 AM)
- [ ] Add Key Vault action to get secret
- [ ] Add HTTP action for Graph API
- [ ] Add Parse JSON action
- [ ] Add Apply to each with Dataverse upsert
- [ ] Add condition for high-severity posts
- [ ] Add Teams notification action

**Details:** [FLOW_SETUP.md](./FLOW_SETUP.md)

---

### Step 8: Create Teams Channel

- [ ] Open Microsoft Teams
- [ ] Create channel: `Platform Alerts` (or similar)
- [ ] Note the team and channel for flow configuration

---

### Step 9: Configure Teams Notification

- [ ] Add Teams action to your flow
- [ ] Use adaptive card template from `teams-notification-card.json`
- [ ] Replace placeholders with dynamic content
- [ ] Configure to post only on high-severity or action-required

**Details:** [TEAMS_INTEGRATION.md](./TEAMS_INTEGRATION.md)

---

### Step 10: Test and Verify

- [ ] Save the flow
- [ ] Click "Test" > "Manually" > "Test"
- [ ] Verify flow runs successfully
- [ ] Check Dataverse for imported records
- [ ] Check Teams channel for notifications (if high-severity posts exist)

---

## Post-Setup

### Regular Maintenance

- [ ] Monitor flow run history weekly
- [ ] Rotate client secret before expiration
- [ ] Review and assess Message Center posts regularly

### Optional Enhancements

- [ ] Add error notification flow
- [ ] Create Dataverse views for filtering
- [ ] Set up Power BI dashboard for trends
- [ ] Integrate with ServiceNow or other ITSM

---

## Quick Links

| Resource | URL |
|----------|-----|
| Azure Portal | https://portal.azure.com |
| Power Apps | https://make.powerapps.com |
| Power Automate | https://make.powerautomate.com |
| Teams | https://teams.microsoft.com |
| M365 Admin Center | https://admin.microsoft.com |
| Message Center | https://admin.microsoft.com/Adminportal/Home#/MessageCenter |

---

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| HTTP 401/403 | Check app registration permissions and admin consent |
| No posts in Dataverse | Check flow run history and HTTP response |
| Teams notifications missing | Verify channel connector and condition logic |
| Key Vault access denied | Check access policy or RBAC assignment |

**Full troubleshooting:** [README.md - Troubleshooting](./README.md#troubleshooting)
