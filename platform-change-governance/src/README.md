# Solution Source (Unpacked XML)

This folder contains the unpacked Power Platform solution for version control.

## Contents

After unpacking, this folder will contain:

```
MessageCenterGovernance/
├── solution.xml              # Solution manifest
├── Entities/                 # Table definitions
│   ├── mcg_messagecenterpost/
│   ├── mcg_assessmentlog/
│   └── mcg_decisionlog/
├── Roles/                    # Security role definitions
├── Workflows/                # Business Process Flow
├── EnvironmentVariables/     # MCG_TenantId, MCG_PollingInterval
└── Other/                    # App, sitemap, etc.
```

## How to Unpack

```bash
pac solution unpack \
  --zipfile ../MessageCenterGovernance_1_0_0_0.zip \
  --folder ./MessageCenterGovernance \
  --processCanvasApps
```

## How to Repack

After making changes to the XML:

```bash
pac solution pack \
  --folder ./MessageCenterGovernance \
  --zipfile ../MessageCenterGovernance_1_0_0_1.zip
```

## Why Unpacked?

- **Version control:** See meaningful diffs when components change
- **Customization:** Edit XML directly for bulk changes
- **Automation:** Build pipelines can pack/unpack automatically
