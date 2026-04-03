import { audio } from '@kit.AudioKit';
import { avSession } from '@kit.AVSessionKit';
import { JSON } from '@kit.ArkTS';
import { AudioRendererPlayer, PcmDecoderTool, PcmStreamDecoder, PcmStreamInfo } from '@ospark/free-pcm';
import { avSessionManager } from './AVSessionManager';
import Logger from '../utils/Logger';
import { backgroundRunningManager } from '../utils/BackgroundRunningManager';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { isPlaying } from '../model/adapter/TabSetting';

const TAG = 'AVPlayerManager';

/**
 * 播放器事件回调接口。
 * 用于解耦 UI 组件或其他逻辑模块与播放核心的耦合。
 * @interface PlayerCallbacks
 */
export interface PlayerCallbacks {
  /** 当播放器被创建 */
  onCreated?: (audioRenderer: audio.AudioRenderer) => void;
  /** 开始播放或从暂停中恢复时触发 */
  onPlay?: () => void;
  /** 播放暂停时触发 */
  onPause?: () => void;
  /** 播放停止时触发 */
  onStop?: () => void;
  /** 播放位置跳转完成后触发 */
  onSeek?: (positionMs: number) => void;
  /** 播放至音频末尾时触发 */
  onCompleted?: () => void;
  /** 音频元数据（如时长）加载完成或发生变化时触发 */
  onDurationChange?: (durationMs: number) => void;
  /** 缓冲进度更新（0.0 - 1.0） */
  onBufferingUpdate?: (progress: number) => void;
  /** PCM Data回调 */
  onPcmData?: (data: ArrayBuffer) => void;
  /** 播放过程或加载过程中出现异常时触发 */
  onError?: (error: Error) => void;
}

/**
 * PlayerManager - 音频播放核心管理类
 * * @description 职责范围：
 * 1. 管理 Free-PCM 播放管线的完整生命周期（加载、渲染、销毁）。
 * 2. 自动与 AVSessionManager 联动，确保系统媒体中心状态同步。
 * 3. 支持多订阅者模式，允许多个页面或模块独立监听播放状态。
 * 4. 内置异步竞态保护机制（Sequence ID）。
 */
export class PlayerManager {
  /** 内部音频渲染器 */
  private renderer: AudioRendererPlayer = new AudioRendererPlayer();
  /** 内部流式解码器 */
  private decoder: PcmStreamDecoder | null = null;
  /** 当前音频流的基础信息 */
  private streamInfo: PcmStreamInfo | null = null;
  /** 解码工具实例 */
  private decoderTool = new PcmDecoderTool();

  /** 播放器是否已准备就绪 */
  private prepared = false;
  /** 是否已触发过当前音源的完成回调 */
  private completionFired = false;
  /** 播放进度监控定时器 */
  private completionTimer: number = -1;
  /** 当前是否是刚加载完成、尚未真正启动的新音源 */
  private sourcePendingStart = false;

  /** 序列号，用于在连续调用 load 时通过闭包识别并拦截过时的异步回调 */
  private seq = 0;

  /** 订阅者映射表 [订阅者ID, 回调实现] */
  private subscribers: Map<string, PlayerCallbacks> = new Map();

  /**
   * 构造函数
   * 初始化时自动注册 AVSession 系统指令监听
   */
  constructor() {
    this.registerAVSessionControl();
    this.registerAudioRenderer();
    this.registerInternalPlayerControl();
  }

  private async setupAudioInterrupt(renderer: audio.AudioRenderer) {
    // 设置焦点模式为共享模式
    renderer.setInterruptMode(audio.InterruptMode.SHARE_MODE);
    renderer.on('outputDeviceChangeWithInfo', async (info: audio.AudioStreamDeviceChangeInfo) => {
      switch (info.changeReason) {
        case audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE:
          // 设备不可用(如蓝牙断开)，需要暂停播放
          await this.pause()
          break;
        case audio.AudioStreamDeviceChangeReason.REASON_NEW_DEVICE_AVAILABLE:
          // 新设备可用
          break;
        case audio.AudioStreamDeviceChangeReason.REASON_OVERRODE:
          // 设备被切换
          break;
      }
    })
  }

  /**
   * 设置音频会话策略
   */
  async setAudioSession() {
    const settingModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
    const playingMix = settingModel.experimentalPlayingMixEnabled;

    const strategy: audio.AudioSessionStrategy = {
      concurrencyMode: playingMix ? audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS:audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT
    }
    await audio.getAudioManager().getSessionManager().activateAudioSession(strategy)
  }

  async setupAudioRenderer(renderer: audio.AudioRenderer) {
    renderer.on('stateChange', async (state: audio.AudioState) => {
      switch (state) {
        case audio.AudioState.STATE_NEW:
          break;
        case audio.AudioState.STATE_PREPARED:
          avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
          break;
        case audio.AudioState.STATE_RUNNING:
          avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
          this.dispatch(cb => cb.onPlay?.());
          break;
        case audio.AudioState.STATE_PAUSED:
          avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
          this.dispatch(cb => cb.onPause?.());
          break;
        case audio.AudioState.STATE_STOPPED:
          avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
          this.dispatch(cb => cb.onStop?.());
          break;
        case audio.AudioState.STATE_RELEASED:
          avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_RELEASED);
          this.dispatch(cb => cb.onStop?.());
          this.dispatch(cb => cb.onPause?.());
          break;
        default:
          break;
      }
    });
  }

  // ── 多订阅者管理 ──────────────────────────────────────────────────────────

  /**
   * 注册内部播放和暂停用来启动后台任务
   */
  private registerInternalPlayerControl() {
    this.addSubscriber('internal_player_control', {
      onCreated: (renderer: audio.AudioRenderer)=>{
        this.setupAudioInterrupt(renderer);
        this.setupAudioRenderer(renderer);
        this.setAudioSession();
      },
      onPlay: () => backgroundRunningManager.startBackgroundRunning(),
      onPause: () => backgroundRunningManager.stopBackgroundRunning(),
    });
  }

  /**
   * 注册订阅者。
   * 若 ID 已存在，则会覆盖旧的回调对象。
   * @param string subscriberId - 唯一标识（如 'MainPage', 'GlobalLogger'）
   * @param PlayerCallbacks callbacks - 回调函数集合
   */
  public addSubscriber(subscriberId: string, callbacks: PlayerCallbacks): void {
    this.subscribers.set(subscriberId, callbacks);
    Logger.info(TAG, `Subscriber "${subscriberId}" registered.`);
  }

  /**
   * 移除指定订阅者。
   * @param string subscriberId - 订阅者唯一标识
   */
  public removeSubscriber(subscriberId: string): void {
    this.subscribers.delete(subscriberId);
  }

  /**
   * 清空所有订阅者。
   */
  public clearAllSubscribers(): void {
    this.subscribers.clear();
  }

  /**
   * 获取所有订阅者 ID。
   * @returns string[]
   */
  public getSubscriberIds(): string[] {
    return Array.from(this.subscribers.keys());
  }

  // ── 播放控制逻辑 ──────────────────────────────────────────────────────────

  /**
   * 加载音源并准备播放。
   * 会自动清理上一个音源并同步元数据到系统媒体中心。
   * @param string source - 音频资源的 URI 或本地路径
   * @returns Promise<void>
   */
  public async load(source: string): Promise<void> {
    await this.cleanup();

    this.seq++;
    const currentSeq = this.seq;

    // 创建解码流
    const dec = this.decoderTool.createStreamDecoder(source, {}, {
      onError: (e: Error) => {
        if (this.seq !== currentSeq) {
          return;
        }
        this.dispatch(cb => cb.onError?.(e));
      },
    });
    this.decoder = dec;

    try {
      const info = await dec.ready;
      // 竞态检查：如果序列号已更新，说明 load 被重新调用，丢弃当前陈旧请求
      if (this.seq !== currentSeq) return;

      this.streamInfo = info;
      this.prepared = true;
      this.completionFired = false;
      this.sourcePendingStart = true;

      //  通知内部订阅者
      this.dispatch(cb => cb.onDurationChange?.(info.durationMs));
      this.dispatch(cb => cb.onSeek?.(0));


      // 监听流结束
      dec.done.then(() => {
        if (this.seq !== currentSeq) return;
        this.startCompletionWatchdog();
      }).catch((e: Error) => {
        if (this.seq !== currentSeq) return;
        this.dispatch(cb => cb.onError?.(e));
      });

    } catch (e) {
      if (this.seq === currentSeq) {
        this.dispatch(cb => cb.onError?.(e as Error));
      }
    }
  }

  /**
   * 开始或恢复播放。
   * 同时更新系统 AVSession 状态为 PLAY。
   */
  public async play(): Promise<void> {
    if (!this.prepared || !this.decoder || !this.streamInfo) {
      Logger.warn(TAG, 'play called before prepared');
      // 即使提前返回，也要确保 sourcePendingStart 被清零，避免残留导致后续 watchdog 被跳过
      this.sourcePendingStart = false;
      return;
    }

    const state = this.renderer.getState();
    const shouldStartFresh = this.sourcePendingStart || state === audio.AudioState.STATE_STOPPED;

    try {
      if (state === audio.AudioState.STATE_PAUSED && !shouldStartFresh) {
        await this.renderer.resume();
      } else {
        await this.renderer.play(this.decoder, this.streamInfo);
      }

      this.sourcePendingStart = false;

      this.startCompletionWatchdog();

      // 同步系统状态
      avSessionManager.syncPlaybackState(
        avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        shouldStartFresh ? 0 : this.renderer.getCurrentPosition()
      );
    } catch (e) {
      this.dispatch(cb => cb.onError?.(e as Error));
    }
    let IsPlaying: isPlaying = AppStorageV2.connect(
      isPlaying,
      "isPlaying",
      () => new isPlaying(),
    )!;
    IsPlaying.isPlaying =true
  }

  /**
   * 暂停播放。
   * 同时更新系统 AVSession 状态为 PAUSE。
   */
  public async pause(): Promise<void> {
    try {
      await this.renderer?.pause();

      avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE, this.renderer.getCurrentPosition());
    } catch (e) {
      this.dispatch(cb => cb.onError?.(e as Error));
    }
    let IsPlaying: isPlaying = AppStorageV2.connect(
      isPlaying,
      "isPlaying",
      () => new isPlaying(),
    )!;
    IsPlaying.isPlaying =false
  }

  /**
   * 停止播放（保留当前音源）。
   */
  public async stop(): Promise<void> {
    try {
      await this.renderer?.stop();
      this.stopCompletionWatchdog();

      avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
    } catch (e) {
      this.dispatch(cb => cb.onError?.(e as Error));
    }
    let IsPlaying: isPlaying = AppStorageV2.connect(
      isPlaying,
      "isPlaying",
      () => new isPlaying(),
    )!;
    IsPlaying.isPlaying =false
  }

  /**
   * 跳转至指定进度。
   * @param number positionMs - 目标位置（毫秒）
   */
  public async seek(positionMs: number): Promise<void> {
    if (!this.prepared) return;
    // 如果用户已经可以 seek，说明音源已经可以被操作，清除 pending 状态
    if (this.sourcePendingStart) {
      this.sourcePendingStart = false;
    }
    try {
      await this.renderer?.seekTo(positionMs);
      this.dispatch(cb => cb.onSeek?.(positionMs));

      // 更新系统进度条位置
      const currentState = this.isPlaying()
        ? avSession.PlaybackState.PLAYBACK_STATE_PLAY
        : avSession.PlaybackState.PLAYBACK_STATE_PAUSE;

      avSessionManager.syncPlaybackState(currentState, positionMs);
    } catch (e) {
      this.dispatch(cb => cb.onError?.(e as Error));
    }
  }

  /**
   * 释放播放器资源并注销所有订阅者。
   */
  public async destroy(): Promise<void> {
    await this.cleanup();
    avSessionManager.removeSubscriber('player_internal_core');
    this.clearAllSubscribers();
  }

  // ── 状态查询 ──────────────────────────────────────────────────────────────

  /** @returns number 当前播放进度（毫秒） */
  public getCurrentPosition(): number {
    return this.renderer?.getCurrentPosition() ?? 0;
  }

  /** @returns number 当前音频总时长（毫秒） */
  public getDuration(): number {
    return this.streamInfo?.durationMs ?? 0;
  }

  /** @returns boolean 是否正在播放中 */
  public isPlaying(): boolean {
    return this.renderer?.getState() === audio.AudioState.STATE_RUNNING;
  }

  /** @returns boolean 当前音频资源是否已准备完成 */
  public isPrepared(): boolean {
    return this.prepared;
  }

  // ── 内部私有方法 ──────────────────────────────────────────────────────────

  /**
   * 将 AVSession 的外部系统指令映射到播放器实例方法。
   * @private
   */
  private registerAVSessionControl(): void {
    avSessionManager.addSubscriber('player_internal_core', {
      onPause: () => this.pause(),
      onStop: () => this.stop(),
      onSeek: (pos) => this.seek(pos),
    });
  }

  /**
   * AudioRenderer回调
   * @private
   */
  private registerAudioRenderer() {
    this.renderer.setOnCreated(
      (renderer: audio.AudioRenderer) => {
        this.dispatch(cb => cb.onCreated?.(renderer));
      }
    )
    this.renderer.setOnPcmData((data) => {
      this.dispatch(cb => cb.onPcmData?.(data));
    })
  }

  /**
   * 向所有订阅者分发事件。
   * @private
   */
  private dispatch(invoke: (callbacks: PlayerCallbacks) => void): void {
    this.subscribers.forEach((callbacks, id) => {
      try {
        invoke(callbacks);
      } catch (error) {
        Logger.error(TAG, `Subscriber "${id}" error: ${JSON.stringify(error)}`);
      }
    });
  }

  /**
   * 清理当前播放状态与资源。
   * @private
   */
  private async cleanup(): Promise<void> {
    this.stopCompletionWatchdog();
    try { await this.renderer?.stop(); } catch (_e) {}
    try { this.decoder?.close(); } catch (_e) {}
    this.decoder = null;
    this.streamInfo = null;
    this.prepared = false;
    this.completionFired = false;
    this.sourcePendingStart = false;
  }

  /**
   * 启动播放完成监控。
   * 由于部分 PCM 流结尾可能存在微小偏差，采用轮询方式确保完成回调触发。
   * @private
   */
  private startCompletionWatchdog(): void {
    if (this.completionTimer !== -1) return;

this.completionTimer = setInterval(async () => {
      if (this.completionFired || !this.renderer || this.sourcePendingStart) return;

      const dur = this.getDuration();
      const pos = this.getCurrentPosition();

      // 无效时长，跳过检查
      if (dur <= 0) {
        return;
      }

      // 保护性检查：如果 position 远超过 duration（>500ms），说明是旧流的脏数据，跳过本次判断
      // 这种情况会在切歌时发生：旧流的 position 残留在 renderer 中，新歌 duration 较短
      // 但允许轻微超出（PCM流末尾可能有微小偏差）
      if (pos > dur + 500) {
        return;
      }

      // 距离结束小于 50ms 视为完成（包括 position 轻微超过 duration 的情况）
      if (pos >= dur - 50) {
        await this.handleCompleted();
      }
    }, 200);
  }

  /** @private */
  private stopCompletionWatchdog(): void {
    if (this.completionTimer !== -1) {
      clearInterval(this.completionTimer);
      this.completionTimer = -1;
    }
  }

  /**
   * 播放完成处理。
   * @private
   */
  private async handleCompleted(): Promise<void> {
    if (this.completionFired) return;
    this.completionFired = true;
    this.stopCompletionWatchdog();

    this.dispatch(cb => cb.onCompleted?.());
    // 通知系统媒体中心状态变更为暂停/结束
    avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
  }

  /**
   * 设置EQ增益
   */
  public setEqGainsLR(leftGainsDb: number[], rightGainsDb: number[]): void {
    this.renderer?.setEqGainsLR(leftGainsDb, rightGainsDb);
  }

  /**
   * 设置左右声道独立音量系数
   */
  public setChannelVolumes(leftCoeff: number, rightCoeff: number): void {
    this.renderer?.setChannelVolumes(leftCoeff, rightCoeff);
  }

  /**
   * 启用/禁用动态范围压缩
   */
  public setDrcEnabled(enabled: boolean): void {
    this.renderer?.setDrcEnabled(enabled);
  }

  /**
   * 设置 DRC 参数
   */
  public setDrcParams(thresholdDb: number, ratio: number, attackMs: number, releaseMs: number, makeupGainDb: number): void {
    this.renderer?.setDrcParams(thresholdDb, ratio, attackMs, releaseMs, makeupGainDb);
  }

  /**
   * 应用音频效果配置
   * @param eqEnabled EQ 是否启用
   * @param eqGains EQ 十段增益值
   * @param drcEnabled DRC 是否启用
   * @param drcThreshold DRC 阈值
   * @param drcRatio DRC 压缩比
   * @param drcAttack DRC 起始时间
   * @param drcRelease DRC 释放时间
   * @param drcMakeup DRC 补偿增益
   * @param volumeCoeffEnabled 音量系数是否启用
   * @param leftVolumeCoeff 左声道音量系数
   * @param rightVolumeCoeff 右声道音量系数
   */
  public applyAudioEffects(
    eqEnabled: boolean,
    eqGains: number[],
    drcEnabled: boolean,
    drcThreshold: number,
    drcRatio: number,
    drcAttack: number,
    drcRelease: number,
    drcMakeup: number,
    volumeCoeffEnabled: boolean,
    leftVolumeCoeff: number,
    rightVolumeCoeff: number
  ): void {
    // 应用 EQ
    if (eqEnabled) {
      this.setEqGainsLR(eqGains, eqGains);
    } else {
      this.setEqGainsLR([0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    }

    // 应用 DRC
    this.setDrcEnabled(drcEnabled);
    if (drcEnabled) {
      this.setDrcParams(drcThreshold, drcRatio, drcAttack, drcRelease, drcMakeup);
    }

    // 应用音量系数
    if (volumeCoeffEnabled) {
      this.setChannelVolumes(leftVolumeCoeff, rightVolumeCoeff);
    } else {
      this.setChannelVolumes(1.0, 1.0);
    }
  }
}

/** 导出 PlayerManager 全局单例 */
export const playerManager = new PlayerManager();
