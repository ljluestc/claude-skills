# Incident Diagnosis Eval Harness

A repo-ready validation pipeline for the **network incident diagnosis** RAG prompt.
The harness verifies that LLM outputs are well-formed, grounded in retrieved
documents, calibrated honestly, and safe to act on.

## Layout

```
evals/incident_diagnosis/
├── schema.json          # JSON Schema (Draft-7) for the LLM output
├── validator.py         # Library + CLI: enforces all pipeline rules
├── test_cases.yaml      # Golden + adversarial cases
├── test_validator.py    # Pytest suite (parametrized over YAML)
└── README.md            # This file
```

## Validation rules

| # | Rule | Source field |
|---|------|--------------|
| 1 | Output conforms to `schema.json` (Draft-7) | full doc |
| 2 | Every `evidence[].doc_id` exists in retrieved context | `evidence[].doc_id` |
| 3 | Every `evidence[].quote` appears verbatim (substring match) in its cited doc | `evidence[].quote` |
| 4 | `confidence == "high"` requires evidence from **>= 2 distinct doc_ids** | `evidence[]`, `confidence` |
| 5 | Any `suggested_actions[]` with `impact == "disruptive"` must have `requires_approval == true` | `suggested_actions[]` |
| 6 | If `confidence != "high"`, `missing_data` must be non-empty | `confidence`, `missing_data` |
| 7 | Every `suggested_actions[].rationale` must reference a known `doc_id` or `telemetry_ref` | `suggested_actions[].rationale` |
| extra | Every non-null `evidence[].telemetry_ref` must be a known telemetry id | `evidence[].telemetry_ref` |

## Install

The harness uses only stdlib + two small deps:

```bash
pip install pytest pyyaml jsonschema
```

## Run

From the repo root:

```bash
pytest evals/incident_diagnosis/ -v
```

To validate a single LLM output against a single test case (CLI mode):

```bash
python evals/incident_diagnosis/validator.py path/to/output.json evals/incident_diagnosis/test_cases.yaml
```

CLI exit codes:
- `0` — VALID
- `1` — INVALID (violations printed to stdout)

## Test cases included

| Case | Expected | What it covers |
|------|----------|----------------|
| `happy_path_high_confidence` | PASS | Two corroborating docs, telemetry match, safe + approved disruptive action |
| `hallucinated_doc_id` | FAIL | Cites `RB-999` not present in retrieved docs |
| `missing_evidence_quote` | FAIL | Quote not found verbatim in the cited doc |
| `unsafe_disruptive_action` | FAIL | Disruptive action with `requires_approval=false` |
| `low_confidence_without_missing_data` | FAIL | `confidence="low"` but `missing_data=[]` |
| `conflicting_evidence_medium_confidence` | PASS | Two competing docs, honest medium confidence with `missing_data` populated |
| `high_confidence_single_doc_id_should_fail_calibration` | FAIL | `confidence="high"` with only one supporting doc |

## Adding a new test case

Append to `cases:` in `test_cases.yaml`:

```yaml
- name: my_new_scenario
  retrieved_docs:
    - doc_id: RB-321
      content: "verbatim runbook text the model may quote"
  telemetry_ids: ["s1"]
  output:
    root_cause: "..."
    confidence: medium
    evidence:
      - doc_id: RB-321
        quote: "verbatim runbook text"
        telemetry_ref: s1
        relevance: "..."
    suggested_actions:
      - action: "..."
        rationale: "RB-321 says ..."
        impact: safe
        requires_approval: false
        rollback: null
    unsupported_hypotheses: []
    missing_data: ["..."]
  expected:
    valid: true
    violation_substrings: []
```

The pytest run will auto-discover it.

## CI example (GitHub Actions)

`.github/workflows/eval-incident-diagnosis.yml`:

```yaml
name: eval-incident-diagnosis

on:
  push:
    paths:
      - "evals/incident_diagnosis/**"
      - ".github/workflows/eval-incident-diagnosis.yml"
  pull_request:
    paths:
      - "evals/incident_diagnosis/**"

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
          cache: "pip"

      - name: Install deps
        run: pip install pytest pyyaml jsonschema

      - name: Run validator eval suite
        run: pytest evals/incident_diagnosis/ -v --tb=short --junitxml=eval-report.xml

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: eval-report
          path: eval-report.xml
```

## Wiring into the LLM serving path

The validator is import-safe; production code can call it directly:

```python
from evals.incident_diagnosis.validator import validate_output

result = validate_output(
    output=model_response_json,
    retrieved_docs=rag_docs,            # list of {doc_id, content}
    telemetry_ids=incident_signal_ids,  # list of str
)

if not result.valid:
    # Re-prompt the model with the specific violations:
    retry_prompt = "Your previous output was rejected:\n" + "\n".join(
        f"- {v}" for v in result.violations
    )
    ...
```

This closes the loop required by failure-mode mitigations 1, 2, 3, 5, 8, 10, and 12
in the prompt's design doc.

## License

Same license as the parent repository.
