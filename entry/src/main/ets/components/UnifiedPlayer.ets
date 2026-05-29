import { AppStorageV2, curves, PersistenceV2 } from "@kit.ArkUI";
import { avSession } from "@kit.AVSessionKit";
import { LyricResponse } from "../adapter/omsp";
import { BreakpointConstants } from "../common/BreakpointConstants";
import { WindowProperties } from "../model/WindowProperties";
import TabSettingModel from "../model/adapter/TabSetting";
import { avSessionManager } from "../services/AVSessionManager";
import { PlayerCallbacks, playerManager } from "../services/PlayerManager";
import { songPlayerManager } from "../services/SongPlayerManager";
import { AudioEffectsSheet } from "./AudioEffectsSheet";
import { NowPlayingQueueSheet } from "./NowPlayingQueueSheet";
import { SleepTimerSheet } from "./SleepTimerSheet";
import { cover } from "../utils/Tools";
import { AudioVisualizer, AudioVisualState } from "../utils/AudioVisualizer";
import { ImageColorExtractor } from "../utils/ImageColorExtractor";
import Logger from "../utils/Logger";
import LrcParser, { LyricLine, LyricToken, ParsedLrc } from "../utils/LrcParser";
import CurrentSourceViewModel from "../viewmodel/CurrentSourceViewModel";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import SettingViewModel from "../viewmodel/SettingViewModel";

const TAG: string = "UnifiedPlayer";

const COLLAPSED_COVER: number = 44;
const COLLAPSED_BAR_H: number = 60;
const SIDE_MARGIN: number = 8;
const COVER_LEFT_PAD: number = 8;
const COLLAPSED_TITLE_SCALE: number = 0.54;
const ROOT_ID: string = "unified-player-root";

export class UIToken {
  text: string = "";
  startTimeMs: number = 0;
  durationMs: number = 0;
}

export class UILine {
  text: string = "";
  startTimeMs: number = 0;
  durationMs: number = 0;
  tokens: UIToken[] = [];
}

/**
 * 统一播放器跨组件信号（用于 Index 返回键兜底收起）
 */
@ObservedV2
export class UnifiedPlayerController {
  @Trace isExpanded: boolean = false;
  @Trace collapseRequestVersion: number = 0;
}

@ComponentV2
struct LyricTokenView {
  @Param tokenText: string = "";
  @Param startTimeMs: number = 0;
  @Param durationMs: number = 0;
  @Param currentProgress: number = 0;

  @Local textWidth: number = 0;

  @Computed
  get progressRatio(): number {
    if (this.currentProgress < this.startTimeMs) return 0;
    if (this.durationMs <= 0) return 1;
    if (this.currentProgress >= this.startTimeMs + this.durationMs) return 1;
    return (this.currentProgress - this.startTimeMs) / this.durationMs;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Text(this.tokenText)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor("#80FFFFFF")
        .maxLines(1)
        .onAreaChange((oldValue, newValue) => {
          if (this.textWidth === 0) {
            this.textWidth = newValue.width as number;
          }
        })
      Row() {
        Text(this.tokenText)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textShadow({ radius: 12, color: "#4DFFFFFF", offsetX: 0, offsetY: 0 })
          .maxLines(1)
          .width(this.textWidth > 0 ? this.textWidth : 'auto')
      }
      .position({ x: 0, y: 0 })
      .clip(true)
      .width(this.textWidth > 0 ? (this.textWidth + 16) * this.progressRatio : 0)
      .animation({ duration: 150, curve: Curve.Linear })
    }
    .width(this.textWidth > 0 ? this.textWidth : undefined)
    .flexShrink(0)
  }
}

/**
 * 统一播放器组件（折叠底部条 ↔ 全屏播放页）。
 *
 * 由连续进度 expandProgress(0=折叠,1=展开) 驱动，拖动时实时更新（跟手），松手吸附：
 * - 「背景卡片」buildBackgroundCard：深色不透明底，从折叠条形变放大到全屏（尺寸/位置/圆角 lerp），
 *   承载所有元素、中间态不透出下层；光晕/模糊封面仅在后段（glowFactor）浮现。
 * - 封面、歌名是持久节点，lerp 飞行（落点垂直居中）；SM 完全展开后交接给 Swiper 第一页以便整页左右滑。
 * - 进度/控制/顶栏/圆点/歌词：仅 fullyExpanded 时出现（中间态只有背景卡片+封面+歌名跟手）。
 * - 拖动把手：背景卡片 + 封面 + 歌名（折叠态上拖展开；展开态/完全展开下拖折叠）。
 * 不使用 geometryTransition；持久节点上不叠加 .animation()。
 */
@ComponentV2
export struct UnifiedPlayer {
  @Consumer() pageInfos: NavPathStack = new NavPathStack();

  @Param visible: boolean = true;

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
  @Local tabSettingModel: TabSettingModel = PersistenceV2.connect(
    TabSettingModel,
    "TabSettingModel",
    () => new TabSettingModel(),
  )!;
  @Local controller: UnifiedPlayerController = AppStorageV2.connect(
    UnifiedPlayerController,
    "UnifiedPlayerController",
    () => new UnifiedPlayerController(),
  )!;

  /** 展开进度：0=折叠，1=展开。拖动实时更新（跟手），松手 animateTo 吸附。 */
  @Local expandProgress: number = 0;
  /**
   * 是否完全展开。由 animateTo 的 onFinish 在动画真正结束后置位（而非用 expandProgress>=1）。
   * 这样点击展开/返回/收起的 animateTo 期间，持久封面/歌名仍挂载、其几何被 animateTo 插值 → 有飞行动画；
   * 完全展开后才把封面交接给 Swiper 第一页。
   */
  @Local isFullyExpanded: boolean = false;
  /**
   * 展开内容层（控制/顶栏/圆点/歌词）是否挂载。展开/拖动达阈值即 true（控件随 contentFactor 渐入），
   * 收起动画期间保持 true（让控件随 contentFactor 淡出下移），动画结束（onFinish）才置 false 卸载，
   * 从而支持完整的退出动画（而非瞬间消失）。
   */
  @Local isContentMounted: boolean = false;
  /** SM 展开态 Swiper 当前页：0=封面控制页，1=歌词页 */
  @Local activeTabIndex: number = 0;
  private swiperController: SwiperController = new SwiperController();

  @Local isPlaying: boolean = false;
  @Local currentProgress: number = 0;
  @Local duration: number = 0;
  @Local localProgress: number = 0;
  @Local isDraggingProgress: boolean = false;

  @Local showSheet: boolean = false;
  @Local sheetType: string = "";
  @Local isTopBarVisible: boolean = true;

  @Local parsedLrc: ParsedLrc = new ParsedLrc([], []);
  @Local uiLyrics: UILine[] = [];
  @Local isWordForWordMode: boolean = false;
  @Local activeLyricIndex: number = 0;
  @Local lyricTranslateY: number = 0;
  @Local lyricContainerHeight: number = 0;
  @Local isInitialLoaded: boolean = false;
  @Local isLyricDragging: boolean = false;
  @Local lyricDragOffsetY: number = 0;
  @Local showLyricTimeBubble: boolean = false;
  @Local lyricTimeBubbleText: string = "";
  @Local lyricTouchStartY: number = 0;
  @Local loadedLyricCacheId: string = "";

  @Local mainColor: string = "#FF007DFF";
  @Local gradientStartColor: string = "#FF3399FF";
  @Local gradientEndColor: string = "#FF005BB5";
  @Local colorExtracted: boolean = false;
  @Local hasCoverColor: boolean = false;
  @Local loadedColorSongId: string = "";

  @Local audioLevel: number = 0;
  @Local audioBass: number = 0;
  @Local audioMid: number = 0;
  @Local audioTreble: number = 0;

  private subscriberId: string =
    "UnifiedPlayer_" + Date.now().toString() + "_" + Math.floor(Math.random() * 1000000).toString();
  private progressTimerId: number = -1;
  private topBarHideTimerId: number = -1;
  private colorExtractRequestId: number = 0;
  private audioVisualState: AudioVisualState = new AudioVisualState();
  private lyricYPositions: number[] = [];
  private estimatedDragLineHeight: number = 56;
  private isPlayerBound: boolean = false;
  private springCurve = curves.interpolatingSpring(0, 1, 328, 36);
  private closeCurve = curves.cubicBezierCurve(0.23, 1, 0.32, 1);
  private dragStartProgress: number = 0;

  // ── 生命周期 ──────────────────────────────────────────────────────────────

  aboutToAppear(): void {
    this.activatePlayerBinding();
  }

  aboutToDisappear(): void {
    this.deactivatePlayerBinding();
    this.clearTopBarTimer();
  }

  @Monitor("playlistViewModel.currentSong")
  onCurrentSongChanged(): void {
    if (!this.playlistViewModel.currentSong) {
      if (this.expandProgress > 0) {
        this.collapse();
      }
      this.parsedLrc = new ParsedLrc([], []);
      this.uiLyrics = [];
      this.activeLyricIndex = 0;
      return;
    }
    this.currentProgress = playerManager.getCurrentPosition();
    this.localProgress = this.currentProgress;
    this.duration = playerManager.getDuration();
    this.extractMainColor();
    this.loadLyricsForCurrentSong();
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

  @Monitor("controller.collapseRequestVersion")
  onCollapseRequested(): void {
    if (this.expandProgress > 0) {
      // 返回手势链路：Index.onBackPress → controller.collapseRequestVersion++ → 本 @Monitor。
      // @Monitor 回调处于「状态更新流程」内，此处直接调 collapse() 里的 animateTo 会因
      // 「UI 上下文不明确 / V2 嵌套状态更新」而不产生动画 → expandProgress 瞬间归零、
      // 内容层立即卸载，表现为「一下子消失」而非飞行折叠。
      // 推迟到下一事件循环（干净的 UI 上下文）再收起，animateTo 才能产生共享元素飞行折叠动画。
      setTimeout(() => this.collapse(), 0);
    }
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

  // ── 展开 / 收起 / 拖动 ───────────────────────────────────────────────────────

  private expand(): void {
    if (!this.playlistViewModel.currentSong) {
      return;
    }
    this.controller.isExpanded = true;
    this.isContentMounted = true;
    this.getUIContext().animateTo(
      {
        curve: this.springCurve,
        onFinish: () => {
          if (this.expandProgress >= 1) {
            this.isFullyExpanded = true;
          }
        },
      },
      () => {
        this.expandProgress = 1;
      },
    );
    this.startTopBarTimer();
  }

  private collapse(): void {
    this.controller.isExpanded = false;
    // 立即切回持久封面/歌名（从 Swiper 交接回持久层），随后 animateTo 飞行折叠
    this.isFullyExpanded = false;
    this.getUIContext().animateTo(
      {
        duration: 450,
        curve: this.closeCurve,
        // 收起动画结束后才卸载内容层，期间控件随 contentFactor 淡出下移（退出动画）
        onFinish: () => {
          if (this.expandProgress <= 0) {
            this.isContentMounted = false;
          }
        },
      },
      () => {
        this.expandProgress = 0;
      },
    );
    this.activeTabIndex = 0;
    this.clearTopBarTimer();
  }

  private settleTo(target: number): void {
    this.controller.isExpanded = target >= 1;
    this.isContentMounted = true;
    this.getUIContext().animateTo(
      {
        curve: this.springCurve,
        onFinish: () => {
          if (target >= 1 && this.expandProgress >= 1) {
            this.isFullyExpanded = true;
          } else if (target < 1 && this.expandProgress <= 0) {
            // 收起完成兜底重置：否则若 isFullyExpanded 残留 true，持久 play/next 会因
            // opacity 0 + hitTestBehavior None 而既不可见也不可点。
            this.isFullyExpanded = false;
            this.isContentMounted = false;
          }
        },
      },
      () => {
        this.expandProgress = target;
      },
    );
    if (target < 1) {
      this.activeTabIndex = 0;
      this.clearTopBarTimer();
    } else {
      this.startTopBarTimer();
    }
  }

  private onHandleDragStart(): void {
    if (!this.playlistViewModel.currentSong) {
      return;
    }
    // 开始拖动：若此前已完全展开，从 Swiper 交接回持久封面/歌名以便跟手
    this.isFullyExpanded = false;
    this.dragStartProgress = this.expandProgress;
  }

  private onHandleDragUpdate(offsetY: number): void {
    const range = Math.max(1, this.windowProperties.winHeight * 0.5);
    this.expandProgress = this.clamp(this.dragStartProgress - offsetY / range, 0, 1);
    // 拖动达阈值即挂载内容层，使控件随手淡入；收起方向不在此卸载（交给松手 settleTo 的 onFinish）
    if (this.expandProgress > 0.35) {
      this.isContentMounted = true;
    }
  }

  private onHandleDragEnd(offsetY: number): void {
    let target: number;
    if (offsetY < -80) {
      target = 1;
    } else if (offsetY > 80) {
      target = 0;
    } else {
      target = this.expandProgress >= 0.5 ? 1 : 0;
    }
    this.settleTo(target);
  }

  private onHandleTap(): void {
    if (this.expandProgress < 1) {
      this.expand();
    }
  }

  // ── 播放控制 ──────────────────────────────────────────────────────────────

  private togglePlayPause(): void {
    if (this.isPlaying) {
      playerManager.pause();
    } else {
      songPlayerManager.playCurrentSongOrResume();
    }
  }

  private playPrev(): void {
    const prev = this.playlistViewModel.prevSong(true);
    if (prev) {
      this.playlistViewModel.playSong(prev, true);
    }
  }

  private playNext(): void {
    const next = this.playlistViewModel.nextSong(true);
    if (next) {
      this.playlistViewModel.playSong(next, true);
    }
  }

  private toggleLoopMode(): void {
    avSessionManager.syncLoopMode(this.playlistViewModel.setMode());
  }

  private onSliderChange(value: number, mode: SliderChangeMode): void {
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
  }

  private openLandscapePage(): void {
    if (!this.playlistViewModel.currentSong) {
      return;
    }
    this.pageInfos.pushPathByName("NowPlayingLandscape", null, false);
  }

  private openSheet(type: string): void {
    this.showSheet = false;
    this.sheetType = type;
    this.showSheet = true;
  }

  private closeSheet(): void {
    this.showSheet = false;
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

  private formatTime(ms: number): string {
    if (ms < 0 || isNaN(ms)) {
      return "00:00";
    }
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
  }

  // ── 顶栏 / 进度 / 律动 / 颜色 / 歌词 ──────────────────────────────────────────

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

  private async extractMainColor(): Promise<void> {
    const songId = this.playlistViewModel.currentSong?.id;
    if (songId !== undefined && this.loadedColorSongId === songId.toString() && this.colorExtracted) {
      return;
    }
    const requestId = this.colorExtractRequestId + 1;
    this.colorExtractRequestId = requestId;
    const currentCover = this.currentSongCover;
    if (!currentCover) {
      this.hasCoverColor = false;
      this.colorExtracted = true;
      return;
    }
    try {
      const coverUrl = cover(currentCover, 120) as string;
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
        if (songId !== undefined) {
          this.loadedColorSongId = songId.toString();
        }
      }
    }
  }

  private async loadLyricsForCurrentSong(): Promise<void> {
    const songId = this.playlistViewModel.currentSong?.id;
    const sourceId = this.playlistViewModel.currentSong?.sourceId;
    const source = this.currentSourceViewModel.source;
    if (songId === undefined || !source) {
      this.isInitialLoaded = true;
      return;
    }

    const cacheId = `${sourceId}_${songId}`;
    if (this.loadedLyricCacheId === cacheId && this.uiLyrics.length > 0) {
      this.updateActiveLyricByProgress(this.currentProgress);
      this.isInitialLoaded = true;
      return;
    }

    this.isInitialLoaded = false;
    this.parsedLrc = new ParsedLrc([], []);
    this.uiLyrics = [];
    this.isWordForWordMode = false;
    this.activeLyricIndex = 0;
    this.lyricYPositions = [];

    try {
      const resp: LyricResponse = await source.getLyric(songId);
      const wordForWordText: string = resp.lyric?.wordforword ?? "";
      const normalText: string = resp.lyric?.normal ?? "";
      const hasWordForWord: boolean = wordForWordText.trim().length > 0;
      const hasNormal: boolean = normalText.trim().length > 0;
      const shouldUseWordForWord: boolean = this.settingModel.wordForWordLyricsEnabled && hasWordForWord;
      const lrcText: string = shouldUseWordForWord
        ? wordForWordText
        : hasNormal
          ? normalText
          : wordForWordText;
      this.isWordForWordMode = shouldUseWordForWord;
      this.parsedLrc = LrcParser.parse(lrcText);

      const lines: LyricLine[] = this.parsedLrc.lines;
      const uiList: UILine[] = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const nextLine = lines[i + 1];
        const lineDuration = nextLine ? nextLine.startTimeMs - line.startTimeMs : 8000;

        const uiLine = new UILine();
        uiLine.text = line.text;
        uiLine.startTimeMs = line.startTimeMs;
        uiLine.durationMs = Math.max(0, lineDuration);

        for (let j = 0; j < line.tokens.length; j++) {
          const token: LyricToken = line.tokens[j];
          const nextToken = line.tokens[j + 1];
          const uiToken = new UIToken();
          uiToken.text = token.text;
          uiToken.startTimeMs = token.startTimeMs;
          if (nextToken) {
            uiToken.durationMs = Math.max(0, nextToken.startTimeMs - token.startTimeMs);
          } else {
            uiToken.durationMs = Math.max(0, uiLine.startTimeMs + uiLine.durationMs - token.startTimeMs);
            if (uiToken.durationMs > 5000) uiToken.durationMs = 5000;
          }
          uiLine.tokens.push(uiToken);
        }
        uiList.push(uiLine);
      }
      this.uiLyrics = uiList;

      this.updateActiveLyricByProgress(this.currentProgress);
      this.loadedLyricCacheId = cacheId;
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
    if (this.lyricContainerHeight === 0 || this.uiLyrics.length === 0) {
      return;
    }
    let centerY = this.lyricYPositions[this.activeLyricIndex];
    if (centerY === undefined) {
      centerY = this.activeLyricIndex * this.estimatedDragLineHeight + this.estimatedDragLineHeight / 2;
    }
    this.lyricTranslateY = this.lyricContainerHeight / 2 - centerY;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value));
  }

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t;
  }

  private lyricLineDistance(index: number): number {
    return index - this.activeLyricIndex;
  }

  private lyricLineScale(index: number): number {
    const d = Math.abs(this.lyricLineDistance(index));
    if (d === 0) return 1.0;
    return this.clamp(0.85 - d * 0.05, 0.7, 0.85);
  }

  private lyricLineOpacity(index: number): number {
    const d = this.lyricLineDistance(index);
    const absD = Math.abs(d);
    if (absD === 0) return 1.0;
    const base = d < 0 ? 0.35 : 0.5;
    return this.clamp(base - absD * 0.1, 0, 1);
  }

  private lyricLineBlur(index: number): number {
    const absD = Math.abs(this.lyricLineDistance(index));
    if (absD === 0) return 0;
    return this.clamp(absD * 1.5, 0, 6);
  }

  private shouldRenderWordForWordLine(line: UILine): boolean {
    return this.settingModel.wordForWordLyricsEnabled && this.isWordForWordMode && line.tokens.length > 0;
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
    const t = this.findCueTimeForLine(lineIndex);
    if (t >= 0) {
      playerManager.seek(t);
      this.currentProgress = t;
      this.updateActiveLyricByProgress(t);
    }
  }

  // ── 计算属性 ──────────────────────────────────────────────────────────────

  @Computed
  get currentSongCover(): string | undefined {
    return this.playlistViewModel.currentSong?.album?.cover;
  }

  @Computed
  get coverSrc(): ResourceStr {
    const c = this.playlistViewModel.currentSong?.album?.cover;
    return c ? cover(c, 480) : $r("sys.media.ohos_app_icon");
  }

  @Computed
  get artistText(): string {
    return this.playlistViewModel.currentSong?.artists?.map((artist) => artist.name).join("/") ?? "";
  }

  @Computed
  get isSm(): boolean {
    return this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM;
  }

  /** 光晕/模糊：拖动后段（>0.4）才渐显 */
  @Computed
  get glowFactor(): number {
    return this.clamp((this.expandProgress - 0.4) / 0.6, 0, 1);
  }

  /** 控件（进度/循环/上一首/队列/顶栏/圆点）显隐系数：后段（>0.45）随进度渐进淡入，避免完全展开瞬间停顿刷新 */
  @Computed
  get contentFactor(): number {
    return this.clamp((this.expandProgress - 0.45) / 0.55, 0, 1);
  }

  /** 折叠态右侧按钮透明度：拖动一开始即快速隐藏 */
  @Computed
  get collapsedButtonOpacity(): number {
    return this.clamp((0.3 - this.expandProgress) / 0.3, 0, 1);
  }

  @Computed
  get tabReserved(): number {
    const bottom = this.windowProperties.bottomRect;
    if (this.tabSettingModel.barFloatingStyle) {
      return bottom + 64 + 6 + 8;
    }
    if (this.isSm) {
      return bottom + 48 + 8;
    }
    return bottom + 8;
  }

  @Computed
  get collapsedBarTop(): number {
    return this.windowProperties.winHeight - this.tabReserved - COLLAPSED_BAR_H;
  }

  @Computed
  get expCoverSize(): number {
    if (this.isSm) {
      const s = this.windowProperties.winWidth * 0.72;
      return Math.min(320, Math.max(220, Math.floor(s)));
    }
    const s = this.windowProperties.winWidth * 0.3;
    return Math.min(360, Math.max(220, Math.floor(s)));
  }

  /** 展开态内容块（封面+歌名+控制）估算高度，用于垂直居中 */
  @Computed
  get expContentBlockHeight(): number {
    return this.expCoverSize + 36 + 64 + 24 + 150;
  }

  @Computed
  get collapsedCoverY(): number {
    return this.collapsedBarTop + (COLLAPSED_BAR_H - COLLAPSED_COVER) / 2;
  }

  @Computed
  get collapsedTitleX(): number {
    return SIDE_MARGIN + COVER_LEFT_PAD + COLLAPSED_COVER + 12;
  }

  @Computed
  get collapsedTitleY(): number {
    return this.collapsedBarTop + 8;
  }

  @Computed
  get expCoverX(): number {
    if (this.isSm) {
      return (this.windowProperties.winWidth - this.expCoverSize) / 2;
    }
    const leftColW = this.windowProperties.winWidth / 2;
    return (leftColW - this.expCoverSize) / 2 + 48;
  }

  /** 展开态封面 y：让封面+歌名+控制整体垂直居中 */
  @Computed
  get expCoverY(): number {
    const usable = this.windowProperties.winHeight - this.windowProperties.topRect - this.windowProperties.bottomRect;
    return this.windowProperties.topRect + Math.max(48, (usable - this.expContentBlockHeight) / 2);
  }

  @Computed
  get expTitleX(): number {
    if (this.isSm) {
      return 32;
    }
    return this.expCoverX;
  }

  @Computed
  get expTitleY(): number {
    return this.expCoverY + this.expCoverSize + 36;
  }

  @Computed
  get expTitleWidth(): number {
    if (this.isSm) {
      return this.windowProperties.winWidth - 64;
    }
    return this.windowProperties.winWidth / 2 - 96;
  }

  /** 展开态控制区起始 y（歌名下方） */
  @Computed
  get contentTop(): number {
    return this.expTitleY + 64 + 24;
  }

  // 折叠态控制按钮中心（折叠条右侧的 播放 / 下一首）
  @Computed
  get foldedCtrlCenterY(): number {
    return this.collapsedBarTop + COLLAPSED_BAR_H / 2;
  }

  @Computed
  get foldedPlayCenterX(): number {
    return this.windowProperties.winWidth - SIDE_MARGIN - 12 - 88 + 20;
  }

  @Computed
  get foldedNextCenterX(): number {
    return this.foldedPlayCenterX + 44;
  }

  // 展开态控制按钮行中心 y（进度条 60 + 间距 24 + 按钮行半高 40）
  @Computed
  get expCtrlRowCenterY(): number {
    return this.contentTop + 60 + 24 + 40;
  }

  // 展开态 播放键中心 x（SpaceBetween 下中央按钮恒为屏宽一半）
  @Computed
  get expPlayCenterX(): number {
    return this.windowProperties.winWidth / 2;
  }

  // 展开态 下一首中心 x（按 SpaceBetween 5 按钮 mode24/prev36/play80/next36/queue24 估算，真机可微调）
  @Computed
  get expNextCenterX(): number {
    return 190 + (3 * (this.windowProperties.winWidth - 264)) / 4;
  }

  // ── 子构建器：背景卡片（持久，折叠条→全屏 形变飞行） ───────────────────────────

  @Builder
  buildBackgroundCard() {
    Stack({ alignContent: Alignment.Center }) {
      // 深色不透明底：承载元素、中间态不透出下层
      Column()
        .width("100%")
        .height("100%")
        .backgroundColor("#0B0B10")

      // 模糊封面（后段渐显）
      if (this.playlistViewModel.currentSong?.album?.cover) {
        Image(cover(this.playlistViewModel.currentSong?.album?.cover, 240))
          .width("100%")
          .height("100%")
          .objectFit(ImageFit.Cover)
          .blur(100)
          .opacity(0.32 * this.glowFactor);
      }
      // 光晕小球（后段渐显）
      Row()
        .width(this.windowProperties.winWidth * 0.9)
        .height(this.windowProperties.winWidth * 0.9)
        .borderRadius(9999)
        .backgroundColor(this.colorExtracted && this.hasCoverColor ? this.gradientStartColor : "#402C2C2C")
        .opacity(((this.isPlaying ? 0.26 : 0.2) + this.audioBass * 0.18) * this.glowFactor)
        .blur(100)
        .position({
          x: -this.windowProperties.winWidth * 0.2 + this.audioMid * 24,
          y: -this.windowProperties.winHeight * 0.08 + this.audioBass * 16,
        })
        .scale(
          this.isPlaying
            ? { x: 1.1 + this.audioBass * 0.14, y: 1.1 + this.audioBass * 0.14 }
            : { x: 1.0, y: 1.0 },
        )
        .animation({ duration: 180, curve: Curve.EaseOut })
      Row()
        .width(this.windowProperties.winWidth * 0.8)
        .height(this.windowProperties.winWidth * 0.8)
        .borderRadius(9999)
        .backgroundColor(this.colorExtracted && this.hasCoverColor ? this.gradientEndColor : "#33202020")
        .opacity(((this.isPlaying ? 0.22 : 0.16) + this.audioTreble * 0.2) * this.glowFactor)
        .blur(120)
        .position({
          x: this.windowProperties.winWidth * 0.4 - this.audioTreble * 28,
          y: this.windowProperties.winHeight * 0.45 - this.audioMid * 22,
        })
        .scale(
          this.isPlaying
            ? { x: 1.12 + this.audioTreble * 0.18, y: 1.12 + this.audioTreble * 0.18 }
            : { x: 1.0, y: 1.0 },
        )
        .animation({ duration: 180, curve: Curve.EaseOut })
      Row()
        .width(this.windowProperties.winWidth * 0.56)
        .height(this.windowProperties.winWidth * 0.56)
        .borderRadius(9999)
        .backgroundColor(this.colorExtracted && this.hasCoverColor ? this.mainColor : "#2A4A4A4A")
        .opacity((0.1 + this.audioLevel * 0.14) * this.glowFactor)
        .blur(88)
        .scale({ x: 0.96 + this.audioLevel * 0.24, y: 0.96 + this.audioLevel * 0.24 })
        .animation({ duration: 180, curve: Curve.EaseOut })
      // 顶部暗化蒙层（后段）
      Column()
        .width("100%")
        .height("100%")
        .backgroundColor("#22000000")
        .opacity(this.glowFactor)
    }
    .width(this.lerp(this.windowProperties.winWidth - 2 * SIDE_MARGIN, this.windowProperties.winWidth, this.expandProgress))
    .height(this.lerp(COLLAPSED_BAR_H, this.windowProperties.winHeight, this.expandProgress))
    .position({
      x: this.lerp(SIDE_MARGIN, 0, this.expandProgress),
      y: this.lerp(this.collapsedBarTop, 0, this.expandProgress),
    })
    .borderRadius(this.lerp(16, 0, this.expandProgress))
    .clip(true)
    .shadow({
      radius: this.lerp(24, 0, this.expandProgress),
      color: "#40000000",
      offsetX: 0,
      offsetY: this.lerp(8, 0, this.expandProgress),
    })
    .onClick(() => this.onHandleTap())
    .gesture(
      PanGesture({ direction: PanDirection.Vertical })
        .onActionStart(() => this.onHandleDragStart())
        .onActionUpdate((event: GestureEvent) => this.onHandleDragUpdate(event.offsetY))
        .onActionEnd((event: GestureEvent) => this.onHandleDragEnd(event.offsetY)),
    );
  }

  // ── 子构建器：折叠态右侧按钮（渐隐） ─────────────────────────────────────────

  @Builder
  buildCollapsedButtons() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph(this.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill"))
          .fontSize(24)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .onClick(() => this.togglePlayPause())
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r("sys.symbol.forward_end_fill"))
          .fontSize(24)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .onClick(() => this.playNext())
    }
    .height(COLLAPSED_BAR_H)
    .position({
      x: this.windowProperties.winWidth - SIDE_MARGIN - 12 - 88,
      y: this.collapsedBarTop,
    })
    .opacity(this.collapsedButtonOpacity);
  }

  // ── 子构建器：持久封面（跟手 lerp 飞行 + 拖动把手） ────────────────────────────

  @Builder
  buildSharedCover() {
    Image(this.coverSrc)
      .width(this.lerp(COLLAPSED_COVER, this.expCoverSize, this.expandProgress))
      .height(this.lerp(COLLAPSED_COVER, this.expCoverSize, this.expandProgress))
      .borderRadius(
        this.lerp(this.settingModel.radiusItem, this.settingModel.radiusCardLarge, this.expandProgress),
      )
      .objectFit(ImageFit.Cover)
      .position({
        x: this.lerp(SIDE_MARGIN + COVER_LEFT_PAD, this.expCoverX, this.expandProgress),
        y: this.lerp(this.collapsedCoverY, this.expCoverY, this.expandProgress),
      })
      .shadow({
        radius: this.lerp(6, 36, this.expandProgress),
        color: "#66000000",
        offsetX: 0,
        offsetY: this.lerp(2, 18, this.expandProgress),
      })
      // SM 完全展开时隐藏（交给 Swiper 第一页封面）；其余情况显示并参与飞行/飞回
      .opacity(this.isSm && this.isFullyExpanded ? 0 : 1)
      // 透明时不拦截触摸，让点击/下滑穿透到 Swiper 第一页封面（切歌词/下滑折叠）
      .hitTestBehavior(this.isSm && this.isFullyExpanded ? HitTestMode.None : HitTestMode.Default)
      .onClick(() => this.onHandleTap())
      .gesture(
        PanGesture({ direction: PanDirection.Vertical })
          .onActionStart(() => this.onHandleDragStart())
          .onActionUpdate((event: GestureEvent) => this.onHandleDragUpdate(event.offsetY))
          .onActionEnd((event: GestureEvent) => this.onHandleDragEnd(event.offsetY)),
      );
  }

  @Builder
  buildSharedTitle() {
    Column({ space: 6 }) {
      Text(this.playlistViewModel.currentSong?.name ?? $r("app.string.not_playing"))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width("100%")
        .textAlign(TextAlign.Start)
      Text(this.artistText)
        .fontSize(18)
        .fontColor("#B3FFFFFF")
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width("100%")
        .textAlign(TextAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(this.expTitleWidth)
    .height(64)
    .position({
      x: this.lerp(this.collapsedTitleX, this.expTitleX, this.expandProgress),
      y: this.lerp(this.collapsedTitleY, this.expTitleY, this.expandProgress),
    })
    .scale({
      x: this.lerp(COLLAPSED_TITLE_SCALE, 1, this.expandProgress),
      y: this.lerp(COLLAPSED_TITLE_SCALE, 1, this.expandProgress),
      centerX: 0,
      centerY: 0,
    })
    .opacity(this.isSm && this.isFullyExpanded ? 0 : 1)
    .hitTestBehavior(this.isSm && this.isFullyExpanded ? HitTestMode.None : HitTestMode.Default)
    .onClick(() => this.onHandleTap())
    .gesture(
      PanGesture({ direction: PanDirection.Vertical })
        .onActionStart(() => this.onHandleDragStart())
        .onActionUpdate((event: GestureEvent) => this.onHandleDragUpdate(event.offsetY))
        .onActionEnd((event: GestureEvent) => this.onHandleDragEnd(event.offsetY)),
    );
  }

  // ── 子构建器：持久 播放/下一首 按钮（跟手 lerp 飞行，与封面同模式交接 Swiper 控制行） ──

  @Builder
  buildSharedControlButtons() {
    // 播放 / 暂停：飞向控制区中央大圆
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill"))
        .fontSize(this.lerp(24, 36, this.expandProgress))
        .fontColor([Color.White])
        // 关键：父 Stack 的 hitTestBehavior(None) 只让「自身」不响应，子 SymbolGlyph 仍会命中并拦截下层
        // buildControls 播放键（表现为「中心点不动、边缘能点」）。子节点也设 None，整个子树才完全穿透。
        .hitTestBehavior(HitTestMode.None)
    }
    .width(this.lerp(40, 80, this.expandProgress))
    .height(this.lerp(40, 80, this.expandProgress))
    .borderRadius(this.lerp(20, 40, this.expandProgress))
    .backgroundColor("#1AFFFFFF")
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: "#26FFFFFF" })
    .shadow({
      radius: this.lerp(8, 24, this.expandProgress),
      color: "#33000000",
      offsetX: 0,
      offsetY: this.lerp(4, 12, this.expandProgress),
    })
    .position({
      x:
        this.lerp(this.foldedPlayCenterX, this.expPlayCenterX, this.expandProgress) -
        this.lerp(20, 40, this.expandProgress),
      y:
        this.lerp(this.foldedCtrlCenterY, this.expCtrlRowCenterY, this.expandProgress) -
        this.lerp(20, 40, this.expandProgress),
    })
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.9 })
    .onClick(() => this.togglePlayPause())
    .opacity(this.isFullyExpanded ? 0 : 1)
    .hitTestBehavior(this.isFullyExpanded ? HitTestMode.None : HitTestMode.Default)
    // 折叠态按钮仅 40×40，上下各留 10vp 属背景卡片区——点偏会命中背景卡片触发展开而非播放。
    // 扩大点击热区到整条高（60）、左右补满到与下一首按钮相邻，避免「点不动」。
    .responseRegion({ x: -2, y: -10, width: 44, height: 60 })
    // 下一首：飞向控制区右侧
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r("sys.symbol.forward_end_fill"))
        .fontSize(this.lerp(24, 36, this.expandProgress))
        .fontColor([Color.White])
        // 同上：next 几乎整块都是图标，子节点不设 None 就会整体拦截下层（「完全点不动」）
        .hitTestBehavior(HitTestMode.None)
    }
    .width(this.lerp(40, 48, this.expandProgress))
    .height(this.lerp(40, 48, this.expandProgress))
    .position({
      x:
        this.lerp(this.foldedNextCenterX, this.expNextCenterX, this.expandProgress) -
        this.lerp(20, 24, this.expandProgress),
      y:
        this.lerp(this.foldedCtrlCenterY, this.expCtrlRowCenterY, this.expandProgress) -
        this.lerp(20, 24, this.expandProgress),
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
    .onClick(() => this.playNext())
    .opacity(this.isFullyExpanded ? 0 : 1)
    .hitTestBehavior(this.isFullyExpanded ? HitTestMode.None : HitTestMode.Default)
    .responseRegion({ x: -2, y: -10, width: 44, height: 60 })
  }

  // ── 子构建器：进度 + 控制按钮区 ─────────────────────────────────────────────

  @Builder
  buildControls() {
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
          .onChange((value: number, mode: SliderChangeMode) => this.onSliderChange(value, mode))
        Row() {
          Text(this.formatTime(this.isDraggingProgress ? this.localProgress : this.currentProgress))
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
      // 进度条整体：随展开进度后段渐进淡入 + 上移，避免完全展开瞬间突现
      .opacity(this.contentFactor)
      .translate({ y: (1 - this.contentFactor) * 36 })

      Row() {
        SymbolGlyph(
          this.playlistViewModel.mode === avSession.LoopMode.LOOP_MODE_SHUFFLE
            ? $r("sys.symbol.shuffle")
            : this.mapModeResource(this.playlistViewModel.mode),
        )
          .fontSize(24)
          .fontColor(["#99FFFFFF"])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .onClick(() => this.toggleLoopMode())
          .opacity(this.contentFactor)
          .translate({ y: (1 - this.contentFactor) * 28 })
        SymbolGlyph($r("sys.symbol.backward_end_fill"))
          .fontSize(36)
          .fontColor([Color.White])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .onClick(() => this.playPrev())
          .opacity(this.contentFactor)
          .translate({ y: (1 - this.contentFactor) * 28 })
        // 播放 / 下一首：不加 transition——由持久飞行节点 buildSharedControlButtons 交接，避免交接处闪烁
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
        .onClick(() => this.togglePlayPause())
        // SM 由持久飞行的 play 交接（完全展开才显示）；MD/LG 无持久层，随 contentFactor 渐进
        .opacity(this.isSm ? (this.isFullyExpanded ? 1 : 0) : this.contentFactor)
        SymbolGlyph($r("sys.symbol.forward_end_fill"))
          .fontSize(36)
          .fontColor([Color.White])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .onClick(() => this.playNext())
          .opacity(this.isSm ? (this.isFullyExpanded ? 1 : 0) : this.contentFactor)
        SymbolGlyph($r("sys.symbol.list_bullet"))
          .fontSize(24)
          .fontColor(["#99FFFFFF"])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .onClick(() => this.openSheet("queue"))
          .opacity(this.contentFactor)
          .translate({ y: (1 - this.contentFactor) * 28 })
      }
      .width("100%")
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width("100%");
  }

  // ── 子构建器：顶栏 ─────────────────────────────────────────────────────────

  @Builder
  buildTopBar() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r("sys.symbol.chevron_down"))
          .fontSize(26)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .backgroundColor("#1AFFFFFF")
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .onClick(() => this.collapse())
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
          action: () => this.openLandscapePage(),
        },
        {
          value: $r("app.string.audio_effects_title"),
          action: () => this.openSheet("audioEffects"),
        },
        {
          value: $r("app.string.sleep_timer_title"),
          action: () => this.openSheet("sleepTimer"),
        },
      ])
    }
    .width("100%")
    .alignItems(VerticalAlign.Center)
    .padding({ left: 24, right: 24, top: this.windowProperties.topRect + 16, bottom: 8 })
    .position({ x: 0, y: 0 })
    .opacity((this.isTopBarVisible ? 1 : 0) * this.contentFactor)
    .translate({ y: this.isTopBarVisible ? 0 : -20 })
    .animation({ duration: 400, curve: Curve.EaseOut });
  }

  // ── 子构建器：歌词面板 ──────────────────────────────────────────────────────

  @Builder
  buildPlainLyricLine(line: UILine, index: number) {
    Text(line.text)
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.activeLyricIndex === index ? Color.White : "#80FFFFFF")
      .textAlign(TextAlign.Start)
      .maxLines(5)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textShadow(
        this.activeLyricIndex === index
          ? { radius: 16, color: "#4DFFFFFF", offsetX: 0, offsetY: 0 }
          : undefined,
      )
      .animation({ duration: 500, curve: this.closeCurve });
  }

  @Builder
  buildWordForWordLyricLine(line: UILine, index: number) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
      if (Math.abs(this.lyricLineDistance(index)) > 8) {
        ForEach(
          line.tokens,
          (token: UIToken, tokenIndex: number) => {
            Text(token.text)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor("#80FFFFFF")
              .maxLines(1)
              .flexShrink(0)
          },
          (token: UIToken, tokenIndex: number): string =>
            `simple-${line.startTimeMs.toString()}-${tokenIndex.toString()}`,
        )
      } else {
        ForEach(
          line.tokens,
          (token: UIToken, tokenIndex: number) => {
            LyricTokenView({
              tokenText: token.text,
              startTimeMs: token.startTimeMs,
              durationMs: token.durationMs,
              currentProgress:
                index === this.activeLyricIndex
                  ? this.currentProgress
                  : index < this.activeLyricIndex
                    ? Number.MAX_SAFE_INTEGER
                    : -1,
            })
          },
          (token: UIToken, tokenIndex: number): string =>
            `${line.startTimeMs.toString()}-${tokenIndex.toString()}`,
        )
      }
    }
    .width("100%");
  }

  @Builder
  buildLyricsPanel() {
    Stack({ alignContent: Alignment.Top }) {
      if (!this.isInitialLoaded) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(Color.White)
          Text($r("app.string.now_playing_lyrics_placeholder"))
            .fontSize(16)
            .fontColor("#80FFFFFF")
            .margin({ top: 16 })
        }
        .width("100%")
        .height("100%")
        .justifyContent(FlexAlign.Center);
      } else if (this.uiLyrics.length === 0) {
        Column() {
          Text($r("app.string.now_playing_lyrics_empty"))
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
              this.uiLyrics,
              (line: UILine, index: number) => {
                Row() {
                  if (this.shouldRenderWordForWordLine(line)) {
                    this.buildWordForWordLyricLine(line, index);
                  } else {
                    this.buildPlainLyricLine(line, index);
                  }
                }
                .width("100%")
                .alignItems(VerticalAlign.Center)
                .padding({ top: 12, bottom: 12 })
                .onAreaChange((oldV, newV) => {
                  const y = newV.position.y as number;
                  const h = newV.height as number;
                  const centerY = y + h / 2;
                  if (Math.abs((this.lyricYPositions[index] || 0) - centerY) > 1) {
                    this.lyricYPositions[index] = centerY;
                    if (index === this.activeLyricIndex) {
                      this.updateLyricTranslate();
                    }
                  }
                })
                .opacity(Math.abs(this.lyricLineDistance(index)) <= 10 ? this.lyricLineOpacity(index) : 0)
                .scale({
                  x: this.lyricLineScale(index),
                  y: this.lyricLineScale(index),
                  centerX: 0,
                  centerY: "50%",
                })
                .blur(Math.abs(this.lyricLineDistance(index)) <= 6 ? this.lyricLineBlur(index) : 0)
                .animation({ duration: 600, curve: this.closeCurve })
                .onClick(() => this.seekToLyricLine(index));
              },
              (line: UILine, index: number) => index.toString(),
            )
          }
          .width("100%")
          .padding({ left: 32, right: 32 })
          .translate({ y: this.lyricTranslateY + (this.isLyricDragging ? this.lyricDragOffsetY : 0) })
          .animation({
            duration: this.isLyricDragging || !this.isInitialLoaded ? 0 : 700,
            curve: this.closeCurve,
          })
        }
        .width("100%")
        .height("100%")
        .onAreaChange((oldValue, newValue) => {
          this.lyricContainerHeight = newValue.height as number;
        })
        .onTouch((event?: TouchEvent) => {
          if (!event) return;
          if (event.type === TouchType.Down) {
            this.isLyricDragging = true;
            this.showLyricTimeBubble = true;
            this.lyricDragOffsetY = 0;
            this.lyricTouchStartY = event.touches[0].y;
          }
          if (event.type === TouchType.Move) {
            const dy = event.touches[0].y - this.lyricTouchStartY;
            this.lyricDragOffsetY = dy;
            const offsetLines = Math.round(-this.lyricDragOffsetY / this.estimatedDragLineHeight);
            const previewIndex = this.clamp(this.activeLyricIndex + offsetLines, 0, this.uiLyrics.length - 1);
            const t = this.findCueTimeForLine(previewIndex);
            this.lyricTimeBubbleText = t >= 0 ? this.formatTime(t) : "";
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            const offsetLines = Math.round(-this.lyricDragOffsetY / this.estimatedDragLineHeight);
            const targetIndex = this.clamp(this.activeLyricIndex + offsetLines, 0, this.uiLyrics.length - 1);
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

  // ── 子构建器：SM Swiper 第一页（封面+歌名+控制，绝对定位，与持久封面同坐标交接） ──

  @Builder
  buildPlayerPanel() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.coverSrc)
        .width(this.expCoverSize)
        .height(this.expCoverSize)
        .borderRadius(this.settingModel.radiusCardLarge)
        .objectFit(ImageFit.Cover)
        .position({ x: this.expCoverX, y: this.expCoverY })
        .shadow({ radius: 36, color: "#66000000", offsetX: 0, offsetY: 18 })
        .opacity(this.isFullyExpanded ? 1 : 0)
        .onClick(() => this.swiperController.changeIndex(1, true))
        .gesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart(() => this.onHandleDragStart())
            .onActionUpdate((event: GestureEvent) => this.onHandleDragUpdate(event.offsetY))
            .onActionEnd((event: GestureEvent) => this.onHandleDragEnd(event.offsetY)),
        )
      Column({ space: 6 }) {
        Text(this.playlistViewModel.currentSong?.name ?? $r("app.string.not_playing"))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width("100%")
          .textAlign(TextAlign.Start)
        Text(this.artistText)
          .fontSize(18)
          .fontColor("#B3FFFFFF")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width("100%")
          .textAlign(TextAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
      .width(this.expTitleWidth)
      .height(64)
      .position({ x: this.expTitleX, y: this.expTitleY })
      .opacity(this.isFullyExpanded ? 1 : 0)
      // 控制区已移出 Swiper（见 buildFullContent 固定层），此处仅留封面+歌名随页滑动
    }
    .width("100%")
    .height("100%");
  }

  @Builder
  buildLyricsFull() {
    Column() {
      Blank().height(this.windowProperties.topRect + 72)
      Stack() {
        this.buildLyricsPanel()
      }
      .layoutWeight(1)
      .width("100%")
    }
    .width("100%")
    // 歌词只占 contentTop 以上：控制区已移出 Swiper 固定在下半，歌词避让避免被遮挡
    .height(this.contentTop);
  }

  // ── 子构建器：宽屏（MD/LG）左右分栏，封面/歌名用持久节点 ──────────────────────

  @Builder
  buildWideFull() {
    Row() {
      Column() {
        Blank().height(this.contentTop)
        this.buildControls()
        Blank().layoutWeight(1)
      }
      .width("50%")
      .height("100%")
      .padding({ left: 48, right: 24, bottom: this.windowProperties.bottomRect + 24 })

      Column() {
        Blank().height(this.windowProperties.topRect + 56)
        Stack() {
          this.buildLyricsPanel()
        }
        .layoutWeight(1)
        .width("100%")
      }
      .width("50%")
      .height("100%")
      .padding({ right: 48, bottom: this.windowProperties.bottomRect + 24 })
    }
    .width("100%")
    .height("100%");
  }

  // ── 子构建器：完全展开后的内容层（仅 fullyExpanded 显示） ──────────────────────

  @Builder
  buildFullContent() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.isSm) {
        Swiper(this.swiperController) {
          this.buildPlayerPanel()
          this.buildLyricsFull()
        }
        .loop(false)
        .indicator(false)
        .duration(360)
        .curve(this.closeCurve)
        .index(this.activeTabIndex)
        .disableSwipe(!this.isFullyExpanded)
        .onChange((index: number) => {
          this.activeTabIndex = index;
          this.startTopBarTimer();
        })
        .width("100%")
        .height("100%")

        Row({ space: 6 }) {
          Row()
            .height(5)
            .width(this.activeTabIndex === 0 ? 20 : 6)
            .borderRadius(999)
            .backgroundColor(this.activeTabIndex === 0 ? Color.White : "#40FFFFFF")
            .animation({ duration: 300, curve: this.closeCurve })
          Row()
            .height(5)
            .width(this.activeTabIndex === 1 ? 20 : 6)
            .borderRadius(999)
            .backgroundColor(this.activeTabIndex === 1 ? Color.White : "#40FFFFFF")
            .animation({ duration: 300, curve: this.closeCurve })
        }
        .position({ x: 0, y: this.windowProperties.topRect + 28 })
        .width("100%")
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .opacity(this.contentFactor)

        // 控制区固定在播放页下半（移出 Swiper）：根治 play/next 等按钮与 Swiper 水平滑动竞争导致的「点不动」，
        // 且封面页/歌词页都常驻控制区。位置 contentTop 与持久飞行 play/next 落点一致，交接无缝。
        Column() {
          this.buildControls()
        }
        .width("100%")
        .padding({ left: 32, right: 32 })
        .position({ x: 0, y: this.contentTop })
      } else {
        this.buildWideFull()
      }
      this.buildTopBar()
    }
    .width("100%")
    .height("100%")
    .onTouch((event?: TouchEvent) => {
      if (event && event.type === TouchType.Down) {
        this.startTopBarTimer();
      }
    })
    .bindSheet($$this.showSheet, this.buildDynamicSheet(), {
      height:
        this.sheetType === "queue" || this.sheetType === "sleepTimer" ? SheetSize.MEDIUM : SheetSize.LARGE,
      showClose: false,
      preferType: SheetType.CENTER,
      onWillDismiss: () => {
        this.showSheet = false;
      },
    });
  }

  // ── 子构建器：动态 Sheet ─────────────────────────────────────────────────────

  @Builder
  buildQueueSheet() {
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
  buildAudioEffectsSheet() {
    AudioEffectsSheet({
      onClose: () => {
        this.closeSheet();
      },
    });
  }

  @Builder
  buildSleepTimerSheet() {
    SleepTimerSheet({
      onClose: () => {
        this.closeSheet();
      },
    });
  }

  @Builder
  buildDynamicSheet() {
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.visible && this.playlistViewModel.currentSong) {
        // 1. 背景卡片（持久，折叠条→全屏 形变飞行）—— 拖动把手，承载所有元素
        this.buildBackgroundCard()

        // 2. 折叠态右侧按钮：MD/LG 用静态按钮；SM 改用第 5 步的持久飞行 play/next
        if (!this.isSm && !this.isFullyExpanded) {
          this.buildCollapsedButtons()
        }

        // 3. 展开内容层（控制/顶栏/圆点/歌词 Swiper）：展开/拖动达阈值即挂载、收起动画结束才卸载（isContentMounted），
        //    内部控件随 contentFactor 渐进淡入/淡出；封面/歌名/play-next 仍按 isFullyExpanded 交接（避免与持久飞行层重影）。
        if (this.isContentMounted) {
          this.buildFullContent()
        }

        // 4. 持久封面 + 歌名（跟手 lerp 飞行）：始终挂载、用 opacity 交接，而非 if 卸载。
        //    若用 if 卸载，收起时它会在 expandProgress 已被置 0 后才重新挂载 → 直接出现在折叠态、无飞回。
        //    始终挂载则 animateTo 能对其几何插值 → 展开/收起对称飞行。SM 完全展开时 opacity 0 交给 Swiper。
        this.buildSharedCover()
        this.buildSharedTitle()

        // 5. SM 持久 播放/下一首 按钮（始终挂载、opacity 交接，同上）
        if (this.isSm) {
          this.buildSharedControlButtons()
        }
      }
    }
    .width("100%")
    .height("100%")
    .id(ROOT_ID)
    // 折叠态（progress≈0）Transparent 透传给下层列表；progress>0 时 Default 拦截。
    .hitTestBehavior(this.expandProgress > 0.01 ? HitTestMode.Default : HitTestMode.Transparent);
  }
}
