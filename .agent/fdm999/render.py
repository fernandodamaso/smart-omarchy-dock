"""Supplementary Qt/Mesa captures; not native Omarchy host qualification."""
from pathlib import Path
import os
import subprocess
from tests.test_widget_chrome_qml import block

source = Path('tests/tst_sidebarsplitscroll.qml').read_text()
source = source.replace('  width: 760; height: 780', '  width: 660; height: 680')
source = source.replace('      implicitHeight: width < 230 ? 410 : 290', '''      implicitHeight: display.implicitHeight + field.implicitHeight + 34
      DemoWidgetDisplayBody {
        id: display
        width: parent.width
        widgetContext: ({data:{status:"Healthy",provider:"Synthetic fixture",cpu:0.42,memory:0.849,
          stats:[{label:"Agents",value:"4",helper:"3 active"},{label:"Coverage",value:"92%",helper:"Headless"}],
          trend:[4,7,5,9,8,12,11]}})
      }
      WidgetFormField {
        id: field; y:display.implicitHeight+12; width:parent.width
        label:"Example input"; helperText:"Native host qualification remains FDM-1001."
        WidgetTextInput { width:parent.width; text:"WidgetKit 1.0" }
      }''')
source = source.replace('      WidgetTextInput { objectName:"split-input-first"; y:10; width:parent.width; text:"first" }', '')
source = source.replace('      WidgetTextInput { objectName:"split-input-last"; y:parent.implicitHeight-40; width:parent.width; text:"last" }', '')
source = source.replace('        Rectangle { width:parent.width; height:800; color:"#303440" }', '''        Rectangle {
          width:parent.width; height:800
          color:Qt.tint(Color.background,Util.alpha(Color.foreground,0.035))
          Column {
            x:10; y:10; width:parent.width-20; spacing:10
            WidgetText { text:"Hierarchy input fixture"; role:"title" }
            WidgetText { text:"Not a full Omarchy desktop"; role:"caption"; muted:true }
            Repeater { model:18; WidgetText { required property int index; text:"Window "+(index+1); width:parent.width } }
          }
        }''')
source = source.replace('  property var areas: []', '''  Rectangle { anchors.fill:parent; color:Color.background; z:-10 }
  property var areas: []''')
source = source[:source.rfind('}')] + '''
  function test_render_final_evidence() {
    var f=build(20),g=build(350)
    f.panel.y=30;g.panel.y=30
    f.panel.availableHeight=500;g.panel.availableHeight=500
    f.panel.viewport.contentHeight=130;g.panel.viewport.contentHeight=130
    f.panel.footerControl.y=540;g.panel.footerControl.y=540
    settle(f);settle(g)
    g.area.scrollView.contentY=120;settle(g)
    mouseMove(testCase,650,670)
    wait(100)
    var saved=false
    verify(testCase.grabToImage(function(result){saved=result.saveToFile("@@OUTPUT@@")}))
    tryVerify(function(){return saved})
  }
}
'''
out = Path(os.environ['RUNNER_TEMP']) / 'evidence' / 'gallery'
out.mkdir(parents=True, exist_ok=True)
case = Path('tests/tst_fdm999_render_temporary.qml')
try:
    for theme, bg, fg, muted, accent, urgent in [
        ('tokyo-night','#1a1b26','#a9b1d6','#414868','#7aa2f7','#f7768e'),
        ('catppuccin-latte','#eff1f5','#4c4f69','#acb0be','#1e66f5','#d20f39'),
    ]:
        text = source.replace('    var f=build(20),g=build(350)',
            f'    Color.background="{bg}";Color.foreground="{fg}";Color.muted="{muted}";Color.accent="{accent}";Color.urgent="{urgent}"\n    var f=build(20),g=build(350)')
        case.write_text(text.replace('@@OUTPUT@@', str(out / (theme + '.png'))))
        env = dict(os.environ, QT_QPA_PLATFORM='xcb', QSG_RHI_BACKEND='opengl', LIBGL_ALWAYS_SOFTWARE='1', QML_XHR_ALLOW_FILE_READ='1')
        env.pop('QT_QUICK_BACKEND', None)
        result = subprocess.run(['xvfb-run','-a','/usr/lib/qt6/bin/qmltestrunner','-input',str(case),'-import','components','-import','tests/qml-imports',
                                 'SidebarSplitScroll::test_render_final_evidence'],env=env,capture_output=True,text=True,timeout=45)
        (out / (theme + '.log')).write_text(result.stdout + result.stderr)
        if result.returncode != 0:
            raise RuntimeError(result.stdout + result.stderr)
        print(theme, 'capture:', out / (theme + '.png'))
finally:
    case.unlink(missing_ok=True)
