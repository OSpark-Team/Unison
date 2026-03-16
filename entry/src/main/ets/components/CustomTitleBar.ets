/**
 * 自定义标题栏组件
 * 
 * 功能特性：
 * - 支持状态栏避让处理
 * - 左侧返回按钮
 * - 中间标题文本
 * - 右侧操作按钮（可选）
 * - 透明背景或自定义背景色
 * 
 * 使用场景：
 * - 全屏页面的自定义标题栏
 * - 需要状态栏避让的页面
 * - 替代 NavDestination 默认标题栏
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { WindowProperties } from '../model/WindowProperties';
import { BreakpointConstants } from '../common/BreakpointConstants';

@ComponentV2
export struct CustomTitleBar {
  /**
   * 标题文本
   */
  @Param title: ResourceStr = '';
  
  /**
   * 是否显示返回按钮
   */
  @Param showBackButton: boolean = true;
  
  /**
   * 返回按钮点击回调
   */
  @Param onBackClick?: () => void = undefined;
  
  /**
   * 标题栏背景色
   */
  @Param bgColor: ResourceColor = Color.Transparent;
  
  /**
   * 标题栏高度（不包含状态栏避让）
   */
  @Param barHeight: number = 48;

  /**
   * 是否显示搜索框
   */
  @Param showSearchBox: boolean = false;

  /**
   * 搜索关键词变化回调
   */
  @Param onSearchChange?: (keyword: string) => void = undefined;

  /**
   * 搜索框占位符文本
   */
  @Param searchPlaceholder: Resource = $r('app.string.search_placeholder');

  /**
   * 搜索关键词
   */
  @Local searchKeyword: string = '';

  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;
  
  /**
   * 搜索框 Builder
   */
  @Builder
  buildSearchBox() {
    Search({
      value: this.searchKeyword,
      placeholder: this.searchPlaceholder
    })
      .width(this.getSearchBoxWidth())
      .onSubmit((value: string) => {
        this.handleSearchChange(value);
      })
      .onChange((value: string) => {
        this.handleSearchChange(value);
      })
      .animation({
        duration: 300,
        curve: Curve.EaseInOut,
        playMode: PlayMode.Normal
      })
  }

  /**
   * 右侧操作插槽构建器
   */
  @Builder
  defaultActionSlot() {
    // 默认为空
  }

  /**
   * 右侧操作区域插槽
   */
  @BuilderParam actionContent: () => void = this.defaultActionSlot;
  
  /**
   * 处理返回按钮点击
   */
  private handleBackClick(): void {
    if (this.onBackClick) {
      this.onBackClick();
    }
  }

  /**
   * 处理搜索关键词变化
   */
  private handleSearchChange(keyword: string): void {
    this.searchKeyword = keyword;
    if (this.onSearchChange) {
      this.onSearchChange(keyword);
    }
  }

  /**
   * 获取搜索框宽度
   */
  private getSearchBoxWidth(): number | string {
    if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM) {
      return "calc(100% - 360px)";
    } else if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_MD) {
      return "60%";
    } else {
      return "60%";
    }
  }
  
  build() {
    Column() {
      // 状态栏占位区域
      Row()
        .width('100%')
        .height(this.windowProperties.topRect)
        .backgroundColor(this.bgColor)
      
      // 标题栏内容区域
      Row({ space: 8 }) {
        // 左侧：返回按钮
        if (this.showBackButton) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(26)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(46)
          .height(46)
          .backgroundColor($r("app.color.background_secondary"))
          .onClick(() => this.handleBackClick())
        }

        // 中间：标题
        if (!this.showSearchBox) {
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
        } else {
          // 当搜索框展开时，标题隐藏或缩小
          Blank()
        }

        // 搜索框区域
        if (this.showSearchBox) {
          this.buildSearchBox()
        }

        // 右侧：操作区域
        if (!this.showSearchBox) {
          Row() {
            this.actionContent()
          }
          .justifyContent(FlexAlign.End)
        }
      }
      .width('100%')
      .height(this.barHeight)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.bgColor)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}
