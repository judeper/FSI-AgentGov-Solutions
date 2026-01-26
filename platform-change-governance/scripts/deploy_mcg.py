#!/usr/bin/env python3
"""
MCG Solution Deployment Script

Deploys the complete Message Center Governance solution to Dataverse via Web API.

Creates:
    - Publisher & Solution
    - 3 Tables (MessageCenterPost, AssessmentLog, DecisionLog) with AI-friendly descriptions
    - 26 Columns with AI-friendly descriptions for agent reasoning
    - 2 Relationships and 1 Alternate Key
    - 2 Environment Variables (MCG_TenantId, MCG_PollingInterval)
    - 4 Security Roles (MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor)
    - 4 Views (All Open Posts, New Posts, High Severity, My Assigned)
    - Main Form with 5 tabs (Overview, Content, Assessment, Decision, Audit Trail)
    - Model-Driven App (Message Center Governance) with security role associations
    - Business Process Flow placeholder (5-stage governance workflow)

Usage:
    python deploy_mcg.py \\
        --environment-url "https://org12345.crm.dynamics.com" \\
        --tenant-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \\
        --client-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \\
        --client-secret "your-secret-value"

Prerequisites:
    1. Azure AD App Registration with client secret
    2. Dataverse Application User with System Administrator role (required for security role creation)
    3. pip install requests msal

Post-Deployment (Manual):
    1. Create Azure AD app registration with ServiceMessage.Read.All (Application permission)
    2. Grant admin consent for the Graph API permission
    3. Create Power Automate flow for Message Center ingestion
    4. Configure and activate Business Process Flow in portal
"""

import argparse
import getpass
import os
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
# All tables and columns include AI-friendly descriptions for agent reasoning
TABLE_DEFINITIONS = {
    "mcg_messagecenterpost": {
        "schema_name": "mcg_MessageCenterPost",
        "display_name": "Message Center Post",
        "display_collection_name": "Message Center Posts",
        "description": "Stores Microsoft 365 Message Center posts for governance tracking. Each record represents a single announcement requiring organizational assessment and decision. AI agents use this to triage, assess impact, and recommend actions.",
        "ownership_type": "UserOwned",
        "primary_name": {
            "schema_name": "mcg_Title",
            "display_name": "Title",
            "max_length": 500,
            "description": "Title of the Message Center post. Primary identifier for users and AI triage.",
        },
        "columns": [
            {
                "schema_name": "mcg_MessageCenterId",
                "type": "String",
                "display_name": "Message Center ID",
                "max_length": 50,
                "required": True,
                "description": "Unique ID from Microsoft (MC######). Used as alternate key for upsert during sync.",
            },
            {
                "schema_name": "mcg_Category",
                "type": "Picklist",
                "display_name": "Category",
                "choice": "mcg_category",
                "required": True,
                "description": "Microsoft classification. Values: 'Prevent or Fix Issue' (URGENT - security/compliance/disruption), 'Plan for Change' (UPCOMING - scheduled change needing preparation), 'Stay Informed' (FYI - informational only).",
            },
            {
                "schema_name": "mcg_Severity",
                "type": "Picklist",
                "display_name": "Severity",
                "choice": "mcg_severity",
                "required": True,
                "description": "Microsoft-assigned urgency. Values: Normal (standard cycle), High (review within 24-48h), Critical (IMMEDIATE action required). Correlate with ActionRequiredBy date.",
            },
            {
                "schema_name": "mcg_Services",
                "type": "Memo",
                "display_name": "Services",
                "max_length": 4000,
                "description": "Comma-separated list of affected Microsoft 365 services (Exchange, SharePoint, Teams, etc.). Map to organizational dependencies.",
            },
            {
                "schema_name": "mcg_Tags",
                "type": "Memo",
                "display_name": "Tags",
                "max_length": 4000,
                "description": "Microsoft-provided categorization tags. Use for pattern matching and similar post identification.",
            },
            {
                "schema_name": "mcg_StartDateTime",
                "type": "DateTime",
                "display_name": "Start Date/Time",
                "description": "When the change takes effect. Use with EndDateTime to determine change window.",
            },
            {
                "schema_name": "mcg_EndDateTime",
                "type": "DateTime",
                "display_name": "End Date/Time",
                "description": "When the change period ends. May be null for permanent changes.",
            },
            {
                "schema_name": "mcg_ActionRequiredBy",
                "type": "DateTime",
                "display_name": "Action Required By",
                "description": "Deadline for required actions. Critical for triage prioritization. Null means no deadline.",
            },
            {
                "schema_name": "mcg_Body",
                "type": "Memo",
                "display_name": "Body",
                "max_length": 100000,
                "description": "Full HTML content from Message Center. Contains technical details needed for impact assessment. May be lengthy.",
            },
            {
                "schema_name": "mcg_State",
                "type": "Picklist",
                "display_name": "State",
                "choice": "mcg_state",
                "required": True,
                "description": "Governance workflow stage. Values: New (unreviewed), Triage (categorizing), Assess (evaluating impact), Decide (approval pending), Closed (complete). Drives BPF progression.",
            },
            {
                "schema_name": "mcg_ImpactAssessment",
                "type": "Picklist",
                "display_name": "Impact Assessment",
                "choice": "mcg_impactassessment",
                "description": "Organization-specific impact. Values: None (not applicable), Low (few users/non-critical), Medium (multiple users/important services), High (critical services/large user base/compliance).",
            },
            {
                "schema_name": "mcg_Relevance",
                "type": "Picklist",
                "display_name": "Relevance",
                "choice": "mcg_relevance",
                "description": "Applicability to organization. Values: Not Applicable (doesn't affect us), Informational (FYI only), Action Required (needs organizational response).",
            },
            {
                "schema_name": "mcg_Decision",
                "type": "Picklist",
                "display_name": "Decision",
                "choice": "mcg_decision",
                "description": "Final governance decision. Values: Accept (proceed with change), Defer (delay response), Escalate (needs executive review), No Action Required (close record).",
            },
            {
                "schema_name": "mcg_DecisionRationale",
                "type": "Memo",
                "display_name": "Decision Rationale",
                "max_length": 10000,
                "description": "Business justification for decision. Required for audit trail. Include risk assessment and stakeholder input.",
            },
            {
                "schema_name": "mcg_LastModifiedDateTime",
                "type": "DateTime",
                "display_name": "Last Modified Date/Time",
                "description": "Microsoft's last update timestamp. Detect content changes requiring re-assessment.",
            },
            {
                "schema_name": "mcg_ClosedOn",
                "type": "DateTime",
                "display_name": "Closed On",
                "description": "When this governance item was closed. Set when State transitions to Closed.",
            },
        ],
        "lookups": [
            {
                "schema_name": "mcg_ClosedBy",
                "display_name": "Closed By",
                "target_entity": "systemuser",
                "required": False,
                "description": "User who closed this governance item. Populated when State transitions to Closed.",
            },
        ],
    },
    "mcg_assessmentlog": {
        "schema_name": "mcg_AssessmentLog",
        "display_name": "Assessment Log",
        "display_collection_name": "Assessment Logs",
        "description": "Audit trail of impact assessments. Each record documents an evaluation of a Message Center post's organizational impact. AI agents should include reasoning chain in Notes.",
        "ownership_type": "UserOwned",
        "primary_name": {
            "schema_name": "mcg_Name",
            "display_name": "Name",
            "max_length": 300,
            "description": "Auto-generated assessment identifier. Format: Post title + timestamp.",
        },
        "columns": [
            {
                "schema_name": "mcg_AssessedOn",
                "type": "DateTime",
                "display_name": "Assessed On",
                "required": True,
                "description": "When this assessment was performed. Audit timestamp.",
            },
            {
                "schema_name": "mcg_ImpactAssessment",
                "type": "Picklist",
                "display_name": "Impact Assessment",
                "choice": "mcg_impactassessment",
                "required": True,
                "description": "Impact level determined by this assessment. Values: None (not applicable), Low (few users/non-critical), Medium (multiple users/important services), High (critical services/large user base/compliance).",
            },
            {
                "schema_name": "mcg_Notes",
                "type": "Memo",
                "display_name": "Notes",
                "max_length": 10000,
                "description": "Detailed analysis including affected systems, user groups, technical considerations. AI should include reasoning chain.",
            },
            {
                "schema_name": "mcg_RecommendedAction",
                "type": "Picklist",
                "display_name": "Recommended Action",
                "choice": "mcg_recommendedaction",
                "description": "Assessor's recommendation. Values: Implement (proceed, benefits outweigh risks), Defer (postpone, not urgent), Dismiss (no action, not applicable), Escalate (needs executive review).",
            },
            {
                "schema_name": "mcg_AffectedSystems",
                "type": "Memo",
                "display_name": "Affected Systems",
                "max_length": 4000,
                "description": "Specific organizational systems/applications impacted. Comma-separated list.",
            },
        ],
    },
    "mcg_decisionlog": {
        "schema_name": "mcg_DecisionLog",
        "display_name": "Decision Log",
        "display_collection_name": "Decision Logs",
        "description": "Audit trail of governance decisions. Documents approvals, deferrals, and escalations with rationale for compliance.",
        "ownership_type": "UserOwned",
        "primary_name": {
            "schema_name": "mcg_Name",
            "display_name": "Name",
            "max_length": 300,
            "description": "Auto-generated decision identifier. Format: Post title + decision + timestamp.",
        },
        "columns": [
            {
                "schema_name": "mcg_DecidedOn",
                "type": "DateTime",
                "display_name": "Decided On",
                "required": True,
                "description": "When decision was made. Audit timestamp for compliance.",
            },
            {
                "schema_name": "mcg_Decision",
                "type": "Picklist",
                "display_name": "Decision",
                "choice": "mcg_decision",
                "required": True,
                "description": "The governance decision. Values: Accept (proceed), Defer (delay), Escalate (executive review), No Action Required (close).",
            },
            {
                "schema_name": "mcg_DecisionRationale",
                "type": "Memo",
                "display_name": "Decision Rationale",
                "max_length": 10000,
                "required": True,
                "description": "Business justification. Must include risk assessment, stakeholder input, compliance considerations. Required for audit.",
            },
            {
                "schema_name": "mcg_ExternalTicketReference",
                "type": "String",
                "display_name": "External Ticket Reference",
                "max_length": 200,
                "description": "Link to external ticketing system (ServiceNow, Jira, etc.) if change requires tracked work.",
            },
        ],
        "lookups": [
            {
                "schema_name": "mcg_DecidedBy",
                "display_name": "Decided By",
                "target_entity": "systemuser",
                "required": True,
                "description": "User who made this governance decision. Required for SOX/FINRA compliance audit trail.",
            },
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
        "lookup_description": "Lookup to parent MessageCenterPost record. Required - every assessment belongs to one post.",
    },
    {
        "schema_name": "mcg_messagecenterpost_decisionlogs",
        "referenced_entity": "mcg_messagecenterpost",
        "referencing_entity": "mcg_decisionlog",
        "lookup_schema_name": "mcg_MessageCenterPostId",
        "lookup_display_name": "Message Center Post",
        "lookup_description": "Lookup to parent MessageCenterPost record. Required - every decision belongs to one post.",
    },
]

# Environment Variable definitions
ENVIRONMENT_VARIABLE_DEFINITIONS = [
    {
        "schemaname": "mcg_TenantId",
        "displayname": "MCG Tenant ID",
        "type": 100000000,  # String
        "description": "Azure AD tenant ID for Microsoft Graph API authentication",
    },
    {
        "schemaname": "mcg_PollingInterval",
        "displayname": "MCG Polling Interval",
        "type": 100000001,  # Number
        "description": "Polling interval in seconds for Message Center sync (default: 21600 = 6 hours)",
        "default_value": "21600",
    },
]

# View definitions for MessageCenterPost table
VIEW_DEFINITIONS = [
    {
        "name": "All Open Posts",
        "entity": "mcg_messagecenterpost",
        "filter": '<condition attribute="mcg_state" operator="ne" value="100000004"/>',
        "is_default": True,
        "description": "All posts that are not closed",
    },
    {
        "name": "New Posts - Awaiting Triage",
        "entity": "mcg_messagecenterpost",
        "filter": '<condition attribute="mcg_state" operator="eq" value="100000000"/>',
        "is_default": False,
        "description": "New posts requiring initial triage",
    },
    {
        "name": "High Severity Posts",
        "entity": "mcg_messagecenterpost",
        "filter": '<filter type="or"><condition attribute="mcg_severity" operator="eq" value="100000001"/><condition attribute="mcg_severity" operator="eq" value="100000002"/></filter>',
        "is_default": False,
        "description": "Posts marked as High or Critical severity",
        "is_or_filter": True,
    },
    {
        "name": "My Assigned Posts",
        "entity": "mcg_messagecenterpost",
        "filter": '<condition attribute="ownerid" operator="eq-userid"/>',
        "is_default": False,
        "description": "Posts assigned to the current user",
    },
]

# View columns to display in the grid
VIEW_COLUMNS = [
    {"name": "mcg_title", "width": 300},
    {"name": "mcg_category", "width": 120},
    {"name": "mcg_severity", "width": 100},
    {"name": "mcg_state", "width": 100},
    {"name": "mcg_actionrequiredby", "width": 140},
    {"name": "ownerid", "width": 150},
    {"name": "createdon", "width": 140},
]

# Security Role definitions
ROLE_DEFINITIONS = {
    "mcg_MCAdmin": {
        "name": "MC Admin",
        "businessunitid": None,  # Will be populated at runtime
        "privileges": {
            "mcg_messagecenterpost": {
                "Create": "Organization",
                "Read": "Organization",
                "Write": "Organization",
                "Delete": "Organization",
                "Append": "Organization",
                "AppendTo": "Organization",
                "Assign": "Organization",
                "Share": "Organization",
            },
            "mcg_assessmentlog": {
                "Create": "Organization",
                "Read": "Organization",
                "Write": "Organization",
                "Delete": "Organization",
                "Append": "Organization",
                "AppendTo": "Organization",
                "Assign": "Organization",
                "Share": "Organization",
            },
            "mcg_decisionlog": {
                "Create": "Organization",
                "Read": "Organization",
                "Write": "Organization",
                # Delete removed - audit records should not be deleted
                "Append": "Organization",
                "AppendTo": "Organization",
            },
        },
    },
    "mcg_MCOwner": {
        "name": "MC Owner",
        "businessunitid": None,
        "privileges": {
            "mcg_messagecenterpost": {
                "Create": "User",
                "Read": "BusinessUnit",
                "Write": "User",
                "Delete": "User",
                "Append": "User",
                "AppendTo": "User",
                "Assign": "User",
            },
            "mcg_assessmentlog": {
                "Create": "User",
                "Read": "BusinessUnit",
                "Write": "User",
                "Delete": "User",
                "Append": "User",
                "AppendTo": "User",
                "Assign": "User",
            },
            "mcg_decisionlog": {
                "Create": "User",
                "Read": "BusinessUnit",
                "Write": "User",
                "Append": "User",
                "AppendTo": "User",
                "Assign": "User",
            },
        },
    },
    "mcg_MCComplianceReviewer": {
        "name": "MC Compliance Reviewer",
        "businessunitid": None,
        "privileges": {
            "mcg_messagecenterpost": {
                "Read": "Organization",
                "Write": "BusinessUnit",  # Can update compliance fields
                "Append": "BusinessUnit",
                "AppendTo": "BusinessUnit",
            },
            "mcg_assessmentlog": {
                "Read": "Organization",
            },
            "mcg_decisionlog": {
                "Read": "Organization",
                "Create": "User",  # Can add compliance decisions
                "Append": "User",
                "AppendTo": "User",
                # Write removed - decisions are immutable once created for compliance
            },
        },
    },
    "mcg_MCAuditor": {
        "name": "MC Auditor",
        "businessunitid": None,
        "privileges": {
            "mcg_messagecenterpost": {
                "Read": "Organization",
            },
            "mcg_assessmentlog": {
                "Read": "Organization",
            },
            "mcg_decisionlog": {
                "Read": "Organization",
            },
        },
    },
}

# Privilege depth mappings - uses Dataverse Web API string enum names
# Per 2024 Microsoft docs: Basic=0 (own records), Local=1 (BU), Deep=2 (parent:child BUs), Global=3 (org-wide)
PRIVILEGE_DEPTH = {
    "User": "Basic",           # Own records only
    "BusinessUnit": "Local",   # Business unit level
    "ParentChild": "Deep",     # Parent:child business units
    "Organization": "Global",  # Organization-wide
}

# Form definition for MessageCenterPost
FORM_DEFINITION = {
    "entity": "mcg_messagecenterpost",
    "name": "Main Form",
    "type": 2,  # Main form
    "tabs": [
        {
            "name": "tab_overview",
            "label": "Overview",
            "sections": [
                {
                    "name": "section_summary",
                    "label": "Summary",
                    "columns": 2,
                    "controls": [
                        {"attribute": "mcg_title", "row": 1, "col": 1, "rowspan": 1, "colspan": 2},
                        {"attribute": "mcg_messagecenterid", "row": 2, "col": 1},
                        {"attribute": "mcg_category", "row": 2, "col": 2},
                        {"attribute": "mcg_severity", "row": 3, "col": 1},
                        {"attribute": "mcg_state", "row": 3, "col": 2},
                        {"attribute": "ownerid", "row": 4, "col": 1},
                        {"attribute": "mcg_actionrequiredby", "row": 4, "col": 2},
                    ],
                },
                {
                    "name": "section_dates",
                    "label": "Dates",
                    "columns": 2,
                    "controls": [
                        {"attribute": "mcg_startdatetime", "row": 1, "col": 1},
                        {"attribute": "mcg_enddatetime", "row": 1, "col": 2},
                        {"attribute": "createdon", "row": 2, "col": 1},
                        {"attribute": "mcg_lastmodifieddatetime", "row": 2, "col": 2},
                    ],
                },
            ],
        },
        {
            "name": "tab_content",
            "label": "Content",
            "sections": [
                {
                    "name": "section_body",
                    "label": "Message Body",
                    "columns": 1,
                    "controls": [
                        {"attribute": "mcg_body", "row": 1, "col": 1, "rowspan": 6},
                    ],
                },
                {
                    "name": "section_metadata",
                    "label": "Metadata",
                    "columns": 2,
                    "controls": [
                        {"attribute": "mcg_services", "row": 1, "col": 1},
                        {"attribute": "mcg_tags", "row": 1, "col": 2},
                    ],
                },
            ],
        },
        {
            "name": "tab_assessment",
            "label": "Assessment",
            "sections": [
                {
                    "name": "section_impact",
                    "label": "Impact Assessment",
                    "columns": 2,
                    "controls": [
                        {"attribute": "mcg_impactassessment", "row": 1, "col": 1},
                        {"attribute": "mcg_relevance", "row": 1, "col": 2},
                    ],
                },
                {
                    "name": "section_assessment_log",
                    "label": "Assessment History",
                    "columns": 1,
                    "subgrid": {
                        "name": "subgrid_assessments",
                        "entity": "mcg_assessmentlog",
                        "relationship": "mcg_messagecenterpost_assessmentlogs",
                    },
                },
            ],
        },
        {
            "name": "tab_decision",
            "label": "Decision",
            "sections": [
                {
                    "name": "section_decision_fields",
                    "label": "Decision",
                    "columns": 2,
                    "controls": [
                        {"attribute": "mcg_decision", "row": 1, "col": 1, "colspan": 2},
                        {"attribute": "mcg_decisionrationale", "row": 2, "col": 1, "colspan": 2, "rowspan": 3},
                    ],
                },
                {
                    "name": "section_decision_log",
                    "label": "Decision History",
                    "columns": 1,
                    "subgrid": {
                        "name": "subgrid_decisions",
                        "entity": "mcg_decisionlog",
                        "relationship": "mcg_messagecenterpost_decisionlogs",
                    },
                },
            ],
        },
        {
            "name": "tab_audit",
            "label": "Audit Trail",
            "sections": [
                {
                    "name": "section_timeline",
                    "label": "Timeline",
                    "columns": 1,
                    "timeline": True,
                },
            ],
        },
    ],
}

# Model-Driven App definition
APP_DEFINITION = {
    "name": "Message Center Governance",
    "uniquename": "mcg_MessageCenterGovernance",
    "description": "Governance application for Microsoft Message Center posts",
    "entities": ["mcg_messagecenterpost", "mcg_assessmentlog", "mcg_decisionlog"],
}

# Business Process Flow definition
BPF_DEFINITION = {
    "name": "MCG Governance Process",
    "uniquename": "mcg_mcggovernanceprocess",
    "entity": "mcg_messagecenterpost",
    "stages": [
        {"name": "New", "state_value": 100000000},
        {"name": "Triage", "state_value": 100000001},
        {"name": "Assess", "state_value": 100000002},
        {"name": "Decide", "state_value": 100000003},
        {"name": "Closed", "state_value": 100000004},
    ],
}


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


def make_description(text: str) -> dict | None:
    """Create a Dataverse Description Label structure. Returns None for empty text."""
    if not text or not text.strip():
        return None
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.Label",
        "LocalizedLabels": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                "Label": text.strip(),
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

        # Build primary attribute with optional description
        primary_attr = {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": primary["schema_name"],
            "DisplayName": make_label(primary["display_name"]),
            "IsPrimaryName": True,
            "MaxLength": primary["max_length"],
            "RequiredLevel": make_required_level(True),
            "FormatName": {"Value": "Text"},
        }
        primary_desc = make_description(primary.get("description", ""))
        if primary_desc:
            primary_attr["Description"] = primary_desc

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
            "Attributes": [primary_attr],
        }

        # Add table description if provided
        table_desc = make_description(table_def.get("description", ""))
        if table_desc:
            payload["Description"] = table_desc

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

        # Add description if provided
        col_desc = make_description(column_def.get("description", ""))
        if col_desc:
            payload["Description"] = col_desc

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

    def add_lookup_column(self, table_logical_name: str, lookup_def: dict) -> None:
        """Add a lookup column to an existing table.

        This creates a single-entity lookup to system entities like systemuser.
        For lookups to custom entities, use create_relationship instead.
        """
        schema_name = lookup_def["schema_name"]
        target_entity = lookup_def["target_entity"]

        # Check if column already exists
        existing = self.get(
            f"EntityDefinitions(LogicalName='{table_logical_name}')/Attributes(LogicalName='{schema_name.lower()}')"
        )
        if existing.get("LogicalName"):
            return  # Column exists

        payload: dict[str, Any] = {
            "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
            "SchemaName": schema_name,
            "DisplayName": make_label(lookup_def["display_name"]),
            "RequiredLevel": make_required_level(lookup_def.get("required", False)),
            "Targets": [target_entity],
        }

        # Add description if provided
        lookup_desc = make_description(lookup_def.get("description", ""))
        if lookup_desc:
            payload["Description"] = lookup_desc

        response = self._request(
            "POST",
            f"EntityDefinitions(LogicalName='{table_logical_name}')/Attributes",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Add lookup {schema_name} failed: {response.status_code} - {response.text}")

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

        # Build lookup attribute with optional description
        lookup_attr = {
            "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
            "SchemaName": rel_def["lookup_schema_name"],
            "DisplayName": make_label(rel_def["lookup_display_name"]),
            "RequiredLevel": make_required_level(True),
        }
        lookup_desc = make_description(rel_def.get("lookup_description", ""))
        if lookup_desc:
            lookup_attr["Description"] = lookup_desc

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
            "Lookup": lookup_attr,
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
    # Environment Variables
    # -------------------------------------------------------------------------

    def create_environment_variable(self, var_def: dict) -> None:
        """Create an environment variable definition and optionally a default value."""
        schema_name = var_def["schemaname"]

        # Check if already exists
        existing = self.get(
            f"environmentvariabledefinitions?$filter=schemaname eq '{schema_name}'"
        )
        if existing.get("value"):
            print(f"      {var_def['displayname']} already exists, skipping")
            return

        # Create the definition
        payload = {
            "schemaname": schema_name,
            "displayname": var_def["displayname"],
            "type": var_def["type"],
            "description": var_def.get("description", ""),
        }

        response = self._request(
            "POST",
            "environmentvariabledefinitions",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create env var {schema_name} failed: {response.status_code} - {response.text}")

        # Get the definition ID for creating default value
        created = self.get(f"environmentvariabledefinitions?$filter=schemaname eq '{schema_name}'")
        if not created.get("value"):
            return

        definition_id = created["value"][0]["environmentvariabledefinitionid"]

        # Create default value if specified
        if "default_value" in var_def:
            value_payload = {
                "value": var_def["default_value"],
                "EnvironmentVariableDefinitionId@odata.bind": f"/environmentvariabledefinitions({definition_id})",
            }
            response = self._request(
                "POST",
                "environmentvariablevalues",
                json=value_payload,
                headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
            )
            if response.status_code not in (200, 201, 204):
                print(f"      Warning: Could not set default value: {response.text}")

    # -------------------------------------------------------------------------
    # Views (Saved Queries)
    # -------------------------------------------------------------------------

    def build_fetchxml(self, entity: str, columns: list[dict], filter_xml: str, is_or_filter: bool = False) -> str:
        """Build FetchXML for a view."""
        cols = "\n        ".join([f'<attribute name="{c["name"]}"/>' for c in columns])

        # Wrap filter condition appropriately
        if is_or_filter:
            # Filter is already a complete filter element
            filter_block = f"      {filter_xml}"
        elif filter_xml:
            filter_block = f"""      <filter type="and">
        {filter_xml}
      </filter>"""
        else:
            filter_block = ""

        return f"""<fetch version="1.0" output-format="xml-platform" mapping="logical" distinct="false">
  <entity name="{entity}">
    {cols}
    <attribute name="{entity}id"/>
{filter_block}
    <order attribute="createdon" descending="true"/>
  </entity>
</fetch>"""

    def build_layoutxml(self, entity: str, columns: list[dict]) -> str:
        """Build LayoutXML for view grid columns."""
        cells = "\n          ".join(
            [f'<cell name="{c["name"]}" width="{c["width"]}"/>' for c in columns]
        )
        return f"""<grid name="resultset" object="1" jump="{entity}id" select="1" icon="1" preview="1">
  <row name="result" id="{entity}id">
    {cells}
  </row>
</grid>"""

    def create_view(self, view_def: dict, columns: list[dict]) -> None:
        """Create a saved query (view) for an entity."""
        entity = view_def["entity"]
        name = view_def["name"]

        # Check if view already exists
        existing = self.get(
            f"savedqueries?$filter=returnedtypecode eq '{entity}' and name eq '{name}'"
        )
        if existing.get("value"):
            print(f"      '{name}' already exists, skipping")
            return

        is_or_filter = view_def.get("is_or_filter", False)
        fetchxml = self.build_fetchxml(entity, columns, view_def["filter"], is_or_filter)
        layoutxml = self.build_layoutxml(entity, columns)

        payload = {
            "name": name,
            "returnedtypecode": entity,
            "fetchxml": fetchxml,
            "layoutxml": layoutxml,
            "querytype": 0,  # Public view
            "isdefault": view_def.get("is_default", False),
            "description": view_def.get("description", ""),
        }

        response = self._request(
            "POST",
            "savedqueries",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create view '{name}' failed: {response.status_code} - {response.text}")

    # -------------------------------------------------------------------------
    # Security Roles
    # -------------------------------------------------------------------------

    def get_root_business_unit(self) -> str:
        """Get the root business unit ID."""
        result = self.get("businessunits?$filter=parentbusinessunitid eq null&$select=businessunitid,name")
        if result.get("value"):
            return result["value"][0]["businessunitid"]
        raise Exception("Could not find root business unit")

    def get_privilege_id(self, privilege_name: str) -> str | None:
        """Get a privilege ID by name."""
        result = self.get(f"privileges?$filter=name eq '{privilege_name}'&$select=privilegeid")
        if result.get("value"):
            return result["value"][0]["privilegeid"]
        return None

    def wait_for_privileges(self, entity_name: str, timeout: int = 120) -> bool:
        """Poll until custom entity privileges are available.

        After PublishAllXml, Dataverse takes time to create CRUD privileges for
        custom entities. This method polls until at least the Read privilege exists.

        Args:
            entity_name: Logical name of the entity (e.g., 'mcg_messagecenterpost')
            timeout: Maximum seconds to wait (default: 120)

        Returns:
            True if privileges are available, False if timeout
        """
        start = time.time()
        priv_name = f"prvRead{entity_name}"
        while time.time() - start < timeout:
            priv_id = self.get_privilege_id(priv_name)
            if priv_id:
                return True
            time.sleep(5)
        return False

    def create_security_role(self, role_key: str, role_def: dict, business_unit_id: str) -> list[str]:
        """Create a security role with specified privileges.

        Returns:
            List of failed privilege assignments (empty if all succeeded)
        """
        role_name = role_def["name"]
        failures: list[str] = []

        # Check if role already exists
        existing = self.get(f"roles?$filter=name eq '{role_name}'&$select=roleid")
        if existing.get("value"):
            print(f"      '{role_name}' already exists, skipping")
            return failures

        # Create the role
        role_payload = {
            "name": role_name,
            "businessunitid@odata.bind": f"/businessunits({business_unit_id})",
        }

        response = self._request(
            "POST",
            "roles",
            json=role_payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create role '{role_name}' failed: {response.status_code} - {response.text}")

        # Get the created role ID
        created = self.get(f"roles?$filter=name eq '{role_name}'&$select=roleid")
        if not created.get("value"):
            print(f"      Warning: Could not find created role to add privileges")
            return [f"{role_name}: role created but not found for privilege assignment"]

        role_id = created["value"][0]["roleid"]

        # Add privileges to the role
        for entity_name, privileges in role_def["privileges"].items():
            for priv_type, depth in privileges.items():
                # Build privilege name (e.g., prvCreateaccount)
                priv_name = f"prv{priv_type}{entity_name}"
                priv_id = self.get_privilege_id(priv_name)

                if priv_id:
                    depth_value = PRIVILEGE_DEPTH.get(depth, "Basic")
                    success = self._add_role_privilege(role_id, priv_id, depth_value, priv_name)
                    if not success:
                        failures.append(f"{role_name}: {priv_name}")
                else:
                    failures.append(f"{role_name}: {priv_name} (privilege not found)")

        return failures

    def _add_role_privilege(self, role_id: str, privilege_id: str, depth: str, priv_name: str = "") -> bool:
        """Add a privilege to a role using AddPrivilegesRole action.

        Returns:
            True if privilege was added successfully, False otherwise
        """
        payload = {
            "Privileges": [
                {
                    "PrivilegeId": privilege_id,
                    "Depth": depth,  # String enum: "Basic", "Local", "Deep", "Global"
                }
            ]
        }

        response = self._request(
            "POST",
            f"roles({role_id})/Microsoft.Dynamics.CRM.AddPrivilegesRole",
            json=payload,
        )
        if response.status_code in (200, 204):
            return True
        # Log warnings for failures
        print(f"      Warning: Could not assign privilege {priv_name or privilege_id}: {response.status_code}")
        return False

    # -------------------------------------------------------------------------
    # Forms
    # -------------------------------------------------------------------------

    def build_formxml(self, form_def: dict) -> str:
        """Build FormXML for a main form."""
        tabs_xml = []

        for tab_idx, tab in enumerate(form_def["tabs"]):
            sections_xml = []

            for sec_idx, section in enumerate(tab["sections"]):
                rows_xml = []

                if section.get("timeline"):
                    # Timeline control
                    rows_xml.append("""<row>
              <cell id="{timeline}">
                <control id="notescontrol" classid="{F3015350-44A2-4AA0-97B5-00166532B5E9}"/>
              </cell>
            </row>""")
                elif section.get("subgrid"):
                    # Subgrid control
                    subgrid = section["subgrid"]
                    rows_xml.append(f"""<row>
              <cell id="{{subgrid_{subgrid['name']}}}">
                <control id="{subgrid['name']}" classid="{{E7A81278-8635-4D9E-8D4D-59480B391C5B}}">
                  <parameters>
                    <TargetEntityType>{subgrid['entity']}</TargetEntityType>
                    <ViewId>{{00000000-0000-0000-0000-000000000000}}</ViewId>
                    <RelationshipName>{subgrid['relationship']}</RelationshipName>
                  </parameters>
                </control>
              </cell>
            </row>""")
                else:
                    # Regular controls
                    for control in section.get("controls", []):
                        attr = control["attribute"]
                        colspan = control.get("colspan", 1)
                        rowspan = control.get("rowspan", 1)
                        rows_xml.append(f"""<row>
              <cell id="{{{attr}}}" colspan="{colspan}" rowspan="{rowspan}">
                <control id="{attr}" classid="{{4273EDBD-AC1D-40D3-9FB2-095C621B552D}}"/>
              </cell>
            </row>""")

                section_xml = f"""<section name="{section['name']}" showlabel="true" showbar="false" columns="{section['columns']}" id="{{{section['name']}}}">
          <labels>
            <label description="{section['label']}" languagecode="1033"/>
          </labels>
          <rows>
            {''.join(rows_xml)}
          </rows>
        </section>"""
                sections_xml.append(section_xml)

            tab_xml = f"""<tab name="{tab['name']}" id="{{{tab['name']}}}" visible="true" showlabel="true">
      <labels>
        <label description="{tab['label']}" languagecode="1033"/>
      </labels>
      <columns>
        <column width="100%">
          <sections>
            {''.join(sections_xml)}
          </sections>
        </column>
      </columns>
    </tab>"""
            tabs_xml.append(tab_xml)

        return f"""<form>
  <tabs>
    {''.join(tabs_xml)}
  </tabs>
</form>"""

    def create_form(self, form_def: dict) -> None:
        """Create a system form for an entity."""
        entity = form_def["entity"]
        name = form_def["name"]

        # Check if form already exists (there will be a default, so check by name)
        existing = self.get(
            f"systemforms?$filter=objecttypecode eq '{entity}' and name eq '{name}' and type eq 2"
        )
        if existing.get("value"):
            print(f"      Main form already exists, skipping")
            return

        formxml = self.build_formxml(form_def)

        payload = {
            "name": name,
            "objecttypecode": entity,
            "type": form_def.get("type", 2),  # Main form
            "formxml": formxml,
            "description": "Main form for Message Center Post governance",
        }

        response = self._request(
            "POST",
            "systemforms",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create form failed: {response.status_code} - {response.text}")

    # -------------------------------------------------------------------------
    # Model-Driven App
    # -------------------------------------------------------------------------

    def get_entity_metadata_id(self, entity_logical_name: str) -> str | None:
        """Get the MetadataId for an entity."""
        result = self.get(f"EntityDefinitions(LogicalName='{entity_logical_name}')?$select=MetadataId")
        return result.get("MetadataId")

    def build_sitemap_xml(self, app_def: dict) -> str:
        """Build SiteMap XML for the model-driven app."""
        subareas = []
        for idx, entity in enumerate(app_def["entities"]):
            # Get display name from table definitions
            table_def = TABLE_DEFINITIONS.get(entity, {})
            display_name = table_def.get("display_name", entity)
            subareas.append(
                f'<SubArea Id="mcg_subarea_{idx}" Entity="{entity}" Title="{display_name}"/>'
            )

        return f"""<SiteMap>
  <Area Id="mcg_area_main" Title="Governance">
    <Group Id="mcg_group_records" Title="Records">
      {chr(10).join('      ' + s for s in subareas)}
    </Group>
  </Area>
</SiteMap>"""

    def create_model_driven_app(self, app_def: dict) -> None:
        """Create a model-driven app with sitemap and components."""
        unique_name = app_def["uniquename"]

        # Check if app already exists
        existing = self.get(f"appmodules?$filter=uniquename eq '{unique_name}'")
        if existing.get("value"):
            print(f"      App already exists, skipping")
            return

        # Build sitemap
        sitemap_xml = self.build_sitemap_xml(app_def)

        # Create the app module
        payload = {
            "name": app_def["name"],
            "uniquename": unique_name,
            "description": app_def.get("description", ""),
            "clienttype": 4,  # Unified Interface
            "sitemapxml": sitemap_xml,
            "webresourceid": None,  # No custom web resource
        }

        response = self._request(
            "POST",
            "appmodules",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            raise Exception(f"Create app module failed: {response.status_code} - {response.text}")

        # Get the created app ID
        created = self.get(f"appmodules?$filter=uniquename eq '{unique_name}'")
        if not created.get("value"):
            print(f"      Warning: Could not find created app to add components")
            return

        app_id = created["value"][0]["appmoduleid"]

        # Add entity components to the app
        for entity in app_def["entities"]:
            metadata_id = self.get_entity_metadata_id(entity)
            if metadata_id:
                self._add_app_component(app_id, metadata_id, 1)  # 1 = Entity

    def _add_app_component(self, app_id: str, component_id: str, component_type: int) -> bool:
        """Add a component to a model-driven app. Returns True if added, False if already exists or error."""
        payload = {
            "AppId": app_id,
            "Components": [
                {
                    "ComponentType": component_type,
                    "ComponentId": component_id,
                }
            ],
        }

        try:
            response = self._request(
                "POST",
                "AddAppComponents",
                json=payload,
            )
            if response.status_code in (200, 204):
                return True
            # Check if component already exists (common duplicate error)
            if response.status_code == 400 and "already" in response.text.lower():
                return False
            print(f"      Warning: Could not add component {component_id}: {response.status_code}")
            return False
        except Exception as e:
            print(f"      Warning: Error adding component {component_id}: {e}")
            return False

    # -------------------------------------------------------------------------
    # Business Process Flow
    # -------------------------------------------------------------------------

    def create_business_process_flow(self, bpf_def: dict) -> None:
        """Create a business process flow."""
        unique_name = bpf_def["uniquename"]

        # Check if BPF already exists
        existing = self.get(f"workflows?$filter=uniquename eq '{unique_name}' and category eq 4")
        if existing.get("value"):
            print(f"      BPF already exists, skipping")
            return

        # Build minimal XAML for BPF stages
        # Note: Full BPF XAML is complex; this creates the workflow record
        # Stage configuration may need manual adjustment in the portal
        stages_xml = []
        for idx, stage in enumerate(bpf_def["stages"]):
            stages_xml.append(f"""<Stage Name="{stage['name']}" Position="{idx + 1}"/>""")

        # Simplified workflow XAML
        xaml = f"""<Workflow>
  <BPFEntity>{bpf_def['entity']}</BPFEntity>
  <Stages>
    {''.join(stages_xml)}
  </Stages>
</Workflow>"""

        payload = {
            "name": bpf_def["name"],
            "uniquename": unique_name,
            "category": 4,  # Business Process Flow
            "primaryentity": bpf_def["entity"],
            "type": 1,  # Definition
            "businessprocesstype": 0,  # Business Process Flow
            "scope": 4,  # Organization
            "xaml": xaml,
        }

        response = self._request(
            "POST",
            "workflows",
            json=payload,
            headers={"MSCRM.SolutionUniqueName": SOLUTION_CONFIG["uniquename"]},
        )
        if response.status_code not in (200, 201, 204):
            # BPF creation via API is limited; warn but don't fail
            print(f"      Warning: BPF creation may require portal configuration: {response.status_code}")
            return

        print(f"created (verify stages in portal)")

    # -------------------------------------------------------------------------
    # App Role Association
    # -------------------------------------------------------------------------

    def associate_roles_to_app(self, app_id: str) -> None:
        """Associate MCG security roles with the model-driven app."""
        role_names = ["MC Admin", "MC Owner", "MC Compliance Reviewer", "MC Auditor"]

        # Get currently associated roles using $expand syntax
        app_result = self.get(f"appmodules({app_id})?$select=name&$expand=appmoduleroles_association($select=roleid,name)")
        existing_role_ids = set()
        if app_result.get("appmoduleroles_association"):
            existing_role_ids = {r["roleid"] for r in app_result["appmoduleroles_association"]}

        associated_count = 0
        skipped_count = 0

        for role_name in role_names:
            # Get role ID
            role_result = self.get(f"roles?$filter=name eq '{role_name}'&$select=roleid")
            if not role_result.get("value"):
                print(f"      Warning: Role '{role_name}' not found")
                continue

            role_id = role_result["value"][0]["roleid"]

            # Skip if already associated
            if role_id in existing_role_ids:
                skipped_count += 1
                continue

            # Associate role
            try:
                response = self._request(
                    "POST",
                    f"appmodules({app_id})/appmoduleroles_association/$ref",
                    json={"@odata.id": f"{self.api_url}/roles({role_id})"},
                )
                if response.status_code in (200, 204):
                    associated_count += 1
                else:
                    print(f"      Warning: Could not associate role '{role_name}': {response.status_code}")
            except Exception as e:
                print(f"      Warning: Error associating role '{role_name}': {e}")

        # Also associate Basic User role for minimum Dataverse access
        basic_result = self.get("roles?$filter=name eq 'Basic User'&$select=roleid")
        if basic_result.get("value"):
            basic_id = basic_result["value"][0]["roleid"]
            if basic_id not in existing_role_ids:
                try:
                    response = self._request(
                        "POST",
                        f"appmodules({app_id})/appmoduleroles_association/$ref",
                        json={"@odata.id": f"{self.api_url}/roles({basic_id})"},
                    )
                    if response.status_code in (200, 204):
                        associated_count += 1
                except Exception as e:
                    print(f"      Warning: Could not associate Basic User role: {e}")
        else:
            print("      Warning: 'Basic User' role not found - users may not be able to access app")

        print(f"      {associated_count} associated, {skipped_count} already present")

    def add_components_to_app(self, app_id: str) -> None:
        """Add forms, views, and BPF as explicit app components."""
        components_added = 0
        skipped = 0

        # Add views (savedqueries) - component type 26
        for view_def in VIEW_DEFINITIONS:
            view_result = self.get(
                f"savedqueries?$filter=name eq '{view_def['name']}' and returnedtypecode eq '{view_def['entity']}'&$select=savedqueryid"
            )
            if view_result.get("value"):
                view_id = view_result["value"][0]["savedqueryid"]
                if self._add_app_component(app_id, view_id, 26):  # 26 = SavedQuery
                    components_added += 1
                else:
                    skipped += 1

        # Add main form (systemforms) - component type 60
        form_result = self.get(
            f"systemforms?$filter=name eq 'Main Form' and objecttypecode eq 'mcg_messagecenterpost' and type eq 2&$select=formid"
        )
        if form_result.get("value"):
            form_id = form_result["value"][0]["formid"]
            if self._add_app_component(app_id, form_id, 60):  # 60 = SystemForm
                components_added += 1
            else:
                skipped += 1

        # Add BPF (workflow) - component type 29
        bpf_result = self.get(
            f"workflows?$filter=uniquename eq '{BPF_DEFINITION['uniquename']}' and category eq 4&$select=workflowid"
        )
        if bpf_result.get("value"):
            bpf_id = bpf_result["value"][0]["workflowid"]
            if self._add_app_component(app_id, bpf_id, 29):  # 29 = Workflow
                components_added += 1
            else:
                skipped += 1

        print(f"      {components_added} added, {skipped} already present")

    # -------------------------------------------------------------------------
    # Publish
    # -------------------------------------------------------------------------

    def publish_all(self) -> None:
        """Publish all customizations."""
        response = self._request("POST", "PublishAllXml")
        if response.status_code not in (200, 204):
            raise Exception(f"PublishAllXml failed: {response.status_code} - {response.text}")

    # -------------------------------------------------------------------------
    # Verification
    # -------------------------------------------------------------------------

    def verify_deployment(self) -> dict:
        """Verify all deployment components exist and are properly configured.

        Returns:
            Dictionary with verification results including:
            - tables: list of verified tables
            - roles: list of verified roles with privilege counts
            - app: app module status
            - issues: list of any issues found
        """
        results = {
            "tables": [],
            "roles": [],
            "app": None,
            "env_vars": [],
            "views": [],
            "issues": [],
        }

        # Verify tables exist
        for table_name in TABLE_DEFINITIONS.keys():
            table_result = self.get(f"EntityDefinitions(LogicalName='{table_name}')?$select=LogicalName,DisplayName")
            if table_result.get("LogicalName"):
                results["tables"].append(table_name)
            else:
                results["issues"].append(f"Table '{table_name}' not found")

        # Verify security roles exist and have privileges
        for role_key, role_def in ROLE_DEFINITIONS.items():
            role_name = role_def["name"]
            role_result = self.get(f"roles?$filter=name eq '{role_name}'&$select=roleid,name")
            if role_result.get("value"):
                role_id = role_result["value"][0]["roleid"]
                # Count privileges assigned to role
                priv_result = self.get(
                    f"roles({role_id})?$select=name&$expand=roleprivileges_association($select=privilegeid)"
                )
                priv_count = len(priv_result.get("roleprivileges_association", []))
                results["roles"].append({"name": role_name, "privilege_count": priv_count})
                if priv_count == 0:
                    results["issues"].append(f"Role '{role_name}' has ZERO privileges assigned")
            else:
                results["issues"].append(f"Role '{role_name}' not found")

        # Verify app module exists
        app_result = self.get(f"appmodules?$filter=uniquename eq '{APP_DEFINITION['uniquename']}'&$select=name")
        if app_result.get("value"):
            results["app"] = APP_DEFINITION["name"]
        else:
            results["issues"].append(f"App module '{APP_DEFINITION['uniquename']}' not found")

        # Verify environment variables
        for var_def in ENVIRONMENT_VARIABLE_DEFINITIONS:
            var_result = self.get(
                f"environmentvariabledefinitions?$filter=schemaname eq '{var_def['schemaname']}'&$select=displayname"
            )
            if var_result.get("value"):
                results["env_vars"].append(var_def["schemaname"])
            else:
                results["issues"].append(f"Environment variable '{var_def['schemaname']}' not found")

        # Verify views
        for view_def in VIEW_DEFINITIONS:
            view_result = self.get(
                f"savedqueries?$filter=name eq '{view_def['name']}' and returnedtypecode eq '{view_def['entity']}'&$select=name"
            )
            if view_result.get("value"):
                results["views"].append(view_def["name"])
            else:
                results["issues"].append(f"View '{view_def['name']}' not found")

        return results


# =============================================================================
# MAIN DEPLOYMENT
# =============================================================================


def deploy(environment_url: str, tenant_id: str, client_id: str, client_secret: str) -> None:
    """Run the full deployment with 19-step sequence."""
    print("=== MCG Solution Deployment v1.3.0 ===")
    print(f"Environment: {environment_url}\n")

    client = DataverseClient(environment_url, tenant_id, client_id, client_secret)

    # Step 1: Authenticate
    print("[1/19] Authenticating...", end=" ", flush=True)
    client.authenticate()
    print("✓")

    # Step 2: Publisher
    print("[2/19] Publisher 'mcg'...", end=" ", flush=True)
    publisher_id = client.get_or_create_publisher()
    print("ready")

    # Step 3: Solution
    print("[3/19] Solution 'MessageCenterGovernance'...", end=" ", flush=True)
    client.get_or_create_solution(publisher_id)
    print("ready")

    # Steps 4-6: Create tables and columns (with AI-friendly descriptions)
    step = 4
    for table_logical_name, table_def in TABLE_DEFINITIONS.items():
        col_count = len(table_def["columns"])
        lookup_count = len(table_def.get("lookups", []))
        print(f"[{step}/19] Table '{table_def['schema_name']}'...", end=" ", flush=True)
        client.create_table(table_logical_name, table_def)
        print(f"created")

        for col_def in table_def["columns"]:
            client.add_column(table_logical_name, col_def)

        for lookup_def in table_def.get("lookups", []):
            client.add_lookup_column(table_logical_name, lookup_def)

        total = col_count + lookup_count
        print(f"      Added {total} columns with descriptions")
        step += 1

    # Step 7: Relationships
    print("[7/19] Relationships...", end=" ", flush=True)
    for rel_def in RELATIONSHIP_DEFINITIONS:
        client.create_relationship(rel_def)
    print(f"created ({len(RELATIONSHIP_DEFINITIONS)})")

    # Step 8: Alternate key
    print("[8/19] Alternate key 'mcg_messagecenterid'...", end=" ", flush=True)
    client.create_alternate_key(
        "mcg_messagecenterpost",
        "mcg_MessageCenterIdKey",
        ["mcg_messagecenterid"],
    )
    print("created")
    print("      Waiting for activation...", end=" ", flush=True)
    client.wait_for_alternate_key("mcg_messagecenterpost", "mcg_messagecenteridkey")
    print("Active ✓")

    # Step 9: Environment Variables
    print("[9/19] Environment Variables...", end=" ", flush=True)
    for var_def in ENVIRONMENT_VARIABLE_DEFINITIONS:
        client.create_environment_variable(var_def)
    print(f"created ({len(ENVIRONMENT_VARIABLE_DEFINITIONS)})")

    # Step 10: Views (before first publish)
    print("[10/19] Views...", end=" ", flush=True)
    for view_def in VIEW_DEFINITIONS:
        client.create_view(view_def, VIEW_COLUMNS)
    print(f"created ({len(VIEW_DEFINITIONS)})")

    # Step 11: Main Form
    print("[11/19] Main Form...", end=" ", flush=True)
    client.create_form(FORM_DEFINITION)
    print("created")

    # Step 12: Business Process Flow (placeholder)
    print("[12/19] Business Process Flow...", end=" ", flush=True)
    client.create_business_process_flow(BPF_DEFINITION)

    # Step 13: First Publish (enables privileges for custom entities)
    print("[13/19] Publishing customizations...", end=" ", flush=True)
    client.publish_all()
    print("✓")

    # Wait for privileges to propagate (poll instead of fixed sleep)
    print("      Waiting for privilege propagation...", end=" ", flush=True)
    privileges_ready = True
    for entity_name in TABLE_DEFINITIONS.keys():
        if not client.wait_for_privileges(entity_name, timeout=120):
            print(f"\n      ERROR: Privileges for {entity_name} not available after 120s")
            privileges_ready = False
            break
    if privileges_ready:
        print("ready ✓")
    else:
        print("\n      WARNING: Proceeding with security role creation despite missing privileges")

    # Step 14: Security Roles (after publish - privileges now exist)
    print("[14/19] Security Roles...", end=" ", flush=True)
    business_unit_id = client.get_root_business_unit()
    all_privilege_failures: list[str] = []
    for role_key, role_def in ROLE_DEFINITIONS.items():
        failures = client.create_security_role(role_key, role_def, business_unit_id)
        all_privilege_failures.extend(failures)
    print(f"created ({len(ROLE_DEFINITIONS)})")

    # Report privilege failures
    if all_privilege_failures:
        print(f"      WARNING: {len(all_privilege_failures)} privilege assignment(s) failed:")
        for failure in all_privilege_failures[:10]:  # Show first 10
            print(f"        - {failure}")
        if len(all_privilege_failures) > 10:
            print(f"        ... and {len(all_privilege_failures) - 10} more")

    # Step 15: Model-Driven App
    print("[15/19] Model-Driven App...", end=" ", flush=True)
    client.create_model_driven_app(APP_DEFINITION)
    print("created")

    # Get app ID for component and role association
    app_result = client.get(f"appmodules?$filter=uniquename eq '{APP_DEFINITION['uniquename']}'&$select=appmoduleid")
    if app_result.get("value"):
        app_id = app_result["value"][0]["appmoduleid"]

        # Step 16: Add components to app
        print("[16/19] App Components...", end=" ", flush=True)
        client.add_components_to_app(app_id)

        # Step 17: Associate security roles to app
        print("[17/19] Role Associations...", end=" ", flush=True)
        client.associate_roles_to_app(app_id)
    else:
        print("[16/19] App Components... skipped (app not found)")
        print("[17/19] Role Associations... skipped (app not found)")

    # Step 18: Final Publish
    print("[18/19] Final publish...", end=" ", flush=True)
    client.publish_all()
    print("✓")

    # Step 19: Verification
    print("[19/19] Verifying deployment...", end=" ", flush=True)
    verification = client.verify_deployment()
    print("done")
    print(f"      Tables: {len(verification['tables'])}/{len(TABLE_DEFINITIONS)}")
    print(f"      Roles: {len(verification['roles'])}/{len(ROLE_DEFINITIONS)}")
    for role in verification["roles"]:
        priv_status = "✓" if role["privilege_count"] > 0 else "⚠ EMPTY"
        print(f"        - {role['name']}: {role['privilege_count']} privileges {priv_status}")
    print(f"      Views: {len(verification['views'])}/{len(VIEW_DEFINITIONS)}")
    print(f"      Env Vars: {len(verification['env_vars'])}/{len(ENVIRONMENT_VARIABLE_DEFINITIONS)}")
    print(f"      App: {'✓' if verification['app'] else '✗'}")

    if verification["issues"]:
        print(f"\n      ⚠ ISSUES DETECTED ({len(verification['issues'])}):")
        for issue in verification["issues"]:
            print(f"        - {issue}")

    # Print next steps
    print("\n" + "=" * 60)
    print("=== Deployment Complete ===")
    print("=" * 60)
    print("""
REMAINING MANUAL STEPS:

1. AZURE AD APP REGISTRATION
   - Go to Azure Portal > Azure Active Directory > App Registrations
   - Create new registration (single tenant)
   - Under "Certificates & secrets", create a client secret
   - Under "API permissions":
     * Add permission > Microsoft Graph > Application permissions
     * Select ServiceMessage.Read.All
     * Click "Grant admin consent" (requires Global Administrator)
   - Note the Application (client) ID and client secret

2. POWER AUTOMATE FLOW FOR MESSAGE CENTER INGESTION
   - Trigger: Recurrence (6 hours recommended)
   - Action 1: HTTP GET to Graph API
     * URI: https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages
     * Authentication: Active Directory OAuth
       - Tenant: Your Azure AD Tenant ID
       - Audience: https://graph.microsoft.com
       - Client ID: From app registration
       - Credential Type: Secret
       - Secret: From app registration
   - Action 2: Parse JSON response
   - Action 3: For each message > Create/Update Dataverse record
     * Use mcg_MessageCenterId as alternate key for upsert

3. BUSINESS PROCESS FLOW CONFIGURATION
   - The script creates a placeholder BPF record
   - Go to make.powerapps.com > Solutions > MessageCenterGovernance
   - Either configure the existing BPF or delete and recreate:
     * Name: MCG Governance Process
     * Entity: Message Center Post
     * Stages: New, Triage, Assess, Decide, Closed
   - Add relevant fields to each stage
   - Save and ACTIVATE the BPF

4. VERIFY DEPLOYMENT
   - Open Message Center Governance app in Power Apps
   - Verify 4 views appear for MessageCenterPost
   - Verify main form has 5 tabs
   - Verify security roles have privileges assigned

5. ASSIGN SECURITY ROLES TO USERS
   - MC Admin: Full access to all records
   - MC Owner: Manages assigned posts, creates assessments
   - MC Compliance Reviewer: Reviews and approves decisions
   - MC Auditor: Read-only access for audit purposes
""")


def main():
    parser = argparse.ArgumentParser(
        description="Deploy MCG Solution to Dataverse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example:
    # Using environment variable (recommended - avoids shell history exposure)
    export MCG_CLIENT_SECRET="your-secret-value"
    python deploy_mcg.py \\
        --environment-url "https://org12345.crm.dynamics.com" \\
        --tenant-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \\
        --client-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

    # Or provide via command line (appears in shell history - less secure)
    python deploy_mcg.py \\
        --environment-url "https://org12345.crm.dynamics.com" \\
        --tenant-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \\
        --client-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \\
        --client-secret "your-secret-value"

Security Note:
    Client secret can be provided via:
    1. MCG_CLIENT_SECRET environment variable (recommended)
    2. --client-secret argument (appears in shell history)
    3. Interactive prompt (if neither above is provided)
        """,
    )
    parser.add_argument("--environment-url", required=True, help="Dataverse environment URL")
    parser.add_argument("--tenant-id", required=True, help="Azure AD tenant ID")
    parser.add_argument("--client-id", required=True, help="Azure AD application client ID")
    parser.add_argument(
        "--client-secret",
        required=False,
        help="Azure AD application client secret (prefer MCG_CLIENT_SECRET env var)",
    )

    args = parser.parse_args()

    # Get client secret: env var > CLI arg > interactive prompt
    client_secret = os.environ.get("MCG_CLIENT_SECRET")
    if not client_secret:
        client_secret = args.client_secret
    if not client_secret:
        print("Client secret not found in MCG_CLIENT_SECRET or --client-secret")
        client_secret = getpass.getpass("Enter client secret: ")
    if not client_secret:
        print("❌ Client secret is required", file=sys.stderr)
        sys.exit(1)

    try:
        deploy(args.environment_url, args.tenant_id, args.client_id, client_secret)
    except Exception as e:
        print(f"\n❌ Deployment failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
