# 03 — Runbook: Diagnosis Latency SLO Breach

## Purpose

Restore diagnosis query latency (`POST /sessions/{id}/query`) to SLO: p99 < 8s, p50 < 3s.

## Symptoms

- Alerts firing: `DiagnosisLatencyP99FastBurn`.
- User-facing symptom: delayed first token / stalled session responses.
- Increased queue depth in diagnosis workers.

## Quick Triage (first 10 minutes)

1. Check if issue is global or tenant-specific.
2. Check dependency health:
   - LLM provider timeout/error rate
   - Qdrant latency
   - OpenSearch latency/health
   - OPA decision latency (if auth path included)
3. Inspect latency stage breakdown dashboard.
4. Check recent deploys/config changes.

## Diagnostic Checks

### A) Query pipeline stage latency
- rewrite latency
- OpenSearch query latency
- Qdrant query latency
- reranker latency
- LLM TTFB and total tokens

### B) Resource saturation
- diagnosis pod CPU/memory throttling
- queue backlog
- node pressure / eviction events

### C) External dependency
- provider SLA/incident pages
- network egress errors

## Mitigation Playbook

### Mitigation 1: Degrade gracefully (fastest)
- Switch to smaller model for P3–P5.
- Reduce retrieval fanout (e.g., 50→20 per retriever).
- Shorten context window (last N turns + summary).
- Enable cached rewrite/retrieval where possible.

### Mitigation 2: Scale out
- Increase diagnosis worker replicas.
- Increase reranker worker replicas (GPU if available).
- Prioritize P1/P2 queue.

### Mitigation 3: Dependency failover
- Route to fallback LLM provider.
- If Qdrant slow/unavailable: BM25-only mode.
- If OpenSearch degraded: dense-only mode.

## Rollback

If latency regression started after a deploy:
1. Roll back diagnosis service to last known good release.
2. Roll back prompt/template or reranker config changes.
3. Verify p95 and p99 recovery over 15 minutes.

## Exit Criteria

- p99 < 8s and p50 < 3s sustained for 30 minutes.
- Burn-rate alerts cleared.
- No critical queue backlog.

## Communication

- Update incident channel every 15 minutes.
- If customer impact exists, post status-page update.

## Follow-up Actions

- Add regression test for slow stage.
- Add stage-level SLO (e.g., LLM TTFB budget).
- Capacity adjustment if saturation recurring.
