/**
 * 内容卡片组件
 *
 * 功能特性：
 * - 顶部固定标题区域（标题 + 描述）
 * - 下方完全自定义的内容插槽
 * - 支持自定义宽度、高度和宽高比
 * - 宽高比优先于固定高度
 *
 * 使用场景：
 * - 推荐列表：标题显示"本周推荐"，内容插槽显示推荐项列表
 * - 功能介绍：标题显示功能名称，内容插槽显示功能说明或演示
 * - 数据展示：标题显示数据类别，内容插槽显示图表或统计信息
 *
 * @example
 * ```typescript
 * // 示例 1：推荐列表
 * ContentCard({
 *   title: "本周推荐",
 *   description: "为你精选的音乐"
 * }) {
 *   // 内容插槽
 *   List() {
 *     ForEach(items, (item) => {
 *       ListItem() {
 *         Text(item.name)
 *       }
 *     })
 *   }
 * }
 *
 * // 示例 2：功能介绍
 * ContentCard({
 *   title: "智能推荐",
 *   description: "基于你的喜好推荐内容",
 *   aspectRatioValue: 1.5,  // 3:2 宽高比
 *   widthValue: 300
 * }) {
 *   Column() {
 *     Image($r('app.media.feature_icon'))
 *     Text("功能说明文字")
 *   }
 * }
 *
 * // 示例 3：固定高度
 * ContentCard({
 *   title: "最近播放",
 *   heightValue: 200  // 如果不设置 aspectRatioValue，使用固定高度
 * }) {
 *   Scroll() {
 *     // 滚动内容
 *   }
 * }
 * ```
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

@ComponentV2
export struct ContentCard {
  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  /**
   * 卡片宽度
   * 默认值：'100%'
   * 注意：由于 width 是 ArkUI 保留属性，使用 widthValue 命名
   */
  @Param widthValue: string | number = '100%';

  /**
   * 卡片高度
   * 默认值：undefined（自适应内容）
   * 注意：如果同时设置了 aspectRatioValue，由 ArkUI 框架根据宽度和宽高比自动计算高度
   */
  @Param heightValue?: string | number = undefined;

  /**
   * 宽高比（宽度 / 高度）
   * 默认值：undefined（不使用宽高比，高度自适应内容）
   * 示例：
   * - 1.5 表示 3:2（宽:高）
   * - 1.0 表示 1:1（正方形）
   * - 1.777 表示 16:9
   * 注意：设置后由 ArkUI 框架自动根据宽度计算高度
   */
  @Param aspectRatioValue?: number = undefined;

  /**
   * 卡片标题
   * 显示在顶部标题区域，较大字号
   */
  @Param title: ResourceStr = '';

  /**
   * 卡片描述
   * 显示在标题下方，较小字号，灰色
   */
  @Param description?: ResourceStr = undefined;

  /**
   * 圆角半径
   * 默认值：12
   */
  @Param borderRadiusValue: number = 12;

  /**
   * 卡片背景色
   * 默认值：白色
   */
  @Param bgColor: ResourceColor = $r('app.color.background_white');

  /**
   * 标题区域内边距
   * 默认值：16
   */
  @Param titlePadding: number = 16;

  /**
   * 内容区域内边距
   * 默认值：8
   */
  @Param contentPadding: number = 8;

  /**
   * 默认内容插槽构建器
   * 当没有传入 content 时使用
   */
  @Builder
  defaultContentSlot() {
  }

  /**
   * 内容插槽
   * 位于标题区域下方，占据剩余空间
   * 可以放置任意自定义内容
   */
  @BuilderParam content: () => void = this.defaultContentSlot;

  build() {
    Column() {
      // 标题区域
      if (this.title || this.description) {
        Column({ space: 4 }) {
          if (this.title) {
            Text(this.title)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.description) {
            Text(this.description)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding(this.titlePadding)
        .alignItems(HorizontalAlign.Start)
      }

      // 内容区域插槽
      Column() {
        this.content()
      }
      .width('100%')
      .layoutWeight(1)  // 占据剩余空间
      .padding(this.contentPadding)
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .aspectRatio(this.aspectRatioValue)
    .backgroundColor(this.bgColor)
    .borderRadius(this.borderRadiusValue)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
    .clip(true)  // 裁剪超出圆角的内容
  }
}
