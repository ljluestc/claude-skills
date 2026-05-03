# 06 — Chaos Experiments

## Objectives

Validate that the platform degrades safely and predictably under key dependency failures:
- Qdrant outage
- OpenSearch degradation
- LLM provider timeout
- OPA failure

## Safety Guardrails

- Run in staging first, then controlled prod window.
- Define abort thresholds before start.
- Announce start/stop in incident channel.
- Keep rollback commands ready.

## Common Experiment Template

For each experiment:
1. **Hypothesis**
2. **Steady-state metrics**
3. **Fault injection**
4. **Expected behavior**
5. **Abort criteria**
6. **Rollback**
7. **Results + actions**

---

## Experiment A — Qdrant Outage

### Hypothesis
If Qdrant is unavailable, system falls back to BM25/OpenSearch-only retrieval with acceptable degradation and no complete outage.

### Steady-state Metrics
- diagnosis p99 latency
- success rate of `/sessions/{id}/query`
- retrieval quality trend

### Fault Injection
- Simulate Qdrant service outage (e.g., block service or kill pods).

### Expected Behavior
- Alert `QdrantUnavailable` fires.
- Retrieval switches to BM25-only mode.
- No 5xx surge above availability budget.

### Abort Criteria
- API availability falls below 99.5% over 10 minutes.
- diagnosis p99 > 20s for 10 minutes.

### Rollback
- Restore Qdrant deployment/service.
- verify health checks and query path recovered.

---

## Experiment B — OpenSearch Degradation

### Hypothesis
With OpenSearch latency/errors elevated, dense retrieval path sustains service while relevance drops within tolerable bounds.

### Steady-state Metrics
- OpenSearch p95 latency
- shard failure count
- diagnosis latency and groundedness pass rate

### Fault Injection
- Inject latency / CPU stress into OpenSearch data nodes.

### Expected Behavior
- Alert `OpenSearchClusterRed` or latency alert fires.
- Retrieval falls back to dense-only (Qdrant).
- Groundedness remains >= threshold via citation enforcement.

### Abort Criteria
- sustained query failure > 5%.
- groundedness pass rate < 95% for 15 minutes.

### Rollback
- Remove stress injection.
- Rebalance shards and validate search health.

---

## Experiment C — LLM Provider Timeout

### Hypothesis
LLM timeout spike triggers provider failover and preserves partial functionality.

### Steady-state Metrics
- LLM timeout rate
- fallback provider usage
- diagnosis success/latency

### Fault Injection
- Inject network delay/timeout to primary LLM endpoint.

### Expected Behavior
- `LlmProviderTimeoutSpike` alert fires.
- Circuit breaker opens for primary.
- traffic routes to fallback provider.
- If fallback unavailable: retrieval-only safe mode.

### Abort Criteria
- diagnosis API 5xx > 3% for 10 minutes.
- incident response workflows blocked.

### Rollback
- remove network fault.
- close circuit breaker after health probe pass.

---

## Experiment D — OPA Failure

### Hypothesis
OPA failure does not allow unsafe privilege escalation; high-risk operations fail closed.

### Steady-state Metrics
- OPA decision latency/error rate
- authz deny/fail counts by endpoint
- tool execution approval flow success

### Fault Injection
- stop OPA sidecars / block policy bundle fetch.

### Expected Behavior
- `OpaAuthzFailureSpike` alert fires.
- Tier-1/2 actions fail closed.
- Tier-0 behavior follows configured emergency policy.

### Abort Criteria
- unauthorized action accepted.
- widespread lockout of essential read-only operations.

### Rollback
- restore OPA instances and policy bundle.
- re-run authz canary tests.

---

## Post-Experiment Report Checklist

- Did behavior match hypothesis?
- Were alerts timely and actionable?
- Were runbooks sufficient?
- What SLO impact occurred?
- What mitigations/automation should be added?

## Suggested Cadence

- Monthly: one dependency chaos test.
- Quarterly: full game day with chained failures (e.g., LLM timeout + OpenSearch degradation).
