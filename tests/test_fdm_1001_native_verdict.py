import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "tests/runtime/fdm_1001_native_verdict.py"
SPEC = importlib.util.spec_from_file_location("fdm_1001_native_verdict", MODULE)
verdict = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verdict)


def ready(*connectors):
    return "sidebar-native: " + json.dumps({
        "event": "ready", "panelCount": len(connectors), "connectors": list(connectors)
    })


def state(connector="DP-1", widget_count=1):
    return {
        "connector": connector,
        "allocation": {"availableMiddleHeight": 100, "hierarchyHeight": 40,
                       "widgetHeight": 50, "blankHeight": 10, "conservationError": 0,
                       "conserved": True},
        "hierarchy": {"naturalDemand": 60, "presentedCount": 2, "contentY": 5,
                      "contentHeight": 60, "viewportHeight": 40, "maximumScroll": 20,
                      "pendingRestore": False, "restoring": False},
        "widgets": {"naturalHeaderDemand": 20, "naturalContentDemand": 80,
                    "presentedCount": widget_count, "ids": ["herdr.agents"][:widget_count],
                    "contentY": 10, "contentHeight": 80, "viewportHeight": 50,
                    "maximumScroll": 30, "pendingRestore": False, "restoring": False,
                    "inputBusy": False, "layoutRevision": 1},
        "diagnostics": {"interactionBusy": False, "widgetReorderActive": False},
    }


class Fdm1001NativeVerdictTests(unittest.TestCase):
    def write_log(self, lines):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "native.log"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def test_passes_and_preserves_last_state_per_connector(self):
        earlier = state()
        earlier["widgets"]["contentY"] = 2
        log = self.write_log([
            "unrelated output",
            ready("DP-1"),
            "sidebar-native: " + json.dumps({"event": "viewport-state", "state": earlier}),
            "sidebar-native: " + json.dumps({"event": "viewport-state", "state": state()}),
        ])
        result = verdict.verdict(log, "SB-06", ["DP-1"], 1)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["finalStates"]["DP-1"]["widgets"]["contentY"], 10)
        self.assertNotIn("ids", json.dumps(result))

    def test_fails_closed_for_empty_malformed_and_missing_state_records(self):
        for lines, reason in [([], "NO_OBSERVER_RECORDS"),
                              (["sidebar-native: {bad"], "MALFORMED_JSON:line=1"),
                              (["sidebar-native: {\"event\":\"viewport-state\"}"], "MISSING_STATE:line=1")]:
            with self.subTest(reason=reason):
                result = verdict.verdict(self.write_log(lines), "SB-06", ["DP-1"], None)
                self.assertEqual(result["status"], "FAIL")
                self.assertIn(reason, result["reasons"])

    def test_rejects_unsettled_and_invalid_final_metrics(self):
        final = state()
        final["allocation"]["blankHeight"] = -1
        final["hierarchy"]["contentY"] = 21
        final["widgets"]["pendingRestore"] = True
        log = self.write_log([ready("DP-1"),
                              "sidebar-native: " + json.dumps({"event": "viewport-state", "state": final})])
        result = verdict.verdict(log, "SB-06", ["DP-1"], 1)
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("INVALID_METRIC:connector=DP-1:field=allocation.blankHeight", result["reasons"])
        self.assertIn("SCROLL_OUT_OF_BOUNDS:connector=DP-1:section=hierarchy", result["reasons"])
        self.assertIn("UNSETTLED_STATE:connector=DP-1:field=widgets.pendingRestore", result["reasons"])

    def test_invalid_field_types_fail_without_crashing(self):
        final = state()
        final["allocation"]["hierarchyHeight"] = "forty"
        final["hierarchy"]["contentHeight"] = "sixty"
        final["widgets"]["presentedCount"] = "one"
        log = self.write_log([ready("DP-1"),
                              "sidebar-native: " + json.dumps({"event": "viewport-state", "state": final})])
        result = verdict.verdict(log, "SB-06", ["DP-1"], None)
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("INVALID_METRIC:connector=DP-1:field=allocation.hierarchyHeight", result["reasons"])
        self.assertIn("INVALID_METRIC:connector=DP-1:field=hierarchy.contentHeight", result["reasons"])
        self.assertIn("INVALID_FIELD:connector=DP-1:field=widgets.presentedCount", result["reasons"])

    def test_cli_writes_fail_verdict_for_truncated_log(self):
        log = self.write_log([ready("DP-1")])
        output = log.with_name("verdict.json")
        status = verdict.main(["--log", str(log), "--case-id", "SB-06",
                               "--expected-connector", "DP-1", "--verdict", str(output)])
        self.assertEqual(status, 1)
        result = json.loads(output.read_text())
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["reasons"], ["MISSING_FINAL_STATE:connector=DP-1"])

    def test_ready_record_must_describe_the_expected_connector_set(self):
        invalid = self.write_log(['sidebar-native: {"event":"ready"}'])
        result = verdict.verdict(invalid, "SB-06", ["DP-1"], None)
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("INVALID_READY:line=1", result["reasons"])

        mismatch = self.write_log([
            ready("DP-2"),
            "sidebar-native: " + json.dumps({"event": "viewport-state", "state": state()}),
        ])
        result = verdict.verdict(mismatch, "SB-06", ["DP-1"], 1)
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("READY_CONNECTOR_MISMATCH:connector=DP-1", result["reasons"])


if __name__ == "__main__":
    unittest.main()
