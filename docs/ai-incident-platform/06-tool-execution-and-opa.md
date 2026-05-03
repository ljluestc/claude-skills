# 06 — Tool Execution and OPA Policy

## Why a Policy Layer

The agent is not the security boundary. Even a well-aligned model can be manipulated via prompt injection in a retrieved log line. We treat every tool call as an untrusted RPC and validate it with **Open Policy Agent** before execution.

OPA centralizes:

- Per-tool argument policy.
- Per-tenant scoping.
- Per-environment guardrails (e.g., `prod` vs `staging`).
- Read-only enforcement on data tools.
- Audit-grade decision logs.

## Execution Flow

```
Agent step → produces ToolCall{name, args}
        │
        ▼
Tool registry: schema validation (Pydantic / JSON Schema)
        │
        ▼
OPA decision request (Rego policy)
   input: { tool, args, principal, tenant, env, run_id, trace_id }
        │
   ┌────┴────┐
   │ allow?  │
   └────┬────┘
   yes  │  no
        ▼   └───→ deny: log, abort step, surface to critic + audit
   Adapter (sandboxed, timeout, retry budget)
        │
        ▼
   Result + provenance → scratchpad
        │
        ▼
   OTel span closed; OPA decision + result_hash to audit log
```

## Tool Schema Contract

Every tool registers a strict schema. Synthetic illustrative example for `QueryLogs` (no production data):

```python
class QueryLogsArgs(BaseModel):
    service: str            # required, must be in tenant's service catalog
    dsl: dict               # OpenSearch DSL; subset only
    time_range: TimeRange   # bounded; max 24h
    max_hits: int = 100     # hard cap server-side
```

Validation:

- Unknown fields rejected.
- `service` looked up against tenant's service catalog.
- `dsl` parsed and pruned to a whitelist (no `_msearch`, no scripts, no destructive ops).

## OPA Policy Examples

### A. Read-only enforcement on PromQL

```rego
package incident.tools.query_metrics

import future.keywords.in

default allow := false

# Deny mutating PromQL functions outright
deny_functions := { "delete_series", "tsdb_admin" }

allow if {
    input.tool == "QueryMetrics"
    input.principal.tenant_id == input.args.tenant_id
    not contains_denied_function(input.args.promql)
    input.args.range_seconds <= 86400  # 24h
}

contains_denied_function(q) if {
    some f in deny_functions
    contains(lower(q), f)
}
```

### B. Tenant scoping on log search

```rego
package incident.tools.query_logs

default allow := false

allow if {
    input.tool == "QueryLogs"
    input.args.filters.tenant_id == input.principal.tenant_id
    input.args.time_range.duration_seconds <= 86400
    input.args.max_hits <= 1000
    not has_disallowed_clause(input.args.dsl)
}

has_disallowed_clause(dsl) if {
    walk(dsl, [_, v])
    is_object(v)
    v.script
}
```

### C. No mutating tools without human approval

```rego
package incident.tools.mutating

default allow := false

allow if {
    input.tool in {"RestartPod", "RollbackDeploy"}
    input.principal.kind == "human"
    input.principal.has_role("incident-commander")
    input.args.approval.granted_at != null
}
```

The mutating tools are not part of the default agent surface; the policy is included so the platform's posture is uniform: even if a tool were accidentally registered, OPA would block it.

## Sandboxing

- Each tool runs in a dedicated worker pool with a per-tool circuit breaker and timeout.
- Network egress is restricted via mesh-level policy (Cilium/Calico): only the tool's allowlisted endpoints are reachable.
- Filesystem/process operations are not part of any tool. There is no `Exec` tool by design.

## Audit

For every tool invocation we record (synthetic illustrative shape):

```jsonc
{
  "audit_event_id": "ae_<ulid>",
  "ts": "<rfc3339_nano>",
  "run_id": "run_<ulid>",
  "principal": { "kind": "agent", "model": "...", "tenant_id": "tenant_<ulid>" },
  "tool": "QueryLogs",
  "args_hash": "sha256:...",
  "opa_decision": "allow | deny",
  "opa_policy_version": "v1.42.0",
  "result_hash": "sha256:...",
  "latency_ms": 87,
  "trace_id": "..."
}
```

Records are written to:

1. **Append-only Postgres partition** (`audit_events`), immutable via row-level triggers.
2. **WORM object store** (S3/GCS/Blob with object lock + versioning) for long-term tamper-evident retention.

OPA's own decision log is also shipped to the same WORM bucket for legal/compliance.

## Performance

- OPA sidecar with bundle distribution; in-process evaluation, no network hop.
- Decision latency target: P95 `< 5 ms`.
- Decisions cached by `(tool, args_hash, principal_hash)` with `30s` TTL for hot paths.

## Operational Practices

- Policies live in a dedicated repo with required reviews from security + on-call.
- Argo CD pushes signed bundles to all clusters. Kyverno verifies signatures.
- Shadow-evaluation mode: new policies run alongside the active one for 24h before promotion. Mismatches alert the on-call.

## Failure Modes

| Failure | Effect | Mitigation |
|---|---|---|
| OPA sidecar down | Tool calls cannot be executed | Liveness probe restarts; orchestrator returns degraded answer |
| Stale policy bundle | Outdated decisions | Bundle TTL `5m`; alert if last-update lag `> 10m` |
| Policy regression | False denials | Shadow mode catches before promotion; rapid rollback via Argo |
| Bypass attempt via prompt injection | Argument crafted to look benign | Validation + OPA + adapter pruning all enforce constraints; tested in red-team eval |
