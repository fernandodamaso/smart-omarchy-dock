import { loadModel } from './host_harness.mjs'
export const desktopModel = loadModel('DockDesktopModel')
export function sidebarFixture() {
  const monitors = [
    { id: 2, name: 'HDMI-A-1', lastIpcObject: { id: 2, name: 'HDMI-A-1', x: 0, y: 0, focused: true, activeWorkspace: { id: 7 }, model: 'Right' } },
    { id: 9, name: 'DP-1', lastIpcObject: { id: 9, name: 'DP-1', x: -1920, y: 0, focused: false, activeWorkspace: { id: 3 }, model: 'Left' } },
    { id: 5, name: 'USB-C-1', lastIpcObject: { id: 5, name: 'USB-C-1', x: 1920, y: -100, model: 'Portrait', scale: 1.5 } }
  ]
  const screens = [
    { name: 'HDMI-A-1', x: 0, y: 0, width: 1920, height: 1080 },
    { name: 'DP-1', x: -1920, y: 0, width: 1920, height: 1080 },
    { name: 'USB-C-1', x: 1920, y: -100, width: 720, height: 1280 }
  ]
  const workspaces = [{ id: 3, name: '3', monitorID: 9 }, { id: 4, name: '4', monitorID: 9 },
    { id: 7, name: 'Code', monitorID: 2 }, { name: 'project alpha', monitorID: 2 },
    { id: 11, monitorID: 99 }, { id: 12, monitorID: 9 }, { id: 12, monitorID: 2 }]
  const definitions = [
    ['a', 'chrome', '0xa', { id: 3 }, 9], ['b', 'chrome', '0xb', { id: 3 }, 9],
    ['c', 'chrome', '0xc', { id: 7 }, 2], ['terminal', 'terminal', '0xd', { name: 'project alpha' }, 2],
    ['pending-one', 'firefox', '', { id: 7 }, 2], ['pending-two', 'firefox', '', { id: 7 }, 2],
    ['sticky', 'sticky-app', '0xe', { id: 3 }, 2, true],
    ['minimized', 'chrome', '0xf', { name: 'special:smartdock-minimized' }, 2],
    ['hidden', 'hidden-app', '0x10', { id: 3 }, 9],
    ['scratch', 'terminal', '0x11', { name: 'special:scratch' }, 2],
    ['unknown-one', '', '', null, null], ['unknown-two', '', '', null, null]
  ]
  const toplevels = definitions.map(([id, appId]) => ({ id, appId, title: `Title ${id}`, activated: id === 'c' }))
  const handles = definitions.map(([, , address, workspace, monitor, pinned], i) => ({
    wayland: toplevels[i], address, lastIpcObject: { address, workspace, monitor, pinned: pinned === true, urgent: i === 1 }
  }))
  const settings = { pinned: ['closed-app', 'chrome', 'hidden-app'], hiddenApplications: ['hidden-app'],
    workspaceGroups: [{ desktopId: 'chrome', workspace: 'id:3' }], workspaceMonitorScope: 'current-monitor',
    workspaceMonitorOrder: [], sortByWorkspace: true, groupWindows: true }
  const input = { mode: 'sidebar', settings, applications: ['chrome', 'firefox', 'terminal', 'closed-app'].map(id => ({ id, name: id, icon: id })),
    toplevels, hyprToplevels: handles, hyprWorkspaces: workspaces, hyprMonitors: monitors,
    minimizedOrigins: { '0xf': { workspace: '3', monitor: '9' } }, focusedWorkspace: 'id:7',
    dockMonitor: monitors[0], filteredToplevels: [] }
  return { input, screens, monitors, workspaces, toplevels, handles, settings }
}
