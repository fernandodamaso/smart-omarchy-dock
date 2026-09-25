import assert from "node:assert/strict";
import fs from "node:fs";

const dockItem = fs.readFileSync("components/DockItem.qml", "utf8");
const launchMotion = fs.readFileSync("components/DockLaunchMotion.qml", "utf8");

assert.match(dockItem, /property bool launchPending: false/);
assert.match(
  dockItem,
  /if \(root\.pinnedItem && root\.runningCount === 0\)\s+root\.beginLaunchFeedback\(\)/
);
assert.match(
  dockItem,
  /if \(root\.launchPending && root\.runningCount > 0\)\s+root\.clearLaunchFeedback\(\)/
);
assert.match(dockItem, /id: launchFeedbackTimeout\s+interval: 8000/);
assert.match(dockItem, /active: root\.launchPending/);
assert.match(dockItem, /animationsEnabled: root\.interfaceAnimationsEnabled/);
assert.match(
  dockItem,
  /x: attentionMotion\.xOffset \+ launchMotion\.xOffset\s+y: attentionMotion\.yOffset \+ launchMotion\.yOffset/
);

assert.match(launchMotion, /loops: Animation\.Infinite/);
assert.match(launchMotion, /case "top":/);
assert.match(launchMotion, /case "left":/);
assert.match(launchMotion, /case "right":/);
assert.match(launchMotion, /case "bottom":/);

console.log("launch feedback wiring tests passed");
