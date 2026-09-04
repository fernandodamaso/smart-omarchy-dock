#!/usr/bin/env python3
import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "research/fdm816/decision.py"
RESULT = ROOT / "research/fdm816/results/reviewed-result.json"
BASE = json.loads(RESULT.read_text(encoding="utf-8"))


def run(record):
    return subprocess.run(
        [sys.executable, str(HELPER), "--stdin"],
        input=json.dumps(record),
        text=True,
        capture_output=True,
        check=False,
    )


def bounded_candidate():
    record = copy.deepcopy(BASE)
    record["evidence"].update(
        eventDrivenCoversAll=False,
        boundedAdaptiveCoversAll=True,
        degradedBehaviorAccepted=False,
        performanceWithinBudget=True,
        continuousHyprctlPollingRequired=False,
    )
    record["candidateEvaluation"]["bounded adaptive refresh"].update(
        coversAllRequiredScenarios=True,
        startTrigger="verified non-polling signal",
        startTriggerVerified=True,
        stopCondition="geometry stable for 500 ms",
        stopConditionVerified=True,
        notes="A verified bounded burst covers the complete matrix.",
    )
    return record


def event_driven_candidate():
    record = copy.deepcopy(BASE)
    record["evidence"].update(
        eventDrivenCoversAll=True,
        boundedAdaptiveCoversAll=False,
        degradedBehaviorAccepted=False,
        performanceWithinBudget=True,
        continuousHyprctlPollingRequired=False,
    )
    record["candidateEvaluation"]["event/protocol"].update(
        coversAllRequiredScenarios=True,
        notes="A verified supported signal covers the complete matrix.",
    )
    return record


def degraded_candidate():
    record = copy.deepcopy(BASE)
    record["evidence"].update(
        eventDrivenCoversAll=False,
        boundedAdaptiveCoversAll=False,
        degradedBehaviorAccepted=True,
        performanceWithinBudget=False,
        continuousHyprctlPollingRequired=True,
    )
    record["candidateEvaluation"]["documented degraded behavior"].update(
        acceptable=True,
        documentedLimitations=[
            "Geometry-only movement may remain stale until a documented event."
        ],
        notes="The user-visible limitation was reviewed and accepted.",
    )
    return record


class DecisionTests(unittest.TestCase):
    def assertDecision(self, record, expected):
        completed = run(record)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout.strip(), expected)

    def assertRejected(self, record, expected):
        completed = run(record)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn(expected, completed.stderr)

    def test_reviewed_result_is_no_go(self):
        self.assertDecision(BASE, "NO-GO")

    def test_stored_decision_matches_classifier(self):
        completed = run(BASE)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(BASE["decision"], completed.stdout.strip())

    def test_reviewed_result_redacts_client_identity(self):
        for field in ("address", "class", "title"):
            self.assertTrue(BASE["target"][field].startswith("[redacted"))

    def test_flat_booleans_are_rejected(self):
        self.assertRejected(BASE["evidence"], "full evidence record")

    def test_event_driven_result(self):
        self.assertDecision(event_driven_candidate(), "event-driven")

    def test_summary_booleans_must_match_candidate_evidence(self):
        cases = [
            (
                event_driven_candidate(),
                "event/protocol",
                "coversAllRequiredScenarios",
                False,
                "eventDrivenCoversAll",
            ),
            (
                bounded_candidate(),
                "bounded adaptive refresh",
                "coversAllRequiredScenarios",
                False,
                "boundedAdaptiveCoversAll",
            ),
            (
                degraded_candidate(),
                "documented degraded behavior",
                "acceptable",
                False,
                "degradedBehaviorAccepted",
            ),
        ]
        for record, candidate_name, field, value, expected in cases:
            with self.subTest(expected=expected):
                record["candidateEvaluation"][candidate_name][field] = value
                self.assertRejected(record, expected)

    def test_bounded_result_requires_verified_start_and_stop(self):
        record = bounded_candidate()
        self.assertDecision(record, "bounded adaptive refresh")
        for field in ("startTriggerVerified", "stopConditionVerified"):
            broken = copy.deepcopy(record)
            broken["candidateEvaluation"]["bounded adaptive refresh"][field] = False
            self.assertRejected(broken, field)

    def test_bounded_result_enforces_caps(self):
        record = bounded_candidate()
        record["candidateEvaluation"]["bounded adaptive refresh"][
            "boundedSampleCount"
        ] = 21
        self.assertRejected(record, "boundedSampleCount")

    def test_degraded_result_requires_documented_limitations(self):
        record = degraded_candidate()
        self.assertDecision(record, "documented degraded behavior")
        for field, value in (("documentedLimitations", []), ("notes", "")):
            broken = copy.deepcopy(record)
            broken["candidateEvaluation"]["documented degraded behavior"][
                field
            ] = value
            self.assertRejected(broken, field)

    def test_continuous_polling_is_no_go_without_accepted_degradation(self):
        record = event_driven_candidate()
        record["evidence"].update(
            eventDrivenCoversAll=False,
            continuousHyprctlPollingRequired=True,
        )
        record["candidateEvaluation"]["event/protocol"][
            "coversAllRequiredScenarios"
        ] = False
        self.assertDecision(record, "NO-GO")


if __name__ == "__main__":
    unittest.main()
