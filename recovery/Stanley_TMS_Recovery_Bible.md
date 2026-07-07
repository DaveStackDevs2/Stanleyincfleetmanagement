Stanley TMS Recovery Bible v1.0
Table of Contents
Stanley Transportation Management System - Project Bible and AI Handoff
Document status: Recovery Bible v1.0 - Baseline complete and living master handoff documentPrepared: 2026-07-03Primary purpose: Full project recovery, workflow continuity, and durable project memory between AI chats, developers, tools, and future build sessions.
This document is not a casual summary. It is the working specification for the Stanley Transportation Management System (TMS). Future AI chats should read this first before making technical recommendations, writing prompts, changing Supabase, changing frontend code, or advising on hosting.
Recovery Bible Operating Notice
This document is the permanent project memory for the Stanley Transportation Management System. It is not a casual summary, a chat recap, or a prompt draft. It is the authoritative source of truth used to recover the project if conversation history, AI memory, or developer context is lost.
A future AI or developer must treat this document as the first artifact to read before giving recommendations, changing architecture, writing code, changing Supabase, changing the frontend, or advising on deployment.
Current recovery state: Baseline complete as of this version. Future work should maintain and evolve this document as the TMS changes.
Critical instruction: Do not re-harvest old conversations unless new source material is added. Continue from this Bible.
Universal AI Project Continuity Protocol
These rules are technology-neutral and apply to any long-running AI-assisted project.
1. The Recovery Document Is the Source of Truth
The Recovery Document is the authoritative source of project knowledge. Conversation history is temporary. Project knowledge is permanent. If conversation history and the Recovery Document disagree, verify and then update the Recovery Document.
2. Preserve Knowledge, Not Conversation
Do not preserve chats for their own sake. Preserve decisions, requirements, reasons, constraints, and current state. Transfer all meaningful project knowledge into the Recovery Document.
3. Document the Why
Never document only what was built. Document why it exists, why it was designed that way, what alternatives were considered, and why those alternatives were rejected.
4. Assume Complete Memory Loss
Always assume previous AI conversations, previous developers, and previous project memory may be unavailable. The Recovery Document must enable complete project recovery.
5. Never Leave Critical Knowledge Only in Chat
If knowledge affects the project, it belongs in the Recovery Document.
6. Document Before Moving On
Complete documentation of the current work before beginning unrelated work. Avoid leaving undocumented systems.
7. Update Continuously
The Recovery Document is a living engineering artifact. It evolves whenever the project evolves.
8. Record Every Decision
Every significant decision should record the decision, reason, date, impact, and dependencies.
9. Preserve Rejected Ideas
Rejected solutions are project knowledge. Record what was proposed, why it was rejected, and what replaced it.
10. Verify Before Documenting
Do not assume. Whenever possible verify against source code, repository, database, API, or existing documentation.
11. Organize by System
Do not organize by conversation. Organize by subsystem such as authentication, administration, billing, fleet, reporting, scheduling, and notifications.
12. Separate Knowledge Levels
Document information at three levels: business knowledge, system knowledge, and technical knowledge.
13. Preserve Traceability
Every significant feature should trace back to a business requirement, design decision, implementation, and testing approach.
14. Document Dependencies
Every subsystem should identify what it depends on and what depends on it.
15. Recovery Must Be Possible
Another AI or developer should be able to continue using only the Recovery Document and the source repository. No previous conversations should be required.
16. Record Project State
Maintain current phase, current task, completion percentage, outstanding work, known issues, and next recommended task.
17. Maintain Source Inventory
Maintain an inventory of repositories, conversation exports, specifications, design documents, databases, reference material, and external resources.
18. Every Session Ends With Continuity
Before ending work, update the Recovery Document, Decision Log, Change Log, Current Project Status, unfinished work, and next recommended task.
19. Write for Replacement
Always assume another AI or developer may replace the current contributor tomorrow. Write so they never need to ask, “What were they thinking?”
20. Completion Standard
The Recovery Document is complete only when another competent engineer or AI can understand the business, understand the system, understand the implementation, continue development, maintain the project, and extend the project without previous conversations.
21. Recovery Document as Project Artifact
The Recovery Document is maintained with the same discipline as source code. Updating one without the other constitutes an incomplete change.
22. Self-Maintenance Rule
The AI is responsible for maintaining the Recovery Document. The user should not have to remind the AI to update it. Maintaining project knowledge is part of the work.
23. Definition of Done
A task is complete only when the software reflects the change, the Recovery Document reflects the change, the Decision Log is updated, the Change Log is updated, Current Project Status is updated, Outstanding Work is updated, and the next task is recorded.
24. Session Start Protocol
At the beginning of every session, read the Recovery Document, review Current Project Status, Decision Log, Outstanding Work, previous session notes, and Current Task. Confirm understanding before beginning work.
25. Session End Protocol
Before ending, record all decisions, synchronize the Recovery Document, update project status, record unfinished work, record the recommended next task, and verify project continuity.
26. Recovery Gate
Before beginning substantial new work ask: Is the Recovery Document current? If not, updating it becomes the highest documentation priority.
27. Daily Refresh Rule
Every work session begins with a Recovery Document refresh. Never rely on remembered conversation when a Recovery Document exists.
28. Knowledge Preservation Rule
Knowledge should evolve, not disappear. When implementation changes, document the new implementation while preserving significant historical decisions and reasons.
29. Successor AI Protocol
An incoming AI is not beginning a new project. It is inheriting an existing one. Its first responsibility is understanding. Improvement comes after understanding.
30. Preserve Before Improve
Never redesign before understanding business goals, architecture, history, dependencies, and implementation. Project continuity takes precedence over optimization.
31. Project Understanding Before Critique
Do not criticize architecture before understanding why it exists. Assume previous contributors had valid reasons until proven otherwise. Seek understanding before proposing redesign.
32. Respect Existing Architecture
Assume documented architecture is intentional. Evolution is preferred over replacement. Large redesign requires demonstrated understanding.
33. Principle of Earned Confidence
Confidence is earned through understanding. Recommendations should be based on demonstrated comprehension of business requirements, existing implementation, historical decisions, and system dependencies.
34. AI Responsibility Rule
The AI is responsible for recognizing project knowledge that belongs in the Recovery Document. The user should not have to identify missing documentation.
35. Human-Centered Language Rule
All user-facing elements should use language that matches the user’s mental model, not developer terminology. Prefer business language over internal software terms.
Examples: use “Menu” instead of “Drawer,” “Add Vehicle” instead of “Create Fleet Record,” and “Vehicle Calendar” instead of “Scheduling Interface.”
Successor AI Warning
Do not begin by telling the user why the previous AI, previous developer, or existing architecture is wrong.
A new AI session usually has less context than the previous one. Apparent problems may exist because the incoming AI has not yet understood the business reason, project history, or backend constraint behind the decision.
The first responsibility of a successor AI is to inherit the project faithfully. Read the Recovery Bible first. Understand the current design. Then, and only then, suggest improvements if they solve a real problem and preserve project intent.
An incoming AI is not appointed as the project’s architect. It is appointed as the project’s successor.
Recovery Check Trigger
If the user says “Recovery check”, the AI must stop new development and verify that the Recovery Bible is current. The AI should update the Bible if needed before continuing.
Clickable Table of Contents
1.
Recovery Bible Operating Notice
2.
Universal AI Project Continuity Protocol
3.
Successor AI Warning
4.
Recovery Check Trigger
5.
Operating Rule for Future AI Chats
6.
Executive Summary
7.
Current Project State
8.
Source Material Harvested
9.
Drift Detection and Corrected Direction
10.
Product Definition
11.
Out of Scope / Explicit Non-Goals
12.
System Architecture
13.
Backend Architecture
14.
Frontend Vision
15.
Calendar-First Operating Model
16.
Core Workflows
17.
Authentication, MFA, Sign-In, and Security
18.
Admin Console
19.
User Roles and Permissions
20.
Dashboard
21.
Vehicles and Fleet Rules
22.
Reservations and Availability Engine
23.
Case Lifecycle
24.
Billing and Warranty
25.
Notes, Audit, Notifications, Conflicts
26.
Connectivity, Identities, Hosting, and Repositories
27.
Frontend Build Strategy
28.
Rules for Working With Dave
29.
Development Workflow
30.
Known Backend Inventory
31.
Open Questions
32.
Next Build Priorities
33.
Change Log
34.
Appendix A - Tables
35.
Appendix B - Views
36.
Appendix C - Function Families
Operating Rule for Future AI Chats
Any AI or developer joining this project must start by treating this document as the current working memory. Do not assume the current chat contains enough context. Do not rebuild old decisions from scratch. Do not simplify the system into a generic rental app, CRM, or reservation app.
The core project is a Transportation Management System for dealership rental/loaner operations. It is backend-driven, case-driven, vehicle-calendar-driven, permission-controlled, and audit-oriented.
Executive Summary
The Stanley TMS is intended to manage dealership transportation operations across rental vehicles, loaner vehicles, reservations, cases, billing calculations, warranty reimbursement, fleet availability, conflicts, notes, audit logs, notifications, user administration, and controlled actions.
The most important architecture rule is:
The case is the lifecycle root.
In database terms, that means transportation_events owns lifecycle. Vehicles, reservations, billing lines, warranty records, notes, and conflicts connect back to the case. The system must never treat a reservation, vehicle, billing line, or warranty record as the lifecycle owner.
The operating vision has evolved from a conventional dashboard-first app into a calendar-first fleet timeline system. Staff should be able to look at a vehicle/time grid and act from there. Clicking a vehicle slot should open context-aware actions rather than forcing users to hunt through separate forms.
Current Project State
Confirmed Completed Infrastructure
•
Supabase backend exists and has been backed up to GitHub.
•
GitHub repository exists: DaveStackDevs2/Stanleyincfleetmanagement.
•
Supabase CLI was installed and authenticated on the work PC.
•
Docker Desktop and WSL were installed and made operational.
•
supabase db pull successfully created a full migration snapshot.
•
Migration history was synchronized.
•
Repository structure now includes:
Stanleyincfleetmanagement README.md├── schema.sql├── functions_export.sql├── triggers_export.sql├── views_export.sql├── policies.sql├── extensions_export.sql├── supabase_project_config.md├── supabase/└── config.toml├── migrations/└── 20260702160608_remote_schema.sql└──
Confirmed Backend Snapshot
The current pulled migration contains:
•
55 tables
•
11 views detected in the main migration parser pass
•
217 database functions
The SQL exports also contain dedicated backups for schema, functions, triggers, views, RLS policies, and extensions.
Source Material Harvested
This Project Bible is based on the following source families:
•
DATABASE_MAPPING_MASTER.txt
•
PROJECT_EXECUTION_MASTER.txt
•
PROJECT_TASKS_COMPLETED.txt
•
PROJECT_CURRENT_STATUS.txt
•
ADMIN SETTINGS RULES.txt
•
AUTHENTICATION SECURITY RULES.txt
•
NOTES AND AUDIT RULES.txt
•
NOTIFICATION SYSTEM RULES.txt
•
PERMISSIONS ENFORCEMENT RULES.txt
•
SERVICE ACTION CONTROL RULES.txt
•
Copilot conversation 01.txt
•
Copilot conversation 02.txt
•
copilortconversation 1.txt
•
New Text Document (3).txt
•
ChatGPT export zip
•
Stanleyincfleetmanagement-main.zip
•
Current ChatGPT working conversation
Important note: The previous partial handoff document was insufficient. It missed major areas such as Admin Console, Dashboard, MFA, roles, sign-in policy, and service-action runtime thinking. This version is intended to correct that by harvesting the old conversations and the backend files together.
Drift Detection and Corrected Direction
Confirmed Development Direction
The following are real project direction and should be preserved:
•
Backend-first architecture.
•
Supabase as primary database/backend.
•
transportation_events as lifecycle root.
•
Frontend should call controlled views/functions/service actions rather than making uncontrolled direct mutations.
•
Calendar/timeline should become the main operating surface.
•
Billing calculations remain in scope, but payment processing/accounting integration does not.
•
Warranty logic remains in scope.
•
Admin, authentication, MFA, roles, permission controls, audit, notifications, and service contracts remain in scope.
•
GitHub is the code/source-control home.
•
Squarespace remains the public web presence; the TMS may be linked from it or integrated around it.
Detected Drift
The following were drift or misunderstandings and should not be carried forward uncritically:
•
Treating the product as a generic CRM.
•
Treating the product as a simple rental app.
•
Removing billing/warranty logic just because accounting/payment collection was removed.
•
Assuming Lovable should invent schema, demo data, or business workflow.
•
Asking Dave to endlessly copy/paste SQL chunks instead of using repository/file exports.
•
Evaluating Appsmith/Retool only as if this were a generic internal tool, without respecting Squarespace portability and code ownership needs.
•
Treating calendar as a secondary display instead of a primary operating surface.
Corrected Direction
The project should proceed as a portable web application with Supabase as backend, GitHub as source of truth, and a frontend built to match the calendar-first workflow. Whether the frontend is produced by a builder, manual code, or hybrid tooling, it must remain portable and must not trap the business inside a no-code platform that cannot later be moved or hosted appropriately.
Product Definition
What We Are Building
A Dealership Transportation Management System for managing rental and loaner fleet operations.
It exists to:
•
Track vehicle availability.
•
Manage loaner and rental usage.
•
Manage reservations and quotes.
•
Create and operate case lifecycle records.
•
Track current vehicle assignment and vehicle history.
•
Support swaps, returns, renewals, extensions, and continuation workflows.
•
Calculate billing and warranty responsibility.
•
Preserve notes and audit history.
•
Surface conflicts, overdue activity, and warnings.
•
Enforce permissions and authentication.
•
Support admin configuration.
•
Provide dashboard visibility.
•
Prepare operational data for Tekion updates where needed.
What It Is Not
•
Not a CRM.
•
Not a payment collection system.
•
Not an accounting integration.
•
Not a generic appointment scheduler.
•
Not a standalone static Squarespace page.
•
Not a system where Lovable or any frontend builder is allowed to invent lifecycle logic.
Out of Scope / Explicit Non-Goals
These points were clarified in past conversations and should not be reintroduced without explicit owner approval:
•
No accounting system integration.
•
No payment processing or customer payment collection inside the app.
•
No customer signature workflow in this app; customer rental contracts/signatures are handled through OnTrac/GM contract workflow.
•
No per-use customer fuel tracking.
•
No per-use customer mileage tracking for charging purposes.
•
No customer damage tracking workflow unless later reintroduced.
•
No replacing Tekion.
•
No uncontrolled direct frontend mutation of critical lifecycle tables.
The app may still calculate internal billing, tax, warranty, GM reimbursement, extended-warranty coverage, late fees, and operational totals. Removing accounting/payment does not remove billing calculations.
System Architecture
High-Level Architecture
Squarespace public site link/button↓TMS web application frontend Supabase client / RPC calls↓Supabase Auth + PostgreSQL backend controlled functions/views/contracts↓Transportation lifecycle engine
Core Architecture Rules
•
All lifecycle activity centers on transportation_events.
•
Vehicles are assigned through assignment/history structures, not by simply editing a vehicle row.
•
Current vehicle assignment comes from active_vehicle_assignments.
•
Vehicle history comes from vehicle_events.
•
Billing is multi-line, multi-period, and multi-vehicle capable.
•
Notes are append-only.
•
Audit records must explain critical changes.
•
Conflicts must remain visible until explicitly resolved.
•
Permissions must be enforced beyond the frontend.
Backend Architecture
Backend Role
The backend is not just storage. It contains a large part of the system’s business logic, state evaluation, and orchestration.
The backend currently includes engines/areas for:
•
Case lifecycle.
•
Vehicle lifecycle.
•
Reservation availability.
•
VIN assignment and hard-lock dependencies.
•
Soft-lock candidate selection.
•
Billing and contract periods.
•
Extended warranty day ledger.
•
GM warranty rates.
•
Late fee rules.
•
Pay type rules.
•
Admin settings.
•
Authentication security policy.
•
MFA lifecycle events.
•
Network access gates.
•
User administration.
•
Roles and permissions.
•
Service action contracts.
•
Dashboard payloads.
•
Warning center.
•
Email outbound messages and provider webhooks.
•
QR/scan session handling.
•
Notification queues/logs.
•
Audit logging.
Service Action Backbone
The backend includes a service_action_contracts table and functions such as:
•
get_service_action_contract_catalog_state
•
get_frontend_safe_service_action_contracts_state
•
get_service_action_contract_state
The confirmed service action contract catalog includes action groups such as:
•
auth
•
case
•
customer
•
dashboard
•
email
•
reservation
•
transportation_event
•
user_admin
•
vehicle
This is critical because the frontend should not freely decide how to mutate data. It should discover or be coded to use approved actions.
Frontend Vision
The frontend should be a serious operations interface. It should not feel like a generic CRM.
Main Operating Principle
Fleet calendar first. Cases and records open from the calendar/timeline when possible.
Primary Screens
•
Fleet Calendar / Vehicle Timeline.
•
Dashboard.
•
Cases / Case Detail.
•
Vehicles / Vehicle Detail.
•
Quotes and Reservations.
•
Billing.
•
Warranty.
•
Conflict Center / Warning Center.
•
Notes and Activity.
•
Admin Console.
•
Notifications.
UI Identity Rules
Vehicles must display:
•
Stock number first.
•
Model second.
•
Fleet type as constraint/context.
Vehicles must not display VIN as the primary user-facing identifier, and the frontend must not rely on vehicle_class as an identity concept.
Calendar-First Operating Model
The calendar should not merely show data. It should be an interaction surface.
Fleet Timeline Layout
Rows should represent vehicles. Time columns should represent dates/times. Timeline blocks should represent:
•
Active rental/loaner use.
•
Reservations.
•
Quotes or pending holds.
•
Dependency locks.
•
Conflicts.
•
Overdue cases.
•
Maintenance/out-of-service blocks if later enabled.
Empty Slot Click
When a user clicks an empty vehicle/date/time slot, the menu should offer context-aware options such as:
•
Create Walk-in Rental.
•
Create Walk-in Loaner.
•
Create Quote.
•
Create Reservation.
The selected vehicle and selected date/time context must be carried into the correct workflow.
Occupied Slot Click
When a user clicks an existing assignment/reservation/case block, the menu should offer actions such as:
•
Open Case.
•
Extend expected return.
•
Return vehicle / complete case.
•
Swap vehicle.
•
Continue same vehicle.
•
Open billing context.
•
Add note.
•
View conflict/dependency.
Critical Calendar Rule
The calendar must not directly modify lifecycle state. Calendar actions must route into backend-controlled workflows/service actions.
Core Workflows
Walk-in Rental
Purpose: start a retail rental directly from vehicle/date context.
Expected flow:
1.
User selects vehicle/time slot.
2.
System confirms fleet eligibility.
3.
User enters customer details and rental terms.
4.
Backend creates case, assignment, contract period, billing line(s), notes/audit as required.
5.
Calendar updates from backend state.
Walk-in Loaner
Purpose: start a loaner from vehicle/date context.
Rules:
•
Loaner case must have RO number.
•
Without RO number, system must prevent loaner assignment.
•
Loaner fleet may only be used for loaner use, not public rental.
•
Rental fleet may be used for rental and, if allowed, loaner use.
Quote
Purpose: planning/intake only; does not create active lifecycle case until converted.
Reservation
Purpose: planned future use.
The reservation system is planning/intake. It must not become lifecycle owner. Final assignment and case lifecycle must still flow through transportation events and controlled actions.
Availability Request
User enters:
•
vehicle use type,
•
requested start date/time,
•
projected end date/time,
•
optional model/fleet preferences,
•
customer and RO context as needed.
System evaluates:
•
eligible fleet,
•
time-window conflicts,
•
existing reservations,
•
active vehicle events,
•
out-of-service or policy constraints,
•
dependencies/locks.
System returns:
•
available vehicles,
•
recommended vehicle(s),
•
conflicts,
•
next available alternatives.
Authentication, MFA, Sign-In, and Security
Confirmed Design Intent
Authentication is required before app access. The backend contains auth/security tables and functions, including app_user_security, user_auth_security_events, approved network logic, MFA event recording, and auth access gate functions.
Password Policy
Existing rules specify:
•
email + password login,
•
minimum password length,
•
uppercase/lowercase/symbol requirements,
•
failed login tracking,
•
lockout after failed attempts,
•
disabled state after post-lockout failure,
•
admin reset ability,
•
temporary password expiry,
•
forced password change when required,
•
optional email reset depending on policy,
•
network restriction support.
MFA
MFA is part of the backend/security design. The service action catalog includes auth/MFA-related actions such as:
•
access gate evaluation,
•
auth policy read,
•
MFA lifecycle event recording,
•
AAL2 requirement support in service action contracts.
Important: Supabase Auth may provide MFA capability, but the app-level backend also contains policy/orchestration records. Future frontend must not assume basic login is enough. It must respect app-level access gate state and AAL2/MFA requirements.
Sign-In Flow Concept
The app must always open to the sign-in page first. No dashboard, calendar, vehicle list, admin console, or operational data should load before authentication and access-gate evaluation.
Expected frontend flow:
1.
User lands on sign-in page.
2.
User enters email/password.
3.
Supabase Auth verifies identity.
4.
App calls backend access-gate logic.
5.
Backend returns one of:
–
allow access,
–
require MFA enrollment,
–
require MFA challenge,
–
locked out,
–
disabled,
–
outside approved network,
–
password reset required.
6.
If allowed, the app detects the user’s roles, permissions, and remembered dashboard preferences.
7.
The user is routed to the correct post-login dashboard/calendar experience for their role.
Post-Login Visibility Rule
After sign-in, the app must only reveal screens, navigation items, dashboard widgets, calendar actions, admin tools, and service actions that the current user is permitted to access. The frontend may hide inaccessible options for usability, but the backend/service-action layer remains the enforcement authority.
Admin Console
The Admin Console is a required module, not optional polish.
Admin Areas
•
User management.
•
Role assignment.
•
Permission visibility.
•
Password reset packages.
•
Lockout clearing.
•
MFA/security policy view and management.
•
Admin settings.
•
Notification settings.
•
Feature toggles.
•
Tax rate and policy configuration.
•
Warranty provider/rule configuration.
•
Late fee rule configuration.
•
Pay type rules.
•
Network restrictions and approved networks.
•
Master vehicle list administration.
•
CTP fleet membership management.
•
Vehicle retirement from CTP.
•
Vehicle stock number correction/change.
•
Vehicle fleet type conversion, including rental to loaner and loaner to rental, where permitted.
Master Vehicle List Administration
The backend stores the master vehicle list. The Admin Console must expose controlled tools for authorized users to maintain that list without bypassing lifecycle, audit, and permission rules.
Required admin vehicle actions include:
•
Add vehicle to CTP.
•
Retire vehicle from CTP.
•
Change/correct stock number.
•
Change fleet type, including rental to loaner or loaner to rental.
•
Maintain VIN as immutable backend identity unless a correction process is explicitly defined.
•
Capture reason, actor, timestamp, old value, and new value for meaningful changes.
•
Prevent unauthorized edits from normal operational screens.
Admin Tables / Backend Areas
Relevant backend structures include:
•
admin_settings
•
admin_setting_permissions
•
app_users
•
app_user_security
•
roles
•
permissions
•
user_roles
•
role_permissions
•
approved_networks
•
user_auth_security_events
•
service_action_contracts
Admin Rule
Critical settings must require appropriate permission. Changes must be audited. Admin UI must not be the only enforcement layer.
User Roles and Permissions
Role System
The backend includes roles and permissions. The design requires permissions at:
•
UI visibility level,
•
service/action execution level,
•
backend/database level.
Known Role Concepts
•
Dev: full system access.
•
Admin: full system access except AI interaction if that distinction remains.
•
Service Manager: restricted from rental pricing control.
•
Other roles to be defined by permission mapping.
Permission Enforcement Rule
No action may execute without user context and permission validation. The frontend may hide actions, but backend enforcement is mandatory.
Dashboard
The Dashboard is a required high-level operational view.
Dashboard Backend
The backend includes dashboard functions such as:
•
get_master_operational_dashboard_state
•
get_dashboard_payload_state
•
get_dashboard_section_access_state
•
get_case_candidate_dashboard_state
•
get_operational_domain_counts_state
•
get_warning_center_counts_state
•
get_utilization_snapshot_state
Dashboard Content
The dashboard should show:
•
active cases,
•
overdue vehicles,
•
reservations needing VIN assignment,
•
conflicts/dependencies,
•
warranty alerts,
•
warning center counts,
•
fleet utilization,
•
available vehicles,
•
vehicles out,
•
upcoming returns,
•
lost rentals summary,
•
admin/security warnings for authorized users.
Dashboard Rule
Dashboard widgets must be permission-aware. Users should only see data and actions they are allowed to access.
After sign-in, the dashboard must be loaded from role/permission context and remembered user preferences where available. The dashboard is not one universal layout for every user; it is a controlled landing surface. From the dashboard, users may navigate to anything they have permission to navigate to. If a user does not have permission for a feature, it should not appear as a usable navigation option.
Vehicles and Fleet Rules
Vehicle Identity
Backend identity:
•
VIN is true identity.
Frontend identity:
•
stock number is primary visible ID,
•
model is secondary,
•
fleet type is operational constraint.
Vehicle Table Fields
The vehicles schema includes fields such as:
•
id
•
vin
•
stock_number
•
model
•
fleet_type
•
status
•
mileage
•
recon_status
•
current_tag
•
fleet_conversion_type
•
location
•
notes
Fleet Type Rules
•
Rental vehicles may be used for public rentals and possibly loaner use where policy allows.
•
Loaner vehicles may only be used for loaner use and not public rental.
•
Loaner assignment requires RO number.
CTP / Monitoring
Backend contains CTP monitoring policies and functions, including preferred max days/miles settings. This should feed dashboard/warning center behavior.
Master Vehicle List and Fleet Lifecycle
The vehicle list is a controlled backend master list, not a casual editable UI table. Vehicle administration must support:
•
adding a vehicle to CTP,
•
retiring/removing a vehicle from CTP,
•
changing/correcting stock number,
•
changing fleet type between rental and loaner where business rules allow,
•
preserving VIN as the true backend identity,
•
recording audit history for all meaningful changes.
Changing a vehicle from rental to loaner or loaner to rental is not just a display edit. It changes operational eligibility and must be handled as a permissioned backend action.
Reservations and Availability Engine
Reservations are planning/intake, not lifecycle authority.
VIN Assignment / Locking
Past backend work built support for:
•
reservations needing VIN assignment,
•
VIN-lock lead days,
•
hard-lock dependency integration,
•
reservation vehicle assignment with dependency state,
•
clearing assignment with dependency resolution.
Relevant objects include:
•
v_reservation_assignment_state
•
v_reservations_needing_vin_assignment
•
get_reservations_needing_vin_assignment_state
•
assign_reservation_vehicle_with_hard_lock_state
•
clear_reservation_vehicle_assignment_with_dependency_state
•
reservation_vehicle_dependencies
Availability Evaluation
The system must check time windows, not just vehicle status. A vehicle is available only if it is free for the entire requested period and passes fleet/policy constraints.
Case Lifecycle
Lifecycle Owner
transportation_events owns lifecycle.
Supporting Tables
•
active_vehicle_assignments for current vehicle.
•
vehicle_events for assignment history.
•
contract_periods for time segments.
•
billing_lines for charges/calculation lines.
•
transportation_event_notes for notes.
•
transportation_event_state_history for state changes.
Important Actions
The backend includes case action functions for:
•
create/start/bill/load,
•
complete/return/close/load,
•
cancel/load,
•
continue same vehicle/load,
•
reassign active case/load,
•
accept extension/load,
•
unified payload retrieval.
Case UI
Case detail should show:
•
header,
•
current vehicle,
•
status,
•
customer,
•
expected return,
•
billing summary,
•
tabs for vehicles, billing, notes, activity, conflicts, warranty.
Billing and Warranty
Billing Purpose
The app calculates billing, warranty responsibility, taxes, late fees, and totals. It does not collect payment and does not integrate with accounting.
Billing Rules
•
Rentals are retail only and must include tax.
•
GM warranty has no tax.
•
Extended warranty has defined coverage days.
•
When coverage ends, current billing line must end and a new taxable segment must begin.
•
Coverage applies to the case across all vehicles, not per individual vehicle.
•
Billing must support multiple lines, vehicles, and periods.
•
Billing data must not be flattened.
Tables
•
billing_lines
•
billing_event_totals
•
contract_periods
•
gm_warranty_rates
•
extended_warranty_rules
•
warranty_day_ledger
•
warranty_providers
•
late_fee_rules
•
pay_type_rules
Notes, Audit, Notifications, Conflicts
Notes
Notes belong to transportation events and are append-only.
Required note areas:
•
general case note,
•
estimated/expected return change note,
•
billing note.
When expected return changes, a note must capture old value, new value, and reason code.
Audit
Critical changes must create audit records, including:
•
status changes,
•
assignment changes,
•
billing adjustments,
•
permission changes,
•
admin setting changes.
Notifications
Notifications inform users about:
•
conflicts,
•
overdue vehicles,
•
billing issues,
•
warranty alerts,
•
system events.
Notifications must respect permissions and cooldowns.
Conflicts / Warning Center
Conflicts must be visible and must not silently resolve. The warning center/dashboard should surface critical, warning, and review items.
Connectivity, Identities, Hosting, and Repositories
Known Accounts / Identifiers
•
Supabase project name shown during setup: davey@stanleyme.com's Project.
•
Supabase project ref: ycwejunodgnnkickjvsk.
•
Supabase region: us-east-1.
•
GitHub repository: DaveStackDevs2/Stanleyincfleetmanagement.
•
Work email identity mentioned: davey@stanleyme.com.
•
Local Windows profiles encountered: StanleyAdmin and DaveYoung.
•
Lovable project seen in UI: CaseFlow Navigator.
•
Earlier intended Lovable name: Stanley Fleet Management.
Squarespace / Website Context
Squarespace is the public-facing site environment. The TMS should be built so it can be linked from Squarespace or otherwise integrated without being trapped inside a proprietary builder.
The TMS should likely live as a separate application behind login, reachable from a Squarespace button/menu link.
Important correction from Dave: there was specific owner-provided Squarespace/web-address information passed into earlier Copilot conversations. The current harvested Bible does not yet contain the exact Squarespace URL/domain/web-address details. Future updates must harvest and record those exact values rather than leaving this section generic. Do not invent the domain structure.
Email Identity and Provider Context
Known current work identity: davey@stanleyme.com.
The backend includes email-related structures for outbound message queueing and provider webhook recording. However, Dave has stated that specific email identity/provider information was given in prior Copilot discussion and should be included. The current document must treat exact email provider identity, sending domain, mailbox ownership, and provider integration details as not yet fully harvested/confirmed until the relevant source text is located.
Hosting Cost Concern
Vercel may be convenient but cost concerns exist because another business project reportedly became expensive. The frontend should therefore avoid platform-specific hosting dependencies and remain portable.
Frontend Build Strategy
Current Strategic Direction
Do not continue relying on Lovable as the primary long-term builder without a strong reason. Lovable drifted, created UI assumptions, and GitHub syncing was not available/working in the current project context.
Tool Requirement
The frontend should be created in a way that:
•
can be stored in GitHub,
•
can be hosted outside the builder,
•
can connect to Supabase,
•
can be linked from Squarespace,
•
can support a sophisticated calendar/timeline UI,
•
can enforce backend-driven workflows,
•
does not require repeated paid/limited AI prompt cycles for normal maintenance.
Candidate Direction
A portable web app frontend remains the strongest technical fit. The specific tooling can be decided, but the requirement is portable code ownership, not a locked-in builder.
Rules for Working With Dave
These are mandatory collaboration rules harvested from the current and prior workflow:
•
Give one step at a time when asking Dave to perform app/CLI/web actions.
•
Do not provide five options when one recommendation is clearly best.
•
Do not drift into long background explanations during hands-on setup.
•
Stay focused on the current task.
•
Explain what we are doing, why it matters, and how it shows progression.
•
Do not call this a CRM.
•
Do not treat Dave as a programmer.
•
Dave is product owner and workflow/business rules authority.
•
The assistant/developer is responsible for technical implementation, prompts, SQL, architecture, and full-stack engineering decisions.
•
Do not use Lovable prompts for discovery.
•
Do not let frontend tools invent backend logic.
•
Do not ask Dave to paste hundreds of lines repeatedly when file upload or repo export is available.
•
Be honest about uncertainty.
•
Detect and call out drift.
•
Update this Project Bible after meaningful decisions or completed work.
•
Do not end sessions with only abstract discussion; each work session should produce a measurable artifact, decision, or completed step.
Development Workflow
Source of Truth
GitHub and this Project Bible must become the working source of truth.
Backend Workflow
1.
Inspect current schema/function state.
2.
Plan SQL or backend change.
3.
Apply only controlled changes.
4.
Verify with targeted queries.
5.
Pull/update schema snapshot when appropriate.
6.
Commit/save to GitHub.
7.
Update Project Bible.
Frontend Workflow
1.
Define exact screen/workflow.
2.
Identify backend data sources/functions.
3.
Build the screen or generate a tightly constrained prompt.
4.
Test behavior.
5.
Save source to GitHub.
6.
Update Project Bible.
Known Backend Inventory
Database Tables by Domain
•
Lifecycle/cases: transportation_events, transportation_event_state_history, transportation_event_notes.
•
Vehicles: vehicles, active_vehicle_assignments, vehicle_events, vehicle_swaps, vehicle_stock_history, vehicle_tags, vehicle_qr_codes, vehicle_scan_events, vehicle_scan_sessions.
•
Reservations/quotes: reservations, quotes, reservation_conflicts, reservation_vehicle_dependencies.
•
Billing/warranty: billing_lines, billing_event_totals, contract_periods, gm_warranty_rates, extended_warranty_rules, warranty_cases, warranty_day_ledger, warranty_alerts, warranty_providers, pay_type_rules, late_fee_rules.
•
Users/security: app_users, app_user_security, user_auth_security_events, roles, permissions, user_roles, role_permissions, app_user_reset_tokens, approved_networks.
•
Admin/service/contracts: admin_settings, admin_setting_permissions, service_action_contracts.
•
Notifications/email: notifications, notification_rules, notification_log, notification_delivery_queue, notification_recipients, email_outbound_messages, email_provider_webhook_events.
•
Operations/reporting: lost_rentals, engine_runs, fleet_policies, rental_model_limits, customer_preferences, tags.
Open Questions
These need later confirmation before final build decisions:
•
Exact frontend stack/tool to use for portable app generation.
•
Exact hosting strategy after avoiding high Vercel-cost risk.
•
Whether the current Lovable project should be abandoned, exported, or used only as visual reference.
•
Final role/permission matrix for all staff roles.
•
Final dashboard widget order and permission filtering.
•
Exact Squarespace URL/domain/subdomain structure, including the owner-provided information Dave says was passed to Copilot.
•
Exact email provider, sending identity, mailbox/domain setup, and any provider-specific constraints previously given to Copilot.
•
Email provider choice for outbound messages and password reset flow.
•
Tekion update workflow: manual entry vs import/export vs future API integration.
•
Whether QR scan workflows are required in the first release.
•
Whether CTP monitoring thresholds are final.
Next Build Priorities
1.
Complete this Project Bible and use it as the reset point.
2.
Perform backend audit against GitHub migration/functions.
3.
Produce a frontend build decision memo focused on portability, Squarespace linking, cost, and calendar timeline capability.
4.
Define MVP frontend screens:
–
Sign-in/access gate.
–
Fleet Calendar/Timeline.
–
Dashboard.
–
Case detail.
–
Vehicle detail.
–
Reservation/availability request.
–
Admin console basics.
5.
Build first working screen against read-only backend payloads.
6.
Add controlled write actions only after read screens are stable.
Final Recovery Audit - v1.0 Baseline
Status: Complete for baseline recovery.
This version has been audited against the known source material available in this work session:
•
Current ChatGPT conversation
•
Original ChatGPT export ZIP
•
Copilot Conversation 01
•
Copilot Conversation 02
•
Supabase/GitHub backend snapshot
•
Project rule files and database mapping documents
•
Prior Project Bible drafts
The audit found no remaining known high-level project recovery gap that should block using this document as the baseline handoff for future TMS work.
Baseline Recovery Scope
This baseline captures:
•
What the TMS is and is not
•
Why it exists
•
How it should be continued by a future AI
•
How the Recovery Bible must be maintained
•
Backend-first architecture
•
Calendar-first operating model
•
Authentication/MFA/permission expectations
•
Admin console expectations
•
Dashboard expectations
•
Master Vehicle List expectations
•
Case lifecycle orientation
•
Vehicle/reservation/rental/loaner/billing/reporting scope
•
Email, Squarespace, GitHub, and Supabase context
•
Known backend inventory
•
Open items and next build priorities
Remaining Work After v1.0
Remaining work is no longer recovery work. It is implementation and ongoing specification maintenance:
•
Expand subsystem sections as each frontend screen is built.
•
Add exact UI screenshots/wireframes once available.
•
Update backend references when new migrations are added.
•
Replace any “needs confirmation” items when the user provides missing external details.
•
Update this Recovery Bible at the end of every significant work session.
Change Log
2026-07-03 - Recovery Bible v1.0 Baseline
•
Added Universal AI Project Continuity Protocol.
•
Added Successor AI Protocol and Project Understanding Before Critique rule.
•
Added Recovery Gate, Daily Refresh Rule, Recovery Check trigger, and Self-Maintenance requirements.
•
Clarified that the Recovery Bible is maintained like source code and is part of the Definition of Done.
•
Completed baseline recovery audit and marked the document ready for future AI handoff.
2026-07-03 - Added Dave correction package
Dave reviewed the first Project Bible and identified missing product-critical areas. This update adds or reinforces: opening to sign-in page, role/permission detection after sign-in, remembered dashboard preferences, dashboard navigation permissions, calendar as primary tool for Dave/CTP staff, master vehicle list administration, CTP add/retire lifecycle, stock number changes, rental/loaner fleet type conversion, and explicit open items for exact Squarespace and email provider details that must be harvested rather than guessed.
2026-07-03
•
Created expanded Project Bible after user identified omissions in earlier handoff.
•
Included admin console, dashboard, sign-in policy, MFA, user roles, service action backbone, and calendar-first workflow.
•
Added drift-detection section to separate true design from prior AI drift.
•
Added source inventory and current infrastructure state.
Appendix A - Tables
•
active_vehicle_assignments
•
admin_setting_permissions
•
admin_settings
•
app_user_reset_tokens
•
app_user_security
•
app_users
•
approval_actions
•
approved_networks
•
audit_log
•
billing_event_totals
•
billing_lines
•
contract_periods
•
customer_preferences
•
customers
•
email_outbound_messages
•
email_provider_webhook_events
•
engine_runs
•
extended_warranty_rules
•
fleet_policies
•
gm_warranty_rates
•
late_fee_rules
•
lost_rentals
•
notification_delivery_queue
•
notification_log
•
notification_recipients
•
notification_rules
•
notifications
•
pay_type_rules
•
permissions
•
quotes
•
rental_model_limits
•
reservation_conflicts
•
reservation_vehicle_dependencies
•
reservations
•
role_permissions
•
roles
•
service_action_contracts
•
tags
•
transportation_event_notes
•
transportation_event_state_history
•
transportation_events
•
user_auth_security_events
•
user_roles
•
vehicle_events
•
vehicle_qr_codes
•
vehicle_scan_events
•
vehicle_scan_sessions
•
vehicle_stock_history
•
vehicle_swaps
•
vehicle_tags
•
vehicles
•
warranty_alerts
•
warranty_cases
•
warranty_day_ledger
•
warranty_providers
Appendix B - Views
•
v_auth_security_policy_state
•
v_ctp_monitoring_policy_state
•
v_email_outbound_message_state
•
v_email_webhook_event_history
•
v_service_action_contract_state
•
v_user_auth_entry_orchestration_state
•
v_user_auth_security_event_history
•
v_vehicle_ctp_monitoring_state
•
v_vehicle_qr_action_entry_state
•
v_vehicle_scan_event_history
•
v_vehicle_scan_session_history
Appendix C - Function Families
Auth / MFA / Login / Reset
•
begin_admin_password_reset_state
•
clear_password_reset_pending_state
•
complete_password_reset_db_state
•
consume_reset_token_state
•
create_approved_network_state
•
create_reset_token_state
•
ensure_app_user_security_row
•
ensure_user_security_state
•
get_approved_network_match_state
•
get_approved_networks_state
•
get_auth_security_policy_state
•
get_login_network_gate_state_by_email
•
get_network_gate_state
•
get_reset_link_network_gate_state
•
get_reset_token_validity_state
•
get_security_admin_settings_state
•
get_user_auth_access_gate_state
•
get_user_auth_access_gate_state_by_email
•
get_user_auth_security_event_history_state
•
get_user_login_precheck_state_by_email
•
get_user_outside_network_access_state
•
get_user_reset_artifact_state
•
get_user_reset_entry_state_by_email
•
get_user_security_detail_state
•
invalidate_reset_tokens_for_user_state
•
issue_admin_password_reset_package_state
•
issue_new_user_password_setup_package_state
•
record_failed_login_attempt
•
record_successful_login
•
record_user_auth_security_event_state
•
record_user_mfa_event_state
•
set_approved_network_active_state
•
set_email_password_reset_link_enabled_state
•
set_mfa_required_for_all_users_state
•
set_network_restriction_enabled_state
•
set_user_outside_network_access_state
•
update_approved_network_state
Admin / Users / Roles / Permissions
•
add_user_role_state
•
assign_user_role_by_name_state
•
create_app_user_state
•
create_app_user_with_role_state
•
create_approved_network_state
•
ensure_app_user_security_row
•
get_admin_setting_permission_requirement_state
•
get_admin_settings_catalog_state
•
get_approved_network_match_state
•
get_approved_networks_state
•
get_permissions_catalog_state
•
get_roles_with_permissions_state
•
get_security_admin_settings_state
•
get_user_admin_detail_payload_state
•
get_user_admin_list_payload_state
•
get_user_admin_setting_access_state
•
get_user_admin_settings_access_matrix_state
•
get_user_role_names_state
•
remove_user_role_state
•
set_approved_network_active_state
•
set_network_restriction_enabled_state
•
update_approved_network_state
Dashboard / Warning Center / Counts
•
get_case_candidate_dashboard_state
•
get_dashboard_payload_state
•
get_dashboard_section_access_state
•
get_lost_rentals_summary_state
•
get_master_operational_dashboard_state
•
get_operational_domain_counts_state
•
get_utilization_snapshot_state
•
get_warning_center_counts_state
•
get_warning_center_detail_state
Cases / Transportation Events
•
accept_case_extension_and_get_unified_payload_state
•
accept_transportation_event_extension_state
•
activate_case_billing_state
•
add_transportation_event_general_note_state
•
cancel_case_and_get_unified_payload_state
•
cancel_reservation_with_transportation_event_state
•
close_current_transportation_event_billing_line_state
•
close_transportation_event_state
•
complete_case_and_get_unified_payload_state
•
complete_case_return_and_close_state
•
continue_case_same_vehicle_and_get_unified_payload_state
•
continue_case_same_vehicle_state
•
create_and_start_case_with_vehicle_by_vin_state
•
create_case_bootstrap_state
•
create_case_bootstrap_with_vehicle_by_vin_state
•
create_reservation_with_transportation_event_state
•
create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_
•
create_start_and_bill_case_with_vehicle_by_vin_state
•
create_transportation_event_billing_line_state
•
create_transportation_event_state
•
escalate_transportation_event_dependency_to_critical_state
•
get_case_activation_list_state
•
get_case_candidate_dashboard_state
•
get_case_completion_candidate_state
•
get_case_completion_list_state
•
get_case_continuation_candidate_state
•
get_case_continuation_list_state
•
get_case_reassignment_candidate_state
•
get_case_reassignment_list_state
•
get_live_active_case_list_state
•
get_transportation_event_current_billing_state
•
get_transportation_event_current_dependency_state
•
get_transportation_event_extension_candidate_state
•
get_transportation_event_note_history_state
•
get_transportation_event_operational_list_state
•
get_transportation_event_operational_payload_state
•
get_transportation_event_state
•
get_transportation_event_unified_operational_list_state
•
get_transportation_event_unified_operational_payload_state
•
get_unified_case_payload_state
•
reassign_active_case_to_vehicle_and_get_unified_payload_state
•
reassign_active_case_to_vehicle_state
•
reopen_transportation_event_state
•
resolve_transportation_event_dependency_as_reassigned_state
•
resolve_transportation_event_dependency_as_removed_state
Reservations / Availability / Dependencies
•
accept_reservation_extension_state
•
assign_reservation_vehicle_state
•
assign_reservation_vehicle_with_hard_lock_state
•
cancel_reservation_with_transportation_event_state
•
clear_reservation_vehicle_assignment_state
•
clear_reservation_vehicle_assignment_with_dependency_state
•
close_current_reservation_billing_line_state
•
create_hard_lock_state
•
create_or_update_reservation_conflict_state
•
create_reservation_billing_line_state
•
create_reservation_for_tekion_customer_state
•
create_reservation_with_transportation_event_state
•
escalate_dependency_to_critical_state
•
escalate_reservation_dependency_to_critical_state
•
escalate_transportation_event_dependency_to_critical_state
•
get_billing_dependency_banner_state
•
get_calendar_dependency_badges_state
•
get_case_candidate_dashboard_state
•
get_case_completion_candidate_state
•
get_case_continuation_candidate_state
•
get_case_reassignment_candidate_state
•
get_current_reservation_dependency_state
•
get_reservation_assignment_state
•
get_reservation_current_billing_state
•
get_reservation_extension_candidate_state
•
get_reservation_lifecycle_list_state
•
get_reservation_lifecycle_state
•
get_reservation_operational_list_payload_state
•
get_reservation_operational_payload_state
•
get_reservation_transportation_link_payload_state
•
get_reservation_vehicle_candidates_state
•
get_reservation_vin_lock_lead_days_state
•
get_reservation_vin_lock_window_state
•
get_reservations_needing_vin_assignment_state
•
get_transportation_event_current_dependency_state
•
get_transportation_event_extension_candidate_state
•
get_upcoming_rental_dependency_feed_state
•
renew_reservation_same_vehicle_state
•
resolve_linked_conflicts_for_dependency_state
•
resolve_reservation_conflict_state
•
resolve_reservation_dependency_as_reassigned_state
•
resolve_reservation_dependency_as_removed_state
•
resolve_reservation_dependency_state
•
resolve_transportation_event_dependency_as_reassigned_state
•
resolve_transportation_event_dependency_as_removed_state
•
restart_reservation_same_vehicle_after_gap_state
•
return_reservation_vehicle_use_state
•
select_soft_lock_candidate_state
•
set_reservation_actual_return_state
•
set_reservation_billed_through_state
•
set_reservation_vin_lock_lead_days_state
•
start_reservation_vehicle_use_state
•
swap_reservation_vehicle_state
•
upsert_reservation_dependency_state
Vehicles / Fleet / QR / Scan
•
assign_reservation_vehicle_state
•
assign_reservation_vehicle_with_hard_lock_state
•
clear_reservation_vehicle_assignment_state
•
clear_reservation_vehicle_assignment_with_dependency_state
•
close_vehicle_scan_session_state
•
continue_case_same_vehicle_and_get_unified_payload_state
•
continue_case_same_vehicle_state
•
create_and_start_case_with_vehicle_by_vin_state
•
create_case_bootstrap_with_vehicle_by_vin_state
•
create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_
•
create_start_and_bill_case_with_vehicle_by_vin_state
•
create_vehicle_state
•
get_ctp_monitoring_policy_state
•
get_or_create_vehicle_state_by_vin
•
get_reservation_vehicle_candidates_state
•
get_vehicle_by_vin_state
•
get_vehicle_ctp_monitoring_list_state
•
get_vehicle_ctp_monitoring_state
•
get_vehicle_operational_aggregate_list_state
•
get_vehicle_operational_payload_state
•
get_vehicle_operational_state
•
get_vehicle_qr_action_entry_state
•
get_vehicle_scan_session_state
•
issue_vehicle_qr_code_state
•
reassign_active_case_to_vehicle_and_get_unified_payload_state
•
reassign_active_case_to_vehicle_state
•
record_vehicle_scan_event_state
•
renew_reservation_same_vehicle_state
•
renew_same_vehicle_state
•
resolve_dependencies_for_vehicle_return_state
•
restart_reservation_same_vehicle_after_gap_state
•
return_reservation_vehicle_use_state
•
return_vehicle_state
•
set_preferred_max_ctp_days_state
•
set_preferred_max_ctp_qualified_miles_state
•
set_vehicle_ctp_entry_state
•
set_vehicle_status_state
•
start_reservation_vehicle_use_state
•
start_vehicle_scan_session_state
•
start_vehicle_use_state
•
swap_reservation_vehicle_state
•
swap_vehicle_state
•
update_vehicle_core_state
Billing / Tax / Late Fees / Pay Types
•
activate_case_billing_state
•
add_billing_context_note_state
•
business_contract_days
•
close_billing_line_at_paid_through_state
•
close_billing_line_state
•
close_current_reservation_billing_line_state
•
close_current_transportation_event_billing_line_state
•
create_billing_parent_line_state
•
create_extension_billing_line_state
•
create_late_fee_rule_state
•
create_reservation_billing_line_state
•
create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_
•
create_start_and_bill_case_with_vehicle_by_vin_state
•
create_transportation_event_billing_line_state
•
ensure_tax_child_line_state
•
get_active_late_fee_rules_state
•
get_billing_dependency_banner_state
•
get_billing_rule_catalog_state
•
get_reservation_current_billing_state
•
get_transportation_event_current_billing_state
•
resolve_over_due_pay_type_default_state
•
resolve_pay_type_rule_state
•
set_late_fee_rule_active_state
•
set_late_fees_enabled_state
•
set_reservation_billed_through_state
•
update_late_fee_rule_state
Warranty
•
create_extended_warranty_rule_state
•
create_warranty_provider_state
•
resolve_extended_warranty_provider_default_state
•
set_extended_warranty_rule_active_state
•
set_warranty_provider_active_state
•
update_extended_warranty_rule_state
•
update_warranty_provider_state
Email / Notifications
•
get_email_outbound_message_state
•
get_login_network_gate_state_by_email
•
get_user_auth_access_gate_state_by_email
•
get_user_email_outbound_history_state
•
get_user_login_precheck_state_by_email
•
get_user_reset_entry_state_by_email
•
mark_email_outbound_message_failed_state
•
mark_email_outbound_message_sent_state
•
queue_email_outbound_message_state
•
record_email_provider_webhook_event_state
•
set_email_password_reset_link_enabled_state
Customers
•
create_customer_state
•
create_reservation_for_tekion_customer_state
•
get_customer_by_tekion_customer_number_state
•
get_customer_operational_aggregate_list_state
•
get_customer_operational_list_state
•
get_customer_operational_payload_state
•
get_customer_operational_state
•
get_or_create_customer_state_by_tekion
•
update_customer_state
Appendix D - How to Use This Document in a New Chat
Paste or upload this Project Bible first. Then tell the AI:
Read this Project Bible. Do not summarize it. Treat it as the current source of truth for the Stanley Transportation Management System. Ask only one clarifying question if needed. Continue from the Current Project State and Next Build Priorities.
Then provide the current task.
Appendix E - Strong Warning to Future AI
Do not flatten this system. Do not convert it into a generic CRM. Do not move backend business rules into the frontend. Do not assume reservations own lifecycle. Do not identify vehicles primarily by VIN in the UI. Do not hide conflicts. Do not remove billing/warranty logic just because the app does not collect payments. Do not ignore admin/security/MFA/roles. Do not use builder prompts for discovery. Do not begin by criticizing or redesigning previous work before understanding the business reasons, backend constraints, and historical decisions captured in this Recovery Bible.