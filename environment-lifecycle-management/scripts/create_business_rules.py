#!/usr/bin/env python3
"""
Create business rules for Environment Lifecycle Management.

Creates conditional required field rules:
- Zone Rationale Required (Zone = 2 or 3)
- Security Group Required (Zone = 2 or 3)
- Approval Comments Required (State = Rejected)
"""

import argparse
import os
import sys
from typing import Optional

from elm_client import ELMClient

# Business rule definitions
BUSINESS_RULES = [
    {
        "name": "ELM Zone Rationale Required",
        "description": "Require Zone Rationale when Zone is 2 or 3",
        "entity": "fsi_environmentrequest",
        "xaml": """<RuleDefinitions xmlns="http://schemas.microsoft.com/crm/2009/WebServices">
  <Steps>
    <Step Name="Zone Rationale Required" Description="Set Zone Rationale as required when Zone is 2 or 3">
      <Condition>
        <Or>
          <Condition EntityName="fsi_environmentrequest" AttributeName="fsi_zone" Operator="Equals">
            <Value>2</Value>
          </Condition>
          <Condition EntityName="fsi_environmentrequest" AttributeName="fsi_zone" Operator="Equals">
            <Value>3</Value>
          </Condition>
        </Or>
      </Condition>
      <TrueStep>
        <Action Name="Set Required Level">
          <Arguments>
            <Argument Name="EntityName">fsi_environmentrequest</Argument>
            <Argument Name="AttributeName">fsi_zonerationale</Argument>
            <Argument Name="RequiredLevel">Required</Argument>
          </Arguments>
        </Action>
      </TrueStep>
      <FalseStep>
        <Action Name="Set Required Level">
          <Arguments>
            <Argument Name="EntityName">fsi_environmentrequest</Argument>
            <Argument Name="AttributeName">fsi_zonerationale</Argument>
            <Argument Name="RequiredLevel">None</Argument>
          </Arguments>
        </Action>
      </FalseStep>
    </Step>
  </Steps>
</RuleDefinitions>""",
    },
    {
        "name": "ELM Security Group Required",
        "description": "Require Security Group ID when Zone is 2 or 3",
        "entity": "fsi_environmentrequest",
        "xaml": """<RuleDefinitions xmlns="http://schemas.microsoft.com/crm/2009/WebServices">
  <Steps>
    <Step Name="Security Group Required" Description="Set Security Group ID as required when Zone is 2 or 3">
      <Condition>
        <Or>
          <Condition EntityName="fsi_environmentrequest" AttributeName="fsi_zone" Operator="Equals">
            <Value>2</Value>
          </Condition>
          <Condition EntityName="fsi_environmentrequest" AttributeName="fsi_zone" Operator="Equals">
            <Value>3</Value>
          </Condition>
        </Or>
      </Condition>
      <TrueStep>
        <Action Name="Set Required Level">
          <Arguments>
            <Argument Name="EntityName">fsi_environmentrequest</Argument>
            <Argument Name="AttributeName">fsi_securitygroupid</Argument>
            <Argument Name="RequiredLevel">Required</Argument>
          </Arguments>
        </Action>
      </TrueStep>
      <FalseStep>
        <Action Name="Set Required Level">
          <Arguments>
            <Argument Name="EntityName">fsi_environmentrequest</Argument>
            <Argument Name="AttributeName">fsi_securitygroupid</Argument>
            <Argument Name="RequiredLevel">None</Argument>
          </Arguments>
        </Action>
      </FalseStep>
    </Step>
  </Steps>
</RuleDefinitions>""",
    },
    {
        "name": "ELM Approval Comments Required",
        "description": "Require Approval Comments when State is Rejected",
        "entity": "fsi_environmentrequest",
        "xaml": """<RuleDefinitions xmlns="http://schemas.microsoft.com/crm/2009/WebServices">
  <Steps>
    <Step Name="Approval Comments Required" Description="Set Approval Comments as required when State is Rejected">
      <Condition>
        <Condition EntityName="fsi_environmentrequest" AttributeName="fsi_state" Operator="Equals">
          <Value>5</Value>
        </Condition>
      </Condition>
      <TrueStep>
        <Action Name="Set Required Level">
          <Arguments>
            <Argument Name="EntityName">fsi_environmentrequest</Argument>
            <Argument Name="AttributeName">fsi_approvalcomments</Argument>
            <Argument Name="RequiredLevel">Required</Argument>
          </Arguments>
        </Action>
      </TrueStep>
      <FalseStep>
        <Action Name="Set Required Level">
          <Arguments>
            <Argument Name="EntityName">fsi_environmentrequest</Argument>
            <Argument Name="AttributeName">fsi_approvalcomments</Argument>
            <Argument Name="RequiredLevel">None</Argument>
          </Arguments>
        </Action>
      </FalseStep>
    </Step>
  </Steps>
</RuleDefinitions>""",
    },
]


def create_business_rules(client: ELMClient, dry_run: bool = False) -> None:
    """Create business rules for ELM entities."""
    print("\n" + "=" * 60)
    print("ELM Business Rules Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    print("\n[Creating Business Rules]")

    for rule in BUSINESS_RULES:
        rule_name = rule["name"]
        entity = rule["entity"]

        # Check if rule already exists
        existing = client.get_workflows(entity, category=2)
        rule_exists = any(w.get("name") == rule_name for w in existing)

        if rule_exists:
            print(f"\n  {rule_name}:")
            print(f"    Already exists, skipping")
            continue

        if dry_run:
            print(f"\n  {rule_name}:")
            print(f"    Would create: {rule['description']}")
            print(f"    Entity: {entity}")
            continue

        # Create the business rule as a workflow
        workflow_data = {
            "name": rule_name,
            "description": rule["description"],
            "primaryentity": entity,
            "category": 2,  # Business Rule
            "type": 1,  # Definition
            "scope": 4,  # Entity (entire table)
            "mode": 0,  # Background
            "statecode": 1,  # Activated
            "statuscode": 2,  # Activated
            "xaml": rule["xaml"],
        }

        try:
            workflow_id = client.create_workflow(workflow_data)
            print(f"\n  {rule_name}:")
            print(f"    Created: {workflow_id}")
            print(f"    Entity: {entity}")
        except Exception as e:
            print(f"\n  {rule_name}:")
            print(f"    ERROR: {e}")
            print(f"    NOTE: Business rules may need to be created manually via maker portal")

    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("BUSINESS RULES DEPLOYMENT COMPLETE")
    print("=" * 60)

    print("\n[Important Notes]")
    print("  - Business rules created via API may need activation in maker portal")
    print("  - Verify rules trigger correctly on Zone and State changes")
    print("  - Test with Zone 2/3 requests to confirm conditional requirements")


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create business rules for ELM",
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

        create_business_rules(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
