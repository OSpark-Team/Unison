import { AppStorageV2, window } from "@kit.ArkUI";
import { HdsNavDestination } from "@kit.UIDesignKit";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import CurrentSourceViewModel from "../viewmodel/CurrentSourceViewModel";
import { PlayerCallbacks, playerManager } from "../services/PlayerManager";
import { songPlayerManager } from "../services/SongPlayerManager";
import { avSession } from "@kit.AVSessionKit";
import { avSessionManager } from "../services/AVSessionManager";
import { cover } from "../utils/Tools";
import { ImageColorExtractor } from "../utils/ImageColorExtractor";
import Logger from "../utils/Logger";
import { NowPlayingQueueSheet } from "../components/NowPlayingQueueSheet";
import LrcParser, { ParsedLrc } from "../utils/LrcParser";
import { LyricResponse } from "../adapter/omsp";
import { AudioVisualizer, AudioVisualState } from "../utils/AudioVisualizer";
import { NowPlayingLandscape as NowPlayingLandscapeContent } from "../components/NowPlayingLandscape";
import WindowUtil from "../utils/WindowUtil";
import { WindowProperties } from "../model/WindowProperties";
import { MiniPlayerUiState } from "../model/MiniPlayerUiState";

const TAG: string = "NowPlayingLandscapePage";
const NOW_PLAYING_LANDSCAPE_ORIENTATION_OWNER: string = "NowPlayingLandscape";
@Builder
export function NowPlayingLandscapeBuilder() {
  NowPlayingLandscapePage();
}

@ComponentV2
struct NowPlayingLandscapePage {
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
    'WindowProperties',
    () => new WindowProperties(),
  )!;
  @Local miniPlayerUiState: MiniPlayerUiState = AppStorageV2.connect(
    MiniPlayerUiState,
    'MiniPlayerUiState',
    () => new MiniPlayerUiState(),
  )!;

  @Local isPlaying: boolean = false;
  @Local currentProgress: number = 0;
  @Local duration: number = 0;
  @Local showQueueSheet: boolean = false;
  @Local parsedLrc: ParsedLrc = new ParsedLrc([], []);
  @Local activeLyricIndex: number = 0;
  @Local mainColor: string = "#FF007DFF";
  @Local gradientStartColor: string = "#FF3399FF";
  @Local gradientEndColor: string = "#FF005BB5";
  @Local hasCoverColor: boolean = false;
  @Local audioLevel: number = 0;
  @Local audioBass: number = 0;
  @Local audioMid: number = 0;
  @Local audioTreble: number = 0;

  private progressTimerId: number = -1;
  private colorExtractRequestId: number = 0;
  private audioVisualState: AudioVisualState = new AudioVisualState();

  private backInProgress: boolean = false;

  aboutToAppear(): void {
    this.miniPlayerUiState.nowPlayingLandscapeActive = true;
    // 进入页面即设置横屏方向，避免先渲染竖屏布局再旋转带来的树抖动
    WindowUtil.setOrientationOverride(
      NOW_PLAYING_LANDSCAPE_ORIENTATION_OWNER,
      window.Orientation.LANDSCAPE,
    );

    // 设置常亮
    WindowUtil.setWindowScreenOn(true)

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
        this.updateActiveLyricByProgress(pos);
      },
      onPcmData: (data: ArrayBuffer) => {
        this.updateAudioReactiveState(data);
      },
    };

    playerManager.addSubscriber("NowPlayingLandscapePage", callbacks);
    this.isPlaying = playerManager.isPlaying();
    this.duration = playerManager.getDuration();
    this.currentProgress = playerManager.getCurrentPosition();
    if (this.isPlaying) {
      this.startProgressTimer();
    }

    this.extractMainColor();
    this.loadLyricsForCurrentSong();
  }

  aboutToDisappear(): void {
    this.miniPlayerUiState.nowPlayingLandscapeActive = false;
    playerManager.removeSubscriber("NowPlayingLandscapePage");
    this.stopProgressTimer();
    this.resetAudioReactiveState();
    this.showQueueSheet = false;
    WindowUtil.clearOrientationOverride(NOW_PLAYING_LANDSCAPE_ORIENTATION_OWNER);
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

  private onSliderChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      playerManager.seek(value);
      this.currentProgress = value;
      this.updateActiveLyricByProgress(value);
    }
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
    const mode = this.playlistViewModel.setMode();
    avSessionManager.syncLoopMode(mode);
  }

  private toggleShuffle(): void {
    if (this.playlistViewModel.mode === avSession.LoopMode.LOOP_MODE_SHUFFLE) {
      this.playlistViewModel.setMode(avSession.LoopMode.LOOP_MODE_LIST);
    } else {
      this.playlistViewModel.setMode(avSession.LoopMode.LOOP_MODE_SHUFFLE);
    }
    avSessionManager.syncLoopMode(this.playlistViewModel.mode);
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
    this.activeLyricIndex = cues[best].lineIndex;
  }

  private async loadLyricsForCurrentSong(): Promise<void> {
    this.parsedLrc = new ParsedLrc([], []);
    this.activeLyricIndex = 0;
    const songId = this.playlistViewModel.currentSong?.id;
    const source = this.currentSourceViewModel.source;
    if (!songId || !source) {
      return;
    }
    try {
      const resp: LyricResponse = await source.getLyric(songId);
      const lrcText: string = resp.lyric?.normal ?? "";
      this.parsedLrc = LrcParser.parse(lrcText);
      this.updateActiveLyricByProgress(this.currentProgress);
    } catch (error) {
      Logger.warn(TAG, `loadLyricsForCurrentSong failed: ${error}`);
    }
  }

  private async extractMainColor(): Promise<void> {
    const requestId = this.colorExtractRequestId + 1;
    this.colorExtractRequestId = requestId;
    if (!this.currentSongCover) {
      this.hasCoverColor = false;
      return;
    }
    try {
      const coverUrl = cover(this.currentSongCover, 120) as string;
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
    }
  }

  private handleBack(): void {
    if (this.backInProgress) {
      return;
    }
    this.backInProgress = true;

    const finalize = () => {
      this.backInProgress = false;
      if (this.waitTimerId !== -1) {
        clearTimeout(this.waitTimerId);
        this.waitTimerId = -1;
      }
    };

    // 取消常亮
    WindowUtil.setWindowScreenOn(false)

    WindowUtil.clearOrientationOverride(
      NOW_PLAYING_LANDSCAPE_ORIENTATION_OWNER,
    )
      .then(
        () => {
          this.pageInfos.pop(false);
          this.backInProgress = false;
        },
        (error: Error) => {
          Logger.warn(TAG, `clearOrientationOverride failed: ${error}`);
          this.pageInfos.pop(false);
          this.backInProgress = false;
        },
      )
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
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        NowPlayingLandscapeContent({
          song: this.playlistViewModel.currentSong,
          parsedLrc: this.parsedLrc,
          activeLyricIndex: this.activeLyricIndex,
          currentProgress: this.currentProgress,
          duration: this.duration,
          isPlaying: this.isPlaying,
          modeSymbol: this.currentModeResource,
          audioLevel: this.audioLevel,
          audioBass: this.audioBass,
          audioMid: this.audioMid,
          audioTreble: this.audioTreble,
          mainColor: this.mainColor,
          gradientStartColor: this.gradientStartColor,
          gradientEndColor: this.gradientEndColor,
          hasCoverColor: this.hasCoverColor,
          onSeek: (value: number, mode: SliderChangeMode) => this.onSliderChange(value, mode),
          onModeClick: () => {
            if (this.playlistViewModel.mode === avSession.LoopMode.LOOP_MODE_SHUFFLE) {
              this.toggleShuffle();
            } else {
              this.toggleLoopMode();
            }
          },
          onPrev: () => this.playPrev(),
          onPlayPause: () => this.togglePlayPause(),
          onNext: () => this.playNext(),
          onQueueClick: () => {
            this.showQueueSheet = true;
          },
        })
      }
      .width("100%")
      .height("100%")
      .bindSheet($$this.showQueueSheet, this.buildQueueSheet(), {
        height: SheetSize.MEDIUM,
        showClose: false,
        preferType: SheetType.CENTER,
        onWillDismiss: () => {
          this.showQueueSheet = false;
        },
      })
    }
    .onShown(() => {
      this.miniPlayerUiState.nowPlayingLandscapeActive = true;
    })
    .onHidden(() => {
      this.miniPlayerUiState.nowPlayingLandscapeActive = false;
    })
    .onBackPressed(() => {
      this.handleBack();
      return true;
    })
    .hideTitleBar(true)
    .ignoreLayoutSafeArea()
    .mode(NavDestinationMode.STANDARD);
  }
}
