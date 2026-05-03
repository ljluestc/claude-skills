# 03 — Ingestion Pipeline

## Goals

- Bring logs, metrics, configs, deploy events, and change records into a single uniform stream.
- Redact PII/secrets before persistence.
- Index for both lexical (BM25) and semantic (ANN) retrieval.
- Tolerate 100× burst loads without back-pressuring the producers.
- Achieve P95 freshness `< 60s` event-to-indexed.

## Topology

```
Producers
  ├─ App logs (Fluent Bit / OTel logs)
  ├─ Metrics scrapers (Prometheus remote_write → adapter)
  ├─ Config/runbook repos (webhook on push)
  ├─ Deploy events (CD systems → webhook)
  └─ Alert payloads (PagerDuty / Opsgenie webhooks)
        │
        ▼
   Kafka topics (per-region)
   ├─ events.raw
   ├─ events.normalized
   ├─ events.enriched
   └─ embeddings.requests
        │
        ▼
   Stream workers (Flink / Beam / Go consumers)
   ├─ Normalizer
   ├─ PII/Safety filter
   ├─ Enricher
   └─ Chunker → Embedder
        │
        ▼
   Indexers (atomic via outbox pattern)
   ├─ OpenSearch (BM25 + filter fields)
   ├─ Qdrant (vectors + payload)
   └─ Postgres (metadata + audit refs)
```

## Stages

### 1. Edge Collection

- **Logs:** Fluent Bit or OTel Collector DaemonSets per K8s node, multi-line aware, k8s metadata enriched.
- **Metrics:** Prometheus remote-write adapter forwards selected series.
- **Configs/runbooks:** Git provider webhooks pushed on commit; full-tree snapshot job runs hourly to fix drift.
- **Deploys + alerts:** webhook receivers normalize CD/PD payloads into platform `Event` shape.

### 2. Schema Normalization

A single canonical record (synthetic illustrative values, no real production data):

```jsonc
{
  "id": "evt_<ulid>",
  "ts": "<rfc3339_nano>",
  "tenant_id": "tenant_<ulid>",
  "service": "checkout-api",
  "env": "prod",
  "kind": "log | metric | config | deploy | alert",
  "body": "<text or json>",
  "attrs": {
    "trace_id": "...",
    "span_id": "...",
    "severity": "warn",
    "version": "v1.42.3",
    "region": "us-east-1"
  },
  "sensitivity": "public | internal | restricted",
  "source": "fluentbit | otel | gh-webhook | pd-webhook",
  "schema_version": 1
}
```

Normalizer enforces OTel semantic conventions; rejected records flow to `events.deadletter` with reason.

### 3. PII / Safety Filter

- Microsoft Presidio + organization-specific regex packs (cloud keys, JWTs, internal hostnames).
- Replaces matched spans with `<REDACTED:type>` placeholders, preserving structure for retrieval.
- Tags `sensitivity` and emits a `redaction_count` metric.
- Records that cannot be deterministically redacted are quarantined to a restricted-access topic.

### 4. Enrichment

- Service catalog lookup → owner team, on-call schedule, repo URL.
- Topology graph join → upstream/downstream services.
- Deploy marker join → most recent deploy of `service` at `ts`.
- SLO state join → was `service` already burning budget at `ts`?

### 5. Chunking

| Source | Chunk strategy |
|---|---|
| Logs | Service+severity windows, capped at 60s and 8 KB; preserves trace_id grouping. |
| Configs | Structural splits (YAML doc/section, JSON schema path); never split mid-key. |
| Runbooks | Heading-based with `≈ 1k token` chunks and 100-token overlap. |
| Metrics | Anomaly windows: collapse stable regions, expand around inflection points. |
| Deploys/alerts | One chunk per event. |

### 6. Embedding

- Model: `bge-m3` (open) or `text-embedding-3-large` (managed); chosen per-tenant by config.
- Served on Triton or vLLM, GPU pool autoscaled by KEDA on Kafka lag.
- Batch sizes up to 256, dynamic batching enabled.
- Embeddings persisted with model version, dimension, and content hash so reindex is incremental.

### 7. Indexing

Atomic across Qdrant, OpenSearch, and Postgres via the **outbox pattern**:

1. Worker writes to Postgres `documents` + `outbox` row in one transaction.
2. CDC tailer (Debezium) emits `outbox` rows to a relay topic.
3. Indexer consumers fan out writes to Qdrant and OpenSearch and acknowledge.
4. Reconciliation job re-emits any unacked rows after a SLA window.

This guarantees a record is never visible in only one of the two retrieval stores.

## Backpressure & Burst Handling

- **Tiered topics:** `events.raw.high`, `events.raw.normal`, `events.raw.debug`. Under lag, `debug` consumers slow first; `high` (alerts, deploys) is preserved.
- **KEDA autoscaling** on Kafka consumer lag for normalizer, embedder, indexer pools.
- **Drop policy** is explicit: only `debug`-tier records may be sampled; alert and deploy records are never dropped.
- **Producer-side limits:** Fluent Bit configured with mem buffers and back-off; if Kafka brokers are unreachable for `> 30s`, agents persist to local disk and retry.

## Failure Modes

| Failure | Effect | Mitigation |
|---|---|---|
| Kafka broker loss | Producer retries, partition leader re-election | RF=3, min ISR 2, rack-aware replication |
| Embedder GPU saturation | Embedding queue grows | KEDA scales pool, gateway slows ingestion of `debug` |
| Schema-invalid event | Normalizer rejects | Routed to `events.deadletter` with reason; on-call alert if rate > threshold |
| Outbox tailer down | Storage drift between Qdrant/OpenSearch | Reconciliation job replays unacked rows; idempotent writes |
| PII filter false negative | Sensitive data persisted | Out-of-band scrubber re-scans nightly; `sensitivity=restricted` records age out faster |

## Observability of the Pipeline

- **OTel traces** propagate from collector through every stream worker; sampling preserves all error spans.
- **SLIs:** ingestion freshness, Kafka consumer lag, embedder queue depth, dead-letter rate, indexer write success rate.
- **Alerts:** burn-rate alerts on freshness; deadletter rate; embedder `5xx`; outbox lag.

See [07 — observability-and-slos](07-observability-and-slos.md).
