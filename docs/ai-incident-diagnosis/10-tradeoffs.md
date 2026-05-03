# 10 — Tradeoffs

## Decision Framework

Each architecture choice optimizes across four axes:
- **Safety**
- **Latency**
- **Cost**
- **Operational complexity**

No choice wins on all four; this document captures intentional compromises.

---

## T1 — Hybrid Retrieval vs Simpler Retrieval

### Chosen
BM25 + dense embeddings + cross-encoder reranker.

### Alternative
Dense-only or BM25-only retrieval.

### Why Chosen
Network incidents contain both:
- exact lexical artifacts (IP addresses, interface names, error strings),
- semantic context (similar symptoms described differently).

Hybrid retrieval consistently improves recall and answer grounding.

### Cost
- More infra components (ES + Qdrant + reranker).
- More tuning and observability overhead.

### Trigger to Revisit
If offline eval shows negligible gains (<3% MRR lift) for 3 consecutive months.

---

## T2 — Human Approval Gates vs Autonomous Actions

### Chosen
Tiered approvals: Tier-0 auto, Tier-1 single approval, Tier-2 dual approval.

### Alternative
Fully autonomous AI tool execution.

### Why Chosen
Production network changes are high-risk and often regulated. Human-in-the-loop is required for safety and compliance.

### Cost
- Slower remediation for some incidents.
- Additional UX complexity for approval workflows.

### Trigger to Revisit
If a tenant opts into controlled automation for specific low-risk Tier-1 operations with proven safety controls.

---

## T3 — Shared Multi-Tenant Infra vs Dedicated Per-Tenant

### Chosen
Shared control plane/data plane with strict logical isolation (RLS, per-tenant indices/collections, OPA policies).

### Alternative
Full dedicated stack per tenant.

### Why Chosen
Shared infrastructure provides better cost efficiency and easier operations for most tenants.

### Cost
- Noisy-neighbor risk without careful quotas and scheduling.
- Stronger burden on isolation correctness.

### Trigger to Revisit
Large regulated tenants can be promoted to dedicated clusters as a paid tier.

---

## T4 — Temporal Workflows vs Simple Queue Consumers

### Chosen
Temporal for durable, stateful, multi-step orchestration.

### Alternative
Kafka consumers + custom retry/state management.

### Why Chosen
Diagnostic workflows involve timers, approvals, retries, and compensation — Temporal simplifies correctness and visibility.

### Cost
- Additional operational component and learning curve.
- Workflow code discipline required.

### Trigger to Revisit
Unlikely; this decision is foundational unless workflow complexity drops significantly.

---

## T5 — SSE Streaming vs Request-Response

### Chosen
SSE for query responses.

### Alternative
Blocking request/response with final payload only.

### Why Chosen
Time-to-first-token matters for operator UX; streaming improves perceived latency and transparency.

### Cost
- Client implementation complexity.
- Connection management overhead.

### Trigger to Revisit
If clients standardize on WebSocket for all real-time features; SSE could be consolidated.

---

## T6 — Active-Passive Multi-Region vs Active-Active

### Chosen
Active-passive for initial production.

### Alternative
Active-active global architecture.

### Why Chosen
Active-passive provides strong resilience with much lower consistency and routing complexity.

### Cost
- Standby region underutilization.
- Failover still incurs short disruption.

### Trigger to Revisit
If global low-latency requirements or regional sovereignty constraints demand active-active.

---

## T7 — Managed LLM APIs vs Self-Hosted Models

### Chosen
Managed APIs first, optional self-hosted fallback.

### Alternative
Fully self-hosted model serving from day one.

### Why Chosen
Faster time-to-market, higher baseline model quality, lower MLOps burden.

### Cost
- Vendor dependency and variable inference cost.
- Data governance concerns for some enterprises.

### Trigger to Revisit
If monthly token spend crosses threshold where self-hosted TCO is lower at required quality.

---

## T8 — Strict Schema Validation vs Flexible Free-Text AI Output

### Chosen
Strict structured output schema with validation/retry.

### Alternative
Accept free-text responses and parse heuristically.

### Why Chosen
Safety and tool-execution correctness require machine-parseable outputs.

### Cost
- Occasional valid responses rejected due to formatting.
- Slight latency overhead for validation/retry.

### Trigger to Revisit
Only if model reliability makes strict schema failures negligible.

---

## T9 — Per-Tenant Data Isolation in Shared DB vs Separate DB per Tenant

### Chosen
Shared cluster with Citus + RLS + tenant key distribution.

### Alternative
Database-per-tenant.

### Why Chosen
Better operational scalability and lower baseline cost for medium tenants.

### Cost
- Strong requirement for defense-in-depth and continuous isolation testing.

### Trigger to Revisit
Highly regulated tenants may require separate physical databases.

---

## T10 — Cost vs Performance in Model Routing

### Chosen
Severity-aware routing (premium models for P1/P2, economical models for P3–P5).

### Alternative
Single high-end model for all requests.

### Why Chosen
Preserves high quality where it matters most while controlling cost.

### Cost
- Response quality variance across severities.
- More routing logic and monitoring complexity.

### Trigger to Revisit
If lower-cost models achieve near parity on internal benchmark suites.

---

## Final Position

The architecture intentionally prioritizes:
1. **Safety and controllability** over full automation speed.
2. **Grounded retrieval quality** over minimal stack simplicity.
3. **Operational resilience** over lowest short-term infrastructure cost.

These tradeoffs are appropriate for production network operations where incorrect automation can create widespread outages.
