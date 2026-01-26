# Solution Source (Optional)

This folder is reserved for unpacked Power Platform solution files if you choose to use a solution package approach.

## v2.0.0 Changes

In v2.0.0, the solution was simplified from a packaged deployment to a manual setup approach:

- **No pre-built solution package** - Create the Dataverse table and Power Automate flow manually
- **Single table** - Only `MessageCenterLog` (no AssessmentLog or DecisionLog)
- **No custom security roles** - Use standard Dataverse permissions
- **No Business Process Flow** - Simple status field instead

## If You Want a Solution Package

You can create your own solution package after setting up the components:

1. Create the Dataverse table and flow following the guides
2. Add components to a solution in Power Apps
3. Export as unmanaged solution
4. Unpack for version control:

```bash
pac solution unpack \
  --zipfile ./MessageCenterMonitor_2_0_0.zip \
  --folder ./MessageCenterMonitor \
  --processCanvasApps
```

## Expected Structure (If Packaged)

```
MessageCenterMonitor/
├── solution.xml              # Solution manifest
├── Entities/                 # Table definitions
│   └── mcm_messagecenterlog/
└── Other/                    # Additional components
```

## Why Manual Setup?

The v2.0.0 simplification prioritizes:

- **Transparency** - See exactly what you're creating
- **Flexibility** - Easy to customize during setup
- **Lower barrier** - No solution import complexities
- **Maintainability** - Simpler components to troubleshoot
