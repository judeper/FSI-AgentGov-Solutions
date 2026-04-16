#!/usr/bin/env python3
"""
Create Dataverse schema for Agent 365 Lifecycle Governance.

Creates AgentLifecycleRecord, SponsorAssignment, AccessReview, DeactivationRequest,
and LifecycleComplianceEvent tables with all columns, choice fields, relationships,
and alternate keys.
"""

import argparse
import os
import sys
from typing import Optional

import requests
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

PUBLISHER_PREFIX = "fsi"

# Shared option sets (reused from ACV) - only create if missing
SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "Name": "fsi_acv_zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Governance Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Unclassified", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Zone 1", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Zone 2", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Zone 3", "LanguageCode": 1033}]}},
        ],
    },
}

# ALG-specific option sets
OPTIONSETS = {
    "fsi_ALG_governancezone": {
        "Name": "fsi_ALG_governancezone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Governance Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Governance zone classification for lifecycle management", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Zone 1 (Personal)", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Zone 2 (Team/Departmental)", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Zone 3 (Enterprise/Customer-Facing)", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_lifecyclestage": {
        "Name": "fsi_ALG_lifecyclestage",
        "DisplayName": {"LocalizedLabels": [{"Label": "Lifecycle Stage", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current lifecycle stage of the agent", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Onboarding", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Active", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Under Review", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Inactive", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Pending Deactivation", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Deactivated", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "Deleted", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_lastactivitysource": {
        "Name": "fsi_ALG_lastactivitysource",
        "DisplayName": {"LocalizedLabels": [{"Label": "Last Activity Source", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Source of the most recent agent activity signal", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "SignInLog", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "PPACModified", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Published", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Unknown", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_accessreviewstatus": {
        "Name": "fsi_ALG_accessreviewstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Access Review Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current status of the access review cycle", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Not Started", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "In Progress", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Completed", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Overdue", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_reviewcadence": {
        "Name": "fsi_ALG_reviewcadence",
        "DisplayName": {"LocalizedLabels": [{"Label": "Review Cadence", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Frequency of access review cycles", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Annual", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Semi-Annual", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Quarterly", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_assignmentreason": {
        "Name": "fsi_ALG_assignmentreason",
        "DisplayName": {"LocalizedLabels": [{"Label": "Assignment Reason", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Reason for sponsor assignment or reassignment", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Initial Onboarding", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Sponsor Departure", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Escalation", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Manual Reassignment", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_reviewtype": {
        "Name": "fsi_ALG_reviewtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Review Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of access review", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Scheduled", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Triggered", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Ad Hoc", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_reviewstatus": {
        "Name": "fsi_ALG_reviewstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Review Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current status of an access review instance", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Pending", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "In Progress", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Completed", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Overdue", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Escalated", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_certifierdecision": {
        "Name": "fsi_ALG_certifierdecision",
        "DisplayName": {"LocalizedLabels": [{"Label": "Certifier Decision", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Access review certifier decision", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Approved", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Denied", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Not Reviewed", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_triggerreason": {
        "Name": "fsi_ALG_triggerreason",
        "DisplayName": {"LocalizedLabels": [{"Label": "Trigger Reason", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Reason that triggered a deactivation request", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Inactivity Threshold", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Sponsor Departed", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Access Review Denied", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Manual Request", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Access Expiry", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_approvalstatus": {
        "Name": "fsi_ALG_approvalstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Approval Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Status of a deactivation approval request", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Pending", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Approved", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Cancelled", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_eventtype": {
        "Name": "fsi_ALG_eventtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Event Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of lifecycle compliance event", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Sponsor Assigned", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Sponsor Departed", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Orphan Detected", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Access Review Started", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Access Review Completed", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Access Review Overdue", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "Access Review Escalated", "LanguageCode": 1033}]}},
            {"Value": 100000007, "Label": {"LocalizedLabels": [{"Label": "Inactivity Detected", "LanguageCode": 1033}]}},
            {"Value": 100000008, "Label": {"LocalizedLabels": [{"Label": "Deactivation Requested", "LanguageCode": 1033}]}},
            {"Value": 100000009, "Label": {"LocalizedLabels": [{"Label": "Deactivation Approved", "LanguageCode": 1033}]}},
            {"Value": 100000010, "Label": {"LocalizedLabels": [{"Label": "Deactivation Rejected", "LanguageCode": 1033}]}},
            {"Value": 100000011, "Label": {"LocalizedLabels": [{"Label": "Agent Disabled", "LanguageCode": 1033}]}},
            {"Value": 100000012, "Label": {"LocalizedLabels": [{"Label": "Agent Deleted", "LanguageCode": 1033}]}},
            {"Value": 100000013, "Label": {"LocalizedLabels": [{"Label": "Zone Assigned", "LanguageCode": 1033}]}},
            {"Value": 100000014, "Label": {"LocalizedLabels": [{"Label": "CA Policy Validated", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ALG_complianceimpact": {
        "Name": "fsi_ALG_complianceimpact",
        "DisplayName": {"LocalizedLabels": [{"Label": "Compliance Impact", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Compliance impact level of the lifecycle event", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "None", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Low", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Medium", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
        ],
    },
}

# Table definitions
TABLES = {
    "fsi_AgentLifecycleRecord": {
        "SchemaName": "fsi_AgentLifecycleRecord",
        "DisplayName": {"LocalizedLabels": [{"Label": "Agent Lifecycle Record", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Agent Lifecycle Records", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Master lifecycle state for each governed agent", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_AgentName",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Agent Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Display name from Entra/PPAC", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_agentname",
    },
    "fsi_SponsorAssignment": {
        "SchemaName": "fsi_SponsorAssignment",
        "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor Assignment", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Sponsor Assignments", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Sponsor assignment history for agent lifecycle tracking", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_SponsorUpn",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor UPN", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "User principal name of the sponsor", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_sponsorupn",
    },
    "fsi_AccessReview": {
        "SchemaName": "fsi_AccessReview",
        "DisplayName": {"LocalizedLabels": [{"Label": "Access Review", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Access Reviews", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Access review records for agent lifecycle governance", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Access review record name", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
    "fsi_DeactivationRequest": {
        "SchemaName": "fsi_DeactivationRequest",
        "DisplayName": {"LocalizedLabels": [{"Label": "Deactivation Request", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Deactivation Requests", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Deactivation approval requests for agent lifecycle management", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Deactivation request record name", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
    # NOTE: OrganizationOwned — non-admin roles should not have delete privilege
    # on this table. Configure security roles accordingly to maintain immutability.
    "fsi_LifecycleComplianceEvent": {
        "SchemaName": "fsi_LifecycleComplianceEvent",
        "DisplayName": {"LocalizedLabels": [{"Label": "Lifecycle Compliance Event", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Lifecycle Compliance Events", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Append-only event log for agent lifecycle compliance auditing", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Compliance event record name", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
}

# Column definitions for each table
COLUMNS = {
    "fsi_agentlifecyclerecord": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Entra Agent ID or Power Platform Bot ID — alternate key part 1", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Power Platform environment GUID — alternate key part 2", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EntraObjectId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Entra Object ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Entra service principal object ID", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_GovernanceZone",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Governance Zone", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Zone 1/2/3 governance classification", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_governancezone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LifecycleStage",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Lifecycle Stage", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current lifecycle stage of the agent", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_lifecyclestage')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SponsorUpn",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor UPN", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current sponsor user principal name", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SponsorObjectId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor Object ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Entra Object ID of the current sponsor", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SponsorActive",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor Active", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether the current sponsor account is active in Entra", "LanguageCode": 1033}]},
            "DefaultValue": True,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SponsorAssignedDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor Assigned Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the current sponsor was assigned", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LastActivityDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Last Activity Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Most recent detected activity date for the agent", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LastActivitySource",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Last Activity Source", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Source of the last activity signal", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_lastactivitysource')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_InactivityDays",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Inactivity Days", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Number of days since the last detected activity", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_InactivityThreshold",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone Inactivity Threshold", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Inactivity threshold in days per zone (Zone 1: 180, Zone 2: 90, Zone 3: 30)", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AccessReviewStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Access Review Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current access review cycle status", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_accessreviewstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_NextReviewDue",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Next Review Due", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Date the next access review is due", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LastReviewCompleted",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Last Review Completed", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Date the last access review was completed", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ReviewCadence",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Review Cadence", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Frequency of access reviews for this agent", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_reviewcadence')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CaPolicyAssigned",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "CA Policy Assigned", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether a Conditional Access policy is assigned to this agent", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DeactivationRequested",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Deactivation Requested", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether a deactivation request is pending for this agent", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_FirstRegistered",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "First Registered", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the agent was first registered in lifecycle governance", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LastUpdated",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Last Updated", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the lifecycle record was last updated", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
    ],
    "fsi_sponsorassignment": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SponsorObjectId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor Object ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Entra Object ID of the sponsor", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SponsorDisplayName",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sponsor Display Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the sponsor from Entra", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AssignmentDate",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Assignment Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When this sponsor assignment was made", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AssignmentReason",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Assignment Reason", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Reason for this sponsor assignment", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_assignmentreason')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AssignedBy",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Assigned By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Flow name or UPN that performed the assignment", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EndDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "End Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When this sponsor assignment ended", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_IsCurrent",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Is Current", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether this is the current active sponsor assignment", "LanguageCode": 1033}]},
            "DefaultValue": True,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
    ],
    "fsi_accessreview": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EntraReviewId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Entra Review ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Entra ID access review definition identifier", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EntraReviewInstanceId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Entra Review Instance ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Entra ID access review instance identifier", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ReviewType",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Review Type", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Type of access review (Scheduled, Triggered, Ad Hoc)", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_reviewtype')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ZoneCadence",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone Cadence", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Review cadence derived from the agent governance zone", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_reviewcadence')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ReviewStartDate",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Review Start Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the access review period started", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ReviewDueDate",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Review Due Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Deadline for completing the access review", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CertifierUpn",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Certifier UPN", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person responsible for certifying the review", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ReviewStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Review Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current status of the access review", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_reviewstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CertifierDecision",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Certifier Decision", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Decision made by the certifier", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_certifierdecision')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DecisionNotes",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Decision Notes", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Certifier notes explaining the review decision", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DecisionDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Decision Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the certifier made their decision", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AccessChangesMade",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Access Changes Made", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Description of access changes resulting from the review", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EscalationTarget",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Escalation Target", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN or group the review was escalated to", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EscalationDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Escalation Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the review was escalated", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
    ],
    "fsi_deactivationrequest": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_TriggerReason",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Trigger Reason", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Reason that triggered the deactivation request", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_triggerreason')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_InactivityDaysAtTrigger",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Inactivity Days at Trigger", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Number of inactivity days when the deactivation was triggered", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RequestedBy",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Requested By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Flow name or UPN that initiated the deactivation request", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RequestDate",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Request Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the deactivation was requested", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovalStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approval Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current approval status of the deactivation request", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_approvalstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApproverUpn",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approver UPN", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person who approved or rejected the request", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovalDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approval Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the deactivation request was approved or rejected", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovalNotes",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approval Notes", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Notes from the approver regarding the decision", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DisableDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Disable Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the agent was disabled in Entra/Power Platform", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DeletionHoldUntil",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Deletion Hold Until", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Date until which deletion is held for recovery purposes", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DeletionDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Deletion Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the agent was permanently deleted", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DeletionConfirmedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Deletion Confirmed By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN or flow name that confirmed the deletion", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
    ],
    # NOTE: fsi_LifecycleComplianceEvent stores agent ID as a string field
    # (not a lookup) to preserve immutability of event records.
    "fsi_lifecyclecomplianceevent": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Agent identifier (stored as string for immutability)", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Agent display name at the time of the event", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Power Platform environment identifier at event time", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EventType",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Event Type", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Type of lifecycle compliance event", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_eventtype')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EventDetails",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Event Details", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Detailed description or JSON payload for the event", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ComplianceImpact",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Compliance Impact", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Compliance impact level of the event", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ALG_complianceimpact')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_TriggeredBy",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Triggered By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Flow name or UPN that triggered the event", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Timestamp",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Timestamp", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the compliance event occurred", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RelatedRecordId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Related Record ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "GUID of a related Dataverse record for cross-reference", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
    ],
}

# Alternate key for AgentLifecycleRecord (fsi_agentid + fsi_environmentid)
ALTERNATE_KEYS = [
    {
        "SchemaName": f"{PUBLISHER_PREFIX}_AgentEnvironmentKey",
        "DisplayName": {"LocalizedLabels": [{"Label": "Agent + Environment Key", "LanguageCode": 1033}]},
        "KeyAttributes": [f"{PUBLISHER_PREFIX}_agentid", f"{PUBLISHER_PREFIX}_environmentid"],
        "EntityLogicalName": "fsi_agentlifecyclerecord",
    },
]

RELATIONSHIPS = [
    {
        "@odata.type": "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_AgentLifecycleRecord_SponsorAssignment",
        "ReferencedEntity": "fsi_agentlifecyclerecord",
        "ReferencingEntity": "fsi_sponsorassignment",
        "CascadeConfiguration": {
            "Assign": "NoCascade",
            "Delete": "RemoveLink",
            "Merge": "NoCascade",
            "Reparent": "NoCascade",
            "Share": "NoCascade",
            "Unshare": "NoCascade",
        },
        "Lookup": {
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentLifecycleRecordLookup",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Lifecycle Record", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Parent agent lifecycle record for this sponsor assignment", "LanguageCode": 1033}]},
        },
    },
    {
        "@odata.type": "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_AgentLifecycleRecord_AccessReview",
        "ReferencedEntity": "fsi_agentlifecyclerecord",
        "ReferencingEntity": "fsi_accessreview",
        "CascadeConfiguration": {
            "Assign": "NoCascade",
            "Delete": "RemoveLink",
            "Merge": "NoCascade",
            "Reparent": "NoCascade",
            "Share": "NoCascade",
            "Unshare": "NoCascade",
        },
        "Lookup": {
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentLifecycleRecordLookup",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Lifecycle Record", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Parent agent lifecycle record for this access review", "LanguageCode": 1033}]},
        },
    },
    {
        "@odata.type": "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_AgentLifecycleRecord_DeactivationRequest",
        "ReferencedEntity": "fsi_agentlifecyclerecord",
        "ReferencingEntity": "fsi_deactivationrequest",
        "CascadeConfiguration": {
            "Assign": "NoCascade",
            "Delete": "RemoveLink",
            "Merge": "NoCascade",
            "Reparent": "NoCascade",
            "Share": "NoCascade",
            "Unshare": "NoCascade",
        },
        "Lookup": {
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentLifecycleRecordLookup",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Lifecycle Record", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Parent agent lifecycle record for this deactivation request", "LanguageCode": 1033}]},
        },
    },
]


def _label(obj: dict) -> str:
    """Extract the English label from a Dataverse LocalizedLabels structure."""
    labels = obj.get("LocalizedLabels", [])
    for lbl in labels:
        if lbl.get("LanguageCode") == 1033:
            return lbl.get("Label", "")
    return labels[0].get("Label", "") if labels else ""


def _col_type(col: dict) -> str:
    """Return a human-friendly column type from the @odata.type."""
    odata = col.get("@odata.type", "")
    mapping = {
        "Microsoft.Dynamics.CRM.StringAttributeMetadata": "String",
        "Microsoft.Dynamics.CRM.MemoAttributeMetadata": "Memo",
        "Microsoft.Dynamics.CRM.PicklistAttributeMetadata": "Picklist",
        "Microsoft.Dynamics.CRM.BooleanAttributeMetadata": "Boolean",
        "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata": "DateTime",
        "Microsoft.Dynamics.CRM.IntegerAttributeMetadata": "Integer",
        "Microsoft.Dynamics.CRM.DecimalAttributeMetadata": "Decimal",
        "Microsoft.Dynamics.CRM.MoneyAttributeMetadata": "Money",
        "Microsoft.Dynamics.CRM.LookupAttributeMetadata": "Lookup",
    }
    return mapping.get(odata, odata.split(".")[-1] if odata else "Unknown")


def _optionset_name_from_bind(col: dict) -> Optional[str]:
    """Extract the global option-set name from a GlobalOptionSet@odata.bind value."""
    bind = col.get("GlobalOptionSet@odata.bind", "")
    if "Name='" in bind:
        return bind.split("Name='")[1].rstrip("')")
    return None


def _resolve_optionset(name: str) -> Optional[dict]:
    """Look up an option set by name across OPTIONSETS and SHARED_OPTIONSETS."""
    if name in OPTIONSETS:
        return OPTIONSETS[name]
    if name in SHARED_OPTIONSETS:
        return SHARED_OPTIONSETS[name]
    return None


def _format_option_values(options: list) -> str:
    """Return a compact string of value/label pairs for an option set."""
    parts = []
    for opt in options:
        val = opt.get("Value", "")
        lbl = _label(opt.get("Label", {}))
        parts.append(f"`{val}` = {lbl}")
    return ", ".join(parts)


def generate_schema_docs() -> str:
    """Generate a Markdown reference document from the in-memory schema definitions."""
    lines: list[str] = []

    # ── Header ──────────────────────────────────────────────────────────
    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append("> Auto-generated from `create_alg_dataverse_schema.py`. Do not edit manually.")
    lines.append("")

    # ── Tables ──────────────────────────────────────────────────────────
    lines.append("## Tables")
    lines.append("")
    lines.append("| SchemaName | Logical Name | Description | Primary Name Attribute |")
    lines.append("|---|---|---|---|")
    for schema_name, tbl in TABLES.items():
        logical = schema_name.lower()
        desc = _label(tbl.get("Description", {}))
        pna = tbl.get("PrimaryNameAttribute", "")
        lines.append(f"| {schema_name} | {logical} | {desc} | {pna} |")
    lines.append("")

    # ── Columns (per table) ─────────────────────────────────────────────
    lines.append("## Columns")
    lines.append("")

    for table_schema_name, tbl in TABLES.items():
        table_logical = table_schema_name.lower()
        # Combine the primary attribute(s) defined in TABLES.Attributes with COLUMNS
        primary_attrs = tbl.get("Attributes", [])
        extra_cols = COLUMNS.get(table_logical, [])
        all_cols = primary_attrs + extra_cols

        # Also include any lookup columns coming from relationships
        rel_lookups: list[dict] = []
        for rel in RELATIONSHIPS:
            if rel.get("ReferencingEntity", "").lower() == table_logical:
                lookup = rel.get("Lookup", {})
                if lookup:
                    lk = dict(lookup)
                    lk["@odata.type"] = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
                    rel_lookups.append(lk)
        all_cols = all_cols + rel_lookups

        lines.append(f"### {table_schema_name} (`{table_logical}`)")
        lines.append("")
        lines.append("| SchemaName | Logical Name | Type | Required | Description | Option Set |")
        lines.append("|---|---|---|---|---|---|")

        for col in all_cols:
            sn = col.get("SchemaName", "")
            ln = sn.lower()
            ctype = _col_type(col)
            req_val = col.get("RequiredLevel", {}).get("Value", "None")
            required = "Yes" if req_val == "ApplicationRequired" else "No"
            desc = _label(col.get("Description", {}))

            # Option set info
            os_cell = ""
            os_name = _optionset_name_from_bind(col)
            if os_name:
                os_def = _resolve_optionset(os_name)
                if os_def:
                    os_cell = f"**{os_name}**: {_format_option_values(os_def.get('Options', []))}"
                else:
                    os_cell = os_name
            elif ctype == "Boolean":
                opt = col.get("OptionSet", {})
                true_lbl = _label(opt.get("TrueOption", {}).get("Label", {})) if opt.get("TrueOption") else "Yes"
                false_lbl = _label(opt.get("FalseOption", {}).get("Label", {})) if opt.get("FalseOption") else "No"
                os_cell = f"`1` = {true_lbl}, `0` = {false_lbl}"

            lines.append(f"| {sn} | {ln} | {ctype} | {required} | {desc} | {os_cell} |")

        lines.append("")

    # ── Alternate Keys ──────────────────────────────────────────────────
    lines.append("## Alternate Keys")
    lines.append("")
    lines.append("| SchemaName | Entity | Key Attributes |")
    lines.append("|---|---|---|")
    for key in ALTERNATE_KEYS:
        sn = key.get("SchemaName", "")
        entity = key.get("EntityLogicalName", "")
        attrs = ", ".join(key.get("KeyAttributes", []))
        lines.append(f"| {sn} | {entity} | {attrs} |")
    lines.append("")

    # ── Option Sets ─────────────────────────────────────────────────────
    lines.append("## Option Sets")
    lines.append("")

    lines.append("### Shared Option Sets")
    lines.append("")
    for name, osdef in SHARED_OPTIONSETS.items():
        desc = _label(osdef.get("Description", {}))
        lines.append(f"#### {name}")
        lines.append("")
        lines.append(f"{desc}")
        lines.append("")
        lines.append("| Value | Label |")
        lines.append("|---|---|")
        for opt in osdef.get("Options", []):
            lines.append(f"| {opt['Value']} | {_label(opt['Label'])} |")
        lines.append("")

        if name == "fsi_acv_zone":
            lines.append(
                '> **⚠️ Important:** `fsi_acv_zone` and `fsi_ALG_governancezone` '
                'use **incompatible value mappings** for zones. `fsi_acv_zone` starts '
                'with Unclassified at 100000000, shifting zone numbers up by one '
                '(Zone 1 = 100000001). ALG tables bind exclusively to '
                '`fsi_ALG_governancezone` (Zone 1 = 100000000). When building '
                'flows, always use `fsi_ALG_governancezone` values for ALG '
                'tables — do **not** substitute `fsi_acv_zone` values from ELM lookups '
                'without remapping.'
            )
            lines.append("")

    lines.append("### ALG Option Sets")
    lines.append("")
    for name, osdef in OPTIONSETS.items():
        desc = _label(osdef.get("Description", {}))
        lines.append(f"#### {name}")
        lines.append("")
        lines.append(f"{desc}")
        lines.append("")
        lines.append("| Value | Label |")
        lines.append("|---|---|")
        for opt in osdef.get("Options", []):
            lines.append(f"| {opt['Value']} | {_label(opt['Label'])} |")
        lines.append("")

    # ── Relationships ───────────────────────────────────────────────────
    lines.append("## Relationships")
    lines.append("")
    lines.append("| SchemaName | Referenced Entity | Referencing Entity | Lookup Column |")
    lines.append("|---|---|---|---|")
    for rel in RELATIONSHIPS:
        sn = rel.get("SchemaName", "")
        ref_entity = rel.get("ReferencedEntity", "")
        refing_entity = rel.get("ReferencingEntity", "")
        lookup_sn = rel.get("Lookup", {}).get("SchemaName", "")
        lines.append(f"| {sn} | {ref_entity} | {refing_entity} | {lookup_sn} |")
    lines.append("")

    return "\n".join(lines)


def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets (shared and ALG-specific)."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    # Check and create shared option sets (fsi_acv_zone)
    print("\nShared option sets (reused from ACV):")
    for name, metadata in SHARED_OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists (reusing)")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    # Create ALG-specific option sets
    print("\nALG-specific option sets:")
    for name, metadata in OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    return {"created": created, "skipped": skipped}


def create_tables(client: DataverseClient, dry_run: bool) -> dict:
    """Create tables."""
    print("\n=== Creating Tables ===")
    created = 0
    skipped = 0
    for table_name, metadata in TABLES.items():
        logical_name = table_name.lower()
        if client.check_table_exists(logical_name):
            print(f"  {table_name}: Already exists")
            skipped += 1
        else:
            print(f"  {table_name}: Creating")
            client.create_table(metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_columns(client: DataverseClient, dry_run: bool) -> None:
    """Create columns on tables."""
    print("\n=== Creating Columns ===")
    for table_logical_name, columns in COLUMNS.items():
        print(f"\n{table_logical_name}:")
        for column_metadata in columns:
            schema_name = column_metadata.get("SchemaName", "")
            col_logical_name = schema_name.lower()
            if client.get_attribute_metadata(table_logical_name, col_logical_name):
                print(f"  {schema_name}: Already exists")
            else:
                print(f"  {schema_name}: Creating")
                client.create_column(table_logical_name, column_metadata)


def create_relationships(client: DataverseClient, dry_run: bool) -> dict:
    """Create one-to-many relationships (lookup columns)."""
    print("\n=== Creating Relationships ===")
    created = 0
    skipped = 0
    for rel_metadata in RELATIONSHIPS:
        schema_name = rel_metadata.get("SchemaName", "")
        if client.get_relationship(schema_name):
            print(f"  {schema_name}: Already exists")
            skipped += 1
        else:
            print(f"  {schema_name}: Creating")
            if not dry_run:
                client.create_relationship(rel_metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_schema(client: DataverseClient, dry_run: bool) -> dict:
    """Create complete schema (orchestrator)."""
    option_set_results = create_optionsets(client, dry_run)
    table_results = create_tables(client, dry_run)
    create_columns(client, dry_run)
    relationship_results = create_relationships(client, dry_run)
    print("\n=== Schema Creation Complete ===")
    return {
        "errors": 0,
        "option_sets": option_set_results,
        "tables": table_results,
        "relationships": relationship_results,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Agent 365 Lifecycle Governance",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("ALG_TENANT_ID"), help="Entra ID tenant ID (or set ALG_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("ALG_CLIENT_ID"), help="Application (client) ID (or set ALG_CLIENT_ID env var)")
    parser.add_argument("--environment-url", default=os.environ.get("ALG_ENVIRONMENT_URL"), help="Dataverse environment URL (or set ALG_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication")
    parser.add_argument("--dry-run", action="store_true", help="Preview schema operations without API calls")
    parser.add_argument("--output-docs", action="store_true", help="Generate docs/dataverse-schema.md and exit (no credentials required)")
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

    if not args.tenant_id or not args.environment_url:
        parser.error("Missing required arguments. Provide --tenant-id and --environment-url (or set ALG_TENANT_ID and ALG_ENVIRONMENT_URL env vars)")
    if not args.client_id and not args.interactive:
        parser.error("--client-id is required (or set ALG_CLIENT_ID env var) unless --interactive is specified")

    client_secret = os.environ.get("ALG_CLIENT_SECRET")
    if not args.interactive:
        if not client_secret:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        if args.dry_run:
            print("=== DRY RUN MODE - No changes will be made ===")

        create_schema(client, args.dry_run)

        if not args.dry_run:
            print("\nSchema deployment: SUCCESS")

        sys.exit(0)
    except requests.HTTPError as e:
        print(f"HTTP Error: {e}", file=sys.stderr)
        sys.exit(2)
    except RuntimeError as e:
        print(f"Authentication Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(4)


if __name__ == "__main__":
    main()
