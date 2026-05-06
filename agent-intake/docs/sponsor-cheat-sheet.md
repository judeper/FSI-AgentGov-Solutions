# Sponsor Cheat Sheet — Agent Intake (Express Path)

**Audience:** A line-of-business manager (the **sponsor**) who has received a Teams adaptive card asking you to approve a direct report's request to build a personal-scope AI agent.

**Time required:** ~2 minutes to review and click.

---

## What just landed in Teams

A direct message from the **Agent Intake** flow with an adaptive card titled "**Sponsor approval requested — [Maker name] — [Agent purpose]**".

The card contains:

1. **Maker** — name and email of your direct report
2. **Purpose** — one-sentence business outcome
3. **Audience & user count** — who will use this and how many
4. **Tier / Zone** — auto-classified as **Tier 3 / Zone 3** (lowest risk; this is what makes it Express-eligible)
5. **Trigger answers** — the six Yes/No questions, all of which the maker answered "No"
6. **Attestation language** — the supervisory statement you are agreeing to
7. **Two buttons** — **Approve** and **Decline**

---

## What you are attesting to

By clicking **Approve**, you confirm:

> "By approving, you confirm this agent's purpose, data sources, and intended users align with our supervisory expectations under FINRA Rule 3110, and that you accept ongoing supervisory accountability."

**In plain terms:**

- The maker has told you what the agent does and why
- The agent will not take financial actions, will not handle MNPI/NPI, will not face external customers, and will not exceed the maker's existing data access
- You are the appropriate supervisor for this person's work product
- You will be the named accountable supervisor on the firm's record for 7 years

---

## What you should check before clicking

| Check | What to look at | Red flag |
|---|---|---|
| **Right person** | Is the maker someone you actually supervise? | Cross-team requests — decline and ask the maker to use their actual manager |
| **Right scope** | Does the purpose match work this person is paid to do? | Personal projects, side hustles, exploratory tools outside their role |
| **Right audience** | Does the audience claim stay within personal scope for Express? | Team, department, firm-wide, or external audiences should not be Express |
| **Right answers** | Look at the six trigger answers — do they ring true based on what you know about the person's work? | If you suspect a "No" should have been "Yes", decline and ask for re-submission |

You are **not** attesting to technical safety, DLP correctness, or data-classification accuracy — those are auto-checked by the platform. You **are** attesting to business-purpose appropriateness and ongoing supervisory accountability.

---

## SLA and escalation

| Event | When |
|---|---|
| You should respond | **Within 3 business days** of card receipt |
| First reminder sent to you | Day 4 |
| Auto-escalates to your manager | Day 7 |
| Final denial ("no sponsor response") | Day 11 |

If you will be out of office, you can **delegate** by replying to the card with the email of your delegate (a planned follow-up feature; for this preview ask the maker to re-submit naming your delegate as sponsor).

---

## What "Decline" means

Declining is fine and expected when something does not look right. The maker is notified with your reason (you will be prompted for one) and can re-submit with corrections. There is no penalty to you or the maker for a decline; it is part of the supervisory conversation.

The maker may re-submit **once**. A second decline closes the request until policy or circumstances change.

---

## What happens after you Approve

1. Within 2 minutes: Microsoft Entra Agent ID is minted in your tenant
2. The agent is registered in `agent-registry-automation` linking back to you as sponsor
3. The maker is notified in Teams with their Agent ID and a link to start building in Agent Builder or Copilot Studio
4. The decision pack — including your click event, timestamp, IP address, and the rendered card — is stored immutably for 7 years per FINRA 4511 / SEC 17a-4 / CFTC 1.31

---

## Ongoing accountability

Once the agent is live, you may receive periodic notifications:

- **90-day value review** — quarterly batch; AI Governance Committee asks if the agent is still being used and producing the stated value
- **Annual sponsor re-attestation** — Teams reminder asking you to re-confirm the agent should continue
- **Drift alerts** — if the agent's actual usage exceeds the declared scope (e.g., shared more broadly than declared), you will be notified by [`unrestricted-agent-sharing-detector`](../../unrestricted-agent-sharing-detector/) and asked to review

---

## Questions?

- About this specific request: reply to the maker directly
- About your supervisory role under FINRA 3110: contact your firm's Compliance team
- About the platform itself: see the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/)
