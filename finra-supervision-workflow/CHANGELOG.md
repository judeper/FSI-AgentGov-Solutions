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
- ~~FINRA 3120 report generator (`generate_3120_report.py`)~~ — Planned for a future release (see README)
- Power BI dashboard setup guide (template planned for future release)
- Integration with Communication Compliance API
- Documentation suite (prerequisites, schema, flows, troubleshooting)

### Regulatory Alignment

- FINRA Rule 3110 supervision routing
- FINRA Rule 3120 testing evidence
- FINRA Notice 24-09 AI communication supervision
- SEC 17a-3/4 recordkeeping

### Known Limitations

- Communication Compliance polling (not real-time webhook)
- Manual Power BI deployment required
- Zone/tier configuration via model-driven app only
