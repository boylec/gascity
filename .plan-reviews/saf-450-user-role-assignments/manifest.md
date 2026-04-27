# Planning Manifest: SAF-450 User-Role Assignments API

- **Review ID**: saf-450-user-role-assignments
- **Repo Root**: /Users/caseyboyle/src/SafetyChain/gas-city
- **Target Rig**: enterprise (/Users/caseyboyle/src/SafetyChain/enterprise)
- **Coordinator**: quartermaster-2 (session hq-n0nrp)
- **Review Target**: enterprise/polecats.sonnet
- **Linear Issue**: SAF-450
- **Root Bead**: hq-k71b0k

## Problem Statement

Implement REST API endpoints for managing user-role assignments and
resolving computed permissions in the SafetyChain Identity bounded context.
The domain model (User aggregate, RoleAssignment value object,
PermissionResolver service) exists but has no HTTP exposure, no persistence
infrastructure, and no database schema.

Endpoints:
- `GET /api/v1/users/:userId/roles` (list assignments)
- `POST /api/v1/users/:userId/roles` (assign role)
- `DELETE /api/v1/users/:userId/roles/:roleId` (revoke role)
- `GET /api/v1/users/:userId/permissions` (computed permissions)
