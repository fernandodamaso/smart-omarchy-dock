#!/usr/bin/env python3
"""Pure FDM-816 feasibility decision classifier.

This helper does not measure geometry and does not claim feasibility. It only
turns a completed, human-reviewed evidence record into one allowed decision.
"""

import argparse
import json
import sys
from pathlib import Path

DECISIONS = (
    "event-driven",
    "bounded adaptive refresh",
    "documented degraded behavior",
    "NO-GO",
)

REQUIRED_EVIDENCE = (
    "matrixComplete",
    "numericStateMappingVerified",
    "eventDrivenCoversAll",
    "boundedAdaptiveCoversAll",
    "degradedBehaviorAccepted",
    "performanceWithinBudget",
    "continuousHyprctlPollingRequired",
)

REQUIRED_SCENARIOS = (
    "tiled resize",
    "floating drag/resize",
    "maximize/fullscreen",
    "workspace/special-workspace",
    "monitor scale/transform/rearrangement",
    "hotplug",
    "slow overlap-boundary movement",
    "rapid overlap-boundary movement",
)

REQUIRED_SCENARIO_LIST_FIELDS = (
    "eventOrProtocolSignals",
    "freshnessMs",
    "hyprctlFixtureLabels",
    "quickshellFixtureLabels",
)

REQUIRED_SCENARIO_TEXT_FIELDS = (
    "cpuAndLogNotes",
    "notes",
)

REQUIRED_CANDIDATES = (
    "event/protocol",
    "centralized refresh",
    "bounded adaptive refresh",
    "documented degraded behavior",
)


def _require_boolean(mapping, key):
    if key not in mapping or not isinstance(mapping[key], bool):
        raise ValueError(f"{key} must be an explicit boolean")
    return mapping[key]


def _require_candidate_boolean(mapping, key, prefix):
    if key not in mapping or not isinstance(mapping[key], bool):
        raise ValueError(f"{prefix}.{key} must be an explicit boolean")
    return mapping[key]


def _is_non_negative_number(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and value >= 0
    )


def _require_non_empty_text(mapping, key, prefix):
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{prefix}.{key} must be non-empty evidence text")
    return value


def _require_scenarios(payload):
    scenarios = payload.get("scenarios")
    if not isinstance(scenarios, dict):
        raise ValueError("scenarios must be a completed evidence mapping")
    for name in REQUIRED_SCENARIOS:
        record = scenarios.get(name)
        if not isinstance(record, dict):
            raise ValueError(f"scenario {name!r} must have a completed evidence record")
        for field in REQUIRED_SCENARIO_LIST_FIELDS:
            values = record.get(field)
            if not isinstance(values, list) or not values:
                raise ValueError(
                    f"scenario {name!r} field {field!r} must be a non-empty list"
                )
        for field in REQUIRED_SCENARIO_TEXT_FIELDS:
            values = record.get(field)
            if not isinstance(values, str) or not values.strip():
                raise ValueError(
                    f"scenario {name!r} field {field!r} must be non-empty evidence text"
                )
        freshness = record["freshnessMs"]
        if any(
            value is not None and not _is_non_negative_number(value)
            for value in freshness
        ):
            raise ValueError(
                f"scenario {name!r} field 'freshnessMs' must contain "
                "non-negative numbers or null"
            )
        if not _is_non_negative_number(record.get("maxMismatchMs")):
            raise ValueError(
                f"scenario {name!r} field 'maxMismatchMs' must be a "
                "non-negative number"
            )


def _require_numeric_mapping(payload):
    mapping = payload.get("numericStateMapping")
    if not isinstance(mapping, dict):
        raise ValueError("numericStateMapping must be a verified value mapping")
    if mapping.get("verifiedAgainstPinnedVersions") is not True:
        raise ValueError(
            "numericStateMapping.verifiedAgainstPinnedVersions must be true"
        )
    for field in ("fullscreenField", "fullscreenClientField"):
        record = mapping.get(field)
        if not isinstance(record, dict):
            raise ValueError(f"numericStateMapping.{field} must be recorded")
        if not record.get("observedValues"):
            raise ValueError(
                f"numericStateMapping.{field}.observedValues must be non-empty"
            )
        if not record.get("meaningByValue"):
            raise ValueError(
                f"numericStateMapping.{field}.meaningByValue must be non-empty"
            )
    maximized = mapping.get("maximizedEvidence")
    if not isinstance(maximized, dict) or not maximized.get("observedFields"):
        raise ValueError(
            "numericStateMapping.maximizedEvidence.observedFields must be non-empty"
        )
    if not maximized.get("notes") or not str(maximized.get("notes")).strip():
        raise ValueError("numericStateMapping.maximizedEvidence.notes must be non-empty")


def _require_candidate_mapping(payload):
    candidates = payload.get("candidateEvaluation")
    if not isinstance(candidates, dict):
        raise ValueError("candidateEvaluation must be a completed evidence mapping")
    for name in REQUIRED_CANDIDATES:
        if not isinstance(candidates.get(name), dict):
            raise ValueError(f"candidateEvaluation.{name} must be recorded")
    return candidates


def _require_bounded_adaptive_candidate(payload):
    candidates = _require_candidate_mapping(payload)
    candidate = candidates["bounded adaptive refresh"]
    prefix = "candidateEvaluation.bounded adaptive refresh"
    if candidate.get("coversAllRequiredScenarios") is not True:
        raise ValueError(f"{prefix}.coversAllRequiredScenarios must be true")

    sample_count = candidate.get("boundedSampleCount")
    if (
        not isinstance(sample_count, int)
        or isinstance(sample_count, bool)
        or not 1 <= sample_count <= 20
    ):
        raise ValueError(f"{prefix}.boundedSampleCount must be an integer from 1 to 20")

    interval_ms = candidate.get("boundedIntervalMs")
    if not _is_non_negative_number(interval_ms) or interval_ms < 200:
        raise ValueError(f"{prefix}.boundedIntervalMs must be at least 200")

    _require_non_empty_text(candidate, "startTrigger", prefix)
    if candidate.get("startTriggerVerified") is not True:
        raise ValueError(f"{prefix}.startTriggerVerified must be true")

    _require_non_empty_text(candidate, "stopCondition", prefix)
    if candidate.get("stopConditionVerified") is not True:
        raise ValueError(f"{prefix}.stopConditionVerified must be true")
    _require_non_empty_text(candidate, "notes", prefix)


def _require_degraded_candidate(candidate):
    prefix = "candidateEvaluation.documented degraded behavior"
    limitations = candidate.get("documentedLimitations")
    if (
        not isinstance(limitations, list)
        or not limitations
        or any(not isinstance(value, str) or not value.strip() for value in limitations)
    ):
        raise ValueError(
            f"{prefix}.documentedLimitations must be a non-empty list of text"
        )
    _require_non_empty_text(candidate, "notes", prefix)


def _require_candidate_evidence(payload, evidence):
    candidates = _require_candidate_mapping(payload)
    event_candidate = candidates["event/protocol"]
    centralized_candidate = candidates["centralized refresh"]
    bounded_candidate = candidates["bounded adaptive refresh"]
    degraded_candidate = candidates["documented degraded behavior"]

    event_protocol_covers = _require_candidate_boolean(
        event_candidate,
        "coversAllRequiredScenarios",
        "candidateEvaluation.event/protocol",
    )
    centralized_covers = _require_candidate_boolean(
        centralized_candidate,
        "coversAllRequiredScenarios",
        "candidateEvaluation.centralized refresh",
    )
    bounded_covers = _require_candidate_boolean(
        bounded_candidate,
        "coversAllRequiredScenarios",
        "candidateEvaluation.bounded adaptive refresh",
    )
    degraded_accepted = _require_candidate_boolean(
        degraded_candidate,
        "acceptable",
        "candidateEvaluation.documented degraded behavior",
    )

    expected = {
        "eventDrivenCoversAll": event_protocol_covers or centralized_covers,
        "boundedAdaptiveCoversAll": bounded_covers,
        "degradedBehaviorAccepted": degraded_accepted,
    }
    for key, candidate_value in expected.items():
        if evidence[key] != candidate_value:
            raise ValueError(
                f"evidence.{key} must match the completed candidate evaluation"
            )

    if event_protocol_covers:
        _require_non_empty_text(
            event_candidate,
            "notes",
            "candidateEvaluation.event/protocol",
        )
    if centralized_covers:
        prefix = "candidateEvaluation.centralized refresh"
        _require_non_empty_text(centralized_candidate, "refreshOwner", prefix)
        _require_non_empty_text(centralized_candidate, "notes", prefix)
    if bounded_covers:
        _require_bounded_adaptive_candidate(payload)
    if degraded_accepted:
        _require_degraded_candidate(degraded_candidate)


def _require_full_record(payload):
    if not isinstance(payload, dict) or "evidence" not in payload:
        raise ValueError("provide a full evidence record, not standalone booleans")
    if payload.get("probeComplete") is not True:
        raise ValueError("probeComplete must be true before recording a decision")
    _require_scenarios(payload)
    _require_numeric_mapping(payload)


def classify(payload):
    _require_full_record(payload)
    evidence = payload["evidence"]
    if not isinstance(evidence, dict):
        raise ValueError("evidence must be a completed evidence mapping")
    values = {key: _require_boolean(evidence, key) for key in REQUIRED_EVIDENCE}

    if not values["matrixComplete"]:
        raise ValueError("matrixComplete must be true before recording a decision")
    if not values["numericStateMappingVerified"]:
        raise ValueError(
            "numericStateMappingVerified must be true before recording a decision"
        )
    _require_candidate_evidence(payload, values)

    # Continuous hyprctl polling is outside the accepted production design.
    if values["continuousHyprctlPollingRequired"]:
        return (
            "documented degraded behavior"
            if values["degradedBehaviorAccepted"]
            else "NO-GO"
        )

    if values["eventDrivenCoversAll"] and values["performanceWithinBudget"]:
        return "event-driven"

    if values["boundedAdaptiveCoversAll"] and values["performanceWithinBudget"]:
        return "bounded adaptive refresh"

    if values["degradedBehaviorAccepted"]:
        return "documented degraded behavior"

    return "NO-GO"


def _read_payload(args):
    if args.stdin:
        return json.load(sys.stdin), None
    if not args.path:
        raise ValueError("provide a result JSON path or --stdin")
    path = Path(args.path)
    return json.loads(path.read_text(encoding="utf-8")), path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?")
    parser.add_argument("--stdin", action="store_true")
    parser.add_argument(
        "--write",
        action="store_true",
        help="write the single classified decision back to result JSON",
    )
    args = parser.parse_args()

    try:
        payload, path = _read_payload(args)
        decision = classify(payload)
        if decision not in DECISIONS:
            raise ValueError(f"classifier produced unsupported decision: {decision}")

        if args.write:
            if path is None:
                raise ValueError("--write requires a result JSON path")
            payload["decision"] = decision
            path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

        print(decision)
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"fdm816 decision: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
