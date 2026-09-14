# Browser activity provider

SmartDock's optional browser-profile provider publishes profile ownership and
small, privacy-preserving activity rows for Chrome. It is an additive snapshot
alongside the existing `windows` and `profiles` maps:

```json
{
  "schemaVersion": 1,
  "available": true,
  "port": 9222,
  "classes": ["google-chrome"],
  "windows": {"0x123": "Profile 1"},
  "profiles": {"Profile 1": {"name": "Work", "path": "..."}},
  "activities": {
    "0x123": [{
      "targetId": "A1B2",
      "serviceId": "whatsapp",
      "label": "WhatsApp",
      "profileKey": "Profile 1",
      "domain": "web.whatsapp.com",
      "count": 3,
      "windowAddress": "0x123"
    }]
  }
}
```

The provider accepts only HTTPS targets on `web.whatsapp.com` or
`mail.google.com`. WhatsApp requires a title of `(N) WhatsApp`; Gmail requires
`(N) ... - Gmail`. Counts are positive integers capped at 999999. Duplicate
targets for one service/profile are reduced to the highest count, and target
IDs are validated before they can be displayed or activated.

The card exposes profile names, service labels, counts, and ordinary window
preview captures. It never publishes URLs, titles, message text, account
identifiers, or page content. A click is accepted only when the target ID and
window address still exist in the current snapshot; SmartDock then activates
the Hyprland window and sends `Target.activateTarget` through the provider.

The provider executable is optional. If it is absent, unreachable, or emits an
invalid optional `activities` field, profile/window previews remain usable and
activity rows are cleared. A validated Chrome activity total is only a fallback
for the Chrome launcher badge. An authoritative LauncherEntry count always
wins, including an explicit zero or hidden state; other applications keep the
existing launcher-count and attention-dot precedence.

## Validation

Provider parsing and activation are covered by
`provider/browser-profiles/tests/test_browser_profile_provider.py`. QML model,
preview, and badge behavior are covered by the existing `qmltestrunner` suites.
The checks do not claim live Chrome CDP, image decoding, focus, or auto-hide
qualification; those require an isolated graphical session with the provider
installed and Chrome launched with remote debugging enabled.
