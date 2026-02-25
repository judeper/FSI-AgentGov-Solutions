# Conflict Rules Configuration

Default conflict rules and customization guidance.

---

## Default Rule Set

The following rules are provided as defaults for FSI organizations deploying AI agents on Power Platform.

### Maker/Checker Rules (Category 1)

| Rule ID | Role A | Role B | Severity | Description |
|---------|--------|--------|----------|-------------|
| MC-001 | Agent Developer | Pipeline Approver | Critical | Prevents self-approval of agent changes |
| MC-002 | Solution Developer | Solution Promoter | Critical | Requires independent promotion review |
| MC-003 | Flow Creator | Flow Approver | High | Enforces flow change review |
| MC-004 | Connection Creator | Connection Approver | High | Ensures connection review |
| MC-005 | DLP Policy Author | DLP Policy Approver | Critical | Prevents self-exemption |

### Segregation Rules (Category 2)

| Rule ID | Role A | Role B | Severity | Description |
|---------|--------|--------|----------|-------------|
| SG-001 | System Administrator | Agent Publisher (same env) | Critical | Admin shouldn't publish own work |
| SG-002 | Security Administrator | Agent Developer | High | Security role separation |
| SG-003 | Compliance Administrator | Agent Developer | High | Compliance role separation |
| SG-004 | Environment Creator | Environment Approver | High | Environment lifecycle separation |
| SG-005 | Data Steward | Data Consumer (sensitive) | Medium | Data access separation |

### Privileged Access Rules (Category 3)

| Rule ID | Role A | Role B | Severity | Description |
|---------|--------|--------|----------|-------------|
| PA-001 | Global Administrator | Agent Developer | Critical | Global admin shouldn't be maker |
| PA-002 | Power Platform Administrator | Basic User (any env) | High | Admin/user separation |
| PA-003 | Privileged Role Administrator | Application Administrator | Critical | Privilege escalation prevention |
| PA-004 | Break-Glass Account | Any Non-Emergency Use | Critical | Emergency access only (template — disabled by default; customize role names before enabling) |

---

## Rule Definition

### Rule Structure

```json
{
  "ruleId": "MC-001",
  "name": "Agent Developer cannot be Pipeline Approver",
  "category": "Maker/Checker",
  "roleA": {
    "name": "Agent Developer",
    "context": "Dataverse Security Role",
    "scope": "Environment"
  },
  "roleB": {
    "name": "Pipeline Approver",
    "context": "Dataverse Security Role",
    "scope": "Same Environment"
  },
  "severity": "Critical",
  "autoBlock": true,
  "allowException": true,
  "exceptionRequires": ["Manager", "Compliance"],
  "description": "Prevents self-approval of agent changes in deployment pipelines"
}
```

### Scope Definitions

| Scope | Meaning |
|-------|---------|
| **Tenant** | Roles apply tenant-wide |
| **Environment** | Roles in same Power Platform environment |
| **Same Environment** | Both roles must be in exact same environment |
| **Any Environment** | Roles in any environment trigger conflict |
| **Application** | Roles in same application/agent |

---

## Customization

### Adding Custom Rules

1. Navigate to the SoD Detector app
2. Go to **Conflict Rules** > **New Rule**
3. Complete the rule form:
   - Name: Descriptive rule name
   - Category: Select appropriate category
   - Role A/B: Define conflicting roles
   - Context: Where roles are assigned
   - Severity: Impact level
   - Allow Exception: Whether exceptions permitted

### Rule Syntax for PowerShell Import

```powershell
# Custom rules can be imported using Import-ConflictRules.ps1 with a JSON file:
# .\scripts\Import-ConflictRules.ps1 -Environment "https://your-org.crm.dynamics.com" -RuleFile "custom-rules.json"
```

### Disabling Rules

To disable a rule without deleting, update the `fsi_enabled` field to `false` in the Dataverse `fsi_conflictrule` table, or use the SoD Detector app UI.

---

## Role Mapping

### Entra ID Directory Roles

| Display Name | Role Template ID |
|--------------|------------------|
| Global Administrator | 62e90394-69f5-4237-9190-012177145e10 |
| Privileged Role Administrator | e8611ab8-c189-46e8-94e1-60213ab1f814 |
| Application Administrator | 9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3 |
| Security Administrator | 194ae4cb-b126-40b2-bd5b-6091b380977d |
| Compliance Administrator | 17315797-102d-40b4-93e0-432062caca18 |
| Power Platform Administrator | 11648597-926c-4cf3-9c36-bcebb0ba8dcc |

### Power Platform Environment Roles

| Role Name | Description |
|-----------|-------------|
| System Administrator | Full environment access |
| System Customizer | Customization but not user management |
| Environment Maker | Create resources in environment |
| Basic User | Run apps, minimal create |

### Common Dataverse Security Roles

| Role Name | Typical Scope |
|-----------|---------------|
| Agent Developer | Create/edit Copilot Studio agents |
| Agent Publisher | Publish agents to channels |
| Pipeline Approver | Approve deployment pipeline runs |
| Solution Developer | Create/edit solutions |
| Solution Promoter | Move solutions between environments |

---

## Testing Rules

### Dry Run Mode

Test rules without creating violations:

```powershell
.\scripts\Invoke-SoDScan.ps1 -Environment "https://your-org.crm.dynamics.com" -DryRun -Verbose
```

### Test Specific User

Single-user conflict testing is planned for a future release.
<!-- .\scripts\Test-UserSoD.ps1 -UserPrincipalName "user@contoso.com" -->

### Rule Validation

Rule validation tooling is planned for a future release.
<!-- .\scripts\Test-ConflictRule.ps1 -RuleFile "custom-rules.json" -->

---

## Best Practices

### Rule Design

1. **Be Specific** - Narrow scope prevents false positives
2. **Document Rationale** - Include clear description
3. **Set Appropriate Severity** - Reserve Critical for true blockers
4. **Allow Exceptions** - Most rules should permit documented exceptions
5. **Test First** - Use dry run before enabling

### Maintenance

1. **Review Quarterly** - Ensure rules remain relevant
2. **Track False Positives** - Refine rules with high FP rates
3. **Audit Exceptions** - Ensure exceptions are justified
4. **Update for Changes** - Add rules for new roles/processes

### FSI-Specific Considerations

1. **FINRA 3110** - Supervision roles require separation
2. **SOX 404** - Document all rule rationale for auditors
3. **OCC 2011-12** - Model validation requires independence
4. **Information Barriers** - Research/trading separation rules

---

## Importing Default Rules

```powershell
# Import all default rules
.\scripts\Import-ConflictRules.ps1 -Environment "https://your-org.crm.dynamics.com" -RuleSet "Default"

# Import only Maker/Checker rules
.\scripts\Import-ConflictRules.ps1 -Environment "https://your-org.crm.dynamics.com" -RuleSet "MakerChecker"

# Import from custom file
.\scripts\Import-ConflictRules.ps1 -Environment "https://your-org.crm.dynamics.com" -RuleFile "my-rules.json"
```

---

*Segregation of Duties Detector v1.0.0*
