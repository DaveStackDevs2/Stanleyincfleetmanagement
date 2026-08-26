# 2026-08-26 — Post-merge Rental block-pricing engine reconciliation

## Status

PR #62 merged to `main` at `e07b05269c0fe69607ff0573eee8d2c98d4b9cd6`, but its two A1 Supabase migrations remain **repository-only and unapplied**.

No A1 production deployment should occur until the merged migration bodies are reconciled with the current live Supabase engines.

## Live-engine reconciliation finding

A fresh live Supabase inspection before deployment found that `20260826213000_wire_rental_block_pricing_money_engines.sql` would replace newer authoritative production function bodies with older/simplified versions.

The correction must preserve these verified live contracts while adding Rental block pricing only where appropriate:

- `get_billing_preview_state(uuid,timestamptz)`
  - preserve the stored-snapshot Closed Billing review branch;
  - preserve historical tax-child validation and historical vehicle/contract lookup;
  - preserve `segments[*].contract_days` compatibility;
  - preserve future-start Rental Extension zero-elapsed behavior;
  - keep non-Rental Billing on inclusive `business_contract_days(...)` and the existing daily path;
  - never reprice closed/locked history.
- `activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer)`
  - preserve the shared Rental/Loaner engine;
  - preserve `reservation_type` and `ro_number` response fields;
  - preserve Loaner current-time Billing preview and `rental_payment_state = null`;
  - apply Rental block pricing only in the Rental branch.
- `preview_rental_extension_state(uuid,timestamptz)` must remain Rental-only and preserve current-line identity/safety checks and stable response fields.
- `accept_extension_commit_state(...)` must add server-authoritative block money only for Rental while preserving the non-Rental path and established helper sequence.
- `complete_case_return_and_close_state(...)` must preserve the current completion sequence and use `get_billing_preview_state(...)` as final money/tax authority, including historical tax snapshots; only the current Rental segment may receive block-pricing decomposition persistence.

## Existing verified repository lineage

The correction should build from the established reconciliation migrations rather than reconstructing simplified function bodies:

- `20260819143500_verified_closed_billing_review.sql`
- `20260819160500_verified_return_final_billing_persistence.sql`
- `20260820120000_verified_authoritative_extensions.sql`
- `20260820190000_anchor_extension_contract_days.sql`
- `20260821170000_correct_rental_payment_and_extension_workflow.sql`
- `20260821193000_reconcile_rental_loaner_pickup_workflows.sql`

## Deployment gate

Required order for this and future Supabase function changes:

1. inspect existing live engines/signatures/security/grants;
2. compare proposed SQL to the live engine contracts and reconcile drift;
3. run repository tests and review the remote diff;
4. run a real PostgreSQL `BEGIN/ROLLBACK` preflight;
5. only then deploy;
6. verify live definitions, grants, migration state, and behavior after deployment.

The global inclusive `business_contract_days(...)` contract must not be changed. No late/grace automation, capacity changes, Lost Rentals, or whole-Rental retroactive override are part of this correction.
