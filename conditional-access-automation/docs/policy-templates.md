# Policy Templates

Detailed specifications for Conditional Access policy templates targeting AI workloads.

## Template Overview

| Template | Zone | MFA | Device | Session | State |
|----------|------|-----|--------|---------|-------|
| CA-CopilotStudio-Zone1 | 1 | Risk-based | Any | 8 hours | Report-only |
| CA-CopilotStudio-Zone2 | 2 | Required | Any | 4 hours | Report-only |
| CA-CopilotStudio-Zone3 | 3 | Required | Compliant | 1 hour | Report-only |
| CA-AgentBuilder-Zone1 | 1 | Risk-based | Any | 8 hours | Report-only |
| CA-AgentBuilder-Zone2 | 2 | Required | Any | 4 hours | Report-only |
| CA-AgentBuilder-Zone3 | 3 | Required | Compliant | 1 hour | Report-only |
| CA-M365Copilot-AllZones | All | Risk-based | Any | 8 hours | Report-only |
| CA-BlockLegacyAuth-AI | All | N/A | N/A | N/A | Report-only |
| CA-RequireCompliantDevice-Zone3 | 3 | Any | Required | N/A | Report-only |

---

## Authentication strengths and passkeys

The default templates use `builtInControls: ["mfa"]` for broad compatibility. For Zone 3 or high-risk operations, consider a tenant-specific variant that uses `grantControls.authenticationStrength` with the built-in **Phishing-resistant MFA strength** or an approved custom strength. Microsoft Learn documents that authentication strengths can require FIDO2/passkeys, Windows Hello for Business, or certificate-based authentication. Do not combine `mfa` and `authenticationStrength` in the same policy. Retrieve current strength IDs from Microsoft Graph before authoring templates.

## Template Specifications

### CA-CopilotStudio-Zone1

**Purpose:** Risk-based MFA for Zone 1 (Personal Productivity) Copilot Studio agents.

```json
{
  "displayName": "CA-CopilotStudio-Zone1-RiskBasedMFA",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeGroups": ["<zone-1-users-group-id>"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": ["<copilot-studio-app-id>"]
    },
    "signInRiskLevels": ["medium", "high"],
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  },
  "sessionControls": {
    "signInFrequency": {
      "value": 8,
      "type": "hours",
      "isEnabled": true
    }
  }
}
```

**Key Settings:**
- MFA only for medium+ risk sign-ins
- 8-hour session timeout
- Targets Zone 1 user group
- Excludes break-glass accounts

---

### CA-CopilotStudio-Zone2

**Purpose:** Always require MFA for Zone 2 (Team Collaboration) Copilot Studio agents.

```json
{
  "displayName": "CA-CopilotStudio-Zone2-MFARequired",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeGroups": ["<zone-2-users-group-id>"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": ["<copilot-studio-app-id>"]
    },
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  },
  "sessionControls": {
    "signInFrequency": {
      "value": 4,
      "type": "hours",
      "isEnabled": true
    }
  }
}
```

**Key Settings:**
- MFA always required
- 4-hour session timeout
- Targets Zone 2 user group

---

### CA-CopilotStudio-Zone3

**Purpose:** MFA + compliant device for Zone 3 (Enterprise Managed) Copilot Studio agents.

```json
{
  "displayName": "CA-CopilotStudio-Zone3-MFA-CompliantDevice",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeGroups": ["<zone-3-users-group-id>"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": ["<copilot-studio-app-id>"]
    },
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "AND",
    "builtInControls": ["mfa", "compliantDevice"]
  },
  "sessionControls": {
    "signInFrequency": {
      "value": 1,
      "type": "hours",
      "isEnabled": true
    },
    "persistentBrowser": {
      "mode": "never",
      "isEnabled": true
    }
  }
}
```

**Key Settings:**
- MFA AND compliant device required
- 1-hour session timeout
- No persistent browser sessions
- Targets Zone 3 user group

---

### CA-AgentBuilder-Zone1

**Purpose:** Risk-based MFA for Zone 1 (Personal Productivity) Agent Builder access.

```json
{
  "displayName": "CA-AgentBuilder-Zone1-RiskBasedMFA",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeGroups": ["<zone-1-users-group-id>"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": ["<agent-builder-app-id>"]
    },
    "signInRiskLevels": ["medium", "high"],
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  },
  "sessionControls": {
    "signInFrequency": {
      "value": 8,
      "type": "hours",
      "isEnabled": true
    }
  }
}
```

**Key Settings:**
- MFA only for medium+ risk sign-ins
- 8-hour session timeout
- Targets Zone 1 user group
- Mirrors CA-CopilotStudio-Zone1 controls for Agent Builder

---

### CA-AgentBuilder-Zone2

**Purpose:** MFA for Zone 2 Agent Builder access.

```json
{
  "displayName": "CA-AgentBuilder-Zone2-MFARequired",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeGroups": ["<zone-2-users-group-id>"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": ["<agent-builder-app-id>"]
    },
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  },
  "sessionControls": {
    "signInFrequency": {
      "value": 4,
      "type": "hours",
      "isEnabled": true
    }
  }
}
```

---

### CA-AgentBuilder-Zone3

**Purpose:** MFA + compliant device for Zone 3 Agent Builder access.

```json
{
  "displayName": "CA-AgentBuilder-Zone3-MFA-CompliantDevice",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeGroups": ["<zone-3-users-group-id>"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": ["<agent-builder-app-id>"]
    },
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "AND",
    "builtInControls": ["mfa", "compliantDevice"]
  },
  "sessionControls": {
    "signInFrequency": {
      "value": 1,
      "type": "hours",
      "isEnabled": true
    }
  }
}
```

---

### CA-M365Copilot-AllZones

**Purpose:** Baseline risk-based MFA for all M365 Copilot access.

```json
{
  "displayName": "CA-M365Copilot-AllZones-RiskBasedMFA",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeUsers": ["All"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"],
      "excludeGuestsOrExternalUsers": {
        "guestOrExternalUserTypes": "b2bCollaborationGuest,b2bCollaborationMember"
      }
    },
    "applications": {
      "includeApplications": ["<m365-copilot-app-id>"]
    },
    "signInRiskLevels": ["low", "medium", "high"],
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  },
  "sessionControls": {
    "signInFrequency": {
      "value": 8,
      "type": "hours",
      "isEnabled": true
    }
  }
}
```

**Key Settings:**
- Applies to all users (except guests, break-glass)
- MFA for any risk level
- Uses the M365 Copilot app ID from `config.applications.m365Copilot` (substituted by `Deploy-CAPolicies.ps1` at deploy time)

---

### CA-BlockLegacyAuth-AI

**Purpose:** Block legacy authentication protocols for all AI applications.

```json
{
  "displayName": "CA-BlockLegacyAuth-AllAI",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeUsers": ["All"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": [
        "<copilot-studio-app-id>",
        "<agent-builder-app-id>",
        "<m365-copilot-app-id>"
      ]
    },
    "clientAppTypes": ["exchangeActiveSync", "other"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["block"]
  }
}
```

**Key Settings:**
- Blocks Exchange ActiveSync and legacy clients
- Critical security baseline
- Helps reduce MFA bypass risk by blocking legacy client types

---

### CA-RequireCompliantDevice-Zone3

**Purpose:** Require compliant or hybrid-joined device for Zone 3 applications.

```json
{
  "displayName": "CA-RequireCompliantDevice-Zone3",
  "state": "enabledForReportingButNotEnforced",
  "conditions": {
    "users": {
      "includeGroups": ["<zone-3-users-group-id>"],
      "excludeUsers": ["<break-glass-1>", "<break-glass-2>"]
    },
    "applications": {
      "includeApplications": [
        "<copilot-studio-app-id>",
        "<agent-builder-app-id>"
      ]
    },
    "platforms": {
      "includePlatforms": ["windows", "macOS", "iOS", "android"]
    },
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"]
  },
  "grantControls": {
    "operator": "AND",
    "builtInControls": ["mfa", "compliantDevice"]
  }
}
```

**Key Settings:**
- MFA AND compliant device required
- Covers Windows, macOS, iOS, Android
- Zone 3 users only

---

## Customization Guide

### Replace Placeholders

Before deployment, replace these placeholders in templates:

| Placeholder | Description | How to Find |
|-------------|-------------|-------------|
| `<zone-1-users-group-id>` | Security group for Zone 1 users | Entra ID > Groups |
| `<zone-2-users-group-id>` | Security group for Zone 2 users | Entra ID > Groups |
| `<zone-3-users-group-id>` | Security group for Zone 3 users | Entra ID > Groups |
| `<copilot-studio-app-id>` | Copilot Studio app ID | Enterprise Applications |
| `<agent-builder-app-id>` | Agent Builder app ID | Enterprise Applications |
| `<break-glass-1>` | Emergency account 1 object ID | Entra ID > Users |
| `<break-glass-2>` | Emergency account 2 object ID | Entra ID > Users |

### Find Group IDs

```powershell
Get-MgGroup -Filter "displayName eq 'Zone-3-AI-Users'" |
    Select-Object DisplayName, Id
```

### Find Application IDs

```powershell
Get-MgServicePrincipal -Filter "startswith(displayName, 'Copilot')" |
    Select-Object DisplayName, AppId, Id

# Power Automate embedded-flow compatibility check
Get-MgServicePrincipal -Filter "appId eq '7df0a125-d3be-4c96-aa54-591f83ff541c'" |
    Select-Object DisplayName, AppId, Id
```

When targeting individual cloud apps, review Microsoft Flow Service (`7df0a125-d3be-4c96-aa54-591f83ff541c`) with Power Apps, Power Automate, Teams, SharePoint, Excel, and Copilot Studio host apps so Conditional Access requirements remain consistent for embedded flow token exchange.

---

## Combining Policies

Policies are additive - users may be subject to multiple policies:

### Zone 3 User Example

A Zone 3 user accessing Copilot Studio would be evaluated by:

1. **CA-CopilotStudio-Zone3** - Requires MFA + compliant device
2. **CA-BlockLegacyAuth-AI** - Blocks legacy auth
3. **CA-RequireCompliantDevice-Zone3** - Requires device compliance

**Result:** Must use MFA, compliant device, and modern authentication.

### Policy Precedence

- Block policies take precedence over grant policies
- AND operators require ALL controls
- OR operators require ANY control
- Most restrictive combination applies

---

## Testing Recommendations

### Report-Only Testing

1. Deploy all policies in report-only mode
2. Wait 7 days for data collection
3. Review Conditional Access insights
4. Check for unexpected blocks
5. Verify coverage completeness

### What-If Analysis

Use the What-If tool in Entra ID:

1. Navigate to Entra ID > Conditional Access > What If
2. Select user, application, and conditions
3. Review which policies would apply
4. Verify expected behavior

### Staged Rollout

1. **Week 1:** Deploy to pilot group (10-20 users)
2. **Week 2:** Expand to early adopters (100 users)
3. **Week 3:** Deploy to Zone 1 users
4. **Week 4:** Deploy to Zone 2 users
5. **Week 5:** Deploy to Zone 3 users

---

## Default Audit Mode and Placeholder Validation

### Report-Only Default State

All 9 CA policy templates ship with `state: "enabledForReportingButNotEnforced"` (audit/report-only mode). This is intentional — policies should be tested with the What-If tool and Conditional Access insights before enforcement.

To enable policies for enforcement, use `Deploy-CAPolicies.ps1 -EnablePolicies $true` or manually update the `state` field to `"enabled"` in the Entra admin center.

### Placeholder Tokens

Templates contain `<placeholder>` tokens (e.g., `<zone-3-users-group-id>`, `<copilot-studio-app-id>`, `<break-glass-1>`) that must be replaced with tenant-specific values at deploy time. `Deploy-CAPolicies.ps1` performs this substitution using values from the configuration file (`-ConfigPath`).

**Pre-deployment validation:** `Deploy-CAPolicies.ps1` validates that all
`<placeholder>` tokens were substituted from `-ConfigPath` before issuing the
Graph API call. If any placeholder remains unresolved (e.g., a missing field
in `config.json`), the script fails fast with a clear error rather than
sending an invalid GUID to Microsoft Graph.

To author and deploy safely:

1. Run `Deploy-CAPolicies.ps1 -WhatIf` first and review the substituted values
   in verbose output.
2. Ensure your `config.json` contains all required fields (see
   `config.sample.json` for the complete schema; `policyPrefix` defaults to
   `CA-FSI`).
