# MIME Type Restrictions for File Uploads

> **Version:** v1.0.0

Dataverse plugin, DLP policy template, and Sentinel queries for MIME type restriction governance in Copilot Studio agent file upload scenarios.

## Overview

This solution provides enforcement and monitoring artifacts for restricting file upload MIME types in Copilot Studio agents. It includes a Dataverse plugin for server-side validation, a DLP policy template for policy-based enforcement, and KQL queries for Sentinel-based monitoring and exception tracking.

> **Note:** The PowerShell module (`FsiMimeControl`) remains in FSI-AgentGov under `scripts/governance/`.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.25 - MIME Type Restrictions](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.25-mime-type-restrictions-for-file-uploads/) | Primary — File upload type enforcement |
| [1.5 - DLP and Sensitivity Labels](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels/) | DLP policy integration |

## Components

```
mime-type-restrictions/
├── README.md
├── CHANGELOG.md
└── src/
    ├── ValidateMimeTypePlugin.cs     # Dataverse plugin for server-side MIME validation
    ├── dlp-policy-template.json      # DLP policy template for MIME restrictions
    ├── MimeConfig.json               # MIME type allowlist/blocklist configuration
    ├── query-mime-blocks.kql          # Sentinel query for blocked MIME type events
    ├── high-volume-blocks.json       # Sentinel alert for high-volume block patterns
    └── query-exception-usage.kql     # Sentinel query for exception usage tracking
```

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Microsoft Sentinel workspace (for KQL queries)
- Dataverse System Administrator permissions (for plugin registration)

## Deployment

See the control implementation playbooks for [Control 1.25](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.25-mime-type-restrictions-for-file-uploads/) in FSI-AgentGov.

## License

MIT License — see [LICENSE](../LICENSE)
