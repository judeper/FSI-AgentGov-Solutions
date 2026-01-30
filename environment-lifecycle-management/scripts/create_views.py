#!/usr/bin/env python3
"""
Create model-driven app views for Environment Lifecycle Management.

Creates standard views for EnvironmentRequest:
- My Requests
- Pending My Approval
- All Pending
- Provisioning in Progress
- Failed Requests
- Completed This Month
"""

import argparse
import os
import sys
from typing import Optional

from elm_client import ELMClient

# View definitions with FetchXML queries
VIEWS = [
    {
        "name": "My Requests",
        "description": "Environment requests submitted by current user",
        "entity": "fsi_environmentrequest",
        "querytype": 0,  # Public view
        "isdefault": True,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_environmentrequest">
    <attribute name="fsi_requestnumber"/>
    <attribute name="fsi_environmentname"/>
    <attribute name="fsi_zone"/>
    <attribute name="fsi_state"/>
    <attribute name="fsi_requestedon"/>
    <attribute name="createdon"/>
    <order attribute="createdon" descending="true"/>
    <filter type="and">
      <condition attribute="fsi_requester" operator="eq-userid"/>
    </filter>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10001" jump="fsi_requestnumber" select="1" icon="1" preview="1">
  <row name="result" id="fsi_environmentrequestid">
    <cell name="fsi_requestnumber" width="100"/>
    <cell name="fsi_environmentname" width="200"/>
    <cell name="fsi_zone" width="80"/>
    <cell name="fsi_state" width="100"/>
    <cell name="fsi_requestedon" width="150"/>
  </row>
</grid>""",
    },
    {
        "name": "Pending My Approval",
        "description": "Requests awaiting approval from current user",
        "entity": "fsi_environmentrequest",
        "querytype": 0,
        "isdefault": False,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_environmentrequest">
    <attribute name="fsi_requestnumber"/>
    <attribute name="fsi_environmentname"/>
    <attribute name="fsi_zone"/>
    <attribute name="fsi_requester"/>
    <attribute name="fsi_businessjustification"/>
    <attribute name="fsi_requestedon"/>
    <order attribute="fsi_requestedon" descending="false"/>
    <filter type="and">
      <condition attribute="fsi_state" operator="eq" value="3"/>
      <condition attribute="fsi_approver" operator="eq-userid"/>
    </filter>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10001" jump="fsi_requestnumber" select="1" icon="1" preview="1">
  <row name="result" id="fsi_environmentrequestid">
    <cell name="fsi_requestnumber" width="100"/>
    <cell name="fsi_environmentname" width="200"/>
    <cell name="fsi_zone" width="80"/>
    <cell name="fsi_requester" width="150"/>
    <cell name="fsi_requestedon" width="150"/>
  </row>
</grid>""",
    },
    {
        "name": "All Pending",
        "description": "All requests pending approval",
        "entity": "fsi_environmentrequest",
        "querytype": 0,
        "isdefault": False,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_environmentrequest">
    <attribute name="fsi_requestnumber"/>
    <attribute name="fsi_environmentname"/>
    <attribute name="fsi_zone"/>
    <attribute name="fsi_requester"/>
    <attribute name="fsi_approver"/>
    <attribute name="fsi_requestedon"/>
    <order attribute="fsi_requestedon" descending="false"/>
    <filter type="and">
      <condition attribute="fsi_state" operator="eq" value="3"/>
    </filter>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10001" jump="fsi_requestnumber" select="1" icon="1" preview="1">
  <row name="result" id="fsi_environmentrequestid">
    <cell name="fsi_requestnumber" width="100"/>
    <cell name="fsi_environmentname" width="200"/>
    <cell name="fsi_zone" width="80"/>
    <cell name="fsi_requester" width="150"/>
    <cell name="fsi_approver" width="150"/>
    <cell name="fsi_requestedon" width="150"/>
  </row>
</grid>""",
    },
    {
        "name": "Provisioning in Progress",
        "description": "Requests currently being provisioned",
        "entity": "fsi_environmentrequest",
        "querytype": 0,
        "isdefault": False,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_environmentrequest">
    <attribute name="fsi_requestnumber"/>
    <attribute name="fsi_environmentname"/>
    <attribute name="fsi_zone"/>
    <attribute name="fsi_provisioningstarted"/>
    <attribute name="fsi_approver"/>
    <order attribute="fsi_provisioningstarted" descending="true"/>
    <filter type="and">
      <condition attribute="fsi_state" operator="eq" value="6"/>
    </filter>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10001" jump="fsi_requestnumber" select="1" icon="1" preview="1">
  <row name="result" id="fsi_environmentrequestid">
    <cell name="fsi_requestnumber" width="100"/>
    <cell name="fsi_environmentname" width="200"/>
    <cell name="fsi_zone" width="80"/>
    <cell name="fsi_provisioningstarted" width="150"/>
    <cell name="fsi_approver" width="150"/>
  </row>
</grid>""",
    },
    {
        "name": "Failed Requests",
        "description": "Requests that failed provisioning",
        "entity": "fsi_environmentrequest",
        "querytype": 0,
        "isdefault": False,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_environmentrequest">
    <attribute name="fsi_requestnumber"/>
    <attribute name="fsi_environmentname"/>
    <attribute name="fsi_zone"/>
    <attribute name="fsi_requester"/>
    <attribute name="fsi_provisioningstarted"/>
    <order attribute="fsi_provisioningstarted" descending="true"/>
    <filter type="and">
      <condition attribute="fsi_state" operator="eq" value="8"/>
    </filter>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10001" jump="fsi_requestnumber" select="1" icon="1" preview="1">
  <row name="result" id="fsi_environmentrequestid">
    <cell name="fsi_requestnumber" width="100"/>
    <cell name="fsi_environmentname" width="200"/>
    <cell name="fsi_zone" width="80"/>
    <cell name="fsi_requester" width="150"/>
    <cell name="fsi_provisioningstarted" width="150"/>
  </row>
</grid>""",
    },
    {
        "name": "Completed This Month",
        "description": "Requests completed in current month",
        "entity": "fsi_environmentrequest",
        "querytype": 0,
        "isdefault": False,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_environmentrequest">
    <attribute name="fsi_requestnumber"/>
    <attribute name="fsi_environmentname"/>
    <attribute name="fsi_zone"/>
    <attribute name="fsi_environmentid"/>
    <attribute name="fsi_environmenturl"/>
    <attribute name="fsi_provisioningcompleted"/>
    <order attribute="fsi_provisioningcompleted" descending="true"/>
    <filter type="and">
      <condition attribute="fsi_state" operator="eq" value="7"/>
      <condition attribute="fsi_provisioningcompleted" operator="this-month"/>
    </filter>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10001" jump="fsi_requestnumber" select="1" icon="1" preview="1">
  <row name="result" id="fsi_environmentrequestid">
    <cell name="fsi_requestnumber" width="100"/>
    <cell name="fsi_environmentname" width="200"/>
    <cell name="fsi_zone" width="80"/>
    <cell name="fsi_environmenturl" width="250"/>
    <cell name="fsi_provisioningcompleted" width="150"/>
  </row>
</grid>""",
    },
]

# ProvisioningLog views
PROVISIONING_LOG_VIEWS = [
    {
        "name": "All Provisioning Logs",
        "description": "All provisioning log entries",
        "entity": "fsi_provisioninglog",
        "querytype": 0,
        "isdefault": True,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_provisioninglog">
    <attribute name="fsi_name"/>
    <attribute name="fsi_environmentrequest"/>
    <attribute name="fsi_sequence"/>
    <attribute name="fsi_action"/>
    <attribute name="fsi_actor"/>
    <attribute name="fsi_timestamp"/>
    <attribute name="fsi_success"/>
    <order attribute="fsi_timestamp" descending="true"/>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10002" jump="fsi_name" select="1" icon="1" preview="1">
  <row name="result" id="fsi_provisioninglogid">
    <cell name="fsi_environmentrequest" width="150"/>
    <cell name="fsi_sequence" width="80"/>
    <cell name="fsi_action" width="150"/>
    <cell name="fsi_actor" width="200"/>
    <cell name="fsi_timestamp" width="150"/>
    <cell name="fsi_success" width="80"/>
  </row>
</grid>""",
    },
    {
        "name": "Failed Actions",
        "description": "Provisioning log entries where action failed",
        "entity": "fsi_provisioninglog",
        "querytype": 0,
        "isdefault": False,
        "fetchxml": """<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="fsi_provisioninglog">
    <attribute name="fsi_name"/>
    <attribute name="fsi_environmentrequest"/>
    <attribute name="fsi_action"/>
    <attribute name="fsi_actor"/>
    <attribute name="fsi_timestamp"/>
    <attribute name="fsi_errormessage"/>
    <order attribute="fsi_timestamp" descending="true"/>
    <filter type="and">
      <condition attribute="fsi_success" operator="eq" value="0"/>
    </filter>
  </entity>
</fetch>""",
        "layoutxml": """<grid name="resultset" object="10002" jump="fsi_name" select="1" icon="1" preview="1">
  <row name="result" id="fsi_provisioninglogid">
    <cell name="fsi_environmentrequest" width="150"/>
    <cell name="fsi_action" width="150"/>
    <cell name="fsi_actor" width="150"/>
    <cell name="fsi_timestamp" width="150"/>
    <cell name="fsi_errormessage" width="300"/>
  </row>
</grid>""",
    },
]


def create_views(client: ELMClient, dry_run: bool = False) -> None:
    """Create model-driven app views for ELM entities."""
    print("\n" + "=" * 60)
    print("ELM Views Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Get entity type codes for views
    print("\n[Getting Entity Metadata]")
    er_metadata = client.get_entity_metadata("fsi_environmentrequest")
    pl_metadata = client.get_entity_metadata("fsi_provisioninglog")

    if not er_metadata:
        print("  ERROR: EnvironmentRequest table not found. Run create_dataverse_schema.py first.")
        return

    er_type_code = er_metadata.get("ObjectTypeCode", 10001)
    pl_type_code = pl_metadata.get("ObjectTypeCode", 10002) if pl_metadata else 10002

    print(f"  EnvironmentRequest type code: {er_type_code}")
    if pl_metadata:
        print(f"  ProvisioningLog type code: {pl_type_code}")
    else:
        print("  ProvisioningLog table not found, will skip ProvisioningLog views")

    # Create EnvironmentRequest views
    print("\n[Creating EnvironmentRequest Views]")
    for view in VIEWS:
        view_name = view["name"]
        entity = view["entity"]

        # Check if view already exists
        existing = client.get_saved_queries(entity, f"name eq '{view_name}'")
        if existing:
            print(f"\n  {view_name}:")
            print(f"    Already exists, skipping")
            continue

        if dry_run:
            print(f"\n  {view_name}:")
            print(f"    Would create: {view['description']}")
            continue

        # Update layout XML with correct type code
        layout = view["layoutxml"].replace("object=\"10001\"", f"object=\"{er_type_code}\"")

        query_data = {
            "name": view_name,
            "description": view["description"],
            "returnedtypecode": entity,
            "querytype": view["querytype"],
            "isdefault": view["isdefault"],
            "fetchxml": view["fetchxml"],
            "layoutxml": layout,
        }

        try:
            query_id = client.create_saved_query(query_data)
            print(f"\n  {view_name}:")
            print(f"    Created: {query_id}")
        except Exception as e:
            print(f"\n  {view_name}:")
            print(f"    ERROR: {e}")

    # Create ProvisioningLog views
    if pl_metadata:
        print("\n[Creating ProvisioningLog Views]")
        for view in PROVISIONING_LOG_VIEWS:
            view_name = view["name"]
            entity = view["entity"]

            # Check if view already exists
            existing = client.get_saved_queries(entity, f"name eq '{view_name}'")
            if existing:
                print(f"\n  {view_name}:")
                print(f"    Already exists, skipping")
                continue

            if dry_run:
                print(f"\n  {view_name}:")
                print(f"    Would create: {view['description']}")
                continue

            # Update layout XML with correct type code
            layout = view["layoutxml"].replace("object=\"10002\"", f"object=\"{pl_type_code}\"")

            query_data = {
                "name": view_name,
                "description": view["description"],
                "returnedtypecode": entity,
                "querytype": view["querytype"],
                "isdefault": view["isdefault"],
                "fetchxml": view["fetchxml"],
                "layoutxml": layout,
            }

            try:
                query_id = client.create_saved_query(query_data)
                print(f"\n  {view_name}:")
                print(f"    Created: {query_id}")
            except Exception as e:
                print(f"\n  {view_name}:")
                print(f"    ERROR: {e}")

    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("VIEWS DEPLOYMENT COMPLETE")
    print("=" * 60)


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create model-driven app views for ELM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ELM_TENANT_ID"),
        help="Entra ID tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ELM_CLIENT_ID"),
        help="Application (client) ID",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ELM_CLIENT_SECRET"),
        help="Client secret",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ELM_ENVIRONMENT_URL"),
        help="Dataverse environment URL",
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
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Get client secret if needed
    client_secret = args.client_secret
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = ELMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
        )

        create_views(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
