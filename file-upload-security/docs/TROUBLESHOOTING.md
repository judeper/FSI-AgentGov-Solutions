# Troubleshooting

## Common Issues

### Authentication

#### "Token acquisition failed"

**Cause:** Invalid credentials or missing permissions.

**Resolution:**
1. Verify `FUS_TENANT_ID` and `FUS_CLIENT_ID` environment variables
2. Confirm app registration has required API permissions with admin consent
3. For certificate auth, verify the certificate is not expired:
   ```powershell
   Get-ChildItem Cert:\CurrentUser\My | Where-Object Thumbprint -eq $thumbprint
   ```
4. For interactive auth, use `-Interactive` flag

#### "Insufficient privileges"

**Cause:** Service principal lacks Dataverse System Administrator role.

**Resolution:**
1. In Power Platform admin center, navigate to target environment
2. **Settings** > **Users** > **Application users**
3. Add the service principal as an application user
4. Assign **System Administrator** security role

### Dataverse

#### "Entity 'fsi_fileupload_baseline' does not exist"

**Cause:** Schema not deployed.

**Resolution:**
```bash
cd scripts
python deploy.py --tenant-id <tid> --url <url> --interactive
```

#### "Column 'fsi_file_upload_enabled' does not exist"

**Cause:** Partial schema deployment.

**Resolution:** Re-run schema deployment (idempotent — existing entities are skipped):
```bash
python create_dataverse_schema.py --tenant-id <tid> --url <url> --interactive
```

### PowerShell Scripts

#### "FUSClient.psm1 not found"

**Cause:** Script invoked from wrong directory.

**Resolution:** Run scripts from the `scripts/` directory:
```powershell
cd file-upload-security\scripts
.\Test-FileUploadCompliance.ps1 -TenantId $tid -DataverseUrl $url
```

#### "No agents found"

**Cause:** Environment filter too restrictive or no published agents.

**Resolution:**
1. Remove environment filters: `-EnvironmentFilter '*'`
2. Include draft agents: `-IncludeDrafts`
3. Verify environments have Copilot Studio agents

#### "File upload status could not be determined"

**Cause:** Agent configuration JSON uses unexpected field name for file upload setting.

**Resolution:** The FUSClient checks multiple field names (`FileUpload`, `fileUpload`, `FileUploadEnabled`, `AllowFileUpload`, `fileUploadEnabled`). If Microsoft changes the field name:
1. Check the raw bot configuration in Dataverse
2. Update the field name list in `Get-BotFileUploadEnabled` in `FUSClient.psm1`

### Power Automate Flow

#### "Azure Automation job times out"

**Cause:** Large tenant with many environments/agents exceeds 2-hour timeout.

**Resolution:**
1. Filter environments: use `fsi_FUS_IncludeSandbox = false` in Dataverse
2. Increase flow timeout in `Wait_For_Job` action
3. Run scans per-zone rather than full tenant

#### "Parse_Results fails"

**Cause:** Runbook output is not valid JSON.

**Resolution:**
1. Check Azure Automation job output in Azure Portal
2. Verify no `Write-Host` or other stdout contamination in runbook
3. Check for PowerShell module version conflicts

#### "Teams card not posted"

**Cause:** Incorrect Teams group/channel IDs or insufficient permissions.

**Resolution:**
1. Verify `TeamsGroupId` via Graph Explorer: `GET /me/joinedTeams`
2. Get `TeamsChannelId` via: `GET /teams/{id}/channels`
3. Ensure the Teams connection user is a member of the target team

### Evidence Export

#### "Hash verification failed"

**Cause:** Evidence file modified after export.

**Resolution:**
1. Re-export the evidence: `Export-FileUploadEvidence.ps1`
2. Transfer evidence files as-is (no text encoding changes)
3. Use binary file transfer (not copy-paste)

#### Empty evidence export

**Cause:** No validation history in date range.

**Resolution:**
1. Verify validation runs have completed: check `fsi_fileupload_validationhistory`
2. Adjust date range: `-StartDate` and `-EndDate`
3. Run a validation first: `Test-FileUploadCompliance.ps1`

## Getting Help

- **Framework documentation:** [FSI-AgentGov](https://github.com/judeper/FSI-AgentGov)
- **Control reference:** [1.14 - Data Minimization and Agent Scope Control](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.14-data-minimization-and-agent-scope-control.md)
- **Solution repository:** [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions)

---

*File Upload Security Configurator — Troubleshooting Guide*
