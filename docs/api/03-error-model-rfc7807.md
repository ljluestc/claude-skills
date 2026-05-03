# Error Model — RFC 7807 (with `errors[]` extension)

All error responses use **`Content-Type: application/problem+json`** and follow
[RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807), extended with an
`errors[]` array for field-level validation failures and a `trace_id` for
distributed-trace correlation.

## Schema

```json
{
  "type":     "https://docs.netdiag.com/errors/<slug>",
  "title":    "Human-readable summary (stable per type)",
  "status":   400,
  "detail":   "Specific, actionable description of THIS occurrence.",
  "instance": "/v1/incidents/req_01HKZX9F2Q",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN",
  "errors": [
    { "field": "<dot.path>", "code": "<machine_code>", "message": "<human>" }
  ]
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `type` | yes | Stable URI; documented at `https://docs.netdiag.com/errors/<slug>`. Never a generic string. |
| `title` | yes | Stable per `type`; safe to map to client UI labels. |
| `status` | yes | Mirrors HTTP status code. |
| `detail` | recommended | Free-form, occurrence-specific, actionable. |
| `instance` | recommended | URI that identifies this occurrence (request id or resource path). |
| `trace_id` | recommended | Trace correlation id (ULID). |
| `errors[]` | only on 422 | Field-level failures; see below. |

### `errors[]` extension (422 only)

```json
[
  { "field": "severity",      "code": "out_of_range",   "message": "must be 1..5" },
  { "field": "tags[3]",       "code": "max_length",     "message": "must be ≤ 32 chars" },
  { "field": "callback_url",  "code": "invalid_format", "message": "must be a valid HTTPS URL" }
]
```

- `field` uses dot-path with array indexing: `tags[3]`, `actions[0].command`.
- `code` is a stable, snake_case machine code (clients may localize against it).
- `message` is a human-readable fallback.

## Catalog

| Status | `type` slug | When |
|--------|-------------|------|
| `400` | `bad-request` | Malformed JSON, unknown query parameter, invalid header value. |
| `401` | `unauthenticated` | Missing, expired, or invalid token. |
| `403` | `forbidden` | Authenticated, but lacks scope/role for this operation. |
| `404` | `not-found` | Resource missing **or** cross-tenant access (do not leak existence). |
| `405` | `method-not-allowed` | Method not supported on this resource. |
| `409` | `conflict` | Generic conflict. Use specific slugs below when possible. |
| `409` | `idempotency-key-conflict` | Idempotency key reused with different body. |
| `409` | `idempotency-in-flight` | First request still processing; retry with backoff. |
| `412` | `precondition-failed` | `If-Match` / `If-Unmodified-Since` failed. |
| `415` | `unsupported-media-type` | Wrong `Content-Type`. |
| `422` | `validation-error` | Field-level failures; populate `errors[]`. |
| `429` | `rate-limit-exceeded` | Token bucket empty. |
| `500` | `internal-error` | Unexpected; opaque message; safe to retry. |
| `503` | `dependency-unavailable` | Upstream telemetry/AI provider down. |
| `504` | `gateway-timeout` | Upstream did not respond in time. |

## Examples

### 400 — Bad Request

```http
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/bad-request",
  "title": "Bad Request",
  "status": 400,
  "detail": "Unknown query parameter: 'state'. Did you mean 'status'?",
  "instance": "/v1/incidents",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN"
}
```

### 401 — Unauthenticated

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="netdiag", error="invalid_token", error_description="Token expired"
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/unauthenticated",
  "title": "Unauthenticated",
  "status": 401,
  "detail": "Access token is expired.",
  "instance": "/v1/incidents",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN"
}
```

### 404 — Not Found (cross-tenant access denied)

```http
HTTP/1.1 404 Not Found
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/not-found",
  "title": "Not Found",
  "status": 404,
  "detail": "Incident does not exist.",
  "instance": "/v1/incidents/inc_01HKZXXXXXXXXXXXXXXXX",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN"
}
```

> Cross-tenant access returns `404`, not `403`, to avoid leaking resource existence.

### 412 — Precondition Failed

```http
HTTP/1.1 412 Precondition Failed
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/precondition-failed",
  "title": "Precondition Failed",
  "status": 412,
  "detail": "Resource has been updated since you last read it. Re-fetch and retry.",
  "instance": "/v1/incidents/inc_01HKZX9F2Q",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN"
}
```

### 422 — Validation Error

```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/validation-error",
  "title": "Validation Error",
  "status": 422,
  "detail": "1 field failed validation.",
  "instance": "/v1/incidents",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN",
  "errors": [
    { "field": "severity", "code": "out_of_range", "message": "must be 1..5" }
  ]
}
```

### 429 — Rate Limit Exceeded

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 12
RateLimit-Limit: 1000
RateLimit-Remaining: 0
RateLimit-Reset: 12
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/rate-limit-exceeded",
  "title": "Rate Limit Exceeded",
  "status": 429,
  "detail": "Too many requests on route class 'write'. Retry after 12 seconds.",
  "instance": "/v1/incidents",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN"
}
```

### 503 — Dependency Unavailable

```http
HTTP/1.1 503 Service Unavailable
Retry-After: 30
Content-Type: application/problem+json

{
  "type": "https://docs.netdiag.com/errors/dependency-unavailable",
  "title": "Dependency Unavailable",
  "status": 503,
  "detail": "Telemetry backend is temporarily unavailable.",
  "instance": "/v1/diagnostics",
  "trace_id": "01HKZX9F2QABCDEFGHJKMN"
}
```

## Client Guidance

- **Switch on `type`**, never on `title` or `detail`. Titles are stable per type but localized titles or detail strings may evolve.
- **Surface `trace_id` to support staff** so they can correlate with server-side traces.
- **Respect `Retry-After`** for `429` and `503`. Combine with exponential backoff capped at 30 s.
- **For `422`, render `errors[]` per field** in your form UI; fall back to `detail` if the array is empty.

See [ADR 0002 — RFC 7807 error format](../../adr/0002-rfc7807-error-format.md) for the rationale.
