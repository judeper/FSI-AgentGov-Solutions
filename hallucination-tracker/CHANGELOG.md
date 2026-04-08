# Changelog

All notable changes to the Hallucination Feedback Tracker.

---

## [1.0.0] - April 2026

### Added
- Dataverse schema deployment script with 1 table, 3 option sets, and `--output-docs` support
- Environment variables script (7 variables for analysis config, notifications)
- Connection references script (Dataverse + Teams)
- PowerShell governance scripts: Export-HallucinationEvidence (SHA-256), Test-EvidenceIntegrity, Get-HallucinationSummary
- Auto-generated Dataverse schema documentation

### Changed
- Graduated from v0.1.0-preview to v1.0.0 with full deployment scripts and governance automation

---

## [0.1.0-preview] - February 2026

### Added

- Initial release of Hallucination Feedback Tracker
- **Feedback Source Schema** (specification only — collection flows not yet implemented):
  - User thumbs-down reactions
  - Supervisor rejections from FSW
  - Automated verification checks
  - Customer complaints
- **Hallucination Categories:**
  - Factual error
  - Fabricated data
  - Citation missing
  - Outdated information
  - Confidence overstatement
- **Pattern Analysis:**
  - Category clustering
  - Agent-specific patterns
  - Severity distribution
- **Python Scripts:**
  - `analyze_patterns.py` - Pattern detection
- **Agent Scoring:**
  - Accuracy score calculation
  - Rating system (Excellent/Good/Needs Improvement/Critical)
- **Documentation:**
  - Prerequisites and licensing
  - Source configuration guide
  - Pattern analysis methods

### Regulatory Alignment

- FINRA 2210 - Communications accuracy
- SEC Marketing Rule - Substantiation
- CFPB Chatbot Guidance - Accuracy

---

*Hallucination Feedback Tracker v1.0.0 - FSI Agent Governance Framework*
