# Emergency Access (Break-Glass) Drill Procedure

> **Status:** Template — adapt to your organization's emergency access policy and incident response plan.

This document covers how to test break-glass account access during disaster recovery scenarios, the recommended drill cadence, evidence collection requirements, and a post-drill review template.

## Purpose

Emergency access accounts (break-glass accounts) are highly privileged Microsoft Entra ID accounts that bypass normal access controls (MFA, Conditional Access) to restore administrative access during outages. FSI organizations must periodically verify these accounts function correctly — a break-glass account that fails during an actual emergency is worse than not having one.

This drill procedure supports compliance with OCC 2011-12 (operational resilience testing) and helps meet FFIEC BCP expectations for documented access continuity.

## Prerequisites

| Requirement | Details |
|------------|---------|
| **Break-glass accounts** | At least 2 cloud-only Microsoft Entra ID accounts excluded from all Conditional Access policies |
| **Secure credential storage** | Physical safe, split-knowledge procedure, or hardware security module |
| **Azure Monitor / Sentinel** | Sign-in logs for emergency accounts forwarded to a SIEM workspace |
| **Drill coordinator** | Named individual with authority to authorize break-glass use outside emergencies |

> **Reference:** [Microsoft Learn — Manage emergency access accounts](https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access)

## Drill Cadence

| Frequency | Activity | Regulatory Alignment |
|-----------|----------|---------------------|
| **Quarterly** (minimum) | Full break-glass drill — credential retrieval, sign-in, verification, re-seal | OCC 2011-12 (operational resilience), FFIEC BCP |
| **Annually** | Comprehensive DR exercise including break-glass as part of full business continuity test | FINRA Rule 4370, SEC 17a-4(f) |
| **On change** | Re-test whenever Conditional Access policies, MFA providers, or Entra ID tenant configuration changes | Best practice |

> **Note:** Quarterly is a minimum recommendation. Organizations with higher risk profiles or examiner findings should consider monthly drills.

## Drill Procedure

### Phase 1: Preparation

1. **Schedule the drill** with the drill coordinator and at least one witness
2. **Notify the SOC / security operations** that a break-glass test is planned (prevents false-positive incident response)
3. **Prepare an isolated workstation** or InPrivate browser session — do not use a device already signed in with production credentials
4. **Open Azure Monitor / Sentinel** in a separate session to observe sign-in events in near-real-time

### Phase 2: Credential Retrieval

1. Retrieve break-glass credentials from secure storage following your organization's split-knowledge or dual-control procedure
2. **Record the retrieval timestamp** (evidence item)
3. Verify both accounts have credentials available (primary and secondary)

### Phase 3: Sign-In Test

For **each** break-glass account:

1. Open an InPrivate / incognito browser window
2. Navigate to `https://entra.microsoft.com`
3. Sign in using the break-glass account credentials
4. **Record the sign-in timestamp** (evidence item)
5. Verify the account has Global Administrator or equivalent role
6. Perform a read-only administrative action to confirm access:
   - Navigate to **Users** → verify user list loads
   - Navigate to **Conditional Access** → verify policies are visible
7. **Record the verification timestamp** (evidence item)
8. Sign out completely
9. Close the browser window

### Phase 4: Post-Drill Verification

1. In Azure Monitor / Microsoft Entra sign-in logs, confirm:
   - Sign-in events appear for the break-glass account(s)
   - Sign-in location and IP match the drill workstation
   - No unexpected sign-in events for break-glass accounts outside the drill window
2. **Record any anomalies** (evidence item)

### Phase 5: Re-Seal

1. If credentials were changed or rotated during the drill, update secure storage
2. Re-seal the credential storage (safe, HSM, etc.)
3. **Record the re-seal timestamp** (evidence item)

## Evidence Collection Format

Each drill produces a structured evidence record. Use this format for audit documentation:

```
Drill ID:            DR-YYYY-MM-DD-NNN
Drill Date:          YYYY-MM-DD
Drill Coordinator:   [Name, Title]
Witness:             [Name, Title]
Drill Type:          Quarterly Break-Glass / Annual BCP / On-Change

Account 1:
  UPN:               [break-glass-1@domain.com]
  Credential Retrieved: YYYY-MM-DDTHH:MM:SSZ
  Sign-In Timestamp:    YYYY-MM-DDTHH:MM:SSZ
  Sign-In Result:       [Success / Failure — detail if failure]
  Verification Action:  [Action performed to confirm access]
  Verification Time:    YYYY-MM-DDTHH:MM:SSZ
  Sign-Out Time:        YYYY-MM-DDTHH:MM:SSZ
  Anomalies:            [None / describe]

Account 2:
  UPN:               [break-glass-2@domain.com]
  Credential Retrieved: YYYY-MM-DDTHH:MM:SSZ
  Sign-In Timestamp:    YYYY-MM-DDTHH:MM:SSZ
  Sign-In Result:       [Success / Failure — detail if failure]
  Verification Action:  [Action performed to confirm access]
  Verification Time:    YYYY-MM-DDTHH:MM:SSZ
  Sign-Out Time:        YYYY-MM-DDTHH:MM:SSZ
  Anomalies:            [None / describe]

Sentinel Verification:
  Sign-in logs reviewed: [Yes/No]
  Unexpected sign-ins:   [None / describe]
  Log retention confirmed: [Yes/No]

Re-Seal:
  Credentials re-sealed: YYYY-MM-DDTHH:MM:SSZ
  Storage location:      [Safe ID / HSM ID]
```

## Post-Drill Review Template

Complete this review within 5 business days of each drill:

### Drill Summary

| Field | Value |
|-------|-------|
| Drill ID | |
| Date | |
| Coordinator | |
| Witness(es) | |
| Drill type | Quarterly / Annual / On-Change |

### Results

| Check | Account 1 | Account 2 |
|-------|-----------|-----------|
| Credential retrieval successful | ☐ Yes ☐ No | ☐ Yes ☐ No |
| Sign-in successful | ☐ Yes ☐ No | ☐ Yes ☐ No |
| Admin actions verified | ☐ Yes ☐ No | ☐ Yes ☐ No |
| Sign-in logs captured in SIEM | ☐ Yes ☐ No | ☐ Yes ☐ No |
| No unexpected sign-in activity | ☐ Yes ☐ No | ☐ Yes ☐ No |
| Credentials re-sealed | ☐ Yes ☐ No | ☐ Yes ☐ No |

### Findings and Remediation

| Finding | Severity | Remediation | Owner | Target Date |
|---------|----------|-------------|-------|-------------|
| | | | | |

### Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Drill Coordinator | | | |
| IT Security Lead | | | |
| Compliance Officer | | | |

---

*Updated: May 2026 | Version: v1.0*
