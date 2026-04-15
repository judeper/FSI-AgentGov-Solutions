#!/usr/bin/env python3
"""
Create Dataverse schema for Conditional Access Automation.

Deploys three tables, two global option sets, and all columns required
for CA policy baseline snapshots, immutable validation history, and
per-policy violation tracking. Reuses the shared fsi_acv_zone option set
when present.

Tables:
  - fsi_CAPolicyBaseline: Point-in-time CA policy configuration snapshots
  - fsi_CAPolicyValidationHistory: Immutable audit trail of compliance scans
  - fsi_CAPolicyViolation: Individual policy-level violation records

Option Sets:
  - fsi_acv_zone (shared): Governance zone classification
  - fsi_acv_severity (CAA): Validation severity levels

All operations are idempotent — safe to re-run.
"""

import argparse
import os
import sys
from typing import Optional

import requests

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Shared Option Sets (reused from ACV) — only create if missing
# =============================================================================

SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "Name": "fsi_acv_zone",
        "DisplayName": {
            "LocalizedLabels": [{"Label": "Governance Zone", "LanguageCode": 1033}]
        },
        "Description": {
            "LocalizedLabels": [
                {"Label": "Governance zone classification", "LanguageCode": 1033}
            ]
        },
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {
                "Value": 100000000,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "Unclassified", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "Value": 100000001,
                "Label": {
                    "LocalizedLabels": [{"Label": "Zone 1", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 100000002,
                "Label": {
                    "LocalizedLabels": [{"Label": "Zone 2", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 100000003,
                "Label": {
                    "LocalizedLabels": [{"Label": "Zone 3", "LanguageCode": 1033}]
                },
            },
        ],
    },
}

# =============================================================================
# CAA-Specific Option Sets
# =============================================================================

OPTIONSETS = {
    "fsi_acv_severity": {
        "Name": "fsi_acv_severity",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Validation Severity", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Severity level for CA policy validation results",
                    "LanguageCode": 1033,
                }
            ]
        },
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {
                "Value": 100000000,
                "Label": {
                    "LocalizedLabels": [{"Label": "Passed", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 100000001,
                "Label": {
                    "LocalizedLabels": [{"Label": "Warning", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 100000002,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "GracePeriod", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "Value": 100000003,
                "Label": {
                    "LocalizedLabels": [{"Label": "Failed", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 100000004,
                "Label": {
                    "LocalizedLabels": [{"Label": "Error", "LanguageCode": 1033}]
                },
            },
        ],
    },
}

# =============================================================================
# Table Definitions
# =============================================================================

TABLES = {
    "fsi_CAPolicyBaseline": {
        "SchemaName": "fsi_CAPolicyBaseline",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "CA Policy Baseline", "LanguageCode": 1033}
            ]
        },
        "DisplayCollectionName": {
            "LocalizedLabels": [
                {"Label": "CA Policy Baselines", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": (
                        "Point-in-time snapshots of Conditional Access policy "
                        "configurations for drift detection"
                    ),
                    "LanguageCode": 1033,
                }
            ]
        },
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Policy_Display_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {
                    "LocalizedLabels": [
                        {"Label": "Policy Display Name", "LanguageCode": 1033}
                    ]
                },
                "Description": {
                    "LocalizedLabels": [
                        {
                            "Label": "Primary name — CA policy display name",
                            "LanguageCode": 1033,
                        }
                    ]
                },
                "MaxLength": 256,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_policy_display_name",
    },
    "fsi_CAPolicyValidationHistory": {
        "SchemaName": "fsi_CAPolicyValidationHistory",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "CA Policy Validation History", "LanguageCode": 1033}
            ]
        },
        "DisplayCollectionName": {
            "LocalizedLabels": [
                {
                    "Label": "CA Policy Validation Histories",
                    "LanguageCode": 1033,
                }
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": (
                        "Immutable audit trail of compliance scan results — "
                        "organization-owned to prevent individual record deletion"
                    ),
                    "LanguageCode": 1033,
                }
            ]
        },
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Run_Id",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {
                    "LocalizedLabels": [
                        {"Label": "Run ID", "LanguageCode": 1033}
                    ]
                },
                "Description": {
                    "LocalizedLabels": [
                        {
                            "Label": (
                                "Primary name — unique identifier for each "
                                "validation run"
                            ),
                            "LanguageCode": 1033,
                        }
                    ]
                },
                "MaxLength": 50,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_run_id",
    },
    "fsi_CAPolicyViolation": {
        "SchemaName": "fsi_CAPolicyViolation",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "CA Policy Violation", "LanguageCode": 1033}
            ]
        },
        "DisplayCollectionName": {
            "LocalizedLabels": [
                {"Label": "CA Policy Violations", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": (
                        "Individual policy-level violation records with "
                        "resolution tracking and severity-based escalation"
                    ),
                    "LanguageCode": 1033,
                }
            ]
        },
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Policy_Display_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {
                    "LocalizedLabels": [
                        {"Label": "Policy Display Name", "LanguageCode": 1033}
                    ]
                },
                "Description": {
                    "LocalizedLabels": [
                        {
                            "Label": (
                                "Primary name — CA policy that triggered "
                                "the violation"
                            ),
                            "LanguageCode": 1033,
                        }
                    ]
                },
                "MaxLength": 256,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_policy_display_name",
    },
}

# =============================================================================
# Column Definitions (per table logical name)
# =============================================================================

COLUMNS = {
    # -----------------------------------------------------------------
    # fsi_CAPolicyBaseline columns
    # -----------------------------------------------------------------
    "fsi_capolicybaseline": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Policy_Id",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Policy ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Entra ID object ID of the CA policy",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Policy_State",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Policy State", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Policy state at capture time (enabled, disabled, "
                            "enabledForReportingButNotEnforced)"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Governance zone classification",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Conditions_Json",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Conditions JSON", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Full conditions block (users, applications, "
                            "locations, platforms, risk levels)"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Grant_Controls_Json",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Grant Controls JSON", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Grant control requirements "
                            "(MFA, compliant device, etc.)"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Session_Controls_Json",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Session Controls JSON", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Session control settings (sign-in frequency, "
                            "persistent browser, etc.)"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Break_Glass_Exclusions",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Break Glass Exclusions", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Emergency access account exclusions",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Baseline_Hash",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Baseline Hash", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "SHA-256 hash of the serialized policy "
                            "for fast drift comparison"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 64,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Is_Active",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Is Active", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Whether this baseline is the current "
                            "active snapshot"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {
                    "Value": 1,
                    "Label": {
                        "LocalizedLabels": [
                            {"Label": "Yes", "LanguageCode": 1033}
                        ]
                    },
                },
                "FalseOption": {
                    "Value": 0,
                    "Label": {
                        "LocalizedLabels": [
                            {"Label": "No", "LanguageCode": 1033}
                        ]
                    },
                },
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Captured_At",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Captured At", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "UTC timestamp when the baseline was captured",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Captured_By",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Captured By", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Identity that captured the baseline "
                            "(UPN or service principal)"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 256,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Tenant_Id",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Tenant ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Entra ID tenant GUID",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
    ],
    # -----------------------------------------------------------------
    # fsi_CAPolicyValidationHistory columns
    # -----------------------------------------------------------------
    "fsi_capolicyvalidationhistory": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Validation_Time",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Validation Time", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "UTC timestamp when the scan executed",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Total_Policies",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Total Policies", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Number of CA policies evaluated",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Passed_Count",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Passed Count", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Policies that met all requirements",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Warning_Count",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Warning Count", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Policies with non-critical findings",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Failed_Count",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Failed Count", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Policies that failed validation checks",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Drift_Count",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Drift Count", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Policies that drifted from baseline",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Overall_Severity",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Overall Severity", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Worst severity across all evaluated policies"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Results_Json",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Results JSON", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Full scan results array with "
                            "per-policy detail"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Validated_By",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Validated By", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Identity that executed the scan",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 256,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Tenant_Id",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Tenant ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Entra ID tenant GUID",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
    ],
    # -----------------------------------------------------------------
    # fsi_CAPolicyViolation columns
    # -----------------------------------------------------------------
    "fsi_capolicyviolation": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Run_Id",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Run ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Validation run that detected the violation"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Policy_Id",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Policy ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Entra ID object ID of the violating policy"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Violation_Type",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Violation Type", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Category (e.g., state_drift, condition_change, "
                            "grant_mismatch, policy_removed)"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Governance zone of the affected policy",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Severity",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Severity", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Severity level of the violation",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Expected_Value",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Expected Value", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Baseline value that was expected",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Actual_Value",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Actual Value", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Current value that differs from baseline"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Description",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Description", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Human-readable explanation of the violation"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Is_Resolved",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Is Resolved", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Whether the violation has been addressed"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {
                    "Value": 1,
                    "Label": {
                        "LocalizedLabels": [
                            {"Label": "Yes", "LanguageCode": 1033}
                        ]
                    },
                },
                "FalseOption": {
                    "Value": 0,
                    "Label": {
                        "LocalizedLabels": [
                            {"Label": "No", "LanguageCode": 1033}
                        ]
                    },
                },
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Resolved_At",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Resolved At", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "UTC timestamp when the violation was resolved"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Resolved_By",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Resolved By", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Identity that resolved the violation"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 256,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Detected_At",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Detected At", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "UTC timestamp when the violation was detected"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Tenant_Id",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Tenant ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Entra ID tenant GUID",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
    ],
}

# No formal Dataverse relationships — logical links via fsi_run_id / fsi_policy_id
RELATIONSHIPS: list = []


# =============================================================================
# Documentation Generation Helpers
# =============================================================================


def _label(obj: dict) -> str:
    """Extract the English label from a Dataverse LocalizedLabels structure."""
    labels = obj.get("LocalizedLabels", [])
    for lbl in labels:
        if lbl.get("LanguageCode") == 1033:
            return lbl.get("Label", "")
    return labels[0].get("Label", "") if labels else ""


def _col_type(col: dict) -> str:
    """Return a human-friendly column type from the @odata.type."""
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
    odata = col.get("@odata.type", "")
    return mapping.get(odata, odata.split(".")[-1] if odata else "Unknown")


def _optionset_name_from_bind(col: dict) -> Optional[str]:
    """Extract the global option-set name from a GlobalOptionSet@odata.bind."""
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
    """Generate a Markdown reference document from the in-memory schema."""
    lines: list[str] = []

    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append(
        "> Auto-generated from `create_caa_dataverse_schema.py`. "
        "Do not edit manually."
    )
    lines.append("")

    # Tables overview
    lines.append("## Tables")
    lines.append("")
    lines.append(
        "| SchemaName | Logical Name | Ownership | Description "
        "| Primary Name Attribute |"
    )
    lines.append("|---|---|---|---|---|")
    for schema_name, tbl in TABLES.items():
        logical = schema_name.lower()
        ownership = tbl.get("OwnershipType", "")
        desc = _label(tbl.get("Description", {}))
        pna = tbl.get("PrimaryNameAttribute", "")
        lines.append(
            f"| {schema_name} | {logical} | {ownership} | {desc} | {pna} |"
        )
    lines.append("")

    # Columns per table
    lines.append("## Columns")
    lines.append("")

    for table_schema_name, tbl in TABLES.items():
        table_logical = table_schema_name.lower()
        primary_attrs = tbl.get("Attributes", [])
        extra_cols = COLUMNS.get(table_logical, [])
        all_cols = primary_attrs + extra_cols

        lines.append(f"### {table_schema_name} (`{table_logical}`)")
        lines.append("")
        lines.append(
            "| SchemaName | Logical Name | Type | Required "
            "| Description | Option Set |"
        )
        lines.append("|---|---|---|---|---|---|")

        for col in all_cols:
            sn = col.get("SchemaName", "")
            ln = sn.lower()
            ctype = _col_type(col)
            req_val = col.get("RequiredLevel", {}).get("Value", "None")
            required = "Yes" if req_val == "ApplicationRequired" else "No"
            desc = _label(col.get("Description", {}))

            os_cell = ""
            os_name = _optionset_name_from_bind(col)
            if os_name:
                os_def = _resolve_optionset(os_name)
                if os_def:
                    os_cell = (
                        f"**{os_name}**: "
                        f"{_format_option_values(os_def.get('Options', []))}"
                    )
                else:
                    os_cell = os_name
            elif ctype == "Boolean":
                opt = col.get("OptionSet", {})
                true_lbl = (
                    _label(opt.get("TrueOption", {}).get("Label", {}))
                    if opt.get("TrueOption")
                    else "Yes"
                )
                false_lbl = (
                    _label(opt.get("FalseOption", {}).get("Label", {}))
                    if opt.get("FalseOption")
                    else "No"
                )
                os_cell = f"`1` = {true_lbl}, `0` = {false_lbl}"

            lines.append(
                f"| {sn} | {ln} | {ctype} | {required} "
                f"| {desc} | {os_cell} |"
            )
        lines.append("")

    # Option sets
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

    lines.append("### CAA Option Sets")
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

    # Relationships
    if RELATIONSHIPS:
        lines.append("## Relationships")
        lines.append("")
        lines.append(
            "| SchemaName | Referenced Entity | Referencing Entity "
            "| Lookup Column |"
        )
        lines.append("|---|---|---|---|")
        for rel in RELATIONSHIPS:
            sn = rel.get("SchemaName", "")
            ref_entity = rel.get("ReferencedEntity", "")
            refing_entity = rel.get("ReferencingEntity", "")
            lookup_sn = rel.get("Lookup", {}).get("SchemaName", "")
            lines.append(
                f"| {sn} | {ref_entity} | {refing_entity} | {lookup_sn} |"
            )
        lines.append("")

    return "\n".join(lines)


# =============================================================================
# Schema Deployment Functions
# =============================================================================


def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets (shared and CAA-specific)."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    print("\nShared option sets (reused from ACV):")
    for name, metadata in SHARED_OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists (reusing)")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    print("\nCAA-specific option sets:")
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
            if client.get_attribute_metadata(
                table_logical_name, col_logical_name
            ):
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
    if not RELATIONSHIPS:
        print("  No formal relationships (logical links via fsi_run_id / fsi_policy_id)")
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


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse schema for Conditional Access Automation"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Generate schema docs (no credentials required)\n"
            "  python create_caa_dataverse_schema.py --output-docs\n\n"
            "  # Dry run with interactive auth\n"
            "  python create_caa_dataverse_schema.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_caa_dataverse_schema.py \\\n"
            "    --tenant-id $CAA_TENANT_ID \\\n"
            "    --client-id $CAA_CLIENT_ID \\\n"
            "    --client-secret $CAA_CLIENT_SECRET \\\n"
            "    --environment-url $CAA_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CAA_TENANT_ID"),
        help="Entra ID tenant ID (or set CAA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CAA_CLIENT_ID"),
        help="Application (client) ID (or set CAA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CAA_CLIENT_SECRET"),
        help="Client secret (or set CAA_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CAA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set CAA_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview schema operations without API calls",
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

    if not args.tenant_id or not args.environment_url:
        parser.error(
            "Missing required arguments. Provide --tenant-id and "
            "--environment-url (or set CAA_TENANT_ID and "
            "CAA_ENVIRONMENT_URL env vars)"
        )
    if not args.client_id and not args.interactive:
        parser.error(
            "--client-id is required (or set CAA_CLIENT_ID env var) "
            "unless --interactive is specified"
        )

    client_secret = args.client_secret or os.environ.get("CAA_CLIENT_SECRET")
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
