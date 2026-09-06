import QtQuick
import QtTest
import "../components/DockBadgeModel.js" as BadgeModel

TestCase {
  name: "AttentionMotionModel"

  function test_revisionsTrackNewUrgentAddressesOnly() {
    var state = BadgeModel.reduceWindowUrgencyState(null, [], true, true)
    compare(state.windowUrgentRevision, 0)
    compare(state.windowUrgent, false)

    state = BadgeModel.reduceWindowUrgencyState(state, ["0xaaa"], true, false)
    compare(state.windowUrgentRevision, 1)
    compare(state.windowUrgent, true)

    state = BadgeModel.reduceWindowUrgencyState(state, ["0xaaa"], true, false)
    compare(state.windowUrgentRevision, 1)

    state = BadgeModel.reduceWindowUrgencyState(
      state, ["0xaaa", "0xbbb"], true, false)
    compare(state.windowUrgentRevision, 2)

    state = BadgeModel.reduceWindowUrgencyState(state, ["0xbbb"], true, false)
    compare(state.windowUrgentRevision, 2)
    compare(state.windowUrgent, true)

    state = BadgeModel.reduceWindowUrgencyState(state, [], true, false)
    compare(state.windowUrgentRevision, 2)
    compare(state.windowUrgent, false)

    state = BadgeModel.reduceWindowUrgencyState(state, ["0xbbb"], true, false)
    compare(state.windowUrgentRevision, 3)
  }

  function test_hiddenDockQueuesOneStillUrgentRevision() {
    var first = BadgeModel.reduceUrgentMotion(null, {
      revision: 4,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: false,
      interactionActive: false,
      now: 10000
    })
    compare(first.play, false)
    compare(first.state.seenRevision, 4)

    var hidden = BadgeModel.reduceUrgentMotion(first.state, {
      revision: 5,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: false,
      interactionActive: false,
      now: 10010
    })
    compare(hidden.play, false)
    compare(hidden.state.pendingRevision, 5)

    var reveal = BadgeModel.reduceUrgentMotion(hidden.state, {
      revision: 5,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: false,
      now: 10020
    })
    compare(reveal.play, true)
    compare(reveal.state.pendingRevision, 0)
  }

  function test_cooldownAndInteractionSuppression() {
    var state = BadgeModel.primeUrgentMotionState(null, 10)
    var play = BadgeModel.reduceUrgentMotion(state, {
      revision: 11,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: false,
      now: 20000
    })
    compare(play.play, true)

    var cooldown = BadgeModel.reduceUrgentMotion(play.state, {
      revision: 12,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: false,
      now: 20000 + BadgeModel.URGENT_WINDOW_COOLDOWN_MS - 1
    })
    compare(cooldown.play, false)

    var suppressed = BadgeModel.reduceUrgentMotion(cooldown.state, {
      revision: 13,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: true,
      now: 24000
    })
    compare(suppressed.play, false)
    compare(suppressed.state.pendingRevision, 13)
    compare(suppressed.state.pendingReminder, true)

    var afterSuppression = BadgeModel.reduceUrgentMotion(suppressed.state, {
      revision: 13,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: false,
      now: 27000
    })
    compare(afterSuppression.play, true)
  }

  function test_attentionRemindersCountOnlySuppressionAndClear() {
    var state = BadgeModel.primeUrgentMotionState(null, 0)
    var attention = BadgeModel.reduceUrgentMotion(state, {
      revision: 0,
      windowUrgent: false,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: true,
      dockShown: true,
      interactionActive: false,
      now: 40000
    })
    compare(attention.play, true)

    var countOnly = BadgeModel.reduceUrgentMotion(attention.state, {
      revision: 0,
      windowUrgent: false,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: false,
      reminder: true,
      dockShown: true,
      interactionActive: false,
      now: 43000
    })
    compare(countOnly.play, false)
    compare(countOnly.state.pendingReminder, false)

    var hidden = BadgeModel.reduceUrgentMotion(
      BadgeModel.primeUrgentMotionState(null, 0), {
        revision: 0,
        windowUrgent: false,
        primaryOwner: true,
        badgesEnabled: true,
        animationEnabled: true,
        attentionActive: true,
        reminder: true,
        dockShown: false,
        interactionActive: false,
        now: 50000
      })
    compare(hidden.play, false)
    compare(hidden.state.pendingReminder, true)

    var revealed = BadgeModel.reduceUrgentMotion(hidden.state, {
      revision: 0,
      windowUrgent: false,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: false,
      now: 50001
    })
    compare(revealed.play, true)

    var cleared = BadgeModel.reduceUrgentMotion(revealed.state, {
      revision: 0,
      windowUrgent: false,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: false,
      reminder: true,
      dockShown: true,
      interactionActive: false,
      now: 54000
    })
    compare(cleared.play, false)
    compare(cleared.state.pendingReminder, false)
  }

  function test_primaryOwnershipAndVectors() {
    var state = BadgeModel.primeUrgentMotionState(null, 20)
    var secondary = BadgeModel.reduceUrgentMotion(state, {
      revision: 21,
      windowUrgent: true,
      primaryOwner: false,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: false,
      now: 30000
    })
    compare(secondary.play, false)
    compare(secondary.state.seenRevision, 20)

    var primary = BadgeModel.reduceUrgentMotion(secondary.state, {
      revision: 21,
      windowUrgent: true,
      primaryOwner: true,
      badgesEnabled: true,
      animationEnabled: true,
      attentionActive: true,
      reminder: false,
      dockShown: true,
      interactionActive: false,
      now: 30000
    })
    compare(primary.play, true)

    compare(JSON.stringify(BadgeModel.urgentMotionVector("bottom", 5)),
      JSON.stringify({ x: 0, y: -5 }))
    compare(JSON.stringify(BadgeModel.urgentMotionVector("top", 5)),
      JSON.stringify({ x: 0, y: 5 }))
    compare(JSON.stringify(BadgeModel.urgentMotionVector("left", 5)),
      JSON.stringify({ x: 5, y: 0 }))
    compare(JSON.stringify(BadgeModel.urgentMotionVector("right", 5)),
      JSON.stringify({ x: -5, y: 0 }))
  }
}
