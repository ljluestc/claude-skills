# ADR 0001: Incident Diagnosis API Design Decisions (Bundled)

- Status: Accepted
- Date: 2026-05-03

## Context

NetDiag requires an API contract that is:
- safe for production network operations
- deterministic under retries and partial failures
- multi-tenant and compliance-friendly
- evolvable without breaking enterprise integrations

This bundled ADR captures the five core design decisions from the original API plan.

## Decision 1 — Idempotency Window and Semantics

### Decision
Use `Idempotency-Key` on mutating POST routes and store dedupe records for **24 hours**.

Deduplication key:
- `(tenant_id, principal_id, route, idempotency_key)`

Conflict semantics:
- same key + different body => `409 idempotency-key-conflict`
- same key while first request in-flight => `409 idempotency-in-flight`

### Rationale
- Retries are common from clients, webhooks, and queue-based integrations.
- Prevents duplicate creation/execution side effects.
- 24h balances retry safety with bounded storage.

### Consequences
- Requires reliable idempotency store (typically Redis + persistence fallback).
- Request hashing and replay headers become part of platform contract.

## Decision 2 — RFC 7807 as Universal Error Contract

### Decision
All API errors use `application/problem+json` (RFC 7807) with stable `type` URIs and extensions:
- `trace_id`
- `error_code`
- `retryable`
- `invalid_params[]`

### Rationale
- Uniform machine-readable error handling across all services.
- Better supportability and trace correlation.
- Easier compliance and audit review.

### Consequences
- Services must normalize internal errors into a canonical problem shape.
- Ad-hoc error formats are disallowed.

## Decision 3 — Read Consistency and Optimistic Concurrency

### Decision
- Single-resource reads (`GET /{resource}/{id}`): read-after-write consistency.
- Collection/list/search endpoints: eventual consistency acceptable.
- Mutable resources use optimistic concurrency (`ETag` + `If-Match`).

### Rationale
- Operators need immediate correctness on direct resource reads.
- Collections can trade strictness for scale/performance.
- `ETag`/`If-Match` prevents lost updates in concurrent workflows.

### Consequences
- Clients must handle `412 precondition-failed` and retry with fresh reads.
- State-transition conflicts may return `409 conflict`.

## Decision 4 — Auth Model (JWT + API Key + Webhook HMAC)

### Decision
Support three auth modes:
1. OIDC JWT bearer for users/services
2. API key auth for external system integrations
3. HMAC signature verification for inbound webhooks

Tenant scope is always credential-derived and never client-supplied.

### Rationale
- Different integration types need different trust models.
- Keeps external integrations simple while preserving enterprise-grade controls.
- HMAC is the practical baseline for webhook authenticity/integrity.

### Consequences
- Multi-scheme auth support in gateway and service middleware.
- Credential rotation and revocation must be first-class ops workflows.

## Decision 5 — Rate-Limit Key and Budget Policy

### Decision
Rate limiting is enforced per tenant with route-class budgets, keyed by:
- `(tenant_id, auth_principal, route_class)`

Standard response headers:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`
- `Retry-After` on 429

### Rationale
- Prevents noisy-neighbor effects in multi-tenant operation.
- Route-class budgets protect critical flows (diagnosis/tooling/audit independently).
- Standard headers improve client-side adaptive retry behavior.

### Consequences
- Requires consistent route classification at gateway layer.
- Budget tuning becomes a recurring SRE/product activity.

## Summary

These decisions optimize for:
- correctness under retry/concurrency
- secure multi-tenant operation
- reliable client behavior under failure
- operational clarity for incident response and compliance
