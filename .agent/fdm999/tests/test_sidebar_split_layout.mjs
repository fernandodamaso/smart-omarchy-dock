import assert from 'node:assert/strict'
import {loadModel} from './host_harness.mjs'
const model=loadModel('DockSidebarWidgetModel')
assert.equal(typeof model.sidebarSplitLayout,'function','FDM-999 allocator is missing')
const base={availableHeight:800,hierarchyContentHeight:1000,widgetHeaderHeight:32,
  widgetContentHeight:1000,presentedWidgetCount:4,rail:false,minHierarchyHeight:120,
  minWidgetHeight:66,requestedSplitPx:null}
const cases=[
  [{},[440,360,0]],
  [{hierarchyContentHeight:100},[100,700,0]],
  [{widgetContentHeight:34},[734,66,0]],
  [{hierarchyContentHeight:100,widgetContentHeight:34},[100,66,634]],
  [{presentedWidgetCount:0},[800,0,0]],
  [{rail:true},[800,0,0]],
  [{availableHeight:186},[120,66,0]],
  [{availableHeight:185},[120,65,0]],
  [{availableHeight:100},[68,32,0]],
  [{availableHeight:32},[0,32,0]],
  [{availableHeight:31},[31,0,0]],
  [{availableHeight:0},[0,0,0]],
  [{requestedSplitPx:560},[560,240,0]],
  [{requestedSplitPx:-100},[120,680,0]],
  [{requestedSplitPx:900},[734,66,0]],
  [{requestedSplitPx:null},[440,360,0]],
]
const near=(a,b)=>assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`)
for(const [patch,expected] of cases){
  const r=model.sidebarSplitLayout({...base,...patch})
  ;[r.hierarchyHeight,r.widgetHeight,r.blankHeight].forEach((v,i)=>{
    assert.ok(Number.isFinite(v)&&v>=0);near(v,expected[i])
  })
}
let seed=999
const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296}
const invalid=[undefined,null,NaN,Infinity,-Infinity,'200',{},-10]
const dimension=()=>random()<0.1?invalid[Math.floor(random()*invalid.length)]:random()*1800
const finite=(n,fallback=0)=>typeof n==='number'&&Number.isFinite(n)?n:fallback
for(let i=0;i<100000;i++){
  const input={availableHeight:dimension(),hierarchyContentHeight:dimension(),widgetHeaderHeight:dimension(),
    widgetContentHeight:dimension(),minHierarchyHeight:dimension(),minWidgetHeight:dimension(),
    presentedWidgetCount:random()<0.1?dimension():Math.floor(random()*8),rail:random()<0.1,
    requestedSplitPx:random()<0.5?null:dimension()}
  const r=model.sidebarSplitLayout(input)
  const A=Math.max(0,finite(input.availableHeight)),H=Math.max(0,finite(input.hierarchyContentHeight))
  const Wh=Math.max(0,finite(input.widgetHeaderHeight)),W=Math.max(0,finite(input.widgetContentHeight))
  const count=Math.max(0,Math.floor(finite(input.presentedWidgetCount)))
  for(const value of Object.values(r))assert.ok(Number.isFinite(value)&&value>=0)
  near(r.hierarchyHeight+r.widgetHeight+r.blankHeight,A)
  assert.ok(r.hierarchyHeight<=H+1e-7);assert.ok(r.widgetHeight<=Wh+W+1e-7)
  if(input.rail||count===0||A<Wh)assert.equal(r.widgetHeight,0)
  else{
    assert.ok(r.widgetHeight+1e-7>=Wh)
    const hmin=Math.min(H,Math.max(0,finite(input.minHierarchyHeight)))
    const wmin=Math.min(Wh+W,Math.max(Wh,finite(input.minWidgetHeight,Wh)))
    if(hmin+wmin<=A){assert.ok(r.hierarchyHeight+1e-7>=hmin);assert.ok(r.widgetHeight+1e-7>=wmin)}
  }
}
for(const input of [undefined,null,{}, {availableHeight:Number.MAX_VALUE,hierarchyContentHeight:Number.MAX_VALUE,
  widgetHeaderHeight:Number.MAX_VALUE,widgetContentHeight:Number.MAX_VALUE,presentedWidgetCount:1}])
  for(const value of Object.values(model.sidebarSplitLayout(input)))assert.ok(Number.isFinite(value)&&value>=0)
const cards=[{id:'one',y:0,height:100},{id:'two',y:106,height:150},{id:'three',y:262,height:200}]
const a=model.widgetScrollAnchor(cards,130)
assert.equal(a.id,'two');assert.equal(a.offset,24)
assert.equal(model.widgetScrollPosition(a,cards,300),130)
assert.equal(model.widgetScrollPosition(a,[{id:'one',y:0,height:160},{id:'two',y:166,height:150},{id:'three',y:322,height:200}],400),190)
assert.equal(model.widgetScrollPosition(a,[{id:'one',y:0,height:100},{id:'three',y:106,height:200}],200),106)
assert.equal(model.widgetScrollPosition(a,[{id:'one',y:0,height:100}],20),0)
assert.equal(model.widgetScrollPosition(a,[],0),0)
assert.equal(model.widgetScrollPosition(a,[{id:'two',y:0,height:150},{id:'one',y:156,height:100}],140),24)
assert.equal(model.widgetScrollPosition(a,cards,10),10)
assert.equal(model.widgetFocusScroll(270,24,130,100,400),194)
assert.equal(model.widgetFocusScroll(50,24,130,100,400),50)
assert.equal(model.widgetFocusScroll(150,24,130,100,400),130)
assert.equal(model.widgetFocusScroll(150,240,130,100,400),150)
console.log('FDM-999: 16 table + 100000 seeded allocation cases, invalid inputs, stable anchors and focused-descendant bounds PASS')
