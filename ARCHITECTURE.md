# Stanley Chevrolet Belfast
# Transportation Management System

## Overview

This project is a Transportation Management System (TMS) for Stanley Chevrolet Belfast.

It is not intended to be a general CRM.

## Frontend

Framework:

- React 19
- Vite
- TypeScript

Shared Supabase client:

`frontend/src/lib/supabase.ts`

## Backend

Supabase.

Current data access is primarily through:

`v_admin_vehicle_master_state`

## Current Modules

Implemented:

- Admin Console
- Fleet Administration

Planned:

- Authentication
- Reservations
- Transportation workflow
- Calendar integration
- Reporting
- Administration

## Security Roadmap

1. Authentication
2. Session persistence
3. Protected routes
4. Remove anonymous access
5. Role-based authorization

## Repository Philosophy

Business logic belongs in the backend where practical.

Frontend should remain focused on presentation and workflow.

Repository changes should be incremental and verifiable.
