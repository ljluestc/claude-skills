# 01 — Requirements

## Problem Statement

Enterprise NOC/SRE teams diagnose network incidents manually — searching runbooks, SSHing into devices, correlating logs across systems. Diagnosis is slow (30–90 min MTTR for P1s), tribal-knowledge-dependent, and error-prone under pressure.

**NetDiag** is a multi-tenant platform that uses RAG-powered AI and controlled tool execution to accelerate incident diagnosis. An SRE describes symptoms in natural language; the system retrieves relevant runbooks, proposes and executes diagnostic commands (with human approval), and synthesizes findings into actionable recommendations.

## User Personas

| Persona | Role | Needs |
|---------|------|-------|
| **NOC Engineer** | First responder, triages alerts | Fast symptom-to-runbook matching, guided tool execution |
| **Senior SRE** | Deep diagnosis, approves mutating actions | Conversational AI diagnosis, tool approval workflows |
| **Team Lead** | Escalation target, reviews postmortems | Approval escalation, audit trail, MTTR dashboards |
| **Tenant Admin** | Manages org config, users, runbooks | SSO setup, model selection, tool policy, data retention |
| **Platform Operator** | Runs the NetDiag platform itself | Observability, scaling, multi-tenant isolation |

## Functional Requirements

### FR-1: Incident Management
- Create, update, and resolve incidents via API and webhook integrations (PagerDuty, Opsgenie, ServiceNow, Alertmanager).
- Incident lifecycle state machine: `Open → Triaging → Diagnosing → Mitigating → Resolved → Postmortem`.
- Severity classification (P1–P5) with structured metadata (affected devices, interfaces, topology).

### FR-2: AI-Assisted Diagnosis
- Conversational diagnostic sessions tied to an incident.
- Hybrid retrieval (BM25 + dense embeddings + cross-encoder reranker) over runbooks and past incident summaries.
- Structured AI responses: diagnosis text, confidence score, evidence with citations, proposed tool calls, follow-up questions.
- Model routing by incident severity (strongest model for P1/P2, cost-efficient for P3–P5).

### FR-3: Diagnostic Tool Execution
- Plugin-based tool registry (ping, traceroute, SNMP GET, `show` commands, packet capture, config diff, interface bounce, etc.).
- Three-tier risk model:
  - **Tier 0** — read-only, auto-approved.
  - **Tier 1** — read-only, requires single approval.
  - **Tier 2** — mutating, requires dual approval.
- Approval gate with timeout, auto-escalation, and auto-reject.
- Sandboxed execution with per-tenant network scoping.

### FR-4: Runbook Management
- CRUD with versioning (Markdown source in object storage).
- Automated ingestion pipeline: chunking → embedding → indexing into BM25 and vector stores.
- Git-sync mode for tenant runbook repositories.
- Team-scoped access control within a tenant.

### FR-5: Workflow Orchestration
- Multi-step diagnostic workflows (auto-triage, guided diagnosis, postmortem generation).
- Parallel tool fan-out, approval waits with timeout, iterative diagnosis loops.
- Durable execution with retry and compensation.

### FR-6: Audit & Compliance
- Immutable audit log for every API call, tool execution, approval decision, and AI interaction.
- Append-only storage with tamper detection (hash chains).
- Configurable retention (1–7 years). SOC 2 / ISO 27001 control mapping.

### FR-7: Multi-Tenancy
- Full tenant isolation at data, compute, and network layers.
- Per-tenant configuration: LLM model, allowed tools, approval policies, SSO, data retention.
- Tenant-level resource quotas and rate limiting.

## Non-Functional Requirements

| Requirement | Target |
|-------------|--------|
| **Query latency (p99)** | < 8 s (includes LLM inference) |
| **Query latency (p50)** | < 3 s |
| **Tool execution success** | > 99.5% |
| **API availability** | > 99.9% (43 min/month error budget) |
| **Retrieval relevance (MRR@10)** | > 0.65 |
| **Approval turnaround (p95)** | < 5 min |
| **Multi-region RTO** | < 5 min |
| **Audit log durability** | Zero data loss (`acks=all`) |
| **Max concurrent tenants** | 500+ |
| **Concurrent P1 sessions** | 50 per tenant |

## Constraints

- **Human-in-the-loop required** for all mutating network operations — no autonomous remediation.
- **LLM dependency** — platform must degrade gracefully (retrieval-only mode) when LLM providers are unavailable.
- **Network device credentials** must never be exposed to the AI model or persisted in logs.
- **Data residency** — tenant data must stay within the configured region.
- **Cloud-agnostic** — must deploy on EKS, GKE, and AKS with minimal cloud-specific code.
