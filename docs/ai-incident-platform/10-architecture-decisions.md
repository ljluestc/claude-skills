# 10 — Architecture Decision Records

ADR-style log of the major design choices. Each record captures **context**, **decision**, **consequences**, and **alternatives considered**.

---

## ADR-001 — Kafka as the Ingestion Backbone

**Status:** Accepted

**Context.** We need to absorb 100× burst loads from logs/metrics/configs/deploys without back-pressuring producers, and we need replayable streams for re-indexing.

**Decision.** Use Apache Kafka (managed via MSK / Confluent Cloud, or self-hosted on K8s with Strimzi) as the event backbone. Topics: `events.raw`, `events.normalized`, `events.enriched`, `embeddings.requests`, plus `events.deadletter`.

**Consequences.**
- High burst tolerance and durable ordering by partition key (`tenant_id+service`).
- MirrorMaker 2 enables cross-region/cross-cloud DR replication.
- Operationally heavier than a managed Pub/Sub-style queue.
- Extra latency floor (~seconds) versus direct writes; acceptable because retrieval is on the synchronous path, not ingestion.

**Alternatives.** Cloud Pub/Sub (lower ops, less portable across clouds); direct writes (no replay, fragile under burst).

---

## ADR-002 — Hybrid Retrieval (BM25 + Dense ANN + Reranker)

**Status:** Accepted

**Context.** Incident queries are sometimes lexical (UUIDs, stack frames) and sometimes semantic (symptom prose). Neither alone meets the recall@8 ≥ 0.85 target.

**Decision.** Combine OpenSearch BM25 + Qdrant HNSW dense retrieval, fuse via Reciprocal Rank Fusion (k=60), then rerank top-30 with a cross-encoder (`bge-reranker-v2-m3`) into top-8.

**Consequences.**
- +15–25 pts recall on log queries with rare tokens vs. dense-only.
- +120 ms latency budget for the reranker.
- Two storage stacks to operate.

**Alternatives.** Pure dense (cheap, simpler, but worse on rare tokens); pure BM25 (worse on natural-language queries); LLM-as-reranker (more accurate but breaks the 2s budget).

---

## ADR-003 — Cross-Encoder Reranker over LLM Reranker

**Status:** Accepted

**Context.** Reranker quality vs latency tradeoff inside the 2s end-to-end budget.

**Decision.** Use a small cross-encoder ONNX-quantized to INT8 on a CPU pool. Hard 120 ms budget for top-30.

**Consequences.**
- Predictable tail latency, no GPU contention.
- Slightly worse than LLM-as-reranker on edge cases, but recoverable via the planner+critic loop.

**Alternatives.** LLM rerank (rejected on latency); no rerank (rejected on quality, kept as rung-2 fallback).

---

## ADR-004 — Bounded Agent Loop, Read-Only by Default

**Status:** Accepted

**Context.** A free-running agent is a cost, latency, and safety risk. Auto-remediation can take wrong actions in production.

**Decision.** Hard budgets on steps, tool calls, tokens, wall-clock, and cost. Default tool surface is read-only; mutating tools require human approval and a separate workflow.

**Consequences.**
- Slower MTTR than auto-fix, but avoids wrong-fix incidents.
- Predictable cost envelope per run.
- Remediation is a separate, optional product surface.

**Alternatives.** Open-ended ReAct (rejected on cost/safety); fully autonomous remediation (rejected; no auditable approval path).

---

## ADR-005 — Strict Citations + Critic Step

**Status:** Accepted

**Context.** Hallucinated diagnoses erode operator trust and can mislead during incidents.

**Decision.** Every claim in the answer must cite at least one retrieved `doc_id`. A separate, smaller critic model verifies citations via paraphrase test before the composer streams to the user. On rejection, the planner revises once.

**Consequences.**
- ~10% latency overhead.
- Substantial increase in operator trust; objectively measurable via the citation-faithfulness SLI (`≥ 0.95`).
- Adds a critic-rejection-rate signal that detects hallucination drift across model upgrades.

**Alternatives.** Free-form answers (rejected; not auditable); rule-based grounding only (rejected; brittle).

---

## ADR-006 — OPA for Tool-Argument Policy

**Status:** Accepted

**Context.** Prompt injection in retrieved logs can cause the model to construct dangerous or out-of-scope tool args. We need a policy boundary outside the model.

**Decision.** Every tool call is validated against Rego policies in an OPA sidecar before execution. Decisions are logged to the WORM bucket alongside the audit log.

**Consequences.**
- Adds a `~5 ms` decision hop (cached for hot paths).
- Centralizes policy in a reviewable repo with required security signoff.
- Defense in depth alongside in-process schema validation.

**Alternatives.** App-level checks only (rejected; less centralized, harder to audit); policy in the LLM prompt (rejected; trivially bypassed).

---

## ADR-007 — OpenTelemetry as the Single Telemetry Standard

**Status:** Accepted

**Context.** We need consistent traces, metrics, and logs across many languages, clouds, and components.

**Decision.** All services instrument with the OTel SDK. Per-region OTel Collectors fan out to Tempo/Mimir/Loki. Trace context propagates through Kafka headers and the agent loop.

**Consequences.**
- Vendor-neutral; portable across clouds.
- Easier root-cause: one trace from gateway through agent through tool through storage.
- Slightly higher integration effort vs. a single-vendor APM.

**Alternatives.** Vendor APM (lock-in, harder portability); custom logging only (no joinable traces).

---

## ADR-008 — Self-Hosted Qdrant on K8s for Vector DB

**Status:** Accepted

**Context.** We require a vector DB available in EKS, GKE, and AKS with consistent ops and per-tenant sharding.

**Decision.** Run Qdrant on K8s (StatefulSet with PVCs, RF≥2 per shard). Snapshots to per-region object store every 15m. Per-tenant shards by hash; payload indexes on `service`, `env`, `kind`, `ts`.

**Consequences.**
- Portable across all three clouds with the same Helm chart.
- Need a small platform team to operate and tune HNSW params.
- Higher control vs. a managed service (filtered ANN, tunable `M`/`ef`, payload indexes).

**Alternatives.** Pinecone/Vertex Vector (managed, less portable); pgvector (operationally simpler but slower at scale); Weaviate (viable but team familiarity tilts to Qdrant).

---

## ADR-009 — Multi-Cloud Active/Active

**Status:** Accepted

**Context.** Reliability target `99.9%` plus regulatory constraints (data residency in EU/APAC) and concentration risk if a single cloud has a major outage.

**Decision.** Active/active across at least two regions on each of EKS, GKE, AKS. Anycast routing. Per-tenant single-writer for metadata. Async cross-cloud replication for stateful tier; sync replication only for the audit log.

**Consequences.**
- Higher infra cost and ops complexity (three control planes).
- Higher cross-cloud egress (mitigated with caps and replication tiering).
- Significantly stronger blast-radius containment.

**Alternatives.** Single cloud with multi-region DR (cheaper, simpler, fails the cloud-outage scenario); single cloud only (rejected; concentration risk + sovereignty).

---

## ADR-010 — Per-Tenant Logical Isolation, Physical Only for Regulated Tenants

**Status:** Accepted

**Context.** Hundreds of tenants; cost-prohibitive to give each one dedicated clusters. Some regulated tenants require stronger isolation.

**Decision.** Default isolation is logical: enforced via storage-adapter filters baked into the request context, plus contract tests on every PR. Regulated tenants can opt into physical isolation (dedicated namespaces, dedicated Kafka clusters, dedicated Qdrant shards).

**Consequences.**
- Cost-efficient default with strong defense in depth.
- Optional escape hatch for compliance-driven workloads.
- Two operational modes; well-typed via tenant-tier configuration.

**Alternatives.** Always physical (cost prohibitive); always logical (rejected; can't satisfy some regulators).

---

## ADR-011 — Streaming Diagnose Responses (SSE)

**Status:** Accepted

**Context.** Operators need a useful first signal as fast as possible during an active incident.

**Decision.** `POST /v1/diagnose` streams via SSE. The composer emits the summary first, then evidence; full critic verification happens before the *first user-visible token* leaves the gateway.

**Consequences.**
- Users see meaningful content within `< 500 ms`.
- Idempotency requires a `run_id` on retries; canonical responses replay from the runs table.
- Partial-failure handling: retry resumes from the last emitted token offset.

**Alternatives.** Single JSON response (rejected; bad UX during incidents); bidi gRPC streaming (more capable, but SSE is universally supported by clients).

---

## ADR-012 — Immutable Audit Log

**Status:** Accepted

**Context.** Every diagnosis must be reconstructible after the fact for compliance, postmortems, and red-team analysis.

**Decision.** Two immutable sinks for run inputs, tool calls, OPA decisions, and model outputs:
1. Append-only Postgres partition with row-level triggers preventing UPDATE/DELETE.
2. WORM object store (S3 / GCS / Azure Blob) with object lock + versioning, double-written cross-cloud.

**Consequences.**
- True replayability and tamper-evidence.
- Storage cost; mitigated by content-addressed deduplication and tiered retention.
- Audit-write latency must be monitored; an async writer with bounded queue + backpressure alarm.

**Alternatives.** Single Postgres-only audit (rejected; single point of failure for compliance); third-party SaaS audit (rejected; multi-cloud parity and sovereignty concerns).

---

## ADR-013 — Provider Abstraction for LLMs

**Status:** Accepted

**Context.** Single-provider lock-in is a reliability and pricing risk.

**Decision.** All model calls go through a provider-abstraction layer that supports Anthropic API, AWS Bedrock, and Google Vertex. Primary/secondary configured per environment. Failover on `5xx` or sustained latency breach.

**Consequences.**
- Higher complexity in the abstraction (capability flags, parameter mapping).
- Stronger reliability and pricing leverage.
- Eval harness must be run on each candidate provider routinely.

**Alternatives.** Single provider (rejected on availability); two providers (acceptable interim; chose three for stronger redundancy).

---

## ADR-014 — Outbox Pattern for Atomic Indexing

**Status:** Accepted

**Context.** A document must appear in OpenSearch, Qdrant, and Postgres consistently — never in only one.

**Decision.** Workers write Postgres (`documents`) plus an `outbox` row in a single transaction. A Debezium CDC tailer emits outbox rows to a relay topic; downstream indexers fan out to OpenSearch and Qdrant idempotently. Reconciliation job re-emits unacked rows.

**Consequences.**
- Eventual consistency across stores within seconds.
- No 2PC; resilient to indexer outages.
- Outbox table requires periodic compaction.

**Alternatives.** Distributed transactions (rejected; brittle, slow); fire-and-forget writes (rejected; drift between stores).

---

## ADR-015 — Error-Budget Policy Drives Release Cadence

**Status:** Accepted

**Context.** Reliability and feature velocity must be balanced explicitly.

**Decision.** When the 30-day diagnose-availability budget burns `> 50%` in `< 25%` of the window, non-critical releases are frozen, on-call is paged, and model upgrades are blocked until the burn rate normalizes.

**Consequences.**
- Predictable, automated reliability gating.
- Occasional release freezes during incidents; product teams plan for it.
- Cultural alignment between dev and SRE on what "shipping responsibly" means.

**Alternatives.** Subjective release decisions (rejected; inconsistent); always block on any burn (rejected; brittle).

---

## Index

| ADR | Topic |
|---|---|
| 001 | Kafka as ingestion backbone |
| 002 | Hybrid retrieval (BM25 + ANN + reranker) |
| 003 | Cross-encoder reranker vs LLM reranker |
| 004 | Bounded agent loop, read-only default |
| 005 | Strict citations + critic |
| 006 | OPA tool-argument policy |
| 007 | OpenTelemetry as the standard |
| 008 | Self-hosted Qdrant on K8s |
| 009 | Multi-cloud active/active |
| 010 | Logical tenant isolation by default |
| 011 | SSE streaming diagnose responses |
| 012 | Immutable audit log |
| 013 | LLM provider abstraction |
| 014 | Outbox pattern for atomic indexing |
| 015 | Error-budget-driven release cadence |
