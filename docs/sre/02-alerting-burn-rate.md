# 02 — Alerting & Burn-Rate

## Alerting Principles

1. **Page only for actionable, user-impacting conditions.**
2. **Use multi-window burn-rate alerts** to reduce noise.
3. **Separate SLO alerts from infrastructure health alerts.**
4. **Every alert links to a runbook.**

## Multi-Window Burn-Rate Strategy

| Class | Burn Rate | Short Window | Long Window | Action |
|------|-----------|--------------|-------------|--------|
| Fast burn (critical) | 14.4x | 5m | 1h | Page on-call immediately |
| Medium burn (high) | 6x | 30m | 6h | Page business-hours / high-priority |
| Slow burn (warning) | 1x | 6h | 3d | Ticket + planned remediation |

For an SLO with error budget `E`, alert threshold is `burn_rate * E`.

## Prometheus Alert Rules (examples)

```yaml
groups:
  - name: sre_slo_burnrate
    rules:
      - alert: ApiAvailabilityFastBurn
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
          ) > (14.4 * 0.001)
          and
          (
            sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h]))
          ) > (14.4 * 0.001)
        for: 2m
        labels:
          severity: critical
          slo: availability
        annotations:
          summary: "API availability fast burn"
          runbook: "docs/sre/03-runbook-diagnosis-latency.md"

      - alert: ApiAvailabilitySlowBurn
        expr: |
          (
            sum(rate(http_requests_total{status=~"5.."}[6h])) / sum(rate(http_requests_total[6h]))
          ) > (1 * 0.001)
          and
          (
            sum(rate(http_requests_total{status=~"5.."}[3d])) / sum(rate(http_requests_total[3d]))
          ) > (1 * 0.001)
        for: 15m
        labels:
          severity: warning
          slo: availability
        annotations:
          summary: "API availability slow burn"

      - alert: DiagnosisLatencyP99FastBurn
        expr: |
          histogram_quantile(0.99, sum(rate(diagnosis_query_ttfb_seconds_bucket[5m])) by (le)) > 8
          and
          histogram_quantile(0.99, sum(rate(diagnosis_query_ttfb_seconds_bucket[1h])) by (le)) > 8
        for: 5m
        labels:
          severity: critical
          slo: diagnosis_latency
        annotations:
          summary: "Diagnosis latency p99 over SLO"
          runbook: "docs/sre/03-runbook-diagnosis-latency.md"

      - alert: RetrievalQualityDrop
        expr: |
          retrieval_eval_mrr10{dataset="prod_weekly"} < 0.65
          or
          retrieval_eval_ndcg10{dataset="prod_weekly"} < 0.72
        for: 10m
        labels:
          severity: high
          slo: retrieval_quality
        annotations:
          summary: "Retrieval quality below SLO"
          runbook: "docs/sre/04-runbook-retrieval-quality-drop.md"

      - alert: GroundednessDrop
        expr: |
          grounded_response_pass_rate_30m < 0.98
        for: 10m
        labels:
          severity: high
          slo: groundedness
        annotations:
          summary: "Groundedness pass rate below SLO"
          runbook: "docs/sre/04-runbook-retrieval-quality-drop.md"

      - alert: ToolExecutionFailureRateHigh
        expr: |
          1 -
          (
            sum(rate(tool_execution_total{status="completed"}[30m]))
            /
            sum(rate(tool_execution_total{status=~"completed|failed|timed_out"}[30m]))
          ) > 0.005
        for: 10m
        labels:
          severity: high
          slo: tool_execution_success
        annotations:
          summary: "Tool execution failure rate above budget"
          runbook: "docs/sre/05-runbook-tool-execution-failure.md"
```

## Additional Infra Alerts

```yaml
groups:
  - name: sre_infra
    rules:
      - alert: QdrantUnavailable
        expr: up{job="qdrant"} == 0
        for: 2m
        labels: {severity: critical}

      - alert: OpenSearchClusterRed
        expr: opensearch_cluster_health_status{color="red"} == 1
        for: 2m
        labels: {severity: critical}

      - alert: LlmProviderTimeoutSpike
        expr: |
          sum(rate(llm_requests_total{status="timeout"}[5m])) /
          sum(rate(llm_requests_total[5m])) > 0.2
        for: 5m
        labels: {severity: critical}

      - alert: OpaAuthzFailureSpike
        expr: |
          sum(rate(opa_decision_errors_total[5m])) > 5
        for: 2m
        labels: {severity: high}
```

## Grafana Dashboard Panel Plan

### Dashboard: `SRE / AI Incident Diagnosis`

1. **SLO Summary Row**
   - availability 30d
   - diagnosis latency p50/p95/p99
   - retrieval MRR@10 / NDCG@10
   - groundedness pass rate
   - tool execution success
2. **Error Budget Row**
   - budget remaining gauge per SLO
   - burn-rate sparkline (5m/1h, 30m/6h, 6h/3d)
3. **Diagnosis Pipeline Row**
   - query TTFB histogram
   - stage latency breakdown (rewrite, OpenSearch, Qdrant, rerank, LLM)
4. **Retrieval & Groundedness Row**
   - top-K recall trend
   - citation coverage trend
   - hallucination/ungrounded response count
5. **Tool Execution Row**
   - execution success/failure by tool
   - timeout rate
   - approval wait p95
6. **Dependency Health Row**
   - Qdrant availability/latency
   - OpenSearch cluster health
   - LLM provider success/timeout
   - OPA decision latency/error

## Routing & Escalation

- Critical: page primary on-call + incident channel.
- High: page secondary during business hours; ticket auto-created.
- Warning: ticket only, reviewed in weekly reliability meeting.
