import fs from 'node:fs'
import vm from 'node:vm'
import { loadModel } from './host_harness.mjs'
export function qmlMethods(file, state) {
  const context = vm.createContext({ console, ...state })
  context.root = context
  const source = fs.readFileSync(new URL('../components/' + file, import.meta.url), 'utf8')
  vm.runInContext((source.match(/^  function [\s\S]*?^  }/gm) || []).join('\n'), context, { filename: file })
  return context
}
export function interactionFixture() {
  const windows = [{ appId:'editor',title:'A' }, { appId:'editor',title:'B' }]
  const monitors = [{ id:0,name:'DP-1',activeWorkspace:{id:1} },
    { id:1,name:'HDMI-A-1',activeWorkspace:{name:'Design work'} }]
  const workspaces = [{ id:1,monitorID:0 },{ name:'Design work',monitorID:1 },{ id:3,monitorID:0 }]
  const handles = windows.map((wayland,i) => ({ wayland,address:'0x'+(i+1),
    lastIpcObject:{workspace:{name:'Design work'},monitor:1} }))
  const requests = [], batches = []
  const Hyprland = { usingLua:false,monitors:{values:monitors},workspaces:{values:workspaces},
    toplevels:{values:handles},focusedWorkspace:{id:1},dispatch:r=>requests.push(r) }
  const ToplevelManager = { toplevels:{values:windows},activeToplevel:windows[1] }
  const DockModel = loadModel('DockModel'), WindowModel = loadModel('DockWindowModel')
  const SidebarModel = loadModel('DockSidebarModel')
  const actions = qmlMethods('DockWindowActions.qml', { DockModel,DockWindowModel:WindowModel,
    Hyprland,ToplevelManager,Quickshell:{execDetached:r=>batches.push(r)},
    minimizedWorkspace:'special:smartdock-minimized',minimizedOrigins:{},
    windowWorkspacePins:{},workspaceMonitorPins:{},activeToplevel:windows[1] })
  const controller = qmlMethods('DockSidebarController.qml', { DockModel,WindowModel,SidebarModel,
    DesktopModel:loadModel('DockDesktopModel'),Qt:{callLater(){}},host:{windowActions:actions},
    windowActions:actions,toplevels:windows,hyprToplevels:handles,workspaces,monitors,
    selectedConnector:'DP-1',mode:'sidebar',interactionBusy:false,resizeActive:false,
    initialized:true,collapsed:false,settings:{},folds:{},focusedRowKey:'',
    registry:SidebarModel.reconcileHandles({nextToken:1,entries:[]},windows),
    dragSession:null,dragTarget:null,focusReturnTarget:null,
    dragChanged(){},navigationRequested(){},contextRequested(){},refreshed(){},surfaceInvalidated(){} })
  controller.projection = {rows:windows.map((t,i)=>({kind:'window',key:controller.registry.entries[i].key,
    toplevel:t,address:handles[i].address,workspaceIdentity:'name:Design work',monitorIdentity:'1'}))
    .concat([{kind:'workspace',key:'ws',workspaceIdentity:'name:Design work',monitorIdentity:'1'},
      {kind:'monitor',key:'mon',monitorIdentity:'0',connector:'DP-1'},
      {kind:'workspace',key:'ws3',workspaceIdentity:'id:3',monitorIdentity:'0'}])}
  Object.defineProperty(controller,'rowsByKey',{get:()=>Object.fromEntries(controller.projection.rows.map(r=>[r.key,r]))})
  return {controller,actions,windows,handles,monitors,workspaces,requests,batches,Hyprland,ToplevelManager,
    clear(){requests.length=0;batches.length=0}}
}
