import { Playlist } from '../model/adapter/Playlist';
import { ImageColorExtractor } from '../utils/ImageColorExtractor';
import { cover } from '../utils/Tools';
import Logger from '../utils/Logger';
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

const TAG = 'PlaylistInfoCard';

/**
 * 歌单信息卡片组件
 *
 * 架构说明：
 * - 纯静态结构（背景层、封面、文字信息、加载态）保留 @Builder
 * - 含响应式状态的操作按钮区域直接在 build() 里内联
 * - 根本原因：@Builder 嵌套调用时内层 this.xxx 脱离响应式追踪链
 *   收藏图标依赖 this.isSubscribed，必须在 build() 直接渲染才能响应变化
 */
@ComponentV2
export struct PlaylistInfoCard {
  /** 系统设置 ViewModel */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** 歌单数据 */
  @Param @Require playlist: Playlist;

  /** 是否已订阅 */
  @Param isSubscribed: boolean = false;

  /** 是否显示收藏按钮 */
  @Param showFavoriteButton: boolean = true;

  /** 播放全部回调 */
  @Param onPlayAll?: () => void = undefined;

  /** 随机播放回调 */
  @Param onShuffle?: () => void = undefined;

  /** 收藏或取消收藏回调 */
  @Param onToggleFavorite?: () => void = undefined;

  /** 下载全部回调 */
  @Param onDownloadAll?: () => void = undefined;

  /** 卡片高度 */
  @Param cardHeight: number | string = 280;

  /** 封面尺寸 */
  @Param coverSize: number = 160;

  /** 是否为垂直布局（SM断点） */
  @Param isVerticalLayout: boolean = false;

  /** 动态提取的主色调 */
  @Local mainColor: string = '#FF007DFF';

  /** 动态提取的多个颜色 */
  @Local dominantColors: string[] = ['#FF007DFF', '#FF4ECDC4', '#FF45B7B8'];

  /** 渐变起始颜色（较亮） */
  @Local gradientStartColor: string = '#FF3399FF';

  /** 渐变结束颜色（较暗） */
  @Local gradientEndColor: string = '#FF005BB5';

  /** 主色调提取状态 */
  @Local colorExtracted: boolean = false;

  aboutToAppear(): void {
    this.extractMainColor();
  }

  @Computed
  get cover(): string | undefined {
    let coverUrl = this.playlist.cover;
    if (coverUrl?.startsWith('cover://')) {
      const index = parseInt(coverUrl.substring(8));
      coverUrl = this.playlist.songs?.[index]?.album?.cover;
    }
    return coverUrl;
  }

  private async extractMainColor(): Promise<void> {
    if (!this.playlist.cover) {
      Logger.warn(TAG, '歌单封面为空，使用默认颜色');
      this.colorExtracted = true;
      return;
    }
    try {
      const coverUrl = cover(this.cover, 100) as string;
      this.dominantColors = await ImageColorExtractor.extractMultipleDominantColors(coverUrl, 100);
      if (this.dominantColors.length > 0) {
        const colorsToMix = this.dominantColors.length > 1
          ? [this.dominantColors[0], this.dominantColors[1]]
          : [this.dominantColors[0]];
        this.mainColor = ImageColorExtractor.mixColors(colorsToMix, 0.6);
        this.gradientStartColor = ImageColorExtractor.adjustColorBrightness(this.mainColor, 1.15);
        this.gradientEndColor = ImageColorExtractor.adjustColorBrightness(this.mainColor, 0.7);
        Logger.info(TAG, `颜色提取成功 - 主色: ${this.mainColor}, 渐变: ${this.gradientStartColor} -> ${this.gradientEndColor}`);
      }
      this.colorExtracted = true;
      Logger.info(TAG, `多颜色提取成功: ${this.dominantColors.join(', ')}`);
    } catch (error) {
      Logger.error(TAG, `颜色提取失败: ${error}`);
      this.colorExtracted = true;
    }
  }

  // ─────────────────────────────────────────────
  // 静态结构 @Builder（不含响应式状态判断，可安全使用）
  // ─────────────────────────────────────────────

  @Builder
  buildBackgroundLayer() {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 135,
        colors: [
          [this.gradientStartColor, 0.0],
          [this.mainColor, 0.5],
          [this.gradientEndColor, 1.0]
        ]
      })
      .opacity(this.settingModel.opacityPlaylistGradient)
  }

  @Builder
  buildCover() {
    if (this.cover) {
      Image(cover(this.cover, this.coverSize))
        .width(this.coverSize)
        .height(this.coverSize)
        .borderRadius(this.settingModel.radiusCard)
        .objectFit(ImageFit.Cover)
        .shadow({
          radius: 24,
          color: $r('app.color.cover_shadow_strong'),
          offsetX: 0,
          offsetY: 10
        })
        .animation({ duration: 300, curve: Curve.EaseInOut })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(48)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(this.coverSize)
      .height(this.coverSize)
      .borderRadius(this.settingModel.radiusCard)
      .backgroundColor($r('app.color.background_secondary'))
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  buildPlaylistInfo() {
    Column({ space: 8 }) {
      Text(this.playlist.name || $r('app.string.playlist_detail_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.playlist_text_on_image'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .width('100%')

      if (this.playlist.description) {
        Text(this.playlist.description)
          .fontSize(13)
          .fontColor($r('app.color.playlist_text_secondary_on_image'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(18)
          .margin({ top: 4 })
      } else {
        Text($r('app.string.playlist_description_empty'))
          .fontSize(13)
          .fontColor($r('app.color.playlist_text_secondary_on_image'))
          .opacity(this.settingModel.opacityWeak)
          .margin({ top: 4 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  buildLoadingState() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.playlist_text_on_image'))
      Text($r('app.string.playlist_loading'))
        .fontSize(14)
        .fontColor($r('app.color.playlist_text_secondary_on_image'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.playlist_loading_background'))
  }


  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.colorExtracted) {

        this.buildBackgroundLayer()

        if (this.isVerticalLayout) {
          // ── 垂直布局（SM断点）──
          Column({ space: 16 }) {
            Row({ space: 16 }) {
              this.buildCover()
              this.buildPlaylistInfo()
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            Row() {
              // 左侧操作按钮
              Row({ space: 12 }) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.shuffle'))
                    .fontSize(20)
                    .fontColor([$r('app.color.playlist_text_on_image')])
                }
                .width(44).height(44)
                .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.2))
                .onClick(() => { this.onShuffle?.() })
                .animation({ duration: 200, curve: Curve.EaseInOut })

                if (this.showFavoriteButton) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph(this.isSubscribed ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                      .fontSize(20)
                      .fontColor([$r('app.color.playlist_text_on_image')])
                  }
                  .width(44).height(44)
                  .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.2))
                  .onClick(() => { this.onToggleFavorite?.() })
                  .animation({ duration: 200, curve: Curve.EaseInOut })
                }

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(20)
                    .fontColor([$r('app.color.playlist_text_on_image')])
                }
                .width(44).height(44)
                .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.2))
                .onClick(() => { this.onDownloadAll?.() })
                .animation({ duration: 200, curve: Curve.EaseInOut })
              }

              Blank()

              // 右侧播放按钮
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.play_fill'))
                  .fontSize(28)
                  .fontColor([$r('app.color.playlist_text_on_image')])
              }
              .width(60).height(60)
              .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.3))
              .onClick(() => { this.onPlayAll?.() })
              .animation({ duration: 200, curve: Curve.EaseInOut })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .height('100%')
          .padding(20)
          .justifyContent(FlexAlign.SpaceBetween)

        } else {
          // ── 水平布局（MD / LG断点）──
          Column({ space: 20 }) {
            Row() {
              Blank()
              this.buildCover()
              Blank()
            }
            .width('100%')

            Column({ space: 8 }) {
              Text(this.playlist.name || '')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.playlist_text_on_image'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Center)

              if (this.playlist.description) {
                Text(this.playlist.description)
                  .fontSize(14)
                  .fontColor($r('app.color.playlist_text_secondary_on_image'))
                  .maxLines(6)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)

            Blank()

            Row() {
              // 左侧操作按钮
              Row({ space: 12 }) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.shuffle'))
                    .fontSize(20)
                    .fontColor([$r('app.color.playlist_text_on_image')])
                }
                .width(44).height(44)
                .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.2))
                .onClick(() => { this.onShuffle?.() })
                .animation({ duration: 200, curve: Curve.EaseInOut })

                if (this.showFavoriteButton) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph(this.isSubscribed ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                      .fontSize(20)
                      .fontColor([$r('app.color.playlist_text_on_image')])
                  }
                  .width(44).height(44)
                  .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.2))
                  .onClick(() => { this.onToggleFavorite?.() })
                  .animation({ duration: 200, curve: Curve.EaseInOut })
                }

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(20)
                    .fontColor([$r('app.color.playlist_text_on_image')])
                }
                .width(44).height(44)
                .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.2))
                .onClick(() => { this.onDownloadAll?.() })
                .animation({ duration: 200, curve: Curve.EaseInOut })
              }

              Blank()

              // 右侧播放按钮
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.play_fill'))
                  .fontSize(28)
                  .fontColor([$r('app.color.background_white')])
              }
              .width(60).height(60)
              .backgroundColor(ImageColorExtractor.generateGradientColor(this.mainColor, 0.3))
              .onClick(() => { this.onPlayAll?.() })
              .animation({ duration: 200, curve: Curve.EaseInOut })
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .width('100%')
          .height('100%')
          .padding(20)
          .justifyContent(FlexAlign.SpaceBetween)
        }

      } else {
        this.buildLoadingState()
      }
    }
    .width('100%')
    .height(this.cardHeight)
    .borderRadius(this.settingModel.radiusCardLarge)
    .clip(true)
    .animation({
      duration: 400,
      curve: Curve.EaseInOut
    })
  }
}
