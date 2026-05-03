# 01 — SLI/SLO Definition

## Scope

This document defines core reliability indicators and objectives for the AI incident diagnosis platform.

## Core SLIs

### SLI-1: API Availability
- **Definition:** Successful API requests / total API requests.
- **Good event:** HTTP status not in 5xx.
- **Window:** rolling 30 days.
- **PromQL:**
```promql
1 - (
  sum(rate(http_requests_total{status=~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
)
```

### SLI-2: Diagnosis Latency (TTFB)
- **Definition:** Time from `POST /sessions/{id}/query` to first SSE token.
- **Good event:** request duration <= threshold.
- **Metrics:** p50/p95/p99.
- **PromQL (p99):**
```promql
histogram_quantile(0.99, sum(rate(diagnosis_query_ttfb_seconds_bucket[5m])) by (le))
```

### SLI-3: Retrieval Quality
- **Definition:** Weekly offline relevance quality on labeled set.
- **Metrics:** `MRR@10`, `NDCG@10`.
- **Good event:** query with reciprocal rank above floor contributes positively to mean.

### SLI-4: Groundedness
- **Definition:** Fraction of AI responses that are citation-grounded and pass groundedness evaluator.
- **Signals:**
  - citation coverage (`% responses with >=1 valid citation`)
  - attribution precision (`% cited spans matching source`)
  - hallucination rate from evaluator model/human audit
- **Good event:** response passes groundedness check.

### SLI-5: Tool Execution Success
- **Definition:** Completed tool executions / (completed + failed + timed_out).
- **Note:** excludes rejected approvals.
- **PromQL:**
```promql
sum(rate(tool_execution_total{status="completed"}[30m]))
/
sum(rate(tool_execution_total{status=~"completed|failed|timed_out"}[30m]))
```

## SLO Targets

| SLO | Target | Window |
|-----|--------|--------|
| API availability | >= 99.9% | 30d |
| Diagnosis latency p99 | < 8s | 30d |
| Diagnosis latency p50 | < 3s | 30d |
| Retrieval quality | MRR@10 >= 0.65 and NDCG@10 >= 0.72 | weekly / 30d rollup |
| Groundedness pass rate | >= 98.0% | 30d |
| Tool execution success | >= 99.5% | 30d |

## Error Budgets

### Availability (99.9%)
- Monthly budget: `0.1%` bad events.
- Equivalent downtime budget (30-day month): `43m 12s`.

### Diagnosis Latency p99 < 8s
- Up to `1%` of requests may exceed threshold.

### Retrieval Quality
- Weekly budget: at most `1 failed weekly eval` in rolling 4-week window.

### Groundedness (98%)
- Budget: up to `2%` responses may fail groundedness checks.

### Tool Execution Success (99.5%)
- Budget: up to `0.5%` execution failures/timeouts.

## Error Budget Policy

- **Healthy:** burn rate < 1x → normal feature velocity.
- **Warning:** burn rate 1x–3x → freeze non-critical deploys for affected services.
- **Critical:** burn rate > 6x → incident process, stop risky changes, prioritize reliability work.

## Ownership

| SLI/SLO | Primary Owner | Secondary |
|---------|----------------|----------|
| Availability, latency | Platform SRE | Backend |
| Retrieval quality, groundedness | Applied AI / RAG team | SRE |
| Tool execution success | Tooling platform team | SRE |

## Review Cadence

- Weekly: SLO report + budget trend.
- Monthly: threshold tuning and false-positive/false-negative review.
- Quarterly: recalibrate targets based on product tier and customer SLA commitments.
