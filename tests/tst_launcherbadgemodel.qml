import QtQuick
import QtTest
import "../components/DockBadgeModel.js" as BadgeModel

TestCase {
  name: "DockLauncherBadgeModel"

  function test_normalizesLauncherUrisWithoutFuzzyMatching() {
    compare(BadgeModel.normalizeLauncherIdentity(
      " application://Com.DiscordApp.Discord.desktop "),
      "com.discordapp.discord")
    compare(BadgeModel.normalizeLauncherIdentity(
      "application://My%20App.desktop"), "my app")
    compare(BadgeModel.normalizeLauncherIdentity(
      "https://example.test/app.desktop"), "")
    compare(BadgeModel.normalizeLauncherIdentity(
      "application://../bad.desktop"), "")
    compare(BadgeModel.normalizeLauncherIdentity(
      "application://foo\\bar.desktop"), "")
  }

  function test_authoritativeCountsOverrideDotsOnlyWhenVisibleAndPositive() {
    var records = {
      "com.discordapp.discord": { count: 8, visible: true },
      "com.hidden.app": { count: 5, visible: false },
      "com.zero.app": { count: 0, visible: true }
    }

    var count = BadgeModel.launcherCountState(
      records, "com.discordapp.Discord", true)
    var presentation = BadgeModel.applicationBadgePresentation(
      true, "automatic", count, "attention")
    compare(presentation.kind, "count")
    compare(presentation.text, "8")
    compare(presentation.severity, "attention")

    presentation = BadgeModel.applicationBadgePresentation(
      true, "automatic",
      BadgeModel.launcherCountState(records, "com.hidden.app", true),
      "urgent")
    compare(presentation.kind, "dot")
    compare(presentation.severity, "urgent")

    presentation = BadgeModel.applicationBadgePresentation(
      true, "automatic",
      BadgeModel.launcherCountState(records, "com.zero.app", true),
      "attention")
    compare(presentation.kind, "dot")
  }

  function test_dotsOnlyAndUnavailableProviderKeepFdm809Fallback() {
    var records = {
      "org.telegram.desktop": { count: 120, visible: true }
    }
    var count = BadgeModel.launcherCountState(
      records, "org.telegram.desktop", true)

    var presentation = BadgeModel.applicationBadgePresentation(
      true, "automatic", count, "urgent")
    compare(presentation.kind, "count")
    compare(presentation.text, "99+")

    presentation = BadgeModel.applicationBadgePresentation(
      true, "dots-only", count, "urgent")
    compare(presentation.kind, "dot")
    compare(presentation.severity, "urgent")

    presentation = BadgeModel.applicationBadgePresentation(
      true, "automatic",
      BadgeModel.launcherCountState(records, "org.telegram.desktop", false),
      "attention")
    compare(presentation.kind, "dot")
    compare(presentation.severity, "attention")
  }
}
