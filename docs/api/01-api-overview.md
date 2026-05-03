# NetDiag API — Overview

> Multi-tenant REST API for an AI-assisted network incident diagnosis platform.

## Goals

- Triage and diagnose network incidents at scale (10k QPS read, 1k QPS write).
- Run long-running, AI-assisted diagnostics asynchronously.
- Serve enterprise multi-tenant customers with strict isolation.
- Provide stable contracts that internal services and external integrations can depend on.

## Resources

```
Tenant (1) ──┬── (N) Incident ──┬── (N) Diagnostic ── (N) Query
             │                  └── (N) Event (audit/timeline)
             ├── (N) Runbook
             └── (N) ApiKey / ServiceAccount
```

| Resource | Lifecycle | Consistency | Notes |
|----------|-----------|-------------|-------|
| `incidents` | `triaging → diagnosing → resolved → closed` | Strong (read-after-write, optimistic locking) | Tenant-scoped, immutable id |
| `runbooks` | versioned, immutable releases | Strong on publish, eventual on list | Templated remediation steps |
| `diagnostics` | `queued → running → succeeded/failed/cancelled` | Eventual on list, strong on get-by-id | Long-running async (LRO) |
| `queries` | `submitted → executed → expired` | Eventual | NL→structured query against telemetry |

## URI Conventions

- Base URL: `https://api.netdiag.com/v1`
- Tenant scope is **implicit from the auth token**, never in the URL.
- Plural collections; nest only when ownership is mandatory:
  - `/incidents/{id}/diagnostics` (1:N owned)
  - `/diagnostics/{id}` (also addressable directly for cross-incident queries)
- `snake_case` everywhere — paths, query parameters, JSON keys.
- Resource ids prefixed by type (`inc_…`, `dia_…`, `rb_…`) — debuggable in logs.

## Authentication Summary

| Caller | Mechanism | Header |
|--------|-----------|--------|
| Internal service | JWT (RS256), 15-min TTL | `Authorization: Bearer <jwt>` |
| External integration | API key (prefixed `nd_live_…`/`nd_test_…`) | `Authorization: ApiKey <key>` |
| Inbound webhooks | HMAC-SHA256 signature | `X-NetDiag-Signature: t=…,v1=…` |

All requests must include `X-Tenant-Id`; the server enforces it matches the tenant claim.

See [05-auth-rate-limits.md](05-auth-rate-limits.md) for full details.

## Cross-cutting Concerns

| Concern | Reference |
|---------|-----------|
| Versioning, idempotency | [02-versioning-idempotency.md](02-versioning-idempotency.md) |
| Error model (RFC 7807) | [03-error-model-rfc7807.md](03-error-model-rfc7807.md) |
| Pagination, filtering, sorting | [04-pagination-filtering-sorting.md](04-pagination-filtering-sorting.md) |
| Auth and rate limits | [05-auth-rate-limits.md](05-auth-rate-limits.md) |
| Consistency and concurrency | [06-consistency-and-concurrency.md](06-consistency-and-concurrency.md) |
| Validation checklist | [07-validation-checklist.md](07-validation-checklist.md) |

## Async Workflow

Diagnostics and large queries follow the **Long-Running Operation (LRO) handle pattern**:

1. `POST` returns `202 Accepted` with `Location: /v1/diagnostics/{op_id}` and `Operation-Id` header.
2. Clients either poll `GET /v1/diagnostics/{op_id}`, stream `GET /v1/diagnostics/{op_id}/events` (SSE), or supply a `callback_url` for webhook delivery on terminal state.

See [06-consistency-and-concurrency.md](06-consistency-and-concurrency.md).

## Architectural Decisions

ADRs in [`/adr`](../../adr/):

- [0001 — Idempotency window](../../adr/0001-idempotency-window.md)
- [0002 — RFC 7807 error format](../../adr/0002-rfc7807-error-format.md)
- [0003 — Read consistency model](../../adr/0003-read-consistency-model.md)
- [0004 — Auth model (JWT + API key)](../../adr/0004-auth-model.md)
- [0005 — Rate-limit key choice](../../adr/0005-rate-limit-key.md)

## OpenAPI Specification

Source of truth: [`/openapi/incident-diagnosis-api.yaml`](../../openapi/incident-diagnosis-api.yaml).
