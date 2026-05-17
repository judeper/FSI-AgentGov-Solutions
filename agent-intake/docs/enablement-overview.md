# Agent Intake enablement overview

Use this page to route the right person to the right document for `agent-intake` v1.0.0-preview.

The enablement set helps customers explain the intake experience, sponsor accountability, reviewer expectations, admin setup steps, and the demo story used in pilot conversations. Pair these guides with the technical source documents in this folder, especially [`classification-rules.md`](./classification-rules.md), [`flow-configuration.md`](./flow-configuration.md), [`reviewer-app-build.md`](./reviewer-app-build.md), and [`orchestrator-architecture.md`](./orchestrator-architecture.md).

## Which guide should I read?

| Doc | Audience | Length | When to read |
|---|---|---:|---|
| [`maker-guide.md`](./maker-guide.md) | Builder of an agent | ~10 min | Before filling out the intake form |
| [`sponsor-guide.md`](./sponsor-guide.md) | Business sponsor / line manager | ~7 min | When the Teams sponsor card arrives |
| [`reviewer-cheat-sheet.md`](./reviewer-cheat-sheet.md) | InfoSec, Privacy, Compliance, Legal, and MRM reviewers | ~12 min | Before joining the Standard / Full reviewer board |
| [`admin-onboarding-guide.md`](./admin-onboarding-guide.md) | Power Platform / M365 admin | ~30 min | Before the first deployment or rebuild |
| [`demo-script.md`](./demo-script.md) | Demo operator / solution architect | ~10 min prep | Before a customer architecture demo |

## Quick links by role

| I am a... | Start here | Then read |
|---|---|---|
| Maker | [`maker-guide.md`](./maker-guide.md) | [`classification-rules.md`](./classification-rules.md) |
| Sponsor | [`sponsor-guide.md`](./sponsor-guide.md) | [`maker-guide.md`](./maker-guide.md) |
| Reviewer | [`reviewer-cheat-sheet.md`](./reviewer-cheat-sheet.md) | [`reviewer-app-build.md`](./reviewer-app-build.md) |
| Customer admin | [`admin-onboarding-guide.md`](./admin-onboarding-guide.md) | [`pilot-deployment-runbook.md`](./pilot-deployment-runbook.md) |
| Demo operator | [`demo-script.md`](./demo-script.md) | [`admin-onboarding-guide.md`](./admin-onboarding-guide.md) |

## Source-of-truth references

- Routing and quorum policy: [`classification-rules.md`](./classification-rules.md)
- Locked design decisions and appeal rules: [`decisions.md`](./decisions.md)
- Maker form behavior: [`portal-configuration.md`](./portal-configuration.md) and [`maker-form-progressive-disclosure.md`](./maker-form-progressive-disclosure.md)
- Flow inventory and handoff logic: [`flow-configuration.md`](./flow-configuration.md)
- Reviewer UI and security roles: [`reviewer-app-build.md`](./reviewer-app-build.md)
- Deployment and teardown behavior: [`orchestrator-architecture.md`](./orchestrator-architecture.md) and [`pilot-deployment-runbook.md`](./pilot-deployment-runbook.md)
- Downstream handoffs: [`mrm-integration.md`](./mrm-integration.md), [`drift-detection-integration.md`](./drift-detection-integration.md), and [`identity-records-automation.md`](./identity-records-automation.md)

## Regulatory framing used across these guides

These documents use the same regulatory shorthand as the rest of the solution: FINRA Rule 3110 supervision, FINRA Rule 4511(a) books-and-records expectations, SEC Rules 17a-3(a)(17) and 17a-4(f), CFTC Rule 1.31, GLBA Section 501(b), Federal Reserve SR 11-7, OCC Bulletin 2011-12 where a firm still uses legacy model-risk language internally, and the repo's `agent-intake` decisions around current AI governance framing. The guides are intended to support compliance with those obligations when customers pair them with firm policy, configured controls, and retained evidence.
