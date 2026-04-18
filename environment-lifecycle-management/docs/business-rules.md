# ELM Business Rules — Manual Authoring Guide

ELM ships **three** business rules that cannot be reliably created
through the Dataverse Web API in this repository. The supported way to
deploy them is to author them once in the Power Platform maker portal,
then transport them via your managed solution.

If you want a machine-readable copy of the definitions, run:

```bash
python scripts/create_business_rules.py            # human-readable
python scripts/create_business_rules.py --format json
```

## Rule 1 — ELM Zone Rationale Required

* **Entity:** `fsi_environmentrequest`
* **Scope:** Entity
* **Condition:** `fsi_zone` equals `Zone2` (100000002) **OR** `fsi_zone`
  equals `Zone3` (100000003)
* **True branch action:** Set Business Required → `fsi_zonerationale` →
  *Business Required*
* **False branch action:** Set Business Required → `fsi_zonerationale` →
  *Not Required*

## Rule 2 — ELM Security Group Required

* **Entity:** `fsi_environmentrequest`
* **Scope:** Entity
* **Condition:** `fsi_zone` equals `Zone2` (100000002) **OR** `fsi_zone`
  equals `Zone3` (100000003)
* **True branch action:** Set Business Required → `fsi_securitygroupid`
  → *Business Required*
* **False branch action:** Set Business Required → `fsi_securitygroupid`
  → *Not Required*

## Rule 3 — ELM Approval Comments Required

* **Entity:** `fsi_environmentrequest`
* **Scope:** Entity
* **Condition:** `fsi_state` equals `Rejected` (100000005)
* **True branch action:** Set Business Required → `fsi_approvalcomments`
  → *Business Required*
* **False branch action:** Set Business Required → `fsi_approvalcomments`
  → *Not Required*

## Authoring procedure

1. Sign in to https://make.powerapps.com.
2. Open **Solutions** and select the solution that contains your ELM
   tables (either the unmanaged developer solution or your shipping
   managed solution staging area).
3. Click **New** → **Automation** → **Business rule**.
4. In the picker, choose `fsi_environmentrequest`.
5. In the rule designer, set **Scope** to *Entity* (so server-side
   validation runs, not just the form-side preview).
6. Drag a **Condition** node onto the canvas and configure the
   condition exactly as documented above.
7. Connect **True** and **False** branches to **Set Business Required**
   action nodes targeting the appropriate column.
8. **Save** the rule, then **Activate** it.
9. Repeat for all three rules.

After authoring, optionally export the solution to capture the
generated WF Foundation XAML if you want to track the rules under
source control.

## Why not deploy via Web API?

* The XAML root for category=2 business rules in modern Dataverse is
  Windows Workflow Foundation
  (`<Activity xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities">`),
  not the legacy `<RuleDefinitions xmlns=".../crm/2009/WebServices">`
  format that earlier versions of `create_business_rules.py` produced.
* Workflow rows must be created in **Draft** state
  (`statecode=0`/`statuscode=1`) and then PATCHed to **Activated**.
  The previous script attempted to create them already-Activated, which
  the platform rejects.
* Reliably generating valid WF XAML programmatically is brittle. Using
  the maker portal lets the platform produce the correct XAML on save.
