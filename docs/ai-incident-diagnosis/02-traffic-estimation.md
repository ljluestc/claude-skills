# 02 — Traffic Estimation

## Assumptions

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Tenants | 200 (year 1), 500 (year 3) | Mid-market + enterprise |
| Avg incidents / tenant / day | 15 | Mix of P1–P5 across a medium network |
| Diagnostic sessions / incident | 1.5 | Some incidents need multiple sessions |
| Queries / session | 6 | Conversational back-and-forth |
| Tool executions / session | 4 | 2–3 Tier-0 auto + 1 Tier-1 approval |
| Runbooks / tenant | 300 | Avg enterprise NOC knowledge base |
| Avg runbook size | 5 KB | Markdown, procedures + topology snippets |
| Chunk size | 512 tokens (~2 KB) | Standard RAG chunking |
| Chunks / runbook | 3 | After splitting with overlap |

## Read/Write QPS (Year 1 — 200 tenants)

### Incidents

```
Creates:  200 tenants × 15 incidents/day = 3,000/day ≈ 0.03 QPS
Reads:    ~10× writes (dashboards, polling) ≈ 0.3 QPS
Updates:  ~2× creates (status transitions) ≈ 0.07 QPS
```

### Diagnostic Queries (the hot path)

```
Sessions: 3,000 incidents × 1.5 = 4,500 sessions/day
Queries:  4,500 × 6 = 27,000 queries/day ≈ 0.31 QPS avg
Peak:     ~5× avg (incident storms) ≈ 1.5 QPS
```

Each query triggers:
- 1 BM25 search (ES)
- 1 dense vector search (Qdrant)
- 1 reranker inference
- 1 LLM generation call

### Tool Executions

```
Total:    4,500 sessions × 4 tools = 18,000/day ≈ 0.21 QPS avg
Peak:     ~1 QPS
Tier-0:   ~75% (auto-approved, <3s)
Tier-1/2: ~25% (requires human approval)
```

### Runbook Ingestion

```
Updates:  ~50 runbooks/day across all tenants (low-volume batch)
Chunks:   50 × 3 = 150 embed + index ops/day — negligible QPS
```

### Audit Events

```
Every API call + tool exec + AI query → ~80,000 events/day ≈ 0.9 QPS avg
Peak:     ~5 QPS
```

## Year 3 Projection (500 tenants)

| Metric | Year 1 (200T) | Year 3 (500T) |
|--------|---------------|----------------|
| Incidents/day | 3,000 | 7,500 |
| Diagnostic queries/day | 27,000 | 67,500 |
| Query QPS (avg / peak) | 0.31 / 1.5 | 0.78 / 4 |
| Tool executions/day | 18,000 | 45,000 |
| Audit events/day | 80,000 | 200,000 |
| Audit event QPS (avg / peak) | 0.9 / 5 | 2.3 / 12 |

> **Key insight:** QPS is moderate — this is not a social-media-scale system. The bottleneck is **latency per query** (LLM inference), not throughput. Design for low-latency, not high-throughput.

## Storage Estimates

### PostgreSQL (structured data)

```
Incidents:      7,500/day × 2 KB × 365 = ~5.5 GB/year
Sessions:       11,250/day × 1 KB × 365 = ~4 GB/year
Query turns:    67,500/day × 4 KB × 365 = ~98 GB/year
Tool execs:     45,000/day × 3 KB × 365 = ~49 GB/year
Approvals:      11,250/day × 0.5 KB × 365 = ~2 GB/year
Runbooks meta:  150K rows × 1 KB = ~150 MB (negligible)
────────────────────────────────────────────────────────
Total PG:       ~160 GB/year (year 3)
```

### Qdrant (vector embeddings)

```
Runbook chunks: 500 tenants × 300 runbooks × 3 chunks = 450,000 vectors
Vector size:    1024 dims × 4 bytes = 4 KB/vector
Metadata:       ~1 KB/vector
────────────────────────────────────────────────────────
Total Qdrant:   450K × 5 KB = ~2.25 GB
                With HNSW index overhead (~2×): ~5 GB
```

### Elasticsearch (BM25 + audit hot tier)

```
Runbook chunks: 450K docs × 3 KB = ~1.35 GB
Audit (30-day): 200K/day × 30 × 1 KB = ~6 GB
Past incidents: 7,500/day × 30 × 2 KB = ~450 MB
────────────────────────────────────────────────────────
Total ES hot:   ~8 GB
```

### S3 (long-term)

```
Runbook source:  150K × 5 KB = ~750 MB
Audit archive:   200K/day × 365 × 1 KB = ~73 GB/year (Parquet, compressed ~15 GB)
AI transcripts:  67,500/day × 365 × 5 KB = ~123 GB/year (compressed ~25 GB)
────────────────────────────────────────────────────────
Total S3:        ~40 GB/year (compressed)
```

## Bandwidth

```
Inbound:  Queries + tool params — negligible (<1 Mbps)
Outbound: SSE streams (avg 4 KB response × 0.78 QPS) ≈ 3 KB/s — negligible
Internal: ES/Qdrant search fan-out — ~50 KB per query × 0.78 QPS ≈ 40 KB/s
LLM API:  ~4K tokens/query × 0.78 QPS ≈ 3.1K tokens/s (input+output combined)
```

## LLM Token Budget

```
Input context:   ~3,000 tokens/query (chunks + metadata + history)
Output:          ~1,000 tokens/query
Total:           ~4,000 tokens/query
Daily (year 3):  67,500 × 4,000 = 270M tokens/day

Cost estimate (Claude Sonnet for P1/P2, Haiku for P3–P5):
  P1/P2 (~20%): 13,500 queries × 4K tokens × $15/1M = ~$810/day
  P3–P5 (~80%): 54,000 queries × 4K tokens × $1/1M  = ~$216/day
  Total: ~$1,026/day ≈ $31K/month
```

## Summary

| Resource | Year 3 Estimate |
|----------|----------------|
| Peak QPS (queries) | ~4 |
| Peak QPS (audit) | ~12 |
| PostgreSQL | ~160 GB/year |
| Qdrant | ~5 GB |
| Elasticsearch (hot) | ~8 GB |
| S3 (archive) | ~40 GB/year |
| LLM tokens | ~270M/day |
| LLM cost | ~$31K/month |
