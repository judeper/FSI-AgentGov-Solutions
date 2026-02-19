# Changelog

All notable changes to the FINRA Supervision Workflow solution are documented here.

## [1.0.0] - February 2026

### Added

- Initial release
- SupervisionQueue table with 17 columns
- SupervisionLog table for immutable audit trail
- SupervisionConfig table for zone/tier-based rules
- Four security roles (Supervisor, Queue Manager, Admin, Auditor)
- Deployment script (`deploy.py`)
- Evidence export script (`export_supervision_evidence.py`)
- Power BI dashboard setup guide (manual build; no `.pbix` template included)
- Integration with Communication Compliance API
- Documentation suite (prerequisites, schema, flows, troubleshooting)

### Regulatory Alignment

- FINRA Rule 3110 supervision routing
- FINRA Rule 3120 testing evidence
- FINRA Notice 24-09 AI communication supervision
- SEC 17a-3/4 recordkeeping

### Known Limitations

- Communication Compliance polling (not real-time webhook)
- Manual Power BI deployment required (no `.pbix` template included)
- Zone/tier configuration via model-driven app only

### Planned

- FINRA 3120 report generator (not yet included)
