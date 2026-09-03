import QtQuick
import QtTest
import "../components/DockBadgeModel.js" as BadgeModel

TestCase {
  name: "DockBadgeModel"

  function test_matchesOnlyStrictDesktopIdentityFieldsAndExplicitAliases() {
    var entry = {
      id: "org.mozilla.firefox.desktop",
      startupClass: "firefox",
      name: "Firefox Browser"
    }

    compare(BadgeModel.normalizeIdentity("  ORG.MOZILLA.FIREFOX.desktop  "),
      "org.mozilla.firefox")
    verify(BadgeModel.strictIdentityMatches(
      "org.mozilla.firefox", entry, ["firefox"], {}))
    verify(BadgeModel.strictIdentityMatches(
      "org.mozilla.firefox", entry, ["Firefox Browser"], {}))
    verify(!BadgeModel.strictIdentityMatches(
      "org.mozilla.firefox", entry, ["mozilla"], {}))
    verify(!BadgeModel.strictIdentityMatches(
      "org.mozilla.firefox", entry, ["Mozilla Firefox"], {}))
    verify(BadgeModel.strictIdentityMatches(
      "org.mozilla.firefox", entry, ["Mozilla Firefox"],
      { "org.mozilla.firefox": ["Mozilla Firefox"] }))
  }

  function test_reducesAttentionSourcesWithoutInventingCounts() {
    compare(BadgeModel.reduceSeverity(["none", "attention"]), "attention")
    compare(BadgeModel.reduceSeverity(["attention", "urgent"]), "urgent")
    compare(BadgeModel.notificationSeverity(2, 2), "urgent")
    compare(BadgeModel.notificationSeverity(1, 2), "attention")
    compare(BadgeModel.badgeSeverity(true, false, "none"), "attention")
    compare(BadgeModel.badgeSeverity(true, true, "attention"), "urgent")
  }

  function test_replacesNotificationsByOriginalIdAndExpiresAfterTtl() {
    var slack = { id: "com.slack.Slack", startupClass: "Slack", name: "Slack" }
    var discord = {
      id: "com.discordapp.Discord",
      startupClass: "discord",
      name: "Discord"
    }
    var records = BadgeModel.upsertNotification({}, {
      originalId: 9,
      app: "Slack",
      urgency: 1,
      timestamp: 1000
    }, 2, 1000)
    compare(BadgeModel.localSeverity(records, slack.id, slack, {}), "attention")

    records = BadgeModel.upsertNotification(records, {
      originalId: 9,
      app: "Discord",
      appIcon: "discord",
      urgency: 2,
      timestamp: 1000
    }, 2, 1200)
    compare(Object.keys(records).length, 1)
    compare(BadgeModel.localSeverity(records, slack.id, slack, {}), "none")
    compare(BadgeModel.localSeverity(records, discord.id, discord, {}), "urgent")

    compare(Object.keys(BadgeModel.pruneExpired(
      records, 1000 + BadgeModel.LOCAL_ATTENTION_TTL_MS - 1)).length, 1)
    compare(Object.keys(BadgeModel.pruneExpired(
      records, 1000 + BadgeModel.LOCAL_ATTENTION_TTL_MS)).length, 0)
  }

  function test_focusDwellClearsOnlyLocalAttention() {
    var entry = {
      id: "com.discordapp.Discord",
      startupClass: "discord",
      name: "Discord"
    }
    var records = BadgeModel.upsertNotification({}, {
      originalId: 11,
      app: "Discord",
      urgency: 1,
      timestamp: 5000
    }, 2, 5000)

    verify(!BadgeModel.shouldClearFocused(
      5000, 5000 + BadgeModel.FOCUS_DWELL_MS - 1))
    verify(BadgeModel.shouldClearFocused(
      5000, 5000 + BadgeModel.FOCUS_DWELL_MS))

    records = BadgeModel.clearMatchingNotifications(
      records, entry.id, entry, {})
    compare(BadgeModel.localSeverity(records, entry.id, entry, {}), "none")
    compare(BadgeModel.badgeSeverity(true, false, "none"), "attention")
  }

  function test_ungroupedApplicationsAssignOnePrimaryBadgeItem() {
    var items = [
      { desktopId: "com.discordapp.Discord" },
      { desktopId: "com.discordapp.Discord.desktop" },
      { desktopId: "org.mozilla.firefox" }
    ]
    verify(BadgeModel.isPrimaryVisibleItem(items, 0))
    verify(!BadgeModel.isPrimaryVisibleItem(items, 1))
    verify(BadgeModel.isPrimaryVisibleItem(items, 2))
  }
}
