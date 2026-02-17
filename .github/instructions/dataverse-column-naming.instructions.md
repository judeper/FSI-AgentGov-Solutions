---
applyTo: "**/*.ps1"
---

# Dataverse Column Naming Convention

When writing OData queries, `$select`, `$filter`, `$orderby`, or referencing Dataverse columns in PowerShell scripts, use the **logical name** format.

## The Rule

Dataverse columns have two names:
- **SchemaName** (PascalCase): `fsi_AgentId`, `fsi_EnvironmentName`, `fsi_ViolationType`
- **Logical name** (all-lowercase): `fsi_agentid`, `fsi_environmentname`, `fsi_violationtype`

The logical name is the SchemaName converted to lowercase. Dataverse NEVER inserts underscores between words.

## Examples

```powershell
# CORRECT — logical names (all-lowercase, no word separators)
$select = "fsi_agentid,fsi_environmentname,fsi_violationtype,fsi_detectedat"
$filter = "fsi_violationtype eq 0 and fsi_severity ge 2"
$orderby = "fsi_detectedat desc"

# WRONG — snake_case (Dataverse does NOT use this format)
$select = "fsi_agent_id,fsi_environment_name,fsi_violation_type,fsi_detected_at"
```

## Source of Truth

Each solution's `create_*_dataverse_schema.py` defines the SchemaName for every column. To find the correct logical name, locate the SchemaName and lowercase it.

Generated schema docs at `docs/dataverse-schema.md` list both SchemaName and logical name for every column.
