import { AppStorageV2, PersistenceV2 } from "@kit.ArkUI";
import { avSession } from "@kit.AVSessionKit";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import SettingViewModel from "../viewmodel/SettingViewModel";
import { PlayerCallbacks, playerManager } from "../services/PlayerManager";
import { avSessionManager } from "../services/AVSessionManager";
import { songPlayerManager } from "../services/SongPlayerManager";
import { WindowProperties } from "../model/WindowProperties";
import { BreakpointConstants } from "../common/BreakpointConstants";
import { ImageColorExtractor } from "../utils/ImageColorExtractor";
import { cover } from "../utils/Tools";
import { NowPlayingQueueSheet } from "./NowPlayingQueueSheet";
@ComponentV2
export struct PlayerCard {
  private subscriberId: string = 'PlayerCard_' + Date.now().toString() + '_' + Math.floor(Math.random() * 1000000).toString();
  @Local playlistViewModel: PlaylistViewModel = AppStorageV2.connect(
    PlaylistViewModel,
    "PlaylistViewModel",
    () => new PlaylistViewModel(),
  )!;

  @Local settingModel: SettingViewModel = PersistenceV2.connect(
    SettingViewModel,
    "SettingViewModel",
    () => new SettingViewModel(),
  )!;

  @Local windowProperties: WindowProperties = AppStorageV2.connect(
    WindowProperties,
    "WindowProperties",
    () => new WindowProperties(),
  )!;

  @Param cardHeight: number | string = "auto";
  @Param layoutMode: string = "horizontal";
  @Param coverSize: number = 0;

  /** 打开全屏 NowPlaying 弹窗（由父页面注入路由能力） */
  @Event onOpenNowPlaying: () => void = () => {};

  private transitionId(suffix: string): string {
    return 'np_shared' + suffix;
  }

  @Local isPlaying: boolean = false;
  @Local showQueueSheet: boolean = false;
  @Local currentProgress: number = 0;
  @Local duration: number = 0;

  @Local mainColor: string = "#FF007DFF";
  @Local gradientStartColor: string = "#FF3399FF";
  @Local gradientEndColor: string = "#FF005BB5";
  @Local colorExtracted: boolean = false;
  @Local hasCoverColor: boolean = false;

  private colorExtractRequestId: number = 0;
  private progressTimerId: number = -1;

  private resolveVerticalCoverSize(): number {
    const paddingX = 40;
    let fraction = 1.0;
    if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
      fraction = 0.3333;
    } else if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_MD) {
      fraction = 0.4;
    }
    const cardWidth = this.windowProperties.winWidth * fraction - paddingX;
    const minSize = 160;
    const maxSize = 240;
    const raw = Math.floor(cardWidth);
    return Math.min(maxSize, Math.max(minSize, raw));
  }

  @Computed
  get verticalCoverSize(): number {
    return this.coverSize > 0 ? this.coverSize : this.resolveVerticalCoverSize();
  }

  aboutToAppear(): void {
    this.extractMainColor();

    const callbacks: PlayerCallbacks = {
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

    playerManager.addSubscriber(this.subscriberId, callbacks);
    this.isPlaying = playerManager.isPlaying();
    this.duration = playerManager.getDuration();
    this.currentProgress = playerManager.getCurrentPosition();
    if (this.isPlaying) {
      this.startProgressTimer();
    }
  }

  @Computed
  get currentSongCover(): string | undefined {
    return this.playlistViewModel.currentSong?.album?.cover;
  }

  private async extractMainColor(): Promise<void> {
    const requestId = this.colorExtractRequestId + 1;
    this.colorExtractRequestId = requestId;

    if (!this.currentSongCover) {
      if (!this.hasCoverColor) {
        this.colorExtracted = true;
      }
      return;
    }
    try {
      const coverUrl = cover(this.currentSongCover, 100) as string;
      const dominantColors = await ImageColorExtractor.extractMultipleDominantColors(coverUrl, 100);

      if (requestId !== this.colorExtractRequestId) {
        return;
      }

      if (dominantColors.length > 0) {
        this.hasCoverColor = true;
        const colorsToMix =
          dominantColors.length > 1 ? [dominantColors[0], dominantColors[1]] : [dominantColors[0]];
        this.mainColor = ImageColorExtractor.mixColors(colorsToMix, 0.6);
        this.gradientStartColor = ImageColorExtractor.adjustColorBrightness(this.mainColor, 1.15);
        this.gradientEndColor = ImageColorExtractor.adjustColorBrightness(this.mainColor, 0.7);
      }
    } catch (error) {
      // 提色异常忽略
    } finally {
      if (requestId === this.colorExtractRequestId) {
        this.colorExtracted = true;
      }
    }
  }

  @Monitor("currentSongCover")
  onCurrentSongCoverChanged(): void {
    this.extractMainColor();
  }

  @Builder
  private buildBackgroundLayer() {
    Column()
      .width("100%")
      .height("100%")
      .linearGradient({
        angle: 135,
        colors: [
          [this.gradientStartColor, 0.0],
          [this.mainColor, 0.5],
          [this.gradientEndColor, 1.0],
        ],
      })
      .id("player-card-bg-colored")
      .transition(TransitionEffect.OPACITY)
      .geometryTransition(this.transitionId("-background"), { follow: true })
      .opacity(this.settingModel.opacityPlaylistGradient);
  }

  aboutToDisappear(): void {
    playerManager.removeSubscriber(this.subscriberId);
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
    const prevSong = this.playlistViewModel.prevSong(true);
    if (prevSong !== undefined) {
      this.playlistViewModel.playSong(prevSong, true);
    }
  }

  private playNext(): void {
    const nextSong = this.playlistViewModel.nextSong(true);
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
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
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
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.colorExtracted && this.hasCoverColor) {
        this.buildBackgroundLayer();
      } else {
        Column()
          .width("100%")
          .height("100%")
          .backgroundColor($r("app.color.playlist_card_background"))
          .id("player-card-bg-uncolored")
          .transition(TransitionEffect.OPACITY)
          .geometryTransition(this.transitionId("-background"), { follow: true });
      }

      if (this.layoutMode === "vertical") {
        Column() {
          if (this.playlistViewModel.currentSong) {
            Image(
              this.playlistViewModel.currentSong?.album?.cover
                ? cover(this.playlistViewModel.currentSong?.album?.cover, this.verticalCoverSize)
                : $r("sys.media.ohos_app_icon"),
            )
              .width(this.verticalCoverSize)
              .height(this.verticalCoverSize)
              .borderRadius(this.settingModel.radiusCard)
              .objectFit(ImageFit.Cover)
              .id("player-card-cover-vertical")
              .transition(TransitionEffect.OPACITY)
              .geometryTransition(this.transitionId("-cover"), { follow: true })
              .shadow({
                radius: 24,
                color: $r("app.color.cover_shadow_strong"),
                offsetX: 0,
                offsetY: 10,
              })
              .margin({ top: 32 })

          }
          Blank().layoutWeight(2)
          Column({ space: 8 }) {
            Text(this.playlistViewModel.currentSong?.name ?? $r("app.string.playlist_detail_title"))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.playlist_text_on_image"))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .width("100%")
            Text(
              this.playlistViewModel.currentSong?.artists?.map((artist) => artist.name).join("/") ??
                "",
            )
              .fontSize(14)
              .fontColor($r("app.color.playlist_text_secondary_on_image"))
              .opacity(this.settingModel.opacitySecondaryText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .width("100%")
          }
          .width("100%")
          .alignItems(HorizontalAlign.Start)
          .id("player-card-title-vertical")
          .transition(TransitionEffect.OPACITY)
          .geometryTransition(this.transitionId("-title"), { follow: true })
          Blank().layoutWeight(1)
          Column({ space: 4 }) {
            Slider({
              value: this.currentProgress,
              min: 0,
              max: this.duration > 0 ? this.duration : 100,
              style: SliderStyle.OutSet,
            })
              .blockColor(Color.White)
              .selectedColor(Color.White)
              .trackColor("#33ffffff")
              .trackThickness(4)
              .onChange((value: number, mode: SliderChangeMode) => this.onSliderChange(value, mode))
              .animation({ duration: 360, curve: Curve.EaseOut })
            Row() {
              Text(this.formatTime(this.currentProgress))
                .fontSize(12)
                .fontColor($r("app.color.playlist_text_secondary_on_image"))
              Text(this.formatTime(this.duration))
                .fontSize(12)
                .fontColor($r("app.color.playlist_text_secondary_on_image"))
            }
            .width("100%")
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: 8, right: 8, top: 2 })
          }
          .width("100%")
          .id("player-card-progress-vertical")
          .transition(TransitionEffect.OPACITY)
          Blank().layoutWeight(1)
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
            SymbolGlyph(this.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill"))
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
          .padding({ left: 4, right: 4, bottom: 28 })
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .id("player-card-controls-vertical")
          .transition(TransitionEffect.OPACITY)
        }
        .width("100%")
        .height("100%")
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24 });

      } else {
        Column() {
          Column({ space: 4 }) {
            Text(this.playlistViewModel.currentSong?.name ?? $r("app.string.playlist_detail_title"))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("app.color.playlist_text_on_image"))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .width("100%")
            Text(
              this.playlistViewModel.currentSong?.artists?.map((artist) => artist.name).join("/") ??
                "",
            )
              .fontSize(14)
              .fontColor($r("app.color.playlist_text_secondary_on_image"))
              .opacity(this.settingModel.opacitySecondaryText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
              .textAlign(TextAlign.Start)
              .width("100%")
          }
          .width("100%")
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 104, right: 20, top: 24 })
          .id("player-card-title")
          .transition(TransitionEffect.OPACITY)
          .geometryTransition(this.transitionId("-title"), { follow: true })
          Blank().layoutWeight(1)
          Column({ space: 4 }) {
            Slider({
              value: this.currentProgress,
              min: 0,
              max: this.duration > 0 ? this.duration : 100,
              style: SliderStyle.OutSet,
            })
              .blockColor(Color.White)
              .selectedColor(Color.White)
              .trackColor("#33ffffff")
              .trackThickness(4)
              .onChange((value: number, mode: SliderChangeMode) => this.onSliderChange(value, mode))
              .animation({ duration: 360, curve: Curve.EaseOut })
            Row() {
              Text(this.formatTime(this.currentProgress))
                .fontSize(12)
                .fontColor($r("app.color.playlist_text_secondary_on_image"))
              Text(this.formatTime(this.duration))
                .fontSize(12)
                .fontColor($r("app.color.playlist_text_secondary_on_image"))
            }
            .width("100%")
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: 8, right: 8, top: 2 })
          }
          .width("100%")
          .padding({ left: 20, right: 20 })
          .id("player-card-progress")
          .transition(TransitionEffect.OPACITY)
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
            SymbolGlyph(this.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill"))
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
          .padding({ left: 24, right: 24, bottom: 20 })
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .id("player-card-controls")
          .transition(TransitionEffect.OPACITY)
        }
        .width("100%")
        .height("100%");

        if (this.playlistViewModel.currentSong) {
          Image(
            this.playlistViewModel.currentSong?.album?.cover
              ? cover(this.playlistViewModel.currentSong?.album?.cover, 120)
              : $r("sys.media.ohos_app_icon"),
          )
            .width(72)
            .height(72)
            .borderRadius(this.settingModel.radiusCard)
            .objectFit(ImageFit.Cover)
            .id("player-card-cover")
            .transition(TransitionEffect.OPACITY)
            .geometryTransition(this.transitionId("-cover"), { follow: true })
            .margin({ left: 16, top: 16 })
            .shadow({
              radius: 24,
              color: $r("app.color.cover_shadow_strong"),
              offsetX: 0,
              offsetY: 10,
            })
            .onClick(() => {
              if (this.playlistViewModel.currentSong) {
                this.onOpenNowPlaying();
              }
            });
        }
      }
    }
    .width("100%")
    .height(this.cardHeight)
    .borderRadius(this.settingModel.radiusCardLarge)
    .clip(true)
    .onClick(() => {
      if (this.playlistViewModel.currentSong) {
        this.onOpenNowPlaying();
      }
    })
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
