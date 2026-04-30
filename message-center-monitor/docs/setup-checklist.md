# Message Center Monitor — Setup Checklist

End-to-end deployment checklist for the Message Center Monitor solution. This checklist replaces the v2.2 manual-table-creation flow with the v2.3+ scripted deployment path.

**Estimated time:** 60–90 minutes
**Prerequisites:** see [README Prerequisites](../README.md#prerequisites)

---

## Checklist

### Step 1: Create Microsoft Entra ID app registration

- [ ] Go to [Microsoft Entra admin center](https://entra.microsoft.com) > **Applications** > **App registrations** > **New registration**
- [ ] Name: `Message Center Monitor`, account type: single tenant
- [ ] After registration, open **API permissions** > **Add a permission** > **Microsoft Graph** > **Application permissions** > add `ServiceMessage.Read.All`
- [ ] Click **Grant admin consent** (requires an administrator with permission to consent)
- [ ] Copy the Application (client) ID and Directory (tenant) ID

**Details:** [README — Microsoft Entra ID App Registration](../README.md#1-microsoft-entra-id-app-registration)

---

### Step 2: (Recommended) Configure certificate or federated credential

Per the repository [authentication standard](../../AGENTS.md#authentication-standard-managed-identity-first), prefer certificate-based or workload identity federation over client secrets. Client secret is the legacy fallback path used only when neither is available.

- [ ] In your app registration, open **Certificates & secrets**
- [ ] Either:
  - **Certificate:** click **Certificates** > **Upload certificate** and upload a PEM/CRT issued by your internal CA, OR
  - **Federated credential:** click **Federated credentials** > **Add credential** and bind it to your CI workload (GitHub Actions OIDC, Azure DevOps, etc.)
- [ ] If neither is feasible, fall back to **Client secrets** > **+ New client secret** (≤ 90 days expiration for prod)

**Details:** [README — Recommended: Certificate or Federated Credential](../README.md#15-recommended-certificate-or-federated-credential)

---

### Step 3: Create Azure Key Vault and store the credential

- [ ] Create a Key Vault (Azure Portal or CLI)
- [ ] Add the certificate (preferred) or client secret as a secret named `MessageCenterClientSecret`
- [ ] Enable purge protection (soft-delete is on by default in Azure CLI ≥ 2.39 — do **not** pass the deprecated `--enable-soft-delete true` flag)
- [ ] Grant the Power Automate connection (or managed identity) **Get** access on secrets

**Details:** [Secrets Management](secrets-management.md)

---

### Step 4: (Recommended) Apply Conditional Access policy to the service principal

- [ ] Restrict the service principal sign-ins to expected source IPs (Power Automate Azure region IP ranges or your CI runner egress)
- [ ] Optionally require workload identity policies where supported

The companion [conditional-access-automation](../../conditional-access-automation/) solution can deploy and monitor these CA policies.

---

### Step 5: Provision the Dataverse schema

The schema script creates the table, columns, option sets, **and the alternate key on `fsi_messagecenterid`** in one call. Pull the secret from Key Vault into an environment variable rather than passing it as a CLI argument.

- [ ] Run the schema script (PowerShell):

  ```powershell
  $env:MCM_CLIENT_SECRET = (Get-Secret -Vault MyVault -Name MessageCenterClientSecret -AsPlainText)
  python scripts\create_mcm_dataverse_schema.py `
      --tenant-id <tenant-guid> `
      --client-id <app-id> `
      --environment-url https://<org>.crm.dynamics.com `
      --output-docs
  ```

- [ ] Or run the schema script (bash):

  ```bash
  export MCM_CLIENT_SECRET=$(az keyvault secret show --vault-name kv-mcm --name MessageCenterClientSecret --query value -o tsv)
  python scripts/create_mcm_dataverse_schema.py \
      --tenant-id <tenant-guid> \
      --client-id <app-id> \
      --environment-url https://<org>.crm.dynamics.com \
      --output-docs
  ```

- [ ] Verify `docs/dataverse-schema.md` was regenerated with the canonical column names and option-set integers

---

### Step 6: Create the Dataverse Application User

The PowerShell governance scripts call the Dataverse Web API as the same Entra app used for Microsoft Graph. Without an application user, the scripts fail with `401 Unauthorized` or `403 Forbidden`.

- [ ] Power Platform admin center → **Environments** → select your environment → **Settings** → **Users + permissions** → **Application users** → **+ New app user**
- [ ] Add the Entra app from Step 1 by Application (client) ID
- [ ] Assign a custom security role with **read / write / append / append-to** access on `fsi_messagecenterlog`
- [ ] (Non-prod only) **System Administrator** is acceptable; for production, scope a custom role to the table
- [ ] Confirm the application user appears with status **Enabled**

---

### Step 7: Provision environment variables

- [ ] Run the env-var setup script:

  ```powershell
  $env:MCM_CLIENT_SECRET = (Get-Secret -Vault MyVault -Name MessageCenterClientSecret -AsPlainText)
  python scripts\create_mcm_environment_variables.py `
      --tenant-id <tenant-guid> `
      --client-id <app-id> `
      --environment-url https://<org>.crm.dynamics.com
  ```

This provisions: polling schedule (`fsi_PollingIntervalDays`), severity threshold (`fsi_NotifySeverities`), Teams channel ID (`fsi_TeamsChannelId`), Teams team ID (`fsi_TeamsTeamId`), and Key Vault references for the client secret.

---

### Step 8: Provision connection references

- [ ] Run the connection-reference setup script:

  ```bash
  export MCM_CLIENT_SECRET=$(az keyvault secret show --vault-name kv-mcm --name MessageCenterClientSecret --query value -o tsv)
  python scripts/create_mcm_connection_references.py \
      --tenant-id <tenant-guid> \
      --client-id <app-id> \
      --environment-url https://<org>.crm.dynamics.com
  ```

This provisions connection references for: Microsoft Dataverse, Microsoft Teams, Azure Key Vault, and HTTP with Microsoft Entra ID (Premium).

---

### Step 9: Build the Power Automate flow

- [ ] Follow the step-by-step instructions in [Flow Configuration](flow-configuration.md)
- [ ] Wire each step to the connection references and environment variables provisioned above
- [ ] Use the alternate-key upsert approach (`fsi_messagecenterid`); the key was provisioned by the schema script in Step 5

---

### Step 10: Configure Teams channel and adaptive card

- [ ] Create a Teams channel for platform alerts (e.g., `Platform Alerts`)
- [ ] Configure the adaptive card per [Teams Integration](teams-integration.md), starting from `templates/teams-notification-card.json`
- [ ] Replace the `{environment}`, `{appId}`, `{publisherPrefix}`, and `{recordId}` curly tokens in the `Assess Record` Action.OpenUrl URL with your tenant-specific values

---

### Step 11: Verify DLP policy

- [ ] Power Platform admin center > **Data policies**
- [ ] Verify HTTP connector can access `graph.microsoft.com`
- [ ] Verify Azure Key Vault connector is allowed
- [ ] If blocked, add to the allowed endpoints or move to the **Business** group

**Details:** [README — DLP Policy](../README.md#6-dlp-policy-if-applicable)

---

### Step 12: Smoke-test before standing up the flow

Validate auth and Dataverse access end-to-end before relying on the scheduled flow.

- [ ] Run the governance script in dry-run mode:

  ```powershell
  pwsh ./scripts/governance/Invoke-MessageCenterSync.ps1 `
      -DryRun `
      -AuthMode DeviceCode `
      -TenantId <tenant-guid> `
      -ClientId <app-id> `
      -EnvironmentUrl https://<org>.crm.dynamics.com
  ```

  > **AuthMode tip:** Use the credential you actually have on this workstation. `DeviceCode` (interactive browser sign-in) or `ClientSecret` (with `$env:MCM_CLIENT_SECRET`) are the typical choices for an admin laptop. `ManagedIdentity` (the script default) only works when the script runs in a host that has a managed identity assigned — not on a laptop.

- [ ] Confirm: token acquisition succeeds, Dataverse list/upsert simulated rows match the schema, no `401`/`403` errors
- [ ] Then enable the flow and run it once manually from the Power Automate designer

---

## Post-Setup

### Regular maintenance

- [ ] Monitor flow run history weekly
- [ ] Rotate client secret per [Secrets Management — Rotation cadence](secrets-management.md#rotation-cadence) (90 days prod, ≤ 365 days non-prod)
- [ ] Triage Message Center posts in the model-driven app or directly in Dataverse

### Optional enhancements

- [ ] Add error notification flow — see [Flow Configuration Step 8](flow-configuration.md#step-8-error-handling) for the Try/Catch scope pattern
- [ ] Create Dataverse views filtered by service or category
- [ ] Build a Power BI report on the `fsi_messagecenterlog` table for trend analysis
- [ ] Integrate with ServiceNow or another ITSM via Power Automate

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
| HTTP 401/403 from Graph | Check app registration permissions, admin consent, and credential expiry |
| HTTP 401/403 from Dataverse | Re-verify the application user (Step 6) is enabled and has `fsi_messagecenterlog` access |
| Schema script fails on alternate key | Re-run with `--output-docs`; the script is idempotent and provisions the key on `fsi_messagecenterid` |
| No posts in Dataverse | Check flow run history and HTTP response; verify pagination loop |
| Teams notifications missing | Verify channel connector, env-var-driven severity check, and `fsi_notifiedon` duplicate-prevention logic |
| Key Vault access denied | Check access policy or RBAC assignment for the flow connection identity |

**Full troubleshooting:** [README — Troubleshooting](../README.md#troubleshooting)
