-- Minimal guest Hyprland config for named KVM SmartDock sessions.
-- Two virtio-gpu scanouts sit left-to-right so workspace-card drag is real.
hl.monitor({ output = "", mode = "preferred", position = "auto-right", scale = 1 })
hl.config({
  general = { layout = "dwindle", gaps_in = 0, gaps_out = 0 },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
})

hl.on("hyprland.start", function()
  local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""
  local display = os.getenv("WAYLAND_DISPLAY") or ""
  local ready = os.getenv("SMARTDOCK_GUEST_READY")
  assert(ready and ready ~= "", "SMARTDOCK_GUEST_READY is required")
  local f = assert(io.open(ready, "w"))
  f:write(string.format(
    '{"wayland_display":"%s","hyprland_instance_signature":"%s"}\n',
    display,
    sig
  ))
  f:close()
end)
