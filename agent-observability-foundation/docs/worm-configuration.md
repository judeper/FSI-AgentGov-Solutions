# WORM Configuration Guide

Manual setup for Write Once Read Many (WORM) immutable storage policies on Azure Blob Storage (StorageV2) for SEC 17a-4 compliance.

---

## WARNING: IRREVERSIBLE ACTION

> **WORM policies are PERMANENT once locked. This action CANNOT be undone.**
>
> - Locked WORM policies CANNOT be unlocked
> - Data protected by locked WORM CANNOT be deleted until retention period expires
> - Storage accounts with locked WORM containers CANNOT be deleted
> - **Test in a non-production storage account first**

This is why WORM configuration is excluded from the `provision.py` automation script. Manual configuration with explicit confirmation prevents accidental production lockdown.

---

## Overview

WORM (Write Once Read Many) policies enable immutable storage for Azure Blob Storage, meeting SEC 17a-4(f) requirements for non-erasable, non-rewritable storage of broker-dealer communications and records.

**Cohasset Validation:** Microsoft Azure Blob Storage immutable storage has been validated by Cohasset Associates for compliance with:
- SEC Rule 17a-4(f)
- FINRA Rule 4511(c)
- CFTC Rule 1.31(c)-(d)

---

## Prerequisites

Before configuring WORM policy:

1. **Storage account exists:** Provisioned by `provision.py` (StorageV2, hierarchical namespace disabled)
2. **Container exists:** `insights-logs-apptraces` container is auto-created by Azure Diagnostic Settings on first telemetry export (NOT created by `provision.py`)
3. **Diagnostic Settings configured:** Data is flowing to the container
4. **Verify test environment:** Confirm you are NOT in production (first time)

---

## Step-by-Step Portal Instructions

### Step 1: Navigate to Storage Account

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to **Storage accounts**
3. Select your telemetry storage account (e.g., `sagentobservability`)

### Step 2: Open Container Access Policy

1. In the left menu, click **Containers**
2. Click on the `insights-logs-apptraces` container
3. In the container blade, click **Access policy** in the left menu

### Step 3: Add Time-Based Retention Policy

1. Under **Immutable blob storage**, click **+ Add policy**
2. Select **Time-based retention policy**
3. Configure policy parameters:
   - **Policy state:** Unlocked (initially)
   - **Retention period:** Enter retention in days
   - **Allow protected append writes:** **ENABLED** (REQUIRED for diagnostic export pipelines)

   > **CRITICAL:** Azure Monitor diagnostic settings export telemetry by *appending* to existing blobs. A locked time-based policy without `allowProtectedAppendWrites` will block these appends and silently halt telemetry export — the storage account remains immutable but no longer receives data, creating an audit gap. Always enable protected append writes for any container that receives Azure Monitor diagnostic export.

   **Retention Period Reference:**
   | Regulatory Requirement | Minimum Days | Recommended |
   |------------------------|--------------|-------------|
   | SEC 17a-4(b)(4) - Communications | 730 (2 years) | 730 |
   | SEC 17a-4(a) - Financial records | 2190 (6 years) | 2555 (7 years) |
   | FINRA 4511 - Books and records | 2190 (6 years) | 2555 (7 years) |

4. Click **OK** to save the policy

> **Note:** The policy is now in **Unlocked** state. Data is protected by the retention period, but the policy can still be modified or deleted.

### Step 4: Review Policy State

After saving, verify the policy shows:
- **Policy state:** Unlocked
- **Retention period:** Your configured days
- **Immutability scope:** Container

### Step 5: Test in Unlocked State

Before locking the policy, verify it works as expected:

1. **Upload a test blob:**
   ```bash
   echo "test content" > test-worm.txt
   az storage blob upload \
       --account-name <storage-account> \
       --container-name insights-logs-apptraces \
       --name test-worm.txt \
       --file test-worm.txt \
       --auth-mode login
   ```

2. **Attempt to delete the test blob (should SUCCEED in Unlocked state):**
   ```bash
   az storage blob delete \
       --account-name <storage-account> \
       --container-name insights-logs-apptraces \
       --name test-worm.txt \
       --auth-mode login
   ```

3. **Expected result:** Delete succeeds (Unlocked allows deletion)

### Step 6: Verify Compliance Requirements Before Locking

Before locking, confirm:

- [ ] Storage account is the correct production account
- [ ] Retention period matches regulatory requirements
- [ ] You understand this action is IRREVERSIBLE
- [ ] Compliance/Legal team has approved the configuration
- [ ] You have documented this configuration decision

### Step 7: Lock the Policy (IRREVERSIBLE)

> **THIS ACTION CANNOT BE UNDONE**

1. Return to **Container > Access policy**
2. Click on your time-based retention policy
3. Click **Lock policy**
4. Read the confirmation warning carefully
5. Type the confirmation text if required
6. Click **OK** to lock

The policy state will change to **Locked**.

### Step 8: Test Locked Policy

Verify immutability is enforced:

1. **Upload a new test blob:**
   ```bash
   echo "locked test" > test-locked.txt
   az storage blob upload \
       --account-name <storage-account> \
       --container-name insights-logs-apptraces \
       --name test-locked.txt \
       --file test-locked.txt \
       --auth-mode login
   ```

2. **Attempt to delete the test blob (should FAIL):**
   ```bash
   az storage blob delete \
       --account-name <storage-account> \
       --container-name insights-logs-apptraces \
       --name test-locked.txt \
       --auth-mode login
   ```

3. **Expected result:** Delete fails with error:
   ```
   This operation is not permitted as the blob is immutable due to a policy.
   ```

---

## Verification

Run the verification script to confirm WORM compliance status:

```bash
python scripts/verify_worm.py --storage-account <storage-account> --container insights-logs-apptraces
```

The script performs read-only verification without modifying any policies.

---

## Compliance States

| State | SEC 17a-4 Compliant | Description |
|-------|---------------------|-------------|
| **No policy** | No | No immutability protection; data can be deleted |
| **Unlocked** | No | Policy exists but can be modified or deleted |
| **Locked, retention < 6y** | No | Policy is permanent but retention does not meet SEC 17a-4(a) (recommended ≥ 2555 days) |
| **Locked, append writes disabled** | Partial | Existing data is immutable but new diagnostic-export appends will be blocked, creating an audit gap |
| **Locked, retention ≥ 6y, append writes enabled** | Yes | Data is immutable for retention period and Azure Monitor export continues to land |

The shipped `verify_worm.py` checks all four conditions (state, retention, protected append writes, container present) and exits with code 2 if any of them fails.

---

## Policy Management After Locking

### Extending Retention Period

You CAN extend the retention period on a locked policy:

1. Navigate to **Container > Access policy**
2. Click on the locked policy
3. Increase the retention period value
4. Click **OK**

> **Note:** You can only EXTEND retention, never reduce it.

### Legal Hold

In addition to time-based retention, you can apply legal hold for litigation or investigation:

1. Navigate to **Container > Access policy**
2. Under **Legal hold**, click **+ Add**
3. Add a legal hold tag (e.g., "Investigation-2026-001")
4. Click **OK**

Legal holds:
- Can be added/removed without affecting WORM policy
- Prevent deletion regardless of retention period
- Require explicit removal when legal matter concludes

---

## Troubleshooting

### "Cannot delete storage account"

**Cause:** WORM-locked containers prevent storage account deletion.

**Resolution:**
- Wait for all retention periods to expire
- OR contact Azure Support for exceptional circumstances
- **Prevention:** Use separate storage accounts for test and production

### "Policy shows Unlocked"

**Cause:** Policy was created but not explicitly locked.

**Resolution:** Follow Step 7 to lock the policy. Unlocked policies do NOT meet SEC 17a-4 requirements.

### "Delete operation succeeded on locked container"

**Possible Causes:**
- Blob was uploaded BEFORE policy was locked
- Blob retention period has expired
- Legal hold was removed

**Verification:** Check blob immutability status in portal or via Azure CLI.

### "Cannot modify retention period"

**Cause:** Attempting to reduce retention on locked policy.

**Resolution:** Retention can only be extended on locked policies. Plan retention periods carefully before locking.

---

## Cost Implications

Locked WORM storage has cost implications:

| Consideration | Impact |
|---------------|--------|
| Storage duration | Cannot delete data before retention expires; costs accumulate |
| Storage account deletion | Cannot delete account; must wait for all containers to expire |
| Testing mistakes | Accidentally locked test data remains until expiration |

**Mitigation:**
- Use short retention periods for testing (e.g., 1 day)
- Maintain separate test and production storage accounts
- Document all WORM configurations with expiration dates

---

## Related Resources

- [verify_worm.py](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/agent-observability-foundation/scripts/verify_worm.py) - Verification script (read-only)
- [Azure Immutable Storage Overview](https://learn.microsoft.com/azure/storage/blobs/immutable-storage-overview)
- [SEC 17a-4 Compliance Assessment](https://learn.microsoft.com/en-us/compliance/regulatory/offering-SEC-docs)
- [Cohasset Compliance Assessment](https://servicetrust.microsoft.com)

---

*WORM Configuration Guide version: 1.2.0*
*Last updated: February 2026*
