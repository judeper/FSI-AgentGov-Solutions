# Maker Quick Start — Agent Intake (Express Path)

**Audience:** A business user (the **maker**) who wants to build a low-risk personal or team-scope AI agent in Microsoft Agent Builder or Copilot Studio.

**Time required:** ~3 minutes to submit. Sponsor approval typically within 3 business days.

---

## What is the Express path?

Express is the fast lane for the lowest-risk agents — those that:

- Are for **you or your team** (not customer-facing, not external)
- Use **only data you already have access to** (no NPI, no MNPI, no restricted records)
- Take **no autonomous financial actions** (no payments, no order entry, no irreversible external calls)
- Are **not subject to enhanced regulatory routing** (e.g., not OCC/FINRA/SEC supervised activity flow)

If any of those is not true, the form will tell you and save your draft for the Standard or Full path (available in v0.2 and v0.3).

---

## What you fill in (the 10 questions)

### Trigger questions (Yes / No / Not sure)

The first six questions determine whether you are eligible for Express. Answer honestly — "Not sure" routes you to the full intake (and that is the right answer when you are not sure).

| # | Question |
|---|---|
| **T1** | Will this agent take any financial action automatically (e.g., place an order, transfer funds, modify a customer record)? |
| **T2** | Will this agent process MNPI (material non-public information) or NPI (customer non-public personal information under GLBA)? |
| **T3** | Is this agent regulated as a supervised activity (broker-dealer recommendation, advisory, lending, claims)? |
| **T4** | Will this agent interact with external customers, counterparties, or regulators? |
| **T5** | Will this agent use a connector or data source you do not currently have personal access to? |
| **T6** | Is the data this agent uses subject to a residency requirement that differs from where you (the maker) work? |

### Descriptive questions

| # | Question | What you enter |
|---|---|---|
| **BJ-001** | Business outcome | Pick one from the dropdown (e.g., "Reduce time spent on weekly status reports") |
| **BJ-002** | Expected user count | Estimate — e.g., "5 (my team)" |
| **MR-001** | Sponsor | Your direct manager's email (auto-populated from Microsoft Graph) — confirm or override |
| **MR-002** | Free-text justification | Optional. One paragraph if the dropdown does not capture your case. |

---

## What happens after you click Submit

```
You ──► Form ──► Auto-classify ──► Sponsor card ──► (1-click) ──► Agent ID minted ──► You can build
                       │
                       └──► If any trigger = Yes/Not sure: saved as draft, full intake required
```

| Step | What happens | Who does it | Timing |
|---|---|---|---|
| 1 | Form submits | You | Instant |
| 2 | Auto-classifier checks T1–T6 + computes tier/zone | System | <5 sec |
| 3 | If Express-eligible: Teams adaptive card sent to your sponsor | System | <30 sec |
| 4 | Sponsor reviews and clicks "Approve" with FINRA 3110 attestation | Your manager | Up to 3 business days |
| 5 | System mints your Microsoft Entra Agent ID and registers the agent | System | <2 min |
| 6 | You receive a Teams notification with your Agent ID and links to start building | System | Same as step 5 |

If the sponsor does not respond in 3 business days, the request escalates to **their** manager. If still no response after a further 4 business days, the request is denied with reason "no sponsor response" and you can re-submit with a different sponsor.

---

## What you can do once approved

- Build your agent in **Agent Builder** or **Copilot Studio**
- Use connectors that are allowed by your environment's DLP policy (the form already simulated this — anything that would have failed was flagged at submission)
- Share your agent with the users you declared in BJ-002 (sharing beyond that count triggers a re-review via [`unrestricted-agent-sharing-detector`](../../unrestricted-agent-sharing-detector/))

## What stays on the record

Your sponsor's attestation, the trigger answers you gave, and the timestamp are recorded immutably for **7 years** (FINRA 4511, SEC 17a-4, CFTC 1.31). You cannot edit them after submission. If your agent's purpose changes materially (e.g., a new trigger answer would now be Yes), submit a new intake — do not silently expand scope.

## Help

- Form not loading: [link to your portal admin contact]
- Sponsor unsure how to approve: send them [`sponsor-cheat-sheet.md`](sponsor-cheat-sheet.md)
- You need the full intake (Standard / Full path): [link to v0.2/v0.3 process when available]
- General governance questions: see the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/)
