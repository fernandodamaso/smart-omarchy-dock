import QtQuick
import QtTest
import "../components/DockBadgeModel.js" as BadgeModel
import "../components/DockBrowserActivityModel.js" as ActivityModel

TestCase {
  name: "DockLauncherBadgeModel"

  readonly property var chromeEntry: ({
    id: "com.google.Chrome",
    startupClass: "google-chrome",
    name: "Google Chrome"
  })

  function chromeItemBadgeToken(rows, primaryOwner) {
    var total = ActivityModel.presentation(rows || [], []).total
    var browser = BadgeModel.browserCountState(
      chromeEntry.id, chromeEntry, ["google-chrome"], total, true, {})
    var launcher = { authoritative: false, count: 0, visible: false }
    return BadgeModel.applicationBadgeToken(
      true, "automatic",
      BadgeModel.preferredCountState(launcher, browser, primaryOwner),
      BadgeModel.BADGE_NONE)
  }

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

  function test_browserCountIsStrictChromeFallback() {
    var chrome = {
      id: "com.google.Chrome", startupClass: "google-chrome",
      name: "Google Chrome"
    }
    var browser = BadgeModel.browserCountState(
      chrome.id, chrome, ["google-chrome"], 23, true, {})
    compare(browser.count, 23)
    verify(browser.visible)
    verify(!BadgeModel.browserCountState(
      "org.mozilla.firefox", { id: "org.mozilla.firefox", startupClass: "firefox" },
      ["google-chrome"], 23, true, {}).visible)
  }

  function test_launcherCountWinsOverBrowserFallback() {
    var launcher = { authoritative: true, count: 4, visible: true }
    var browser = { authoritative: true, count: 23, visible: true }
    compare(BadgeModel.preferredCountState(launcher, browser).count, 4)
    compare(BadgeModel.preferredCountState(
      { authoritative: false, count: 0, visible: false }, browser).count, 23)
  }

  function test_launcherPrecedenceAlsoSuppressesSecondaryBrowserCounts() {
    var launcher = { authoritative: true, count: 9, visible: true }
    var browser = { authoritative: true, count: 2, visible: true }

    compare(BadgeModel.preferredCountState(launcher, browser, true).count, 9)
    var secondary = BadgeModel.preferredCountState(launcher, browser, false)
    verify(secondary.authoritative)
    verify(!secondary.visible)
    compare(secondary.count, 0)

    var unavailableLauncher = {
      authoritative: false, count: 0, visible: false
    }
    compare(BadgeModel.preferredCountState(
      unavailableLauncher, browser, false).count, 2)
  }

  function test_windowScopedBrowserFallbackTokensPerChromeItem() {
    var emptyRows = []
    var whatsappRows = [{
      targetId: "30512CE29E2EAEB3E32228BBC7F6DE78",
      serviceId: "whatsapp",
      label: "WhatsApp",
      profileKey: "Default",
      domain: "web.whatsapp.com",
      count: 2,
      windowAddress: "0x2"
    }]

    // Flat Chrome: first item owns no activity; second owns WhatsApp 2.
    compare(chromeItemBadgeToken(emptyRows, true), "none")
    compare(chromeItemBadgeToken(whatsappRows, false), "count:2:none")
  }
}
