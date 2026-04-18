#!/usr/bin/env python3
"""Create Dataverse schema for Cross-Tenant External Sharing Governance.

Deploys five tables with shared and solution-specific option sets.
All operations are idempotent.

Tables:
  - fsi_ApprovedExternalTenant (UserOwned): Authoritative allow list of approved
    external tenants and their permitted access scope
  - fsi_ExternalShareFinding (OrganizationOwned): Detected external sharing
    violations per agent and per connection
  - fsi_TenantIsolationRecord (OrganizationOwned): Tenant isolation configuration
    audit history — one record per daily Flow 1 run
  - fsi_EntraCTARecord (OrganizationOwned): Entra cross-tenant access settings
    audit history — one record per weekly Flow 3 run
  - fsi_CrossTenantComplianceEvent (OrganizationOwned): Immutable audit log of all
    cross-tenant governance events — no delete for non-admins
"""

import argparse
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Shared Option Sets (reuse existing ACV option sets — existence check first)
# =============================================================================

SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "name": "fsi_acv_zone",
        "options": [
            ("Unclassified", 0),
            ("Zone 1", 1),
            ("Zone 2", 2),
            ("Zone 3", 3),
        ],
    },
}

# =============================================================================
# CTSG-Specific Option Sets
# =============================================================================

CTSG_OPTIONSETS = {
    "fsi_ctsg_relationshiptype": {
        "name": "fsi_ctsg_relationshiptype",
        "options": [
            ("Subsidiary", 0),
            ("Partner", 1),
            ("Vendor", 2),
            ("Regulator", 3),
            ("Auditor", 4),
            ("Other", 5),
        ],
    },
    "fsi_ctsg_approvalstatus": {
        "name": "fsi_ctsg_approvalstatus",
        "options": [
            ("Pending", 0),
            ("Approved", 1),
            ("Expired", 2),
            ("Suspended", 3),
            ("Revoked", 4),
        ],
    },
    "fsi_ctsg_risktier": {
        "name": "fsi_ctsg_risktier",
        "options": [
            ("Low", 0),
            ("Medium", 1),
            ("High", 2),
        ],
    },
    "fsi_ctsg_ppisolationdirection": {
        "name": "fsi_ctsg_ppisolationdirection",
        "options": [
            ("Inbound", 0),
            ("Outbound", 1),
            ("Both", 2),
            ("None", 3),
        ],
    },
    "fsi_ctsg_guestdetectionmethod": {
        "name": "fsi_ctsg_guestdetectionmethod",
        "options": [
            ("EXT# Parsing", 0),
            ("Mail Field", 1),
            ("CreationType", 2),
            ("Multi-Method Agreed", 3),
            ("Unresolved", 4),
        ],
    },
    "fsi_ctsg_findingtype": {
        "name": "fsi_ctsg_findingtype",
        "options": [
            ("Unapproved Tenant Isolation Exception", 0),
            ("Unapproved Guest Share", 1),
            ("Unapproved B2B Access", 2),
            ("Tenant Isolation Disabled", 3),
            ("Approved Tenant - Review Required", 4),
        ],
    },
    "fsi_ctsg_governancelayer": {
        "name": "fsi_ctsg_governancelayer",
        "options": [
            ("Layer 1 (Tenant Isolation)", 0),
            ("Layer 2 (Entra CTA)", 1),
            ("Layer 3 (Agent Share)", 2),
        ],
    },
    "fsi_ctsg_severity": {
        "name": "fsi_ctsg_severity",
        "options": [
            ("Critical", 0),
            ("High", 1),
            ("Medium", 2),
            ("Low", 3),
        ],
    },
    "fsi_ctsg_findingstatus": {
        "name": "fsi_ctsg_findingstatus",
        "options": [
            ("Open", 0),
            ("Under Review", 1),
            ("Remediated", 2),
            ("Approved Exception", 3),
            ("False Positive", 4),
        ],
    },
    "fsi_ctsg_remediationstatus": {
        "name": "fsi_ctsg_remediationstatus",
        "options": [
            ("Pending", 0),
            ("Approved for Auto-Remediation", 1),
            ("Manually Remediated", 2),
            ("Deferred", 3),
        ],
    },
    "fsi_ctsg_isolationcompliancestatus": {
        "name": "fsi_ctsg_isolationcompliancestatus",
        "options": [
            ("Compliant", 0),
            ("Non-Compliant - Isolation Disabled", 1),
            ("Non-Compliant - Unapproved Entries", 2),
        ],
    },
    "fsi_ctsg_ctacompliancestatus": {
        "name": "fsi_ctsg_ctacompliancestatus",
        "options": [
            ("Compliant", 0),
            ("Non-Compliant - Permissive Defaults", 1),
            ("Non-Compliant - Unapproved Partners", 2),
        ],
    },
    "fsi_ctsg_eventtype": {
        "name": "fsi_ctsg_eventtype",
        "options": [
            ("Tenant Isolation Validated", 0),
            ("Tenant Isolation Violation", 1),
            ("External Share Detected", 2),
            ("External Share Remediated", 3),
            ("Entra CTA Audited", 4),
            ("Entra CTA Violation", 5),
            ("Tenant Onboarding Initiated", 6),
            ("Tenant Approved", 7),
            ("Tenant Expired", 8),
            ("Tenant Suspended", 9),
            ("Tenant Revoked", 10),
            ("Annual Review Due", 11),
            ("Annual Review Overdue", 12),
            ("Annual Review Completed", 13),
            ("Remediation Approved", 14),
            ("Remediation Rejected", 15),
            ("API Schema Validation Failed", 16),
            ("Feature Flag Skip", 17),
            ("Flow Error", 18),
            ("Duplicate Remediation Skipped", 19),
            ("Critical Finding Manual Remediation Required", 20),
        ],
    },
    "fsi_ctsg_complianceimpact": {
        "name": "fsi_ctsg_complianceimpact",
        "options": [
            ("None", 0),
            ("Low", 1),
            ("Medium", 2),
            ("High", 3),
            ("Critical", 4),
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
    required: bool = False, description: str = "",
) -> dict:
    """Build a memo (multiline text) column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
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
    required: bool = True, description: str = "",
) -> dict:
    """Build a boolean column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
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

APPROVED_TENANT_COLUMNS = [
    _string_col("fsi_TenantName", "Tenant Name", 200,
                description="Display name of the external organization"),
    _string_col("fsi_TenantId", "Tenant ID", 100,
                description="Entra Tenant ID (GUID)"),
    _string_col("fsi_PrimaryDomain", "Primary Domain", 200,
                description="Primary verified domain"),
    _picklist_col("fsi_RelationshipType", "Relationship Type",
                  "fsi_ctsg_relationshiptype",
                  description="Type of relationship with external tenant"),
    _picklist_col("fsi_ApprovalStatus", "Approval Status",
                  "fsi_ctsg_approvalstatus",
                  description="Governance approval status"),
    _string_col("fsi_ApprovedBy", "Approved By", 200, required=False,
                description="UPN of governance committee approver"),
    _datetime_col("fsi_ApprovalDate", "Approval Date", required=False,
                  description="Date approval was granted"),
    _memo_col("fsi_BusinessJustification", "Business Justification", 10000,
              description="Minimum 100 characters"),
    _picklist_col("fsi_RiskTier", "Risk Tier", "fsi_ctsg_risktier",
                  description="Risk tier classification"),
    _memo_col("fsi_PermittedAccessScope", "Permitted Access Scope", 10000,
              required=True,
              description="Specific environments, agents, or connectors permitted"),
    _picklist_col("fsi_PPIsolationDirection", "PP Isolation Direction",
                  "fsi_ctsg_ppisolationdirection", required=False,
                  description="Power Platform tenant isolation direction"),
    _boolean_col("fsi_EntraB2BCollaboration", "Entra B2B Collaboration",
                 default=False,
                 description="Whether Entra B2B collaboration is permitted"),
    _boolean_col("fsi_EntraB2BDirectConnect", "Entra B2B Direct Connect",
                 default=False,
                 description="Whether Entra B2B direct connect is permitted"),
    _boolean_col("fsi_AgentSharePermitted", "Agent Share Permitted",
                 default=False,
                 description="Whether agent sharing with this tenant is permitted"),
    _datetime_col("fsi_AnnualReviewDue", "Annual Review Due",
                  description="Next annual review due date"),
    _datetime_col("fsi_LastReviewDate", "Last Review Date", required=False,
                  description="Date of most recent annual review"),
    _string_col("fsi_RequestingTeam", "Requesting Team", 200,
                description="Team that requested the external tenant relationship"),
    _boolean_col("fsi_SecurityAttestation", "Security Attestation",
                 default=False,
                 description="Whether security attestation has been completed"),
    _memo_col("fsi_ExpiryNotes", "Expiry Notes", 5000,
              description="Populated when status is Expired"),
    _memo_col("fsi_Notes", "Notes", 10000,
              description="Additional notes and comments"),
]

EXTERNAL_SHARE_FINDING_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100, required=False,
                description="Power Platform Bot ID (Layer 3 only; null for tenant-level findings)"),
    _string_col("fsi_AgentName", "Agent Name", 500, required=False,
                description="Display name from agent registry (Layer 3 only)"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100, required=False,
                description="Power Platform environment ID (Layer 3 only)"),
    _string_col("fsi_ExternalTenantTenantId", "External Tenant ID", 100,
                description="Tenant ID — populated even if not in registry"),
    _string_col("fsi_ExternalTenantName", "External Tenant Name", 500,
                required=False,
                description="Resolved via API"),
    _string_col("fsi_ExternalUserUpn", "External User UPN", 500,
                required=False,
                description="Layer 3 findings only"),
    _picklist_col("fsi_GuestDetectionMethod", "Guest Detection Method",
                  "fsi_ctsg_guestdetectionmethod", required=False,
                  description="Method used to detect guest user"),
    _picklist_col("fsi_FindingType", "Finding Type",
                  "fsi_ctsg_findingtype",
                  description="Classification of the external sharing finding"),
    _picklist_col("fsi_GovernanceLayer", "Governance Layer",
                  "fsi_ctsg_governancelayer",
                  description="Which governance layer detected the finding"),
    _picklist_col("fsi_Severity", "Severity",
                  "fsi_ctsg_severity",
                  description="Finding severity level"),
    _picklist_col("fsi_FindingStatus", "Finding Status",
                  "fsi_ctsg_findingstatus",
                  description="Current status of the finding"),
    _datetime_col("fsi_DetectedDate", "Detected Date",
                  description="When the finding was first detected"),
    _string_col("fsi_DetectedBy", "Detected By", 200,
                description="Flow name"),
    _picklist_col("fsi_RemediationStatus", "Remediation Status",
                  "fsi_ctsg_remediationstatus",
                  description="Current remediation status"),
    _datetime_col("fsi_RemediationDate", "Remediation Date", required=False,
                  description="When remediation was completed"),
    _memo_col("fsi_RemediationNotes", "Remediation Notes", 10000,
              description="Details about remediation actions taken"),
    _string_col("fsi_AssignedTo", "Assigned To", 200, required=False,
                description="UPN of assigned reviewer"),
    # Note: fsi_ApprovedExternalTenantLookup (lookup to fsi_approvedexternaltenant)
    # is handled as a post-deployment relationship step.
]

TENANT_ISOLATION_RECORD_COLUMNS = [
    _datetime_col("fsi_AuditDate", "Audit Date",
                  description="Date of the tenant isolation audit"),
    _boolean_col("fsi_IsolationEnabled", "Isolation Enabled",
                 description="Whether tenant isolation was enabled at audit time"),
    _integer_col("fsi_AllowListCount", "Allow List Count",
                 description="Total entries in the tenant isolation allow list"),
    _integer_col("fsi_ApprovedCount", "Approved Count",
                 description="Entries that match approved external tenants"),
    _integer_col("fsi_UnapprovedCount", "Unapproved Count",
                 description="Entries not found in approved external tenants"),
    _memo_col("fsi_AllowListSnapshot", "Allow List Snapshot", 100000,
              required=True,
              description="JSON array of allow-list entries"),
    _picklist_col("fsi_ComplianceStatus", "Compliance Status",
                  "fsi_ctsg_isolationcompliancestatus",
                  description="Isolation compliance assessment result"),
    _integer_col("fsi_FindingsCreated", "Findings Created",
                 description="Number of findings created during this audit run"),
    _boolean_col("fsi_ApiSchemaConfirmed", "API Schema Confirmed",
                 description="Whether API response matched expected schema"),
]

ENTRA_CTA_RECORD_COLUMNS = [
    _datetime_col("fsi_AuditDate", "Audit Date",
                  description="Date of the Entra CTA audit"),
    _boolean_col("fsi_DefaultInboundB2BBlocked", "Default Inbound B2B Blocked",
                 description="Whether default inbound B2B collaboration is blocked"),
    _boolean_col("fsi_DefaultOutboundB2BBlocked", "Default Outbound B2B Blocked",
                 description="Whether default outbound B2B collaboration is blocked"),
    _boolean_col("fsi_DefaultDirectConnectBlocked", "Default Direct Connect Blocked",
                 description="Whether default B2B direct connect is blocked"),
    _integer_col("fsi_PartnerEntryCount", "Partner Entry Count",
                 description="Total partner entries in CTA policy"),
    _integer_col("fsi_ApprovedPartnerCount", "Approved Partner Count",
                 description="Partners matching approved external tenants"),
    _integer_col("fsi_UnapprovedPartnerCount", "Unapproved Partner Count",
                 description="Partners not found in approved external tenants"),
    _memo_col("fsi_PartnerSnapshot", "Partner Snapshot", 100000,
              required=True,
              description="JSON array of partner policy entries"),
    _picklist_col("fsi_ComplianceStatus", "Compliance Status",
                  "fsi_ctsg_ctacompliancestatus",
                  description="CTA compliance assessment result"),
    _integer_col("fsi_FindingsCreated", "Findings Created",
                 description="Number of findings created during this audit run"),
]

COMPLIANCE_EVENT_COLUMNS = [
    _picklist_col("fsi_EventType", "Event Type",
                  "fsi_ctsg_eventtype",
                  description="Classification of the governance event"),
    _datetime_col("fsi_EventTimestamp", "Event Timestamp",
                  description="When the event occurred"),
    _string_col("fsi_TriggeredBy", "Triggered By", 200,
                description="Flow name or user UPN"),
    _string_col("fsi_ExternalTenantTenantId", "External Tenant ID", 100,
                required=False,
                description="Tenant ID of the external tenant involved"),
    _string_col("fsi_ExternalTenantName", "External Tenant Name", 500,
                required=False,
                description="Display name of the external tenant involved"),
    _memo_col("fsi_EventDetails", "Event Details", 10000,
              description="JSON payload with event-specific data"),
    _picklist_col("fsi_ComplianceImpact", "Compliance Impact",
                  "fsi_ctsg_complianceimpact",
                  description="Regulatory compliance impact assessment"),
    _string_col("fsi_FrameworkVersion", "Framework Version", 50,
                required=False,
                description="FSI-AgentGov framework version tag"),
]


# =============================================================================
# Table Definitions
# =============================================================================

TABLES = {
    "fsi_approvedexternaltenant": {
        "schema_name": "fsi_ApprovedExternalTenant",
        "display": "Approved External Tenant",
        "plural": "Approved External Tenants",
        "description": (
            "Authoritative allow list of approved external tenants "
            "and their permitted access scope"
        ),
        "ownership": "UserOwned",
        "columns": APPROVED_TENANT_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_externalsharefinding": {
        "schema_name": "fsi_ExternalShareFinding",
        "display": "External Share Finding",
        "plural": "External Share Findings",
        "description": (
            "Detected external sharing violations per agent and per connection"
        ),
        "ownership": "OrganizationOwned",
        "columns": EXTERNAL_SHARE_FINDING_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_tenantisolationrecord": {
        "schema_name": "fsi_TenantIsolationRecord",
        "display": "Tenant Isolation Record",
        "plural": "Tenant Isolation Records",
        "description": (
            "Tenant isolation configuration audit history — "
            "one record per daily Flow 1 run"
        ),
        "ownership": "OrganizationOwned",
        "columns": TENANT_ISOLATION_RECORD_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_entractarecord": {
        "schema_name": "fsi_EntraCTARecord",
        "display": "Entra CTA Record",
        "plural": "Entra CTA Records",
        "description": (
            "Entra cross-tenant access settings audit history — "
            "one record per weekly Flow 3 run"
        ),
        "ownership": "OrganizationOwned",
        "columns": ENTRA_CTA_RECORD_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_crosstenantcomplianceevent": {
        "schema_name": "fsi_CrossTenantComplianceEvent",
        "display": "Cross-Tenant Compliance Event",
        "plural": "Cross-Tenant Compliance Events",
        "description": (
            "Immutable audit log of all cross-tenant governance events — "
            "no delete for non-admins"
        ),
        "ownership": "OrganizationOwned",
        "columns": COMPLIANCE_EVENT_COLUMNS,
        "entity_set_name": None,
    },
}

# =============================================================================
# Alternate Key Definitions
# =============================================================================

ALTERNATE_KEYS = [
    {
        "entity": "fsi_approvedexternaltenant",
        "schema_name": "fsi_TenantIdUniqueKey",
        "display": "Tenant ID Unique Key",
        "key_columns": ["fsi_tenantid"],
    },
    # NOTE: A composite alternate key on fsi_externalsharefinding was removed.
    # Dataverse alt keys cannot include picklist columns (findingtype) or
    # nullable columns (agentid/upn), so dedup must happen at the flow layer
    # via $filter prior to Create. See flow doc Step "Pre-Create dedup".
]


# =============================================================================
# Deployment Functions
# =============================================================================


def _build_optionset_metadata(os_def: dict) -> dict:
    """Construct a Dataverse global OptionSetMetadata payload from a CTSG def."""
    name = os_def["name"]
    options = os_def["options"]
    display_label = os_def.get("display") or " ".join(
        word.capitalize() for word in name.split("_")[1:]
    ) or name
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
        "Name": name,
        "DisplayName": _label(display_label),
        "Description": _label(os_def.get("description", display_label)),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "IsCustomOptionSet": True,
        "Options": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": value,
                "Label": _label(label),
            }
            for (label, value) in options
        ],
    }


def create_shared_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create or verify shared global option sets.

    These option sets are shared with ACV and other solutions.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating/Verifying Shared Option Sets]")

    for os_name, os_def in SHARED_OPTIONSETS.items():
        client.create_option_set(_build_optionset_metadata(os_def))


def create_ctsg_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create CTSG-specific global option sets.

    These option sets are unique to Cross-Tenant External Sharing Governance.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating CTSG Option Sets]")

    for os_name, os_def in CTSG_OPTIONSETS.items():
        client.create_option_set(_build_optionset_metadata(os_def))


def create_table_with_columns(
    client: DataverseClient,
    table_name: str,
    table_def: dict,
    columns: list[dict],
    dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent).

    Args:
        client: DataverseClient instance
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
        client.create_column(logical_name, col)


def create_alternate_keys(client: DataverseClient, dry_run: bool = False) -> None:
    """Create alternate keys on CTSG tables (idempotent).

    Keys:
      - fsi_TenantIdUniqueKey on fsi_approvedexternaltenant — uniqueness on tenant GUID

    NOTE: A composite key on fsi_externalsharefinding was removed because Dataverse
    alternate keys cannot include picklist columns or nullable columns. Finding
    deduplication is performed at the flow layer via $filter prior to Create.
    """
    print("\n[Creating Alternate Keys]")

    for alt_key in ALTERNATE_KEYS:
        entity = alt_key["entity"]
        key_name = alt_key["schema_name"]

        # Idempotent check — query existing keys
        if dry_run or client.dry_run:
            print(f"  [DRY-RUN] Would create alternate key: {key_name} on {entity}")
            continue

        try:
            url = (
                f"{client.api_url}EntityDefinitions"
                f"(LogicalName='{entity}')/Keys"
            )
            resp = client._session.get(url, headers=client._get_headers())
            resp.raise_for_status()
            existing_keys = resp.json().get("value", [])

            already_exists = False
            for key in existing_keys:
                if key.get("SchemaName", "").lower() == key_name.lower():
                    print(f"  {key_name}: already exists, skipping")
                    already_exists = True
                    break
            if already_exists:
                continue
        except Exception:
            pass  # If check fails, attempt creation anyway

        # Create the alternate key
        key_definition = {
            "@odata.type": "Microsoft.Dynamics.CRM.EntityKeyMetadata",
            "SchemaName": key_name,
            "DisplayName": _label(alt_key["display"]),
            "KeyAttributes": alt_key["key_columns"],
        }

        try:
            url = (
                f"{client.api_url}EntityDefinitions"
                f"(LogicalName='{entity}')/Keys"
            )
            resp = client._session.post(
                url, headers=client._get_headers(), json=key_definition
            )
            resp.raise_for_status()
            print(f"  {key_name}: created on {entity}")
        except Exception as e:
            print(f"  {key_name}: creation failed — {e}")
            print("    Alternate keys may take a few minutes to activate.")
            print("    Verify status in Power Platform admin center.")


def create_schema(client: DataverseClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment.

    Order: shared option sets → CTSG option sets → tables → columns →
    alternate keys. All operations are idempotent — safe to re-run.
    """
    print("=" * 60)
    print("CTSG Dataverse Schema Deployment")
    print("  Cross-Tenant External Sharing Governance")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Shared option sets (must exist before tables reference them)
    create_shared_optionsets(client, dry_run)

    # Step 2: CTSG-specific option sets
    create_ctsg_optionsets(client, dry_run)

    # Step 3: Tables and columns
    print("\n[Creating Tables and Columns]")
    for table_name, table_def in TABLES.items():
        print(f"\n  --- {table_def['display']} ({table_def['ownership']}) ---")
        create_table_with_columns(
            client, table_name, table_def, table_def["columns"], dry_run
        )

    # Step 4: Alternate keys
    create_alternate_keys(client, dry_run)

    # Summary
    total_optionsets = len(SHARED_OPTIONSETS) + len(CTSG_OPTIONSETS)
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print(f"  Option sets: {total_optionsets}")
    print(f"  Tables: {len(TABLES)}")
    total_cols = sum(len(t["columns"]) for t in TABLES.values())
    print(f"  Columns: {total_cols}")
    print(f"  Alternate keys: {len(ALTERNATE_KEYS)}")
    print("=" * 60)


# =============================================================================
# Documentation Generation
# =============================================================================


def _extract_label_text(label_obj) -> str:
    """Extract display text from a Dataverse Label structure."""
    if isinstance(label_obj, dict):
        localized = label_obj.get("LocalizedLabels", [])
        if localized:
            return localized[0].get("Label", "")
    return ""


def _col_type_display(col: dict) -> str:
    """Return a human-readable column type string."""
    odata_type = col.get("@odata.type", "")
    if "String" in odata_type:
        return f"String({col.get('MaxLength', '')})"
    if "Memo" in odata_type:
        return f"Memo({col.get('MaxLength', '')})"
    if "Integer" in odata_type:
        return "Integer"
    if "Boolean" in odata_type:
        return "Boolean"
    if "DateTime" in odata_type:
        return "DateTime"
    if "Picklist" in odata_type:
        return "Picklist"
    if "Lookup" in odata_type:
        return "Lookup"
    return odata_type.split(".")[-1] if odata_type else "Unknown"


def _optionset_name_from_col(col: dict) -> str:
    """Extract global option set name from a picklist column definition."""
    bind = col.get("GlobalOptionSet@odata.bind", "")
    if "Name='" in bind:
        return bind.split("Name='")[1].rstrip("')")
    return ""


def generate_schema_docs() -> str:
    """Generate a Markdown reference document from the in-memory schema definitions."""
    lines: list[str] = []

    # Header
    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append(
        "> Auto-generated from `create_ctsg_dataverse_schema.py`. "
        "Do not edit manually."
    )
    lines.append("")

    # Tables summary
    lines.append("## Tables")
    lines.append("")
    lines.append("| SchemaName | Logical Name | Ownership | Description |")
    lines.append("|---|---|---|---|")
    for logical_name, tbl in TABLES.items():
        lines.append(
            f"| {tbl['schema_name']} | {logical_name} "
            f"| {tbl['ownership']} | {tbl['description']} |"
        )
    lines.append("")

    # Columns per table
    lines.append("## Columns")
    lines.append("")

    for logical_name, tbl in TABLES.items():
        lines.append(f"### {tbl['schema_name']} (`{logical_name}`)")
        lines.append("")
        lines.append(
            "| SchemaName | Logical Name | Type | Required | Description | Option Set |"
        )
        lines.append("|---|---|---|---|---|---|")

        for col in tbl["columns"]:
            sn = col.get("SchemaName", "")
            ln = sn.lower()
            ctype = _col_type_display(col)
            req_val = col.get("RequiredLevel", {}).get("Value", "None")
            required = "Yes" if req_val == "ApplicationRequired" else "No"
            desc = _extract_label_text(col.get("Description", {}))
            os_name = _optionset_name_from_col(col)
            os_cell = f"`{os_name}`" if os_name else ""
            lines.append(
                f"| {sn} | {ln} | {ctype} | {required} | {desc} | {os_cell} |"
            )

        lines.append("")

    # Option sets
    lines.append("## Option Sets")
    lines.append("")

    all_optionsets = {**SHARED_OPTIONSETS, **CTSG_OPTIONSETS}
    for os_name, os_def in all_optionsets.items():
        lines.append(f"### `{os_name}`")
        lines.append("")
        lines.append("| Label | Value |")
        lines.append("|---|---|")
        for label, value in os_def["options"]:
            lines.append(f"| {label} | {value} |")
        lines.append("")

    # Alternate keys
    lines.append("## Alternate Keys")
    lines.append("")
    lines.append("| Key Name | Table | Columns |")
    lines.append("|---|---|---|")
    for alt_key in ALTERNATE_KEYS:
        cols = ", ".join(f"`{c}`" for c in alt_key["key_columns"])
        lines.append(
            f"| {alt_key['schema_name']} | {alt_key['entity']} | {cols} |"
        )
    lines.append("")

    # Post-deployment note
    lines.append("## Post-Deployment Steps")
    lines.append("")
    lines.append(
        "- Create lookup column `fsi_ApprovedExternalTenantLookup` on "
        "`fsi_externalsharefinding` referencing `fsi_approvedexternaltenant`. "
        "This relationship is handled as a post-deployment step."
    )
    lines.append("")

    return "\n".join(lines)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for schema deployment."""
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse schema for Cross-Tenant External Sharing Governance"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_ctsg_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_ctsg_dataverse_schema.py \\\n"
            "    --tenant-id $CTSG_TENANT_ID \\\n"
            "    --client-id $CTSG_CLIENT_ID \\\n"
            "    --client-secret $CTSG_CLIENT_SECRET \\\n"
            "    --environment-url $CTSG_ENVIRONMENT_URL\n\n"
            "  # Generate schema documentation only\n"
            "  python create_ctsg_dataverse_schema.py --output-docs\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CTSG_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set CTSG_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CTSG_CLIENT_ID"),
        help="Service principal app ID (or set CTSG_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CTSG_CLIENT_SECRET"),
        help="Service principal secret (or set CTSG_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CTSG_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set CTSG_ENVIRONMENT_URL env var)",
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
    parser.add_argument(
        "--output-docs",
        action="store_true",
        help=(
            "Generate docs/dataverse-schema.md and exit "
            "(no credentials required)"
        ),
    )

    args = parser.parse_args()

    # --output-docs: generate schema reference docs and exit immediately
    if args.output_docs:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        solution_root = os.path.dirname(script_dir)
        docs_dir = os.path.join(solution_root, "docs")
        os.makedirs(docs_dir, exist_ok=True)
        out_path = os.path.join(docs_dir, "dataverse-schema.md")
        md = generate_schema_docs()
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(md)
        print(f"Schema docs written to {out_path}")
        sys.exit(0)

    # Validate required arguments
    if not args.tenant_id:
        print("ERROR: --tenant-id or CTSG_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or CTSG_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = DataverseClient(
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
