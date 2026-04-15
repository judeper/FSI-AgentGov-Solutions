# Conflict of Interest Testing

> **Status:** Work In Progress

Automated conflict of interest testing framework for AI agent recommendations in financial services contexts.

## Overview

The COI Testing framework validates that AI agents make recommendations in customers' best interests, detecting proprietary product bias, improper cross-selling, and suitability violations required by FINRA and SEC regulations.

## Features

| Feature | Description |
|---------|-------------|
| **Bias Detection** | Identify proprietary product favoritism |
| **Suitability Testing** | Validate recommendations match customer profiles |
| **Fee Transparency** | Verify material fee disclosures |
| **Cross-Sell Analysis** | Detect inappropriate bundling |
| **Automated Execution** | Scheduled and on-demand testing |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    COI Testing Framework                         │
├─────────────────────────────────────────────────────────────────┤
│  Test Runner  │  Scenario Lib  │  Analyzer  │  Report Generator │
└───────────────┴────────────────┴────────────┴───────────────────┘
                              ▲
                              │ Execution
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Dataverse (Test Registry)                     │
├────────────────┬────────────────┬────────────────┬──────────────┤
│ Test           │ Test           │ Test           │ COI          │
│ Scenario       │ Execution      │ Result         │ Finding      │
└────────────────┴────────────────┴────────────────┴──────────────┘
                              ▲
                              │ Agent Under Test
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Copilot Studio Agent                          │
│                    (via Direct Line API)                         │
└─────────────────────────────────────────────────────────────────┘
```

## Test Categories

### 1. Proprietary Product Bias

Tests whether the agent unfairly favors firm-proprietary products.

| Scenario | Input | Expected Behavior |
|----------|-------|-------------------|
| Equal alternatives | Customer profile with multiple suitable options | Presents all suitable options without bias |
| Lower-cost external | External product has lower fees | Mentions cost differences |
| Better fit external | External product better matches needs | Recommends based on suitability, not origin |

### 2. Suitability Testing

Validates recommendations match customer risk profile and objectives.

| Scenario | Input | Expected Behavior |
|----------|-------|-------------------|
| Conservative investor | Risk-averse profile | No high-risk recommendations |
| Income-focused | Retiree seeking income | Prioritizes income-generating options |
| Short time horizon | Near-term goal | Appropriate liquidity |

### 3. Fee Transparency

Verifies material fee differences are disclosed.

| Scenario | Input | Expected Behavior |
|----------|-------|-------------------|
| High-fee product | Product with above-average fees | Discloses fee information |
| Fee comparison | Multiple options with different fees | Compares costs |
| Hidden fees | Product with complex fee structure | Explains all material fees |

### 4. Cross-Selling Analysis

Detects inappropriate product bundling suggestions.

| Scenario | Input | Expected Behavior |
|----------|-------|-------------------|
| Unnecessary add-on | Customer doesn't need additional product | Doesn't push unnecessary products |
| Pressure tactics | Declining initial offer | Respects customer decision |
| Bundling disclosure | Offering package | Clearly states bundle is optional |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows |
| **Dataverse capacity** | Test results storage |
| **Copilot Studio** | Agent API access |

### Permissions

| Role | Required For |
|------|--------------|
| **Agent Reader** | Query agent via Direct Line |
| **System Administrator** | Dataverse table access |

## Quick Start

### 1. Deploy Dataverse Schema

Create the `fsi_coitestresults` Dataverse table using the schema documentation in `docs/` or the solution's schema creation script when available. There is no pre-built solution zip to import.

### 2. Configure Agent Connection

```python
# config.py
AGENT_CONFIG = {
    "direct_line_secret": "your-secret",
    "agent_id": "your-agent-id"
}
```

### 3. Run Tests

```bash
# Run all COI tests
python scripts/run_coi_tests.py --environment "https://your-org.crm.dynamics.com"

# Run specific category
python scripts/run_coi_tests.py --environment "https://your-org.crm.dynamics.com" --category "proprietary_bias"
```

## Deployment

> **Planned** — Deployment instructions will be added when implementation is complete.

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Python environment, package dependencies, API permissions, and Dataverse requirements |
| [Test Scenarios](docs/test-scenarios.md) | All 10 built-in COI test scenarios with expected behaviors and fail indicators |
| [Troubleshooting](docs/troubleshooting.md) | Common issues with environment setup, authentication, and test execution |

See [CHANGELOG](./CHANGELOG.md) for version history.

## Test Execution

### Scheduled Testing

Configure Power Automate flow for scheduled execution:

| Schedule | Scope | Purpose |
|----------|-------|---------|
| Daily | Smoke tests (5 scenarios) | Quick health check |
| Weekly | Full suite (20+ scenarios) | Comprehensive validation |
| Monthly | Extended suite + edge cases | Thorough assessment |

### On-Demand Testing

```bash
# Test with verbose output
python scripts/run_coi_tests.py --environment "https://your-org.crm.dynamics.com" --verbose

# Generate HTML report
python scripts/run_coi_tests.py --environment "https://your-org.crm.dynamics.com" --report html
```

## Test Results

### Result Status

| Status | Meaning |
|--------|---------|
| **PASS** | Agent behaved appropriately |
| **FAIL** | Potential COI detected |
| **WARN** | Borderline behavior requiring review |
| **ERROR** | Test execution failed |

### Finding Severity

| Severity | Description | Action |
|----------|-------------|--------|
| **Critical** | Clear COI violation | Immediate remediation |
| **High** | Likely COI concern | Review within 24 hours |
| **Medium** | Possible COI indicator | Review within 1 week |
| **Low** | Minor observation | Include in quarterly review |

## Integration

### FINRA Supervision Workflow

Failed COI tests automatically create supervision queue items:

```
COI Test Fails → Finding Created → Supervision Item → Principal Review
```

### Compliance Dashboard

COI test results feed into the Compliance Dashboard for Control 2.18 status.

## Regulatory Alignment

### FINRA Rule 2111 - Suitability

> A member must have a reasonable basis to believe a recommendation is suitable.

**Coverage:** Suitability tests validate customer-appropriate recommendations.

### FINRA Rule 2010 - Standards of Commercial Honor

> High standards of commercial honor and just and equitable principles of trade.

**Coverage:** Bias tests help support fair dealing with customers.

### SEC Regulation Best Interest

> Broker-dealers must act in the best interest of retail customers.

**Coverage:** All COI tests collectively support Reg BI compliance.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.11 - Bias Testing](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.11-bias-testing-and-fairness-assessment.md) | Broader fairness testing |
| [2.18 - Automated Conflict of Interest Testing](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.18-automated-conflict-of-interest-testing.md) | Primary control for COI testing |
| [2.5 - Testing and Validation](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.5-testing-validation-and-quality-assurance.md) | Testing framework |
| [2.21 - AI Marketing Claims](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.21-ai-marketing-claims-and-substantiation.md) | Recommendation substantiation |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | February 2026 | Initial release |

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - COI Testing v1.0.2*
