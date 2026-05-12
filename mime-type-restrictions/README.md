---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P2, P3]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# MIME Type Restrictions for File Uploads

> **Version:** v1.2.1
> **Status:** Completed

Dataverse plugin, connector-classification reference, and Sentinel queries for MIME type restriction governance in Copilot Studio agent file upload scenarios.

## Overview

This solution provides enforcement and monitoring artifacts for restricting file upload MIME types in Copilot Studio agents. It includes a Dataverse plugin for server-side validation, a connector-classification reference for Power Platform data policies, and KQL queries for Sentinel-based monitoring and exception tracking.

> **Note:** The PowerShell module (`FsiMimeControl`) remains in FSI-AgentGov under `scripts/governance/`.

## PowerShell Module (Optional)

The **FsiMimeControl** PowerShell module provides bulk configuration management, deployment validation, and zone template support. It is maintained separately in the FSI-AgentGov repository.

**Location:** `FSI-AgentGov/scripts/governance/FsiMimeControl.psm1`

**Installation:**
```powershell
Import-Module .\FsiMimeControl.psm1
```

**Zone Templates:** Pre-configured MIME allowlists are available for Zone 1, 2, and 3 under `scripts/governance/mime-templates/`.

This module is optional — the core solution operates independently without it. See [Flow Configuration](docs/flow-configuration.md) for details.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.25 - MIME Type Restrictions](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.25-mime-type-restrictions-for-file-uploads/) | Primary — File upload type enforcement |
| [1.5 - DLP and Sensitivity Labels](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels/) | Defence-in-depth: connector classification informed by the DLP reference template |
| [1.13 - File and Attachment Controls](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.13-file-and-attachment-controls/) | Server-side validation of file attachment types |
| [3.3 - Compliance Reporting and Attestation](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-monitoring/3.3-compliance-reporting-and-attestation/) | Blocked-upload reporting for compliance evidence |
| [3.7 - Monitoring](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-monitoring/3.7-monitoring/) | Continuous upload monitoring and alerting |

## Documentation

| Document | Description |
|----------|-------------|
| [Flow Configuration](docs/flow-configuration.md) | Solution architecture and configuration guide |
| [Build Instructions](docs/build-instructions.md) | Legacy Visual Studio walkthrough for the plugin DLL |
| [Build and Sign](docs/build-and-sign.md) | dotnet CLI build, cosign Sigstore signing, and DLL verification |
| [Delivery Checklist](docs/delivery-checklist.md) | Pre-deployment verification checklist |

## Enterprise Managed Default Allowlist (Zone 3)

The default `mime-config.json` for Zone 3 includes:

| MIME Type | Status | Rationale |
|-----------|--------|-----------|
| `application/pdf` | ✅ Allowed | Standard business document format |
| `image/png` | ✅ Allowed | Common image format, no embedded code risk |
| `image/jpeg` | ✅ Allowed | Common image format, no embedded code risk |
| `image/gif` | ✅ Allowed (non-animated) | Non-animated GIF is low risk; animated GIF flagged for review |
| `image/webp` | ✅ Allowed | Validated with offset-8 WEBP signature check to prevent RIFF collision |
| `image/tiff` | ❌ Removed | TIFF supports multi-page documents and complex metadata (EXIF, IPTC, XMP) that can carry malicious payloads; not a supported Copilot Studio user file input type; uncommon for AI agent input |
| `text/plain` | ✅ Allowed | Binary content absence check |
| `text/csv` | ✅ Allowed | Binary content absence check |
| OpenXML (docx/xlsx/pptx) | ✅ Allowed | PK header + `[Content_Types].xml` + subtype directory validation |

### TIFF Removal Rationale

TIFF was removed from the Enterprise Managed default allowlist based on:

1. **Copilot Studio support matrix:** TIFF is not listed as a supported user file input type in Copilot Studio
2. **Security posture:** TIFF supports multi-page documents, embedded scripts via EXIF/IPTC metadata, and complex IFD structures that have been historically exploited (CVE-2020-1599, CVE-2017-0263)
3. **Business need:** TIFF is uncommon for AI agent input scenarios; organizations that require TIFF should add it to their zone-specific allowlist with explicit risk acceptance

### Animated GIF Policy

Non-animated GIF is retained in the allowlist. Animated GIFs (identifiable by the `NETSCAPE2.0` application extension block) are flagged for review because:

1. Animated GIFs can be used for visual prompt injection via embedded text frames
2. Multi-frame animation adds processing overhead and unpredictable behavior in AI responses
3. Copilot Studio supports non-animated GIF for user file input but does not process animation

Organizations can configure the `animatedGifPolicy` field in `mime-config.json` to `"block"`, `"flag-for-review"`, or `"allow"` based on their risk tolerance.

> **Migration note:** If upgrading from a prior version where TIFF was in the allowlist, review your zone configuration. Existing TIFF files in Dataverse are not affected. The change only applies to new uploads validated by the plugin after configuration update.

## Components

```
mime-type-restrictions/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── flow-configuration.md         # Solution architecture and configuration guide
│   ├── build-instructions.md         # Legacy Visual Studio walkthrough for the plugin DLL
│   ├── build-and-sign.md             # dotnet build, cosign signing, and verification
│   └── delivery-checklist.md         # Pre-deployment verification checklist
├── src/
│   ├── ValidateMimeTypePlugin.cs     # Dataverse plugin for server-side MIME validation
│   └── ValidateMimeTypePlugin.csproj # SDK-style csproj (net462)
├── scripts/
│   ├── query-mime-blocks.kql         # Sentinel query for blocked MIME type events
│   └── query-exception-usage.kql    # Sentinel query for exception usage tracking
└── templates/
    ├── dlp-policy-template.json      # Connector-classification reference (not importable DLP JSON)
    ├── mime-config.json              # MIME type allowlist/blocklist configuration
    └── high-volume-blocks.json       # Sentinel alert for high-volume block patterns
```

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Microsoft Sentinel workspace (for KQL queries)
- Dataverse System Administrator permissions (for plugin registration)

## Deployment

1. Register the Dataverse plugin using the Plugin Registration Tool
2. Translate the DLP reference into Power Platform data policy connector classifications; do not import the reference JSON directly
3. Configure `templates/mime-config.json` with your organization's allowed/blocked MIME types
4. Deploy Sentinel queries to your Log Analytics workspace
5. Verify deployment using the control implementation playbooks for [Control 1.25](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.25-mime-type-restrictions-for-file-uploads/) in FSI-AgentGov

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Plugin not triggering | Plugin not registered or registration step inactive | Re-register plugin in Dataverse Plugin Registration Tool; verify step is active |
| Allowed MIME type blocked | `MimeConfig.json` allowlist missing the type | Add the MIME type to the allowlist and redeploy configuration |
| Sentinel queries return empty | Diagnostic logs not flowing to workspace | Verify Dataverse audit logging is enabled and connected to Sentinel |
| Data policy not limiting risky upload paths | Connector remains in an allowed data group or policy hasn't propagated | Move risky upload-capable connectors to Blocked or Non-business as required; allow up to 24 hours for policy propagation |

### Logs

Review Dataverse plugin trace logs for errors. For Sentinel queries, check the `PowerPlatformDlpActivity_CL` custom log table.

## License

MIT License — see [LICENSE](../LICENSE)
