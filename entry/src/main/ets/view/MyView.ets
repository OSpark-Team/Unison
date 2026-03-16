import { WindowProperties } from "../model/WindowProperties";
import { SettingsView } from "./SettingsView"
import { SourceManagementView } from "./SourceManagementView"
import { AppStorageV2 } from "@kit.ArkUI";
import { BreakpointConstants } from "../common/BreakpointConstants";
import { OSparkLogo } from "../components/OSparkLogo";

@ComponentV2
export struct MyView {
  /**
   * 路由导航
   */
  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;

  build() {
    Scroll() {
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
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .width("100%")
    .height("100%")
  }
}