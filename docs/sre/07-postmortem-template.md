# 07 — Postmortem Template

# Postmortem: <Incident Title>

## 1. Metadata
- **Incident ID:** `<inc-...>`
- **Date/Time (UTC):** `<start>` to `<end>`
- **Severity:** `<SEV1|SEV2|SEV3|SEV4>`
- **Status:** `Closed`
- **Incident Commander:** `<name>`
- **Authors:** `<name/team>`
- **Services Affected:** `<list>`
- **Customer Impacted:** `<yes/no + scope>`

## 2. Executive Summary

Brief, non-technical summary:
- What happened
- User/business impact
- How it was resolved

## 3. Impact

### User Impact
- affected users/tenants (% and count)
- visible symptoms

### Business Impact
- downtime or degradation duration
- SLA/SLO implications
- financial/reputational/compliance impact

## 4. Timeline (UTC)

| Time | Event |
|------|-------|
| `00:00` | First symptom |
| `00:05` | Alert fired |
| `00:10` | IC assigned |
| `00:20` | Mitigation attempt #1 |
| `...` | ... |
| `01:30` | Recovery confirmed |

## 5. Detection & Response Quality

- **MTTD:** `<duration>`
- **MTTA:** `<duration>`
- **MTTM:** `<duration>`
- **MTTR:** `<duration>`
- Which alerts fired (and which should have but didn’t)?
- Were runbooks used? Were they sufficient?

## 6. SLO / Error Budget Impact

| SLO | Target | Observed During Incident | Budget Burned |
|-----|--------|--------------------------|---------------|
| Availability | 99.9% | `<value>` | `<value>` |
| Diagnosis latency p99 | <8s | `<value>` | `<value>` |
| Retrieval quality | MRR@10 >=0.65 | `<value>` | `<value>` |
| Groundedness | >=98% | `<value>` | `<value>` |
| Tool execution success | >=99.5% | `<value>` | `<value>` |

## 7. Root Cause Analysis

### Primary Root Cause
`<technical cause>`

### Contributing Factors
1. `<factor>`
2. `<factor>`
3. `<factor>`

### Why Existing Controls Did/Did Not Catch It
- detection gap:
- prevention gap:
- response gap:

## 8. What Went Well

- `<item>`
- `<item>`

## 9. What Went Poorly

- `<item>`
- `<item>`

## 10. AI/RAG-Specific Analysis (required)

### Retrieval
- OpenSearch health:
- Qdrant health:
- MRR/NDCG delta:

### Groundedness
- citation coverage:
- unsupported-claim rate:

### Tool Execution
- success/failure mix:
- approval bottlenecks:

### Model Provider
- timeout/error behavior:
- failover behavior:

## 11. Corrective Actions

| Priority | Action | Owner | Due Date | Status |
|----------|--------|-------|----------|--------|
| P0 | `<must fix>` | `<owner>` | `<date>` | Open |
| P1 | `<important>` | `<owner>` | `<date>` | Open |
| P2 | `<nice to have>` | `<owner>` | `<date>` | Open |

## 12. Prevention Plan

- Monitoring/alert improvements
- Runbook updates
- Testing/chaos additions
- Deployment guardrails

## 13. Communication Artifacts

- Incident channel link:
- Status page updates:
- Customer communication copy:

## 14. Lessons Learned

- Key takeaways for engineering
- Key takeaways for operations
- Policy/process changes

## 15. Approval

- **IC Sign-off:** `<name/date>`
- **SRE Lead Sign-off:** `<name/date>`
- **Engineering Manager Sign-off:** `<name/date>`
