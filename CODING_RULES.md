# Stanley Chevrolet Belfast
# Transportation Management System (TMS)

## Coding Rules

These rules apply to every change made in this repository.

## General

- Preserve existing functionality unless explicitly instructed otherwise.
- Do not redesign the UI without approval.
- Never invent business rules.
- Never fabricate database fields.
- Never create placeholder logic that pretends to work.
- If something is unknown, inspect the repository instead of guessing.

## Frontend

Technology:

- React 19
- Vite
- TypeScript

Rules:

- Reuse existing components whenever practical.
- Keep components focused and readable.
- Avoid unnecessary abstraction.
- Follow existing project formatting.

## Backend

Backend is Supabase.

Rules:

- Use the shared Supabase client.
- Never create additional Supabase clients.
- Do not bypass Row Level Security.
- Do not modify database schema unless explicitly requested.

## Database

Always prefer existing tables, views, and functions before creating anything new.

## Authentication

Current direction:

- Supabase Auth
- Email/password authentication
- Session persistence
- Role-based authorization after authentication is complete

## Commits

Every implementation should:

- Build successfully
- Avoid TypeScript errors
- Avoid lint errors where possible

Commit messages should clearly describe the completed work.

## Documentation

When architecture or workflow changes, update:

- `recovery/updates/PROJECT_STATUS.md`
- `recovery/updates/DECISIONS.md`
- `recovery/updates/CHANGELOG.md`

before completing work.
