# Downstream Attachment Validation Guide

> **Version:** 1.1.2 | **Control:** 1.14 — Data Minimization and Agent Scope Control

This guide documents how downstream consumers (custom Power Automate flows, Azure Functions, or other solutions) should validate file attachments **after** upload to Copilot Studio agents. These checks complement the server-side MIME validation provided by the Dataverse plugin in the [MIME Type Restrictions](../../mime-type-restrictions/README.md) solution.

## Why Downstream Validation Matters

Copilot Studio's built-in file upload handling validates basic file-type constraints at the channel level. However, once files enter the Power Platform ecosystem (Dataverse, SharePoint, OneDrive), downstream flows and tools may route them to additional services. Defense-in-depth requires that each consumer re-validates attachments before processing.

| Layer | Responsibility | Example |
|-------|---------------|---------|
| **Channel** | Basic file-type filtering by Copilot Studio | Image size limits, PDF page limits |
| **Server-side** | Dataverse plugin MIME validation | Magic-byte checks, denylist enforcement |
| **Downstream** | Consumer-specific validation | This guide |

## Validation Checks

### 1. File Magic-Number Validation

Verify that the file's binary header (magic bytes) matches the declared MIME type. Do not trust the `Content-Type` header or file extension alone.

**PowerShell example:**

```powershell
function Test-FileMagicNumber {
    <#
    .SYNOPSIS
        Validates file content against known magic-byte signatures.
    .DESCRIPTION
        Reads the first bytes of a file and compares against expected
        signatures for the declared MIME type. Returns $true if the
        signature matches, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$FileBytes,

        [Parameter(Mandatory)]
        [string]$DeclaredMimeType
    )

    $signatures = @{
        "application/pdf"  = @(0x25, 0x50, 0x44, 0x46)           # %PDF
        "image/png"        = @(0x89, 0x50, 0x4E, 0x47)           # .PNG
        "image/jpeg"       = @(0xFF, 0xD8, 0xFF)                 # JPEG SOI
        "image/gif"        = @(0x47, 0x49, 0x46, 0x38)           # GIF8
        "image/webp"       = @(0x52, 0x49, 0x46, 0x46)           # RIFF (+ WEBP at offset 8)
    }

    if (-not $signatures.ContainsKey($DeclaredMimeType)) {
        Write-Verbose "No signature defined for $DeclaredMimeType — skipping magic check"
        return $true
    }

    $expected = $signatures[$DeclaredMimeType]
    if ($FileBytes.Length -lt $expected.Length) {
        return $false
    }

    for ($i = 0; $i -lt $expected.Length; $i++) {
        if ($FileBytes[$i] -ne $expected[$i]) {
            return $false
        }
    }

    # WebP requires additional check at offset 8
    if ($DeclaredMimeType -eq "image/webp") {
        if ($FileBytes.Length -lt 12) { return $false }
        $webpSig = [System.Text.Encoding]::ASCII.GetString($FileBytes[8..11])
        if ($webpSig -ne "WEBP") { return $false }
    }

    return $true
}
```

**Python example:**

```python
MAGIC_SIGNATURES: dict[str, list[tuple[int, bytes]]] = {
    "application/pdf": [(0, b"%PDF")],
    "image/png": [(0, b"\x89PNG")],
    "image/jpeg": [(0, b"\xff\xd8\xff")],
    "image/gif": [(0, b"GIF8")],
    "image/webp": [(0, b"RIFF"), (8, b"WEBP")],
}


def validate_magic_number(file_bytes: bytes, declared_mime: str) -> bool:
    """Validate file magic bytes against declared MIME type."""
    checks = MAGIC_SIGNATURES.get(declared_mime)
    if not checks:
        return True  # No signature defined for this type

    for offset, expected in checks:
        end = offset + len(expected)
        if len(file_bytes) < end:
            return False
        if file_bytes[offset:end] != expected:
            return False
    return True
```

### 2. Microsoft Defender for Cloud Integration Check

Before processing uploaded files, verify that Microsoft Defender for Cloud Apps (MDCA) or Defender for Endpoint has scanned the file. This check is especially important for Zone 1 (Enterprise Managed) agents.

**Power Automate pattern:**

1. After file upload to SharePoint/OneDrive, wait for Defender scan completion
2. Check the file's `MalwareDetected` metadata property
3. Block processing if malware is detected or scan is incomplete

**PowerShell example (SharePoint):**

```powershell
function Test-DefenderScanStatus {
    <#
    .SYNOPSIS
        Checks Defender scan status for a SharePoint file.
    .DESCRIPTION
        Queries the Microsoft Graph driveItem malware metadata to verify
        scan completion. Returns scan status and any detection details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DriveId,

        [Parameter(Mandatory)]
        [string]$ItemId,

        [Parameter(Mandatory)]
        [string]$AccessToken
    )

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Accept"        = "application/json"
    }

    $uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$ItemId"
    $item = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    # Check malware metadata (available when Defender for Office 365 is active)
    $malwareInfo = $item.malware
    if ($malwareInfo) {
        return @{
            Status   = "MalwareDetected"
            Details  = $malwareInfo.description
            Blocked  = $true
        }
    }

    return @{
        Status   = "Clean"
        Details  = "No malware detected"
        Blocked  = $false
    }
}
```

> **Note:** Defender for Cloud Apps file policies provide API-based continuous controls for files stored in connected cloud apps. These policies complement but do not replace per-file validation at the flow level.

### 3. Sensitivity Label Inheritance Verification

When files are uploaded to agent conversations, verify that the appropriate sensitivity label is applied or inherited from the parent container.

**Verification steps:**

1. Read the file's current sensitivity label via Microsoft Graph
2. Compare against the minimum required label for the agent's governance zone
3. If the file lacks a label or has a lower-classification label than required, apply the zone's default label or block processing

**PowerShell example:**

```powershell
function Test-SensitivityLabelCompliance {
    <#
    .SYNOPSIS
        Verifies file sensitivity label meets zone requirements.
    .DESCRIPTION
        Checks the file's sensitivity label against the minimum
        required for the agent's governance zone. Uses Microsoft
        Graph extractSensitivityLabels API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DriveId,

        [Parameter(Mandatory)]
        [string]$ItemId,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [ValidateSet("Zone1", "Zone2", "Zone3")]
        [string]$GovernanceZone
    )

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    # Extract current label
    $uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$ItemId/extractSensitivityLabels"
    try {
        $labels = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post
    }
    catch {
        Write-Warning "Could not extract sensitivity labels: $($_.Exception.Message)"
        return @{
            Compliant = $false
            Reason    = "Label extraction failed"
            Action    = "ManualReview"
        }
    }

    $currentLabel = $labels.labels | Select-Object -First 1

    # Zone minimum labels (organization-specific — customize per tenant)
    $zoneMinimums = @{
        "Zone1" = "General"
        "Zone2" = "Internal"
        "Zone3" = "Confidential"
    }

    $requiredLabel = $zoneMinimums[$GovernanceZone]

    if (-not $currentLabel) {
        return @{
            Compliant = $false
            Reason    = "No sensitivity label applied"
            Action    = "ApplyLabel"
            Required  = $requiredLabel
        }
    }

    return @{
        Compliant    = $true
        CurrentLabel = $currentLabel.sensitivityLabelId
        Required     = $requiredLabel
    }
}
```

## Integration Pattern

Combine all three checks in a downstream validation flow:

```
Upload Event
    │
    ▼
┌─────────────────────────┐
│ 1. Magic-number check   │ ──→ FAIL: Block + log
└────────────┬────────────┘
             │ PASS
             ▼
┌─────────────────────────┐
│ 2. Defender scan check  │ ──→ MALWARE: Block + alert
└────────────┬────────────┘
             │ CLEAN
             ▼
┌─────────────────────────┐
│ 3. Sensitivity label    │ ──→ MISSING: Apply default or block
└────────────┬────────────┘
             │ COMPLIANT
             ▼
    Process file normally
```

## Regulatory Context

These validation checks support compliance with:

| Regulation | Relevance |
|-----------|-----------|
| **FINRA Regulatory Notice 25-07** | Defense-in-depth for AI agent file processing |
| **GLBA 501(b)** | Information security safeguards for customer data |
| **SEC Rule 17a-3** | Record integrity for files processed by agents |

> **Important:** These downstream checks are defense-in-depth measures that complement server-side controls. No single validation layer provides complete protection. Organizations should implement all three layers and document their validation pipeline for audit evidence.
