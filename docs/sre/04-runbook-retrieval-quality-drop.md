# 04 — Runbook: Retrieval Quality / Groundedness Drop

## Purpose

Recover retrieval quality (MRR/NDCG) and groundedness when answers become less relevant or less evidence-backed.

## Symptoms

- Alerts: `RetrievalQualityDrop`, `GroundednessDrop`.
- User complaints: “irrelevant suggestions”, “hallucinated root cause”.
- Citation coverage drops or citation mismatch rises.

## Quick Triage

1. Confirm whether issue is:
   - retrieval quality only,
   - groundedness only,
   - both.
2. Validate index freshness and ingestion pipeline status.
3. Check for recent changes in:
   - embedding model
   - reranker model
   - chunking strategy
   - prompt template

## Diagnostic Checks

### Retrieval Quality Checks
- Latest weekly eval metrics vs baseline:
  - `mrr@10`, `ndcg@10`, recall@k.
- OpenSearch query health (timeouts, shard failures).
- Qdrant vector search latency/errors.
- Drift in query rewrite output quality.

### Groundedness Checks
- Citation coverage trend.
- Evaluator-based hallucination rate.
- Fraction of responses with unsupported claims.
- Prompt changes that weakened citation constraints.

## Mitigation Playbook

### Mitigation 1: Safe retrieval mode
- Increase lexical weight in hybrid fusion.
- Require minimum citation count before final answer.
- Lower generation temperature for stability.

### Mitigation 2: Quality rollback
- Roll back embedding/reranker model to last stable version.
- Roll back chunker settings.
- Roll back prompt with strict grounded output schema.

### Mitigation 3: Data/Index repair
- Rebuild affected OpenSearch indices.
- Re-embed and reindex recent runbook changes.
- Backfill failed ingestion jobs.

## Rollback

If issue started after model/config release:
1. Restore previous model IDs and weights.
2. Restore previous retrieval fusion coefficients.
3. Re-run canary eval before broad rollout.

## Exit Criteria

- MRR@10 >= 0.65 and NDCG@10 >= 0.72.
- Groundedness pass rate >= 98%.
- Citation coverage and mismatch back to baseline band.

## Communication

- Notify AI and SRE channels.
- If severe, disable high-risk autonomous suggestions until groundedness restored.

## Follow-up Actions

- Add pre-prod retrieval/groundedness gates in CI.
- Add model-change canary rollout.
- Expand labeled eval set with failure examples from incident.
