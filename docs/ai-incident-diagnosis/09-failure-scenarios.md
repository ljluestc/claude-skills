# 09 — Failure Scenarios

## Incident Response Model

For each scenario:
1. **Detection** via metrics/alerts/logs/traces
2. **Mitigation** via automated failover/degradation/manual action
3. **Tradeoff** documented and accepted

Severity conventions:
- **SEV-1:** user-visible outage or safety risk
- **SEV-2:** partial degradation
- **SEV-3:** localized or recoverable issue

---

## F1 — LLM Provider Outage

### Detection
- LLM API error rate > 50% over 30s.
- Timeouts spike above threshold (e.g., >20%).
- Circuit breaker opens repeatedly.

### Mitigation
- Route requests to fallback provider.
- If all providers fail, switch to **retrieval-only mode**:
  - return top reranked runbook chunks + heuristic summary.
- Trigger ops page for sustained outage > 2 minutes.

### Tradeoff
- Reduced diagnosis quality and conversational depth.
- Potentially slower operator workflows, but service remains partially usable.

---

## F2 — Vector DB Unavailable (Qdrant)

### Detection
- Health checks fail.
- Query latency/timeout anomalies.
- Qdrant cluster status degraded.

### Mitigation
- Fall back to BM25-only retrieval (Elasticsearch).
- Continue reranking on BM25 candidates.
- Queue embedding writes and backfill after recovery.

### Tradeoff
- Semantic recall drops (paraphrases may be missed).
- More dependence on exact-term matching.

---

## F3 — Elasticsearch Degraded/Unavailable

### Detection
- Cluster health `yellow/red`.
- Search timeout rate > threshold.
- JVM/memory pressure alerts.

### Mitigation
- Temporarily run dense-only retrieval (Qdrant).
- Reduce retrieval fanout (e.g., top-50 → top-20) to protect latency.
- Shed non-critical search traffic.

### Tradeoff
- Exact-match retrieval quality declines.
- Some network-specific keywords may be under-retrieved.

---

## F4 — Tool Execution Hang/Crash

### Detection
- Execution exceeds timeout.
- Container exits non-zero.
- Sandbox runtime errors.

### Mitigation
- Hard-kill container at timeout boundary.
- Mark execution `FAILED`.
- Continue diagnosis flow without failed tool output.
- Allow operator manual retry.

### Tradeoff
- Diagnosis confidence may drop.
- Increased manual intervention for critical incidents.

---

## F5 — Approval Gate Stall

### Detection
- Approval request unresolved beyond SLA (e.g., 5 minutes).
- Escalation path not acknowledged.

### Mitigation
- Auto-escalate to team lead/on-call manager.
- Auto-reject after hard timeout (e.g., 15 minutes).
- Workflow continues using available evidence.

### Tradeoff
- Safer than auto-executing risky commands.
- Diagnosis may be slower or less complete.

---

## F6 — Kafka Broker or Consumer Failure

### Detection
- Consumer lag > threshold.
- Producer delivery failures.
- ISR shrink events.

### Mitigation
- Rely on replication factor 3 and ISR failover.
- Producers retry with backoff and idempotency.
- Scale consumers horizontally; rebalance groups.

### Tradeoff
- Temporary delay in async workflows and audit availability.
- With `acks=all`, durability preserved at cost of latency.

---

## F7 — PostgreSQL Primary Failure

### Detection
- Primary health check failure.
- Replication/promote alarms.
- Elevated DB connection errors.

### Mitigation
- Promote replica to primary.
- Rotate service endpoints via proxy/virtual IP.
- Re-point services and recycle stale DB connections.

### Tradeoff
- Brief write unavailability during failover.
- Potential tiny RPO window if replication lag exists.

---

## F8 — Tenant Isolation Breach (Critical Security)

### Detection
- Cross-tenant access anomaly alerts.
- RLS policy violation audit.
- Integration canary tests fail.

### Mitigation
- Trigger tenant kill switch immediately.
- Revoke affected credentials/tokens.
- Contain blast radius, preserve forensic artifacts.
- Execute security incident response playbook.

### Tradeoff
- Temporary tenant-level downtime.
- Strong containment prioritized over continuity.

---

## F9 — Prompt Injection / Unsafe AI Output

### Detection
- Schema validation failures spike.
- Canary token leakage detected in output.
- Unexpected tool suggestions outside policy.

### Mitigation
- Reject malformed output, retry with sanitized context.
- Disable risky tool classes temporarily.
- Escalate to security review if repeated.

### Tradeoff
- More false negatives/blocked responses.
- Slight latency increase from validation and retries.

---

## F10 — Regional Outage

### Detection
- Region health checks fail.
- Wide service and dependency alarms fire simultaneously.

### Mitigation
- DNS failover to secondary region.
- Run in degraded mode while warming caches/indexes.
- Prioritize P1/P2 workload restoration first.

### Tradeoff
- Temporary performance drop during failover.
- Higher cross-region cost and operational complexity.

---

## Summary Matrix

| Failure | Detection Speed | Automated Mitigation | Residual Risk |
|--------|------------------|----------------------|---------------|
| LLM outage | Fast (seconds) | Yes | Lower diagnosis quality |
| Qdrant outage | Fast | Yes | Lower semantic recall |
| ES outage | Fast | Yes | Lower lexical recall |
| Tool crash | Fast | Yes | Missing evidence |
| Approval stall | Medium | Yes | Slower investigations |
| Kafka failure | Fast | Partial | Async delay |
| PG primary fail | Fast | Partial | Short write outage |
| Isolation breach | Fast/Medium | Yes | Security + trust impact |
| Prompt injection | Fast | Yes | Potential response suppression |
| Region outage | Medium | Yes | Degraded capacity |

---

## GameDay Recommendations

- Run monthly chaos drills for F1, F2, F6, F7, F10.
- Run quarterly red-team exercises for F8 and F9.
- Track MTTD/MTTM/MTTR per scenario and improve runbooks.
