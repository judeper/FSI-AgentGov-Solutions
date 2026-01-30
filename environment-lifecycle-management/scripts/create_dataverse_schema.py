#!/usr/bin/env python3
"""
Create Dataverse schema for Environment Lifecycle Management.

Creates EnvironmentRequest and ProvisioningLog tables with all columns,
choice fields, and relationships.
"""

import argparse
import os
import sys
from typing import Optional

from elm_client import ELMClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# ============================================================================
# Choice (OptionSet) Definitions
# ============================================================================

OPTIONSETS = {
    "fsi_er_state": {
        "Name": "fsi_er_state",
        "DisplayName": {"LocalizedLabels": [{"Label": "Request State", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Workflow state for environment requests", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Draft", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Submitted", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "PendingApproval", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Approved", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
            {"Value": 6, "Label": {"LocalizedLabels": [{"Label": "Provisioning", "LanguageCode": 1033}]}},
            {"Value": 7, "Label": {"LocalizedLabels": [{"Label": "Completed", "LanguageCode": 1033}]}},
            {"Value": 8, "Label": {"LocalizedLabels": [{"Label": "Failed", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_er_zone": {
        "Name": "fsi_er_zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Governance Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Environment governance zone classification", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Zone 1", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Zone 2", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Zone 3", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_er_environmenttype": {
        "Name": "fsi_er_environmenttype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Platform environment type", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Sandbox", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Production", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Developer", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_er_region": {
        "Name": "fsi_er_region",
        "DisplayName": {"LocalizedLabels": [{"Label": "Region", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Geographic region for environment", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "United States", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Europe", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "United Kingdom", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Australia", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_er_datasensitivity": {
        "Name": "fsi_er_datasensitivity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Data Sensitivity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Data sensitivity classification", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Public", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Internal", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Confidential", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Restricted", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_er_expectedusers": {
        "Name": "fsi_er_expectedusers",
        "DisplayName": {"LocalizedLabels": [{"Label": "Expected Users", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Expected user population", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Just me (1)", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Small team (2-10)", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Large team (11-50)", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Department (50+)", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_pl_action": {
        "Name": "fsi_pl_action",
        "DisplayName": {"LocalizedLabels": [{"Label": "Provisioning Action", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Provisioning log action type", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "RequestCreated", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "ZoneClassified", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "ApprovalRequested", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Approved", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
            {"Value": 6, "Label": {"LocalizedLabels": [{"Label": "ProvisioningStarted", "LanguageCode": 1033}]}},
            {"Value": 7, "Label": {"LocalizedLabels": [{"Label": "EnvironmentCreated", "LanguageCode": 1033}]}},
            {"Value": 8, "Label": {"LocalizedLabels": [{"Label": "ManagedEnabled", "LanguageCode": 1033}]}},
            {"Value": 9, "Label": {"LocalizedLabels": [{"Label": "GroupAssigned", "LanguageCode": 1033}]}},
            {"Value": 10, "Label": {"LocalizedLabels": [{"Label": "SecurityGroupBound", "LanguageCode": 1033}]}},
            {"Value": 11, "Label": {"LocalizedLabels": [{"Label": "BaselineConfigApplied", "LanguageCode": 1033}]}},
            {"Value": 12, "Label": {"LocalizedLabels": [{"Label": "DLPAssigned", "LanguageCode": 1033}]}},
            {"Value": 13, "Label": {"LocalizedLabels": [{"Label": "ProvisioningCompleted", "LanguageCode": 1033}]}},
            {"Value": 14, "Label": {"LocalizedLabels": [{"Label": "ProvisioningFailed", "LanguageCode": 1033}]}},
            {"Value": 15, "Label": {"LocalizedLabels": [{"Label": "RollbackInitiated", "LanguageCode": 1033}]}},
            {"Value": 16, "Label": {"LocalizedLabels": [{"Label": "RollbackCompleted", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_pl_actortype": {
        "Name": "fsi_pl_actortype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Actor Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of actor performing the action", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "User", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "ServicePrincipal", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "System", "LanguageCode": 1033}]}},
        ],
    },
}


def create_optionsets(client: ELMClient, dry_run: bool = False) -> None:
    """Create all global option sets."""
    print("\n[Creating Global Option Sets]")

    for name, definition in OPTIONSETS.items():
        existing = client.get_global_optionset(name)
        if existing:
            print(f"  {name}: already exists, skipping")
            continue

        if dry_run:
            print(f"  {name}: would create")
        else:
            client.create_global_optionset(definition)
            print(f"  {name}: created")


# ============================================================================
# Table Definitions
# ============================================================================

def get_environment_request_entity() -> dict:
    """Get EnvironmentRequest entity definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_EnvironmentRequest",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Request", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Environment Requests", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Environment provisioning requests with zone classification", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True},
        "PrimaryNameAttribute": "fsi_requestnumber",
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_RequestNumber",
                "DisplayName": {"LocalizedLabels": [{"Label": "Request Number", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Auto-generated request number (REQ-00001)", "LanguageCode": 1033}]},
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 20,
                "FormatName": {"Value": "Text"},
                "AutoNumberFormat": "REQ-{SEQNUM:5}",
            },
        ],
    }


def get_provisioning_log_entity() -> dict:
    """Get ProvisioningLog entity definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_ProvisioningLog",
        "DisplayName": {"LocalizedLabels": [{"Label": "Provisioning Log", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Provisioning Logs", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Immutable audit trail for environment provisioning", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",  # Critical for immutability
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True},
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_Name",
                "DisplayName": {"LocalizedLabels": [{"Label": "Log ID", "LanguageCode": 1033}]},
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 100,
                "FormatName": {"Value": "Text"},
            },
        ],
    }


# ============================================================================
# Column Definitions
# ============================================================================

ENVIRONMENT_REQUEST_COLUMNS = [
    # Core Request Fields
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentName",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "DEPT-Purpose-TYPE naming convention", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_EnvironmentType",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Type", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_er_environmenttype')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Region",
        "DisplayName": {"LocalizedLabels": [{"Label": "Region", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_er_region')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_BusinessJustification",
        "DisplayName": {"LocalizedLabels": [{"Label": "Business Justification", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 4000,
    },
    # Zone Classification Fields
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_er_zone')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_ZoneRationale",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone Rationale", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},  # Required via business rule for Zone 2/3
        "MaxLength": 4000,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_ZoneAutoFlags",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone Auto Flags", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Auto-detected zone triggers (comma-separated)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 500,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_DataSensitivity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Data Sensitivity", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_er_datasensitivity')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_ExpectedUsers",
        "DisplayName": {"LocalizedLabels": [{"Label": "Expected Users", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_er_expectedusers')",
    },
    # Access Control Fields
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_SecurityGroupId",
        "DisplayName": {"LocalizedLabels": [{"Label": "Security Group ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Entra security group GUID", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},  # Required via business rule for Zone 2/3
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
        "SchemaName": "fsi_Requester",
        "DisplayName": {"LocalizedLabels": [{"Label": "Requester", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Targets": ["systemuser"],
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_RequestedOn",
        "DisplayName": {"LocalizedLabels": [{"Label": "Requested On", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    # Workflow State Fields
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_State",
        "DisplayName": {"LocalizedLabels": [{"Label": "State", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_er_state')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
        "SchemaName": "fsi_Approver",
        "DisplayName": {"LocalizedLabels": [{"Label": "Approver", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Targets": ["systemuser"],
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_ApprovedOn",
        "DisplayName": {"LocalizedLabels": [{"Label": "Approved On", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_ApprovalComments",
        "DisplayName": {"LocalizedLabels": [{"Label": "Approval Comments", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},  # Required via business rule on rejection
        "MaxLength": 4000,
    },
    # Provisioning Result Fields
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentId",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Platform environment GUID", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentUrl",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment URL", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 500,
        "FormatName": {"Value": "Url"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_ProvisioningStarted",
        "DisplayName": {"LocalizedLabels": [{"Label": "Provisioning Started", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_ProvisioningCompleted",
        "DisplayName": {"LocalizedLabels": [{"Label": "Provisioning Completed", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
]


PROVISIONING_LOG_COLUMNS = [
    {
        "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
        "SchemaName": "fsi_EnvironmentRequest",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Request", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "Targets": ["fsi_environmentrequest"],
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": "fsi_Sequence",
        "DisplayName": {"LocalizedLabels": [{"Label": "Sequence", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Action sequence number (1, 2, 3...)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MinValue": 1,
        "MaxValue": 999,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Action",
        "DisplayName": {"LocalizedLabels": [{"Label": "Action", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_pl_action')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_ActionDetails",
        "DisplayName": {"LocalizedLabels": [{"Label": "Action Details", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "JSON payload with action details", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 10000,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_Actor",
        "DisplayName": {"LocalizedLabels": [{"Label": "Actor", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "UPN or Service Principal ID", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_ActorType",
        "DisplayName": {"LocalizedLabels": [{"Label": "Actor Type", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_pl_actortype')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_Timestamp",
        "DisplayName": {"LocalizedLabels": [{"Label": "Timestamp", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": "fsi_Success",
        "DisplayName": {"LocalizedLabels": [{"Label": "Success", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DefaultValue": True,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_ErrorMessage",
        "DisplayName": {"LocalizedLabels": [{"Label": "Error Message", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 10000,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_CorrelationId",
        "DisplayName": {"LocalizedLabels": [{"Label": "Correlation ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Automate run ID", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
]


def create_tables(client: ELMClient, dry_run: bool = False) -> None:
    """Create ELM tables with all columns."""
    print("\n[Creating Tables]")

    # Create EnvironmentRequest table
    er_logical_name = "fsi_environmentrequest"
    existing = client.get_entity_metadata(er_logical_name)
    if existing:
        print(f"  {er_logical_name}: already exists")
    elif dry_run:
        print(f"  {er_logical_name}: would create (User-owned, auditing enabled)")
    else:
        client.create_entity(get_environment_request_entity())
        print(f"  {er_logical_name}: created")

    # Create ProvisioningLog table
    pl_logical_name = "fsi_provisioninglog"
    existing = client.get_entity_metadata(pl_logical_name)
    if existing:
        print(f"  {pl_logical_name}: already exists")
    elif dry_run:
        print(f"  {pl_logical_name}: would create (Org-owned, auditing enabled)")
    else:
        client.create_entity(get_provisioning_log_entity())
        print(f"  {pl_logical_name}: created")


def create_columns(client: ELMClient, dry_run: bool = False) -> None:
    """Create columns on ELM tables."""
    print("\n[Creating Columns]")

    # EnvironmentRequest columns
    print("  EnvironmentRequest columns:")
    for col in ENVIRONMENT_REQUEST_COLUMNS:
        col_name = col["SchemaName"].lower()
        existing = client.get_attribute_metadata("fsi_environmentrequest", col_name)
        if existing:
            print(f"    {col_name}: already exists")
        elif dry_run:
            print(f"    {col_name}: would create")
        else:
            client.create_attribute("fsi_environmentrequest", col)
            print(f"    {col_name}: created")

    # ProvisioningLog columns
    print("  ProvisioningLog columns:")
    for col in PROVISIONING_LOG_COLUMNS:
        col_name = col["SchemaName"].lower()
        existing = client.get_attribute_metadata("fsi_provisioninglog", col_name)
        if existing:
            print(f"    {col_name}: already exists")
        elif dry_run:
            print(f"    {col_name}: would create")
        else:
            client.create_attribute("fsi_provisioninglog", col)
            print(f"    {col_name}: created")


def create_schema(client: ELMClient, dry_run: bool = False) -> None:
    """Create complete Dataverse schema for ELM."""
    print("=" * 60)
    print("ELM Dataverse Schema Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Create option sets (must exist before tables reference them)
    create_optionsets(client, dry_run)

    # Step 2: Create tables
    create_tables(client, dry_run)

    # Step 3: Create columns
    create_columns(client, dry_run)

    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print("=" * 60)


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for ELM",
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

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
