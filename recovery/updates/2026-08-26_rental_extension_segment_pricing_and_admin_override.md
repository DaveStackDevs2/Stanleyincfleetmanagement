# 2026-08-26 — Rental Extension segment pricing and Admin/Dev retroactive override

## Binding owner correction

This file supersedes any prior assumption that a Rental Extension automatically reprices the entire continuous Rental.

### Global authorization invariant

**Hard rule: Dev is a superset of Admin. Anything an Admin can see or do in the application, a Dev must also be able to see and do. Never create an Admin capability that excludes Dev.**

This invariant applies to the retroactive-pricing exception below and to all future application permissions/workflows. Other roles do not inherit Admin/Dev capability merely because Dev does.

### Admin rate cards are authoritative

Stanley Rental vehicle pricing is configured in **Admin → Rates, Fees & Billing Rules → Rental Models & Rates**.

The existing `public.rental_rate_rules` and `public.rental_pricing_agreements` Daily / Weekly / Monthly snapshots are the authoritative monetary source. The configured Weekly and Monthly values are **per-day rates for qualifying blocks**.

Implementation MUST NOT hard-code model prices in SQL, React, tests, migrations, or business logic. Tests may use isolated fixture values only inside rollback/test contexts and must not seed production business prices.

### Normal Extension behavior — no retroactive repricing

A Rental Extension creates a new pricing segment beginning at the prior agreed expected-return boundary. The earlier agreed Rental segment remains financially locked by default.

The Extension segment is priced independently with the same completed-block decomposition:

1. completed 28-day Monthly blocks at that Rental's snapshotted Monthly per-day rate,
2. then completed 7-day Weekly blocks at the snapshotted Weekly per-day rate,
3. then remaining days at the snapshotted Daily rate.

Examples:

- Original Rental = 5 days. Customer extends 2 additional days → original 5-day obligation stays unchanged; Extension = 2 Daily days.
- Original Rental = 5 days. Customer extends 7 additional days → original 5-day obligation stays unchanged; Extension = 7 days at the Weekly per-day rate.
- Extension of 10 days → 7 Weekly-rate days + 3 Daily-rate days within the Extension segment.
- Extension of 28 days → 28 Monthly-rate days within the Extension segment.

Do NOT combine the original segment and Extension duration merely to earn a better block retroactively.

The existing Rental Extension parent-line/payment separation should be reused because it matches this owner rule. The shared Rental block-pricing resolver must accept a segment day count and authoritative snapshotted rate card so both Original Rental and each Extension can use the same math without sharing qualification clocks.

### Early Return with Extensions

Early-return repricing applies to the currently affected agreed pricing segment without rewriting already locked prior Rental/Extension segments by default.

- If the customer returns early during the Original Rental segment, recalculate that Original segment from its start through actual return.
- If an earlier Original/Extension segment is already closed and a later Extension is active, preserve the prior locked segment(s) and recalculate the active Extension from its own segment start through actual return.
- Surface Refund due / Customer owes / No difference for the affected segment through the existing Return/Complete workflow and Tekion reconciliation. Stanley TMS does not cashier.

### Admin/Dev retroactive pricing override

An Admin or Dev may explicitly override the normal no-retroactive-repricing rule for exceptional circumstances and request whole-Rental retroactive block repricing.

Requirements:

- The control is visible to Admin and Dev-authorized users only.
- Backend enforcement is mandatory; hiding the button is not sufficient.
- Create/reuse a narrow permission specifically for Rental retroactive-pricing override and map it to **both Admin and Dev** unless the owner later changes policy.
- Service Manager and other roles must not receive the capability merely because they hold other Billing permissions.
- The action must be explicit, audited, actor-stamped, and display the before/after authoritative charge and tax difference before/after commit as appropriate.
- It must reuse the same shared block-pricing and tax engines; no frontend money math.

### 28-day legal renewal boundary remains different from an Extension

The mandatory 28-day contract renewal is an operational/legal continuation boundary, not a customer-requested pricing Extension. It does not by itself reset the pricing qualification for the already-agreed Rental period.

Example: a Reservation agreed from the outset for 38 days still prices as 28 Monthly + 7 Weekly + 3 Daily while requiring a contract renewal at day 28.

A later customer-requested Extension beyond the previously agreed Rental period starts a new pricing segment under the rule above.

## Implementation effect on Issue #61

Checkpoint A must preserve these distinctions:

1. Initial agreed Rental period → one block-priced segment using Admin-configured/snapshotted rates.
2. Mandatory 28-day contract renewal inside that already-agreed period → no pricing reset.
3. Customer-requested Extension beyond the prior agreed period → new independently block-priced Rental Extension segment.
4. Admin/Dev retroactive exception → explicit audited whole-Rental repricing; never default behavior.

Any earlier Issue #61 text suggesting that Dev must be excluded from an Admin capability is superseded by the global Dev-superset authorization invariant.
# A1 repository update — 2026-08-26

Checkpoint A1 adds one shared exact-numeric backend block resolver and prices Extension preview as a new interval from the prior expected-return boundary. Earlier parent lines are not inputs. Reservations no longer offers a Rental money-plan selector. The repository also adds renewal/second-period swap status based on `renewal_sequence`; it does not automate either action. No Supabase apply or live verification is claimed.

The whole-Rental retroactive override remains deferred. Its future narrow permission must include both Admin and Dev and exclude Service Manager/other roles unless separately approved. Persistence still requires a deliberate adjustment-line/audit design that preserves locked/Paid Original and Extension checkpoints and represents Tekion refund/amount-owed handling without rewriting settlement history.
