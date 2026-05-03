# Versioning & Idempotency

## Versioning Strategy

NetDiag uses **URL path versioning** (`/v1`).

- Single source of truth, easy CDN routing, easy deprecation telemetry.
- Breaking changes → new major version (`/v2`).
- Non-breaking additions stay in the current version.
- Minor version surfaced via informational `API-Version: 1.4` response header (not used for routing).

### Deprecation Headers

Deprecated endpoints return:

```http
Deprecation: Sun, 01 Mar 2026 00:00:00 GMT
Sunset: Sun, 01 Sep 2026 00:00:00 GMT
Link: <https://docs.netdiag.com/migrations/v2>; rel="deprecation"
```

- `Deprecation`: when the endpoint became deprecated.
- `Sunset`: when it will stop responding (returns `410 Gone` after this date).
- `Link rel="deprecation"`: documentation pointer.

### Backwards-compat Rules

Permitted within a major version:

- Adding new endpoints.
- Adding optional request fields.
- Adding response fields.
- Relaxing validation (e.g., increasing a max length).

Not permitted (require a major bump):

- Removing or renaming fields.
- Tightening validation (smaller maxes, new required fields).
- Changing field semantics or units.
- Changing default values for optional fields.

### Tradeoffs

| Option | Chose | Rejected | Why |
|--------|-------|----------|-----|
| Path version `/v1` | ✅ | Header `Accept: vnd.netdiag.v2+json`, query `?v=2` | Ops simplicity, CDN routing, easier deprecation telemetry. |
| Field-level deprecation | ✅ for small evolutions | Endpoint churn | E.g., add `status_v2` alongside `status` while clients migrate. |

## Idempotency

### Scope

The `Idempotency-Key` header is **required** on:

- `POST /v1/incidents`
- `POST /v1/incidents/{id}/diagnostics`
- `POST /v1/queries`

It is **optional** but honored on all other `POST` endpoints.

### Header Format

```http
Idempotency-Key: 8e3a8d4e-6c1b-4d2c-9b3f-1f0a2e5c4a11
```

- Must be a UUID (v4 recommended).
- Scope: `(tenant_id, idempotency_key)` — keys do not collide across tenants.

### Server Behavior

| Scenario | Behavior |
|----------|----------|
| New key | Process request, store `(key → request_hash, response, status)` for **24 hours** in Redis. Return original response. |
| Replay with **same body** | Return the cached response unchanged. Set header `Idempotency-Replayed: true`. |
| Replay with **different body** (hash mismatch) | Return `409 Conflict`, `type: idempotency-key-conflict`. |
| Replay while first request is still in-flight | Return `409 Conflict`, `type: idempotency-in-flight`. Client should retry with backoff. |
| First request failed mid-flight (no response stored) | Subsequent retries with same key process normally — at-least-once semantics. |

### Replay Detection Headers

```http
HTTP/1.1 201 Created
Location: /v1/incidents/inc_01HKZX9F2Q
Idempotency-Replayed: false
```

```http
HTTP/1.1 201 Created
Location: /v1/incidents/inc_01HKZX9F2Q
Idempotency-Replayed: true
```

### Window: 24 Hours

Matches industry convention (Stripe, AWS). Long enough to absorb retries from job
systems and queue redelivery; bounded so the idempotency store doesn't grow without
limit. See [ADR 0001](../../adr/0001-idempotency-window.md).

### Idempotency vs Concurrency

`Idempotency-Key` protects against **duplicate creates**.
Use `If-Match: <etag>` for **concurrent updates** — see [06-consistency-and-concurrency.md](06-consistency-and-concurrency.md).
The two are independent: a `PATCH /incidents/{id}` request typically uses `If-Match` and does **not** require `Idempotency-Key` (PATCH is naturally idempotent).

## Example: Idempotent Create

### Initial request

```http
POST /v1/incidents HTTP/1.1
Host: api.netdiag.com
Authorization: Bearer eyJ...
X-Tenant-Id: tnt_acme
Idempotency-Key: 8e3a8d4e-6c1b-4d2c-9b3f-1f0a2e5c4a11
Content-Type: application/json

{
  "title": "BGP flap on edge-router-3",
  "severity": 4,
  "source": "alertmanager"
}
```

```http
HTTP/1.1 201 Created
Location: /v1/incidents/inc_01HKZX9F2Q
ETag: W/"v1"
Idempotency-Replayed: false

{ "id": "inc_01HKZX9F2Q", "status": "triaging", "version": 1, ... }
```

### Replay (same body)

```http
HTTP/1.1 201 Created
Location: /v1/incidents/inc_01HKZX9F2Q
ETag: W/"v1"
Idempotency-Replayed: true

{ "id": "inc_01HKZX9F2Q", "status": "triaging", "version": 1, ... }
```

### Replay (different body)

```http
HTTP/1.1 409 Conflict
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/idempotency-key-conflict",
  "title": "Idempotency Key Conflict",
  "status": 409,
  "detail": "Idempotency key was reused with a different request body.",
  "instance": "/v1/incidents",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN"
}
```
