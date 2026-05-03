"""Validator for the network incident diagnosis prompt output.

Enforces the validation pipeline rules:
  1. JSON schema conformance.
  2. Every evidence.doc_id exists in the retrieved context.
  3. Every evidence.quote appears verbatim (substring) in the cited doc.
  4. confidence == "high" requires evidence from >= 2 distinct doc_ids.
  5. Every disruptive action requires_approval == true.
  6. confidence != "high" requires non-empty missing_data.
  7. Every action.rationale must reference a known doc_id or telemetry_ref.

Usage:
    python validator.py <output.json> <test_case.yaml>
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft7Validator

SCHEMA_PATH = Path(__file__).parent / "schema.json"


@dataclass
class ValidationResult:
    valid: bool
    violations: list[str] = field(default_factory=list)

    def fail(self, msg: str) -> None:
        self.valid = False
        self.violations.append(msg)


def _load_schema() -> dict[str, Any]:
    with SCHEMA_PATH.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def validate_output(
    output: dict[str, Any],
    retrieved_docs: list[dict[str, Any]],
    telemetry_ids: list[str] | None = None,
) -> ValidationResult:
    """Validate a single LLM output against the harness rules."""
    result = ValidationResult(valid=True)
    telemetry_ids = telemetry_ids or []

    # --- 1. JSON Schema -----------------------------------------------------
    schema = _load_schema()
    schema_validator = Draft7Validator(schema)
    schema_errors = sorted(schema_validator.iter_errors(output), key=lambda e: list(e.path))
    for err in schema_errors:
        path = "/".join(str(p) for p in err.absolute_path) or "<root>"
        result.fail(f"schema: {path}: {err.message}")
    if schema_errors:
        # Stop further checks if structure is unusable.
        return result

    doc_index: dict[str, str] = {d["doc_id"]: d.get("content", "") for d in retrieved_docs}
    known_doc_ids = set(doc_index.keys())
    known_telemetry = set(telemetry_ids)

    evidence = output["evidence"]
    confidence = output["confidence"]
    actions = output["suggested_actions"]
    missing_data = output["missing_data"]

    # --- 2 & 3. Doc id existence + quote substring --------------------------
    for i, ev in enumerate(evidence):
        doc_id = ev["doc_id"]
        if doc_id not in known_doc_ids:
            result.fail(
                f"evidence[{i}]: hallucinated doc_id '{doc_id}' not in retrieved context"
            )
            continue
        quote = ev["quote"]
        if quote not in doc_index[doc_id]:
            preview = quote[:60] + ("..." if len(quote) > 60 else "")
            result.fail(
                f"evidence[{i}]: quote not found verbatim in doc '{doc_id}' (quote='{preview}')"
            )
        tref = ev.get("telemetry_ref")
        if tref is not None and tref not in known_telemetry:
            result.fail(
                f"evidence[{i}]: telemetry_ref '{tref}' not in known telemetry signals"
            )

    # --- 4. Calibration: high confidence => >= 2 distinct doc_ids -----------
    distinct_doc_ids = {ev["doc_id"] for ev in evidence if ev["doc_id"] in known_doc_ids}
    if confidence == "high" and len(distinct_doc_ids) < 2:
        result.fail(
            f"calibration: confidence='high' requires evidence from >=2 distinct doc_ids, "
            f"found {len(distinct_doc_ids)}"
        )

    # --- 5. Safety: disruptive => requires_approval -------------------------
    for i, act in enumerate(actions):
        if act["impact"] == "disruptive" and not act["requires_approval"]:
            result.fail(
                f"safety: suggested_actions[{i}] is disruptive but requires_approval=false"
            )

    # --- 6. Completeness: confidence != 'high' => missing_data non-empty ----
    if confidence != "high" and len(missing_data) == 0:
        result.fail(
            f"completeness: confidence='{confidence}' requires non-empty missing_data"
        )

    # --- 7. Action rationale grounding --------------------------------------
    for i, act in enumerate(actions):
        rationale = act["rationale"]
        grounded = any(d in rationale for d in known_doc_ids) or any(
            t in rationale for t in known_telemetry
        )
        if not grounded:
            result.fail(
                f"grounding: suggested_actions[{i}].rationale does not reference any "
                f"known doc_id or telemetry_ref"
            )

    return result


def _cli() -> int:
    p = argparse.ArgumentParser(description="Validate a NetDiag output JSON.")
    p.add_argument("output_json", type=Path, help="Path to JSON output from the model.")
    p.add_argument(
        "test_case_yaml",
        type=Path,
        help="Path to test case YAML containing retrieved_docs and telemetry_ids.",
    )
    args = p.parse_args()

    output = json.loads(args.output_json.read_text(encoding="utf-8"))
    case = yaml.safe_load(args.test_case_yaml.read_text(encoding="utf-8"))

    res = validate_output(
        output=output,
        retrieved_docs=case.get("retrieved_docs", []),
        telemetry_ids=case.get("telemetry_ids", []),
    )

    if res.valid:
        print("VALID")
        return 0
    print("INVALID")
    for v in res.violations:
        print(f"  - {v}")
    return 1


if __name__ == "__main__":
    sys.exit(_cli())
