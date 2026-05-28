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
 * 内部逻辑状态枚举。
 * 与底层 renderer 的物理状态分离：renderer 状态是异步反映，逻辑状态由 PlayerManager 显式控制。
 */
enum LogicState {
  IDLE = 0,       // 空闲/无音源
  LOADING = 1,    // 正在加载新音源（解码器创建到 ready 完成之间）
  READY = 2,      // 加载完成、未启动播放
  PLAYING = 3,    // 播放中
  PAUSED = 4,     // 暂停
  STOPPED = 5,    // 停止
  COMPLETED = 6,  // 播放完成（自然结束）
}

/**
 * PlayerManager - 音频播放核心管理类
 *
 * @description 职责范围：
 * 1. 管理 Free-PCM 播放管线的完整生命周期（加载、渲染、销毁）。
 * 2. 自动与 AVSessionManager 联动，确保系统媒体中心状态同步。
 * 3. 支持多订阅者模式，允许多个页面或模块独立监听播放状态。
 * 4. 内置异步竞态保护（sequence + load mutex）。
 *
 * @remarks
 * 重要状态约定：
 * - `logicState` 与 `renderer.getState()` 双轨：逻辑状态用于决策，物理状态用于驱动；
 * - `loadSeq` 在每次 load 时自增，所有异步回调必须校验自己的 seq 与当前 seq 一致；
 * - `completionWatchdog` 只在 LogicState === PLAYING 时检测完成，防止暂停误判。
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

  /** 逻辑状态机 */
  private logicState: LogicState = LogicState.IDLE;
  /** 是否已触发过当前音源的完成回调 */
  private completionFired = false;
  /** 播放进度监控定时器 */
  private completionTimer: number = -1;

  /** load 序列号，每次 load 自增，用于拦截过时异步回调 */
  private loadSeq = 0;
  /** 当前活跃的 load seq（用于 watchdog 与脏数据判定） */
  private activeLoadSeq = 0;
  /** load 互斥锁：串行化 load 调用，避免 cleanup 之间的竞态 */
  private loadGuard: Promise<void> = Promise.resolve();

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
   *
   * @description 通过 loadGuard 串行化所有 load 调用，避免并发 cleanup/decoder 创建造成的状态错乱。
   * 旧的 in-flight load 通过 loadSeq 比对自动失效（不会写入 streamInfo / prepared 等）。
   *
   * @param string source - 音频资源的 URI 或本地路径
   * @returns Promise<void>
   */
  public async load(source: string): Promise<void> {
    // 抢占式取消：先递增 seq，让任何在途的旧回调立即作废
    this.loadSeq++;
    const currentSeq = this.loadSeq;

    // 排队等待上一个 load 完成（cleanup → 解码器准备）
    const prevGuard = this.loadGuard;
    let releaseGuard: () => void = () => {};
    this.loadGuard = new Promise<void>((resolve) => {
      releaseGuard = resolve;
    });
    try {
      await prevGuard;
    } catch (_e) {
      // prevGuard 不会 reject，保护性处理
    }

    // 等待解锁后再次确认：若期间又来新 load，本次直接放弃
    if (this.loadSeq !== currentSeq) {
      releaseGuard();
      return;
    }

    try {
      await this._loadInternal(source, currentSeq);
    } finally {
      releaseGuard();
    }
  }

  private async _loadInternal(source: string, currentSeq: number): Promise<void> {
    await this.cleanup();
    if (this.loadSeq !== currentSeq) {
      return;
    }

    this.logicState = LogicState.LOADING;

    // 创建解码流
    const dec = this.decoderTool.createStreamDecoder(source, {}, {
      onError: (e: Error) => {
        if (this.loadSeq !== currentSeq) {
          return;
        }
        this.dispatch(cb => cb.onError?.(e));
      },
    });
    this.decoder = dec;

    try {
      const info = await dec.ready;
      // 竞态检查：如果序列号已更新，说明 load 被重新调用，丢弃当前陈旧请求
      if (this.loadSeq !== currentSeq) {
        try { dec.close(); } catch (_e) {}
        return;
      }

      this.streamInfo = info;
      this.completionFired = false;
      this.activeLoadSeq = currentSeq;
      this.logicState = LogicState.READY;

      //  通知内部订阅者
      this.dispatch(cb => cb.onDurationChange?.(info.durationMs));
      this.dispatch(cb => cb.onSeek?.(0));

      // 监听流结束（仅记录，watchdog 真正启动延后到 play 成功后）
      dec.done.catch((e: Error) => {
        if (this.loadSeq !== currentSeq) return;
        this.dispatch(cb => cb.onError?.(e));
      });

    } catch (e) {
      if (this.loadSeq === currentSeq) {
        this.logicState = LogicState.IDLE;
        this.dispatch(cb => cb.onError?.(e as Error));
      }
    }
  }

  /**
   * 开始或恢复播放。
   * 同时更新系统 AVSession 状态为 PLAY。
   *
   * @remarks
   * 状态转换：
   * - READY → renderer.play(decoder, info) → PLAYING
   * - PAUSED → renderer.resume() → PLAYING
   * - STOPPED / COMPLETED → renderer.play(decoder, info) → PLAYING（视为重启）
   * - PLAYING → 直接返回（已在播放）
   * - LOADING / IDLE → 告警后返回
   */
  public async play(): Promise<void> {
    if (this.logicState === LogicState.LOADING || this.logicState === LogicState.IDLE) {
      Logger.warn(TAG, 'play called before prepared');
      return;
    }
    if (!this.decoder || !this.streamInfo) {
      Logger.warn(TAG, 'play called without decoder/streamInfo');
      return;
    }
    if (this.logicState === LogicState.PLAYING) {
      // 已经在播放，幂等返回，防止重启 renderer 导致音频中断
      return;
    }

    const prevLogicState = this.logicState;
    // 仅 PAUSED 可走 resume；READY/STOPPED/COMPLETED 都需要 fresh start
    const canResume = prevLogicState === LogicState.PAUSED;
    const playedSeq = this.activeLoadSeq;

    // 乐观切换：先进入 PLAYING，watchdog 才会工作；失败时回滚
    this.logicState = LogicState.PLAYING;

    try {
      if (canResume) {
        await this.renderer.resume();
      } else {
        await this.renderer.play(this.decoder, this.streamInfo);
      }

      // 启动完成监控（只此一处启动入口）
      this.startCompletionWatchdog();

      // 同步系统状态
      avSessionManager.syncPlaybackState(
        avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        canResume ? this.renderer.getCurrentPosition() : 0
      );

      // 与 UI 同步播放状态（仅在确认成功后写入）
      this.writeExternalPlayingState(true);
    } catch (e) {
      // 失败时回滚逻辑状态，避免 watchdog 在不正确状态下运行
      // 若期间已被新 load 取代（activeLoadSeq 变化），不回滚以免覆盖新状态
      if (this.activeLoadSeq === playedSeq) {
        this.logicState = prevLogicState;
      }
      this.writeExternalPlayingState(false);
      this.dispatch(cb => cb.onError?.(e as Error));
    }
  }

  /**
   * 暂停播放。
   * 同时更新系统 AVSession 状态为 PAUSE。
   */
  public async pause(): Promise<void> {
    try {
      await this.renderer?.pause();
      this.logicState = LogicState.PAUSED;
      avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE, this.renderer.getCurrentPosition());
    } catch (e) {
      this.dispatch(cb => cb.onError?.(e as Error));
    } finally {
      // 暂停后状态确定为非播放（无论 renderer 调用是否成功，UI 应反映用户意图）
      this.writeExternalPlayingState(false);
    }
  }

  /**
   * 停止播放（保留当前音源）。
   */
  public async stop(): Promise<void> {
    try {
      await this.renderer?.stop();
      this.stopCompletionWatchdog();
      this.logicState = LogicState.STOPPED;
      avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
    } catch (e) {
      this.dispatch(cb => cb.onError?.(e as Error));
    } finally {
      this.writeExternalPlayingState(false);
    }
  }

  /**
   * 跳转至指定进度。
   * @param number positionMs - 目标位置（毫秒）
   */
  public async seek(positionMs: number): Promise<void> {
    if (this.logicState === LogicState.IDLE || this.logicState === LogicState.LOADING) {
      return;
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

  /**
   * @returns boolean 当前音频资源是否已准备完成
   * @remarks 与旧版 `prepared` 字段语义一致：只要 decoder/streamInfo 仍可用且不在加载中即返回 true。
   * 这样 SongPlayerManager.playCurrentSongOrResume 在 STOPPED/COMPLETED 状态下也能复用既有解码器，
   * 避免不必要的重新加载与网络请求。
   */
  public isPrepared(): boolean {
    return this.decoder !== null
      && this.streamInfo !== null
      && this.logicState !== LogicState.IDLE
      && this.logicState !== LogicState.LOADING;
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
    this.completionFired = false;
    this.activeLoadSeq = 0;
    this.logicState = LogicState.IDLE;
  }

  /**
   * 启动播放完成监控。
   *
   * @remarks
   * 严格触发条件（任一不满足都跳过）：
   * 1. 逻辑状态必须是 PLAYING（修复关键 bug：暂停时不再误触发 completion）；
   * 2. 物理 renderer 状态必须是 STATE_RUNNING；
   * 3. activeLoadSeq 必须有效（=0 视为无活跃音源）；
   * 4. duration > 0；
   * 5. position 必须在 [0, dur + 200] 范围内（200ms 是 PCM 末尾微小偏差容差）；
   * 6. 接近结尾（>= dur - 50）。
   * @private
   */
  private startCompletionWatchdog(): void {
    if (this.completionTimer !== -1) return;

    this.completionTimer = setInterval(async () => {
      if (this.completionFired || !this.renderer) return;
      // 必须处于逻辑播放状态
      if (this.logicState !== LogicState.PLAYING) return;
      // 必须有活跃音源
      if (this.activeLoadSeq === 0) return;
      // 物理状态必须为 RUNNING
      if (this.renderer.getState() !== audio.AudioState.STATE_RUNNING) return;

      const dur = this.getDuration();
      const pos = this.getCurrentPosition();

      // 无效时长，跳过检查
      if (dur <= 0) return;
      // 异常 position（旧流脏数据或解码器尚未对齐）
      if (pos < 0 || pos > dur + 200) return;

      // 距离结束小于 50ms 视为完成
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
    this.logicState = LogicState.COMPLETED;

    this.dispatch(cb => cb.onCompleted?.());
    // 通知系统媒体中心状态变更为暂停/结束
    avSessionManager.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
  }

  /**
   * 将播放/暂停状态同步到全局 AppStorageV2（供悬浮 UI 使用）。
   * 集中写入，避免在多个分支重复书写且容易遗漏。
   * @private
   */
  private writeExternalPlayingState(playing: boolean): void {
    try {
      const flag = AppStorageV2.connect(
        isPlaying,
        'isPlaying',
        () => new isPlaying(),
      )!;
      flag.isPlaying = playing;
    } catch (e) {
      // 写状态失败不应影响主流程
      Logger.warn(TAG, `Failed to sync external isPlaying flag: ${JSON.stringify(e)}`);
    }
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
