#!/usr/bin/env python3
"""Fail-closed verdict for one FDM-1001 sidebar-native observer case."""

import argparse
import json
import math
import re
import sys
from pathlib import Path


PREFIX = "sidebar-native: "
TOLERANCE = 0.01
WIDGET_ID = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")


def finite_nonnegative(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0


def add_reason(reasons, code):
    if code not in reasons:
        reasons.append(code)


def read_records(log_path):
    records = []
    reasons = []
    try:
        lines = log_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        return records, ["LOG_UNREADABLE:" + type(error).__name__]

    for line_number, line in enumerate(lines, start=1):
        prefix_index = line.find(PREFIX)
        if prefix_index < 0:
            continue
        payload = line[prefix_index + len(PREFIX):]
        try:
            record = json.loads(payload)
        except json.JSONDecodeError:
            add_reason(reasons, f"MALFORMED_JSON:line={line_number}")
            continue
        if not isinstance(record, dict):
            add_reason(reasons, f"INVALID_RECORD:line={line_number}")
            continue
        event = record.get("event")
        if not isinstance(event, str) or not event:
            add_reason(reasons, f"MISSING_EVENT:line={line_number}")
            continue
        if event == "ready":
            panel_count = record.get("panelCount")
            connectors = record.get("connectors")
            if (not isinstance(panel_count, int) or isinstance(panel_count, bool)
                    or panel_count < 0 or not isinstance(connectors, list)
                    or len(connectors) != panel_count
                    or any(not isinstance(connector, str) or not connector
                           for connector in connectors)):
                add_reason(reasons, f"INVALID_READY:line={line_number}")
                continue
        if event == "viewport-state" and not isinstance(record.get("state"), dict):
            add_reason(reasons, f"MISSING_STATE:line={line_number}")
            continue
        records.append((line_number, record))
    if not records and not reasons:
        add_reason(reasons, "NO_OBSERVER_RECORDS")
    return records, reasons


def state_summary(state):
    allocation = state["allocation"]
    hierarchy = state["hierarchy"]
    widgets = state["widgets"]
    diagnostics = state["diagnostics"]
    return {
        "connector": state["connector"],
        "allocation": {key: allocation[key] for key in (
            "availableMiddleHeight", "hierarchyHeight", "widgetHeight", "blankHeight")},
        "hierarchy": {key: hierarchy[key] for key in (
            "presentedCount", "contentY", "contentHeight", "viewportHeight", "maximumScroll")},
        "widgets": {key: widgets[key] for key in (
            "presentedCount", "contentY", "contentHeight", "viewportHeight", "maximumScroll",
            "layoutRevision")},
        "settled": {
            "hierarchyPendingRestore": hierarchy["pendingRestore"],
            "hierarchyRestoring": hierarchy["restoring"],
            "widgetPendingRestore": widgets["pendingRestore"],
            "widgetRestoring": widgets["restoring"],
            "widgetInputBusy": widgets["inputBusy"],
            "interactionBusy": diagnostics["interactionBusy"],
            "widgetReorderActive": diagnostics["widgetReorderActive"],
        },
    }


def validate_state(state, connector, expected_widget_count):
    reasons = []
    if not isinstance(state.get("connector"), str) or not state["connector"]:
        add_reason(reasons, f"INVALID_CONNECTOR:connector={connector}")

    required = {
        "allocation": ("availableMiddleHeight", "hierarchyHeight", "widgetHeight", "blankHeight", "conservationError", "conserved"),
        "hierarchy": ("naturalDemand", "presentedCount", "contentY", "contentHeight", "viewportHeight", "maximumScroll", "pendingRestore", "restoring"),
        "widgets": ("naturalHeaderDemand", "naturalContentDemand", "presentedCount", "ids", "contentY", "contentHeight", "viewportHeight", "maximumScroll", "pendingRestore", "restoring", "inputBusy", "layoutRevision"),
        "diagnostics": ("interactionBusy", "widgetReorderActive"),
    }
    for section, keys in required.items():
        if not isinstance(state.get(section), dict):
            add_reason(reasons, f"MISSING_SECTION:connector={connector}:section={section}")
            continue
        for key in keys:
            if key not in state[section]:
                add_reason(reasons, f"MISSING_FIELD:connector={connector}:field={section}.{key}")
    if reasons:
        return reasons

    allocation = state["allocation"]
    hierarchy = state["hierarchy"]
    widgets = state["widgets"]
    for section, keys in {
        "allocation": ("availableMiddleHeight", "hierarchyHeight", "widgetHeight", "blankHeight"),
        "hierarchy": ("naturalDemand", "presentedCount", "contentY", "contentHeight", "viewportHeight", "maximumScroll"),
        "widgets": ("naturalHeaderDemand", "naturalContentDemand", "presentedCount", "contentY", "contentHeight", "viewportHeight", "maximumScroll", "layoutRevision"),
    }.items():
        for key in keys:
            if not finite_nonnegative(state[section][key]):
                add_reason(reasons, f"INVALID_METRIC:connector={connector}:field={section}.{key}")

    if not isinstance(allocation["conservationError"], (int, float)) or isinstance(allocation["conservationError"], bool) or not math.isfinite(allocation["conservationError"]):
        add_reason(reasons, f"INVALID_METRIC:connector={connector}:field=allocation.conservationError")

    if not isinstance(allocation["conserved"], bool):
        add_reason(reasons, f"INVALID_FIELD:connector={connector}:field=allocation.conserved")
    elif not allocation["conserved"]:
        add_reason(reasons, f"ALLOCATION_NOT_CONSERVED:connector={connector}")
    if isinstance(allocation["conservationError"], (int, float)) and not isinstance(allocation["conservationError"], bool) and math.isfinite(allocation["conservationError"]) and abs(allocation["conservationError"]) > TOLERANCE:
        add_reason(reasons, f"ALLOCATION_ERROR:connector={connector}")
    if all(finite_nonnegative(allocation[key]) for key in ("availableMiddleHeight", "hierarchyHeight", "widgetHeight", "blankHeight")):
        total = allocation["hierarchyHeight"] + allocation["widgetHeight"] + allocation["blankHeight"]
        if abs(allocation["availableMiddleHeight"] - total) > TOLERANCE:
            add_reason(reasons, f"ALLOCATION_SUM_MISMATCH:connector={connector}")

    for section in ("hierarchy", "widgets"):
        metrics = state[section]
        if all(finite_nonnegative(metrics[key]) for key in ("contentY", "maximumScroll")) and metrics["contentY"] > metrics["maximumScroll"] + TOLERANCE:
            add_reason(reasons, f"SCROLL_OUT_OF_BOUNDS:connector={connector}:section={section}")
        if all(finite_nonnegative(metrics[key]) for key in ("contentHeight", "viewportHeight", "maximumScroll")):
            expected_maximum = max(0, metrics["contentHeight"] - metrics["viewportHeight"])
            if abs(metrics["maximumScroll"] - expected_maximum) > TOLERANCE:
                add_reason(reasons, f"SCROLL_RANGE_MISMATCH:connector={connector}:section={section}")

    ids = widgets["ids"]
    if not isinstance(ids, list) or len(ids) > 32 or any(not isinstance(widget_id, str) or not WIDGET_ID.fullmatch(widget_id) for widget_id in ids):
        add_reason(reasons, f"INVALID_WIDGET_IDS:connector={connector}")
    elif not isinstance(widgets["presentedCount"], int) or isinstance(widgets["presentedCount"], bool):
        add_reason(reasons, f"INVALID_FIELD:connector={connector}:field=widgets.presentedCount")
    elif widgets["presentedCount"] > 32 or widgets["presentedCount"] != len(ids):
        add_reason(reasons, f"WIDGET_COUNT_MISMATCH:connector={connector}")
    if expected_widget_count is not None and isinstance(widgets["presentedCount"], int) and not isinstance(widgets["presentedCount"], bool) and widgets["presentedCount"] != expected_widget_count:
        add_reason(reasons, f"EXPECTED_WIDGET_COUNT_MISMATCH:connector={connector}")

    for section, key in (("hierarchy", "pendingRestore"), ("hierarchy", "restoring"),
                         ("widgets", "pendingRestore"), ("widgets", "restoring"),
                         ("widgets", "inputBusy"), ("diagnostics", "interactionBusy"),
                         ("diagnostics", "widgetReorderActive")):
        if state[section][key] is not False:
            add_reason(reasons, f"UNSETTLED_STATE:connector={connector}:field={section}.{key}")
    return reasons


def verdict(log_path, case_id, connectors, expected_widget_count):
    records, reasons = read_records(log_path)
    ready = [record for _, record in records if record["event"] == "ready"]
    if not ready:
        add_reason(reasons, "MISSING_READY_EVENT")
    else:
        ready_connectors = ready[-1]["connectors"]
        for connector in connectors:
            if connector not in ready_connectors:
                add_reason(reasons, f"READY_CONNECTOR_MISMATCH:connector={connector}")
    final_states = {}
    for line_number, record in records:
        if record["event"] != "viewport-state":
            continue
        state = record["state"]
        connector = state.get("connector") if isinstance(state, dict) else None
        if connector in connectors:
            final_states[connector] = (line_number, state)
    summaries = {}
    for connector in connectors:
        if connector not in final_states:
            add_reason(reasons, f"MISSING_FINAL_STATE:connector={connector}")
            continue
        _, state = final_states[connector]
        state_reasons = validate_state(state, connector, expected_widget_count)
        for reason in state_reasons:
            add_reason(reasons, reason)
        if all(isinstance(state.get(section), dict) for section in ("allocation", "hierarchy", "widgets", "diagnostics")):
            try:
                summaries[connector] = state_summary(state)
            except KeyError:
                summaries[connector] = {"connector": state.get("connector")}
    return {
        "caseId": case_id,
        "status": "PASS" if not reasons else "FAIL",
        "reasons": reasons,
        "expectedConnectors": connectors,
        "expectedWidgetCount": expected_widget_count,
        "observerRecordCount": len(records),
        "eventOrder": [{"line": line_number, "event": record["event"]}
                       for line_number, record in records],
        "readyEventCount": len(ready),
        "finalStates": summaries,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path, help="native runtime log containing observer JSONL")
    parser.add_argument("--case-id", required=True)
    parser.add_argument("--expected-connector", action="append", required=True, dest="connectors")
    parser.add_argument("--expected-widget-count", type=int)
    parser.add_argument("--verdict", required=True, type=Path, help="output evidence-ledger verdict JSON")
    args = parser.parse_args(argv)
    if args.expected_widget_count is not None and args.expected_widget_count < 0:
        parser.error("--expected-widget-count must be nonnegative")
    if len(set(args.connectors)) != len(args.connectors) or any(not connector for connector in args.connectors):
        parser.error("--expected-connector values must be unique nonempty strings")
    result = verdict(args.log, args.case_id, args.connectors, args.expected_widget_count)
    args.verdict.parent.mkdir(parents=True, exist_ok=True)
    args.verdict.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"caseId": args.case_id, "status": result["status"], "reasons": result["reasons"]}, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
