# 02 — High-Level Architecture

## System Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                         CLIENT LAYER                                  │
│   On-call UI · Slack/Teams Bot · CLI · PagerDuty Webhook · API SDK   │
└────────────────────────────────┬─────────────────────────────────────┘
                                 │ mTLS + OIDC
┌────────────────────────────────▼─────────────────────────────────────┐
│                  GLOBAL EDGE (anycast, multi-CDN)                     │
│   WAF · Rate Limit · Geo-routing · DDoS · Header signing              │
└────────────────────────────────┬─────────────────────────────────────┘
                                 │
┌────────────────────────────────▼─────────────────────────────────────┐
│                    API GATEWAY (per-region, active/active)            │
│   Envoy + OPA · AuthN/Z · Tenant isolation · Quota · Circuit breaker │
└──┬──────────────────┬──────────────────┬─────────────────┬──────────┘
   │                  │                  │                 │
┌──▼─────────┐  ┌─────▼────────┐  ┌─────▼──────────┐  ┌──▼───────────┐
│ Diagnosis  │  │ Ingestion    │  │ Retrieval      │  │ Orchestration │
│ API (gRPC) │  │ Service      │  │ Service        │  │ Service       │
│ /v1/diag   │  │ (async)      │  │ (BM25+ANN+RRF) │  │ (agent loop)  │
└──┬─────────┘  └──┬───────────┘  └──┬─────────────┘  └──┬────────────┘
   │               │                 │                   │
   │      ┌────────┴───────┐         │                   │
   │      │ Stream Bus     │         │                   │
   │      │ Kafka/PubSub   │         │                   │
   │      └───┬────┬────┬──┘         │                   │
   │          │    │    │            │                   │
   │   ┌──────▼─┐ ┌▼───┐ ┌▼───────┐  │                   │
   │   │Parser/ │ │PII │ │Embed   │  │                   │
   │   │Norm    │ │Filt│ │Worker  │  │                   │
   │   └──┬─────┘ └─┬──┘ └────┬───┘  │                   │
   │      │         │         │      │                   │
   └──────┴─────────┴─────────┴──────┴──────┐            │
                                            ▼            ▼
   ┌──────────────────────────────────────────────────────────────┐
   │                    STORAGE PLANE                              │
   │  Vector DB (Qdrant)  ·  Metadata (Postgres)                   │
   │  Object Store (S3/GCS/Blob) · Time-series (Prom/Mimir)        │
   │  Hot Log Index (OpenSearch) · Cache (Redis Cluster)           │
   │  Audit Log (immutable, WORM) · Feature Store (Feast)          │
   └──────────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────────────────────┐
   │             OBSERVABILITY + CONTROL PLANE                     │
   │  OTel Collector → Tempo/Jaeger · Prom · Loki · Grafana        │
   │  SLO engine (Sloth) · PagerDuty · Policy (OPA/Kyverno)        │
   └──────────────────────────────────────────────────────────────┘
```

## Logical Planes

| Plane | Responsibility | Key Components |
|---|---|---|
| **Edge** | TLS termination, WAF, anycast routing, DDoS protection. | Cloudflare/Front Door + Envoy edge. |
| **Control** | Auth, policy, quota, request shaping. | API Gateway, OPA, OIDC IdP, SPIFFE/SPIRE. |
| **Application** | Stateless services for diagnosis, retrieval, orchestration, ingestion. | gRPC services on K8s. |
| **Data** | Stateful stores: Qdrant, OpenSearch, Postgres, Redis, object store. | Per-region clusters, async cross-region replication. |
| **Observability** | OTel pipelines, metrics/logs/traces, SLO engine, alerting. | OTel Collector, Prometheus/Mimir, Loki, Tempo, Grafana. |
| **Audit** | Immutable record of inputs, tool calls, model outputs, policy decisions. | Append-only Postgres partition + WORM object store. |

## Two Critical Request Paths

### A. Synchronous Diagnose Path (P95 `< 2s`)

```
User → Edge → Gateway (auth, OPA, rate-limit)
     → Diagnosis API (gRPC, SSE)
       → Orchestrator: plan
         → Retrieval Service (parallel)
            ├─ OpenSearch BM25
            ├─ Qdrant ANN
            └─ Reranker
         → Tool calls (read-only) under OPA
         → Critic verifies citations
       → Stream tokens back to user
     → Audit log write (async)
```

Latency budget breakdown for the synchronous path is given in [07 — observability-and-slos](07-observability-and-slos.md).

### B. Asynchronous Ingestion Path

```
Edge collectors (OTel/Vector/Fluent Bit)
  → Kafka events.raw
    → Normalizer  → events.normalized
    → PII filter → events.enriched
    → Embedder   → embeddings.requests
                 → indexers (Qdrant + OpenSearch + Postgres outbox)
```

Detailed in [03 — ingestion-pipeline](03-ingestion-pipeline.md).

## Cross-Cutting Concerns

- **Multi-tenancy:** every request carries `tenant_id` (via OIDC claim). Storage adapters inject row/payload filters server-side; clients cannot bypass.
- **mTLS:** all in-mesh traffic mTLS via SPIFFE workload identities. External calls signed.
- **Idempotency:** `POST /diagnose` accepts `Idempotency-Key`; the orchestrator persists run records and replays the canonical response on retry.
- **Streaming:** diagnose responses use SSE so the user sees first useful tokens before retrieval finishes ranking the long tail.
- **Versioning:** `/v1` API. Backward-incompatible changes require a new prefix and a 6-month overlap.

## Deployment View (per region)

- One K8s cluster per region per cloud (EKS/GKE/AKS).
- Service mesh (Istio or Linkerd) with mTLS, retry budgets, and locality-aware load balancing.
- Argo CD ApplicationSets reconcile the same Helm/Kustomize artifacts across all clusters.
- Argo Rollouts for progressive delivery (5% → 25% → 100%) gated by SLO burn-rate metrics.

## Where to Read Next

- For per-component depth: [03](03-ingestion-pipeline.md), [04](04-hybrid-retrieval.md), [05](05-agent-orchestration.md), [06](06-tool-execution-and-opa.md).
- For SLOs and operational health: [07](07-observability-and-slos.md).
- For failure modes and graceful degradation: [08](08-reliability-and-degradation.md).
- For multi-region rollout: [09](09-multi-region-deployment.md).
