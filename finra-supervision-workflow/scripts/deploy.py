#!/usr/bin/env python3
"""
FINRA Supervision Workflow - Deployment Script

Deploys Dataverse table shells and seeds default configuration.
Column creation and security roles require manual setup (see docs/).

Usage:
    python deploy.py --environment-url https://org.crm.dynamics.com --tenant-id <id>
    python deploy.py --environment-url https://org.crm.dynamics.com --tenant-id <id> --managed-identity-client-id <id>
    python deploy.py --environment-url https://org.crm.dynamics.com --tenant-id <id> --interactive
    # legacy: dev-only — replace with managed identity in production
    python deploy.py --environment-url https://org.crm.dynamics.com --tenant-id <id> --client-id <id> --client-secret <secret>
"""

import argparse
import os
import re
import sys
import time
from datetime import datetime, timezone

try:
    import requests
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)

# Import shared authentication module
_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)
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
            {"name": "fsi_state", "type": "Picklist", "options": ["Pending", "In Review", "Approved", "Escalated", "Rejected"], "required": True, "default": 1},
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
        "description": "Append-only audit trail for supervision actions",
        "ownership": "OrganizationOwned",
        "primary_column": "fsi_lognumber",
        "columns": [
            {"name": "fsi_lognumber", "type": "AutoNumber", "format": "LOG-{SEQNUM:6}"},
            {"name": "fsi_queueitem", "type": "Lookup", "target": "fsi_supervisionqueue", "required": True},
            {"name": "fsi_action", "type": "Picklist", "options": ["Queued", "Assigned", "Claimed", "Reviewed", "Approved", "Rejected", "Escalated", "Reassigned", "Closed"], "required": True},
            {"name": "fsi_actor", "type": "Lookup", "target": "systemuser", "required": True},
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
            "fsi_supervisionlog": {"create": "none", "read": "organization", "write": "none", "delete": "none"},
            "fsi_supervisionconfig": {"create": "none", "read": "organization", "write": "none", "delete": "none"},
        }
    },
    "FSW Queue Manager": {
        "description": "Manage queue, assign items, configure rules",
        "privileges": {
            "fsi_supervisionqueue": {"create": "organization", "read": "organization", "write": "organization", "delete": "none", "assign": "organization", "append": "organization", "appendto": "organization"},
            "fsi_supervisionlog": {"create": "organization", "read": "organization", "write": "none", "delete": "none"},
            "fsi_supervisionconfig": {"create": "organization", "read": "organization", "write": "organization", "delete": "none"},
        }
    },
    "FSW Admin": {
        "description": "Full access for automation and administration",
        "privileges": {
            "fsi_supervisionqueue": {"create": "organization", "read": "organization", "write": "organization", "delete": "none", "assign": "organization", "append": "organization", "appendto": "organization"},
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
    {"name": "Zone1-Tier1", "zone": 1, "tier": 1, "sla_hours": 24, "escalation_hours": 48, "review_percent": 25},
    {"name": "Zone1-Tier2", "zone": 1, "tier": 2, "sla_hours": 48, "escalation_hours": 72, "review_percent": 10},
    {"name": "Zone1-Tier3", "zone": 1, "tier": 3, "sla_hours": 48, "escalation_hours": 72, "review_percent": 5},
    {"name": "Zone2-Tier1", "zone": 2, "tier": 1, "sla_hours": 8, "escalation_hours": 24, "review_percent": 50},
    {"name": "Zone2-Tier2", "zone": 2, "tier": 2, "sla_hours": 24, "escalation_hours": 48, "review_percent": 25},
    {"name": "Zone2-Tier3", "zone": 2, "tier": 3, "sla_hours": 48, "escalation_hours": 72, "review_percent": 10},
    {"name": "Zone3-Tier1", "zone": 3, "tier": 1, "sla_hours": 4, "escalation_hours": 8, "review_percent": 100},
    {"name": "Zone3-Tier2", "zone": 3, "tier": 2, "sla_hours": 8, "escalation_hours": 24, "review_percent": 100},
    {"name": "Zone3-Tier3", "zone": 3, "tier": 3, "sla_hours": 24, "escalation_hours": 48, "review_percent": 100},
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
        """Make HTTP request to Dataverse API with retry for transient failures."""
        url = f"{self.base_url}/{endpoint}"
        max_retries = 3
        for attempt in range(max_retries + 1):
            try:
                response = requests.request(method, url, headers=self.headers, json=data, timeout=30)
            except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
                if attempt < max_retries:
                    retry_after = 2 ** attempt * 5
                    print(f"  Connection error: {exc}, retrying in {retry_after}s (attempt {attempt + 1}/{max_retries})...")
                    time.sleep(retry_after)
                    continue
                raise SystemExit(f"Request failed after {max_retries} retries: {exc}") from exc
            if response.status_code in (429, 503) and attempt < max_retries:
                raw_retry = response.headers.get("Retry-After")
                try:
                    retry_after = int(raw_retry) if raw_retry is not None else 2 ** attempt * 5
                except (ValueError, TypeError):
                    retry_after = 2 ** attempt * 5
                print(f"  Received {response.status_code}, retrying in {retry_after}s (attempt {attempt + 1}/{max_retries})...")
                time.sleep(retry_after)
                continue
            break

        if response.status_code >= 400:
            status = response.status_code
            if status == 404:
                print(f"Not found (404): {endpoint} - resource does not exist yet")
            else:
                print(f"Error {status}: {response.text}")
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

    def create_record(self, entity_set: str, data: dict) -> dict:
        """Create a new record."""
        return self._request("POST", entity_set, data)


def deploy_tables(client: DataverseClient, dry_run: bool = False) -> int:
    """Deploy Dataverse tables. Returns number of failures."""
    print("\n" + "=" * 60)
    print("Deploying Dataverse Tables")
    print("=" * 60)

    failures = 0
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

        # Create entity definition
        entity_def = {
            "SchemaName": table_name,
            "DisplayName": {"@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": table_def["display_name"], "LanguageCode": 1033}]},
            "DisplayCollectionName": {"@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": table_def["plural_name"], "LanguageCode": 1033}]},
            "Description": {"@odata.type": "Microsoft.Dynamics.CRM.Label", "LocalizedLabels": [{"@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel", "Label": table_def["description"], "LanguageCode": 1033}]},
            "OwnershipType": table_def["ownership"],
            "HasNotes": False,
            "HasActivities": False,
        }

        result = client.create_entity(entity_def)
        if result:
            print(f"  Created table: {table_name}")
        else:
            print(f"  Failed to create table: {table_name}")
            failures += 1
            continue

        # Column creation is intentionally skipped — the Dataverse Web API requires
        # type-specific attribute definitions (PicklistAttributeMetadata, LookupAttributeMetadata,
        # etc.) with global option set references that vary per environment.  Create columns
        # manually in Power Apps maker portal or via solution import.
        # See docs/dataverse-schema.md for the full column specification.
        for col in table_def["columns"]:
            print(f"    [SKIPPED] Column: {col['name']} (manual creation required — see docs/dataverse-schema.md)")

    return failures


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
        print("  Security role creation requires manual setup or solution import")
        print("  See docs/security-roles.md for privilege matrix")


def deploy_default_configs(client: DataverseClient, dry_run: bool = False) -> int:
    """Deploy default supervision configuration. Returns number of failures."""
    print("\n" + "=" * 60)
    print("Deploying Default Configuration")
    print("=" * 60)

    failures = 0
    for config in DEFAULT_CONFIGS:
        print(f"\nProcessing config: {config['name']}")

        review_percent = config["review_percent"]
        if not (0 <= review_percent <= 100):
            print(f"  Error: review_percent must be 0-100, got {review_percent}")
            failures += 1
            continue

        sla_hours = config["sla_hours"]
        escalation_hours = config["escalation_hours"]
        if sla_hours <= 0 or escalation_hours <= 0:
            print(f"  Error: sla_hours and escalation_hours must be positive, got sla_hours={sla_hours}, escalation_hours={escalation_hours}")
            failures += 1
            continue
        if escalation_hours <= sla_hours:
            print(f"  Error: escalation_hours ({escalation_hours}) must be greater than sla_hours ({sla_hours})")
            failures += 1
            continue

        if dry_run:
            print(f"  [DRY RUN] Would create config: {config['name']}")
            print(f"    Zone: {config['zone']}, Tier: {config['tier']}")
            print(f"    SLA: {config['sla_hours']}h, Escalation: {config['escalation_hours']}h")
            print(f"    Review %: {config['review_percent']}")
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

        # Note: "fsi_supervisionconfigs" is the default Dataverse pluralized
        # EntitySetName for the fsi_supervisionconfig table. For tables with
        # non-default pluralization, query EntityDefinitions.EntitySetName at
        # deploy time and substitute here.
        result = client.create_record("fsi_supervisionconfigs", record)
        if result:
            print(f"  Created config: {config['name']}")
        else:
            print(f"  Failed to create config: {config['name']}")
            failures += 1

    return failures


def main() -> None:
    parser = argparse.ArgumentParser(description="Deploy FINRA Supervision Workflow solution")
    parser.add_argument("--environment-url", required=True, help="Dataverse environment URL")
    parser.add_argument("--tenant-id", required=True, help="Microsoft Entra ID tenant ID")
    parser.add_argument("--managed-identity-client-id", help="User-assigned managed identity client ID")
    parser.add_argument("--client-id", help="Legacy service principal client ID (dev-only fallback)")
    parser.add_argument("--client-secret", help="Legacy service principal client secret (prefer FSW_CLIENT_SECRET env var to avoid process list exposure)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive authentication for local admin runs")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without deploying")
    parser.add_argument("--tables-only", action="store_true", help="Deploy only tables")
    parser.add_argument("--roles-only", action="store_true", help="Deploy only security roles")
    parser.add_argument("--config-only", action="store_true", help="Deploy only default configuration")

    args = parser.parse_args()

    # legacy: dev-only — replace with managed identity in production
    if args.client_id and not args.client_secret:
        args.client_secret = os.environ.get("FSW_CLIENT_SECRET")
    if args.managed_identity_client_id and (args.client_id or args.client_secret):
        print("Error: use either managed identity or legacy client-secret authentication, not both")
        sys.exit(1)

    # Validate inputs
    if not args.environment_url.startswith("https://"):
        print("Error: --environment-url must start with 'https://' (e.g., https://org.crm.dynamics.com)")
        sys.exit(1)
    # Warn if URL does not match a known Dataverse host suffix; not fatal because
    # private clouds and proxies may use other valid suffixes.
    dataverse_host_pattern = re.compile(
        r'^https://[A-Za-z0-9-]+\.crm[0-9]*\.(dynamics\.com|microsoftdynamics\.(us|de))/?$'
    )
    if not dataverse_host_pattern.match(args.environment_url):
        print(
            "Warning: --environment-url does not match a standard Dataverse host pattern "
            "(*.crm*.dynamics.com or *.crm.microsoftdynamics.{us,de}). "
            "Verify the URL if you encounter authentication errors."
        )
    guid_pattern = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
    if not guid_pattern.match(args.tenant_id):
        print("Error: --tenant-id must be a valid GUID (e.g., 12345678-1234-1234-1234-123456789abc)")
        sys.exit(1)

    print("=" * 60)
    print("FINRA Supervision Workflow - Deployment Script")
    print("=" * 60)
    print(f"Environment: {args.environment_url}")
    print(f"Tenant: {args.tenant_id}")
    print(f"Mode: {'DRY RUN' if args.dry_run else 'DEPLOY'}")
    print(f"Timestamp: {datetime.now(timezone.utc).isoformat()}")

    # Authenticate
    print("\nAuthenticating...")
    if args.interactive:
        access_token = get_access_token(
            args.tenant_id,
            interactive=True,
            environment_url=args.environment_url
        )
    elif args.client_id or args.client_secret:
        access_token = get_access_token(
            args.tenant_id,
            client_id=args.client_id,
            client_secret=args.client_secret,
            environment_url=args.environment_url,
        )
    else:
        access_token = get_access_token(
            args.tenant_id,
            managed_identity_client_id=args.managed_identity_client_id,
            environment_url=args.environment_url,
        )

    print("Authentication successful")

    # Initialize client
    client = DataverseClient(args.environment_url, access_token)

    # Deploy components
    deploy_all = not (args.tables_only or args.roles_only or args.config_only)
    failures = 0

    if deploy_all or args.tables_only:
        failures += deploy_tables(client, args.dry_run)

    if deploy_all or args.roles_only:
        deploy_security_roles(client, args.dry_run)

    if deploy_all or args.config_only:
        failures += deploy_default_configs(client, args.dry_run)

    print("\n" + "=" * 60)
    if failures > 0:
        print(f"Deployment finished with {failures} failure(s)")
    else:
        print("Deployment Complete" if not args.dry_run else "Dry Run Complete")
    print("=" * 60)

    if not args.dry_run:
        print("\nNext steps:")
        print("1. Create table columns manually (deploy.py creates tables but skips columns)")
        print("2. Create security roles manually (see docs/security-roles.md)")
        print("3. Create Power Automate flows (see docs/flow-configuration.md)")
        print("4. Configure Communication Compliance (see docs/communication-compliance-setup.md)")
        print("5. Deploy Power BI dashboard (see docs/power-bi-setup.md)")

    if failures > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
