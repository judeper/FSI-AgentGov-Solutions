#!/usr/bin/env python3
"""
Create Dataverse schema for Unrestricted Agent Sharing Detector.

Creates SharingViolation, SharingException, AgentSharingSetting, ApprovedSecurityGroup,
and SharingPolicy tables with all columns, choice fields, and supporting option sets.
Reuses shared ACV option set (fsi_acv_zone) when present.
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

# UASD-specific option sets
OPTIONSETS = {
    "fsi_UASD_violationtype": {
        "Name": "fsi_UASD_violationtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Violation Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of sharing violation detected", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "ORG_WIDE_SHARING", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "PUBLIC_INTERNET_LINK", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "UNAPPROVED_GROUP", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "EXCESSIVE_INDIVIDUAL", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "CROSS_TENANT_ACCESS", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "POLICY_VIOLATION", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_UASD_violationstatus": {
        "Name": "fsi_UASD_violationstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Violation Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current status of a sharing violation", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Open", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Remediated", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Exception Approved", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "False Positive", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Remediation Failed", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_UASD_severity": {
        "Name": "fsi_UASD_severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Severity level of sharing violation", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Medium", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Low", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_UASD_exceptionstatus": {
        "Name": "fsi_UASD_exceptionstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Exception Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Status of a sharing exception request", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Pending", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Approved", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Expired", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_UASD_dataclassification": {
        "Name": "fsi_UASD_dataclassification",
        "DisplayName": {"LocalizedLabels": [{"Label": "Data Classification", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Data classification level", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Public", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Internal", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Confidential", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Restricted", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_UASD_zoneclassification": {
        "Name": "fsi_UASD_zoneclassification",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone Classification", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Governance zone classification for sharing policies", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Zone 1 (Personal)", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Zone 2 (Team)", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Zone 3 (Enterprise)", "LanguageCode": 1033}]}},
        ],
    },
}

# Table definitions
TABLES = {
    "fsi_SharingViolation": {
        "SchemaName": "fsi_SharingViolation",
        "DisplayName": {"LocalizedLabels": [{"Label": "Sharing Violation", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Sharing Violations", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Detected unrestricted agent sharing violations", "LanguageCode": 1033}]},
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
                "DisplayName": {"LocalizedLabels": [{"Label": "Violation ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Unique violation identifier", "LanguageCode": 1033}]},
                "MaxLength": 100,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
    "fsi_SharingException": {
        "SchemaName": "fsi_SharingException",
        "DisplayName": {"LocalizedLabels": [{"Label": "Sharing Exception", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Sharing Exceptions", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Approved exceptions to sharing policy violations", "LanguageCode": 1033}]},
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
                "DisplayName": {"LocalizedLabels": [{"Label": "Exception ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Unique exception identifier", "LanguageCode": 1033}]},
                "MaxLength": 100,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
    "fsi_AgentSharingSetting": {
        "SchemaName": "fsi_AgentSharingSetting",
        "DisplayName": {"LocalizedLabels": [{"Label": "Agent Sharing Setting", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Agent Sharing Settings", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current sharing configuration for each agent", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Agent ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Unique agent identifier", "LanguageCode": 1033}]},
                "MaxLength": 50,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_agentid",
    },
    "fsi_ApprovedSecurityGroup": {
        "SchemaName": "fsi_ApprovedSecurityGroup",
        "DisplayName": {"LocalizedLabels": [{"Label": "Approved Security Group", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Approved Security Groups", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Pre-approved Entra ID security groups for agent sharing", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_EntraIdGroupId",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Entra ID Group ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Entra ID object ID of the security group", "LanguageCode": 1033}]},
                "MaxLength": 50,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_entraidgroupid",
    },
    "fsi_SharingPolicy": {
        "SchemaName": "fsi_SharingPolicy",
        "DisplayName": {"LocalizedLabels": [{"Label": "Sharing Policy", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Sharing Policies", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Zone-specific agent sharing policy definitions", "LanguageCode": 1033}]},
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
                "DisplayName": {"LocalizedLabels": [{"Label": "Policy Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Sharing policy name", "LanguageCode": 1033}]},
                "MaxLength": 100,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
}

# Column definitions for each table
COLUMNS = {
    "fsi_sharingviolation": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Unique identifier of the agent", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the agent", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Power Platform environment identifier", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the environment", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ViolationType",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Violation Type", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Type of sharing violation detected", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_violationtype')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ViolationStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Violation Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current status of the violation", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_violationstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Severity",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Severity level of the violation", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_severity')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Description",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Description", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Detailed description of the violation", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PrincipalDetails",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Principal Details", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Details of principals involved in the violation", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EvidenceJson",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Evidence JSON", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON evidence payload for the violation", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DetectedAt",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Detected At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the violation was detected", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RemediatedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Remediated At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the violation was remediated", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RemediationResult",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Result", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Result details of remediation action", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ScanRunId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Scan Run ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "GUID correlating all records in one scan run", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
    ],
    "fsi_sharingexception": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Unique identifier of the agent", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the agent", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Power Platform environment identifier", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the environment", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ViolationType",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Violation Type", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Type of sharing violation excepted", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_violationtype')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ExceptionStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Exception Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current status of the exception request", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_exceptionstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DataClassification",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Data Classification", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Data classification level of affected data", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_dataclassification')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_BusinessJustification",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Business Justification", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Business justification for the exception", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RequestedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Requested By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person who requested the exception", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RequestedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Requested At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the exception was requested", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DecimalAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RequestedDuration",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Requested Duration (Days)", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Requested exception duration in days", "LanguageCode": 1033}]},
            "Precision": 0,
            "MinValue": 1,
            "MaxValue": 365,
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedBySecurity",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved By Security", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of security approver", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedByDataOwner",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved By Data Owner", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of data owner approver", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedByCompliance",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved By Compliance", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of compliance approver", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the exception was approved", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ExpiresAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Expires At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the exception expires", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
    ],
    "fsi_agentsharingsetting": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentDisplayName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Display Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the agent", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Power Platform environment identifier", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentDisplayName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment Display Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the environment", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SharingScope",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sharing Scope", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current sharing scope of the agent", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SecurityGroupsJson",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Security Groups JSON", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON array of security groups the agent is shared with", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_IndividualSharesJson",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Individual Shares JSON", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON array of individual users the agent is shared with", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PublicLinkEnabled",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Public Link Enabled", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether a public internet link is enabled for this agent", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CrossTenantEnabled",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Cross Tenant Enabled", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether cross-tenant access is enabled for this agent", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LastScannedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Last Scanned At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When this agent was last scanned", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_BreakGlassExclude",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Break Glass Exclude", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether this agent is excluded from scanning via break-glass", "LanguageCode": 1033}]},
            "IsAuditEnabled": {"Value": True},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
    ],
    "fsi_approvedsecuritygroup": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DisplayName",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Display Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the security group", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Description",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Description", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Description of the security group purpose", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ZoneClassification",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone Classification", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone classification for this group", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_zoneclassification')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_IsActive",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Is Active", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether this group approval is currently active", "LanguageCode": 1033}]},
            "DefaultValue": True,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person who approved this group", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When this group was approved", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
    ],
    "fsi_sharingpolicy": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ZoneClassification",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone Classification", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone this policy applies to", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_UASD_zoneclassification')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_MaxIndividualShares",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Max Individual Shares", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Maximum number of individual user shares allowed", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AllowOrgWidesharing",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Allow Org-Wide Sharing", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether organization-wide sharing is allowed", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AllowPublicLink",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Allow Public Link", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether public internet links are allowed", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AllowCrossTenant",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Allow Cross Tenant", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether cross-tenant sharing is allowed", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedGroupsOnly",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved Groups Only", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether sharing is restricted to approved security groups only", "LanguageCode": 1033}]},
            "DefaultValue": True,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_IsActive",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Is Active", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether this policy is currently active", "LanguageCode": 1033}]},
            "DefaultValue": True,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CreatedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Created By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person who created this policy", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CreatedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Created At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When this policy was created", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ModifiedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Modified At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When this policy was last modified", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
    ],
}

RELATIONSHIPS = [
    {
        "@odata.type": "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_SharingViolation_SharingException",
        "ReferencedEntity": "fsi_sharingviolation",
        "ReferencingEntity": "fsi_sharingexception",
        "CascadeConfiguration": {
            "Assign": "NoCascade",
            "Delete": "RemoveLink",
            "Merge": "NoCascade",
            "Reparent": "NoCascade",
            "Share": "NoCascade",
            "Unshare": "NoCascade",
        },
        "Lookup": {
            "SchemaName": f"{PUBLISHER_PREFIX}_RelatedViolationId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Related Violation", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Optional link to the violation record this exception addresses", "LanguageCode": 1033}]},
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
    lines.append("> Auto-generated from `create_uasd_dataverse_schema.py`. Do not edit manually.")
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
                '> **⚠️ Important:** `fsi_acv_zone` and `fsi_UASD_zoneclassification` '
                'use **incompatible value mappings** for zones. `fsi_acv_zone` starts '
                'with Unclassified at 100000000, shifting zone numbers up by one '
                '(Zone 1 = 100000001). UASD tables bind exclusively to '
                '`fsi_UASD_zoneclassification` (Zone 1 = 100000000). When building '
                'flows, always use `fsi_UASD_zoneclassification` values for UASD '
                'tables — do **not** substitute `fsi_acv_zone` values from ELM lookups '
                'without remapping.'
            )
            lines.append("")

    lines.append("### UASD Option Sets")
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
    """Create global option sets (shared and UASD-specific)."""
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

    # Create UASD-specific option sets
    print("\nUASD-specific option sets:")
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
        description="Create Dataverse schema for Unrestricted Agent Sharing Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("UASD_TENANT_ID"), help="Entra ID tenant ID (or set UASD_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("UASD_CLIENT_ID"), help="Application (client) ID (or set UASD_CLIENT_ID env var)")
    parser.add_argument("--environment-url", default=os.environ.get("UASD_ENVIRONMENT_URL"), help="Dataverse environment URL (or set UASD_ENVIRONMENT_URL env var)")
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
        parser.error("Missing required arguments. Provide --tenant-id and --environment-url (or set UASD_TENANT_ID and UASD_ENVIRONMENT_URL env vars)")
    if not args.client_id and not args.interactive:
        parser.error("--client-id is required (or set UASD_CLIENT_ID env var) unless --interactive is specified")

    client_secret = os.environ.get("UASD_CLIENT_SECRET")
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
