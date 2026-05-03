# Incident Diagnosis API Design (Option C Bundle)

## 1) API Overview

NetDiag exposes a multi-tenant REST API for AI-assisted network incident diagnosis.

Core workflow coverage:
- Incident lifecycle management (`open → triaging → diagnosing → mitigating → resolved → postmortem`)
- Conversational diagnosis sessions with SSE streaming
- Risk-tiered tool execution + approval gates
- Runbook CRUD + sync + chunk inspection
- Audit event query/export

Design goals:
- Strict tenant isolation
- deterministic behavior under retries/concurrency
- human-in-the-loop safety for risky actions
- standards-compliant errors and operational debuggability

Resource model:

```text
Tenant (1) ──┬── (N) Incident ──┬── (N) Diagnostic Session ── (N) Query Turn
             │                  └── (N) Event (audit/timeline)
             ├── (N) Runbook
             └── (N) ApiKey / ServiceAccount
```

Base URL:
- `https://api.netdiag.io/api/v1`

URI conventions:
- plural nouns (`/incidents`, `/runbooks`)
- nested routes only for hard ownership (`/incidents/{id}/sessions`)
- `snake_case` fields and query params
- typed ids (`inc_…`, `sess_…`, `rb_…`, `texec_…`)

## 2) Versioning & Idempotency

### Versioning strategy
- URI major versioning: `/api/v1`
- breaking changes only in new major (`/api/v2`)
- non-breaking additions allowed in v1:
  - new optional fields
  - new optional request fields
  - new endpoints

Deprecation headers (for v1 sunset):

```http
Deprecation: Sun, 01 Mar 2026 00:00:00 GMT
Sunset: Sun, 01 Sep 2026 00:00:00 GMT
Link: <https://docs.netdiag.com/migrations/v2>; rel="deprecation"
```

### Idempotency

`Idempotency-Key` is required on mutating POST operations.

Header format:

```http
Idempotency-Key: 8e3a8d4e-6c1b-4d2c-9b3f-1f0a2e5c4a11
```

Scope:
- `(tenant_id, principal_id, route, idempotency_key)`

Behavior:

| Scenario | Server behavior |
|---|---|
| new key | process request, cache response + request hash for 24h |
| replay same key + same payload | return original response, `Idempotency-Replayed: true` |
| replay same key + different payload | `409 Conflict` (`idempotency-key-conflict`) |
| replay while first request in-flight | `409 Conflict` (`idempotency-in-flight`) |

Endpoints requiring idempotency:
- `POST /incidents`
- `POST /incidents/{incident_id}/sessions`
- `POST /sessions/{session_id}/query`
- `POST /tool-executions/{id}/approve`
- `POST /tool-executions/{id}/reject`
- `POST /runbooks`
- `POST /runbooks/sync`
- `POST /incidents/webhooks/{provider}`

## 3) RFC 7807 Error Model

All errors use:
- `Content-Type: application/problem+json`

Canonical body:

```json
{
  "type": "https://api.netdiag.io/errors/validation-error",
  "title": "Validation Error",
  "status": 422,
  "detail": "1 field failed validation.",
  "instance": "/api/v1/incidents",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN",
  "error_code": "VALIDATION_FAILED",
  "retryable": false,
  "invalid_params": [
    { "name": "severity", "reason": "must be one of P1..P5" }
  ]
}
```

Error catalog:

| Status | Type slug | When |
|---|---|---|
| 400 | `bad-request` | malformed payload, unknown query/enum |
| 401 | `unauthenticated` | invalid/expired credentials |
| 403 | `forbidden` | missing role/scope |
| 404 | `not-found` | missing resource or cross-tenant masking |
| 409 | `conflict` | state conflict/idempotency conflict |
| 412 | `precondition-failed` | stale `If-Match` |
| 422 | `validation-error` | field validation failures |
| 429 | `rate-limit-exceeded` | quota exceeded |
| 500 | `internal-error` | unhandled server failure |
| 503 | `dependency-unavailable` | upstream unavailable |
| 504 | `gateway-timeout` | upstream timeout |

Client guidance:
- branch on `type`/`error_code` (not `detail`)
- display `trace_id` in support UI
- honor `Retry-After` on 429/503

## 4) Pagination, Filtering, Sorting

Cursor pagination for all collections:
- request: `?cursor=<opaque>&limit=20`
- response: `{ items, next_cursor, has_more }`
- bounds: `1 <= limit <= 100`

Filtering:
- `GET /incidents`: `status`, `severity`
- `GET /runbooks`: `tag`, `team`
- `GET /audit/events`: `resource_type`, `resource_id`, `from`, `to`

Sorting:
- query: `sort=<field>:<asc|desc>`
- defaults:
  - incidents: `created_at:desc`
  - runbooks: `updated_at:desc`
  - audit events: `created_at:desc`

## 5) Auth & Rate Limits

### Authentication modes

| Caller type | Mechanism | Header |
|---|---|---|
| user/service | OIDC JWT (RS256) | `Authorization: Bearer <jwt>` |
| external integration | API key | `Authorization: ApiKey <key>` |
| inbound webhook | HMAC signature | `X-NetDiag-Signature: t=...,v1=...` |

Tenant scoping:
- resolved from credential claims
- never accepted from client payload
- enforced in API layer and data layer (RLS)

### Authorization
- role-based checks for approvals and admin actions
- Tier-1/2 tool approvals require `tool_approver`
- Tier-2 may require dual-approval policy

### Rate limits

Default per-tenant budgets:

| Category | Limit |
|---|---|
| diagnosis query | 60/min |
| tool execution | 120/min |
| runbook write | 30/min |
| audit read | 300/min |
| webhook ingest | 600/min |

Rate-limit headers:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`
- `Retry-After` on 429

## 6) Consistency & Concurrency

### Consistency
- `GET /incidents/{id}`, `GET /runbooks/{id}`: read-after-write
- list/search endpoints: may be eventually consistent

### Concurrency control
- `ETag` on mutable resource reads
- `If-Match` required on:
  - `PATCH /incidents/{id}`
  - `PUT /runbooks/{id}`
- stale write → `412 Precondition Failed`
- business state conflict → `409 Conflict`

### Async/LRO behavior
- long-running operations return `202 Accepted` where applicable
- status tracked on resource (`queued/running/succeeded/failed/cancelled`)
- session/query timeline remains monotonic by `turn_number`

## 7) Endpoint Catalog

### Incidents
- `POST /incidents`
- `GET /incidents`
- `GET /incidents/{id}`
- `PATCH /incidents/{id}`
- `DELETE /incidents/{id}`
- `POST /incidents/webhooks/{provider}`

### Sessions
- `POST /incidents/{incident_id}/sessions`
- `POST /sessions/{session_id}/query` (SSE)
- `GET /sessions/{session_id}/turns`
- `DELETE /sessions/{session_id}`

### Tool Executions
- `GET /sessions/{session_id}/tool-executions`
- `GET /tool-executions/{id}/result`
- `POST /tool-executions/{id}/approve`
- `POST /tool-executions/{id}/reject`

### Runbooks
- `POST /runbooks`
- `GET /runbooks`
- `GET /runbooks/{id}`
- `PUT /runbooks/{id}`
- `DELETE /runbooks/{id}`
- `POST /runbooks/sync`
- `GET /runbooks/{id}/chunks`

### Audit
- `GET /audit/events`
- `GET /audit/events/export`

## 8) Validation Checklist

### General
- [ ] credentials valid and tenant-resolvable
- [ ] tenant in credential matches tenant context
- [ ] required headers present (`Content-Type`, `Accept`, idempotency where required)
- [ ] unknown enum/query values rejected
- [ ] cursor token shape validated
- [ ] limit bounds enforced

### Incidents
- [ ] `severity` in `P1..P5`
- [ ] title non-empty and bounded
- [ ] state transitions legal
- [ ] soft-deleted resources hidden by default

### Sessions / Query
- [ ] session belongs to incident + tenant
- [ ] query length bounded (`<= 2000`)
- [ ] SSE accepted for query stream route
- [ ] per-session turn ordering enforced

### Tool execution / approval
- [ ] tool is tenant-allowed
- [ ] params pass schema validation
- [ ] role checks pass for Tier-1/2
- [ ] dual-approval constraints enforced for Tier-2

### Runbooks
- [ ] markdown content required
- [ ] tags/team/title constraints valid
- [ ] version increments on update
- [ ] `If-Match` required on update

### Audit
- [ ] date range bounded
- [ ] export format in allowed set (`csv`, `parquet`)
- [ ] pagination + sort deterministic

## 9) Source of Truth

- API contract: `openapi/incident-diagnosis-api.yaml` (OpenAPI 3.1)
- Architectural rationale bundle: `adr/0001-api-design-decisions.md`
