#!/usr/bin/env python3
"""
FINRA Supervision Workflow - Deployment Script

Creates Dataverse tables, security roles, and initial configuration
for the FINRA Supervision Workflow solution.

Usage:
    python deploy.py --environment-url https://org.crm.dynamics.com --tenant-id <id> --interactive
    python deploy.py --environment-url https://org.crm.dynamics.com --client-id <id> --client-secret <secret>
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone

try:
    import requests
    from msal import PublicClientApplication  # noqa: F401 — validated at import time
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)

from auth import get_access_token


# Dataverse schema definitions
TABLES = {
    "fsi_supervisionqueue": {
        "display_name": "Supervision Queue",
        "plural_name": "Supervision Queue Items",
        "description": "Items requiring supervisory review per FINRA 3110",
        "ownership": "UserOwned",
        "primary_column": "fsi_queuenumber",
        "columns": [
            {"name": "fsi_queuenumber", "type": "AutoNumber", "format": "SUP-{SEQNUM:5}"},
            {"name": "fsi_sourcetype", "type": "Picklist", "options": ["Communication Compliance", "Audit Log", "Manual Entry"], "required": True},
            {"name": "fsi_sourceid", "type": "String", "max_length": 200},
            {"name": "fsi_agentid", "type": "String", "max_length": 100},
            {"name": "fsi_agentname", "type": "String", "max_length": 200, "required": True},
            {"name": "fsi_zone", "type": "Picklist", "options": ["Zone 1 - Personal Productivity", "Zone 2 - Team Collaboration", "Zone 3 - Enterprise Managed"], "required": True},
            {"name": "fsi_tier", "type": "Picklist", "options": ["Tier 1 - Critical", "Tier 2 - Standard", "Tier 3 - Low Risk"], "required": True},
            {"name": "fsi_contentpreview", "type": "Memo", "max_length": 500},
            {"name": "fsi_flaggedreason", "type": "String", "max_length": 500, "required": True},
            {"name": "fsi_state", "type": "Picklist", "options": ["Pending", "In Review", "Approved", "Escalated", "Rejected"], "required": True, "default": 100000000},
            {"name": "fsi_assignedprincipal", "type": "Lookup", "target": "systemuser"},
            {"name": "fsi_queueddate", "type": "DateTime", "required": True},
            {"name": "fsi_sladue", "type": "DateTime", "required": True},
            {"name": "fsi_reviewedby", "type": "Lookup", "target": "systemuser"},
            {"name": "fsi_revieweddate", "type": "DateTime"},
            {"name": "fsi_reviewoutcome", "type": "Picklist", "options": ["Approved", "Rejected", "Escalated"]},
            {"name": "fsi_reviewnotes", "type": "Memo", "max_length": 4000},
        ]
    },
    "fsi_supervisionlog": {
        "display_name": "Supervision Log",
        "plural_name": "Supervision Logs",
        "description": "Immutable audit trail for supervision actions",
        "ownership": "OrganizationOwned",
        "primary_column": "fsi_lognumber",
        "columns": [
            {"name": "fsi_lognumber", "type": "AutoNumber", "format": "LOG-{SEQNUM:6}"},
            {"name": "fsi_queueitem", "type": "Lookup", "target": "fsi_supervisionqueue", "required": True},
            {"name": "fsi_action", "type": "Picklist", "options": ["Queued", "Assigned", "Claimed", "Reviewed", "Approved", "Rejected", "Escalated", "Reassigned", "Closed"], "required": True},
            {"name": "fsi_actor", "type": "String", "max_length": 200, "required": True},
            {"name": "fsi_timestamp", "type": "DateTime", "required": True},
            {"name": "fsi_details", "type": "Memo", "max_length": 4000},
        ]
    },
    "fsi_supervisionconfig": {
        "display_name": "Supervision Config",
        "plural_name": "Supervision Configs",
        "description": "Configuration for supervision rules by zone and tier",
        "ownership": "OrganizationOwned",
        "primary_column": "fsi_name",
        "columns": [
            {"name": "fsi_name", "type": "String", "max_length": 100, "required": True},
            {"name": "fsi_zone", "type": "Picklist", "options": ["Zone 1 - Personal Productivity", "Zone 2 - Team Collaboration", "Zone 3 - Enterprise Managed"], "required": True},
            {"name": "fsi_tier", "type": "Picklist", "options": ["Tier 1 - Critical", "Tier 2 - Standard", "Tier 3 - Low Risk"], "required": True},
            {"name": "fsi_slahours", "type": "Integer", "required": True},
            {"name": "fsi_escalationhours", "type": "Integer", "required": True},
            {"name": "fsi_reviewpercent", "type": "Integer", "required": True},
            {"name": "fsi_defaultprincipal", "type": "Lookup", "target": "systemuser"},
            {"name": "fsi_escalationto", "type": "Lookup", "target": "systemuser"},
            {"name": "fsi_active", "type": "Boolean", "default": True},
        ]
    }
}

SECURITY_ROLES = {
    "FSW Supervisor": {
        "description": "Review assigned queue items",
        "privileges": {
            "fsi_supervisionqueue": {"create": "none", "read": "user", "write": "user", "delete": "none", "append": "user", "appendto": "user"},
            "fsi_supervisionlog": {"create": "organization", "read": "user", "write": "none", "delete": "none"},
            "fsi_supervisionconfig": {"create": "none", "read": "organization", "write": "none", "delete": "none"},
        }
    },
    "FSW Queue Manager": {
        "description": "Manage queue, assign items, configure rules",
        "privileges": {
            "fsi_supervisionqueue": {"create": "organization", "read": "organization", "write": "organization", "delete": "none", "append": "organization", "appendto": "organization", "assign": "organization"},
            "fsi_supervisionlog": {"create": "organization", "read": "organization", "write": "none", "delete": "none"},
            "fsi_supervisionconfig": {"create": "organization", "read": "organization", "write": "organization", "delete": "none"},
        }
    },
    "FSW Admin": {
        "description": "Full access for automation and administration",
        "privileges": {
            "fsi_supervisionqueue": {"create": "organization", "read": "organization", "write": "organization", "delete": "organization", "append": "organization", "appendto": "organization", "assign": "organization"},
            "fsi_supervisionlog": {"create": "organization", "read": "organization", "write": "none", "delete": "none"},
            "fsi_supervisionconfig": {"create": "organization", "read": "organization", "write": "organization", "delete": "organization"},
        }
    },
    "FSW Auditor": {
        "description": "Read-only access for audit and examination",
        "privileges": {
            "fsi_supervisionqueue": {"create": "none", "read": "organization", "write": "none", "delete": "none"},
            "fsi_supervisionlog": {"create": "none", "read": "organization", "write": "none", "delete": "none"},
            "fsi_supervisionconfig": {"create": "none", "read": "organization", "write": "none", "delete": "none"},
        }
    }
}

DEFAULT_CONFIGS = [
    {"name": "Zone1-Tier1", "zone": 100000000, "tier": 100000000, "sla_hours": 24, "escalation_hours": 48, "review_percent": 25},
    {"name": "Zone1-Tier2", "zone": 100000000, "tier": 100000001, "sla_hours": 48, "escalation_hours": 72, "review_percent": 10},
    {"name": "Zone1-Tier3", "zone": 100000000, "tier": 100000002, "sla_hours": 48, "escalation_hours": 72, "review_percent": 5},
    {"name": "Zone2-Tier1", "zone": 100000001, "tier": 100000000, "sla_hours": 8, "escalation_hours": 24, "review_percent": 50},
    {"name": "Zone2-Tier2", "zone": 100000001, "tier": 100000001, "sla_hours": 24, "escalation_hours": 48, "review_percent": 25},
    {"name": "Zone2-Tier3", "zone": 100000001, "tier": 100000002, "sla_hours": 48, "escalation_hours": 72, "review_percent": 10},
    {"name": "Zone3-Tier1", "zone": 100000002, "tier": 100000000, "sla_hours": 4, "escalation_hours": 8, "review_percent": 100},
    {"name": "Zone3-Tier2", "zone": 100000002, "tier": 100000001, "sla_hours": 8, "escalation_hours": 24, "review_percent": 100},
    {"name": "Zone3-Tier3", "zone": 100000002, "tier": 100000002, "sla_hours": 24, "escalation_hours": 48, "review_percent": 100},
]


class DataverseClient:
    """Client for Dataverse Web API operations."""

    def __init__(self, environment_url: str, access_token: str):
        self.base_url = f"{environment_url.rstrip('/')}/api/data/v9.2"
        self.headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
        }

    def _request(self, method: str, endpoint: str, data: dict = None) -> dict:
        """Make HTTP request to Dataverse API with retry for transient errors."""
        url = f"{self.base_url}/{endpoint}"
        max_retries = 3
        for attempt in range(max_retries + 1):
            try:
                response = requests.request(method, url, headers=self.headers, json=data)
            except requests.exceptions.RequestException as exc:
                if attempt < max_retries:
                    wait = 2 ** attempt
                    print(f"  Network error ({exc}), retrying in {wait}s...")
                    time.sleep(wait)
                    continue
                print(f"Error: Network request failed after {max_retries} retries: {exc}")
                return None

            if response.status_code in (429, 502, 503, 504) and attempt < max_retries:
                retry_after = int(response.headers.get("Retry-After", 2 ** attempt))
                print(f"  Transient error {response.status_code}, retrying in {retry_after}s...")
                time.sleep(retry_after)
                continue

            if response.status_code >= 400:
                print(f"Error {response.status_code}: {response.text}")
                return None

            if response.status_code == 204:
                return {"success": True}

            return response.json() if response.text else {"success": True}

    def get_entity_metadata(self, entity_name: str) -> dict:
        """Get entity metadata."""
        return self._request("GET", f"EntityDefinitions(LogicalName='{entity_name}')")

    def create_entity(self, entity_definition: dict) -> dict:
        """Create a new entity."""
        return self._request("POST", "EntityDefinitions", entity_definition)

    def create_attribute(self, entity_name: str, attribute_definition: dict) -> dict:
        """Create a new attribute on an entity."""
        return self._request(
            "POST",
            f"EntityDefinitions(LogicalName='{entity_name}')/Attributes",
            attribute_definition
        )

    def create_relationship(self, relationship_definition: dict) -> dict:
        """Create a one-to-many relationship (required for lookup columns)."""
        return self._request("POST", "RelationshipDefinitions", relationship_definition)

    def create_record(self, entity_set: str, data: dict) -> dict:
        """Create a new record."""
        return self._request("POST", entity_set, data)


COLUMN_DISPLAY_NAMES = {
    "fsi_queuenumber": "Queue Number",
    "fsi_sourcetype": "Source Type",
    "fsi_sourceid": "Source ID",
    "fsi_agentid": "Agent ID",
    "fsi_agentname": "Agent Name",
    "fsi_zone": "Zone",
    "fsi_tier": "Tier",
    "fsi_contentpreview": "Content Preview",
    "fsi_flaggedreason": "Flagged Reason",
    "fsi_state": "State",
    "fsi_assignedprincipal": "Assigned Principal",
    "fsi_queueddate": "Queued Date",
    "fsi_sladue": "SLA Due",
    "fsi_reviewedby": "Reviewed By",
    "fsi_revieweddate": "Reviewed Date",
    "fsi_reviewoutcome": "Review Outcome",
    "fsi_reviewnotes": "Review Notes",
    "fsi_lognumber": "Log Number",
    "fsi_queueitem": "Queue Item",
    "fsi_action": "Action",
    "fsi_actor": "Actor",
    "fsi_timestamp": "Timestamp",
    "fsi_details": "Details",
    "fsi_name": "Name",
    "fsi_slahours": "SLA Hours",
    "fsi_escalationhours": "Escalation Hours",
    "fsi_reviewpercent": "Review Percent",
    "fsi_defaultprincipal": "Default Principal",
    "fsi_escalationto": "Escalation To",
    "fsi_active": "Active",
}


def _build_attribute_definition(col: dict) -> dict:
    """Build Dataverse attribute definition from column config."""
    display_name = COLUMN_DISPLAY_NAMES.get(col["name"], col["name"])
    label = {
        "@odata.type": "Microsoft.Dynamics.CRM.Label",
        "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                             "Label": display_name, "LanguageCode": 1033}]
    }
    req_level = "ApplicationRequired" if col.get("required") else "None"
    base = {
        "SchemaName": col["name"],
        "DisplayName": label,
        "RequiredLevel": {"Value": req_level},
    }

    col_type = col["type"]
    if col_type == "String":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        base["MaxLength"] = col.get("max_length", 100)
        base["FormatName"] = {"Value": "Text"}
    elif col_type == "Memo":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        base["MaxLength"] = col.get("max_length", 4000)
    elif col_type == "Integer":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        base["MinValue"] = 0
        base["MaxValue"] = 2147483647
    elif col_type == "Boolean":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        base["DefaultValue"] = col.get("default", False)
    elif col_type == "DateTime":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        base["Format"] = "DateAndTime"
    elif col_type == "AutoNumber":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        base["AutoNumberFormat"] = col.get("format", "")
        base["MaxLength"] = 20
        base["FormatName"] = {"Value": "Text"}
    elif col_type == "Picklist":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        options = col.get("options", [])
        base["OptionSet"] = {
            "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
            "IsGlobal": False,
            "Options": [
                {"Value": 100000000 + i, "Label": {
                    "@odata.type": "Microsoft.Dynamics.CRM.Label",
                    "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                                         "Label": opt, "LanguageCode": 1033}]
                }} for i, opt in enumerate(options)
            ]
        }
        if "default" in col:
            base["DefaultFormValue"] = col["default"]
    elif col_type == "Lookup":
        base["@odata.type"] = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
        base["Targets"] = [col.get("target", "")]
    else:
        return None

    return base


def deploy_tables(client: DataverseClient, dry_run: bool = False) -> None:
    """Deploy Dataverse tables."""
    print("\n" + "=" * 60)
    print("Deploying Dataverse Tables")
    print("=" * 60)

    for table_name, table_def in TABLES.items():
        print(f"\nProcessing table: {table_name}")

        # Check if table exists
        existing = client.get_entity_metadata(table_name)

        if existing and "LogicalName" in existing:
            print(f"  Table {table_name} already exists, skipping creation")
            continue

        if dry_run:
            print(f"  [DRY RUN] Would create table: {table_name}")
            print(f"    Display Name: {table_def['display_name']}")
            print(f"    Columns: {len(table_def['columns'])}")
            continue

        # Build the primary name attribute inline so Dataverse uses it
        # instead of auto-generating a default primary column
        primary_col_name = table_def["primary_column"]
        primary_col = next(c for c in table_def["columns"] if c["name"] == primary_col_name)
        primary_attr = _build_attribute_definition(primary_col)
        primary_attr["IsPrimaryName"] = True

        # Create entity definition with primary attribute embedded
        entity_def = {
            "SchemaName": table_name,
            "DisplayName": {"@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": table_def["display_name"], "LanguageCode": 1033}]},
            "DisplayCollectionName": {"@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": table_def["plural_name"], "LanguageCode": 1033}]},
            "Description": {"@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": table_def["description"], "LanguageCode": 1033}]},
            "OwnershipType": table_def["ownership"],
            "PrimaryNameAttribute": primary_col_name,
            "HasNotes": False,
            "HasActivities": False,
            "Attributes": [primary_attr],
        }

        result = client.create_entity(entity_def)
        if result:
            print(f"  Created table: {table_name}")
        else:
            print(f"  Failed to create table: {table_name}")
            continue

        # Create columns (skip primary column — already created inline)
        for col in table_def["columns"]:
            if col["name"] == primary_col_name:
                print(f"    Skipping column {col['name']} (created inline as primary)")
                continue

            print(f"    Creating column: {col['name']}")

            if col["type"] == "Lookup":
                # Lookup columns must be created via RelationshipDefinitions
                display_name = COLUMN_DISPLAY_NAMES.get(col["name"], col["name"])
                label = {
                    "@odata.type": "Microsoft.Dynamics.CRM.Label",
                    "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                                         "Label": display_name, "LanguageCode": 1033}]
                }
                req_level = "ApplicationRequired" if col.get("required") else "None"
                relationship_def = {
                    "@odata.type": "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
                    "SchemaName": f"{table_name}_{col['name']}",
                    "ReferencedEntity": col.get("target", ""),
                    "ReferencingEntity": table_name,
                    "Lookup": {
                        "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
                        "SchemaName": col["name"],
                        "DisplayName": label,
                        "RequiredLevel": {"Value": req_level},
                    }
                }
                attr_result = client.create_relationship(relationship_def)
            else:
                attr_def = _build_attribute_definition(col)
                if attr_def:
                    attr_result = client.create_attribute(table_name, attr_def)
                else:
                    attr_result = None

            if attr_result:
                print(f"      Created column: {col['name']}")
            else:
                print(f"      Failed to create column: {col['name']}")


def deploy_security_roles(client: DataverseClient, dry_run: bool = False) -> None:
    """Deploy security roles."""
    print("\n" + "=" * 60)
    print("Deploying Security Roles")
    print("=" * 60)

    for role_name, role_def in SECURITY_ROLES.items():
        print(f"\nProcessing role: {role_name}")

        if dry_run:
            print(f"  [DRY RUN] Would create role: {role_name}")
            print(f"    Description: {role_def['description']}")
            for entity, privs in role_def["privileges"].items():
                print(f"    {entity}: {privs}")
            continue

        # Note: Security role creation via Web API is complex
        # In production, use XrmTooling or solution import
        print(f"  Security role creation requires manual setup or solution import")
        print(f"  See docs/security-roles.md for privilege matrix")


def deploy_default_configs(client: DataverseClient, dry_run: bool = False) -> None:
    """Deploy default supervision configuration."""
    print("\n" + "=" * 60)
    print("Deploying Default Configuration")
    print("=" * 60)

    for config in DEFAULT_CONFIGS:
        print(f"\nProcessing config: {config['name']}")

        if dry_run:
            print(f"  [DRY RUN] Would create config: {config['name']}")
            print(f"    Zone: {config['zone']}, Tier: {config['tier']}")
            print(f"    SLA: {config['sla_hours']}h, Escalation: {config['escalation_hours']}h")
            print(f"    Review %: {config['review_percent']}")
            continue

        # Check for existing config to ensure idempotency
        existing = client._request(
            "GET",
            f"fsi_supervisionconfigs?$filter=fsi_name eq '{config['name']}'&$select=fsi_name"
        )
        if existing and existing.get("value"):
            print(f"  Config {config['name']} already exists, skipping creation")
            continue

        record = {
            "fsi_name": config["name"],
            "fsi_zone": config["zone"],
            "fsi_tier": config["tier"],
            "fsi_slahours": config["sla_hours"],
            "fsi_escalationhours": config["escalation_hours"],
            "fsi_reviewpercent": config["review_percent"],
            "fsi_active": True,
        }

        result = client.create_record("fsi_supervisionconfigs", record)
        if result:
            print(f"  Created config: {config['name']}")
        else:
            print(f"  Failed to create config: {config['name']}")


def main():
    parser = argparse.ArgumentParser(description="Deploy FINRA Supervision Workflow solution")
    parser.add_argument("--environment-url", required=True, help="Dataverse environment URL")
    parser.add_argument("--tenant-id", required=True, help="Azure AD tenant ID")
    parser.add_argument("--client-id", help="Service principal client ID")
    parser.add_argument("--client-secret", help="Service principal client secret (prefer FSW_CLIENT_SECRET env var)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive authentication")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without deploying")
    parser.add_argument("--tables-only", action="store_true", help="Deploy only tables")
    parser.add_argument("--roles-only", action="store_true", help="Deploy only security roles")
    parser.add_argument("--config-only", action="store_true", help="Deploy only default configuration")

    args = parser.parse_args()

    print("=" * 60)
    print("FINRA Supervision Workflow - Deployment Script")
    print("=" * 60)
    print(f"Environment: {args.environment_url}")
    print(f"Tenant: {args.tenant_id}")
    print(f"Mode: {'DRY RUN' if args.dry_run else 'DEPLOY'}")
    print(f"Timestamp: {datetime.now(timezone.utc).isoformat()}")

    # Resolve client secret from env var or CLI arg
    client_secret = args.client_secret or os.environ.get("FSW_CLIENT_SECRET")
    if args.client_secret:
        print("Warning: --client-secret on CLI is visible in process lists. Prefer FSW_CLIENT_SECRET env var.",
              file=sys.stderr)

    # Authenticate
    print("\nAuthenticating...")
    if args.interactive:
        access_token = get_access_token(
            args.tenant_id,
            interactive=True,
            environment_url=args.environment_url
        )
    elif args.client_id and client_secret:
        access_token = get_access_token(
            args.tenant_id,
            client_id=args.client_id,
            client_secret=client_secret,
            environment_url=args.environment_url
        )
    else:
        print("Error: Specify --interactive or provide --client-id and --client-secret")
        sys.exit(1)

    print("Authentication successful")

    # Initialize client
    client = DataverseClient(args.environment_url, access_token)

    # Deploy components
    deploy_all = not (args.tables_only or args.roles_only or args.config_only)

    if deploy_all or args.tables_only:
        deploy_tables(client, args.dry_run)

    if deploy_all or args.roles_only:
        deploy_security_roles(client, args.dry_run)

    if deploy_all or args.config_only:
        deploy_default_configs(client, args.dry_run)

    print("\n" + "=" * 60)
    print("Deployment Complete" if not args.dry_run else "Dry Run Complete")
    print("=" * 60)

    if not args.dry_run:
        print("\nNext steps:")
        print("1. Create security roles manually (see docs/security-roles.md)")
        print("2. Create Power Automate flows (see docs/flow-configuration.md)")
        print("3. Configure Communication Compliance (see docs/communication-compliance-setup.md)")
        print("4. Deploy Power BI dashboard (see docs/power-bi-setup.md)")


if __name__ == "__main__":
    main()
