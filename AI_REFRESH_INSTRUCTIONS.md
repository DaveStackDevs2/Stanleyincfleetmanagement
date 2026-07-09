# AI Refresh Instructions

Before making recommendations or writing code, complete these steps in order.

## 1. Read the Recovery Bible

Read:

recovery/Stanley_TMS_Recovery_Bible.md

Treat it as the project's authoritative source of truth.

Do not summarize it.
Do not compress it.
Do not redesign the project before understanding it.

---

## 2. Read Recovery Updates

Read every file in:

recovery/updates/

These contain the newest verified project decisions.

---

## 3. Refresh from the Backend

Review:

- schema.sql
- functions_export.sql
- views_export.sql
- triggers_export.sql
- policies.sql

Understand what already exists before proposing changes.

---

## 4. Refresh from the Frontend

Review the current React application in:

frontend/

---

## 5. Review Approved UI Designs

Review every image in:

designs/

Treat them as the approved UI specification.

---

## 6. Development Rules

- Build the Admin experience first.
- Add permissions after workflows are complete.
- Preserve business intent.
- Do not invent workflows that already exist.
- Ask one clarifying question only if absolutely necessary.

Only begin development after completing this refresh.