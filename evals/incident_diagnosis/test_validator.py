"""Pytest suite for the incident diagnosis validator.

Run from the repo root:
    pytest evals/incident_diagnosis/ -v

Each YAML case is parametrized into a single pytest item.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import pytest
import yaml

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))

from validator import validate_output  # noqa: E402

CASES_PATH = HERE / "test_cases.yaml"


def _load_cases() -> list[dict[str, Any]]:
    with CASES_PATH.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    return data["cases"]


CASES = _load_cases()


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_validator_case(case: dict[str, Any]) -> None:
    result = validate_output(
        output=case["output"],
        retrieved_docs=case.get("retrieved_docs", []),
        telemetry_ids=case.get("telemetry_ids", []),
    )

    expected = case["expected"]
    expected_valid: bool = expected["valid"]
    expected_substrings: list[str] = expected.get("violation_substrings", []) or []

    joined_violations = "\n".join(result.violations)

    if expected_valid:
        assert result.valid, (
            f"expected case '{case['name']}' to PASS but got violations:\n{joined_violations}"
        )
        assert result.violations == [], (
            f"case '{case['name']}' marked valid but violations are non-empty: "
            f"{result.violations}"
        )
    else:
        assert not result.valid, (
            f"expected case '{case['name']}' to FAIL but validator returned valid=True"
        )
        for needle in expected_substrings:
            assert needle in joined_violations, (
                f"case '{case['name']}' missing expected violation substring '{needle}'.\n"
                f"actual violations:\n{joined_violations}"
            )


def test_cases_file_loads() -> None:
    """Sanity check: YAML loads and required scenarios are present."""
    names = {c["name"] for c in CASES}
    required = {
        "happy_path_high_confidence",
        "hallucinated_doc_id",
        "missing_evidence_quote",
        "unsafe_disruptive_action",
        "low_confidence_without_missing_data",
        "conflicting_evidence_medium_confidence",
        "high_confidence_single_doc_id_should_fail_calibration",
    }
    missing = required - names
    assert not missing, f"required test cases missing from test_cases.yaml: {missing}"
