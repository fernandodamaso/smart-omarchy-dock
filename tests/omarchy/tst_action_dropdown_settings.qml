import QtQuick
import QtTest
import "../../components" as Components

TestCase {
  id: testCase

  name: "DockActionDropdownSettings"
  when: windowShown
  width: 420
  height: 180

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

  function openDropdown() {
    mouseClick(dropdown, dropdown.width / 2,
      dropdown.height - dropdown.rowHeight / 2)
    wait(20)
  }

  function selectWithKey(key) {
    keyClick(key)
    keyClick(Qt.Key_Return)
    wait(20)
  }

  function test_settingsRemainAuthoritativeAfterNativeSelections() {
    resetHarness()
    compare(dropdown.value, "one")

    // User picks a non-default value.
    openDropdown()
    selectWithKey(Qt.Key_Down)
    compare(settingsValue, "two")
    compare(commitCount, 1)
    compare(committedValues[0], "two")

    // External config update must re-drive the native child without a commit.
    settingsValue = "three"
    wait(0)
    compare(dropdown.value, "three")
    compare(commitCount, 1)

    // The native popup must have synchronized to "three": Up therefore picks
    // "two". A broken child binding would still be on "two" and pick "one".
    openDropdown()
    selectWithKey(Qt.Key_Up)
    compare(settingsValue, "two")
    compare(commitCount, 2)
    compare(committedValues[1], "two")

    // Reset the same settings instance, then select again.
    settingsValue = "one"
    wait(0)
    compare(dropdown.value, "one")
    compare(commitCount, 2)

    openDropdown()
    selectWithKey(Qt.Key_Down)
    compare(settingsValue, "two")
    compare(commitCount, 3)
    compare(committedValues[2], "two")

    // A second external update after multiple selections must still win and
    // must not produce a synchronization commit.
    settingsValue = "three"
    wait(0)
    compare(dropdown.value, "three")
    compare(commitCount, 3)

    openDropdown()
    selectWithKey(Qt.Key_Up)
    compare(settingsValue, "two")
    compare(commitCount, 4)
    compare(committedValues[3], "two")
  }
}
