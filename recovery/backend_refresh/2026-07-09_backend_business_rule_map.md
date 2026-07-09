# Backend Business-Rule Map

Date: 2026-07-09

This document records the backend-enforced business rules that are already implemented in the repository and that the frontend should respect. It is intentionally limited to repository-backed behavior from the schema, views, and SQL functions.

## Scope and method

The rules below were derived from the backend artifacts in this repository:
- schema definitions
- SQL view definitions
- SQL function implementations
- admin-setting and policy-related functions

This document does not invent workflow rules. It only summarizes behavior that is already present in the backend.

## 1. Reservation and case lifecycle rules

### 1.1 Transportation events are the lifecycle root
- The backend treats transportation events as the parent lifecycle record for reservations and related continuity actions.
- Reservation creation and case creation are wired through functions that create a reservation plus a transportation event together.
- Frontend impact: screens that display or mutate reservation state should treat the transportation event as the shared lifecycle context, not as an optional child concept.

### 1.2 Reservation assignment is time-gated by a VIN-lock window
- Reservation assignment is governed by a VIN-lock lead-days setting stored in admin settings.
- The lock window starts at `start_date - lead_days`.
- Assignment functions reject requests when the reference time is earlier than the lock window start.
- Frontend impact: the UI should not allow vehicle assignment before the lock window opens, and should display the lock window window start and whether the reservation is inside it.

### 1.3 Reservation vehicle candidates are derived from model match and current availability state
- The backend candidate view joins reservations to vehicles by matching the requested model to the vehicle model.
- Each candidate is labeled as one of:
  - `ready`
  - `pending_return`
  - `unavailable`
- `pending_return` is used when the vehicle currently has open continuity and is therefore not immediately available.
- `ready` is used when the vehicle is available now.
- Frontend impact: candidate ordering, badges, and availability messaging should come from the backend candidate state rather than a separate frontend-only rule.

### 1.4 There is no backend rule that prefers loaners over rentals for candidate selection
- The repository does not contain a separate backend rule that says “prefer loaner before rental” for reservation vehicle candidates.
- The actual candidate logic is model-based and availability/continuity-based, as implemented in the candidate view and candidate payload function.
- Frontend impact: if the UI wants a loaner-first experience, that must be treated as a product decision rather than a repository-enforced rule.

### 1.5 Case completion and continuation are explicit backend actions
- The backend exposes explicit functions for case continuation, completion, and cancellation.
- Completion captures actual return/in time, end mileage, optional closure note, and can close billing.
- Continuation updates the case to a new time while preserving the same vehicle context.
- Cancellation closes the case and records a cancellation reason and note.
- Frontend impact: the UI should invoke these backend actions rather than trying to simulate lifecycle transitions locally.

## 2. Vehicle assignment and dependency rules

### 2.1 Hard-lock assignment creates dependency state
- When assignment is done through the hard-lock assignment function, the backend also creates or updates a reservation vehicle dependency record.
- The dependency captures the vehicle, reservation, source transportation event, expected return snapshot, notes, and actor user.
- Frontend impact: assignment flows that require a dependency trail should rely on the backend-created dependency state and not invent their own dependency record.

### 2.2 Clearing an assignment also clears dependency state
- The backend includes a function that clears a vehicle assignment while also clearing dependency state for the reservation.
- Frontend impact: unassignment actions should be routed through the backend function so dependency cleanup happens consistently.

### 2.3 Dependencies and conflicts are backend-tracked operational signals
- The repository has tables and views for reservation vehicle dependencies and reservation conflicts.
- The backend surfaces dependency and conflict status in operational payloads, dashboard feeds, and warning-center data.
- Frontend impact: warning banners, conflict panels, and dependency indicators should reflect backend state rather than independent local calculations.

## 3. Billing and pay-type rules

### 3.1 Billing lines are tied to a transportation event and a pay type
- Billing line creation requires a valid transportation event and a pay type that exists in the pay-type rules catalog.
- Blank pay types are rejected.
- Frontend impact: the UI should not allow billing actions without a valid pay type and should treat billing as event-scoped.

### 3.2 Billing line temporal constraints are enforced
- The backend validates that end time is not before start time and that paid-through dates are not before start time.
- Frontend impact: date/time editing should respect these constraints and should not rely on the client to enforce them.

### 3.3 Extension billing lines are a backend-supported workflow
- The repository contains an extension-billing-line function that uses an existing parent line and creates an extension record with updated expected return context.
- Frontend impact: extension billing should be implemented as a backend-driven action, not as a custom client-side billing mutation.

### 3.4 Late-fee rules are configurable and gateable
- The backend stores late-fee rules and exposes active-rule retrieval.
- A global admin setting toggles whether late fees are enabled.
- Frontend impact: late-fee visibility and enforcement should be conditioned on the backend-enabled setting.

## 4. Warranty and provider rules

### 4.1 Warranty providers and rules are first-class backend objects
- The repository stores warranty providers, extended warranty rules, warranty cases, warranty alerts, and warranty-day ledger rows.
- Extended warranty rules can require approval and can include daily rates and covered-day rules.
- Frontend impact: warranty screens should read and write through the backend catalog and case functions instead of keeping separate local warranty state.

### 4.2 Warranty approval state is part of the backend workflow
- The backend tracks approval status, approved days, current day count, manual-review needs, and escalation level.
- Frontend impact: the UI should present warranty approval state as backend-managed workflow state rather than as ad-hoc status labels.

## 5. Admin and security rules

### 5.1 VIN-lock lead days is a configurable admin setting
- The backend stores the VIN-lock lead-days value in admin settings.
- The setting is read by the assignment functions and exposed through dedicated payload functions.
- Frontend impact: any VIN-lock timing display or validation should use the backend-provided setting rather than a hard-coded value.

### 5.2 Late-fee enablement is a backend admin toggle
- The backend exposes functions to set and retrieve the global late-fee enablement flag.
- Frontend impact: the UI should reflect the backend toggle as the source of truth for whether late-fee features are available.

### 5.3 MFA, network restrictions, and password-reset settings are backend-managed
- The repository includes backend functions and views for MFA requirements, network restriction enablement, and email password-reset-link enablement.
- Frontend impact: admin security screens should use the backend payloads and update functions instead of managing these settings locally.

## 6. Frontend compliance summary

The frontend should align with the following backend expectations:
- Use backend functions for reservation creation, assignment, continuation, completion, cancellation, and note creation.
- Treat transportation events as the lifecycle parent object for case-level state.
- Respect the VIN-lock window and candidate-state labels returned by the backend.
- Do not implement a separate client-side rule for candidate ordering beyond the backend-provided ranking and state.
- Use backend billing, warranty, and admin-setting functions as the system of record.
- Display dependency and conflict state from backend payloads and dashboard feeds rather than from independently computed local state.
