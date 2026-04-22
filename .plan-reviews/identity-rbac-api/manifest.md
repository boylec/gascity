# Planning Manifest: identity-rbac-api

- **Review ID**: identity-rbac-api
- **Repo root**: /Users/caseyboyle/src/SafetyChain/gas-city
- **Coordinator agent**: quartermaster-3
- **Review target**: enterprise/gastown.polecat
- **Molecule**: hq-jrpiz (mol-sc-idea-to-plan, formula_v2)

## Problem Statement

Build the Identity bounded-context RBAC API surface: Users CRUD + me endpoints, user-role assignments, Roles CRUD with permission set replace, and Permissions read-only list/get. Approximately 20 endpoints with usr_/rol_/perm_ ID prefixes.

## Context

- **Project**: Identity & Access Management
- **Motivation**: QA needs to operate on global data as if tenant was fresh; also provides the admin surface for user+role management within a tenant
- **Blocks**: SAF-450
- **Related**: SAF-446 (Users UI Prototype — frontend consuming this API)
- **Linear**: Not stamped (no linear_id provided in dispatch)
