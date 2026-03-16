import { AppStorageV2, curves, PersistenceV2 } from "@kit.ArkUI";
import { HdsNavDestination } from "@kit.UIDesignKit";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import CurrentSourceViewModel from "../viewmodel/CurrentSourceViewModel";
import { WindowProperties } from "../model/WindowProperties";
import { BreakpointConstants } from "../common/BreakpointConstants";
import SettingViewModel from "../viewmodel/SettingViewModel";
import { PlayerCallbacks, playerManager } from "../services/PlayerManager";
import { avSession } from "@kit.AVSessionKit";
import { avSessionManager } from "../services/AVSessionManager";
import { songPlayerManager } from "../services/SongPlayerManager";
import { cover } from "../utils/Tools";
import { ImageColorExtractor } from "../utils/ImageColorExtractor";
import Logger from "../utils/Logger";
import { NowPlayingQueueSheet } from "../components/NowPlayingQueueSheet";
import LrcParser, { LyricLine, LyricToken, ParsedLrc } from "../utils/LrcParser";
import { LyricResponse } from "../adapter/omsp";
import { AudioEffectsSheet } from "../components/AudioEffectsSheet";
import { SleepTimerSheet } from "../components/SleepTimerSheet";
import { AudioVisualizer, AudioVisualState } from "../utils/AudioVisualizer";
import { id } from "../model/adapter/Types";

const TAG: string = "NowPlaying";

// === 用于 UI 渲染的歌词拓展模型（自带持续时间，方便做平滑填充） ===
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
 * 逐字歌词 Token 渲染组件
 * 利用双层叠加 + 宽度裁剪 + 线性动画实现 Apple Music 级别的平滑注水效果
 */
@ComponentV2
struct LyricTokenView {
  @Param tokenText: string = "";
  @Param startTimeMs: number = 0;
  @Param durationMs: number = 0;
  @Param currentProgress: number = 0;

  // 记录文本的真实物理像素宽度
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
      // 底层：未点亮的暗色文本，决定组件真实的占位宽高
      Text(this.tokenText)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor("#80FFFFFF")
        .maxLines(1) // 确保词块内部绝对不换行
        .onAreaChange((oldValue, newValue) => {
          // 获取当前词块的绝对物理宽度（加判断防止触发死循环）
          if (this.textWidth === 0) {
            this.textWidth = newValue.width as number;
          }
        })

      // 顶层：点亮的白色文本（带发光），通过 Row 的物理宽度裁剪实现进度流淌
      Row() {
        Text(this.tokenText)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textShadow({ radius: 12, color: "#4DFFFFFF", offsetX: 0, offsetY: 0 })
          .maxLines(1) // 确保遮罩内的文字也不换行
          // 强制高亮文字保持真实的文本测量宽度
          .width(this.textWidth > 0 ? this.textWidth : 'auto')
      }
      .position({ x: 0, y: 0 }) // 绝对定位脱离文档流
      .clip(true)
      // 加上 16vp 的额外宽度作为缓冲，防止末尾截断
      .width(this.textWidth > 0 ? (this.textWidth + 16) * this.progressRatio : 0)
      // 动画仅作用于内部裁剪，完全与外部布局解耦
      .animation({ duration: 150, curve: Curve.Linear })
    }
    // 强制锁死外层 Stack 的宽度为文字核心宽度，防止引发重排
    .width(this.textWidth > 0 ? this.textWidth : undefined)
    .flexShrink(0) // 防止在横向 Flex 布局中被异常挤压
  }
}

@Builder
export function NowPlayingBuilder() {
  NowPlaying();
}

@ComponentV2
export struct NowPlaying {
  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  @Param onClose?: () => void = undefined;

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

  private transitionId(suffix: string): string {
    if (this.sharedTransitionDisabled) {
      return "";
    }
    return "np_shared" + suffix;
  }

  @Local sharedTransitionDisabled: boolean = false;

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
  @Local uiLyrics: UILine[] = []; // 渲染使用的带 duration 的歌词列表
  @Local isWordForWordMode: boolean = false;
  @Local activeLyricIndex: number = 0;
  @Local lyricTranslateY: number = 0;
  @Local lyricContainerHeight: number = 0;
  @Local isInitialLoaded: boolean = false;

  // 用于歌词/背景颜色的状态缓存，避免重复拉取
  @Local loadedLyricCacheId: string = "";
  @Local loadedColorSongId: id = "";

  private lyricYPositions: number[] = [];
  private estimatedDragLineHeight: number = 56;

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
  private subscriberId: string = 'NowPlaying_' + Date.now().toString() + '_' +
    Math.floor(Math.random() * 1000000).toString();
  private colorExtractRequestId: number = 0;
  private progressTimerId: number = -1;
  private audioVisualState: AudioVisualState = new AudioVisualState();
  private swiperController: SwiperController = new SwiperController();

  @Monitor("currentProgress")
  onProgressChange() {
    if (!this.isDraggingProgress) {
      this.localProgress = this.currentProgress;
    }
  }

  @Local isTopBarVisible: boolean = true;
  private topBarHideTimerId: number = -1;
  private springCurve = curves.cubicBezierCurve(0.23, 1, 0.32, 1);
  private isPlayerBound: boolean = false;

  aboutToAppear(): void {
    this.activatePlayerBinding();
    this.lastBreakpoint = this.windowProperties.currentBreakpoint;
    this.sharedTransitionDisabled = false;
    this.startTopBarTimer();
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

  aboutToDisappear(): void {
    this.deactivatePlayerBinding();
    this.clearTopBarTimer();
    this.showSheet = false;
  }

  private activatePlayerBinding(): void {
    if (this.isPlayerBound) {
      this.isPlaying = playerManager.isPlaying();
      this.duration = playerManager.getDuration();
      this.currentProgress = playerManager.getCurrentPosition();
      this.localProgress = this.currentProgress;
      // 页面重入时，检查是否需要更新歌词和背景色
      this.extractMainColor();
      this.loadLyricsForCurrentSong();
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

    playerManager.addSubscriber("NowPlayingPage", callbacks);
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
      playerManager.removeSubscriber("NowPlayingPage");
      this.isPlayerBound = false;
    }
    this.stopProgressTimer();
    this.resetAudioReactiveState();
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

  @Computed
  get currentSongCover(): string | undefined {
    return this.playlistViewModel.currentSong?.album?.cover;
  }

  @Computed
  get currentModeResource(): Resource {
    return this.playlistViewModel.mode === avSession.LoopMode.LOOP_MODE_SHUFFLE
      ? $r("sys.symbol.shuffle")
      : this.mapModeResource(this.playlistViewModel.mode);
  }

  @Monitor("activeLyricIndex", "lyricContainerHeight")
  onLyricStateChange(): void {
    this.updateLyricTranslate();
  }

  private updateLyricTranslate(): void {
    if (this.lyricContainerHeight === 0 || this.uiLyrics.length === 0) return;
    let centerY = this.lyricYPositions[this.activeLyricIndex];
    if (centerY === undefined) {
      centerY =
        this.activeLyricIndex * this.estimatedDragLineHeight + this.estimatedDragLineHeight / 2;
    }
    this.lyricTranslateY = this.lyricContainerHeight / 2 - centerY;
  }

  private async loadLyricsForCurrentSong(): Promise<void> {
    const songId = this.playlistViewModel.currentSong?.id;
    const sourceId = this.playlistViewModel.currentSong?.sourceId;
    const source = this.currentSourceViewModel.source;

    if (!songId || !source) {
      this.isInitialLoaded = true;
      return;
    }

    // 拼接 资源ID + 歌曲ID，如果已缓存且未发生变化，则跳过繁重的网络请求与重新渲染
    const cacheId = `${sourceId}_${songId}`;

    if (this.loadedLyricCacheId === cacheId && this.uiLyrics.length > 0) {
      Logger.info(TAG, "Lyrics already loaded for current song, skipping fetch.");
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
      const lrcText: string = shouldUseWordForWord ? wordForWordText : (hasNormal ? normalText : wordForWordText);
      this.isWordForWordMode = shouldUseWordForWord;
      this.parsedLrc = LrcParser.parse(lrcText);

      // --- 将解析后的歌词映射为带 duration（时长）的 UI 渲染模型 ---
      const lines = this.parsedLrc.lines;
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const nextLine = lines[i + 1];
        const lineDuration = nextLine ? (nextLine.startTimeMs - line.startTimeMs) : 8000;

        const uiLine = new UILine();
        uiLine.text = line.text;
        uiLine.startTimeMs = line.startTimeMs;
        uiLine.durationMs = Math.max(0, lineDuration);

        for (let j = 0; j < line.tokens.length; j++) {
          const token = line.tokens[j];
          const nextToken = line.tokens[j + 1];

          const uiToken = new UIToken();
          uiToken.text = token.text;
          uiToken.startTimeMs = token.startTimeMs;

          if (nextToken) {
            // 当前词持续到下个词开始
            uiToken.durationMs = Math.max(0, nextToken.startTimeMs - token.startTimeMs);
          } else {
            // 句末最后一个词，持续到该句结束（限制最大时长防溢出）
            uiToken.durationMs = Math.max(0, (uiLine.startTimeMs + uiLine.durationMs) - token.startTimeMs);
            if (uiToken.durationMs > 5000) uiToken.durationMs = 5000;
          }
          uiLine.tokens.push(uiToken);
        }
        this.uiLyrics.push(uiLine);
      }

      this.updateActiveLyricByProgress(this.currentProgress);
      // 记录已加载的缓存ID
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

  private clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value));
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

  private formatLyricBubbleTime(ms: number): string {
    return this.formatTime(ms);
  }

  private findCueTimeForLine(lineIndex: number): number {
    const cues = this.parsedLrc.cues;
    let best = -1;
    for (let i = 0; i < cues.length; i++) {
      if (cues[i].lineIndex === lineIndex) {
        best = cues[i].timeMs;
        break;
      }
    }
    return best;
  }

  private seekToLyricLine(lineIndex: number): void {
    const t = this.findCueTimeForLine(lineIndex);
    if (t >= 0) {
      playerManager.seek(t);
      this.currentProgress = t;
      this.updateActiveLyricByProgress(t);
    }
  }

  private async extractMainColor(): Promise<void> {
    const songId = this.playlistViewModel.currentSong?.id;
    // 优化：如果该歌曲已经提取过背景色，则不再重复调用耗时的提取逻辑
    if (songId && this.loadedColorSongId === songId && this.colorExtracted) {
      return;
    }

    const requestId = this.colorExtractRequestId + 1;
    this.colorExtractRequestId = requestId;
    if (!this.currentSongCover) {
      this.hasCoverColor = false;
      this.colorExtracted = true;
      return;
    }
    try {
      const coverUrl = cover(this.currentSongCover, 120) as string;
      const dominantColors = await ImageColorExtractor.extractMultipleDominantColors(coverUrl, 100);
      if (requestId !== this.colorExtractRequestId) return;
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
        if (songId) {
          this.loadedColorSongId = songId;
        }
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
    if (ms < 0 || isNaN(ms)) return "00:00";
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
  }

  private togglePlayPause(): void {
    if (this.isPlaying) {
      playerManager.pause();
    } else {
      songPlayerManager.playCurrentSongOrResume();
    }
  }

  private playPrev(): void {
    const prev = this.playlistViewModel.prevSong(true);
    if (prev) this.playlistViewModel.playSong(prev, true);
  }

  private playNext(): void {
    const next = this.playlistViewModel.nextSong(true);
    if (next) this.playlistViewModel.playSong(next, true);
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

  private handleClose(): void {
    this.isClosing = true;
    this.getUIContext()?.animateTo({ duration: 450, curve: this.springCurve }, () => {
      if (this.onClose) {
        this.onClose();
      }
    });
  }

  private openLandscapePage(): void {
    this.sharedTransitionDisabled = true;
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

  @Builder
  private buildPlainLyricLine(line: UILine, index: number) {
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
      .animation({ duration: 500, curve: this.springCurve });
  }

  @Builder
  private buildWordForWordLyricLine(line: UILine, index: number) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
      // 【核心渲染优化】：使用长列表虚拟化思维。只有靠近屏幕焦点的范围，才挂载厚重的 `LyricTokenView` 节点
      // 距离超过 8 的节点降级渲染为原生 Text，彻底消除在 SM 断点下进入歌词界面上百行 Flex 一齐被实例化的主线程卡顿
      if (Math.abs(this.lyricLineDistance(index)) > 8) {
        ForEach(
          line.tokens,
          (token: UIToken, tokenIndex: number) => {
            Text(token.text)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor("#80FFFFFF")
              .maxLines(1)
              .flexShrink(0) // 防止被 Flex 压缩，保证宽度一致
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
              // 只给当前活跃行分发真实进度，其他行传入极值避免频繁重绘
              currentProgress: index === this.activeLyricIndex
                ? this.currentProgress
                : (index < this.activeLyricIndex ? Number.MAX_SAFE_INTEGER : -1)
            })
          },
          (token: UIToken, tokenIndex: number): string =>
          `${line.startTimeMs.toString()}-${tokenIndex.toString()}`,
        )
      }
    }.width("100%");
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
      .onClick(() => this.handleClose())
    }
    .width("100%")
    .alignItems(VerticalAlign.Center)
    .padding({ left: 24, right: 24, top: this.windowProperties.topRect + 16, bottom: 8 })
    .position({ x: 0, y: 0 })
    .zIndex(10)
    .opacity(this.isTopBarVisible ? 1 : 0)
    .translate({ y: this.isTopBarVisible ? 0 : -20 })
    .animation({ duration: 400, curve: Curve.EaseOut });
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
        .height("100%")
        .justifyContent(FlexAlign.Start);
    }
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
        .id("now-playing-ambient-bg")
        .geometryTransition(this.transitionId("-background"), { follow: true })
        .transition(TransitionEffect.OPACITY)
    }
    .width("100%")
    .height("100%");
  }

  @Computed
  get coverSize(): number {
    const size = this.windowProperties.winWidth * 0.72;
    return Math.min(320, Math.max(220, Math.floor(size)));
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
          .id("now-playing-cover")
          .geometryTransition(this.transitionId("-cover"), { follow: true })
          .transition(TransitionEffect.OPACITY)
          .shadow({ radius: 36, color: "#66000000", offsetX: 0, offsetY: 18 })
          .scale(this.isPlaying ? { x: 1.0, y: 1.0 } : { x: 0.94, y: 0.94 })
          .animation({ duration: 900, curve: this.springCurve })
          .onClick(() => {
            this.swiperController.changeIndex(1, SwiperAnimationMode.DEFAULT_ANIMATION)
          }, 5)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
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
        .id("now-playing-title")
        .geometryTransition(this.transitionId("-title"), { follow: true })
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
          .id("now-playing-progress")
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
              .onClick(() => this.playPrev())
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
            SymbolGlyph($r("sys.symbol.forward_end_fill"))
              .fontSize(36)
              .fontColor([Color.White])
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
              .onClick(() => this.playNext())
            SymbolGlyph($r("sys.symbol.list_bullet"))
              .fontSize(24)
              .fontColor(["#99FFFFFF"])
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
              .onClick(() => this.openSheet("queue"))
          }
          .width("100%")
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .id("now-playing-controls")
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
    .gesture(
      SwipeGesture({
        direction: SwipeDirection.Vertical,
        speed: 10
      }).onAction((event) => {
        if (event.angle > 45 && event.angle < 145) {
          this.pageInfos.pop(undefined)
        }
        if (event.angle < -45 && event.angle > -145) {
          this.openSheet("queue")
        }
      })
    )
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

                  // 通过限定像素差触发条件，极大减少频繁的微小重排引发的翻译计算
                  if (Math.abs((this.lyricYPositions[index] || 0) - centerY) > 1) {
                    this.lyricYPositions[index] = centerY;
                    if (index === this.activeLyricIndex) {
                      this.updateLyricTranslate();
                    }
                  }
                })
                .opacity(Math.abs(this.lyricLineDistance(index)) <= 10 ? this.lyricLineOpacity(index) : 0) // 隐藏远处不需要渲染的歌词
                .scale({
                  x: this.lyricLineScale(index),
                  y: this.lyricLineScale(index),
                  centerX: 0,
                  centerY: "50%",
                })
                // 仅对视口内并且距离焦点 < 6 行的歌词计算高昂的模糊特效，这能大幅度解放 GPU
                .blur(Math.abs(this.lyricLineDistance(index)) <= 6 ? this.lyricLineBlur(index) : 0)
                .animation({ duration: 600, curve: this.springCurve })
                .onClick(() => this.seekToLyricLine(index));
              },
              (line: UILine, index: number) => index.toString(),
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
            const previewIndex = this.clamp(
              this.activeLyricIndex + offsetLines,
              0,
              this.uiLyrics.length - 1,
            );
            const t = this.findCueTimeForLine(previewIndex);
            this.lyricTimeBubbleText = t >= 0 ? this.formatLyricBubbleTime(t) : "";
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            const offsetLines = Math.round(-this.lyricDragOffsetY / this.estimatedDragLineHeight);
            const targetIndex = this.clamp(
              this.activeLyricIndex + offsetLines,
              0,
              this.uiLyrics.length - 1,
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
      Swiper(this.swiperController) {
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

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        this.buildAmbientBackground()
        this.buildResponsiveLayout()
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
        this.sheetType === "queue" || this.sheetType === "sleepTimer"
          ? SheetSize.MEDIUM
          : SheetSize.LARGE,
        showClose: false,
        preferType: SheetType.CENTER,
        onWillDismiss: () => {
          this.showSheet = false;
        },
      })
    }
    .onShown(() => {
      this.activatePlayerBinding();
      this.startTopBarTimer();
      this.sharedTransitionDisabled = false;
    })
    .onHidden(() => {
      this.deactivatePlayerBinding();
      this.clearTopBarTimer();
      this.showSheet = false;
    })
    .onBackPressed(() => {
      this.handleClose();
      return true;
    })
    .hideTitleBar(true)
    .ignoreLayoutSafeArea()
    .mode(NavDestinationMode.STANDARD);
  }
}