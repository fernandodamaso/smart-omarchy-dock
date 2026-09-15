#!/usr/bin/env python3
from pathlib import Path


def replace_one(path, old, new, label):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    p.write_text(text.replace(old, new, 1))

replace_one(
    'components/DockMenuModel.js',
'''function initialPage(controlItem, targetCount, preferredTargetValid) {
  if (controlItem) return "controls"
  if (preferredTargetValid || Number(targetCount) === 1) return "window"
  return "app"
}''',
'''function initialPage(controlItem, targetCount, preferredTargetValid, groupedRepresentation) {
  if (controlItem) return "controls"
  if (groupedRepresentation === true) return "app"
  if (preferredTargetValid || Number(targetCount) === 1) return "window"
  return "app"
}''',
    'saved-group initial page model')

replace_one(
    'components/DockContextMenu.qml',
'''    root.page = DockMenuModel.initialPage(
      root.controlItem, root.targetContexts.length, root.pageTarget !== null)''',
'''    root.page = DockMenuModel.initialPage(
      root.controlItem, root.targetContexts.length, root.pageTarget !== null,
      root.representedWorkspaceGrouped())''',
    'saved-group menu routing')

print('FDM-941 one-member saved-group menu fixed')
