#!/usr/bin/env python3
"""
MCG Solution Deployment Script

Deploys Message Center Governance Dataverse components via Web API.
Creates publisher, solution, tables, columns, relationships, and alternate key.

Usage:
    python deploy_mcg.py \
        --environment-url "https://org12345.crm.dynamics.com" \
        --tenant-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
        --client-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
        --client-secret "your-secret-value"

Prerequisites:
    1. Azure AD App Registration with client secret
    2. Dataverse Application User with System Customizer role
    3. pip install requests msal
"""

import argparse
import sys
import time
from typing import Any

import requests
from msal import ConfidentialClientApplication

# =============================================================================
# CONFIGURATION (Embedded)
# =============================================================================

PUBLISHER_CONFIG = {
    "uniquename": "mcg",
    "friendlyname": "Message Center Governance",
    "customizationprefix": "mcg",
    "customizationoptionvalueprefix": 10000,
}

SOLUTION_CONFIG = {
    "uniquename": "MessageCenterGovernance",
    "friendlyname": "Message Center Governance",
    "version": "1.0.0.0",
}

CHOICE_DEFINITIONS = {
    "mcg_category": [
        (100000000, "Prevent or Fix Issue"),
        (100000001, "Plan for Change"),
        (100000002, "Stay Informed"),
    ],
    "mcg_severity": [
        (100000000, "Normal"),
        (100000001, "High"),
        (100000002, "Critical"),
    ],
    "mcg_state": [
        (100000000, "New"),
        (100000001, "Triage"),
        (100000002, "Assess"),
        (100000003, "Decide"),
        (100000004, "Closed"),
    ],
    "mcg_impactassessment": [
        (100000000, "None"),
        (100000001, "Low"),
        (100000002, "Medium"),
        (100000003, "High"),
    ],
    "mcg_relevance": [
        (100000000, "Not Applicable"),
        (100000001, "Informational"),
        (100000002, "Action Required"),
    ],
    "mcg_decision": [
        (100000000, "Accept"),
        (100000001, "Defer"),
        (100000002, "Escalate"),
        (100000003, "No Action Required"),
    ],
    "mcg_recommendedaction": [
        (100000000, "Implement"),
        (100000001, "Defer"),
        (100000002, "Dismiss"),
        (100000003, "Escalate"),
    ],
}

# Table definitions with columns (excluding primary name - added during table creation)
TABLE_DEFINITIONS = {
    "mcg_messagecenterpost": {
        "schema_name": "mcg_MessageCenterPost",
        "display_name": "Message Center Post",
        "display_collection_name": "Message Center Posts",
        "ownership_type": "UserOwned",
        "primary_name": {"schema_name": "mcg_Title", "display_name": "Title", "max_length": 500},
        "columns": [
            {"schema_name": "mcg_MessageCenterId", "type": "String", "display_name": "Message Center ID", "max_length": 50, "required": True},
            {"schema_name": "mcg_Category", "type": "Picklist", "display_name": "Category", "choice": "mcg_category"},
            {"schema_name": "mcg_Severity", "type": "Picklist", "display_name": "Severity", "choice": "mcg_severity"},
            {"schema_name": "mcg_Services", "type": "Memo", "display_name": "Services", "max_length": 4000},
            {"schema_name": "mcg_Tags", "type": "Memo", "display_name": "Tags", "max_length": 4000},
            {"schema_name": "mcg_StartDateTime", "type": "DateTime", "display_name": "Start Date/Time"},
            {"schema_name": "mcg_EndDateTime", "type": "DateTime", "display_name": "End Date/Time"},
            {"schema_name": "mcg_ActionRequiredBy", "type": "DateTime", "display_name": "Action Required By"},
            {"schema_name": "mcg_Body", "type": "Memo", "display_name": "Body", "max_length": 100000},
            {"schema_name": "mcg_State", "type": "Picklist", "display_name": "State", "choice": "mcg_state", "required": True},
            {"schema_name": "mcg_ImpactAssessment", "type": "Picklist", "display_name": "Impact Assessment", "choice": "mcg_impactassessment"},
            {"schema_name": "mcg_Relevance", "type": "Picklist", "display_name": "Relevance", "choice": "mcg_relevance"},
            {"schema_name": "mcg_Decision", "type": "Picklist", "display_name": "Decision", "choice": "mcg_decision"},
            {"schema_name": "mcg_DecisionRationale", "type": "Memo", "display_name": "Decision Rationale", "max_length": 10000},
            {"schema_name": "mcg_LastModifiedDateTime", "type": "DateTime", "display_name": "Last Modified Date/Time"},
        ],
    },
    "mcg_assessmentlog": {
        "schema_name": "mcg_AssessmentLog",
        "display_name": "Assessment Log",
        "display_collection_name": "Assessment Logs",
        "ownership_type": "UserOwned",
        "primary_name": {"schema_name": "mcg_Name", "display_name": "Name", "max_length": 100},
        "columns": [
            {"schema_name": "mcg_AssessedOn", "type": "DateTime", "display_name": "Assessed On", "required": True},
            {"schema_name": "mcg_ImpactAssessment", "type": "Picklist", "display_name": "Impact Assessment", "choice": "mcg_impactassessment", "required": True},
            {"schema_name": "mcg_Notes", "type": "Memo", "display_name": "Notes", "max_length": 10000},
            {"schema_name": "mcg_RecommendedAction", "type": "Picklist", "display_name": "Recommended Action", "choice": "mcg_recommendedaction"},
            {"schema_name": "mcg_AffectedSystems", "type": "Memo", "display_name": "Affected Systems", "max_length": 4000},
        ],
    },
    "mcg_decisionlog": {
        "schema_name": "mcg_DecisionLog",
        "display_name": "Decision Log",
        "display_collection_name": "Decision Logs",
        "ownership_type": "OrganizationOwned",
        "primary_name": {"schema_name": "mcg_Name", "display_name": "Name", "max_length": 100},
        "columns": [
            {"schema_name": "mcg_DecidedOn", "type": "DateTime", "display_name": "Decided On", "required": True},
            {"schema_name": "mcg_Decision", "type": "Picklist", "display_name": "Decision", "choice": "mcg_decision", "required": True},
            {"schema_name": "mcg_DecisionRationale", "type": "Memo", "display_name": "Decision Rationale", "max_length": 10000, "required": True},
            {"schema_name": "mcg_ExternalTicketReference", "type": "String", "display_name": "External Ticket Reference", "max_length": 200},
        ],
    },
}

RELATIONSHIP_DEFINITIONS = [
    {
        "schema_name": "mcg_messagecenterpost_assessmentlogs",
        "referenced_entity": "mcg_messagecenterpost",
        "referencing_entity": "mcg_assessmentlog",
        "lookup_schema_name": "mcg_MessageCenterPostId",
        "lookup_display_name": "Message Center Post",
    },
    {
        "schema_name": "mcg_messagecenterpost_decisionlogs",
        "referenced_entity": "mcg_messagecenterpost",
        "referencing_entity": "mcg_decisionlog",
        "lookup_schema_name": "mcg_MessageCenterPostId",
        "lookup_display_name": "Message Center Post",
    },
]


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================


def make_label(text: str) -> dict:
    """Create a Dataverse Label structure."""
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


def make_required_level(required: bool) -> dict:
    """Create RequiredLevel structure."""
    return {
        "Value": "ApplicationRequired" if required else "None",
        "CanBeChanged": True,
        "ManagedPropertyLogicalName": "canmodifyrequirementlevelsettings",
    }


def make_option_set(choice_name: str) -> dict:
    """Create local OptionSet for a picklist column."""
    options = CHOICE_DEFINITIONS.get(choice_name, [])
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
        "IsGlobal": False,
        "OptionSetType": "Picklist",
        "Options": [
            {
                "Value": val,
                "Label": make_label(label),
            }
            for val, label in options
        ],
    }


# =============================================================================
# DATAVERSE CLIENT
# =============================================================================


class DataverseClient:
    """Client for Dataverse Web API operations."""

    def __init__(self, environment_url: str, tenant_id: str, client_id: str, client_secret: str):
        self.environment_url = environment_url.rstrip("/")
        self.api_url = f"{self.environment_url}/api/data/v9.2"
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.session = requests.Session()
        self.access_token = None

    def authenticate(self) -> None:
        """Authenticate using OAuth2 client credentials."""
        authority = f"https://login.microsoftonline.com/{self.tenant_id}"
        scope = [f"{self.environment_url}/.default"]

        app = ConfidentialClientApplication(
            self.client_id,
            authority=authority,
            client_credential=self.client_secret,
        )

        result = app.acquire_token_for_client(scopes=scope)

        if "access_token" not in result:
            error = result.get("error_description", result.get("error", "Unknown error"))
            raise Exception(f"Authentication failed: {error}")

        self.access_token = result["access_token"]
        self.session.headers.update({
            "Authorization": f"Bearer {self.access_token}",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
            "Accept": "application/json",
            "Content-Type": "application/json; charset=utf-8",
        })

    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        """Make HTTP request with retry for rate limiting."""
        url = f"{self.api_url}/{endpoint}"

        for attempt in range(3):
            response = self.session.request(method, url, **kwargs)

            if response.status_code == 429:
                retry_after = int(response.headers.get("Retry-After", 30))
                print(f"      Rate limited, waiting {retry_after}s...")
                time.sleep(retry_after)
                continue

            return response

        raise Exception("Max retries exceeded due to rate limiting")

    def get(self, endpoint: str) -> dict:
        """GET request."""
        response = self._request("GET", endpoint)
        if response.status_code == 404:
            return {}
        response.raise_for_status()
        return response.json() if response.text else {}

    def post(self, endpoint: str, data: dict) -> dict:
        """POST request."""
        response = self._request("POST", endpoint, json=data)
        if response.status_code not in (200, 201, 204):
            raise Exception(f"POST {endpoint} failed: {response.status_code} - {response.text}")
        return response.json() if response.text else {}

    # -------------------------------------------------------------------------
    # Publisher & Solution
    # -------------------------------------------------------------------------

    def get_or_create_publisher(self) -> str:
        """Check if publisher exists, create if not. Returns publisherid."""
        prefix = PUBLISHER_CONFIG["customizationprefix"]
        existing = self.get(f"publishers?$filter=customizationprefix eq '{prefix}'")

        if existing.get("value"):
            return existing["value"][0]["publisherid"]

        data = {
            "uniquename": PUBLISHER_CONFIG["uniquename"],
            "friendlyname": PUBLISHER_CONFIG["friendlyname"],
            "customizationprefix": prefix,
            "customizationoptionvalueprefix": PUBLISHER_CONFIG["customizationoptionvalueprefix"],
        }
        response = self._request("POST", "publishers", json=data)
        response.raise_for_status()

        # Get the created publisher ID from OData-EntityId header
        entity_id = response.headers.get("OData-EntityId", "")
        if "(" in entity_id:
            return entity_id.split("(")[1].split(")")[0]

        # Fallback: query for it
        created = self.get(f"publishers?$filter=uniquename eq '{PUBLISHER_CONFIG['uniquename']}'")
        return created["value"][0]["publisherid"]

    def get_or_create_solution(self, publisher_id: str) -> str:
        """Check if solution exists, create if not. Returns solutionid."""
        unique_name = SOLUTION_CONFIG["uniquename"]
        existing = self.get(f"solutions?$filter=uniquename eq '{unique_name}'")

        if existing.get("value"):
            return existing["value"][0]["solutionid"]

        data = {
            "uniquename": unique_name,
            "friendlyname": SOLUTION_CONFIG["friendlyname"],
            "version": SOLUTION_CONFIG["version"],
            "publisherid@odata.bind": f"/publishers({publisher_id})",
        }
        response = self._request("POST", "solutions", json=data)
        response.raise_for_status()

        created = self.get(f"solutions?$filter=uniquename eq '{unique_name}'")
        return created["value"][0]["solutionid"]

    # -------------------------------------------------------------------------
    # Tables (Entities)
    # -------------------------------------------------------------------------

    def create_table(self, table_logical_name: str, table_def: dict) -> None:
        """Create a table with its primary name attribute."""
        # Check if table already exists
        existing = self.get(f"EntityDefinitions(LogicalName='{table_logical_name}')")
        if existing.get("LogicalName"):
            print(f"      Table already exists, skipping creation")
            return

        primary = table_def["primary_name"]

        payload = {
            "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
            "SchemaName": table_def["schema_name"],
            "DisplayName": make_label(table_def["display_name"]),
            "DisplayCollectionName": make_label(table_def["display_collection_name"]),
            "HasNotes": False,
            "HasActivities": False,
            "OwnershipType": table_def["ownership_type"],
            "IsAuditEnabled": {
                "Value": True,
                "CanBeChanged": True,
                "ManagedPropertyLogicalName": "canmodifyauditsettings",
            },
            "PrimaryNameAttribute": primary["schema_name"].lower(),
            "Attributes": [
                {
                    "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                    "SchemaName": primary["schema_name"],
                    "DisplayName": make_label(primary["display_name"]),
                    "IsPrimaryName": True,
                    "MaxLength": primary["max_length"],
                    "RequiredLevel": make_required_level(True),
                    "FormatName": {"Value": "Text"},
                }
            ],
        }

        response = self._request(
            "POST",
            "EntityDefinitions",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create table failed: {response.status_code} - {response.text}")

    def add_column(self, table_logical_name: str, column_def: dict) -> None:
        """Add a column to an existing table."""
        col_type = column_def["type"]
        schema_name = column_def["schema_name"]

        # Check if column already exists
        existing = self.get(
            f"EntityDefinitions(LogicalName='{table_logical_name}')/Attributes(LogicalName='{schema_name.lower()}')"
        )
        if existing.get("LogicalName"):
            return  # Column exists

        payload: dict[str, Any] = {
            "SchemaName": schema_name,
            "DisplayName": make_label(column_def["display_name"]),
            "RequiredLevel": make_required_level(column_def.get("required", False)),
        }

        if col_type == "String":
            payload["@odata.type"] = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            payload["MaxLength"] = column_def.get("max_length", 100)
            payload["FormatName"] = {"Value": "Text"}

        elif col_type == "Memo":
            payload["@odata.type"] = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
            payload["MaxLength"] = column_def.get("max_length", 4000)
            payload["Format"] = "Text"

        elif col_type == "DateTime":
            payload["@odata.type"] = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
            payload["Format"] = "DateAndTime"
            payload["DateTimeBehavior"] = {"Value": "UserLocal"}

        elif col_type == "Picklist":
            payload["@odata.type"] = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
            payload["OptionSet"] = make_option_set(column_def["choice"])

        else:
            raise ValueError(f"Unknown column type: {col_type}")

        response = self._request(
            "POST",
            f"EntityDefinitions(LogicalName='{table_logical_name}')/Attributes",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Add column {schema_name} failed: {response.status_code} - {response.text}")

    # -------------------------------------------------------------------------
    # Relationships
    # -------------------------------------------------------------------------

    def create_relationship(self, rel_def: dict) -> None:
        """Create a 1:N relationship with lookup column."""
        schema_name = rel_def["schema_name"]

        # Check if relationship already exists
        existing = self.get(f"RelationshipDefinitions(SchemaName='{schema_name}')")
        if existing.get("SchemaName"):
            print(f"      Relationship {schema_name} already exists, skipping")
            return

        payload = {
            "@odata.type": "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
            "SchemaName": schema_name,
            "ReferencedEntity": rel_def["referenced_entity"],
            "ReferencedAttribute": f"{rel_def['referenced_entity']}id",
            "ReferencingEntity": rel_def["referencing_entity"],
            "CascadeConfiguration": {
                "Assign": "NoCascade",
                "Delete": "Restrict",
                "Merge": "NoCascade",
                "Reparent": "NoCascade",
                "Share": "NoCascade",
                "Unshare": "NoCascade",
            },
            "Lookup": {
                "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
                "SchemaName": rel_def["lookup_schema_name"],
                "DisplayName": make_label(rel_def["lookup_display_name"]),
                "RequiredLevel": make_required_level(True),
            },
        }

        response = self._request(
            "POST",
            "RelationshipDefinitions",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create relationship failed: {response.status_code} - {response.text}")

    # -------------------------------------------------------------------------
    # Alternate Key
    # -------------------------------------------------------------------------

    def create_alternate_key(self, table_logical_name: str, key_name: str, key_columns: list[str]) -> None:
        """Create an alternate key on a table."""
        # Check if key already exists
        existing = self.get(
            f"EntityDefinitions(LogicalName='{table_logical_name}')/Keys?$filter=LogicalName eq '{key_name.lower()}'"
        )
        if existing.get("value"):
            print(f"      Alternate key already exists, skipping creation")
            return

        payload = {
            "@odata.type": "Microsoft.Dynamics.CRM.EntityKeyMetadata",
            "SchemaName": key_name,
            "DisplayName": make_label("Message Center ID Key"),
            "KeyAttributes": key_columns,
        }

        response = self._request(
            "POST",
            f"EntityDefinitions(LogicalName='{table_logical_name}')/Keys",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create alternate key failed: {response.status_code} - {response.text}")

    def wait_for_alternate_key(self, table_logical_name: str, key_name: str, timeout: int = 120) -> None:
        """Poll until alternate key is Active or timeout."""
        start = time.time()
        while time.time() - start < timeout:
            result = self.get(
                f"EntityDefinitions(LogicalName='{table_logical_name}')/Keys?$filter=LogicalName eq '{key_name.lower()}'"
            )
            if result.get("value"):
                status = result["value"][0].get("EntityKeyIndexStatus")
                if status == "Active":
                    return
                if status == "Failed":
                    raise Exception(f"Alternate key activation failed: {result['value'][0]}")
                print(f"      Status: {status}...", end=" ", flush=True)
            time.sleep(5)

        raise TimeoutError(f"Alternate key activation timeout after {timeout}s")

    # -------------------------------------------------------------------------
    # Publish
    # -------------------------------------------------------------------------

    def publish_all(self) -> None:
        """Publish all customizations."""
        response = self._request("POST", "PublishAllXml")
        if response.status_code not in (200, 204):
            raise Exception(f"PublishAllXml failed: {response.status_code} - {response.text}")


# =============================================================================
# MAIN DEPLOYMENT
# =============================================================================


def deploy(environment_url: str, tenant_id: str, client_id: str, client_secret: str) -> None:
    """Run the full deployment."""
    print("=== MCG Solution Deployment ===")
    print(f"Environment: {environment_url}\n")

    client = DataverseClient(environment_url, tenant_id, client_id, client_secret)

    # Step 1: Authenticate
    print("[1/9] Authenticating...", end=" ", flush=True)
    client.authenticate()
    print("✓")

    # Step 2: Publisher
    print("[2/9] Publisher 'mcg'...", end=" ", flush=True)
    publisher_id = client.get_or_create_publisher()
    print("ready")

    # Step 3: Solution
    print("[3/9] Solution 'MessageCenterGovernance'...", end=" ", flush=True)
    client.get_or_create_solution(publisher_id)
    print("ready")

    # Steps 4-6: Create tables and columns
    step = 4
    for table_logical_name, table_def in TABLE_DEFINITIONS.items():
        col_count = len(table_def["columns"])
        print(f"[{step}/9] Table '{table_def['schema_name']}'...", end=" ", flush=True)
        client.create_table(table_logical_name, table_def)
        print(f"created")

        for col_def in table_def["columns"]:
            client.add_column(table_logical_name, col_def)
        print(f"      Added {col_count} columns")
        step += 1

    # Step 7: Relationships
    print(f"[7/9] Relationships...", end=" ", flush=True)
    for rel_def in RELATIONSHIP_DEFINITIONS:
        client.create_relationship(rel_def)
    print(f"created ({len(RELATIONSHIP_DEFINITIONS)})")

    # Step 8: Alternate key
    print("[8/9] Alternate key 'mcg_messagecenterid'...", end=" ", flush=True)
    client.create_alternate_key(
        "mcg_messagecenterpost",
        "mcg_MessageCenterIdKey",
        ["mcg_messagecenterid"],
    )
    print("created")
    print("      Waiting for activation...", end=" ", flush=True)
    client.wait_for_alternate_key("mcg_messagecenterpost", "mcg_messagecenteridkey")
    print("Active ✓")

    # Step 9: Publish
    print("[9/9] Publishing customizations...", end=" ", flush=True)
    client.publish_all()
    print("✓")

    # Print next steps
    print("\n" + "=" * 50)
    print("=== Deployment Complete ===")
    print("=" * 50)
    print("""
Next steps in Power Apps Portal (make.powerapps.com):

1. VIEWS - Create these views for MessageCenterPost:
   - New Posts - Awaiting Triage (state = New)
   - High Severity Posts (severity = High or Critical)
   - My Assigned Posts (owner = current user)
   - All Open Posts (state != Closed)

2. MODEL-DRIVEN APP - Create "Message Center Governance" app
   - Add MessageCenterPost, AssessmentLog, DecisionLog tables
   - Configure navigation and dashboard

3. FORMS - Design main form with tabs:
   - Overview, Content, Assessment, Decision, Audit Trail
   - Add subgrids for related records

4. SECURITY ROLES - Create 4 roles per architecture.md:
   - MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor

5. BUSINESS PROCESS FLOW - Create 5-stage flow:
   - New → Triage → Assess → Decide → Closed

6. ENVIRONMENT VARIABLES - Create:
   - MCG_TenantId (Text)
   - MCG_PollingInterval (Number, default: 21600)

7. POWER AUTOMATE FLOW - Create ingestion flow per implementation-path-a.md
""")


def main():
    parser = argparse.ArgumentParser(
        description="Deploy MCG Solution to Dataverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example:
    python deploy_mcg.py \\
        --environment-url "https://org12345.crm.dynamics.com" \\
        --tenant-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \\
        --client-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \\
        --client-secret "your-secret-value"
        """,
    )
    parser.add_argument("--environment-url", required=True, help="Dataverse environment URL")
    parser.add_argument("--tenant-id", required=True, help="Azure AD tenant ID")
    parser.add_argument("--client-id", required=True, help="Azure AD application client ID")
    parser.add_argument("--client-secret", required=True, help="Azure AD application client secret")

    args = parser.parse_args()

    try:
        deploy(args.environment_url, args.tenant_id, args.client_id, args.client_secret)
    except Exception as e:
        print(f"\n❌ Deployment failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
