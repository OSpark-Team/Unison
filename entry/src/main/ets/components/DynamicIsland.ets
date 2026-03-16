import { AppStorageV2, curves } from "@kit.ArkUI";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import { PlayerCallbacks, playerManager } from "../services/PlayerManager";
import { songPlayerManager } from "../services/SongPlayerManager";
import { resourceUtil } from "../utils/ResourceUtil";
import { avSession } from "@kit.AVSessionKit";
import { avSessionManager } from "../services/AVSessionManager";
import { NowPlayingQueueSheet } from "./NowPlayingQueueSheet";

/**
 * 歌曲灵动岛组件
 * * 动效进阶优化：
 * 1. 对应转场：胶囊态 Marquee 与 展开态 Text 建立位移/透明度联动，消除收缩时的闪烁。
 * 2. 共享元素：封面图在折叠/展开时保持平滑的尺寸和圆角过渡。
 * 3. 动态布局：无歌曲时移除封面占位，文案自适应。
 */
@ComponentV2
export struct DynamicIsland {
  /** 获取全局的播放列表 ViewModel */
  @Local playlistViewModel: PlaylistViewModel = AppStorageV2.connect(
    PlaylistViewModel,
    "PlaylistViewModel",
    () => new PlaylistViewModel(),
  )!;

  /** 控制灵动岛的展开与折叠状态 */
  @Param isExpanded: boolean = false;
  @Event $isExpanded: (val: boolean) => void = (val: boolean) => {};

  /** 打开全屏 NowPlaying 弹窗（由外部页面注入路由能力） */
  @Event onOpenNowPlaying: () => void = () => {};

  private transitionId(suffix: string): string {
    return 'np_shared' + suffix;
  }

  /** 当前播放状态 */
  @Local isPlaying: boolean = false;

  /** 控制播放列表 Sheet 展示 */
  @Local showQueueSheet: boolean = false;
  /** 当前播放进度 (毫秒) */
  @Local currentProgress: number = 0;
  /** 歌曲总时长 (毫秒) */
  @Local duration: number = 0;

  /** * 展开方向锚点
   * Alignment.TopStart: 固定左侧，向右舒展
   * Alignment.TopEnd: 固定右侧，向左舒展
   * Alignment.Top: 固定中间，向两侧舒展
   */
  @Param expandAlignment: Alignment = Alignment.Top;

  /** 灵动岛尺寸参数化 */
  @Param compWidthCollapsed: number = 180;
  @Param compWidthExpanded: number = 340;
  @Param compHeightCollapsed: number = 40;
  @Param compHeightExpanded: number = 220;

  /** 外部传入的间距控制 */
  @Param compMarginTop: number = 0;

  private progressTimerId: number = -1;

  aboutToAppear(): void {
    let callbacks: PlayerCallbacks = {
      onPlay: () => {
        this.isPlaying = true;
        this.startProgressTimer();
      },
      onPause: () => {
        this.isPlaying = false;
        this.stopProgressTimer();
      },
      onStop: () => {
        this.isPlaying = false;
        this.stopProgressTimer();
      },
      onDurationChange: (dur: number) => {
        this.duration = dur;
      },
      onSeek: (pos: number) => {
        this.currentProgress = pos;
      },
    };

    playerManager.addSubscriber("DynamicIslandComponent", callbacks);

    this.isPlaying = playerManager.isPlaying();
    this.duration = playerManager.getDuration();
    this.currentProgress = playerManager.getCurrentPosition();
    if (this.isPlaying) {
      this.startProgressTimer();
    }
  }

  aboutToDisappear(): void {
    playerManager.removeSubscriber("DynamicIslandComponent");
    this.stopProgressTimer();
  }

  private startProgressTimer(): void {
    if (this.progressTimerId === -1) {
      this.progressTimerId = setInterval(() => {
        this.currentProgress = playerManager.getCurrentPosition();
      }, 1000);
    }
  }

  private stopProgressTimer(): void {
    if (this.progressTimerId !== -1) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
    }
  }

  private playPrev(): void {
    let prevSong = this.playlistViewModel.prevSong(true);
    if (prevSong !== undefined) {
      this.playlistViewModel.playSong(prevSong, true);
    }
  }

  private playNext(): void {
    let nextSong = this.playlistViewModel.nextSong(true);
    if (nextSong !== undefined) {
      this.playlistViewModel.playSong(nextSong, true);
    }
  }

  private togglePlayPause(): void {
    if (this.isPlaying) {
      playerManager.pause();
    } else {
      songPlayerManager.playCurrentSongOrResume();
    }
  }

  private formatTime(ms: number): string {
    if (ms < 0 || isNaN(ms)) {
      return "00:00";
    }
    let totalSeconds = Math.floor(ms / 1000);
    let minutes = Math.floor(totalSeconds / 60);
    let seconds = totalSeconds % 60;
    return `${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
  }

  private onSliderChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      playerManager.seek(value);
      this.currentProgress = value;
    }
  }

  private mapModeResource(mode: avSession.LoopMode): Resource {
    switch (mode) {
      case avSession.LoopMode.LOOP_MODE_LIST:
        return $r("sys.symbol.repeat");
      case avSession.LoopMode.LOOP_MODE_SINGLE:
        return $r("sys.symbol.repeat_1");
      case avSession.LoopMode.LOOP_MODE_SHUFFLE:
        return $r("sys.symbol.shuffle");
      default:
        return $r("sys.symbol.repeat");
    }
  }

  @Builder
  private buildQueueSheet() {
    NowPlayingQueueSheet({
      songs: this.playlistViewModel.playlist,
      activeSong: this.playlistViewModel.currentSong,
      scrollToIndex: this.playlistViewModel.currentIndex,
      onSongClick: (song, index) => {
        this.playlistViewModel.playSongByIndex(index, true);
        this.showQueueSheet = false;
      },
      onClose: () => {
        this.showQueueSheet = false;
      },
    });
  }

  build() {
    Stack({ alignContent: this.expandAlignment }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          if (!this.isExpanded) {
            Row() {
              Marquee({
                start: this.isPlaying,
                step: 6,
                loop: -1,
                fromStart: true,
                src:
                  this.playlistViewModel.currentSong !== undefined
                    ? `${this.playlistViewModel.currentSong.name} - ${this.playlistViewModel.currentSong?.artists?.map((artist) => artist.name).join("/")}`
                    : resourceUtil.getString(
                        this.getUIContext().getHostContext(),
                        $r("app.string.not_playing"),
                      ),
              })
                .fontColor(Color.White)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .height(this.compHeightCollapsed)
                .layoutWeight(1)
                // 动态边距：无歌时不留左侧占位
                .margin({ left: this.playlistViewModel.currentSong ? 42 : 16, right: 16 })
            }
            .width("100%")
            .height("100%")
            .alignItems(VerticalAlign.Center)
            // 折叠态文字转场：与展开态文字位移呼应
            .transition(
              TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -20 })),
                TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 20 })),
              ).animation({ duration: 400, curve: Curve.EaseOut }),
            );
          }

          if (this.isExpanded) {
            Column() {
              Column() {
                Text(this.playlistViewModel.currentSong?.name ?? $r("app.string.unknown_song"))
                  .fontColor(Color.White)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(
                  this.playlistViewModel.currentSong?.artists
                    ?.map((artist) => artist.name)
                    .join("/"),
                )
                  .fontColor("#A0A0A0")
                  .fontSize(14)
                  .margin({ top: 4 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .width("100%")
              .padding({ left: 104, top: 24, right: 24 })
              .id("dynamic-island-title")
              .transition(TransitionEffect.OPACITY)
              .geometryTransition(this.transitionId("-title"), { follow: true })
              Blank()
              Column() {
                Slider({
                  value: this.currentProgress,
                  min: 0,
                  max: this.duration > 0 ? this.duration : 100,
                  style: SliderStyle.OutSet,
                })
                  .blockColor(Color.White)
                  .trackColor("#33ffffff")
                  .selectedColor(Color.White)
                  .trackThickness(4)
                  .onChange((value: number, mode: SliderChangeMode) =>
                    this.onSliderChange(value, mode),
                  )
                  .animation({ duration: 400, curve: Curve.EaseOut })
                Row() {
                  Text(this.formatTime(this.currentProgress))
                    .fontColor("#A0A0A0")
                    .fontSize(12)
                  Text(this.formatTime(this.duration))
                    .fontColor("#A0A0A0")
                    .fontSize(12)
                }
                .width("100%")
                .justifyContent(FlexAlign.SpaceBetween)
                .padding({ left: 8, right: 8, top: 4 })
              }
              .width("100%")
              .padding({ left: 16, right: 16 })
              .transition(TransitionEffect.OPACITY)
              .id("dynamic-island-progress")
              Row() {
                SymbolGlyph(this.mapModeResource(this.playlistViewModel.mode))
                  .fontSize(24)
                  .fontColor([Color.White])
                  .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                  .onClick(() => avSessionManager.syncLoopMode(this.playlistViewModel.setMode()))
                SymbolGlyph($r("sys.symbol.backward_end_fill"))
                  .fontSize(32)
                  .fontColor([Color.White])
                  .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                  .onClick(() => this.playPrev())
                SymbolGlyph(
                  this.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill"),
                )
                  .fontSize(48)
                  .fontColor([Color.White])
                  .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                  .onClick(() => this.togglePlayPause())
                SymbolGlyph($r("sys.symbol.forward_end_fill"))
                  .fontSize(32)
                  .fontColor([Color.White])
                  .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                  .onClick(() => this.playNext())
                SymbolGlyph($r("sys.symbol.list_bullet"))
                  .fontSize(24)
                  .fontColor([Color.White])
                  .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                  .onClick(() => {
                    this.showQueueSheet = true;
                  })
              }
              .width("100%")
              .padding({ left: 24, right: 24, bottom: 24 })
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .id("dynamic-island-controls")
              .transition(TransitionEffect.OPACITY)
            }
            .width("100%")
            .height("100%");
          }
        }
        .width("100%")
        .height("100%")
        .backgroundColor(Color.Black)
        .id("dynamic-island-root")
        .transition(TransitionEffect.OPACITY)
        .geometryTransition(this.transitionId("-background"), { follow: true })
        .opacity(0.9)
        .borderRadius(this.isExpanded ? 36 : 20)
        .clip(true)

        if (this.playlistViewModel.currentSong) {
          Image(this.playlistViewModel.currentSong?.album?.cover ?? $r("sys.media.ohos_app_icon"))
            .width(this.isExpanded ? 64 : 28)
            .height(this.isExpanded ? 64 : 28)
            .borderRadius(this.isExpanded ? 16 : 14)
            .objectFit(ImageFit.Cover)
            .id("dynamic-island-cover")
            .transition(TransitionEffect.OPACITY)
            .geometryTransition(this.transitionId("-cover"), { follow: true })
            .margin({
              left: this.isExpanded ? 24 : 6,
              top: this.isExpanded ? 24 : 6,
            });
        }
      }
      .width(this.isExpanded ? this.compWidthExpanded : this.compWidthCollapsed)
      .height(this.isExpanded ? this.compHeightExpanded : this.compHeightCollapsed)
      .animation({ duration: 500, curve: curves.interpolatingSpring(0, 1, 328, 36) })
      .onClick(() => {
        if (!this.playlistViewModel.currentSong) {
          return;
        }
        // 折叠态：先展开
        if (!this.isExpanded) {
          this.$isExpanded(true);
          return;
        }
        // 展开态：进入全屏 NowPlaying
        this.onOpenNowPlaying();
      }, 5)
    }
    .gesture(
      SwipeGesture({
        direction: SwipeDirection.Vertical,
      }).onAction((event) => {
        if (event.angle > 45 && event.angle < 145) {
          this.onOpenNowPlaying();
        }
        if (event.angle < -45 && event.angle > -145) {
          this.$isExpanded(false);
        }
      })
    )
    .margin({ top: this.compMarginTop })
    .bindSheet($$this.showQueueSheet, this.buildQueueSheet(), {
      height: SheetSize.MEDIUM,
      showClose: false,
      preferType: SheetType.CENTER,
      onWillDismiss: () => {
        this.showQueueSheet = false;
      },
    });
  }
}
