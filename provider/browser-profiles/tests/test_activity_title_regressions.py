"""Regression coverage for PR #55's unread-title review findings."""

import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location(
    "activity_title_provider", Path(__file__).parents[1] / "browser_profile_provider.py")
provider = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provider)


class ActivityTitleRegressionTest(unittest.TestCase):
    def target(self, title, fragment="inbox", target_id="A" * 32):
        return {"targetId": target_id,
                "url": "https://mail.google.com/mail/u/0/#" + fragment,
                "title": title, "browserContextId": "context-1"}

    def test_preserves_supported_inbox_unread_signal(self):
        row = provider.activity_for_target(
            self.target("Inbox (13) - person@example.test - Gmail"), "Default", "0x1")
        self.assertIsNotNone(row)
        self.assertEqual(row["count"], 13)
        self.assertEqual(row["serviceId"], "gmail")
        self.assertNotIn("title", row)
        self.assertNotIn("url", row)

    def test_rejects_subject_draft_and_other_ambiguous_numbers(self):
        for title in (
            "Project update (42) - person@example.test - Gmail",
            "Drafts (5) - person@example.test - Gmail",
            "Sent Mail (99) - person@example.test - Gmail",
            "Search results (7) - person@example.test - Gmail",
            "Inbox - person(12)@example.test - Gmail",
            "Re: Inbox (42) - person@example.test - Gmail",
            "Inbox (13) (42) - person@example.test - Gmail",
        ):
            with self.subTest(title=title):
                self.assertIsNone(provider.activity_for_target(
                    self.target(title), "Default", "0x1"))

    def test_rejects_inbox_shaped_subject_outside_inbox_listing(self):
        for fragment in ("inbox/message-id", "drafts", "sent", "search/test", ""):
            with self.subTest(fragment=fragment):
                self.assertIsNone(provider.activity_for_target(
                    self.target("Inbox (42) - person@example.test - Gmail", fragment),
                    "Default", "0x1"))

    def test_subject_cannot_replace_real_inbox_count_in_snapshot(self):
        inbox = self.target("Inbox (13) - person@example.test - Gmail")
        subject = self.target("Project update (42) - person@example.test - Gmail",
                              "inbox/message-id", "B" * 32)
        matches = {
            "contexts": {"0x1": "context-1"},
            "windowIds": {"0x1": 7},
            "targetWindows": {inbox["targetId"]: 7, subject["targetId"]: 7},
        }
        snapshot = provider.build_snapshot(
            matches, {"context-1": "/nonexistent/Chrome/Default"},
            [inbox, subject], 9222, ["google-chrome"])
        rows = snapshot["activities"]["0x1"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["targetId"], inbox["targetId"])
        self.assertEqual(rows[0]["count"], 13)


if __name__ == "__main__":
    unittest.main()
