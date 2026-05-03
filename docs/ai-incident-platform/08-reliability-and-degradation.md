# 08 — Reliability and Graceful Degradation

## Posture

The platform must keep returning a useful answer under partial failure. The retrieval and orchestration paths are designed so that loss of any single component degrades quality without taking down the service.

The core of this posture is the **degradation ladder**:

```
rerank  →  ANN  →  BM25  →  cached runbook
(best quality)              (last-resort answer)
```

Each rung delivers a strictly cheaper, strictly less-precise answer; each is reachable in `< 2s` even when the rung above is unavailable.

## Degradation Ladder (Detail)

### Rung 1 — Full hybrid + reranker (default)

- BM25 + ANN + RRF + cross-encoder + critic.
- Quality: best. Recall@8 `≥ 0.85`, faithfulness `≥ 0.95`.
- Triggers downgrade: reranker timeout, OOM, GPU/CPU saturation, model version mismatch.

### Rung 2 — Hybrid without reranker

- BM25 + ANN + RRF + critic.
- Reranker bypassed; final ranking is the RRF score.
- Quality cost: ~10–20 pts in nDCG@8 on hard queries; latency +0 ms.
- Triggers downgrade: dense ANN unhealthy (Qdrant cluster timeouts, replica loss past quorum).

### Rung 3 — BM25 only

- OpenSearch lexical search with the original query and one expansion variant from the planner.
- Quality cost: substantial loss on natural-language symptom queries.
- Triggers downgrade: BM25 path unhealthy or query plan empty.

### Rung 4 — Cached runbook

- Last-resort: serve the precomputed runbook chunk for the alerting service+symptom from the CDN-backed runbook cache, with an explicit `degraded=true` and `confidence_overall ≤ 0.3`.
- Always available because runbook chunks are static, signed, and globally replicated.

The orchestrator records the chosen rung in the run record and emits an OTel attribute (`degradation_rung`) so dashboards can plot ladder usage.

## Decision Logic

```
budget_left = wall_clock_ms_left
if reranker_healthy and budget_left ≥ 150ms:    use rung 1
elif ann_healthy and budget_left ≥ 80ms:        use rung 2
elif bm25_healthy and budget_left ≥ 80ms:       use rung 3
else:                                           use rung 4
```

Health is measured by per-component circuit breakers (5xx rate, p95 latency vs threshold, last-success age).

## Failure Catalog

| Failure | Impact | Mitigation |
|---|---|---|
| Vector DB region down | No dense retrieval | Rung-2 (BM25-only RRF). Cross-region replica promoted via Argo Rollouts |
| LLM provider outage | No diagnosis | Provider abstraction switches primary→secondary (Anthropic ↔ Bedrock ↔ Vertex). If all fail, return rung-4 cached runbook |
| Kafka lag spike | Stale context | KEDA scales embedders; tiered topics drop `debug` first; UI surfaces freshness indicator |
| Reranker GPU/CPU saturation | Latency breach | Circuit breaker → rung 2 |
| Prompt injection in retrieved logs | Tool misuse attempt | Tool args validated by OPA; `untrusted_content` channel; agent denies cross-tenant ops |
| Poisoned embeddings | Bad retrieval | Source-signed events; provenance score in ranking; quarantine of new sources for 24h shadow eval |
| Cross-region split brain (metadata) | Inconsistent runs | Single-writer per tenant pinned by consistent hash; reads from local replica with bounded staleness header |
| Regional cloud outage | Loss of one cloud's region | Anycast removes region; warm standby in another cloud takes traffic; data replicated asynchronously, RPO ≈ 5 min |
| Runaway agent loop | Cost / latency blowup | Hard step + token + wall-clock + tool-call budgets; killer goroutine; per-tenant cost ceilings |
| Auth bypass attempt | Cross-tenant data access | Tenant filter enforced at storage adapter layer (defense in depth); contract tests on every PR |
| OPA sidecar failure | Tool calls denied | Liveness probe restarts; orchestrator returns rung-4 with explicit explanation |
| Postgres metadata corruption | Run lookups fail | PITR + cross-region read replica; replay from object-store WORM audit log |
| Audit-write lag | Compliance risk | Async writer with bounded queue; alerts when queue depth `> N`; ingest-and-replay if writer crashes |

## Backpressure & Load Shedding

- Edge gateway sheds load on `/v1/diagnose` when SLO burn-rate `> 14.4×`: returns `503` with `Retry-After`, preserving capacity for in-flight runs.
- Streams have priority lanes: `severity=critical` alerts bypass shed; lower priorities back off.
- Per-tenant rate limits prevent one tenant from monopolizing global capacity.

## Recovery Patterns

- **Replay:** every run is reconstructible from the persisted inputs (alert payload + retrieval set ids + tool args + model+seed). Failed regions can re-execute runs after recovery.
- **Idempotent indexers:** outbox + dedupe key on `(doc_hash, schema_version)` lets us replay safely without duplicating.
- **Snapshot/restore:** Qdrant nightly snapshots to object store; OpenSearch ILM snapshots; Postgres PITR; runbook cache rebuilt from source repo.

## RTO / RPO Targets

| Component | RTO | RPO |
|---|---|---|
| Diagnose API | `< 60 s` | n/a (stateless) |
| Retrieval Service | `< 60 s` | n/a (stateless) |
| Qdrant cluster | `< 5 min` | `≤ 15 min` |
| OpenSearch | `< 5 min` | `≤ 5 min` |
| Postgres metadata | `< 5 min` | `≤ 1 min` (continuous WAL ship) |
| Audit log (WORM) | `< 1 min` | `0` (synchronous double-write) |
| Kafka | `< 1 min` | `0` (RF=3, min ISR 2) |

## Chaos Practice

- Weekly game day: kill a vector-DB shard, an OPA sidecar, a region; verify ladder rungs activate.
- Continuous: chaos mesh injects 10% latency on a random downstream every hour; alerting must not fire.
- Provider failover drill monthly: actively switch LLM primary to secondary in canary tenants.

Postmortems for any incident are blameless and feed back into this catalog and the runbooks linked from [07 — observability-and-slos](07-observability-and-slos.md).
