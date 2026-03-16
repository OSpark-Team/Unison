import { AppStorageV2, PersistenceV2, curves } from '@kit.ArkUI';
import { Song } from '../model/adapter/Song';
import { WindowProperties } from '../model/WindowProperties';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { LyricLine, ParsedLrc } from '../utils/LrcParser';
import { cover } from '../utils/Tools';
import WindowUtil from '../utils/WindowUtil';

@ComponentV2
export struct NowPlayingLandscape {
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, 'WindowProperties', () => new WindowProperties())!;
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  // 基础数据源
  @Param song?: Song = undefined;
  @Param parsedLrc: ParsedLrc = new ParsedLrc([], []);
  @Param activeLyricIndex: number = 0;
  @Param currentProgress: number = 0;
  @Param duration: number = 0;
  @Param isPlaying: boolean = false;
  @Param modeSymbol: Resource = $r('sys.symbol.repeat');

  // 音频律动参数 (0 ~ 1.0)
  @Param audioLevel: number = 0;
  @Param audioBass: number = 0;
  @Param audioMid: number = 0;
  @Param audioTreble: number = 0;

  // 提取的封面颜色参数 (让流光背景随封面变色)
  @Param mainColor: string = '#FF007DFF';
  @Param gradientStartColor: string = '#FF3399FF';
  @Param gradientEndColor: string = '#FF005BB5';
  @Param hasCoverColor: boolean = false;

  // 事件回调
  @Param onSeek?: (value: number, mode: SliderChangeMode) => void = undefined;
  @Param onModeClick?: () => void = undefined;
  @Param onPrev?: () => void = undefined;
  @Param onPlayPause?: () => void = undefined;
  @Param onNext?: () => void = undefined;
  @Param onQueueClick?: () => void = undefined;

  // 控制栏自动隐藏逻辑
  @Local isControlsVisible: boolean = true;
  private hideTimerId: number = -1;

  // 进度条拖拽状态
  @Local localProgress: number = 0;
  @Local isDraggingProgress: boolean = false;

  @Monitor('currentProgress')
  onProgressChange() {
    // 非拖拽状态下，才接受外部进度的更新
    if (!this.isDraggingProgress) {
      this.localProgress = this.currentProgress;
    }
  }

  @Monitor('isPlaying')
  onPlayingChanged(): void {
    this.resetHideTimer()
  }

  aboutToAppear(): void {
    this.resetHideTimer();
    this.localProgress = this.currentProgress;
    WindowUtil.setSystemBarEnabled(false)
  }

  aboutToDisappear(): void {
    if (this.hideTimerId !== -1) {
      clearTimeout(this.hideTimerId);
    }
    WindowUtil.setSystemBarEnabled(true)
  }

  private isCompactLandscapePlayer(): boolean {
    const shortEdge = Math.min(this.windowProperties.winWidth, this.windowProperties.winHeight);
    return shortEdge > 0 && shortEdge < 600;
  }

  private resetHideTimer(): void {
    this.isControlsVisible = true;
    if (this.hideTimerId !== -1) {
      clearTimeout(this.hideTimerId);
    }
    // 播放状态下，3秒无操作自动隐藏控制栏
    if (this.isPlaying) {
      this.hideTimerId = setTimeout(() => {
        this.isControlsVisible = false;
        this.hideTimerId = -1;
      }, 3000);
    }
  }

  // --- 歌词动画计算逻辑 ---

  private lyricOffset(index: number): number {
    const d = index - this.activeLyricIndex;
    const baseOffset = 15; // 稍微下移，让视觉中心在横屏上更加舒适居中
    if (d === 0) return baseOffset;
    // 大幅增加上下句的避让间距，确保当前句即使折成3行也不会重叠
    if (d > 0) return baseOffset + 220 + (d - 1) * 90;
    return baseOffset - 220 + (d + 1) * 90;
  }

  private lyricOpacity(index: number): number {
    const d = index - this.activeLyricIndex;
    if (d === 0) return 1.0;
    if (d === 1) return 0.25;
    return 0.0;
  }

  private lyricScale(index: number): number {
    const d = index - this.activeLyricIndex;
    if (d === 0) {
      // 大幅强化律动系数：Bass 从 0.15 加大到 0.35，Level 从 0.1 加大到 0.25
      // 让基础状态下也有肉眼可见的大幅跳动感
      return 1.0 + (this.isPlaying ? (this.audioBass * 0.35 + this.audioLevel * 0.25) : 0);
    }
    return 0.75;
  }

  private lyricBlur(index: number): number {
    const d = index - this.activeLyricIndex;
    if (d === 0) return 0;
    if (d === 1) return 6;
    return 16;
  }

  private formatTime(ms: number): string {
    const safeMs = ms < 0 || isNaN(ms) ? 0 : ms;
    const totalSeconds = Math.floor(safeMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  // --- 核心构建块 ---

  // 恢复：光晕球律动背景 (更省性能，且呼吸感强)
  @Builder
  private buildAmbientBackground() {
    Stack({ alignContent: Alignment.Center }) {
      // 底色
      Column().width('100%').height('100%').backgroundColor(Color.Black)

      // 专辑封面背景底图放大极度模糊
      if (this.song?.album?.cover) {
        Image(cover(this.song.album.cover, 240))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(120)
          .opacity(0.3)
      }

      // 律动光晕 1：跟随 Bass 与 Mid
      Row()
        .width(this.windowProperties.winWidth * 0.9)
        .height(this.windowProperties.winWidth * 0.9)
        .borderRadius(9999)
        .backgroundColor(this.hasCoverColor ? this.gradientStartColor : '#402C2C2C')
        .opacity((this.isPlaying ? 0.24 : 0.18) + this.audioBass * 0.18)
        .blur(100)
        .position({
          x: -this.windowProperties.winWidth * 0.2 + this.audioMid * 24,
          y: -this.windowProperties.winHeight * 0.1 + this.audioBass * 16
        })
        .scale(this.isPlaying ? { x: 1.1 + this.audioBass * 0.14, y: 1.1 + this.audioBass * 0.14 } : { x: 1.0, y: 1.0 })
        .animation({ duration: 180, curve: Curve.EaseOut })

      // 律动光晕 2：跟随 Treble 与 Mid
      Row()
        .width(this.windowProperties.winWidth * 0.8)
        .height(this.windowProperties.winWidth * 0.8)
        .borderRadius(9999)
        .backgroundColor(this.hasCoverColor ? this.gradientEndColor : '#33202020')
        .opacity((this.isPlaying ? 0.2 : 0.14) + this.audioTreble * 0.2)
        .blur(120)
        .position({
          x: this.windowProperties.winWidth * 0.4 - this.audioTreble * 28,
          y: this.windowProperties.winHeight * 0.5 - this.audioMid * 22
        })
        .scale(this.isPlaying ? { x: 1.12 + this.audioTreble * 0.18, y: 1.12 + this.audioTreble * 0.18 } : { x: 1.0, y: 1.0 })
        .animation({ duration: 180, curve: Curve.EaseOut })

      // 律动光晕 3：主色调点缀跟随整体音量 (Level)
      Row()
        .width(this.windowProperties.winWidth * 0.56)
        .height(this.windowProperties.winWidth * 0.56)
        .borderRadius(9999)
        .backgroundColor(this.hasCoverColor ? this.mainColor : '#2A4A4A4A')
        .opacity(0.08 + this.audioLevel * 0.14)
        .blur(88)
        .scale({ x: 0.96 + this.audioLevel * 0.24, y: 0.96 + this.audioLevel * 0.24 })
        .animation({ duration: 180, curve: Curve.EaseOut })

      // 一层微弱的深色遮罩融合各个光晕，增加沉浸感
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#4D000000') // 30% 黑色遮罩，确保白色歌词清晰
        .backdropBlur(24) // 额外的背景毛玻璃效果
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None) // 必须设为None，避免阻挡控制栏唤出交互
  }

  @Builder
  private buildImmersiveLyrics() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.parsedLrc.lines.length === 0) {
        Text($r('app.string.now_playing_lyrics_placeholder'))
          .fontSize(24)
          .fontColor('#80FFFFFF');
      } else {
        ForEach(this.parsedLrc.lines, (line: LyricLine, index: number) => {
          if (Math.abs(index - this.activeLyricIndex) <= 2) {
            Text(line.text)
              .fontSize(this.isCompactLandscapePlayer() ? 44 : 52)
              .lineHeight(this.isCompactLandscapePlayer() ? 56 : 64)
              .fontWeight(FontWeight.Bolder)
              .fontFamily('HarmonyOS Sans')
              .fontColor(Color.White)
              .maxLines(3)
              .textAlign(TextAlign.Center)
              .opacity(this.lyricOpacity(index))
              .translate({ y: this.lyricOffset(index) })
              .blur(this.lyricBlur(index))
              .animation({ duration: 600, curve: curves.cubicBezierCurve(0.23, 1, 0.32, 1) })
              .scale({
                x: this.lyricScale(index),
                y: this.lyricScale(index),
                centerX: '50%',
                centerY: '50%'
              })
              .textShadow(index === this.activeLyricIndex ? {
                radius: 16 + (this.audioLevel * 32), // 将基础与增量下调，最大发光约 48
                color: '#B3FFFFFF',
                offsetX: 0,
                offsetY: 0
              } : undefined)
              .animation({ duration: 120, curve: Curve.EaseOut })
              .width('60%');
          }
        }, (line: LyricLine, index: number): string => index.toString())
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.isCompactLandscapePlayer() ? 28 : 48, right: this.isCompactLandscapePlayer() ? 28 : 48 })
  }

  @Builder
  private buildImmersiveControls() {
    Column({ space: this.isCompactLandscapePlayer() ? 18 : 24 }) {
      // 进度条层
      Row({ space: 16 }) {
        Text(this.formatTime(this.isDraggingProgress ? this.localProgress : this.currentProgress))
          .fontColor('#B3FFFFFF')
          .fontSize(this.isCompactLandscapePlayer() ? 12 : 14)
          .fontFamily('HarmonyOS Sans Numerics')
          .width(this.isCompactLandscapePlayer() ? 38 : 44)
          .textAlign(TextAlign.End)

        Slider({
          value: this.localProgress,
          min: 0,
          max: this.duration > 0 ? this.duration : 100,
          style: SliderStyle.OutSet
        })
          .blockColor(Color.White)
          .selectedColor(Color.White)
          .trackColor('#33FFFFFF')
          .trackThickness(this.isCompactLandscapePlayer() ? 3 : 4)
          .layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.resetHideTimer();
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
              this.isDraggingProgress = true;
              this.localProgress = value;
            } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.isDraggingProgress = false;
              this.localProgress = value;
              if (this.onSeek) {
                this.onSeek(value, mode);
              }
            }
          })

        Text('-' + this.formatTime(this.duration - (this.isDraggingProgress ? this.localProgress : this.currentProgress)))
          .fontColor('#B3FFFFFF')
          .fontSize(this.isCompactLandscapePlayer() ? 12 : 14)
          .fontFamily('HarmonyOS Sans Numerics')
          .width(this.isCompactLandscapePlayer() ? 38 : 44)
          .textAlign(TextAlign.Start)
      }
      .width(this.isCompactLandscapePlayer() ? '64%' : '70%')

      // 按钮控制层
      Row() {
        SymbolGlyph(this.modeSymbol)
          .fontSize(this.isCompactLandscapePlayer() ? 24 : 28)
          .fontColor(['#99FFFFFF'])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            this.resetHideTimer();
            this.onModeClick?.();
          })

        SymbolGlyph($r('sys.symbol.backward_end_fill'))
          .fontSize(this.isCompactLandscapePlayer() ? 32 : 40)
          .fontColor([Color.White])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            this.resetHideTimer();
            this.onPrev?.();
          })

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(this.isCompactLandscapePlayer() ? 36 : 44)
            .fontColor([Color.White])
            .margin({ left: this.isPlaying ? 0 : (this.isCompactLandscapePlayer() ? 4 : 6) });
        }
        .width(this.isCompactLandscapePlayer() ? 72 : 88)
        .height(this.isCompactLandscapePlayer() ? 72 : 88)
        .borderRadius(this.isCompactLandscapePlayer() ? 36 : 44)
        .backgroundColor('#1AFFFFFF')
        .backgroundBlurStyle(BlurStyle.Thin)
        .border({ width: 1, color: '#30FFFFFF' })
        .shadow({ radius: this.isCompactLandscapePlayer() ? 24 : 32, color: '#4D000000', offsetY: this.isCompactLandscapePlayer() ? 8 : 12 })
        .scale({
          x: 1 + (this.isPlaying ? this.audioLevel * 0.15 + this.audioBass * 0.1 : 0),
          y: 1 + (this.isPlaying ? this.audioLevel * 0.15 + this.audioBass * 0.1 : 0)
        })
        .animation({ duration: 120, curve: Curve.EaseOut })
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.9 })
        .onClick(() => {
          this.resetHideTimer();
          this.onPlayPause?.();
        })

        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(this.isCompactLandscapePlayer() ? 32 : 40)
          .fontColor([Color.White])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            this.resetHideTimer();
            this.onNext?.();
          })

        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(this.isCompactLandscapePlayer() ? 24 : 28)
          .fontColor(['#99FFFFFF'])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            this.resetHideTimer();
            this.onQueueClick?.();
          })
      }
      .width(this.isCompactLandscapePlayer() ? '54%' : '60%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      bottom: this.windowProperties.bottomRect + (this.isCompactLandscapePlayer() ? 20 : 32),
      top: this.isCompactLandscapePlayer() ? 36 : 64,
      left: this.isCompactLandscapePlayer() ? 20 : 32,
      right: this.isCompactLandscapePlayer() ? 20 : 32
    })
    // 仅保留底部的一点点渐变，用于确保控制按钮的对比度，不影响全局背景
    .linearGradient({
      direction: GradientDirection.Top,
      colors: [['#00000000', 0], ['#B3000000', 1.0]]
    })
    .opacity(this.isControlsVisible ? 1.0 : 0.0)
    .translate({ y: this.isControlsVisible ? 0 : (this.isCompactLandscapePlayer() ? 28 : 40) })
    .gesture(
      SwipeGesture({
        direction: SwipeDirection.Vertical,
      }).onAction((event) => {
        if (event.angle > 45 && event.angle < 145) {
          clearTimeout(this.hideTimerId);
          this.isControlsVisible = false
          this.hideTimerId = -1
        }
      })
    )
    .animation({ duration: 500, curve: Curve.EaseOut })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {

      // 全屏背景视觉系统 (在最底层)
      this.buildAmbientBackground()

      // 全屏沉浸式大歌词层
      this.buildImmersiveLyrics()

      // 悬浮的底部控制栏
      this.buildImmersiveControls()

    }
    .width('100%')
    .height('100%')
    .onTouch((event?: TouchEvent) => {
      if (event && event.type === TouchType.Down) {
        this.resetHideTimer();
      }
    })
  }
}