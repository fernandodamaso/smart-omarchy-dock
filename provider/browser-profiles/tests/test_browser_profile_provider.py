import importlib.util
from pathlib import Path
import unittest


PROVIDER_PATH = Path(__file__).parents[1] / "browser_profile_provider.py"
SPEC = importlib.util.spec_from_file_location("browser_profile_provider", PROVIDER_PATH)
provider = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provider)


class BrowserProfileProviderTest(unittest.TestCase):
    def test_matches_same_context_equal_size_windows_without_collapsing_ids(self):
        pages = [
            {"targetId": "A" * 32, "title": "Chat",
             "browserContextId": "context-1"},
            {"targetId": "B" * 32, "title": "Themes",
             "browserContextId": "context-1"},
        ]
        class FakeClient:
            def call(self, method, params):
                if method == "Browser.getWindowForTarget":
                    return {"windowId": 1 if params["targetId"] == "A" * 32 else 2}
                if method == "Browser.getWindowBounds":
                    return {"bounds": {"width": 800, "height": 600}}
                raise AssertionError(method)

        matches = provider.match_window_contexts(FakeClient(), [
            {"address": "0x1", "title": "Chat - Google Chrome", "size": [800, 600]},
            {"address": "0x2", "title": "Themes - Google Chrome", "size": [800, 600]},
        ], pages)
        self.assertEqual(matches["windowIds"], {"0x1": 1, "0x2": 2})
        self.assertEqual(matches["targetWindows"],
                         {"A" * 32: 1, "B" * 32: 2})

    def test_recognizes_whatsapp_and_gmail_titles(self):
        whatsapp = provider.activity_for_target(
            {"targetId": "A" * 32, "url": "https://web.whatsapp.com/",
             "title": "(10) WhatsApp"}, "Default", "0x1")
        gmail = provider.activity_for_target(
            {"targetId": "B" * 32,
             "url": "https://mail.google.com/mail/u/0/#inbox",
             "title": "Inbox (13) - person@example.test - Gmail"},
            "Profile 1", "0x2")
        self.assertEqual(whatsapp["count"], 10)
        self.assertEqual(gmail["count"], 13)

    def test_rejects_unknown_ambiguous_and_invalid_targets(self):
        self.assertIsNone(provider.activity_for_target(
            {"targetId": "C" * 32, "url": "https://example.test/",
             "title": "(99) Example"}, "Default", "0x1"))
        self.assertIsNone(provider.activity_for_target(
            {"targetId": "D" * 32, "url": "https://web.whatsapp.com/",
             "title": "WhatsApp"}, "Default", "0x1"))
        for target_id in ("", "not-hex", "A" * 65):
            self.assertIsNone(provider.activity_for_target(
                {"targetId": target_id, "url": "https://web.whatsapp.com/",
                 "title": "(10) WhatsApp"}, "Default", "0x1"))

    def test_rejects_invalid_counts_and_non_https_origins(self):
        for count in (0, -1, provider.MAX_UNREAD_COUNT + 1):
            self.assertIsNone(provider.activity_for_target(
                {"targetId": "A" * 32, "url": "https://web.whatsapp.com/",
                 "title": f"({count}) WhatsApp"}, "Default", "0x1"))
        self.assertIsNone(provider.activity_for_target(
            {"targetId": "A" * 32, "url": "http://web.whatsapp.com/",
             "title": "(10) WhatsApp"}, "Default", "0x1"))

    def test_reduces_duplicate_service_profile_to_highest_count(self):
        rows = [
            {"targetId": "A" * 32, "serviceId": "whatsapp", "label": "WhatsApp",
             "profileKey": "Default", "domain": "web.whatsapp.com", "count": 10,
             "windowAddress": "0x1"},
            {"targetId": "B" * 32, "serviceId": "whatsapp", "label": "WhatsApp",
             "profileKey": "Default", "domain": "web.whatsapp.com", "count": 7,
             "windowAddress": "0x2"},
        ]
        self.assertEqual(provider.reduce_activities(rows), [rows[0]])

    def test_reduction_keeps_mixed_profiles(self):
        rows = [
            {"targetId": "A" * 32, "serviceId": "gmail", "label": "Gmail",
             "profileKey": "Default", "domain": "mail.google.com", "count": 2,
             "windowAddress": "0x1"},
            {"targetId": "B" * 32, "serviceId": "gmail", "label": "Gmail",
             "profileKey": "Profile 1", "domain": "mail.google.com", "count": 3,
             "windowAddress": "0x2"},
        ]
        self.assertEqual(len(provider.reduce_activities(rows)), 2)

    def test_snapshot_adds_classes_activities_and_window_assignment(self):
        target_id = "A" * 32
        matches = {
            "contexts": {"0x1": "context-1"},
            "windowIds": {"0x1": 7},
            "targetWindows": {target_id: 7},
        }
        snapshot = provider.build_snapshot(
            matches, {"context-1": "/tmp/Chrome/Default"},
            [{"targetId": target_id, "url": "https://web.whatsapp.com/",
              "title": "(10) WhatsApp", "browserContextId": "context-1"}],
            9222, ["google-chrome"])
        self.assertEqual(snapshot["classes"], ["google-chrome"])
        self.assertEqual(snapshot["activities"]["0x1"][0]["windowAddress"], "0x1")
        self.assertNotIn("url", snapshot["activities"]["0x1"][0])
        self.assertNotIn("title", snapshot["activities"]["0x1"][0])

    def test_snapshot_fingerprint_changes_with_count(self):
        first = {"schemaVersion": 1, "revision": 1, "available": True,
                 "classes": ["google-chrome"], "port": 9222, "windows": {},
                 "profiles": {}, "activities": {"0x1": [{"count": 1}]}}
        second = dict(first, revision=2,
                      activities={"0x1": [{"count": 2}]})
        self.assertNotEqual(provider.snapshot_fingerprint(first),
                            provider.snapshot_fingerprint(second))

    def test_snapshot_reduces_duplicate_service_profile_globally(self):
        first = "A" * 32
        second = "B" * 32
        matches = {
            "contexts": {"0x1": "context-1", "0x2": "context-1"},
            "windowIds": {"0x1": 1, "0x2": 2},
            "targetWindows": {first: 1, second: 2},
        }
        pages = [
            {"targetId": first, "url": "https://web.whatsapp.com/",
             "title": "(7) WhatsApp", "browserContextId": "context-1"},
            {"targetId": second, "url": "https://web.whatsapp.com/",
             "title": "(10) WhatsApp", "browserContextId": "context-1"},
        ]
        snapshot = provider.build_snapshot(
            matches, {"context-1": "/tmp/Chrome/Default"}, pages, 9222,
            ["google-chrome"])
        self.assertEqual(list(snapshot["activities"]), ["0x2"])
        self.assertEqual(snapshot["activities"]["0x2"][0]["count"], 10)

    def test_activate_target_is_bounded_and_closes_client(self):
        class FakeClient:
            instances = []

            def __init__(self, port):
                self.port = port
                self.calls = []
                self.closed = False
                self.instances.append(self)

            def call(self, method, params):
                self.calls.append((method, params))

            def close(self):
                self.closed = True

        self.assertTrue(provider.activate_target(9222, "AABBCCDD", FakeClient))
        instance = FakeClient.instances[0]
        self.assertEqual(instance.calls,
                         [("Target.activateTarget", {"targetId": "AABBCCDD"})])
        self.assertTrue(instance.closed)
        self.assertFalse(provider.activate_target(0, "AABBCCDD", FakeClient))
        self.assertFalse(provider.activate_target(9222, "$(bad)", FakeClient))

    def test_rejects_oversized_digit_strings_without_raising(self):
        self.assertIsNone(provider.activity_for_target(
            {"targetId": "A" * 32, "url": "https://web.whatsapp.com/",
             "title": "(" + ("9" * 5000) + ") WhatsApp"}, "Default", "0x1"))

    def test_empty_profile_keys_do_not_collapse_distinct_windows(self):
        rows = [
            {"targetId": "A" * 32, "serviceId": "whatsapp", "label": "WhatsApp",
             "profileKey": "", "domain": "web.whatsapp.com", "count": 5,
             "windowAddress": "0x1"},
            {"targetId": "B" * 32, "serviceId": "whatsapp", "label": "WhatsApp",
             "profileKey": "", "domain": "web.whatsapp.com", "count": 8,
             "windowAddress": "0x2"},
        ]
        reduced = provider.reduce_activities(rows)
        self.assertEqual(len(reduced), 2)

    def test_activate_target_returns_false_on_cdp_error(self):
        class FakeClient:
            def __init__(self, port):
                self.port = port

            def call(self, method, params):
                raise provider.CdpError("No target with given id found")

            def close(self):
                pass

        self.assertFalse(provider.activate_target(9222, "AABBCCDD", FakeClient))


if __name__ == "__main__":
    unittest.main()
