#!/usr/bin/env python3
"""Create Dataverse environment variables for File Upload Security Configurator.

Provisions seven environment variables with the fsi_FUS_ prefix.
All operations are idempotent — existing variables are skipped.

Usage:
  python create_environment_variables.py --tenant-id <tid> --url <url> [--dry-run]
"""

import argparse
import os
import sys

from fus_client import FUSClient


# ── Environment Variable Definitions ──────────────────────────────

ENVIRONMENT_VARIABLES = [
    {
        "SchemaName": "fsi_FUS_GracePeriodHours",
        "DisplayName": "FUS Grace Period (Hours)",
        "Description": (
            "Number of hours after baseline capture before drift "
            "violations are raised. Allows time for approved changes "
            "to propagate."
        ),
        "Type": "Decimal",
        "DefaultValue": "24",
    },
    {
        "SchemaName": "fsi_FUS_ScanFrequencyHours",
        "DisplayName": "FUS Scan Frequency (Hours)",
        "Description": (
            "How often the automated file upload validation scan runs. "
            "Controls Power Automate recurrence trigger interval."
        ),
        "Type": "Decimal",
        "DefaultValue": "24",
    },
    {
        "SchemaName": "fsi_FUS_IncludeSandbox",
        "DisplayName": "FUS Include Sandbox Environments",
        "Description": (
            "When true, sandbox (non-production) environments are "
            "included in file upload compliance scans."
        ),
        "Type": "String",
        "DefaultValue": "false",
    },
    {
        "SchemaName": "fsi_FUS_IncludeDrafts",
        "DisplayName": "FUS Include Draft Agents",
        "Description": (
            "When true, agents in draft/unpublished state are included "
            "in file upload compliance scans."
        ),
        "Type": "String",
        "DefaultValue": "false",
    },
    {
        "SchemaName": "fsi_FUS_BaselineMaxAgeDays",
        "DisplayName": "FUS Baseline Max Age (Days)",
        "Description": (
            "Maximum age of baseline records before they are flagged as "
            "stale and require recapture. Supports regulatory review "
            "cadences required by FINRA 3110 and OCC 2011-12."
        ),
        "Type": "Decimal",
        "DefaultValue": "90",
    },
    {
        "SchemaName": "fsi_FUS_TeamsGroupId",
        "DisplayName": "FUS Teams Group ID",
        "Description": (
            "Microsoft 365 Group ID for the Teams team that receives "
            "file upload violation alerts."
        ),
        "Type": "String",
        "DefaultValue": "",
    },
    {
        "SchemaName": "fsi_FUS_TeamsChannelId",
        "DisplayName": "FUS Teams Channel ID",
        "Description": (
            "Teams channel ID within the group that receives "
            "file upload violation alert adaptive cards."
        ),
        "Type": "String",
        "DefaultValue": "",
    },
]


def _label(text: str) -> dict:
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


TYPE_MAP = {
    "String": 100000000,
    "Decimal": 100000001,
    "JSON": 100000002,
}


def deploy_environment_variables(client: FUSClient) -> None:
    """Create all FUS environment variables (idempotent)."""
    print(f"\n{'='*60}")
    print("Environment Variables")
    print(f"{'='*60}")

    for var_def in ENVIRONMENT_VARIABLES:
        schema = var_def["SchemaName"]

        try:
            # Check if already exists
            result = client.query(
                "environmentvariabledefinitions",
                filter=f"schemaname eq '{schema}'",
                select="schemaname",
            )
            if result.get("value"):
                print(f"  {schema}: already exists")
                continue

            if client.dry_run:
                print(f"  [DRY RUN] Would create: {schema}")
                continue

            definition = {
                "schemaname": schema,
                "displayname": var_def["DisplayName"],
                "description": var_def["Description"],
                "type": TYPE_MAP[var_def["Type"]],
                "defaultvalue": var_def["DefaultValue"],
            }

            client.create_record("environmentvariabledefinitions", definition)
            print(f"  {schema}: created ({var_def['Type']})")
        except Exception as exc:
            print(f"  ERROR creating {schema}: {exc}")
            continue

    print(f"\n  Total: {len(ENVIRONMENT_VARIABLES)} environment variables")
    print(f"{'='*60}")


# ── CLI Entry Point ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Create environment variables for File Upload Security Configurator"
    )
    parser.add_argument("--tenant-id", default=os.environ.get("FUS_TENANT_ID"))
    parser.add_argument("--client-id", default=os.environ.get("FUS_CLIENT_ID"))
    parser.add_argument("--client-secret", default=os.environ.get("FUS_CLIENT_SECRET"))
    parser.add_argument("--url", default=os.environ.get("FUS_DATAVERSE_URL"),
                        help="Dataverse environment URL")
    parser.add_argument("--interactive", action="store_true",
                        help="Use interactive browser auth")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be created without making changes")
    args = parser.parse_args()

    if not args.tenant_id or not args.url:
        parser.error(
            "tenant-id and url are required "
            "(set FUS_TENANT_ID and FUS_DATAVERSE_URL env vars or use flags)"
        )

    client = FUSClient(
        tenant_id=args.tenant_id,
        environment_url=args.url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        interactive=args.interactive,
        dry_run=args.dry_run,
    )

    deploy_environment_variables(client)


if __name__ == "__main__":
    main()
