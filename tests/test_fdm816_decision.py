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
        input=json.dumps(record), text=True, capture_output=True, check=False,
    )


def candidate():
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

    def test_reviewed_result_redacts_client_identity(self):
        for field in ("address", "class", "title"):
            self.assertTrue(BASE["target"][field].startswith("[redacted"))

    def test_flat_booleans_are_rejected(self):
        self.assertRejected(BASE["evidence"], "full evidence record")

    def test_event_driven_result(self):
        record = candidate()
        record["evidence"].update(eventDrivenCoversAll=True, boundedAdaptiveCoversAll=False)
        self.assertDecision(record, "event-driven")

    def test_bounded_result_requires_verified_start_and_stop(self):
        record = candidate()
        self.assertDecision(record, "bounded adaptive refresh")
        for field in ("startTriggerVerified", "stopConditionVerified"):
            broken = copy.deepcopy(record)
            broken["candidateEvaluation"]["bounded adaptive refresh"][field] = False
            self.assertRejected(broken, field)

    def test_bounded_result_enforces_caps(self):
        record = candidate()
        record["candidateEvaluation"]["bounded adaptive refresh"]["boundedSampleCount"] = 21
        self.assertRejected(record, "boundedSampleCount")

    def test_continuous_polling_is_no_go(self):
        record = candidate()
        record["evidence"]["continuousHyprctlPollingRequired"] = True
        self.assertDecision(record, "NO-GO")


if __name__ == "__main__":
    unittest.main()
