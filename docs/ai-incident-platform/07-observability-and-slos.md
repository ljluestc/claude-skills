# 07 — Observability and SLOs

## Telemetry Strategy

OpenTelemetry is the single instrumentation standard. Every service emits **traces**, **metrics**, and **logs** through the OTel SDK; an OTel Collector daemonset normalizes and routes them.

```
Service (OTel SDK)
    │
    ▼
OTel Collector (per-region, gateway mode)
    ├─ Traces  → Tempo / Jaeger
    ├─ Metrics → Prometheus / Mimir (Thanos for long-term)
    └─ Logs    → Loki (with Grafana for query)
                 │
                 ▼
        Grafana dashboards · Alertmanager · PagerDuty
```

- **Trace propagation** is mandatory across all hops, including Kafka (B3/W3C in headers), the agent loop (`agent.plan`, `agent.tool.<name>`, `agent.critic`, `agent.compose`), and storage adapters.
- **Sampling**: head-based 10% baseline; tail-based to keep all error spans, all spans `> p99` latency, and all OPA-deny spans.
- **Logs** are structured JSON with `trace_id` and `tenant_id`; PII redacted at the SDK layer.

## SLI Catalog

| SLI | Definition | Source |
|---|---|---|
| `diagnose_latency_p95` | Wall-clock from gateway accept to first useful answer (SSE). | OTel server span on `Diagnose` |
| `diagnose_latency_p99` | Same, end-to-end. | OTel server span |
| `diagnose_availability` | `1 − (5xx / total)` for `/v1/diagnose`. | Gateway logs |
| `retrieval_recall_at_8` | Recall@8 on the offline eval corpus. | Eval runner (nightly) |
| `citation_faithfulness` | % of claims with valid critic-verified citations. | Critic outcomes |
| `ingestion_freshness_p95` | Time from event_ts to indexed_ts. | OTel + DB timestamps |
| `ingestion_durability` | `acked_but_lost / acked`. | Kafka + indexer reconciliation |
| `opa_decision_latency_p95` | OPA evaluation latency. | OTel sidecar span |
| `tool_call_success_rate` | `1 − (tool_errors / tool_attempts)`. | Agent loop metrics |

## SLOs

| SLO | Target | Window |
|---|---|---|
| Diagnose P95 latency | `< 2.0 s` | 30d rolling |
| Diagnose P99 latency | `< 5.0 s` | 30d rolling |
| Diagnose availability | `≥ 99.9%` | 30d rolling |
| Retrieval recall@8 | `≥ 0.85` | 7d rolling |
| Citation faithfulness | `≥ 0.95` | 7d rolling |
| Ingestion freshness P95 | `< 60 s` | 7d rolling |
| Ingestion durability | `≥ 1 − 1e-6` | 30d rolling |

## Latency Budget for the Synchronous Path

Total budget: **1,800 ms wall-clock** (target P95 `< 2,000 ms`).

| Stage | Budget |
|---|---|
| Edge + auth + OPA (gateway) | 50 ms |
| Planner (LLM) | 200 ms |
| Retrieval (BM25 + ANN, parallel) | 200 ms |
| Reranker (cross-encoder) | 120 ms |
| Tool calls (parallel) | 300 ms |
| Critic | 200 ms |
| Composer (first useful tokens) | 350 ms |
| Headroom / streaming overhead | 380 ms |

If any stage exceeds budget, the orchestrator either skips the optional stage (rerank) or returns the best partial answer with `degraded=true`.

## Burn-Rate Alerting

Multiwindow burn-rate alerts on the availability and latency SLOs (synthetic illustrative rules):

```yaml
groups:
  - name: slo_diagnose_availability
    rules:
      - alert: DiagnoseAvailabilityFastBurn
        expr: |
          (
            sum(rate(http_requests_total{job="diagnose-api",status=~"5.."}[1h]))
            /
            sum(rate(http_requests_total{job="diagnose-api"}[1h]))
          ) > (14.4 * 0.001)
          and
          (
            sum(rate(http_requests_total{job="diagnose-api",status=~"5.."}[5m]))
            /
            sum(rate(http_requests_total{job="diagnose-api"}[5m]))
          ) > (14.4 * 0.001)
        for: 2m
        labels: { severity: critical }
        annotations:
          runbook: "https://wiki.internal/runbooks/diagnose-availability"

      - alert: DiagnoseAvailabilitySlowBurn
        expr: |
          (
            sum(rate(http_requests_total{job="diagnose-api",status=~"5.."}[6h]))
            /
            sum(rate(http_requests_total{job="diagnose-api"}[6h]))
          ) > (1 * 0.001)
        for: 15m
        labels: { severity: warning }
        annotations:
          runbook: "https://wiki.internal/runbooks/diagnose-availability"
```

Latency burn-rate alerts use a similar dual-window pattern over `histogram_quantile(0.95, ...)` for the SSE first-useful-token histogram.

## Golden Signal Queries

```promql
# Latency — P99 of /v1/diagnose
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{job="diagnose-api"}[5m])) by (le))

# Traffic — RPS by tenant
sum(rate(http_requests_total{job="diagnose-api"}[5m])) by (tenant_id)

# Errors — 5xx ratio
sum(rate(http_requests_total{job="diagnose-api",status=~"5.."}[5m]))
  /
sum(rate(http_requests_total{job="diagnose-api"}[5m]))

# Saturation — embedder queue depth (Kafka lag)
max(kafka_consumergroup_lag{group="embedder"}) by (topic)
```

## LLM-Specific Observability

- **Token usage** per run, per tenant, per model.
- **Tool-call latency histograms** by tool name.
- **Critic rejection rate** (signal for hallucination drift).
- **Plan revision count** per run.
- **Cost per run** (currency-tagged) feeding tenant guardrails.

Dashboards expose model-version × time-bucketed citation faithfulness so we catch regressions when a model is upgraded.

## Error Budget Policy

If the 30-day diagnose-availability budget burns `> 50%` in `< 25%` of the window, the platform team:

1. Freezes non-critical releases.
2. Pages the on-call to triage.
3. Blocks model upgrades until burn returns to baseline.

Recorded in [10 — architecture-decisions](10-architecture-decisions.md) ADRs.

## Audit Trail Cross-Reference

Run records and OPA decisions are linked via `run_id` and `trace_id`, so any postmortem can reconstruct the exact sequence of agent steps, tool calls, and policy decisions. See [06 — tool-execution-and-opa](06-tool-execution-and-opa.md).
