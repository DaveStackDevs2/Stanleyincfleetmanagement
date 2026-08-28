# Stanley Fleet Management — Operational Punchlist & AI Handoff

**Prepared:** August 28, 2026  
**Owner / Product Lead:** Dave  
**Repository:** `DaveStackDevs2/Stanleyincfleetmanagement`  
**Production:** `https://stanleyincfleetmanagement.vercel.app`  
**Supabase project:** `ycwejunodgnnkickjvsk`

---

# 1. READ THIS FIRST — HOW THE NEXT AI MUST OPERATE

Dave is the operational expert and product owner. The AI is the lead engineer, not the person who invents dealership workflow.

## Mandatory working rules

- **Do not guess dealership workflow.**
- If Dave has not explained a rule, ask him before implementing it.
- Do not turn a suggestion into a “policy” unless Dave approves it.
- Do not restate Dave's own policy back to him as if it were a new AI idea.
- Stay on the current task. Do not drift into Dashboard, reporting, QR codes, Fleet Board cleanup, or other unrelated sections.
- GitHub remote `main` is source of truth.
- Verify actual remote commit / PR / diff before trusting a local or Codex summary.
- Vercel READY does not prove Supabase/backend correctness.
- Before any Supabase migration that changes authoritative functions/views:
  1. inspect live definitions/signatures/grants;
  2. compare proposed SQL to live state;
  3. run rollback preflight using exact merged-main SQL;
  4. deploy only after merge;
  5. verify live behavior, grants, RLS/security-invoker, and rollback cleanliness.
- Do not create real or synthetic operational records merely to make a screen testable unless Dave explicitly agrees.
- When Dave says the workflow is not right, fix the workflow before moving on.

## Current scope lock

**Finish Billing workflow → define OnTrac/plate rules with Dave → finish authoritative plate tracking → finish OnTrac import/review → finish Fleet Administration → wire vehicle eligibility → import real fleet → begin real operational testing.**

Do **not** jump ahead.

---

# 2. CURRENT DEPLOYMENT STATE

## GitHub

Latest merged PR:
- **PR #74 — Normalize Rental Billing typography and warning money**
- Merge SHA: **`8fd0c112f9990b4d0764442f355059cc0da2b3cb`**
- Frontend-only.

Production Vercel is READY on that exact merge SHA.

## Recent Billing PR sequence

- **#70 — Finish Rental Billing staff workflow**
  - manual Billing Start adjustment;
  - Current Charges reconciliation;
  - zero-dollar Extension handling;
  - date presentation cleanup.
- **#71 — Add Rental payment progress workflow**
  - case-level Rental payment ledger;
  - amount-driven payment preview;
  - Paid-Through-driven payment preview;
  - partial-payment allocation;
  - payment history;
  - SO#/RO# reference warning workflow;
  - normal future scheduled-return payment targeting;
  - overdue payment targeting through current elapsed billing period.
- **#72 — Tighten Rental Billing rows and close payment preview**
  - denser Billing rows;
  - `Close Preview`;
  - no backend changes.
- **#73 — Increase Rental Billing date and charge readability**
  - larger operational typography.
- **#74 — Normalize Rental Billing typography and warning money**
  - Warning Center `$396.0000` display fixed to `$396.00`;
  - operational dates/times/days/money normalized to larger typography;
  - frontend only.

---

# 3. BILLING — LOCKED BUSINESS RULES

These are settled. Do not reopen them unless Dave explicitly changes them.

## Reservation and pickup times

A Rental has separate facts:

1. **Reserved Start**
   - the customer's scheduled reservation start;
   - preserved unless staff deliberately edits the Reservation.

2. **Expected Return**
   - preserved independently;
   - being late to pickup does **not** move the return time;
   - the vehicle may already be promised to another customer afterward.

3. **Actual Pickup**
   - the actual physical handoff time;
   - operational fact only;
   - does not automatically change Billing Start or Expected Return.

4. **Billing Start**
   - defaults to Reserved Start;
   - may be manually changed by staff as an exception;
   - changing Billing Start must not change Reserved Start, Actual Pickup, or Expected Return.

**Nothing changes automatically because a customer arrives late.**

## Overdue vs Extension

- Overdue time is **not an Extension**.
- The UI must say **OVERDUE — NOT EXTENDED** until a real Extension is deliberately created.
- Paying overdue charges does not extend the Reservation.
- Only a customer/staff-approved return-time change creates an Extension.

## Rental payment behavior

- A normal Rental would generally be paid before leaving, but **do not hard-block an unpaid Rental from leaving**.
- There are legitimate paperwork situations where something is classified as Rental even if normal retail-rental payment behavior does not apply.

## Partial payments

Rental payment must work in both directions.

### Staff enters amount paid

System calculates:
- Paid Through;
- Days Paid;
- Days Still Due;
- Remaining Amount;
- partial amount credited toward next unpaid billable day, if applicable.

### Staff chooses Paid Through

System calculates:
- exact payment amount required to reach that point.

### Allocation

- payments apply **oldest unpaid charges first**;
- Paid Through advances only through **complete billable days/periods fully covered**;
- if money only partially covers the next charged day, that day remains due;
- the partial amount reduces Amount Owed;
- `Paid Through` is the correct wording. Do **not** change it to “Fully Paid Through.”

## SO#/RO# payment proof

- SO# default.
- Staff can use SO# or RO#.
- A payment may be recorded without a reference.
- Missing reference creates a warning.
- Adding the reference later clears the warning automatically.
- Viewing/acknowledging the warning does not clear it.

## Zero-dollar Billing periods

- A $0 period is shown as **NO CHARGE**.
- No payment button.
- No SO#/RO# requirement.
- No unpaid-warning requirement.

---

# 4. BILLING — WHAT IS FINISHED

## Rental screen

The current Rental detail screen now visibly shows:
- Reserved Start;
- Billing Start;
- Actual Pickup;
- Expected Return;
- Status;
- Total Days;
- Days Paid;
- Paid Through;
- Days Owed;
- Amount Owed;
- Current Charges;
- Original Rental;
- actual Extensions;
- payment workflow;
- payment history;
- Extend Rental;
- Return / Complete.

## Current Charges

Current Charges now separates:
- locked historical charge(s);
- live Current Billing Period;
- Pre-tax;
- Tax;
- Grand Total.

The phrase **Current Extension** was removed because overdue billing is not an Extension.

## Browser typography

The current screen uses larger operational text for:
- timeline dates/times;
- Current Charges dates and totals;
- days;
- Payments & Extensions;
- payment preview/history;
- Extension preview values.

## Payment preview

Browser preview has been visually tested.
- partial payment can result in full days paid plus a partial credit toward the next day;
- no actual payment is created until `Record Payment` is clicked;
- `Close Preview` clears the preview without recording anything.

## Warning money formatting

Warning Center money now displays with normal two-decimal formatting.

---

# 5. BILLING — REMAINING PUNCHLIST BEFORE FREEZE

Do this before beginning Fleet/OnTrac implementation.

## A. Visually test a real RO-backed active Billing case

**Not yet done in the browser.**

Important:
- Dave noticed there is currently no clear active RO/Loaner case available for visual Billing testing.
- Previous AI started investigating this, but Dave stopped it because he had not asked for a test record yet.
- **Do not create an RO test case until Dave explicitly asks.**

When Dave is ready, inspect:
- RO number display;
- pay type;
- daily billing behavior;
- billed-through behavior;
- warranty / Extended Warranty presentation if applicable;
- no Rental-only payment controls leaking into Loaner;
- continuation behavior;
- return behavior;
- Warning Center behavior.

## B. Test Return / Complete

Need end-to-end browser testing for:
- Rental returned normally;
- Rental returned while overdue;
- Rental with amount still due;
- Rental with partial payment;
- Rental paid through current balance;
- Loaner/RO return;
- vehicle released back to correct availability state;
- Billing case moves to Closed Cases correctly;
- no historical Billing data is destroyed.

## C. Test payment mutation in browser

Backend rollback tests have passed, but browser mutation should still be deliberately exercised with Dave.

Test:
1. record a controlled partial payment;
2. verify summary updates;
3. verify Payment History;
4. verify missing SO#/RO# warning;
5. add SO#/RO#;
6. verify warning clears;
7. verify Reservation/pickup/return times remain unchanged.

Do not do this to the current Test Customer without Dave's approval.

## D. Decide Billing freeze point

When Dave says the Rental + Loaner/RO + Return/Complete workflows are operationally correct:
- stop polishing Billing;
- document remaining cosmetic backlog;
- move to Fleet/OnTrac.

---

# 6. FLEET / ONTRAC — DO NOT IMPLEMENT UNTIL DAVE TEACHES THE RULES

Dave receives reports from **GM OnTrac** that provide authoritative operational information used for:
- adding vehicles;
- updating vehicles;
- identifying vehicles leaving the fleet/program;
- license-plate tracking;
- plate expiration information;
- other fleet fields.

The existing schema has some assumptions/scaffolding, but **Dave must explain the actual reports and dealership workflow before we treat those assumptions as policy.**

## Required requirements session with Dave

Before coding, obtain actual report samples and walk through:

### Vehicle identity
- Is full VIN always present?
- Is VIN last-8 also present?
- What is the authoritative matching key?
- How are stock numbers represented?
- Can stock number change?
- How are year/model/trim represented?

### Add vehicle rule
- What exact OnTrac condition means a vehicle should be added?
- Is appearance on In-Service report sufficient?
- Are there cases to ignore?
- What fields are mandatory before the vehicle becomes operational?

### Retirement/removal rule
- What exact report/change tells Dave that a vehicle should leave the active fleet?
- Is disappearance from a report meaningful?
- Is there a separate sold/out-of-service marker?
- Does retirement require manual confirmation?
- What effective date should be recorded?
- What happens if the vehicle still has a plate, future Reservation, active case, or other dependency?

### Plate workflow

Dave must define:
- actual plate types;
- which plate types permit Rental use;
- which plate types permit Loaner use;
- whether plate type is included on OnTrac reports;
- whether plate expiration comes from OnTrac;
- effective date of plate moves;
- whether Dave ever backdates a plate assignment;
- temporary no-plate situations;
- plate replacement vs transfer;
- lost/damaged/expired plate workflow;
- whether one vehicle may ever have more than one active relevant plate;
- whether a plate may temporarily be unassigned.

### Import error handling
- duplicate VIN;
- ambiguous last-8;
- unknown plate;
- plate shown on a different VIN than system history;
- missing required fields;
- report row with vehicle not expected in Stanley fleet;
- retirement candidate with active work;
- bad odometer / qualified miles;
- manually corrected values vs next OnTrac upload.

**Do not invent answers.**

---

# 7. EXISTING FLEET / ONTRAC BACKEND FOUNDATION

We are **not starting from zero**.

## Vehicles

Existing vehicle administration fields include:
- VIN;
- VIN last 8;
- stock number;
- model year;
- model;
- trim;
- fleet type;
- status;
- odometer;
- qualified miles;
- OnTrac days in service;
- record source;
- first / last OnTrac seen timestamps;
- plate-sync-required flag;
- CTP fields;
- retirement fields.

## OnTrac staging

Existing backend includes:
- `ontrac_import_batches`
- `ontrac_import_rows`

Existing staged report types include:
- `in_service_list`
- `expiring_plates`

Rows can preserve:
- VIN;
- VIN last 8;
- stock number;
- model year;
- make/model/trim;
- license plate;
- plate expiration;
- odometer;
- qualified miles;
- days in service;
- program;
- vehicle status;
- matched vehicle;
- review/proposed action;
- import error;
- processed flag.

Existing scaffolded action concepts include:
- insert;
- update;
- retire candidate;
- plate required;
- assign plate;
- ignore/error/review.

**These are scaffolding, not automatically approved dealership rules.**

## Fleet master view

`v_admin_vehicle_master_state` already combines vehicle administration information for the Fleet UI.

## Retirement

Existing backend has:
- `retire_vehicle_state`
- `reactivate_vehicle_state`

The current retirement engine refuses retirement while the vehicle has certain active dependencies such as active assignment/open event/open or upcoming reservation.

Before using this with real data:
- reconcile those safeguards with Dave's actual retirement workflow;
- do not assume the existing behavior is complete.

---

# 8. LICENSE PLATES — KNOWN BUSINESS RULES

This section is extremely important.

## Plate type affects legal/operational use

The vehicle's fleet category by itself is **not sufficient** to determine whether it can be used for a Rental.

Known rule from Dave:
- A vehicle may belong to the **Rental fleet** but currently have a **Loaner-type plate/tag**.
- While it has that plate, it **cannot be used as a Rental**.
- Dave moves plates from car to car.
- The system must preserve the dates that each plate was assigned to each VIN.

Existing broader fleet rule:
- Rental-fleet vehicles may be used as Loaner fallback.
- Loaner-fleet vehicles may not be used as Rentals.

The final eligibility decision must therefore consider at least:
- vehicle fleet classification;
- active plate;
- plate type;
- Reservation type;
- any other rules Dave defines.

**Do not invent the final matrix until Dave gives the plate-type rules.**

---

# 9. EXISTING PLATE DATA MODEL

The database already contains a good historical foundation.

## `tags`

Plate master record:
- `tag_name`
- `tag_type`
- expiration
- status

## `vehicle_tags`

Historical VIN ↔ plate assignment:
- vehicle ID;
- tag/plate ID;
- `applied_at`;
- `removed_at`;
- `is_active`;
- who applied it;
- who removed it;
- notes;
- timestamps.

This is the correct concept for preserving:
> Plate ABC was on VIN 1 from date X to date Y, then on VIN 2 from date Y onward.

## Existing problem

`vehicles.current_tag` also exists as a simple current-value field.

That means there are potentially **two representations** of “current plate”:
1. the historical `vehicle_tags` relationship;
2. `vehicles.current_tag`.

Before real fleet import, this must be reconciled so there is **one authoritative answer**.

Recommended direction — subject to implementation review:
- active `vehicle_tags` relationship becomes authoritative;
- `vehicles.current_tag` becomes derived/compatibility-only or is kept transactionally synchronized;
- never directly overwrite a plate without writing history.

---

# 10. PLATE ADMINISTRATION — REQUIRED BUILD PUNCHLIST

Do not start until Dave has supplied the plate types/rules.

## A. Plate master

Need a real Plate Administration surface for:
- plate number;
- plate type;
- expiration;
- status;
- notes if needed.

## B. Authoritative plate assignment/move engine

A plate move must be one authoritative transaction.

It should:
1. validate the plate;
2. validate the target VIN;
3. identify current active VIN assignment, if any;
4. close the old assignment at the effective timestamp;
5. open the new assignment at the same/elected timestamp;
6. update current vehicle state consistently;
7. preserve all history;
8. audit old VIN, new VIN, plate, effective time, actor, reason;
9. prevent overlapping active assignments;
10. detect conflicts rather than silently overwriting them.

Need Dave's rule for:
- whether a vehicle can have zero active plates;
- whether a vehicle can ever have multiple relevant active plates;
- whether a plate may be unassigned;
- whether assignment can be backdated.

## C. Remove/unassign plate

Need controlled workflow:
- close assignment;
- preserve plate history;
- set plate status appropriately if needed;
- update vehicle eligibility.

## D. Plate history

From a VIN:
- current plate;
- current plate type;
- plate expiration;
- every prior plate;
- date/time applied;
- date/time removed.

From a plate:
- current VIN;
- every prior VIN;
- assignment date ranges;
- expiration/status history if needed.

## E. Eligibility

Plate engine must expose a single authoritative operational result such as:
- eligible for Rental;
- eligible for Loaner;
- unavailable due to plate type;
- unavailable due to no plate;
- unavailable due to expiration/status;
- etc.

Exact statuses are to be approved by Dave.

---

# 11. ONTRAC IMPORT — REQUIRED OPERATIONAL WORKFLOW

The import must be **preview/review/apply**, not blind sync.

## Step 1 — Upload
- Staff uploads actual OnTrac report.

## Step 2 — Parse/stage
- Every source row is preserved in import staging.

## Step 3 — Match

Match row to an existing vehicle using the rules Dave approves.

Must surface:
- exact match;
- new VIN;
- ambiguous match;
- duplicate;
- invalid row;
- plate conflict;
- retirement candidate;
- other review conditions.

## Step 4 — Preview

Show exactly what the import proposes before changing production data.

Examples:
- ADD vehicle;
- UPDATE odometer;
- UPDATE OnTrac days;
- MOVE plate ABC from VIN X to VIN Y;
- UPDATE plate expiration;
- RETIRE candidate;
- NO CHANGE;
- NEEDS REVIEW.

## Step 5 — Dave/staff review

High-risk actions should not silently apply.

At minimum, retirement and conflicting plate moves should be reviewable unless Dave explicitly defines another rule.

## Step 6 — Apply

Use authoritative engines:
- vehicle create/update;
- plate assignment/move;
- retirement;
- other approved state mutations.

Do not directly bulk overwrite historical fields.

## Step 7 — Reconciliation

After apply:
- inserted count;
- updated count;
- plate moves;
- retirement candidates/applied retirements;
- unmatched;
- errors;
- ignored/no-change;
- audit linkage back to import batch and source row.

---

# 12. FLEET ADMINISTRATION — CURRENT STATE

There is already a Fleet Administration page that can load/search/filter/show:
- VIN;
- stock;
- year/model/trim;
- plate;
- plate expiration;
- fleet type;
- status;
- odometer;
- qualified miles;
- days in service;
- source;
- OnTrac last seen;
- location.

However, the operational actions are not complete.

Current UI buttons such as:
- Edit Vehicle;
- Retire Vehicle;
- Reactivate Vehicle;
- View History

are not yet a finished operational workflow.

The current page also still has a history placeholder.

The Admin Console lists:
- GM OnTrac Sync Center as Foundation;
- Plate Administration as Planned;
- Vehicle Import Review as Planned;
- Retirement Review as Planned.

---

# 13. FLEET ADMINISTRATION — REQUIRED BUILD PUNCHLIST

After plate rules and import rules are approved:

## A. Vehicle list

Must support:
- search VIN / last 8 / stock / model / plate;
- Active/Retired;
- Rental/Loaner;
- status;
- plate eligibility;
- needs review.

## B. Vehicle detail

Show:
- full vehicle identity;
- current operational state;
- current plate + plate type;
- plate eligibility;
- plate history;
- OnTrac source/history;
- retirement state/history;
- current/future dependencies;
- audit/activity history.

## C. Add/Edit

Manual add/edit may still be required for exceptions.

Need Dave to define:
- what fields staff may manually override;
- which OnTrac fields should overwrite manual values;
- which manual values should be protected;
- whether manual additions later convert to OnTrac-managed records.

## D. Retirement/Reactivate

Wire existing backend only after workflow review.

Must preserve:
- reason;
- effective date;
- actor;
- history;
- dependency checks.

## E. Plate controls

From Vehicle detail:
- Assign/Move Plate;
- Remove Plate;
- View Plate History.

Do not make `current_tag` a free-text edit box.

---

# 14. VEHICLE ELIGIBILITY — REQUIRED CENTRAL ENGINE

Eligibility cannot be enforced only by the Fleet page.

Every authoritative workflow that can put a vehicle into service must use the same eligibility result.

Must eventually cover:
- Pickup candidate list;
- Pickup;
- manual assignment;
- swap/reassignment;
- walk-in;
- any future direct vehicle assignment workflow.

## Known fleet rule

Current live logic already supports:
- Rental reservation → Rental-fleet vehicle only;
- Loaner reservation → Loaner or Rental-fleet vehicle.

## Missing plate rule

Current pickup/candidate logic does **not yet include the plate-type restriction Dave described.**

That must be added after the plate rules are defined.

## Capacity warning

Do **not** automatically change Reservation Capacity just because plate eligibility is added.

Dave must decide:
- whether Rental Capacity is model inventory, currently-rentable plated inventory, or another rule;
- how temporary Loaner-tagged Rental vehicles affect future Rental availability;
- when that impact should become a warning/conflict vs an immediate capacity reduction.

Do not guess.

---

# 15. REAL FLEET ROLLOUT PLAN

Once Billing, plate authority, import, Fleet Administration, and eligibility are ready:

## Stage 1 — First real OnTrac report, preview only

Do not apply.

Compare:
- source row count;
- proposed vehicle count;
- matched VIN count;
- new VIN count;
- plate count;
- proposed plate moves;
- retirement candidates;
- unmatched/errors.

Dave reviews the proposed interpretation.

## Stage 2 — Controlled apply
- Apply only after Dave agrees the preview is correct.

## Stage 3 — Verification

Manually inspect:
- several VINs;
- several plate assignments;
- plate histories;
- one moved plate;
- vehicle eligibility;
- retired/active states;
- Fleet list;
- Fleet Board effect;
- candidate-selection effect.

## Stage 4 — Begin real transactions

Start with a controlled subset of real operations:
- Reservation;
- Loaner/RO;
- Rental pickup;
- payment;
- Extension;
- swap;
- return;
- Billing close.

## Stage 5 — Expand use

Only after those paths are stable.

---

# 16. CONFLICT / WARNING ENGINES — AFTER REAL DATA IS FLOWING

Do not rebuild the Dashboard/Conflict Center before the operational core works.

Existing database already contains reservation/conflict/dependency concepts.

Once real vehicles and plate eligibility exist, warnings should eventually include examples such as:
- future Reservation endangered by manual Extension;
- vehicle no longer Rental-eligible due to plate move;
- plate conflict;
- plate expiration;
- OnTrac mismatch;
- retirement blocked by active dependency;
- missing payment proof;
- other unresolved operational exceptions.

Warnings should generally:
- be clickable into the affected Transportation Event / VIN / plate;
- remain until the condition is actually resolved;
- not disappear simply because someone viewed them.

---

# 17. DEFERRED — DO NOT DRIFT INTO THESE YET

Unless Dave explicitly changes priority:
- Dashboard rebuild/customizable tiles;
- Global Conflict Center tile;
- Quote/Reservation capacity-alternative refinement;
- Exact-unit assignment redesign;
- Fleet Board cosmetic work;
- QR administration;
- broad Reporting build;
- security-advisor backlog unrelated to the current workflow;
- late fees;
- excess-mile billing;
- broad Admin Console cleanup.

---

# 18. KNOWN APPLICATION ARCHITECTURE / RULES TO PRESERVE

- Transportation Events are the operational source of truth.
- Billing authority belongs in Supabase, not React math.
- App does not cashier; payment state mirrors dealership accounting/Tekion workflow.
- Maine Rental tax currently 10%.
- Pay-type `is_taxable` is authoritative.
- GM Warranty and Extended Warranty are exempt under current configuration.
- Extended Warranty day caps/splits remain separate from Rental block pricing.
- Rental pricing uses Daily/Weekly/Monthly block pricing with 28-day month.
- Positive partial Rental pricing day rounds up.
- Previous Rental/Extension segments are locked and do not retroactively blend when later time accrues.
- Rental vehicles can be Loaner fallback.
- Loaner fleet vehicles cannot be Rentals.
- Special/VIP rules exist but are not part of this immediate Fleet/OnTrac task unless Dave brings them in.

---

# 19. NEXT AI — EXACT FIRST STEPS

When a new chat takes over:

1. Read this entire document.
2. Verify GitHub `main` is still at or ahead of:
   `8fd0c112f9990b4d0764442f355059cc0da2b3cb`
3. Verify primary Vercel production corresponds to current `main`.
4. Do **not** create a new RO test record automatically.
5. Ask Dave whether he wants to:
   - finish Billing RO/Return testing first; or
   - begin the OnTrac/plate requirements walkthrough if he considers Billing frozen.
6. If Billing testing continues, remain only in Billing.
7. If Dave moves to Fleet/OnTrac:
   - ask him to provide the actual OnTrac report(s);
   - inspect the reports before proposing schema/UI changes;
   - capture his plate types and operational rules;
   - write those rules down;
   - only then design/implement the plate/import workflow.
8. Before any Supabase mutation, perform live definition/grant/drift/rollback checks.

---

# 20. DEFINITION OF “OPERATIONAL ENOUGH TO START REAL USE”

The system is ready for controlled real dealership use when all of the following are true.

## Billing
- Rental active Billing works.
- Loaner/RO active Billing works.
- partial/full Rental payment works.
- SO#/RO# proof workflow works.
- Extension works.
- overdue works without fake Extension.
- Return/Complete works.
- Closed Cases preserve history.

## Fleet
- real OnTrac report can be safely previewed and applied.
- vehicle add/update is reliable.
- retirement workflow is reliable.
- Fleet Administration shows authoritative data.

## Plates
- plate master exists operationally.
- plate type controls eligibility.
- plate moves are effective-dated.
- VIN history and plate history are preserved.
- no direct overwrite can erase history.
- one authoritative current-plate answer exists.

## Eligibility
- Pickup and reassignment cannot use a vehicle that is not eligible for the requested use.
- Rental-fleet vehicle with Loaner-only plate is not selectable for Rental use.
- Rental-fleet vehicle may still be available for Loaner use when otherwise eligible.
- Loaner-fleet vehicle remains ineligible for Rental use.

## Real-data validation
- first OnTrac import reconciles correctly.
- several VIN and plate histories manually verified.
- one controlled real Reservation-to-return cycle completed successfully.

Only then expand daily operational use.

---

# FINAL HANDOFF NOTE

The most important instruction is not technical:

**Dave knows the dealership rules. Do not fill gaps with assumptions.**

The project already has substantial backend foundation for Billing, OnTrac staging, vehicle retirement, and plate history. The next phase is not “build everything from scratch.” It is:

1. finish the workflow test gates;
2. learn the exact real-world OnTrac and plate rules from Dave;
3. connect the existing foundations into authoritative, auditable operational workflows;
4. import the real fleet carefully;
5. begin controlled real use.
