# 05 — Runbook: Tool Execution Failure

## Purpose

Restore tool execution reliability (SLO >= 99.5% success) for diagnostic commands.

## Symptoms

- Alert: `ToolExecutionFailureRateHigh`.
- Increased `failed` or `timed_out` statuses.
- Longer approval-to-result time.
- Repeated failures for specific tools or target device groups.

## Quick Triage

1. Determine blast radius:
   - single tool vs many tools
   - single tenant vs global
2. Check failure class distribution:
   - timeout
   - auth/credential
   - network policy/connectivity
   - runtime/container failure
3. Check kill-switch status (tenant/global).

## Diagnostic Checks

### Runtime & Scheduler
- Tool worker pod health, restarts, OOMKilled events.
- Queue depth and worker saturation.

### Network Path
- Egress policy changes.
- DNS/connectivity to target devices.
- Firewall deny logs.

### Credentials
- Vault token/lease validity.
- secret mount/injection errors.
- target device auth failures.

### Policy / Approval
- OPA decision errors or high denial rates.
- Approval workflow timeout spikes.

## Mitigation Playbook

### Mitigation 1: Stabilize service
- Scale tool workers.
- Increase timeout only for known slow but safe read-only tools.
- Pause flaky mutating tools (Tier-2) if needed.

### Mitigation 2: Fallback paths
- Route to backup credential path if primary vault path down.
- Fail open/closed policy based on risk mode:
  - Tier-0 may use cached policy snapshot.
  - Tier-1/2 remain fail-closed.

### Mitigation 3: Isolate bad actors
- Disable failing tool plugin version.
- Quarantine problematic tenant config.
- Apply per-tool circuit breaker.

## Rollback

If regression tied to deploy:
1. Roll back tool-runner image/plugin version.
2. Restore previous OPA policy bundle.
3. Restore previous network policy manifest.

## Exit Criteria

- Tool success rate >= 99.5% for 60 minutes.
- Timeout rate and failure rate back to baseline.
- No pending approval backlog breach.

## Communication

- Provide 15-minute updates during active SEV.
- Inform support teams if diagnostic automation is degraded.

## Follow-up Actions

- Add canary tests for each tool plugin version.
- Add synthetic probes for vault + target-device auth.
- Tune timeout defaults per tool class.
