import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase

  name: "DockActionDropdownSettings"
  when: windowShown
  width: 420
  height: 220

  property string settingsValue: "one"
  property int commitCount: 0
  property var committedValues: []

  Components.DockActionDropdown {
    id: dropdown

    x: 20
    y: 20
    width: 320
    height: implicitHeight
    label: "Action"
    value: testCase.settingsValue
    options: [
      { value: "one", label: "One" },
      { value: "two", label: "Two" },
      { value: "three", label: "Three" }
    ]

    onChanged: function(selectedValue) {
      testCase.commitCount += 1
      var nextValues = testCase.committedValues.slice()
      nextValues.push(selectedValue)
      testCase.committedValues = nextValues
      testCase.settingsValue = selectedValue
    }
  }

  function resetHarness() {
    settingsValue = "one"
    commitCount = 0
    committedValues = []
    wait(0)
  }

  function nativeDropdown() {
    for (var i = 0; i < dropdown.children.length; ++i) {
      var child = dropdown.children[i]
      if (child && typeof child.open === "function"
          && child.popupOpen !== undefined)
        return child
    }
    return null
  }

  function selectNativeValue(nextValue) {
    var native = nativeDropdown()
    verify(native !== null)

    // Open through the real Omarchy Dropdown so its onOpened path syncs
    // currentIndex from the settings-driven value.
    native.open()
    tryCompare(native, "popupOpen", true, 1000)
    wait(0)
    compare(native.value, settingsValue)

    // Mirror Omarchy Dropdown.selectCurrent(): assign value then emit
    // changed(). That is the exact path that clears the child's declarative
    // binding and requires DockActionDropdown's Qt.binding restore.
    native.value = nextValue
    native.changed(nextValue)
    native.close()
    tryCompare(native, "popupOpen", false, 1000)
    wait(0)
  }

  function test_settingsRemainAuthoritativeAfterNativeSelections() {
    resetHarness()
    compare(dropdown.value, "one")

    selectNativeValue("two")
    compare(settingsValue, "two")
    compare(commitCount, 1)
    compare(committedValues[0], "two")
    compare(dropdown.value, "two")

    // External config update must re-drive the native child without a commit.
    settingsValue = "three"
    wait(0)
    compare(dropdown.value, "three")
    compare(nativeDropdown().value, "three")
    compare(commitCount, 1)

    // Selecting again after an external update must still commit once and
    // leave settings authoritative for later reloads.
    selectNativeValue("two")
    compare(settingsValue, "two")
    compare(commitCount, 2)
    compare(committedValues[1], "two")
    compare(nativeDropdown().value, "two")

    settingsValue = "one"
    wait(0)
    compare(dropdown.value, "one")
    compare(commitCount, 2)

    selectNativeValue("two")
    compare(settingsValue, "two")
    compare(commitCount, 3)
    compare(committedValues[2], "two")

    settingsValue = "three"
    wait(0)
    compare(dropdown.value, "three")
    compare(commitCount, 3)

    selectNativeValue("two")
    compare(settingsValue, "two")
    compare(commitCount, 4)
    compare(committedValues[3], "two")
    compare(nativeDropdown().value, "two")
  }
}
