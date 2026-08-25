# Stanley TMS active workflow checkpoint — 2026-08-25

## Purpose

This is a documentation-only continuity checkpoint created before any new application or database code is changed. It exists so a successor AI/developer can recover the currently approved owner workflow even if the ChatGPT conversation ends unexpectedly.

Read this file together with `recovery/Stanley_TMS_Recovery_Bible.md`. Where older recovery/status text conflicts with the owner decisions or verified engine findings recorded here, verify current production/repository state and treat this newer checkpoint as the current active direction.

Repository anchor when this checkpoint was written:

- `main`: `e873c3d3ea075f5b75e90998cb26a88cc1aa5407`
- Merge: PR #44, Fleet Board operational routing

No application code, Supabase migration, production data, or deployed behavior is changed by this checkpoint.

---

# 1. End-to-end product goal remains unchanged

The TMS is not being built as disconnected Reservations, Calendar, and Billing pages. The required connected operating path remains:

**Fleet Board -> Quote / Reservation / Walk-in -> Check-in / Pickup -> active Billing -> daily Bulk Updating / individual Billing changes -> Extension / pay-type split / continuation / swap -> Return / Close**

The old Vehicle Calendar was replaced intentionally by the **Fleet Board**. The Fleet Board is the operational scheduling/front-door surface; do not resurrect a separate calendar-only persistence model.

Most Rental and RO/Loaner cases should be able to begin from the Fleet Board.

Billing is not complete merely because backend calculators exist. Completion means the dealership workflow above works end to end with correct Rental vs Loaner behavior.

---

# 2. Engine-first rule is binding

Before implementing any next feature, inspect LIVE Supabase first and identify the existing authoritative RPC/view/helper/trigger that owns the behavior.

Reuse or extend existing engines. Do not create parallel calculators, lifecycle engines, calendar models, assignment models, or billing models merely because a frontend feature needs another presentation.

A new backend engine is justified only when live inspection proves the required operation does not already exist.

This rule applies to both Fleet Board work and Bulk Updating.

---

# 3. Fleet Board: current verified direction

The Fleet Board is already connected in the repository to the existing operational workflows:

- Day and Week views.
- Day timeline is 7:00 AM–7:00 PM.
- Rental-only Reservation Capacity rows from `rental_model_limits`.
- Model-level pre-pickup Rental and Loaner Reservations.
- Pre-pickup actions route to existing Edit Reservation and Check-in / Pickup workspaces.
- Active VIN-level assignment blocks route to the existing Billing case.
- Empty Day slots route into existing Quote / Reservation / Walk-in intake.
- Empty-slot context carries model, Rental/Loaner type, and selected date/time only.
- Clicking a vehicle row does **not** preassign that VIN to a normal future Reservation.
- Exact Rental-fleet slot can start Rental or Loaner fallback intake.
- Exact Loaner-fleet slot can start Loaner intake only.
- Unsupported / blank / Special fleet types fail closed for intake routing.

The Fleet Board is a router. It does not directly mutate Transportation Events, Pricing Agreements, Pickup, or Billing.

## Important Fleet Board gap found in the 2026-08-25 live engine audit

The board currently **displays** Rental Reservation Capacity, but the authoritative intake engines do not yet enforce it.

Fresh live inspection showed that these existing engines do not currently consult `rental_model_limits` and do not currently create/refresh Rental capacity conflicts:

- `create_quote_with_pricing_agreement_state`
- `create_reservation_with_pricing_agreement_state`
- `create_walk_in_with_pricing_agreement_state`
- `convert_quote_to_reservation_with_pricing_agreement_state`

Therefore the current backend can display a limit such as `2 / 2`, but authoritative creation does not yet guarantee that another Rental Reservation cannot create `3 / 2`.

This is a real unfinished Fleet Board / Reservations integration item and must not be forgotten while Billing work continues.

Before implementing capacity enforcement, inspect and reuse the existing Reservation conflict/dependency engines where applicable. Do not write capacity-conflict logic in React.

---

# 4. Bulk Updating: owner-approved business purpose

“Bulk Updating” is the owner's name for the dealership's normal daily Tekion billing workbench.

It belongs inside active Billing. It is **not** merely a Tekion worksheet. Pressing Apply updates Stanley TMS authoritative Billing first. The compact Tekion helper is produced from the successfully persisted Stanley Billing results afterward so staff can enter those values into Tekion.

This feature must not remove or weaken normal individual-case Billing controls. Staff must still be able to open one RO and choose a different billed-through date/time manually.

Rentals remain financially separate from Loaner/RO daily billed-through processing.

---

# 5. Bulk Updating grid layout

The owner prefers dense spreadsheet-like/gridded work surfaces for this workflow, with alternating row colors and clear row/cell separation. Do not redesign this as large cards.

The Bulk Updating area should show one row for every **currently out** RO/Loaner and Rental, in a consistent useful order.

Required row information:

- selection checkbox where Bulk Updating is allowed
- RO number (or clear Rental identifier for Rental rows)
- current contract-period out/start date and time
- expected return date and time
- current billed-through date and time
- current pay type
- applicable daily amount for that pay type/segment
- total days in vehicle **for this pay type/segment**
- total amount owed **for this pay type/segment**
- tax for that pay type/segment when applicable
- visible success/attention state

For split-pay-type ROs, do not show whole-case lifetime money as if it belongs to the current pay type. The grid must respect authoritative Billing segments.

Example: if an RO begins as Extended Warranty and later becomes Customer Pay, the Customer Pay segment needs its own days, amount, and tax rather than inheriting the Extended Warranty portion.

No monetary arithmetic should be invented in React. Use authoritative backend values.

---

# 6. Bulk Billing Through target controls

At the top of Bulk Updating there is one **Bulk Billing Through** date/time control.

Setting or changing this control must not write anything by itself.

The target may legitimately be in the future. This is required for real dealership operations.

Typical Friday workflow:

- On Friday, staff often bills through **Sunday at 5:00 PM (17:00)**.

Add a convenience button named approximately:

**Bill Thru Sunday**

Behavior of that shortcut:

- Set the Bulk Billing Through date/time to the upcoming Sunday at 5:00 PM.
- Re-evaluate the grid against that target.
- Do **not** select rows automatically.
- Do **not** Apply automatically.
- Do **not** update Billing automatically.

Only an explicit user press of **Apply** may commit Bulk Updating.

---

# 7. Grid state after a Bulk Billing Through target is entered

Once a date/time target is present, rows should immediately communicate what that target would do before the user presses Apply.

## RO/Loaner that would advance

If the selected Bulk Billing Through target is later than the case's current billed-through state and the row is otherwise eligible, the row gets a **light green background**.

The checkbox is available for staff selection.

## RO/Loaner already billed beyond the target

If the current billed-through date/time is later than the entered Bulk target, the row gets a **red background**.

That row is not eligible for Bulk Updating to that target and must not be selectable for the batch.

Binding rule:

**Bulk Updating may advance billed-through state but must never move billed-through backward.**

## Already at the target

If the case is already billed through exactly the selected target, there is nothing to update. It should not be treated as a successful pending change and should not be selectable for an unnecessary write.

## Rentals

Rental rows remain visible for situational awareness but are **not selectable for Bulk Updating**.

Rental rows use an **orange background** so the owner can instantly distinguish Rentals from RO/Loaner cases.

The reason Rentals remain visible is operational: the owner wants to keep their return times/overdue state fresh while becoming comfortable with the new TMS. This display-only Rental presence may be removed later.

## Expected Return / overdue attention

Billing does not stop merely because a Loaner/RO has passed its Expected Return. Bulk billed-through may continue beyond Expected Return.

The UI must still make Expected Return problems/overdue cases clearly visible so staff knows the shop/RO needs attention.

For Rentals, an overdue/attention indicator must remain obvious without losing the orange Rental identity.

Do not use Expected Return as an automatic cap on billed-through.

---

# 8. Selection and Apply behavior

Staff chooses only the RO/Loaner rows they want to update using checkboxes.

Not every currently out RO is necessarily billed in every daily batch.

If Apply is pressed with no eligible rows selected, no write occurs and the user receives a clear message such as:

**Select at least one RO to update.**

When Apply is pressed, Stanley TMS authoritative Billing is updated first.

For every successful selected case, the UI must make success obvious (for example, `Updated` with a clear success state). Staff should never have to guess whether a row committed.

Known ineligible conditions that can be determined before Apply should be surfaced in the grid and made non-selectable rather than waiting for Apply to discover them.

## Runtime batch failure policy is not yet owner-finalized

The owner has not yet explicitly chosen the final transaction policy for an unexpected runtime failure after prevalidation (for example, whether 9 valid rows may succeed if the 10th encounters a new authoritative error, or whether the entire Apply should roll back).

Do not invent this behavior. Before implementation is finalized, ask the owner if the engine design still requires this decision after prevalidation is specified.

---

# 9. Extended Warranty -> Customer Pay behavior during Bulk Updating

This is a required real-world workflow and must be handled automatically by Stanley TMS.

If a selected Bulk Billing Through target crosses an Extended Warranty coverage cap:

1. Reuse the existing Extended Warranty reconciliation/split engine.
2. Complete/close the Extended Warranty Billing segment at the exact authoritative coverage boundary.
3. Create/start the new Customer Pay segment in Stanley Billing at that exact boundary.
4. Continue the Customer Pay portion through the selected Bulk Billing Through target.
5. Persist the authoritative days/amount/tax for each applicable segment.
6. Make the split/action visually clear to staff.

The Tekion helper must show **two rows/entries for that RO** when both portions require Tekion work:

- Extended Warranty portion to complete/update the existing Tekion line.
- Customer Pay portion for the new Tekion line.

The Customer Pay entry must clearly tell staff that a **new Customer Pay line must be created in Tekion**, with tax information when Customer Pay is taxable.

Keep this indication compact; the always-on-top helper is intended to occupy as little screen space as practical.

## Verified backend rule

Live engine inspection on 2026-08-25 verified that Extended Warranty case creation already resolves the active `Customer Pay` pay type and stores it as the post-coverage fallback (`post_coverage_pay_type_rule_id`).

Therefore:

**Extended Warranty automatically defaults to Customer Pay after its covered-day limit.**

If the owner later needs a different pay type for a particular RO, that will be handled manually in normal RO Billing afterward.

Do not invent a different automatic fallback.

---

# 10. Tekion helper after Apply

After successful Stanley Billing updates, show a compact Tekion helper containing only the lines that were actually changed successfully.

The helper is for copying Stanley's persisted authoritative Billing results into Tekion; it does not perform Tekion cashier/payment operations.

Required compact fields per Tekion work line:

- RO number
- Days
- Total / charge amount
- Tax total

Each useful value should be individually clickable to copy to the clipboard so staff can move RO by RO through Tekion with minimal typing.

Extended Warranty -> Customer Pay split can produce two helper lines for the same RO as described above.

The owner wants the helper to be able to remain **always on top** while working in Tekion. Prefer a compact browser-supported always-on-top/Picture-in-Picture style window when technically available; provide a compact in-app fallback if the browser cannot support it.

Do not let helper presentation become the source of financial calculations. It displays authoritative persisted results.

---

# 11. Undo is a real Billing reversal

The Bulk Updating UI includes **Undo**.

Undo means:

**After Apply, reverse the most recent applicable Bulk Updating batch and restore every affected RO to its exact previous Stanley Billing state.**

The restoration includes the prior:

- billed-through timestamp
- segment days/state as applicable
- amount
- tax
- any batch-created split state that must be reversed to faithfully restore the pre-batch state

Undo is not merely clearing checkboxes or changing presentation.

Undo must be auditable and safe.

If a case has been changed individually or otherwise advanced after the Bulk batch, an old Undo must fail closed for that case/batch rather than silently overwriting newer legitimate Billing work.

## Engine audit result

Fresh live inspection found no existing obvious bulk/batch/undo/rollback Billing RPC to reuse, and `billing_lines` has an updated-at trigger but no generic audit trigger capable of reconstructing an arbitrary prior Bulk batch.

The existing single-case billed-through engine is intentionally forward-only and rejects moving billed-through backward.

Therefore a real Undo will require a narrow persisted/audited batch before-state design. That design must still reuse the existing Billing/EW/tax engines for authoritative calculations rather than creating a second calculator.

---

# 12. Existing Billing engines discovered and expected reuse

Relevant existing live engines include, among others:

- `get_billing_preview_state(uuid,timestamptz)`
- `mark_case_billed_through_and_get_preview_state(uuid,timestamptz,text)`
- `set_reservation_billed_through_state(uuid,timestamptz,text)`
- `get_reconciled_billing_workspace_state(timestamptz)`
- `reconcile_extended_warranty_coverage_state(uuid,timestamptz)`
- `reconcile_extended_warranty_coverage_and_get_state(uuid)`
- existing tax-child synchronization / Billing-line helpers
- existing return/close, extension, continuation, reassignment, and swap engines

Do not duplicate their monetary or lifecycle logic.

## Future billed-through finding

Fresh live inspection verified:

- `get_billing_preview_state(...)` does **not** itself reject a future effective timestamp and can calculate using the supplied effective target.
- `mark_case_billed_through_and_get_preview_state(...)` currently **does** reject a billed-through target later than the current clock time.
- `get_reconciled_billing_workspace_state(...)` also currently rejects a future reconciliation timestamp.

This explains why Friday -> Sunday 5:00 PM requires an intentional extension of the controlled commit/reconciliation path.

Do not respond by creating a separate frontend calculator.

---

# 13. Rental vs Loaner separation remains binding

Rental rows appear in Bulk Updating for awareness only.

Bulk Updating must not:

- mark a Rental Paid in Full
- alter Rental Payment state
- create Rental Extensions
- convert Rental billing into Loaner billed-through behavior
- use vehicle fleet type to decide whether a case is a Loaner

The authoritative Reservation/case type governs the workflow.

A Loaner using a Rental-fleet fallback vehicle remains a Loaner.

Rental original charge/payment/Extension behavior stays in the existing Rental workflow.

---

# 14. Individual Billing remains available

Bulk Updating is a daily convenience/workbench, not the only way to change billed-through state.

Staff must continue to be able to open an individual RO in normal Billing and choose a different billed-through date/time or make authorized case-specific changes.

A Bulk feature must not remove or weaken the single-case workflow.

---

# 15. Current open Billing item: weekly/monthly Rental Pickup

Weekly/monthly Rental Pickup remains intentionally fail-closed.

Fresh engine/repository audit found that this is not simply a missing UI toggle. The current authoritative Billing preview is daily-rate based, while the product rules for weekly/monthly blocks, early return fallback, conversion, and later automatic blocks have not been owner-approved.

Do not invent those financial rules.

Do not remove the non-daily Pickup guard until the owner explicitly defines the charging behavior.

This remains an open Billing blocker but is separate from the newly defined Bulk Updating workflow.

---

# 16. Repeated Rental Extension verification

Read-only production inspection found a persisted Rental chain containing:

- initial Billing segment
- first `rental_extension`
- second persisted `rental_extension`

The Transportation Event note for the second change records the controlled repeated-Extension production proof and the event Expected Return advanced accordingly.

This is sufficient evidence that successful repeated Rental Extension persistence occurred after the contract-day-anchor correction.

Do not mutate that production case merely to prove it again.

Older docs saying repeated Extension persistence remains unverified should be reconciled during the next documentation synchronization checkpoint.

---

# 17. Current implementation order / successor guidance

Do not jump directly from this document into Bulk UI code.

Before code changes:

1. Refresh live Supabase/repository state.
2. Reconfirm the existing engines above and inspect any newer migrations/changes.
3. Keep the Fleet Board as the main operating front door.
4. Close or deliberately checkpoint the Fleet Board/Reservations capacity-enforcement and capacity-conflict gap rather than forgetting it while Billing work advances.
5. Then implement Bulk Updating as an extension/orchestration of the existing Billing, EW split, tax, and Reservation state—not as another billing system.
6. Preserve individual Billing controls.
7. Keep weekly/monthly Rental Pickup fail-closed until owner rules are defined.
8. Verify each checkpoint in repository, live Supabase, and Vercel/browser when legitimate production data exists.

The owner explicitly asked that Fleet Board/calendar work remain part of the same overall task because this is where most Rental/RO cases will begin.

---

# 18. Documentation status of this checkpoint

This file intentionally records product requirements and verified engine findings only.

No code has been added for Bulk Updating yet.
No Bulk Undo engine has been added yet.
No future billed-through commit behavior has been changed yet.
No Fleet Board capacity enforcement has been added yet.
No Supabase migration was applied.
No production data was mutated.

The purpose is continuity: a future ChatGPT session should not need the 2026-08-25 conversation to recover these decisions.
