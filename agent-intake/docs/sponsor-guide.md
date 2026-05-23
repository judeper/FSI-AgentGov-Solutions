# Sponsor guide — agent-intake

**Audience:** Line managers, directors, and other business sponsors who receive the Express approval card in Microsoft Teams.

**Best time to read:** When a maker asks you to sponsor a request, or when the Teams card arrives.

This guide explains what the sponsor decision means, what you should check before you approve, and what evidence the solution records. For the maker-facing view, see [`maker-guide.md`](./maker-guide.md). For the detailed approval logic, see [`classification-rules.md`](./classification-rules.md) and [`decisions.md`](./decisions.md).

## 1. What being a sponsor means

In `agent-intake`, the sponsor is the accountable business supervisor for the request.

When you approve an Express-path request, you are not promising that the agent is perfect. You are confirming that, based on what is in front of you:

- the stated business purpose is legitimate and tied to the maker's role
- the requested scope looks reasonable for the maker and audience described
- you accept supervisory accountability for the request under your firm's control framework
- you understand the approval becomes part of the retained supervisory record

That is why the sponsor card uses FINRA Rule 3110 attestation language and why the decision is retained as evidence that supports books-and-records expectations under FINRA Rule 4511(a), SEC Rule 17a-4(f), SEC Rule 17a-3(a)(17), and CFTC Rule 1.31. In many firms, the same record also supports the AI-governance expectations they map to FINRA 25-07.

If the request is not truly low-risk, your job is to stop the Express path and send it back for correction or richer review.

## 2. The Teams card you'll receive

The sponsor card is defined in [`../templates/sponsor-approval-card.json`](../templates/sponsor-approval-card.json). In plain English, it contains:

| Card area | What you will see | Why it matters |
|---|---|---|
| **Title** | “Agent intake sponsor approval” | Confirms this is an intake decision, not a general FYI message |
| **Summary text** | A short sentence telling you this is an Express-path request | Reminds you that this is the lowest-risk path only |
| **Request facts** | Request ID, agent name, maker, audience, submitted time, and tier/zone | Lets you confirm the request identity quickly |
| **Business justification** | The maker's short statement of purpose | This is usually the fastest way to tell whether the request is sensible |
| **Sponsor attestation** | The approval wording you are accepting | This is the supervisory statement retained with your decision |
| **Notes box** | Optional decision notes | Use this when you want a short audit note or reason for denial |
| **Buttons** | **Approve** or **Deny** | Express is intentionally binary |

### Wireframe by words

When the card opens, you should be able to answer these questions in under a minute:

1. Who is asking?
2. What is the agent for?
3. Is the stated audience really personal scope?
4. Does the Tier / Zone summary still look like a low-risk case?
5. Do I accept accountability for this request if it goes live?

If the answer to any of those is “no” or “not yet,” deny and ask the maker to correct the request.

## 3. What to check before approving

Use this quick checklist.

| Check | What good looks like | Escalate or deny when... |
|---|---|---|
| **Business purpose** | The justification is clear, work-related, and proportional | The maker cannot explain what the agent is actually for |
| **Audience** | The request really starts with the maker alone | The maker already plans to share with a team, department, firm-wide audience, or external users |
| **Data fit** | The sources described match what the maker needs | The maker appears to need customer data, MNPI, or another higher-risk source that was not declared |
| **Training and readiness** | The maker understands the use case and your firm's acceptable-use expectations | The maker appears unprepared or says they will work out the controls later |
| **Supervisory relationship** | You are the right person to approve the work | You do not supervise the maker or the request belongs in another chain |
| **Truthfulness of trigger answers** | The low-risk answers ring true based on the role and use case | A “No” answer looks inconsistent with what you know about the work |

### A useful sponsor rule of thumb

If you find yourself wanting to write a long list of conditions, the request probably does **not** belong on Express.

## 4. Approve / Approve with conditions / Deny

### Express uses only Approve or Deny

The shipped Express sponsor card is approve-or-deny only.

- **Approve** when the request is a genuine low-risk personal use case and the maker's description is complete enough for you to stand behind it.
- **Deny** when the purpose, audience, sponsor relationship, or declared data use is wrong, incomplete, or routed too low.

### Where “Approve with conditions” belongs

Conditions are part of the **Standard** and **Full** reviewer workflow, not the Express sponsor card. Reviewer cards capture conditions in `fsi_conditionstext`; the reviewer operating model is described in [`reviewer-cheat-sheet.md`](./reviewer-cheat-sheet.md).

If you want to say “yes, but only if...,” the practical sponsor action is usually one of these:

1. **Deny and ask for a corrected resubmission** if the maker can fix the issue quickly.
2. **Deny and ask for richer review** if the request should be Standard or Full instead of Express.
3. **Escalate to governance or Compliance** if the use case looks novel, customer-facing, or recordkeeping-sensitive.

## 5. Self-approval is blocked

A maker cannot approve their own request. The portal blocks it, and the classifier checks it again in the routing layer.

Why this matters:

- it preserves separation of duties
- it keeps supervisory evidence defensible
- it avoids a path where low-risk requests bypass human review entirely

See [ADR-008 in `decisions.md`](./decisions.md#adr-008--sponsor-cannot-self-approve) and the seeded deny example in `request-sponsor-self-approval-deny.json` referenced by the deployment docs.

## 6. If the maker appeals a denial

The appeal flow is designed for honest corrections, not approval shopping.

Your role in an appeal is simple:

- review what changed
- decide whether the corrected request now belongs on Express, or whether it still needs a richer path
- keep the same standard you used the first time

The appeal mechanism creates a **new request** while preserving the link to the original denial. The logic is documented in [`flow-configuration.md`](./flow-configuration.md#flow-11-fsi-intake-denial-appeal) and [ADR-010 in `decisions.md`](./decisions.md#adr-010--denial-appeal-one-re-submission-allowed).

A good appeal usually includes one of these changes:

- new sponsor
- corrected audience or trigger answer
- clearer business justification
- missing privacy or data-source detail

If none of those changed, a second denial is usually the right call.

## 7. Sponsor backup designation

The sponsor-timeout and escalation path uses the solution environment variable `fsi_intake_sponsorbackupgroup`.

What that means in practice:

- your admin can point the flow to a Microsoft 365 group, distribution list, or named backup approver set
- the backup group is used when a sponsor response times out or a manager lookup is missing
- it helps your firm keep approvals moving during PTO, manager changes, and reorganizations

If you are a frequent sponsor, tell the admin who should cover for you before go-live. The admin-side setup steps are in [`admin-onboarding-guide.md`](./admin-onboarding-guide.md) and [`flow-build-prerequisites.md`](./flow-build-prerequisites.md).

## 8. Audit trail

Here is what the solution records when you decide:

- your UPN and sponsor role
- the decision outcome and timestamp
- any optional notes you entered
- the rendered card hash used as evidence context
- the linked sponsorship record and decision pack
- the retention label state used for the final evidence package

That evidence is written across `fsi_intakeapproval`, `fsi_intakesponsorship`, `fsi_intakeauditevent`, and the immutable `fsi_intakedecisionlog` record described in [`flow-configuration.md`](./flow-configuration.md#flow-8-fsi-intake-decision-pack-writer).

Two practical notes for sponsors:

1. The point of the audit trail is to preserve **who approved what, when, and under what wording**.
2. The default Teams pattern does **not** rely on a durable client IP field, so the strongest evidence is your identity, the timestamp, the card content, and the linked request context.

That record supports internal audit, governance review, and regulator-facing reconstruction if your firm later needs to explain the approval basis.

## Quick sponsor decision rule

Use this shortcut if you are pressed for time:

- **Approve** only when the request is clearly personal-scope, clearly business-related, and clearly low-risk.
- **Deny** when the request needs corrections or richer review.
- **Escalate** when the request may involve customer interaction, regulated communications, NPI, MNPI, cross-border handling, or a scope larger than the maker is claiming.

That keeps the Express path fast for the right use cases and pushes the harder cases into the reviewer workflow where they belong.
