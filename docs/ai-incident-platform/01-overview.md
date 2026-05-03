# 01 — Overview

## Purpose

The **AI Incident Diagnosis Platform** assists on-call engineers by ingesting operational telemetry (logs, metrics, configs, deploy events), retrieving the most relevant context for an active incident, and producing a grounded, cited diagnosis through a bounded agent loop.

The system is read-only by default. Remediation actions are always gated by human approval; the platform's job is to shorten **time-to-understanding**, not to auto-fix production.

## Goals

- **Faster MTTR** — surface likely root causes within seconds of an alert firing.
- **Grounded answers** — every claim cites the exact log line, metric series, runbook section, or config diff that supports it.
- **Reliability** — `99.9%` monthly availability, `P95 < 2s` for diagnosis responses.
- **Multi-cloud portability** — same control plane runs on EKS, GKE, and AKS.
- **Auditability** — every input, tool call, and model output is recorded to immutable storage.

## Non-Goals

- Autonomous remediation (out of scope for v1; sits behind a separate approval workflow).
- Replacing observability platforms (Datadog, Grafana, Splunk, etc.) — we consume their data and link back.
- General-purpose chat. The agent is constrained to the incident-diagnosis tool surface.

## High-Level Capabilities

| Capability | Summary |
|---|---|
| Ingestion | Streams logs, metrics, configs, deploys into a unified event bus (Kafka). |
| Hybrid retrieval | BM25 (OpenSearch) + dense ANN (Qdrant) + cross-encoder reranker, fused by RRF. |
| Bounded agent | Read-only tool set, hard step/token/wall-clock budgets, OPA-validated tool args. |
| Citations + critic | Every claim must cite a retrieved doc; a critic model verifies citations before response. |
| Observability | OpenTelemetry across all hops; SLIs and burn-rate alerts on latency, availability, freshness, and faithfulness. |
| Multi-region | Active/active per cloud, anycast routing, async cross-region replication for stateful tier. |
| Audit | WORM object store + append-only Postgres partition for runs and tool invocations. |

## Top-Level Quality Attributes

- **Latency:** P95 `< 2s` for end-to-end diagnose; first-token streaming `< 500ms`.
- **Availability:** `99.9%` monthly per region, higher globally via anycast.
- **Recall@8:** `≥ 0.85` on the offline retrieval eval set.
- **Citation faithfulness:** `≥ 0.95` (critic-verified).
- **Ingestion freshness:** P95 event-to-indexed `< 60s`.
- **Tenancy:** strict per-tenant isolation enforced at the storage adapter layer.

## Document Map

| # | Doc | Topic |
|---|---|---|
| 01 | [overview](01-overview.md) | This document. |
| 02 | [high-level-architecture](02-high-level-architecture.md) | System diagram, request paths, planes. |
| 03 | [ingestion-pipeline](03-ingestion-pipeline.md) | Kafka, normalization, PII redaction, embedding, indexing. |
| 04 | [hybrid-retrieval](04-hybrid-retrieval.md) | BM25 + ANN + reranker, RRF, MMR, filters. |
| 05 | [agent-orchestration](05-agent-orchestration.md) | Planner/executor/critic loop and budgets. |
| 06 | [tool-execution-and-opa](06-tool-execution-and-opa.md) | Tool schema, OPA policy, sandboxing. |
| 07 | [observability-and-slos](07-observability-and-slos.md) | OTel pipelines, SLIs, SLOs, burn-rate alerts. |
| 08 | [reliability-and-degradation](08-reliability-and-degradation.md) | Failure modes and the rerank → ANN → BM25 → cache ladder. |
| 09 | [multi-region-deployment](09-multi-region-deployment.md) | Active/active topology across EKS/GKE/AKS. |
| 10 | [architecture-decisions](10-architecture-decisions.md) | ADR-style record of major tradeoffs. |
