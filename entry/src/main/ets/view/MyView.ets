import { WindowProperties } from "../model/WindowProperties";
import { SettingsView } from "./SettingsView"
import { SourceManagementView } from "./SourceManagementView"
import { AppStorageV2, PersistenceV2 } from "@kit.ArkUI";
import { BreakpointConstants } from "../common/BreakpointConstants";
import { OSparkLogo } from "../components/OSparkLogo";
import TabSettingModel from "../model/adapter/TabSetting";

@ComponentV2
export struct MyView {
  @Require @Param scroller: Scroller ;

  /**
   * 路由导航
   */
  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;
  /** Tab样式设置 ViewModel（用于统一 UI 参数） */
  @Local TabSettingModel: TabSettingModel = PersistenceV2.connect(TabSettingModel, 'TabSettingModel', () => new TabSettingModel())!;
  build() {
    Scroll(this.scroller) {
      Column() {
        // 数据源管理区域
        SourceManagementView()

        // 设置项区域
        SettingsView()

        // Logo区域
        Column(){
          OSparkLogo({
            compHeight: 24,
            density: 6,
          })
        }
        .padding(16)
      }
      .margin({
        bottom: this.windowProperties.bottomRect,
        top: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? this.windowProperties.topRect + 64 : 100,
        left: 24,
        right: 24,
      })
    }
    .contentEndOffset(this.TabSettingModel.barFloatingStyle?72:0)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .width("100%")
    .height("100%")
  }
}