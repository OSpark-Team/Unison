import { AppStorageV2, curves, PersistenceV2 } from "@kit.ArkUI";
import { avSession } from "@kit.AVSessionKit";
import { LyricResponse } from "../adapter/omsp";
import { BreakpointConstants } from "../common/BreakpointConstants";
import { WindowProperties } from "../model/WindowProperties";
import { avSessionManager } from "../services/AVSessionManager";
import { PlayerCallbacks, playerManager } from "../services/PlayerManager";
import { AudioEffectsSheet } from "./AudioEffectsSheet";
import { NowPlayingQueueSheet } from "./NowPlayingQueueSheet";
import { SleepTimerSheet } from "./SleepTimerSheet";
import { cover } from "../utils/Tools";
import { AudioVisualizer, AudioVisualState } from "../utils/AudioVisualizer";
import { ImageColorExtractor } from "../utils/ImageColorExtractor";
import Logger from "../utils/Logger";
import LrcParser, { LyricLine, ParsedLrc } from "../utils/LrcParser";
import { MiniPlayerUiState } from "../model/MiniPlayerUiState";
import CurrentSourceViewModel from "../viewmodel/CurrentSourceViewModel";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import SettingViewModel from "../viewmodel/SettingViewModel";

const TAG: string = "MiniPlayerShell";
const BACK_KEY_CODE: number = 2000000;

export const MINI_PLAYER_RESERVED_HEIGHT: number = 96;
@ComponentV2
export struct MiniPlayerShell {
  @Consumer() pageInfos: NavPathStack = new NavPathStack();

  @Local playlistViewModel: PlaylistViewModel = AppStorageV2.connect(
    PlaylistViewModel,
    "PlaylistViewModel",
    () => new PlaylistViewModel(),
  )!;
  @Local currentSourceViewModel: CurrentSourceViewModel = AppStorageV2.connect(
    CurrentSourceViewModel,
    "CurrentSourceViewModel",
    () => new CurrentSourceViewModel(),
  )!;
  @Local windowProperties: WindowProperties = AppStorageV2.connect(
    WindowProperties,
    "WindowProperties",
    () => new WindowProperties(),
  )!;
  @Local settingModel: SettingViewModel = PersistenceV2.connect(
    SettingViewModel,
    "SettingViewModel",
    () => new SettingViewModel(),
  )!;
  @Local miniPlayerUiState: MiniPlayerUiState = AppStorageV2.connect(
    MiniPlayerUiState,
    "MiniPlayerUiState",
    () => new MiniPlayerUiState(),
  )!;

  @Param visible: boolean = true;
  @Param bottomOffset: number = 0;

  @Local isExpanded: boolean = false;
  @Local isPlaying: boolean = false;
  @Local currentProgress: number = 0;
  @Local duration: number = 0;
  @Local showSheet: boolean = false;
  @Local sheetType: string = "";
  @Local activeTabIndex: number = 0;
  @Local isClosing: boolean = false;
  @Local lastBreakpoint: string = "";
  @Local localProgress: number = 0;
  @Local isDraggingProgress: boolean = false;
  @Local parsedLrc: ParsedLrc = new ParsedLrc([], []);
  @Local activeLyricIndex: number = 0;
  @Local lyricTranslateY: number = 0;
  @Local lyricContainerHeight: number = 0;
  @Local isInitialLoaded: boolean = false;
  @Local isLyricDragging: boolean = false;
  @Local lyricDragOffsetY: number = 0;
  @Local showLyricTimeBubble: boolean = false;
  @Local lyricTimeBubbleText: string = "";
  @Local lyricTouchStartY: number = 0;
  @Local mainColor: string = "#FF007DFF";
  @Local gradientStartColor: string = "#FF3399FF";
  @Local gradientEndColor: string = "#FF005BB5";
  @Local colorExtracted: boolean = false;
  @Local hasCoverColor: boolean = false;
  @Local audioLevel: number = 0;
  @Local audioBass: number = 0;
  @Local audioMid: number = 0;
  @Local audioTreble: number = 0;
  @Local isTopBarVisible: boolean = true;

  private subscriberId: string =
    "MiniPlayerShell_" +
    Date.now().toString() +
    "_" +
    Math.floor(Math.random() * 1000000).toString();
  private colorExtractRequestId: number = 0;
  private progressTimerId: number = -1;
  private topBarHideTimerId: number = -1;
  private lyricYPositions: number[] = [];
  private estimatedDragLineHeight: number = 56;
  private audioVisualState: AudioVisualState = new AudioVisualState();
  private springCurve = curves.cubicBezierCurve(0.23, 1, 0.32, 1);
  private isPlayerBound: boolean = false;

  aboutToAppear(): void {
    this.activatePlayerBinding();
    this.lastBreakpoint = this.windowProperties.currentBreakpoint;
    this.startTopBarTimer();
  }

  aboutToDisappear(): void {
    this.deactivatePlayerBinding();
    this.clearTopBarTimer();
    this.resetShellState();
  }

  @Monitor("visible")
  onVisibleChanged(): void {
    if (!this.visible) {
      this.clearTopBarTimer();
      if (!this.miniPlayerUiState.resumeExpandedAfterLandscape) {
        this.resetShellState();
      }
      return;
    }
    if (this.miniPlayerUiState.resumeExpandedAfterLandscape) {
      this.isClosing = false;
      this.isExpanded = this.miniPlayerUiState.isExpanded;
      this.miniPlayerUiState.resumeExpandedAfterLandscape = false;
      if (this.isExpanded) {
        this.startTopBarTimer();
      }
    }
  }

  @Monitor("miniPlayerUiState.collapseRequestVersion")
  onCollapseRequestChanged(): void {
    if (this.isExpandedForRender()) {
      this.handleClose();
    }
  }

  @Monitor("playlistViewModel.currentSong")
  onCurrentSongChanged(): void {
    if (!this.playlistViewModel.currentSong) {
      this.resetShellState();
      this.parsedLrc = new ParsedLrc([], []);
      this.activeLyricIndex = 0;
      return;
    }
    this.currentProgress = playerManager.getCurrentPosition();
    this.localProgress = this.currentProgress;
    this.duration = playerManager.getDuration();
    this.extractMainColor();
    this.loadLyricsForCurrentSong();
  }

  @Monitor("windowProperties.currentBreakpoint")
  onBreakpointChanged(): void {
    const current = this.windowProperties.currentBreakpoint;
    if (current === this.lastBreakpoint) {
      return;
    }
    if (current === BreakpointConstants.BREAKPOINT_SM) {
      this.activeTabIndex = 0;
    }
    this.lastBreakpoint = current;
  }

  @Monitor("currentProgress")
  onProgressChange(): void {
    if (!this.isDraggingProgress) {
      this.localProgress = this.currentProgress;
    }
  }

  @Monitor("activeLyricIndex", "lyricContainerHeight")
  onLyricStateChange(): void {
    this.updateLyricTranslate();
  }

  private activatePlayerBinding(): void {
    if (this.isPlayerBound) {
      this.isPlaying = playerManager.isPlaying();
      this.duration = playerManager.getDuration();
      this.currentProgress = playerManager.getCurrentPosition();
      this.localProgress = this.currentProgress;
      return;
    }

    const callbacks: PlayerCallbacks = {
      onPlay: () => {
        this.isPlaying = true;
        this.startProgressTimer();
      },
      onPause: () => {
        this.isPlaying = false;
        this.stopProgressTimer();
        this.resetAudioReactiveState();
      },
      onStop: () => {
        this.isPlaying = false;
        this.stopProgressTimer();
        this.resetAudioReactiveState();
      },
      onDurationChange: (dur: number) => {
        this.duration = dur;
        this.extractMainColor();
        this.loadLyricsForCurrentSong();
      },
      onSeek: (pos: number) => {
        this.currentProgress = pos;
      },
      onPcmData: (data: ArrayBuffer) => {
        this.updateAudioReactiveState(data);
      },
    };

    playerManager.addSubscriber(this.subscriberId, callbacks);
    this.isPlayerBound = true;
    this.isPlaying = playerManager.isPlaying();
    this.duration = playerManager.getDuration();
    this.currentProgress = playerManager.getCurrentPosition();
    this.localProgress = this.currentProgress;
    if (this.isPlaying) {
      this.startProgressTimer();
    }
    this.extractMainColor();
    this.loadLyricsForCurrentSong();
  }

  private deactivatePlayerBinding(): void {
    if (this.isPlayerBound) {
      playerManager.removeSubscriber(this.subscriberId);
      this.isPlayerBound = false;
    }
    this.stopProgressTimer();
    this.resetAudioReactiveState();
  }

  private resetShellState(): void {
    this.showSheet = false;
    this.isExpanded = false;
    this.isClosing = false;
    this.activeTabIndex = 0;
    this.isTopBarVisible = true;
    this.miniPlayerUiState.isExpanded = false;
    this.miniPlayerUiState.resumeExpandedAfterLandscape = false;
  }

  private expandNowPlaying(): void {
    if (!this.playlistViewModel.currentSong) {
      return;
    }
    this.isClosing = false;
    this.isExpanded = true;
    this.miniPlayerUiState.isExpanded = true;
    this.startTopBarTimer();
  }

  private collapseNowPlaying(): void {
    this.resetShellState();
    this.startTopBarTimer();
  }

  private shouldRestoreExpandedImmediately(): boolean {
    return this.visible &&
      this.miniPlayerUiState.resumeExpandedAfterLandscape &&
      this.miniPlayerUiState.isExpanded;
  }

  private isExpandedForRender(): boolean {
    return this.isExpanded || this.shouldRestoreExpandedImmediately();
  }

  private handleClose(): void {
    if (this.isClosing || !this.isExpandedForRender()) {
      return;
    }
    this.isExpanded = true;
    this.isClosing = true;
    this.getUIContext()?.animateTo({ duration: 450, curve: this.springCurve }, () => {
      this.collapseNowPlaying();
    });
  }

  private openLandscapePage(): void {
    if (!this.playlistViewModel.currentSong || !this.isExpanded) {
      return;
    }
    this.clearTopBarTimer();
    this.isClosing = false;
    this.miniPlayerUiState.nowPlayingLandscapeActive = true;
    this.miniPlayerUiState.resumeExpandedAfterLandscape = true;
    this.pageInfos.pushPathByName("NowPlayingLandscape", null, false);
  }

  private startTopBarTimer(): void {
    if (this.topBarHideTimerId !== -1) {
      clearTimeout(this.topBarHideTimerId);
    }
    this.isTopBarVisible = true;
    this.topBarHideTimerId = setTimeout(() => {
      this.isTopBarVisible = false;
      this.topBarHideTimerId = -1;
    }, 3500);
  }

  private clearTopBarTimer(): void {
    if (this.topBarHideTimerId !== -1) {
      clearTimeout(this.topBarHideTimerId);
      this.topBarHideTimerId = -1;
    }
  }

  private resetAudioReactiveState(): void {
    this.audioVisualState = new AudioVisualState();
    this.audioLevel = 0;
    this.audioBass = 0;
    this.audioMid = 0;
    this.audioTreble = 0;
  }

  private updateAudioReactiveState(data: ArrayBuffer): void {
    this.audioVisualState = AudioVisualizer.analyze(data, this.audioVisualState);
    this.audioLevel = this.audioVisualState.level;
    this.audioBass = this.audioVisualState.bass;
    this.audioMid = this.audioVisualState.mid;
    this.audioTreble = this.audioVisualState.treble;
  }

  private getCurrentSongCover(): string {
    const song = this.playlistViewModel.currentSong;
    if (song && song.album && song.album.cover) {
      return song.album.cover;
    }
    return "";
  }

  @Computed
  get coverSize(): number {
    const size = this.windowProperties.winWidth * 0.72;
    return Math.min(320, Math.max(220, Math.floor(size)));
  }

  private async loadLyricsForCurrentSong(): Promise<void> {
    this.isInitialLoaded = false;
    this.parsedLrc = new ParsedLrc([], []);
    this.activeLyricIndex = 0;
    this.lyricYPositions = [];
    const songId = this.playlistViewModel.currentSong?.id;
    const source = this.currentSourceViewModel.source;
    if (!songId || !source) {
      this.isInitialLoaded = true;
      return;
    }
    try {
      const resp: LyricResponse = await source.getLyric(songId);
      const lrcText: string = resp.lyric?.normal ?? "";
      this.parsedLrc = LrcParser.parse(lrcText);
      this.updateActiveLyricByProgress(this.currentProgress);
    } catch (error) {
      Logger.warn(TAG, `loadLyricsForCurrentSong failed: ${error}`);
    } finally {
      setTimeout(() => {
        this.isInitialLoaded = true;
      }, 100);
    }
  }

  private updateActiveLyricByProgress(progressMs: number): void {
    const cues = this.parsedLrc.cues;
    if (cues.length === 0) {
      this.activeLyricIndex = 0;
      return;
    }
    let lo = 0;
    let hi = cues.length - 1;
    let best = 0;
    while (lo <= hi) {
      const mid = Math.floor((lo + hi) / 2);
      if (cues[mid].timeMs <= progressMs) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    const lineIndex = cues[best].lineIndex;
    if (lineIndex !== this.activeLyricIndex) {
      this.activeLyricIndex = lineIndex;
    }
  }

  private updateLyricTranslate(): void {
    if (this.lyricContainerHeight === 0 || this.parsedLrc.lines.length === 0) {
      return;
    }
    let centerY = this.lyricYPositions[this.activeLyricIndex];
    if (centerY === undefined) {
      centerY =
        this.activeLyricIndex * this.estimatedDragLineHeight + this.estimatedDragLineHeight / 2;
    }
    this.lyricTranslateY = this.lyricContainerHeight / 2 - centerY;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value));
  }

  private lyricLineDistance(index: number): number {
    return index - this.activeLyricIndex;
  }

  private lyricLineScale(index: number): number {
    const distance = Math.abs(this.lyricLineDistance(index));
    if (distance === 0) {
      return 1;
    }
    return this.clamp(0.85 - distance * 0.05, 0.7, 0.85);
  }

  private lyricLineOpacity(index: number): number {
    const distance = this.lyricLineDistance(index);
    const absDistance = Math.abs(distance);
    if (absDistance === 0) {
      return 1;
    }
    const base = distance < 0 ? 0.35 : 0.5;
    return this.clamp(base - absDistance * 0.1, 0, 1);
  }

  private lyricLineBlur(index: number): number {
    const absDistance = Math.abs(this.lyricLineDistance(index));
    if (absDistance === 0) {
      return 0;
    }
    return this.clamp(absDistance * 1.5, 0, 6);
  }

  private findCueTimeForLine(lineIndex: number): number {
    const cues = this.parsedLrc.cues;
    for (let i = 0; i < cues.length; i++) {
      if (cues[i].lineIndex === lineIndex) {
        return cues[i].timeMs;
      }
    }
    return -1;
  }

  private seekToLyricLine(lineIndex: number): void {
    const timeMs = this.findCueTimeForLine(lineIndex);
    if (timeMs >= 0) {
      playerManager.seek(timeMs);
      this.currentProgress = timeMs;
      this.updateActiveLyricByProgress(timeMs);
    }
  }

  private async extractMainColor(): Promise<void> {
    const requestId = this.colorExtractRequestId + 1;
    this.colorExtractRequestId = requestId;
    const currentSongCover = this.getCurrentSongCover();
    if (!currentSongCover) {
      this.hasCoverColor = false;
      this.colorExtracted = true;
      return;
    }
    try {
      const coverUrl = cover(currentSongCover, 120) as string;
      const dominantColors = await ImageColorExtractor.extractMultipleDominantColors(coverUrl, 100);
      if (requestId !== this.colorExtractRequestId) {
        return;
      }
      if (dominantColors.length > 0) {
        this.hasCoverColor = true;
        const colorsToMix =
          dominantColors.length > 1 ? [dominantColors[0], dominantColors[1]] : [dominantColors[0]];
        this.mainColor = ImageColorExtractor.mixColors(colorsToMix, 0.6);
        this.gradientStartColor = ImageColorExtractor.adjustColorBrightness(this.mainColor, 1.2);
        this.gradientEndColor = ImageColorExtractor.adjustColorBrightness(this.mainColor, 0.6);
      } else {
        this.hasCoverColor = false;
      }
    } catch (error) {
      this.hasCoverColor = false;
    } finally {
      if (requestId === this.colorExtractRequestId) {
        this.colorExtracted = true;
      }
    }
  }

  private startProgressTimer(): void {
    if (this.progressTimerId === -1) {
      this.progressTimerId = setInterval(() => {
        this.currentProgress = playerManager.getCurrentPosition();
        this.updateActiveLyricByProgress(this.currentProgress);
      }, 150);
    }
  }

  private stopProgressTimer(): void {
    if (this.progressTimerId !== -1) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
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

  private togglePlayPause(): void {
    if (this.isPlaying) {
      playerManager.pause();
      return;
    }
    playerManager.play();
  }

  private playPrev(): void {
    const prevSong = this.playlistViewModel.prevSong(true);
    if (prevSong) {
      this.playlistViewModel.playSong(prevSong, true);
    }
  }

  private playNext(): void {
    const nextSong = this.playlistViewModel.nextSong(true);
    if (nextSong) {
      this.playlistViewModel.playSong(nextSong, true);
    }
  }

  private toggleLoopMode(): void {
    const mode = this.playlistViewModel.setMode();
    avSessionManager.syncLoopMode(mode);
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

  private openSheet(type: string): void {
    this.showSheet = false;
    this.sheetType = type;
    this.showSheet = true;
  }

  private closeSheet(): void {
    this.showSheet = false;
  }

  private getShellHeight(): number | string {
    if (!this.visible || !this.playlistViewModel.currentSong) {
      return 0;
    }
    if (this.isExpandedForRender()) {
      return "100%";
    }
    return MINI_PLAYER_RESERVED_HEIGHT + this.bottomOffset;
  }

  @Builder
  private buildQueueSheet() {
    NowPlayingQueueSheet({
      songs: this.playlistViewModel.playlist,
      activeSong: this.playlistViewModel.currentSong,
      scrollToIndex: this.playlistViewModel.currentIndex,
      onSongClick: (song, index) => {
        this.playlistViewModel.playSongByIndex(index, true);
        this.closeSheet();
      },
      onClose: () => {
        this.closeSheet();
      },
    });
  }

  @Builder
  private buildAudioEffectsSheet() {
    AudioEffectsSheet({
      onClose: () => {
        this.closeSheet();
      },
    });
  }

  @Builder
  private buildSleepTimerSheet() {
    SleepTimerSheet({
      onClose: () => {
        this.closeSheet();
      },
    });
  }

  @Builder
  private buildDynamicSheet() {
    if (this.sheetType === "queue") {
      this.buildQueueSheet();
    } else if (this.sheetType === "audioEffects") {
      this.buildAudioEffectsSheet();
    } else if (this.sheetType === "sleepTimer") {
      this.buildSleepTimerSheet();
    } else {
      Column()
        .width("100%")
        .height("100%");
    }
  }

  @Builder
  private buildMiniPlayerContent() {
    Row({ space: 12 }) {
      Image(
        this.playlistViewModel.currentSong?.album?.cover
          ? cover(this.playlistViewModel.currentSong?.album?.cover, 96)
          : $r("sys.media.ohos_app_icon"),
      )
        .width(44)
        .height(44)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .shadow({ radius: 6, color: "#33000000", offsetY: 2 })
      Column({ space: 2 }) {
        Text(this.playlistViewModel.currentSong?.name ?? $r("app.string.not_playing"))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r("app.color.text_primary"))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(
          this.playlistViewModel.currentSong?.artists?.map((artist) => artist.name).join("/") ?? "",
        )
          .fontSize(13)
          .fontColor($r("app.color.text_secondary"))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph(this.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill"))
          .fontSize(24)
          .fontColor([$r("app.color.text_primary")])
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .onClick(() => {
        this.togglePlayPause();
      })
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r("sys.symbol.forward_end_fill"))
          .fontSize(24)
          .fontColor([$r("app.color.text_primary")])
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .onClick(() => {
        this.playNext();
      })
    }
    .width("100%")
    .height("100%")
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 })),
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 })),
      ).animation({ duration: 260, curve: Curve.EaseOut }),
    );
  }

  @Builder
  private buildTopBar() {
    Row({ space: 12 }) {
      Blank()
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r("sys.symbol.more"))
          .fontSize(26)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .backgroundColor("#1AFFFFFF")
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .bindMenu([
        {
          value: $r("app.string.now_playing_landscape_mode"),
          action: () => {
            this.openLandscapePage();
          },
        },
        {
          value: $r("app.string.audio_effects_title"),
          action: () => {
            this.openSheet("audioEffects");
          },
        },
        {
          value: $r("app.string.sleep_timer_title"),
          action: () => {
            this.openSheet("sleepTimer");
          },
        },
      ])
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r("sys.symbol.chevron_down"))
          .fontSize(26)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .backgroundColor("#1AFFFFFF")
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .onClick(() => {
        this.handleClose();
      })
    }
    .width("100%")
    .padding({ left: 24, right: 24, top: this.windowProperties.topRect + 16, bottom: 8 })
    .position({ x: 0, y: 0 })
    .zIndex(10)
    .opacity(this.isTopBarVisible ? 1 : 0)
    .translate({ y: this.isTopBarVisible ? 0 : -20 })
    .animation({ duration: 400, curve: Curve.EaseOut });
  }

  @Builder
  private buildAmbientBackground() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width("100%")
        .height("100%")
        .backgroundColor(Color.Black)

      if (this.playlistViewModel.currentSong?.album?.cover) {
        Image(cover(this.playlistViewModel.currentSong?.album?.cover, 240))
          .width("100%")
          .height("100%")
          .objectFit(ImageFit.Cover)
          .blur(100)
          .opacity(this.isClosing ? 0 : 0.3);
      }
      Row()
        .width(this.windowProperties.winWidth * 0.9)
        .height(this.windowProperties.winWidth * 0.9)
        .borderRadius(9999)
        .backgroundColor(
          this.colorExtracted && this.hasCoverColor ? this.gradientStartColor : "#402C2C2C",
        )
        .opacity(this.isClosing ? 0 : (this.isPlaying ? 0.24 : 0.18) + this.audioBass * 0.18)
        .blur(100)
        .position({
          x: -this.windowProperties.winWidth * 0.2 + this.audioMid * 24,
          y: -this.windowProperties.winHeight * 0.1 + this.audioBass * 16,
        })
        .scale(
          this.isPlaying
            ? { x: 1.1 + this.audioBass * 0.14, y: 1.1 + this.audioBass * 0.14 }
            : { x: 1.0, y: 1.0 },
        )
        .animation({ duration: 180, curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.animation({ duration: 800, curve: Curve.EaseOut }))
      Row()
        .width(this.windowProperties.winWidth * 0.8)
        .height(this.windowProperties.winWidth * 0.8)
        .borderRadius(9999)
        .backgroundColor(
          this.colorExtracted && this.hasCoverColor ? this.gradientEndColor : "#33202020",
        )
        .opacity(this.isClosing ? 0 : (this.isPlaying ? 0.2 : 0.14) + this.audioTreble * 0.2)
        .blur(120)
        .position({
          x: this.windowProperties.winWidth * 0.4 - this.audioTreble * 28,
          y: this.windowProperties.winHeight * 0.5 - this.audioMid * 22,
        })
        .scale(
          this.isPlaying
            ? { x: 1.12 + this.audioTreble * 0.18, y: 1.12 + this.audioTreble * 0.18 }
            : { x: 1.0, y: 1.0 },
        )
        .animation({ duration: 180, curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.animation({ duration: 800, curve: Curve.EaseOut }))
      Row()
        .width(this.windowProperties.winWidth * 0.56)
        .height(this.windowProperties.winWidth * 0.56)
        .borderRadius(9999)
        .backgroundColor(this.colorExtracted && this.hasCoverColor ? this.mainColor : "#2A4A4A4A")
        .opacity(this.isClosing ? 0 : 0.08 + this.audioLevel * 0.14)
        .blur(88)
        .scale({ x: 0.96 + this.audioLevel * 0.24, y: 0.96 + this.audioLevel * 0.24 })
        .animation({ duration: 180, curve: Curve.EaseOut })
      Column()
        .width("100%")
        .height("100%")
        .backgroundColor("#33000000")
        .backdropBlur(24)
        .transition(TransitionEffect.OPACITY)
    }
    .width("100%")
    .height("100%");
  }

  @Builder
  private buildPlayerPanel() {
    Column() {
      Blank()
        .layoutWeight(
          this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 1.2 : 1,
        )

      if (this.playlistViewModel.currentSong) {
        Image(
          this.playlistViewModel.currentSong?.album?.cover
            ? cover(this.playlistViewModel.currentSong?.album?.cover, this.coverSize)
            : $r("sys.media.ohos_app_icon"),
        )
          .width(this.coverSize)
          .height(this.coverSize)
          .borderRadius(this.settingModel.radiusCardLarge)
          .objectFit(ImageFit.Cover)
          .transition(TransitionEffect.OPACITY)
          .shadow({ radius: 36, color: "#66000000", offsetX: 0, offsetY: 18 })
          .scale(this.isPlaying ? { x: 1.0, y: 1.0 } : { x: 0.94, y: 0.94 })
          .animation({ duration: 900, curve: this.springCurve });
      }
      Blank()
        .height(
          this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 56 : 64,
        )
      Column({ space: 24 }) {
        Column({ space: 8 }) {
          Text(this.playlistViewModel.currentSong?.name ?? $r("app.string.not_playing"))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .textAlign(TextAlign.Start)
          Text(
            this.playlistViewModel.currentSong?.artists?.map((artist) => artist.name).join("/") ??
              "",
          )
            .fontSize(18)
            .fontColor("#B3FFFFFF")
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
        }
        .width("100%")
        .alignItems(HorizontalAlign.Start)
        .transition(TransitionEffect.OPACITY)
        Column({ space: 24 }) {
          Column({ space: 6 }) {
            Slider({
              value: this.localProgress,
              min: 0,
              max: this.duration > 0 ? this.duration : 100,
              style: SliderStyle.OutSet,
            })
              .blockColor(Color.White)
              .selectedColor(Color.White)
              .trackColor("#33FFFFFF")
              .trackThickness(4)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.startTopBarTimer();
                if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                  this.isDraggingProgress = true;
                  this.localProgress = value;
                } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.isDraggingProgress = false;
                  this.localProgress = value;
                  playerManager.seek(value);
                  this.currentProgress = value;
                }
              })
            Row() {
              Text(
                this.formatTime(
                  this.isDraggingProgress ? this.localProgress : this.currentProgress,
                ),
              )
                .fontColor("#80FFFFFF")
                .fontSize(12)
                .fontFamily("Medium")
              Text(this.formatTime(this.duration))
                .fontColor("#80FFFFFF")
                .fontSize(12)
                .fontFamily("Medium")
            }
            .width("100%")
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width("100%")
          .transition(TransitionEffect.OPACITY)
          Row() {
            SymbolGlyph(
              this.playlistViewModel.mode === avSession.LoopMode.LOOP_MODE_SHUFFLE
                ? $r("sys.symbol.shuffle")
                : this.mapModeResource(this.playlistViewModel.mode),
            )
              .fontSize(24)
              .fontColor(["#99FFFFFF"])
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
              .onClick(() => {
                this.toggleLoopMode();
              })
            SymbolGlyph($r("sys.symbol.backward_end_fill"))
              .fontSize(36)
              .fontColor([Color.White])
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
              .onClick(() => {
                this.playPrev();
              })
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph(this.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill"))
                .fontSize(36)
                .fontColor([Color.White])
                .margin({ left: this.isPlaying ? 0 : 4 })
            }
            .width(80)
            .height(80)
            .borderRadius(40)
            .backgroundColor("#1AFFFFFF")
            .backgroundBlurStyle(BlurStyle.Thin)
            .border({ width: 1, color: "#26FFFFFF" })
            .shadow({ radius: 24, color: "#33000000", offsetY: 12 })
            .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.9 })
            .onClick(() => {
              this.togglePlayPause();
            })
            SymbolGlyph($r("sys.symbol.forward_end_fill"))
              .fontSize(36)
              .fontColor([Color.White])
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
              .onClick(() => {
                this.playNext();
              })
            SymbolGlyph($r("sys.symbol.list_bullet"))
              .fontSize(24)
              .fontColor(["#99FFFFFF"])
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
              .onClick(() => {
                this.openSheet("queue");
              })
          }
          .width("100%")
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .transition(TransitionEffect.OPACITY)
        }
      }.width("100%")
      Blank()
        .layoutWeight(
          this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 0.8 : 1,
        )
    }
    .width("100%")
    .height("100%")
    .justifyContent(FlexAlign.Center)
    .padding({
      left: 32,
      right: 32,
      bottom:
        this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 24 : 0,
    });
  }

  @Builder
  private buildLyricsPanel() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.parsedLrc.lines.length === 0) {
        Column() {
          Text($r("app.string.now_playing_lyrics_placeholder"))
            .fontSize(18)
            .fontColor("#80FFFFFF")
        }
        .width("100%")
        .height("100%")
        .justifyContent(FlexAlign.Center);
      } else {
        Stack({ alignContent: Alignment.Top }) {
          Column() {
            ForEach(
              this.parsedLrc.lines,
              (line: LyricLine, index: number) => {
                Row() {
                  Text(line.text)
                    .fontSize(28)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .textAlign(TextAlign.Start)
                    .maxLines(5)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textShadow(
                      this.activeLyricIndex === index
                        ? { radius: 16, color: "#4DFFFFFF", offsetX: 0, offsetY: 0 }
                        : undefined,
                    )
                    .animation({ duration: 500, curve: this.springCurve })
                }
                .width("100%")
                .alignItems(VerticalAlign.Center)
                .padding({ top: 12, bottom: 12 })
                .onAreaChange((oldValue, newValue) => {
                  const y = newValue.position.y as number;
                  const height = newValue.height as number;
                  this.lyricYPositions[index] = y + height / 2;
                  if (index === this.activeLyricIndex) {
                    this.updateLyricTranslate();
                  }
                })
                .opacity(this.lyricLineOpacity(index))
                .scale({
                  x: this.lyricLineScale(index),
                  y: this.lyricLineScale(index),
                  centerX: 0,
                  centerY: "50%",
                })
                .blur(this.lyricLineBlur(index))
                .animation({ duration: 600, curve: this.springCurve })
                .onClick(() => {
                  this.seekToLyricLine(index);
                });
              },
              (line: LyricLine, index: number) => index.toString(),
            )
          }
          .width("100%")
          .padding({ left: 32, right: 32 })
          .translate({
            y: this.lyricTranslateY + (this.isLyricDragging ? this.lyricDragOffsetY : 0),
          })
          .animation({
            duration: this.isLyricDragging || !this.isInitialLoaded ? 0 : 700,
            curve: this.springCurve,
          })
        }
        .width("100%")
        .height("100%")
        .onAreaChange((oldValue, newValue) => {
          this.lyricContainerHeight = newValue.height as number;
        })
        .onTouch((event?: TouchEvent) => {
          if (!event) {
            return;
          }
          if (event.type === TouchType.Down) {
            this.isLyricDragging = true;
            this.showLyricTimeBubble = true;
            this.lyricDragOffsetY = 0;
            this.lyricTouchStartY = event.touches[0].y;
          }
          if (event.type === TouchType.Move) {
            const deltaY = event.touches[0].y - this.lyricTouchStartY;
            this.lyricDragOffsetY = deltaY;
            const offsetLines = Math.round(-this.lyricDragOffsetY / this.estimatedDragLineHeight);
            const previewIndex = this.clamp(
              this.activeLyricIndex + offsetLines,
              0,
              this.parsedLrc.lines.length - 1,
            );
            const cueTime = this.findCueTimeForLine(previewIndex);
            this.lyricTimeBubbleText = cueTime >= 0 ? this.formatTime(cueTime) : "";
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            const offsetLines = Math.round(-this.lyricDragOffsetY / this.estimatedDragLineHeight);
            const targetIndex = this.clamp(
              this.activeLyricIndex + offsetLines,
              0,
              this.parsedLrc.lines.length - 1,
            );
            this.isLyricDragging = false;
            this.showLyricTimeBubble = false;
            this.lyricDragOffsetY = 0;
            this.lyricTouchStartY = 0;
            if (offsetLines !== 0) {
              this.seekToLyricLine(targetIndex);
            }
          }
        });

        if (this.showLyricTimeBubble && this.lyricTimeBubbleText) {
          Text(this.lyricTimeBubbleText)
            .fontSize(14)
            .fontFamily("Medium")
            .fontColor(Color.White)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor("#4D000000")
            .backgroundBlurStyle(BlurStyle.Thin)
            .borderRadius(20)
            .position({ x: 24, y: 48 })
            .transition(TransitionEffect.opacity(0).animation({ duration: 200 }));
        }
      }
    }
    .width("100%")
    .height("100%");
  }

  @Builder
  private buildSmLayout() {
    Stack({ alignContent: Alignment.Top }) {
      Row({ space: 6 }) {
        Row()
          .height(5)
          .width(this.activeTabIndex === 0 ? 20 : 6)
          .borderRadius(999)
          .backgroundColor(this.activeTabIndex === 0 ? Color.White : "#40FFFFFF")
          .animation({ duration: 300, curve: this.springCurve })
        Row()
          .height(5)
          .width(this.activeTabIndex === 1 ? 20 : 6)
          .borderRadius(999)
          .backgroundColor(this.activeTabIndex === 1 ? Color.White : "#40FFFFFF")
          .animation({ duration: 300, curve: this.springCurve })
      }
      .position({ x: 0, y: this.windowProperties.topRect + 28 })
      .width("100%")
      .justifyContent(FlexAlign.Center)
      .zIndex(2)
      .hitTestBehavior(HitTestMode.None)
      Swiper() {
        this.buildPlayerPanel()
        this.buildLyricsPanel()
      }
      .loop(false)
      .duration(400)
      .indicator(false)
      .curve(this.springCurve)
      .index(this.activeTabIndex)
      .onChange((index: number) => {
        this.activeTabIndex = index;
      })
      .width("100%")
      .height("100%")
      .zIndex(1)
    }
    .width("100%")
    .height("100%");
  }

  @Builder
  private buildWideLayout() {
    Row({ space: 0 }) {
      Column() {
        this.buildPlayerPanel()
      }
      .layoutWeight(1)
      .height("100%")
      Blank().width(48)
      Column() {
        this.buildLyricsPanel()
      }
      .layoutWeight(1)
      .height("100%")
    }
    .width("100%")
    .height("100%")
    .padding({ left: 48, right: 48 });
  }

  @Builder
  private buildResponsiveLayout() {
    if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM) {
      this.buildSmLayout();
    } else {
      this.buildWideLayout();
    }
  }

  @Builder
  private buildFullPlayerContent() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildAmbientBackground()
      this.buildResponsiveLayout()
      this.buildTopBar()
    }
    .width("100%")
    .height("100%")
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 24 })),
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 24 })),
      ).animation({ duration: 320, curve: Curve.EaseOut }),
    )
    .onTouch((event?: TouchEvent) => {
      if (event && event.type === TouchType.Down) {
        this.startTopBarTimer();
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.visible && this.playlistViewModel.currentSong) {
        Stack({ alignContent: Alignment.Bottom }) {
          if (this.isExpandedForRender()) {
            this.buildFullPlayerContent();
          } else {
            this.buildMiniPlayerContent();
          }
        }
        .width(this.isExpandedForRender() ? "100%" : "calc(100% - 16vp)")
        .height(this.isExpandedForRender() ? "100%" : 60)
        .margin(this.isExpandedForRender() ? 0 : { bottom: this.bottomOffset + 8, left: 8, right: 8 })
        .borderRadius(this.isExpandedForRender() ? 0 : 16)
        .backgroundColor(this.isExpandedForRender() ? Color.Transparent : "#E5F2F2F2")
        .backgroundBlurStyle(this.isExpandedForRender() ? BlurStyle.NONE : BlurStyle.BACKGROUND_THIN)
        .shadow(this.isExpandedForRender() ? undefined : { radius: 24, color: "#33000000", offsetY: 8 })
        .clip(true)
        .animation({ duration: 450, curve: curves.springMotion(0.25, 0.85) })
        .onClick(() => {
          if (!this.isExpandedForRender()) {
            this.expandNowPlaying();
          }
        })
        .focusable(true)
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down && event.keyCode === BACK_KEY_CODE && this.isExpandedForRender()) {
            this.handleClose();
            event.stopPropagation();
          }
        })
        .gesture(
          PanGesture({ direction: PanDirection.Down }).onActionEnd((event: GestureEvent) => {
            if (this.isExpandedForRender() && event.offsetY > 50) {
              this.handleClose();
            }
          }),
        );
      }
    }
    .width("100%")
    .height(this.getShellHeight())
    .animation({ duration: 450, curve: curves.springMotion(0.25, 0.85) })
    .bindSheet($$this.showSheet, this.buildDynamicSheet(), {
      height:
        this.sheetType === "queue" || this.sheetType === "sleepTimer"
          ? SheetSize.MEDIUM
          : SheetSize.LARGE,
      showClose: false,
      preferType: SheetType.CENTER,
      onWillDismiss: () => {
        this.showSheet = false;
      },
    });
  }
}
