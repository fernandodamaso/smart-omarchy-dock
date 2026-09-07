from pathlib import Path


def replace_once(path, old, new):
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one anchor, found {count}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "components/DockBadgeModel.js",
    '''function badgeSeverity(sniNeedsAttention, hyprUrgent, localAttention) {
  return reduceSeverity([
    sniNeedsAttention ? BADGE_ATTENTION : BADGE_NONE,
    hyprUrgent ? BADGE_URGENT : BADGE_NONE,
    localAttention || BADGE_NONE
  ])
}

function launcherCountState''',
    '''function badgeSeverity(sniNeedsAttention, hyprUrgent, localAttention) {
  return reduceSeverity([
    sniNeedsAttention ? BADGE_ATTENTION : BADGE_NONE,
    hyprUrgent ? BADGE_URGENT : BADGE_NONE,
    localAttention || BADGE_NONE
  ])
}

function motionAttentionEligible(sniNeedsAttention, hyprUrgent, localAttention) {
  return sniNeedsAttention === true || hyprUrgent === true
    || localAttention === BADGE_URGENT
}

function launcherCountState''')

replace_once(
    "components/DockBadgeTracker.qml",
    '''  function badgeFor(desktopId) {
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var local = BadgeModel.localSeverity(
      persisted.localNotifications, desktopId, entry, identityAliases,
      Date.now(), BadgeModel.LOCAL_ATTENTION_TTL_MS)
    var severity = BadgeModel.badgeSeverity(
      sniNeedsAttentionFor(desktopId, entry),
      hyprUrgentFor(desktopId, entry), local)
    return BadgeModel.applicationBadgeToken(
      true, launcherBadgeMode, launcherCountFor(desktopId), severity)
  }''',
    '''  function motionAttentionFor(desktopId) {
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var local = BadgeModel.localSeverity(
      persisted.localNotifications, desktopId, entry, identityAliases,
      Date.now(), BadgeModel.LOCAL_ATTENTION_TTL_MS)
    return BadgeModel.motionAttentionEligible(
      sniNeedsAttentionFor(desktopId, entry),
      hyprUrgentFor(desktopId, entry), local)
  }

  function badgeFor(desktopId) {
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var local = BadgeModel.localSeverity(
      persisted.localNotifications, desktopId, entry, identityAliases,
      Date.now(), BadgeModel.LOCAL_ATTENTION_TTL_MS)
    var severity = BadgeModel.badgeSeverity(
      sniNeedsAttentionFor(desktopId, entry),
      hyprUrgentFor(desktopId, entry), local)
    return BadgeModel.applicationBadgeToken(
      true, launcherBadgeMode, launcherCountFor(desktopId), severity)
  }''')

replace_once(
    "components/DockItem.qml",
    '''  readonly property string attentionSeverity:
    BadgeModel.attentionSeverityFromBadgeToken(attentionBadge)
  readonly property bool attentionActive:
    attentionSeverity !== BadgeModel.BADGE_NONE''',
    '''  readonly property bool attentionActive: badgeTracker
    ? badgeTracker.motionAttentionFor(desktopId) : false''')

replace_once(
    "tests/check_urgent_window_motion.sh",
    '''grep -Fq 'attentionSeverityFromBadgeToken' "$item" \\
  || fail 'DockItem must derive attention from its badge token'
grep -Fq 'readonly property bool attentionActive' "$item" \\
  || fail 'DockItem attention-active property missing'\n''',
    '''grep -Fq 'motionAttentionFor(desktopId)' "$item" \\
  || fail 'DockItem must use source-specific motion eligibility'
grep -Fq 'readonly property bool attentionActive' "$item" \\
  || fail 'DockItem attention-active property missing'\n''')
