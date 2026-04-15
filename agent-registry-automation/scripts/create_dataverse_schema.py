#!/usr/bin/env python3
"""Create Dataverse schema for Agent Registry Automation.

Deploys four tables (AgentInventory, RegistrationRequest,
AgentComplianceEvent, OwnershipAudit) with shared and solution-specific
option sets. All operations are idempotent.

Tables:
  - fsi_AgentInventory (UserOwned): Master agent registry
  - fsi_RegistrationRequest (UserOwned): Registration request tracking
  - fsi_AgentComplianceEvent (OrganizationOwned): Immutable compliance event log
  - fsi_OwnershipAudit (OrganizationOwned): Ownership change audit trail
"""

import argparse
import os
import sys
from typing import Optional

from ara_client import ARAClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Shared Option Sets (reuse existing ACV option sets — existence check first)
# =============================================================================

SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "name": "fsi_acv_zone",
        "options": [
            ("Unclassified", 100000000),
            ("Zone 1", 100000001),
            ("Zone 2", 100000002),
            ("Zone 3", 100000003),
        ],
    },
}

# =============================================================================
# ARA-Specific Option Sets
# =============================================================================

ARA_OPTIONSETS = {
    "fsi_ara_registrationstatus": {
        "name": "fsi_ara_registrationstatus",
        "options": [
            ("Unregistered", 100000000),
            ("PendingApproval", 100000001),
            ("Registered", 100000002),
            ("Rejected", 100000003),
            ("Decommissioned", 100000004),
        ],
    },
    "fsi_ara_publishedstatus": {
        "name": "fsi_ara_publishedstatus",
        "options": [
            ("Published", 100000000),
            ("Draft", 100000001),
            ("Quarantined", 100000002),
            ("Disabled", 100000003),
        ],
    },
    "fsi_ara_riskrating": {
        "name": "fsi_ara_riskrating",
        "options": [
            ("Low", 100000000),
            ("Medium", 100000001),
            ("High", 100000002),
            ("Critical", 100000003),
        ],
    },
    "fsi_ara_eventtype": {
        "name": "fsi_ara_eventtype",
        "options": [
            ("Discovered", 100000000),
            ("Registered", 100000001),
            ("Approved", 100000002),
            ("Rejected", 100000003),
            ("Quarantined", 100000004),
            ("SLA_Escalated", 100000005),
            ("OrphanDetected", 100000006),
            ("OwnerChanged", 100000007),
            ("Decommissioned", 100000008),
            ("EntraSynced", 100000009),
        ],
    },
    "fsi_ara_approvalstatus": {
        "name": "fsi_ara_approvalstatus",
        "options": [
            ("Pending", 100000000),
            ("Approved", 100000001),
            ("Rejected", 100000002),
            ("Escalated", 100000003),
            ("Expired", 100000004),
        ],
    },
}


# =============================================================================
# Column Definition Helpers
# =============================================================================


def _label(text: str) -> dict:
    """Build a Dataverse Label structure."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.Label",
        "LocalizedLabels": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                "Label": text,
                "LanguageCode": 1033,
            }
        ],
    }


def _string_col(
    schema_name: str, display: str, max_length: int, required: bool = True,
    description: str = "",
) -> dict:
    """Build a string column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "MaxLength": max_length,
        "FormatName": {"Value": "Text"},
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _memo_col(
    schema_name: str, display: str, max_length: int,
    description: str = "",
) -> dict:
    """Build a memo (multiline text) column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "MaxLength": max_length,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _integer_col(
    schema_name: str, display: str, required: bool = True,
    description: str = "",
) -> dict:
    """Build an integer column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "MinValue": 0,
        "MaxValue": 2147483647,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _boolean_col(
    schema_name: str, display: str, default: bool = False,
    description: str = "",
) -> dict:
    """Build a boolean column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {
                "Value": 1,
                "Label": _label("Yes"),
            },
            "FalseOption": {
                "Value": 0,
                "Label": _label("No"),
            },
        },
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _datetime_col(
    schema_name: str, display: str, required: bool = True,
    description: str = "",
) -> dict:
    """Build a datetime column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "Format": "DateAndTime",
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _picklist_col(
    schema_name: str, display: str, global_optionset_name: str,
    required: bool = True, description: str = "",
) -> dict:
    """Build a picklist column bound to a global option set."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "OptionSet": None,
        "GlobalOptionSet@odata.bind": (
            f"/GlobalOptionSetDefinitions(Name='{global_optionset_name}')"
        ),
    }
    if description:
        defn["Description"] = _label(description)
    return defn


# =============================================================================
# Table Column Definitions
# =============================================================================

INVENTORY_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Copilot Studio bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100,
                description="Power Platform environment ID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500,
                description="Environment display name"),
    _string_col("fsi_AgentEndpointUrl", "Agent Endpoint URL", 2000,
                required=False,
                description="Bot Framework endpoint URL"),
    _picklist_col("fsi_RegistrationStatus", "Registration Status",
                  "fsi_ara_registrationstatus",
                  description="Agent registration lifecycle status"),
    _picklist_col("fsi_PublishedStatus", "Published Status",
                  "fsi_ara_publishedstatus",
                  description="Agent published state"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _picklist_col("fsi_RiskRating", "Risk Rating", "fsi_ara_riskrating",
                  required=False,
                  description="Agent risk rating"),
    _string_col("fsi_OwnerUpn", "Owner UPN", 200,
                description="Agent owner user principal name"),
    _string_col("fsi_OwnerDisplayName", "Owner Display Name", 500,
                required=False,
                description="Owner display name"),
    _boolean_col("fsi_IsOrphaned", "Is Orphaned", default=False,
                 description="Whether the agent has no active owner"),
    _string_col("fsi_EntraRegistryStatus", "Entra Registry Status", 200,
                required=False,
                description="Microsoft Entra Agent Registry sync status"),
    _datetime_col("fsi_LastScannedAt", "Last Scanned At", required=False,
                  description="When the agent was last discovered by scan"),
    _datetime_col("fsi_RegisteredAt", "Registered At", required=False,
                  description="When the agent was registered"),
    _string_col("fsi_ApprovedBy", "Approved By", 200, required=False,
                description="Approver UPN"),
    _memo_col("fsi_Notes", "Notes", 10000,
              description="Notes and comments"),
    _memo_col("fsi_RawJson", "Raw JSON", 100000,
              description="Full API response snapshot"),
]

REGISTRATION_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="References fsi_agentinventory agent"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100,
                description="Power Platform environment ID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _datetime_col("fsi_RequestDate", "Request Date",
                  description="When registration request was submitted"),
    _string_col("fsi_RequestedBy", "Requested By", 200,
                description="Requester UPN"),
    _picklist_col("fsi_ApprovalStatus", "Approval Status",
                  "fsi_ara_approvalstatus",
                  description="Registration approval status"),
    _string_col("fsi_ApprovedBy", "Approved By", 200, required=False,
                description="Approver UPN"),
    _datetime_col("fsi_ApprovedAt", "Approved At", required=False,
                  description="When approval was granted"),
    _datetime_col("fsi_SlaDeadline", "SLA Deadline",
                  description="SLA deadline for approval decision"),
    _string_col("fsi_EscalationTarget", "Escalation Target", 200,
                required=False,
                description="Skip-level escalation approver UPN"),
    _datetime_col("fsi_EscalationDate", "Escalation Date", required=False,
                  description="When the request was escalated"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _picklist_col("fsi_RiskRating", "Risk Rating", "fsi_ara_riskrating",
                  required=False,
                  description="Agent risk rating"),
    _memo_col("fsi_Justification", "Justification", 10000,
              description="Business justification for registration"),
    _memo_col("fsi_RejectionReason", "Rejection Reason", 5000,
              description="Reason for rejection"),
]

COMPLIANCE_EVENT_COLUMNS = [
    _picklist_col("fsi_EventType", "Event Type", "fsi_ara_eventtype",
                  description="Event classification"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Agent bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100,
                description="Power Platform environment ID"),
    _string_col("fsi_AgentName", "Agent Name", 500, required=False,
                description="Agent display name"),
    _datetime_col("fsi_EventTimestamp", "Event Timestamp",
                  description="When the event occurred"),
    _string_col("fsi_ActorUpn", "Actor UPN", 200, required=False,
                description="UPN of person or system that performed the action"),
    _memo_col("fsi_Details", "Details", 50000,
              description="JSON event details"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone", required=False,
                  description="Zone classification"),
    _string_col("fsi_FrameworkVersion", "Framework Version", 50,
                required=False,
                description="FSI-AgentGov version tag"),
]

OWNERSHIP_AUDIT_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Agent bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100,
                description="Power Platform environment ID"),
    _string_col("fsi_PreviousOwnerUpn", "Previous Owner UPN", 200,
                description="Previous owner user principal name"),
    _string_col("fsi_NewOwnerUpn", "New Owner UPN", 200,
                description="New owner user principal name"),
    _string_col("fsi_ChangeReason", "Change Reason", 500, required=False,
                description="Reason for ownership change"),
    _datetime_col("fsi_ChangedAt", "Changed At",
                  description="When the ownership change occurred"),
    _string_col("fsi_ChangedBy", "Changed By", 200, required=False,
                description="System or user UPN that performed the change"),
    _boolean_col("fsi_IsOrphanReassignment", "Is Orphan Reassignment",
                 default=False,
                 description="Whether this was an orphan agent reassignment"),
    _memo_col("fsi_Details", "Details", 10000,
              description="Additional context"),
]


# =============================================================================
# Table Definitions
# =============================================================================

TABLES = {
    "fsi_agentinventory": {
        "schema_name": "fsi_AgentInventory",
        "display": "Agent Inventory",
        "plural": "Agent Inventory",
        "description": (
            "Master agent registry for governance tracking and lifecycle management"
        ),
        "ownership": "UserOwned",
        "columns": INVENTORY_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_registrationrequest": {
        "schema_name": "fsi_RegistrationRequest",
        "display": "Registration Request",
        "plural": "Registration Requests",
        "description": (
            "Registration request tracking with SLA-driven approval workflow"
        ),
        "ownership": "UserOwned",
        "columns": REGISTRATION_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_agentcomplianceevent": {
        "schema_name": "fsi_AgentComplianceEvent",
        "display": "Agent Compliance Event",
        "plural": "Agent Compliance Events",
        "description": (
            "Immutable compliance event log for regulatory evidence "
            "(supports compliance with FINRA 4511, SEC 17a-3)"
        ),
        "ownership": "OrganizationOwned",
        "columns": COMPLIANCE_EVENT_COLUMNS,
        "entity_set_name": "fsi_agentcomplianceevents",
    },
    "fsi_ownershipaudit": {
        "schema_name": "fsi_OwnershipAudit",
        "display": "Ownership Audit",
        "plural": "Ownership Audits",
        "description": (
            "Ownership change audit trail for agent lifecycle governance"
        ),
        "ownership": "OrganizationOwned",
        "columns": OWNERSHIP_AUDIT_COLUMNS,
        "entity_set_name": None,
    },
}

# Alternate key definition for fsi_agentinventory
ALTERNATE_KEY = {
    "entity": "fsi_agentinventory",
    "schema_name": "fsi_AgentEnvUniqueKey",
    "display": "Agent-Environment Unique Key",
    "key_columns": ["fsi_agentid", "fsi_environmentid"],
}


# =============================================================================
# Deployment Functions
# =============================================================================


def create_shared_optionsets(client: ARAClient, dry_run: bool = False) -> None:
    """Create or verify shared global option sets.

    These option sets are shared with ACV and other solutions.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating/Verifying Shared Option Sets]")

    for os_name, os_def in SHARED_OPTIONSETS.items():
        client.create_option_set(os_def["name"], os_def["options"])


def create_ara_optionsets(client: ARAClient, dry_run: bool = False) -> None:
    """Create ARA-specific global option sets.

    These option sets are unique to Agent Registry Automation.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating ARA Option Sets]")

    for os_name, os_def in ARA_OPTIONSETS.items():
        client.create_option_set(os_def["name"], os_def["options"])


def create_table_with_columns(
    client: ARAClient,
    table_name: str,
    table_def: dict,
    columns: list[dict],
    dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent).

    Args:
        client: ARAClient instance
        table_name: Logical table name
        table_def: Table definition dict
        columns: List of column definitions
        dry_run: Preview mode flag
    """
    logical_name = table_name.lower()

    # Check if table already exists
    if client.check_table_exists(logical_name):
        print(f"  {logical_name}: already exists, skipping table creation")
    else:
        # Build entity definition
        definition = {
            "@odata.type": "#Microsoft.Dynamics.CRM.EntityMetadata",
            "SchemaName": table_def["schema_name"],
            "DisplayName": _label(table_def["display"]),
            "DisplayCollectionName": _label(table_def["plural"]),
            "Description": _label(table_def["description"]),
            "OwnershipType": table_def["ownership"],
            "IsActivity": False,
            "HasActivities": False,
            "HasNotes": False,
            "IsAuditEnabled": {"Value": True, "CanBeChanged": True},
            "PrimaryNameAttribute": "fsi_name",
            "Attributes": [
                {
                    "@odata.type": (
                        "#Microsoft.Dynamics.CRM.StringAttributeMetadata"
                    ),
                    "SchemaName": "fsi_Name",
                    "DisplayName": _label(
                        f"{table_def['display']} ID"
                    ),
                    "Description": _label("Primary name attribute"),
                    "RequiredLevel": {"Value": "ApplicationRequired"},
                    "MaxLength": 500,
                    "FormatName": {"Value": "Text"},
                },
            ],
        }

        # Set explicit EntitySetName if specified
        if table_def.get("entity_set_name"):
            definition["EntitySetName"] = table_def["entity_set_name"]

        client.create_entity(definition)
        print(f"  {logical_name}: created")

    # Create columns
    print(f"  {logical_name} columns:")
    for col in columns:
        col_schema = col["SchemaName"]
        col_type = col.get("@odata.type", "Unknown").split(".")[-1]
        client.create_column(logical_name, col_schema, col_type, col)


def create_alternate_key(client: ARAClient, dry_run: bool = False) -> None:
    """Create the alternate key on fsi_agentinventory (idempotent).

    The key enforces uniqueness on (fsi_agentid, fsi_environmentid) to
    prevent duplicate agent registrations within the same environment.
    """
    print("\n[Creating Alternate Key]")

    entity = ALTERNATE_KEY["entity"]
    key_name = ALTERNATE_KEY["schema_name"]

    # Idempotent check — query existing keys
    if dry_run or client.dry_run:
        print(f"  [DRY-RUN] Would create alternate key: {key_name} on {entity}")
        return

    try:
        url = (
            f"{client.base_url}/EntityDefinitions"
            f"(LogicalName='{entity}')/Keys"
        )
        resp = client.session.get(url, headers=client._get_headers())
        resp.raise_for_status()
        existing_keys = resp.json().get("value", [])

        for key in existing_keys:
            if key.get("SchemaName", "").lower() == key_name.lower():
                print(f"  {key_name}: already exists, skipping")
                return
    except Exception:
        pass  # If check fails, attempt creation anyway

    # Create the alternate key
    key_definition = {
        "SchemaName": key_name,
        "DisplayName": _label(ALTERNATE_KEY["display"]),
        "KeyAttributes": ALTERNATE_KEY["key_columns"],
    }

    try:
        url = (
            f"{client.base_url}/EntityDefinitions"
            f"(LogicalName='{entity}')/Keys"
        )
        resp = client.session.post(
            url, headers=client._get_headers(), json=key_definition
        )
        resp.raise_for_status()
        print(f"  {key_name}: created on {entity}")
    except Exception as e:
        print(f"  {key_name}: creation failed — {e}")
        print("    Alternate keys may take a few minutes to activate.")
        print("    Verify status in Power Platform admin center.")


def create_schema(client: ARAClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment.

    Order: shared option sets → ARA option sets → tables → columns →
    alternate key. All operations are idempotent — safe to re-run.
    """
    print("=" * 60)
    print("ARA Dataverse Schema Deployment")
    print("  Agent Registry Automation")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Shared option sets (must exist before tables reference them)
    create_shared_optionsets(client, dry_run)

    # Step 2: ARA-specific option sets
    create_ara_optionsets(client, dry_run)

    # Step 3: Tables and columns
    print("\n[Creating Tables and Columns]")
    for table_name, table_def in TABLES.items():
        print(f"\n  --- {table_def['display']} ({table_def['ownership']}) ---")
        create_table_with_columns(
            client, table_name, table_def, table_def["columns"], dry_run
        )

    # Step 4: Alternate key on fsi_agentinventory
    create_alternate_key(client, dry_run)

    # Summary
    total_optionsets = len(SHARED_OPTIONSETS) + len(ARA_OPTIONSETS)
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print(f"  Option sets: {total_optionsets}")
    print(f"  Tables: {len(TABLES)}")
    total_cols = sum(len(t["columns"]) for t in TABLES.values())
    print(f"  Columns: {total_cols}")
    print(f"  Alternate keys: 1")
    print("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for schema deployment."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Agent Registry Automation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_dataverse_schema.py \\\n"
            "    --tenant-id $ARA_TENANT_ID \\\n"
            "    --client-id $ARA_CLIENT_ID \\\n"
            "    --client-secret $ARA_CLIENT_SECRET \\\n"
            "    --environment-url $ARA_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ARA_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set ARA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ARA_CLIENT_ID"),
        help="Service principal app ID (or set ARA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ARA_CLIENT_SECRET"),
        help="Service principal secret (or set ARA_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ARA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ARA_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without making changes",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id:
        print("ERROR: --tenant-id or ARA_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or ARA_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = ARAClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
