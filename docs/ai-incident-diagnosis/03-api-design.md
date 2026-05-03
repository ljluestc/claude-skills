# 03 — API Design

## Conventions

- **Base URL:** `https://api.netdiag.io/api/v1`
- **Auth:** Bearer JWT (OIDC). JWT carries `tenant_id`, `user_id`, `roles[]`.
- **Tenant scoping:** Implicit from JWT — all queries automatically filtered by `tenant_id`.
- **Pagination:** Cursor-based (`?cursor=<opaque>&limit=50`).
- **Errors:** RFC 7807 Problem Details JSON.
- **Streaming:** Server-Sent Events (SSE) for diagnostic query responses.
- **Idempotency:** `Idempotency-Key` header on POST endpoints.

---

## Incidents

### Create Incident

```
POST /api/v1/incidents
```

Request:
```json
{
  "severity": "P1",
  "title": "BGP session flapping on cr01.sjc",
  "metadata": {
    "affected_devices": ["cr01.sjc"],
    "affected_interfaces": ["et-0/0/1"],
    "alert_source": "grafana",
    "alert_id": "alert-9f3a"
  }
}
```

Response `201 Created`:
```json
{
  "id": "inc_01HYX3...",
  "tenant_id": "tn_acme",
  "severity": "P1",
  "status": "open",
  "title": "BGP session flapping on cr01.sjc",
  "metadata": { "..." },
  "created_at": "2026-05-03T22:00:00Z",
  "updated_at": "2026-05-03T22:00:00Z"
}
```

### List Incidents

```
GET /api/v1/incidents?status=open&severity=P1&limit=20&cursor=eyJ...
```

Response `200 OK`:
```json
{
  "items": [ { "id": "inc_01HYX3...", "..." } ],
  "next_cursor": "eyJ...",
  "has_more": true
}
```

### Get / Update / Delete

```
GET    /api/v1/incidents/{id}
PATCH  /api/v1/incidents/{id}    — update status, severity, notes
DELETE /api/v1/incidents/{id}    — soft-delete
```

PATCH request:
```json
{
  "status": "mitigating",
  "notes": "Root cause confirmed: MTU mismatch on transit link."
}
```

### Webhook Receiver

```
POST /api/v1/incidents/webhooks/{provider}
```

Accepts PagerDuty, Opsgenie, ServiceNow, Alertmanager payloads. Normalizes into internal incident format.

---

## Diagnostic Sessions

### Start Session

```
POST /api/v1/incidents/{incident_id}/sessions
```

Response `201 Created`:
```json
{
  "id": "sess_7kQ2...",
  "incident_id": "inc_01HYX3...",
  "user_id": "usr_jane",
  "created_at": "2026-05-03T22:01:00Z"
}
```

### Submit Query (SSE)

```
POST /api/v1/sessions/{session_id}/query
Accept: text/event-stream
```

Request:
```json
{
  "query": "BGP session to 10.0.1.1 is flapping every 90s. Hold timer is default."
}
```

SSE response stream:
```
event: turn_start
data: {"turn_id": "turn_abc", "turn_number": 1}

event: diagnosis_chunk
data: {"text": "Likely MTU mismatch on the transit link. "}

event: diagnosis_chunk
data: {"text": "The 90-second flap interval matches the BGP hold timer default..."}

event: evidence
data: {"citations": [{"chunk_id": "rb_42_c7", "runbook": "BGP Troubleshooting v3", "excerpt": "When BGP hold timer expires..."}]}

event: proposed_tools
data: {"tools": [
  {"tool": "show_bgp_neighbor", "params": {"device": "cr01.sjc", "peer": "10.0.1.1"}, "tier": 0, "auto_approved": true},
  {"tool": "show_interface_mtu", "params": {"device": "cr01.sjc", "interface": "et-0/0/1"}, "tier": 0, "auto_approved": true}
]}

event: turn_complete
data: {"turn_id": "turn_abc", "confidence": 0.72, "latency_ms": 2840}
```

### List Turns

```
GET /api/v1/sessions/{session_id}/turns?limit=20
```

### End Session

```
DELETE /api/v1/sessions/{session_id}
```

---

## Tool Executions & Approvals

### List Executions for Session

```
GET /api/v1/sessions/{session_id}/tool-executions
```

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "texec_9f...",
      "turn_id": "turn_abc",
      "tool": "show_bgp_neighbor",
      "params": {"device": "cr01.sjc", "peer": "10.0.1.1"},
      "tier": 0,
      "status": "completed",
      "duration_ms": 1200,
      "created_at": "2026-05-03T22:01:03Z"
    }
  ]
}
```

### Get Execution Result

```
GET /api/v1/tool-executions/{id}/result
```

Response `200 OK`:
```json
{
  "id": "texec_9f...",
  "status": "completed",
  "output": "BGP neighbor 10.0.1.1\n  State: Established → Active (flapping)\n  Hold time: 90s\n  Last error: Hold Timer Expired\n  Messages received: 14,302\n  ...",
  "duration_ms": 1200
}
```

### Approve / Reject (Tier 1 & 2)

```
POST /api/v1/tool-executions/{id}/approve
```

```json
{}
```

```
POST /api/v1/tool-executions/{id}/reject
```

```json
{
  "reason": "Not safe to bounce interface during business hours."
}
```

---

## Runbooks

### CRUD

```
POST   /api/v1/runbooks                   — create (triggers ingestion)
GET    /api/v1/runbooks/{id}              — get specific version
PUT    /api/v1/runbooks/{id}              — update (creates new version, re-ingests)
GET    /api/v1/runbooks?tag=bgp&team=noc  — list (filterable)
DELETE /api/v1/runbooks/{id}              — soft-delete
```

Create request:
```json
{
  "title": "BGP Troubleshooting v3",
  "tags": ["bgp", "routing", "transit"],
  "team": "noc",
  "content_markdown": "# BGP Troubleshooting\n\n## Symptom: Session Flapping\n..."
}
```

### Trigger Git Sync

```
POST /api/v1/runbooks/sync
```

```json
{
  "repo_url": "https://github.com/acme-corp/network-runbooks.git",
  "branch": "main"
}
```

### Debug: Get Indexed Chunks

```
GET /api/v1/runbooks/{id}/chunks
```

Returns the chunked + embedded representation used by the RAG pipeline. Useful for debugging retrieval quality.

---

## Audit

### Query Audit Events

```
GET /api/v1/audit/events?resource_type=incident&resource_id=inc_01HYX3...&from=2026-05-01&limit=100
```

Response `200 OK`:
```json
{
  "items": [
    {
      "id": "evt_a1b2...",
      "actor_id": "usr_jane",
      "action": "tool_execution.approve",
      "resource_type": "tool_execution",
      "resource_id": "texec_9f...",
      "metadata": {"tier": 1, "tool": "packet_capture"},
      "ip": "10.20.30.40",
      "created_at": "2026-05-03T22:05:00Z"
    }
  ],
  "next_cursor": "eyJ..."
}
```

### Export

```
GET /api/v1/audit/events/export?format=csv&from=2026-04-01&to=2026-05-01
```

Returns a download URL for the exported CSV/Parquet file.

---

## Error Format (RFC 7807)

```json
{
  "type": "https://api.netdiag.io/errors/forbidden",
  "title": "Forbidden",
  "status": 403,
  "detail": "User usr_bob lacks role 'tool_approver' required to approve Tier-2 executions.",
  "instance": "/api/v1/tool-executions/texec_9f.../approve"
}
```

---

## Rate Limits

| Endpoint Category | Default Limit | Scope |
|-------------------|---------------|-------|
| Diagnostic queries | 60/min | Per tenant |
| Tool executions | 120/min | Per tenant |
| Runbook writes | 30/min | Per tenant |
| Audit reads | 300/min | Per tenant |
| Webhook ingestion | 600/min | Per tenant |

Rate limit headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`.
