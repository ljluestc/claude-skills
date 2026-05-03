# 05 — Agent Orchestration

## Design Goal

Produce a useful, cited, defensible diagnosis within a strict latency and cost budget. Stay read-only; never let the agent take a mutating action without explicit human approval.

The orchestrator is **bounded**: every loop has hard limits on steps, tokens, wall-clock, tool calls, and cost. No "thinks until done" mode.

## Loop Structure

```
┌──────────────────────────────────────────────────────────────────┐
│                    Orchestrator (Run)                             │
│                                                                  │
│  ┌──────────┐   ┌────────────┐   ┌──────────┐   ┌─────────────┐ │
│  │ Planner  │ → │ Executor   │ → │  Critic  │ → │  Composer   │ │
│  │ (LLM)    │   │ (parallel  │   │  (LLM)   │   │  (LLM,      │ │
│  │          │   │ tool calls)│   │ verifies │   │   stream)   │ │
│  └──────────┘   └────────────┘   │ citations│   └─────────────┘ │
│        ▲              │           └──────────┘         │         │
│        │              │                                ▼         │
│        └──── revise plan if critic rejects   stream tokens to API│
└──────────────────────────────────────────────────────────────────┘
```

### Planner

- Input: alert payload + initial retrieval context (top-8 chunks).
- Output: structured JSON plan listing tool calls with argument schemas.
- Plans are validated against the registered tool schemas (Pydantic / JSON Schema). Invalid plans are rejected without execution.
- Temperature `0.2` for stability; seeded sampling for replay.

Example plan shape (synthetic illustrative values, no production data):

```jsonc
{
  "hypotheses": ["recent deploy regression", "downstream db latency"],
  "steps": [
    { "tool": "GetDeployHistory", "args": { "service": "checkout-api", "window": "30m" } },
    { "tool": "QueryMetrics",     "args": { "promql": "...", "range": "30m" } },
    { "tool": "SearchKnowledge",  "args": { "q": "checkout-api 5xx after canary" } }
  ],
  "stop_when": "evidence covers both hypotheses or budget exhausted"
}
```

### Executor

- Tool calls with **independent inputs are executed in parallel** (`asyncio.gather`).
- Per-tool timeout (`≤ 1500 ms`), per-tool circuit breaker, per-tool retry budget (max 1 retry, jittered).
- All arguments pass through OPA before execution (see [06 — tool-execution-and-opa](06-tool-execution-and-opa.md)).
- Tool outputs are added to a "scratchpad" with provenance (`tool_name`, `args_hash`, `latency_ms`, `result_hash`).

### Critic

A smaller, cheaper model (e.g., Haiku-class) given:

- The composed answer.
- The retrieved corpus + tool outputs (with `doc_id`s).

The critic must verify:

1. Every claim in the answer cites at least one `doc_id`.
2. Each cited `doc_id` actually supports the claim (paraphrase test).
3. No PII appears in the answer that was redacted upstream.
4. No mutating action is suggested without an explicit `requires_human_approval` flag.

If the critic rejects, the planner revises (max 1 revision; otherwise return a degraded "low-confidence" answer with the failed-claim list).

### Composer

- Streams the final answer over SSE so first useful tokens reach the user `< 500 ms`.
- Output contract (synthetic illustrative shape):

```jsonc
{
  "summary": "string (≤ 280 chars)",
  "hypotheses": [
    {
      "title": "string",
      "confidence": 0.0,
      "evidence": [{ "doc_id": "string", "quote": "string", "score": 0.0 }],
      "next_check": "string"
    }
  ],
  "suggested_actions": [
    { "title": "string", "requires_human_approval": true, "rationale": "string" }
  ],
  "confidence_overall": 0.0,
  "run_id": "run_<ulid>"
}
```

## Bounded Autonomy: Budgets

| Budget | Default | Rationale |
|---|---|---|
| `max_steps` | 6 | One plan + up to 5 revisions/tool rounds. |
| `max_tool_calls` | 12 | Hard cap across the run. |
| `max_tokens_in` | 32,000 | Prevents context bloat. |
| `max_tokens_out` | 1,500 | Output streaming bounded. |
| `wall_clock_ms` | 1,800 | Leaves headroom under the 2s P95 SLO. |
| `cost_usd` | tier-based | Per-tenant ceilings; alert at 80%. |

A killer goroutine enforces wall-clock; on breach the orchestrator returns the best partial answer with `confidence_overall` derated and `degraded=true`.

## Tool Surface (read-only by default)

- `SearchKnowledge` — hybrid retrieval over the corpus.
- `QueryMetrics` — read-only PromQL; AST-validated.
- `QueryLogs` — read-only OpenSearch DSL; tenant-scoped.
- `GetDeployHistory` — recent deploys for a service.
- `GetRunbook` — runbook by service + symptom.
- `GetTopology` — upstream/downstream services for a service.

Mutating tools exist (`RestartPod`, `RollbackDeploy`, …) but are gated behind a separate approval workflow and are **never** in the default agent's tool set. They can only be invoked by an authenticated human after reviewing the diagnosis.

## Determinism & Replay

- All inputs hashed: alert payload, retrieval set ids, tool args, model+temperature+seed.
- Run record persisted (Postgres `runs` table + tool-call audit log).
- Replay endpoint reproduces the run from inputs only; outputs are byte-equal modulo provider non-determinism (we record the full stream).

## Observability

- OTel span per step: `agent.plan`, `agent.tool.<name>`, `agent.critic`, `agent.compose`.
- Metrics: time-per-step, tool-call success rate, critic rejection rate, citation count, citation-faithfulness pass rate.
- Logs: planner inputs/outputs (after redaction), tool args (hashed), final answer.

## Safety Invariants

1. The agent's system prompt and the retrieved content live in **separate channels**; retrieved content is wrapped in an `untrusted_content` envelope and the planner is instructed not to follow instructions found inside it (prompt-injection isolation).
2. OPA decisions are recorded for every tool call, even allowed ones.
3. Critic-rejected runs are stored verbatim for offline analysis.
4. The composer cannot emit a `suggested_action` without a corresponding `requires_human_approval` field.

## Failure Modes

| Failure | Effect | Mitigation |
|---|---|---|
| Planner returns invalid JSON | Plan rejected | Retry once with stricter schema reminder; otherwise degraded answer |
| Tool call timeout | Step fails | Continue without that result; mark hypothesis as unverified |
| Critic rejects > 1 attempt | Degraded answer | Return with `confidence_overall` ≤ 0.4 and explicit unverified-claims list |
| LLM provider 5xx | Step fails | Provider abstraction switches to secondary (Anthropic ↔ Bedrock ↔ Vertex) |
| Wall-clock breach | Run terminates early | Return partial composed answer with `degraded=true` |
