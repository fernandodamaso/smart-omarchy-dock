import QtQuick
import QtTest
import "../components/DockBrowserActivityModel.js" as ActivityModel

TestCase {
  name: "DockBrowserActivityModel"

  readonly property var whatsapp: ({
    targetId: "30512CE29E2EAEB3E32228BBC7F6DE78",
    serviceId: "whatsapp",
    label: "WhatsApp",
    profileKey: "Default",
    domain: "web.whatsapp.com",
    count: 10,
    windowAddress: "0x1"
  })

  function test_reducesDuplicatesAndOrdersRows() {
    var duplicate = Object.assign({}, whatsapp, {
      targetId: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      count: 7,
      windowAddress: "0x2"
    })
    var gmail = {
      targetId: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
      serviceId: "gmail",
      label: "Gmail",
      profileKey: "Profile 1",
      domain: "mail.google.com",
      count: 13,
      windowAddress: "0x2"
    }
    var result = ActivityModel.presentation([duplicate, whatsapp, gmail])
    compare(result.rows.length, 2)
    compare(result.rows[0].serviceId, "gmail")
    compare(result.rows[1].count, 10)
    compare(result.total, 23)
  }

  function test_rejectsInvalidAndZeroRows() {
    compare(ActivityModel.presentation([
      Object.assign({}, whatsapp, { count: 0 }),
      Object.assign({}, whatsapp, { count: -1 }),
      Object.assign({}, whatsapp, { targetId: "not-a-target" }),
      Object.assign({}, whatsapp, { serviceId: "" })
    ]).rows.length, 0)
  }

  function test_selectsOnlyRequestedWindowAddresses() {
    var records = {
      "0x1": [whatsapp],
      "0x2": [Object.assign({}, whatsapp, {
        targetId: "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
        serviceId: "gmail",
        label: "Gmail",
        profileKey: "Profile 1",
        domain: "mail.google.com",
        count: 13
      })]
    }
    var rows = ActivityModel.rowsForAddresses(records, ["0x2"])
    compare(rows.length, 1)
    compare(rows[0].windowAddress, "0x2")
  }

  function test_buildsAccessibleName() {
    compare(ActivityModel.accessibleName(whatsapp),
      "Open WhatsApp tab, 10 unread")
  }

  function test_normalizesProviderMetadata() {
    compare(JSON.stringify(ActivityModel.normalizeClasses(
      ["google-chrome", "", "google-chrome", 4])),
      JSON.stringify(["google-chrome"]))
    compare(ActivityModel.normalizePort(9222), 9222)
    compare(ActivityModel.normalizePort(70000), 0)
  }

  function test_buildsSafeActivationCommand() {
    compare(JSON.stringify(ActivityModel.activationCommand(
      "/tmp/provider", "AABBCCDD", 9222)),
      JSON.stringify(["/tmp/provider", "--activate-target", "AABBCCDD",
        "--port", "9222"]))
    compare(ActivityModel.activationCommand(
      "/tmp/provider", "$(touch /tmp/no)", 9222).length, 0)
  }

  function test_rejectsFractionalCounts() {
    compare(ActivityModel.presentation([
      Object.assign({}, whatsapp, { count: 0.5 })
    ]).rows.length, 0)
  }

  function test_keepsDistinctWindowsWhenProfileKeyEmpty() {
    var rows = ActivityModel.presentation([
      Object.assign({}, whatsapp, { profileKey: "", count: 5, windowAddress: "0x1",
        targetId: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }),
      Object.assign({}, whatsapp, { profileKey: "", count: 8, windowAddress: "0x2",
        targetId: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB" })
    ]).rows
    compare(rows.length, 2)
  }

  function test_excludesMutedServicesFromTotal() {
    var gmail = {
      targetId: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
      serviceId: "gmail",
      label: "Gmail",
      profileKey: "Profile 1",
      domain: "mail.google.com",
      count: 13,
      windowAddress: "0x2"
    }
    var result = ActivityModel.presentation([whatsapp, gmail], ["gmail"])
    compare(result.rows.length, 2)
    verify(result.rows[0].muted === true || result.rows[1].muted === true)
    compare(result.rows.filter(function(row) { return row.serviceId === "gmail" })[0].muted, true)
    compare(result.rows.filter(function(row) { return row.serviceId === "whatsapp" })[0].muted, false)
    compare(result.total, 10)
  }
}
