import { Song } from "../model/adapter/Song";
import { avSessionManager } from "./AVSessionManager";
import Logger from "../utils/Logger";
import { emitter } from "@kit.BasicServicesKit";
import { EmitEventConstants } from "../common/EmitEventConstants";
import { cover, getNetworkType, parseAssetId } from "../utils/Tools";
import { playerManager } from "./PlayerManager";
import { AppStorageV2, PersistenceV2 } from "@kit.ArkUI";
import { vibrator } from "@kit.SensorServiceKit";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import SettingViewModel from "../viewmodel/SettingViewModel";
import WindowUtil from "../utils/WindowUtil";
import { SourceListViewModel } from "../viewmodel/SourceListViewModel";
import PlayerViewModel from "../viewmodel/PlayerViewModel";
import { AudioVisualizer, AudioVisualState } from "../utils/AudioVisualizer";
import { id } from "../model/adapter/Types";

const TAG = "SongPlayerManager";
const AUDIO_HAPTICS_PRESET_EFFECT_IDS: string[] = [
  "haptic.effect.hard",
  "haptic.effect.sharp",
  "haptic.effect.soft",
  "haptic.clock.timer",
];
const AUDIO_HAPTICS_FALLBACK_EFFECT_ID: string = "haptic.clock.timer";

// --- 针对 EDM 持续高能优化的律动参数 ---
// 极限降低冷却时间，支持更密集的鼓点 (45ms 约支持 22Hz 连打，足以应对极快的高潮碎拍)
const AUDIO_HAPTICS_TRIGGER_INTERVAL_MS: number = 45;
// 绝对触发下限（由动态阈值主导抗噪，这里放得很低）
const AUDIO_HAPTICS_MIN_DRIVE: number = 0.04;

interface SongChangedData {
  songId?: id;
  sourceId?: string;
}

export class SongPlayerManager {
  private audioHapticsReady: boolean = false;
  private audioHapticsChecking: boolean = false;
  private audioHapticsAvailable: boolean = false;
  private audioHapticsPresetSupported: boolean = false;
  private audioHapticsEffectId: string = AUDIO_HAPTICS_FALLBACK_EFFECT_ID;
  private audioHapticsDispatching: boolean = false;
  private lastAudioHapticsAt: number = 0;

  // 律动检测新状态变量 (基于瞬时突变与动态阈值)
  private audioHapticsVisualState: AudioVisualState = new AudioVisualState();
  private previousBass: number = 0;
  private previousMid: number = 0;
  private previousTreble: number = 0;
  private bassEma: number = 0;
  private energyThreshold: number = 0.05;

  // ─── 私有辅助：获取 ViewModel ────────────────────────────────────────────────

  private getSettingViewModel(): SettingViewModel {
    return PersistenceV2.connect(
      SettingViewModel,
      "SettingViewModel",
      () => new SettingViewModel(),
    )!;
  }

  private getSourceListViewModel(): SourceListViewModel {
    return AppStorageV2.connect(
      SourceListViewModel,
      "SourceListViewModel",
      () => new SourceListViewModel(),
    )!;
  }

  private getPlaylistViewModel(): PlaylistViewModel {
    return AppStorageV2.connect(
      PlaylistViewModel,
      "PlaylistViewModel",
      () => new PlaylistViewModel(),
    )!;
  }

  private getPlayerViewModel(): PlayerViewModel {
    return PersistenceV2.connect(
      PlayerViewModel,
      "PlayerViewModel",
      () => new PlayerViewModel(),
    )!;
  }

  // ─── 睡眠定时器（定时播放/定时暂停） ───────────────────────────────────────────

  private sleepTimerId: number = -1;

  private startSleepTimerWatchdog(): void {
    if (this.sleepTimerId !== -1) return;

    this.sleepTimerId = setInterval(async () => {
      const vm = this.getPlayerViewModel();
      const endAt = vm.sleepTimerEndAtMs;
      if (endAt <= 0) {
        this.stopSleepTimerWatchdog();
        return;
      }

      const now = Date.now();
      if (now >= endAt) {
        try {
          await playerManager.pause();
        } catch (err) {
          Logger.error(TAG, `Sleep timer pause failed: ${(err as Error).message}`);
        }

        vm.sleepTimerEndAtMs = 0;
        this.stopSleepTimerWatchdog();
        this.emitSleepTimerStateChanged('expired', 0, emitter.EventPriority.IMMEDIATE);
      }
    }, 1000);
  }

  private stopSleepTimerWatchdog(): void {
    if (this.sleepTimerId !== -1) {
      clearInterval(this.sleepTimerId);
      this.sleepTimerId = -1;
    }
  }

  private emitSleepTimerStateChanged(state: string, endAtMs: number, priority: emitter.EventPriority): void {
    try {
      emitter.emit(
        { eventId: EmitEventConstants.SLEEP_TIMER_STATE_CHANGED, priority: priority },
        { data: { state: state, endAtMs: endAtMs } },
      );
    } catch (err) {
      // 忽略通知失败
    }
  }

  // ─── 音频律动震感核心逻辑 ───────────────────────────────────────────────────

  private async resolveSupportedAudioHapticsEffectId(): Promise<string> {
    for (let i = 0; i < AUDIO_HAPTICS_PRESET_EFFECT_IDS.length; i++) {
      const effectId = AUDIO_HAPTICS_PRESET_EFFECT_IDS[i];
      const supported = await vibrator.isSupportEffect(effectId);
      if (supported) {
        return effectId;
      }
    }
    return "";
  }

  private async ensureAudioHapticsSupport(): Promise<void> {
    if (this.audioHapticsReady || this.audioHapticsChecking) {
      return;
    }

    this.audioHapticsChecking = true;
    try {
      const vibratorInfoList = vibrator.getVibratorInfoSync();
      this.audioHapticsAvailable = vibratorInfoList.length > 0;
      if (!this.audioHapticsAvailable) {
        Logger.warn(TAG, "Audio haptics disabled: no vibrator detected on current device");
        return;
      }

      const supportedEffectId = await this.resolveSupportedAudioHapticsEffectId();
      if (supportedEffectId.length > 0) {
        this.audioHapticsPresetSupported = true;
        this.audioHapticsEffectId = supportedEffectId;
      } else {
        this.audioHapticsPresetSupported = false;
        this.audioHapticsEffectId = AUDIO_HAPTICS_FALLBACK_EFFECT_ID;
      }
      Logger.info(
        TAG,
        `Audio haptics initialized. presetSupported=${this.audioHapticsPresetSupported}, effectId=${this.audioHapticsEffectId}`,
      );
    } catch (err) {
      this.audioHapticsAvailable = false;
      this.audioHapticsPresetSupported = false;
      this.audioHapticsEffectId = AUDIO_HAPTICS_FALLBACK_EFFECT_ID;
      Logger.warn(TAG, `Audio haptics initialization failed: ${JSON.stringify(err)}`);
    } finally {
      this.audioHapticsReady = true;
      this.audioHapticsChecking = false;
    }
  }

  private clampAudioHapticsValue(value: number): number {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  private resetAudioHapticsState(stopVibration: boolean): void {
    this.lastAudioHapticsAt = 0;
    this.audioHapticsVisualState = new AudioVisualState();
    this.previousBass = 0;
    this.previousMid = 0;
    this.previousTreble = 0;
    this.bassEma = 0;
    this.energyThreshold = 0.05;

    if (stopVibration) {
      this.stopAudioHaptics();
    }
  }

  private async stopAudioHaptics(): Promise<void> {
    if (!this.audioHapticsReady || !this.audioHapticsAvailable) {
      return;
    }

    try {
      await vibrator.stopVibration();
    } catch (err) {
      Logger.warn(TAG, `Stop audio haptics failed: ${JSON.stringify(err)}`);
    }
  }

  private async triggerAudioHaptics(level: number): Promise<void> {
    if (!this.audioHapticsAvailable || this.audioHapticsDispatching) {
      return;
    }

    this.audioHapticsDispatching = true;

    // 放大倍率并限制范围。让较小的鼓点也有足够的力度感
    const normalizedLevel = this.clampAudioHapticsValue(level * 1.5);

    // 震动强度 (80-100)，保证每一次都有力
    const intensity = Math.max(80, Math.min(100, Math.round(80 + normalizedLevel * 20)));

    // 【关键】控制震动时长 (20-65ms)。太长会导致 EDM 的连续鼓点粘连在一起，感觉不到急促有力
    // 强制缩短响应时间，实现类似机械键盘的清脆打击感
    const duration = Math.max(20, Math.min(65, Math.round(20 + normalizedLevel * 45)));

    try {
      if (this.audioHapticsPresetSupported) {
        await vibrator.startVibration({
          type: 'preset',
          effectId: this.audioHapticsEffectId,
          count: 1,
          intensity: intensity,
        }, {
          usage: 'media'
        });
      } else {
        await vibrator.startVibration({
          type: 'time',
          duration: duration,
        }, {
          usage: 'media'
        });
      }
    } catch (err) {
      Logger.warn(TAG, `Trigger audio haptics failed: ${JSON.stringify(err)}`);
    } finally {
      this.audioHapticsDispatching = false;
    }
  }

  private handleAudioHapticsPcmData(data: ArrayBuffer): void {
    const settingViewModel = this.getSettingViewModel();
    if (!settingViewModel.experimentalAudioHapticsEnabled) {
      if (this.lastAudioHapticsAt > 0) {
        this.resetAudioHapticsState(true);
      }
      return;
    }

    if (!this.audioHapticsReady) {
      this.ensureAudioHapticsSupport();
      return;
    }

    if (!this.audioHapticsAvailable || data.byteLength < 2) {
      return;
    }

    this.audioHapticsVisualState = AudioVisualizer.analyze(data, this.audioHapticsVisualState);
    const bass = this.audioHapticsVisualState.bass;
    const mid = this.audioHapticsVisualState.mid;
    const treble = this.audioHapticsVisualState.treble;

    // 计算能量瞬时通量 (Energy Flux - 专抓敲击瞬间的起伏)
    const bassFlux = Math.max(0, bass - this.previousBass);
    const midFlux = Math.max(0, mid - this.previousMid);
    const trebleFlux = Math.max(0, treble - this.previousTreble);

    this.previousBass = bass;
    this.previousMid = mid;
    this.previousTreble = treble;

    // 对 EDM 的鼓点，起音 (Attack) 会在 bass 和 mid 产生巨大的瞬时通量
    const onsetScore = (bassFlux * 3.2) + (midFlux * 1.8) + (trebleFlux * 0.8);

    // 计算突出度 (Prominence - 当前低音相比最近均值的突出程度)
    // 使用快速适应的 EMA (Exponential Moving Average) 追踪基线
    this.bassEma = this.bassEma * 0.85 + bass * 0.15;
    const bassProminence = Math.max(0, bass - this.bassEma);

    // 综合驱动力 (Drive)
    // 结合起音的突变与低音的厚重度
    const drive = onsetScore + (bassProminence * 1.5);

    // 动态阈值自适应 (Dynamic Thresholding)
    // 阈值跟随整体能量起伏。0.85的衰减率能让它在鼓点后迅速下降，准备迎接下一个密集的碎拍
    this.energyThreshold = this.energyThreshold * 0.85 + drive * 0.15;

    // 触发判定
    // 只要驱动力突增超过动态阈值的 25%，且大于绝对底线，即视为一次有力击打。
    const isBeat = drive > AUDIO_HAPTICS_MIN_DRIVE && drive > this.energyThreshold * 1.25;

    const now = Date.now();
    if (isBeat) {
      // CD 限制，45ms 能完美支持极快的高潮连续鼓点，同时防止马达粘连
      if (now - this.lastAudioHapticsAt >= AUDIO_HAPTICS_TRIGGER_INTERVAL_MS) {
        this.lastAudioHapticsAt = now;

        // 传递瞬时驱动力，动态控制马达力度
        this.triggerAudioHaptics(drive);

        // 触发后短暂推高阈值，防止同一个底鼓的衰减余音引起二次重复触发
        this.energyThreshold += drive * 0.2;
      }
    }
  }

  // ─── 公开控制方法 ────────────────────────────────────────────────────────────

  public setSleepTimerMinutes(minutes: number): void {
    const vm = this.getPlayerViewModel();
    const m = Math.floor(minutes);
    if (m <= 0) {
      this.cancelSleepTimer();
      return;
    }

    const endAt = Date.now() + m * 60 * 1000;
    vm.sleepTimerEndAtMs = endAt;
    this.startSleepTimerWatchdog();
    this.emitSleepTimerStateChanged('set', endAt, emitter.EventPriority.HIGH);
  }

  public cancelSleepTimer(): void {
    const vm = this.getPlayerViewModel();
    vm.sleepTimerEndAtMs = 0;
    this.stopSleepTimerWatchdog();
    this.emitSleepTimerStateChanged('cancelled', 0, emitter.EventPriority.HIGH);
  }

  private async checkNetworkAndDataSaver(
    settingViewModel: SettingViewModel,
  ): Promise<string> {
    const uiContext = WindowUtil.getUIContext();
    const networkType = await getNetworkType();
    const dataSaverMode = settingViewModel.dataServiceMode;

    Logger.info(TAG, `Data saver mode: ${dataSaverMode}, Network type: ${networkType}`);

    if (dataSaverMode) {
      if (networkType === "NO_NETWORK") {
        uiContext?.getPromptAction().openToast({ message: $r("app.string.no_network") });
        throw new Error("当前没有网络连接");
      }

      if (dataSaverMode === "wifi-only" && networkType !== "WLAN") {
        const confirm = await uiContext?.getPromptAction().showDialog({
          title: $r("app.string.wifi_only_title"),
          message: $r("app.string.wifi_only"),
          buttons: [
            { text: $r('app.string.cancel'), color: $r('app.color.dialog_text_secondary') },
            { text: $r('app.string.confirm'), color: $r('app.color.dialog_text_primary') }
          ],
        });
        if (confirm?.index === 1) {
          settingViewModel.dataServiceMode = "both";
        } else {
          throw new Error("用户取消了移动数据播放");
        }
      }
    }

    return networkType;
  }

  private async fetchSongDetail(
    song: Song,
    networkType: string,
    settingViewModel: SettingViewModel,
    sourceListViewModel: SourceListViewModel,
  ): Promise<void> {
    const uiContext = WindowUtil.getUIContext();
    const source = sourceListViewModel.sources.find(source => source.id === song.sourceId);
    if (!source) {
      throw new Error(`Not found source: ${song.sourceId}`);
    }

    const playBitrate =
      networkType === "WLAN"
        ? settingViewModel.playBitrate
        : settingViewModel.playBitrateOnData;

    const detail = await source.getSongDetail(song.id, playBitrate);
    song.meta = detail.meta;

    if (!song.meta?.url) {
      uiContext?.getPromptAction().openToast({ message: $r("app.string.empty_url") });
      throw new Error(`Not found url for song: ${song.name}`);
    }
  }

  private syncAvSession(song: Song): void {
    avSessionManager.updateMetadata({
      assetId: `omsp://${song.sourceId}?id=${song.id}`,
      duration: song.duration,
      title: song.name,
      mediaImage: cover(song.album?.cover, 1024) as string,
      artist: song.artists?.map((a) => a.name).join("/"),
      lyric: song.meta?.lyric?.normal,
    });

    avSessionManager.getRawSession()?.setAVPlaybackState({
      isFavorite: song.meta?.isFavorite,
    });
  }

  private async handleSongChanged(song: Song): Promise<void> {
    Logger.info(TAG, `Handling song changed: ${song.name} By ${song.sourceId}`);
    const settingViewModel = this.getSettingViewModel();
    const sourceListViewModel = this.getSourceListViewModel();

    const networkType = await this.checkNetworkAndDataSaver(settingViewModel);
    await this.fetchSongDetail(song, networkType, settingViewModel, sourceListViewModel);
    this.syncAvSession(song);
    await playerManager.load(song.meta!.url!);
    await playerManager.play();
  }

  public async playCurrentSongOrResume(): Promise<void> {
    if (playerManager.isPlaying()) {
      return;
    }

    if (playerManager.isPrepared()) {
      await playerManager.play();
      return;
    }

    const playlistViewModel = this.getPlaylistViewModel();
    const currentSong = playlistViewModel.currentSong;
    if (!currentSong) {
      Logger.warn(TAG, 'Play request ignored: no current song available');
      return;
    }

    await this.handleSongChanged(currentSong);
  }

  private isSameSong(song: Song, songId: id, sourceId: string): boolean {
    return song.id === songId && song.sourceId === sourceId;
  }

  private resolveSongChangedTarget(
    eventData: emitter.EventData,
    playlistViewModel: PlaylistViewModel,
  ): Song | undefined {
    const data = eventData.data as SongChangedData;
    const currentSong = playlistViewModel.currentSong;

    if (data && data.songId !== undefined && data.sourceId !== undefined) {
      if (currentSong && this.isSameSong(currentSong, data.songId, data.sourceId)) {
        return currentSong;
      }

      for (let i = 0; i < playlistViewModel.playlist.length; i++) {
        const song = playlistViewModel.playlist[i];
        if (this.isSameSong(song, data.songId, data.sourceId)) {
          return song;
        }
      }
    }

    return currentSong;
  }

  private registerSongChangedListener(): void {
    emitter.on(
      { eventId: EmitEventConstants.CURRENT_SONG_UPDATED },
      async (eventData: emitter.EventData) => {
        const playlistViewModel = this.getPlaylistViewModel();
        const song = this.resolveSongChangedTarget(eventData, playlistViewModel);
        if (!song) {
          Logger.warn(TAG, 'Song changed event ignored: song payload unavailable');
          return;
        }

        try {
          await this.handleSongChanged(song);
        } catch (err) {
          Logger.error(TAG, `Song changed handling failed: ${(err as Error).message}`);
        }
      },
    );
  }

  private registerPlayerListeners(playlistViewModel: PlaylistViewModel): void {
    playerManager.addSubscriber("song_play_manager", {
      onPause: () => {
        this.resetAudioHapticsState(true);
      },
      onStop: () => {
        this.resetAudioHapticsState(true);
      },
      onCompleted: () => {
        this.resetAudioHapticsState(true);
        const nextSong = playlistViewModel.nextSong(false);
        if (!nextSong) {
          Logger.warn(TAG, "No next song, stop playing");
          return;
        }
        playlistViewModel.playSong(nextSong, true);
      },
      onPcmData: (data: ArrayBuffer) => {
        this.handleAudioHapticsPcmData(data);
      },
    });
  }

  private registerAvSessionListeners(playlistViewModel: PlaylistViewModel, sourceListViewModel: SourceListViewModel): void {
    avSessionManager.addSubscriber("song_play_manager", {
      onPlay: () => {
        this.playCurrentSongOrResume().catch((err: Error) => {
          Logger.error(TAG, `Play current song failed: ${err.message}`);
        });
      },

      onSetLoopMode: (mode) => {
        Logger.info(TAG, `Set loop mode: ${mode}`);
        avSessionManager.syncLoopMode(playlistViewModel.setMode(mode));
      },

      onToggleFavorite: async (assetId) => {
        try {
          const data = parseAssetId(assetId);
          const sourceId = data.sourceId;
          const songId = data.id;
          const source = sourceListViewModel.sources.find(source => source.id === sourceId);
          if (!source) {
            Logger.error(TAG, `Not found source: ${sourceId}`);
            return;
          }
          // 获取当前喜欢状态
          const isFavorite = await source.getLikeStatus(songId);
          await source.likeSong(songId, !isFavorite);
          avSessionManager.getRawSession()?.setAVPlaybackState({ isFavorite: !isFavorite });
        } catch (err) {
          Logger.error(TAG, `Toggle favorite failed: ${(err as Error).message}`);
        }
      },

      onPlayNext: () => {
        const nextSong = playlistViewModel.nextSong(true);
        if (!nextSong) {
          Logger.warn(TAG, "No next song, stop playing");
          return;
        }
        playlistViewModel.playSong(nextSong);
      },

      onPlayPrevious: () => {
        const prevSong = playlistViewModel.prevSong(true);
        if (!prevSong) {
          Logger.warn(TAG, "No previous song, stop playing");
          return;
        }
        playlistViewModel.playSong(prevSong);
      },
    });
  }

  public init(): void {
    const playlistViewModel = this.getPlaylistViewModel();
    const sourceListViewModel = this.getSourceListViewModel();
    this.ensureAudioHapticsSupport();
    this.registerSongChangedListener();
    this.registerPlayerListeners(playlistViewModel);
    this.registerAvSessionListeners(playlistViewModel, sourceListViewModel);

    // 恢复睡眠定时器
    const playerViewModel = this.getPlayerViewModel();
    if (playerViewModel.sleepTimerEndAtMs > 0 && Date.now() < playerViewModel.sleepTimerEndAtMs) {
      this.startSleepTimerWatchdog();
    } else {
      playerViewModel.sleepTimerEndAtMs = 0;
      this.stopSleepTimerWatchdog();
    }
  }

  public async destroy(): Promise<void> {
    this.stopSleepTimerWatchdog();
    this.resetAudioHapticsState(true);
    try {
      await playerManager.destroy();
    } catch (err) {
      Logger.error(TAG, `Destroy failed: ${(err as Error).message}`);
    }
  }
}

export const songPlayerManager = new SongPlayerManager();