# 04 — Hybrid Retrieval

## Why Hybrid

Incidents have two retrieval modes:

- **Lexical** — operators search for rare tokens: a UUID, a stack frame, an exact metric name. BM25 dominates here.
- **Semantic** — operators describe symptoms in natural language. Dense embeddings dominate here.

Neither alone hits the recall target on logs, runbooks, and configs. We use both, fuse, then rerank.

## Pipeline

```
Query (alert text + context)
        │
        ▼
┌───────────────────────┐
│  Query Planner (LLM)  │  expands into N variants:
│                       │   - symptom paraphrase
│                       │   - hypothesis form
│                       │   - runbook lookup
└──────────┬────────────┘
           │ (parallel)
   ┌───────┴────────────────────────────┐
   ▼                ▼                   ▼
BM25 (OpenSearch)   ANN (Qdrant HNSW)   Metadata filter
   k=100              k=100              tenant/time/service
   │                  │                  │
   └──────────┬───────┘──────────────────┘
              │
              ▼
      Reciprocal Rank Fusion (RRF, k=60)
              │
              ▼
   Cross-encoder reranker (top-30 → top-8)
              │
              ▼
        MMR diversification (λ=0.5) + dedupe
              │
              ▼
       Token-budgeted context packer
              │
              ▼
        Retrieved Context
```

## Stage Details

### Query Planner

The planner LLM rewrites the alert + symptom text into 2–3 variants:

1. Symptom paraphrase (`"checkout-api 5xx spike after deploy"`).
2. Hypothesis form (`"what causes increased 5xx after canary rollout?"`).
3. Runbook lookup (`"runbook: checkout-api elevated error rate"`).

Variants are issued in parallel against both retrieval stores. Failures of individual variants do not fail the request.

### BM25 (OpenSearch)

- Indexes: per-tenant, per-kind (`logs-{tenant}-{yyyy-mm}`, `runbooks-{tenant}`, `configs-{tenant}`).
- Default analyzer with custom synonym list for service names and acronyms.
- Filters always applied server-side: `tenant_id`, time range (default last 24h), `env`, `service` if known.
- Returns `top-100` candidates with `_score`.

Synthetic illustrative DSL (no production data):

```jsonc
{
  "size": 100,
  "query": {
    "bool": {
      "must":   [ { "match": { "body": "<query>" } } ],
      "filter": [
        { "term":  { "tenant_id": "tenant_<ulid>" } },
        { "term":  { "kind": "log" } },
        { "term":  { "service": "checkout-api" } },
        { "range": { "ts": { "gte": "now-1h" } } }
      ]
    }
  }
}
```

### Dense ANN (Qdrant)

- HNSW index per `tenant_id` shard.
- Tuned `M=32`, `ef_construct=200`, `ef=128` for query.
- Payload indexes on `service`, `env`, `kind`, `ts` enable filter pushdown.
- Returns `top-100` candidates with cosine score.

### Reciprocal Rank Fusion

For each candidate `d` appearing in the BM25 result list `R_BM25` and/or the ANN list `R_ANN` and/or any planner variant's lists:

```
score(d) = Σ over lists L containing d  of  1 / (k + rank_L(d))
```

with `k = 60`. RRF is robust to score-scale mismatches and avoids ad-hoc weighting.

### Cross-Encoder Reranker

- Model: `bge-reranker-v2-m3`, ONNX, INT8 quantized.
- Runs on a CPU pool (no GPU), dedicated to keep tail latency stable.
- Reranks the top-30 fused candidates → final top-8.
- Hard latency budget: **≤ 120 ms** per request for 30 candidates.

### MMR Diversification

After reranking, apply Maximal Marginal Relevance with `λ = 0.5` to:

- Avoid 8 near-duplicate log lines.
- Force at least one runbook chunk and one deploy/config chunk into the final set when available.

### Context Packing

- Token-budgeted: enforces a hard cap (e.g., `8k` tokens) regardless of the model's context window.
- Each chunk is wrapped with provenance:

```
[doc:{id} score:{rrf:0.91 rerank:0.78} src:{kind} svc:{service} ts:{ts}]
<chunk body>
```

The agent and critic only ever cite by `doc:{id}`.

## Filters and Tenancy

Filters are **always** enforced server-side:

- `tenant_id` from the OIDC claim.
- Time window from the request (defaults to `now - 1h`).
- `service` if extractable from the alert.
- `sensitivity ≤ caller's clearance`.

Clients may *narrow* but never *broaden* these filters.

## Caching

- **Query → result cache** (Redis, TTL `60s`), keyed by `hash(normalized_query | filters | tenant_id)`.
- **Embedding cache** (Redis, TTL `1h`), keyed by `hash(text | model_version)`.
- **Runbook cache** (CDN-backed, signed URLs) for static runbook chunks.
- Stampede protection via single-flight per cache key.

## Latency Budget (target ≤ 800 ms for retrieval as a whole)

| Stage | Target |
|---|---|
| Query plan (LLM) | 150 ms |
| BM25 + ANN (parallel) | 200 ms |
| RRF fusion | 5 ms |
| Reranker | 120 ms |
| MMR + dedupe | 5 ms |
| Pack | 20 ms |
| Cache fast path | ~10 ms |

Retrieval has a hard wall-clock deadline and must return *something*; see [08 — reliability-and-degradation](08-reliability-and-degradation.md) for the rerank → ANN → BM25 → cached-runbook fallback ladder.

## Quality Targets

- Recall@8 `≥ 0.85` on the offline eval set.
- nDCG@8 `≥ 0.75`.
- Citation coverage: every chunk in the final top-8 has a unique `doc_id` resolvable in Postgres.
