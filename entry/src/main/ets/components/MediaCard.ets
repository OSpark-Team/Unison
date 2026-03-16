/**
 * 媒体卡片组件
 *
 * 功能特性：
 * - 支持背景图片或背景视频展示
 * - 底部内容区域带模糊半透明效果
 * - 支持自定义操作区域（通过插槽）
 * - 支持自定义宽度、高度和宽高比
 * - 宽高比优先于固定高度
 *
 * 使用场景：
 * - 资讯展示：显示新闻标题和摘要
 * - 音乐/视频推荐：显示封面、标题和播放按钮
 * - 书籍推荐：显示封面、书名和查看详情按钮
 *
 * @example
 * ```typescript
 * // 示例 1：基础使用 - 只显示图片和文字
 * MediaCard({
 *   backgroundImage: $r('app.media.cover'),
 *   title: "标题文字",
 *   description: "描述文字"
 * })
 *
 * // 示例 2：带操作按钮
 * MediaCard({
 *   backgroundImage: $r('app.media.cover'),
 *   title: "音乐标题",
 *   description: "艺术家名称",
 *   aspectRatioValue: 1  // 1:1 正方形
 * }) {
 *   // 操作区域插槽
 *   Row() {
 *     Button("播放")
 *     Button("收藏")
 *   }
 * }
 *
 * // 示例 3：背景视频
 * MediaCard({
 *   backgroundVideo: $rawfile('video/preview.mp4'),
 *   title: "视频标题",
 *   description: "视频描述",
 *   widthValue: 300,
 *   aspectRatioValue: 16 / 9  // 16:9 宽高比
 * })
 * ```
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

@ComponentV2
export struct MediaCard {
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
   * 默认值：undefined
   * 注意：如果同时设置了 aspectRatioValue，由 ArkUI 框架根据宽度和宽高比自动计算高度
   */
  @Param heightValue?: string | number = undefined;

  /**
   * 宽高比（宽度 / 高度）
   * 默认值：undefined
   * 示例：
   * - 1.5 表示 3:2（宽:高）
   * - 1.0 表示 1:1（正方形）
   * - 1.777 表示 16:9
   * 注意：设置后由 ArkUI 框架自动根据宽度计算高度
   */
  @Param aspectRatioValue?: number = undefined;

  /**
   * 背景图片资源
   * 可选，如果同时提供 backgroundVideo，视频优先显示
   */
  @Param backgroundImg?: ResourceStr = undefined;

  /**
   * 背景视频资源
   * 可选，视频会自动静音循环播放
   * 优先级高于 backgroundImage
   */
  @Param backgroundVideo?: ResourceStr = undefined;

  /**
   * 卡片标题
   * 显示在底部内容区域，较大字号
   */
  @Param title: ResourceStr = '';

  /**
   * 卡片描述
   * 显示在标题下方，较小字号
   */
  @Param description?: ResourceStr = undefined;

  /**
   * 圆角半径
   * 默认值：12
   */
  @Param borderRadiusValue: number = 12;

  /**
   * 默认操作插槽构建器
   * 当没有传入 actionContent 时使用
   */
  @Builder
  defaultActionSlot() {
  }

  /**
   * 操作区域插槽
   * 位于内容区域下方，用于放置按钮等交互元素
   * 可选，如果不传入内容，该区域不显示
   */
  @BuilderParam actionContent: () => void = this.defaultActionSlot;

  /**
   * 卡片点击事件
   */
  @Param onCardClick?: () => void = undefined;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景层：视频或图片
      if (this.backgroundVideo) {
        // 背景视频（优先级更高）
        Video({
          src: this.backgroundVideo,
          controller: new VideoController()
        })
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoPlay(true)
          .muted(true)
          .loop(true)
          .controls(false)
      } else if (this.backgroundImg) {
        // 背景图片
        Image(this.backgroundImg)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        // 无背景时显示占位色
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_gray_light'))
      }

      // 内容层：底部标题描述区域 + 操作区域
      Column() {
        // 标题和描述区域
        Column({ space: 4 }) {
          if (this.title) {
            Text(this.title)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.description) {
            Text(this.description)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .opacity(this.settingModel.opacitySecondaryText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)

        // 操作区域插槽（背景模糊效果）
      Column() {
        this.actionContent()
      }
      .backgroundBlurStyle(this.settingModel.blurStyleLevel >= 2 ? BlurStyle.BACKGROUND_THICK : BlurStyle.Thin,
        { colorMode: ThemeColorMode.LIGHT, adaptiveColor: AdaptiveColor.DEFAULT, scale: 1.0 })
      .width('100%')
      }
      .width('100%')
    }
    .onClick(()=>{
      if(this.onCardClick){
        this.onCardClick();
      }
    })
    .width(this.widthValue)
    .height(this.heightValue)
    .aspectRatio(this.aspectRatioValue)
    .borderRadius(this.borderRadiusValue)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
    .clip(true)  // 裁剪超出圆角的内容
  }
}
