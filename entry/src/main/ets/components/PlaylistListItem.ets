/**
 * 歌单列表项组件
 *
 * 功能特性：
 * - 左侧显示歌单封面（正方形，圆角）
 * - 中间显示歌单名称和歌曲数量（垂直布局）
 * - 右侧显示可选的操作按钮
 * - 支持点击交互和状态样式
 * - 支持自定义封面尺寸和操作区域
 *
 * 使用场景：
 * - 歌单列表展示
 * - 推荐歌单
 * - 收藏歌单列表
 * - 搜索结果列表
 *
 * @example
 * ```typescript
 * // 示例 1：基础使用
 * PlaylistListItem({
 *   coverImage: $r('app.media.playlist_cover'),
 *   playlistName: "华语流行精选",
 *   trackCount: 50
 * })
 *
 * // 示例 2：带点击事件
 * PlaylistListItem({
 *   coverImage: $r('app.media.playlist_cover'),
 *   playlistName: "周杰伦精选集",
 *   trackCount: 30,
 *   onItemClick: () => {
 *     console.log("打开歌单详情")
 *   }
 * })
 *
 * // 示例 3：带操作按钮
 * PlaylistListItem({
 *   coverImage: $r('app.media.playlist_cover'),
 *   playlistName: "我喜欢的音乐",
 *   trackCount: 120,
 *   onItemClick: () => {
 *     console.log("打开歌单详情")
 *   }
 * }) {
 *   // 操作插槽：更多按钮
 *   Row() {
 *     Image($r('sys.symbol.ellipsis'))
 *       .width(24)
 *       .height(24)
 *       .fillColor($r('app.color.text_secondary'))
 *   }
 *   .padding(8)
 *   .onClick((event: ClickEvent) => {
 *     event.stopPropagation()  // 阻止事件冒泡
 *     console.log("显示更多操作")
 *   })
 * }
 *
 * // 示例 4：自定义封面尺寸
 * PlaylistListItem({
 *   coverImage: $r('app.media.playlist_cover'),
 *   playlistName: "古典音乐合集",
 *   trackCount: 80,
 *   coverSize: 56  // 自定义封面尺寸
 * })
 * ```
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
@ComponentV2
export struct PlaylistListItem {
  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  /**
   * 歌单封面图片资源
   * 必填，显示在列表项左侧
   */
  @Param coverImage: ResourceStr = '';

  /**
   * 歌单名称
   * 必填，显示在封面右侧上方
   */
  @Param playlistName: ResourceStr = '';

  /**
   * 歌曲数量
   * 必填，显示在歌单名称下方
   */
  @Param trackCount: number = 0;

  /**
   * 封面尺寸（正方形）
   * 默认值：48（单位：vp）
   * 可选，用于自定义封面大小
   */
  @Param coverSize: number = 48;

  /**
   * 封面圆角半径
   * 默认值：4（单位：vp）
   */
  @Param coverRadius: number = 4;

  /**
   * 列表项高度
   * 默认值：64（单位：vp）
   */
  @Param itemHeight: number = 64;

  /**
   * 列表项左右内边距
   * 默认值：16（单位：vp）
   */
  @Param horizontalPadding: number = 16;

  /**
   * 元素间距
   * 默认值：12（单位：vp）
   */
  @Param itemSpacing: number = 12;

  /**
   * 列表项背景颜色
   * 默认值：Color.Transparent（透明）
   * 可选，用于自定义列表项的背景色
   */
  @Param bgColor: ResourceColor = Color.Transparent;

  /**
   * 是否显示底部分隔线
   * 默认值：false
   * 可选，分隔线从歌单信息位置开始（不从封面下方开始）
   */
  @Param showDivider: boolean = false;

  /**
   * 点击回调函数
   * 可选，当用户点击列表项时触发
   */
  @Param onItemClick?: () => void = undefined;

  /**
   * 默认操作插槽构建器
   * 当没有传入 actionContent 时使用
   */
  @Builder
  defaultActionSlot() {
  }

  /**
   * 操作区域插槽
   * 位于歌曲数量右侧，用于放置"更多"按钮、"收藏"按钮等
   * 可选，如果不传入内容，该区域不显示
   */
  @BuilderParam actionContent: () => void = this.defaultActionSlot;

  /**
   * 处理列表项点击事件
   */
  private handleClick(): void {
    if (this.onItemClick) {
      this.onItemClick();
    }
  }

  /**
   * 格式化歌曲数量文本
   */
  @Computed
  get formattedTrackCount(): ResourceStr {
    return $r('app.string.playlist_track_count', this.trackCount.toString());
  }

  build() {
    Column() {
      Row({ space: this.itemSpacing }) {
        // 左侧：歌单封面
        Image(this.coverImage)
          .width(this.coverSize)
          .height(this.coverSize)
          .borderRadius(this.coverRadius)
          .objectFit(ImageFit.Cover)

        // 中间：歌单信息区域
        Column({ space: 4 }) {
          // 歌单名称
          Text(this.playlistName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 歌曲数量
          if (this.trackCount > 0) {
            Text(this.formattedTrackCount)
              .fontSize(14)
              .fontWeight(FontWeight.Regular)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)  // 占据剩余空间
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        // 右侧：操作插槽区域
        Row({ space: 8 }) {
          // 操作插槽
          this.actionContent()
        }
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(this.itemHeight)
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
      .onClick(() => {
        this.handleClick();
      })
      .hoverEffect(HoverEffect.Highlight)
      .stateStyles({
        normal: {
          .backgroundColor(this.bgColor)
          .borderRadius(this.settingModel.radiusItem)
        },
        pressed: {
          .backgroundColor($r('app.color.item_pressed'))
          .borderRadius(this.settingModel.radiusItem)
        }
      })

      // 底部分隔线
      if (this.showDivider) {
        Divider()
          .strokeWidth(1)
          .color($r('app.color.divider'))
          .margin({ left: this.horizontalPadding + this.coverSize + this.itemSpacing })
      }
    }
    .width('100%')
  }
}
