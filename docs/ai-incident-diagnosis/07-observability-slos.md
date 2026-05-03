# 07 — Observability & SLOs

## Instrumentation Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Metrics | Prometheus | SLI collection, HPA custom metrics |
| Traces | Tempo / Jaeger | Distributed tracing across all services |
| Logs | Loki | Structured log aggregation |
| Dashboards | Grafana | Visualization, alerting rules |
| SDK | OpenTelemetry | Unified instrumentation across Go + Python services |

Every service emits:
- **RED metrics** (Rate, Errors, Duration) per endpoint via OTel middleware.
- **Traces** with span context propagated through gRPC metadata and HTTP headers.
- **Structured JSON logs** with `trace_id`, `tenant_id`, `request_id` for correlation.

---

## Service-Level Indicators (SLIs)

### SLI-1: Diagnostic Query Latency

**Definition:** Time from `POST /sessions/{id}/query` received at the API gateway to the first SSE byte delivered to the client.

**Measurement:**
```promql
histogram_quantile(0.99,
  sum(rate(diagnosis_query_duration_seconds_bucket[5m])) by (le)
)
```

**Why this metric:** The primary user experience signal. Includes the full RAG pipeline: query rewriting, dual retrieval, reranking, and LLM generation (time-to-first-token).

### SLI-2: Retrieval Relevance

**Definition:** Mean Reciprocal Rank at 10 (MRR@10) and NDCG@10 measured against human-labeled relevance judgments.

**Measurement:** Offline evaluation pipeline runs weekly against a curated test set of 500 (query, relevant_chunks) pairs. Results written to Prometheus via pushgateway.

**Why this metric:** Ensures the hybrid retrieval pipeline (BM25 + dense + reranker) is returning useful context to the LLM. Detects embedding drift and index staleness.

### SLI-3: Tool Execution Success Rate

**Definition:** `count(status=completed) / count(status in [completed, failed, timed_out])` over a rolling window. Excludes `rejected` (user choice, not system failure).

**Measurement:**
```promql
sum(rate(tool_execution_total{status="completed"}[30m]))
/
sum(rate(tool_execution_total{status=~"completed|failed|timed_out"}[30m]))
```

### SLI-4: Approval Turnaround

**Definition:** Time from `ApprovalRequest.created_at` to `ApprovalRequest.decided_at` for Tier-1 and Tier-2 tool executions.

**Measurement:**
```promql
histogram_quantile(0.95,
  sum(rate(approval_turnaround_seconds_bucket[30m])) by (le, tier)
)
```

### SLI-5: End-to-End MTTR

**Definition:** Time from `incident.created_at` to `incident.resolved_at`, bucketed by severity.

**Measurement:** Computed on incident resolution, exported as histogram. Aggregated weekly for trend analysis.

### SLI-6: API Availability

**Definition:** Fraction of non-5xx responses across all API endpoints.

**Measurement:**
```promql
1 - (
  sum(rate(http_requests_total{status=~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
)
```

---

## Service-Level Objectives (SLOs)

All SLOs measured on a **30-day rolling window**.

| SLO ID | SLI | Target | Error Budget (30d) |
|--------|-----|--------|-------------------|
| SLO-1 | Query latency p99 | < 8s | 1% of queries may exceed |
| SLO-2 | Query latency p50 | < 3s | 50% of queries must be under |
| SLO-3 | Retrieval MRR@10 | > 0.65 | Weekly eval must pass |
| SLO-4 | Tool execution success | > 99.5% | ~90 failures/month (at 18K/day) |
| SLO-5 | Approval turnaround p95 | < 5 min | 5% of approvals may exceed |
| SLO-6 | API availability | > 99.9% | 43 min downtime/month |

---

## Burn-Rate Alerting

Uses the multi-window, multi-burn-rate approach from the Google SRE Workbook.

### How It Works

The **burn rate** is the rate at which the error budget is being consumed relative to the SLO window. A burn rate of 1× means the budget will be exactly exhausted at the end of the 30-day window. Higher burn rates mean faster exhaustion.

| Alert Severity | Burn Rate | Short Window | Long Window | Budget Consumed | Action |
|----------------|-----------|-------------|------------|-----------------|--------|
| **Page (critical)** | 14.4× | 5 min | 1 hour | 2% in 1h | Wake on-call |
| **Page (high)** | 6× | 30 min | 6 hours | 5% in 6h | Page during hours |
| **Ticket (medium)** | 1× | 6 hours | 3 days | 10% in 3d | File ticket |

Both windows must fire simultaneously to reduce false positives.

### Example: SLO-6 Availability (99.9%)

```yaml
# Prometheus alerting rules
groups:
  - name: slo_availability
    rules:
      # Fast burn — 2% of budget consumed in 1 hour
      - alert: AvailabilityBudgetFastBurn
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[5m]))
            / sum(rate(http_requests_total[5m]))
          ) > (14.4 * 0.001)
          AND
          (
            sum(rate(http_requests_total{status=~"5.."}[1h]))
            / sum(rate(http_requests_total[1h]))
          ) > (14.4 * 0.001)
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "API availability SLO fast-burn: error budget being consumed at 14.4x rate"
          budget_remaining: "{{ $value | humanizePercentage }}"

      # Slow burn — 10% of budget consumed in 3 days
      - alert: AvailabilityBudgetSlowBurn
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[6h]))
            / sum(rate(http_requests_total[6h]))
          ) > (1 * 0.001)
          AND
          (
            sum(rate(http_requests_total{status=~"5.."}[3d]))
            / sum(rate(http_requests_total[3d]))
          ) > (1 * 0.001)
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "API availability SLO slow-burn: on track to exhaust budget"
```

### Example: SLO-1 Query Latency p99 (<8s)

```yaml
      - alert: QueryLatencyFastBurn
        expr: |
          (
            histogram_quantile(0.99,
              sum(rate(diagnosis_query_duration_seconds_bucket[5m])) by (le)
            ) > 8
          )
          AND
          (
            histogram_quantile(0.99,
              sum(rate(diagnosis_query_duration_seconds_bucket[1h])) by (le)
            ) > 8
          )
        for: 2m
        labels:
          severity: critical
```

---

## Infrastructure Alerts (non-SLO)

| Alert | Condition | Severity |
|-------|-----------|----------|
| LLM provider errors | Error rate > 5% over 2 min | Critical (page) |
| Kafka consumer lag | Lag > 10,000 messages | Critical (page) |
| Tool execution queue depth | Pending > 50 | Warning |
| Qdrant query latency | p99 > 500ms over 5 min | Warning |
| Elasticsearch cluster health | Status = red | Critical (page) |
| PG replication lag | Lag > 30s | Critical (page) |
| Redis memory usage | > 85% of maxmemory | Warning |
| Temporal workflow failure rate | > 5% over 15 min | Warning |
| Certificate expiry | < 14 days | Warning |

---

## Dashboards

### Dashboard 1: Platform Overview
- Request rate (by service, by tenant)
- Error rate (by service, status code)
- SLO burn-rate gauges (traffic light: green/yellow/red)
- Active incidents by severity

### Dashboard 2: Diagnosis Engine
- Query latency heatmap (p50/p95/p99)
- Retrieval pipeline breakdown (BM25 time, dense search time, reranker time, LLM time)
- Token usage per tenant
- Model routing distribution (Claude Sonnet vs Haiku)
- Cache hit rate (session context cache)

### Dashboard 3: Tool Execution
- Execution rate by tier and status
- Approval turnaround time histogram
- Sandbox resource usage (CPU, memory, network)
- Failure categorization (timeout vs error vs rejected)

### Dashboard 4: Tenant Health
- Per-tenant query volume and latency
- Per-tenant error budget remaining
- Token budget usage vs allocation
- Noisy-neighbor detection (tenant consuming disproportionate resources)

### Dashboard 5: Data Pipeline
- Runbook ingestion throughput and errors
- Kafka topic lag by consumer group
- Audit event write rate
- Elasticsearch index size and merge activity

---

## Distributed Tracing

Every request generates a trace spanning:

```
[API Gateway] → [Auth] → [Diagnosis Engine]
                              ├── [Query Rewriter (LLM)]
                              ├── [BM25 Search (ES)]      ← parallel
                              ├── [Dense Search (Qdrant)]  ← parallel
                              ├── [Reranker]
                              ├── [LLM Generation]
                              └── [Tool Execution]
                                     ├── [Approval Wait]
                                     └── [Sandbox Run]
```

Custom span attributes:
- `tenant_id`, `incident_id`, `session_id`, `turn_number`
- `model_name`, `token_count_input`, `token_count_output`
- `retrieval_candidates_bm25`, `retrieval_candidates_dense`, `reranked_count`
- `tool_name`, `tool_tier`, `tool_status`
