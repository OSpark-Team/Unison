import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import Logger from '../utils/Logger';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'AVSessionManager';

/**
 * AVSession 外部指令回调接口
 * 用于解耦播放器逻辑，调用方按需实现并注册
 */
export interface SessionCallbacks {
  onPlay?: () => void;
  onPause?: () => void;
  onStop?: () => void;
  onSeek?: (positionMs: number) => void;
  onPlayNext?: () => void;
  onPlayPrevious?: () => void;
  onSetLoopMode?: (mode: avSession.LoopMode) => void;
  onToggleFavorite?: (assetId: string) => void;
}

/**
 * AVSession 管理器
 *
 * @description 职责范围：
 * 1. 维护 AVSession 生命周期（创建/激活/销毁）。
 * 2. 响应系统媒体中心（控制栏、锁屏、穿戴设备）的交互指令。
 * 3. 同步播放器状态（进度、状态、元数据）至系统侧。
 * 4. 支持多订阅者模式：多个模块可独立注册/注销回调，互不影响。
 *
 * @example
* // 初始化
 * await avSessionManager.init(context);
 *
 * // 注册具名订阅者
 * avSessionManager.addSubscriber('player', { onPlay: () => player.play() });
 * avSessionManager.addSubscriber('logger', { onPlay: () => console.log('play triggered') });
 *
 * // 注销某个订阅者
 * avSessionManager.removeSubscriber('logger');
 */
export class AVSessionManager {
  private session: avSession.AVSession | null = null;

  /**
   * 多订阅者 Map：key 为订阅者唯一标识，value 为回调对象
   */
  private subscribers: Map<string, SessionCallbacks> = new Map();

  private cachedMetadata: avSession.AVMetadata | null = null;
  private currentPlaybackState: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;

  // ── 生命周期 ──────────────────────────────────────────────────────────────

  /**
   * 初始化 AVSession
   * @param context UIAbilityContext 上下文
   * @throws {Error} 当 AVSession 创建失败时抛出异常
   */
  public async init(context: common.UIAbilityContext): Promise<void> {
    if (this.session) return;

    try {
      this.session = await avSession.createAVSession(context, 'Unison Music', 'audio');
      await this.session.activate();

      // 初始状态同步
      await this.syncPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
      await this.syncLoopMode(avSession.LoopMode.LOOP_MODE_LIST);

      this.registerSessionListeners();
      if (deviceInfo.sdkApiVersion>22) {
        this.session.enableDesktopLyric(true)
      }
      Logger.info(TAG, 'init', 'AVSession successfully created and activated.');
    } catch (error) {
      Logger.error(TAG, 'init', `Failed to create AVSession: ${JSON.stringify(error)}`);
      throw new Error(`AVSession init failed: ${error}`);
    }
  }

  /**
   * 释放资源并销毁 Session
   * 建议在 UIAbility.onDestroy 中调用
   */
  public async destroy(): Promise<void> {
    if (!this.session) return;

    try {
      this.clearAllSubscribers();
      await this.session.destroy();
      this.session = null;
      this.cachedMetadata = null;
      Logger.info(TAG, 'destroy', 'AVSession destroyed successfully.');
    } catch (error) {
      Logger.error(TAG, 'destroy', `Failed: ${JSON.stringify(error)}`);
    }
  }
  // public setdesktopLyric(judge:boolean){
  //   this.session?.setDesktopLyricVisible(judge)
  // }
  // ── 多订阅者管理 ──────────────────────────────────────────────────────────

  /**
   * 注册一个具名订阅者
   * 若已存在相同 subscriberId，则覆盖更新
   * @param subscriberId 订阅者唯一标识（建议使用模块名，如 'player'、'logger'）
   * @param callbacks    该订阅者的回调对象
   */
  public addSubscriber(subscriberId: string, callbacks: SessionCallbacks): void {
    this.subscribers.set(subscriberId, callbacks);
    Logger.info(TAG, 'addSubscriber', `Subscriber "${subscriberId}" registered. Total: ${this.subscribers.size}`);
  }

  /**
   * 注销指定订阅者
   * @param subscriberId 订阅者唯一标识
   */
  public removeSubscriber(subscriberId: string): void {
    const deleted = this.subscribers.delete(subscriberId);
    if (deleted) {
      Logger.info(TAG, 'removeSubscriber', `Subscriber "${subscriberId}" removed. Total: ${this.subscribers.size}`);
    } else {
      Logger.warn(TAG, 'removeSubscriber', `Subscriber "${subscriberId}" not found.`);
    }
  }

  /**
   * 清空所有订阅者，防止内存泄漏或销毁时被误触发
   */
  public clearAllSubscribers(): void {
    this.subscribers.clear();
    Logger.info(TAG, 'clearAllSubscribers', 'All subscribers cleared.');
  }

  /**
   * 查询是否存在指定订阅者
   * @param subscriberId 订阅者唯一标识
   */
  public hasSubscriber(subscriberId: string): boolean {
    return this.subscribers.has(subscriberId);
  }

  /**
   * 获取当前所有订阅者 ID 列表（用于调试）
   */
  public getSubscriberIds(): string[] {
    return Array.from(this.subscribers.keys());
  }

  // ── 状态同步方法 ──────────────────────────────────────────────────────────

  /**
   * 同步当前播放状态到系统媒体中心
   * @param state      播放状态 (如：PLAYBACK_STATE_PLAY)
   * @param positionMs 当前播放进度（毫秒）
   */
  public async syncPlaybackState(
    state: avSession.PlaybackState,
    positionMs: number = -1
  ): Promise<void> {
    if (!this.session) return;

    this.currentPlaybackState = state;
    try {
      const playbackState: avSession.AVPlaybackState = {
        state,
        speed: 1.0,
      };

      if (positionMs !== -1) {
        playbackState.position = {
          elapsedTime: positionMs,
          updateTime: new Date().getTime()
        }
      }

      await this.session.setAVPlaybackState(playbackState);
    } catch (error) {
      Logger.error(TAG, 'syncPlaybackState', `Failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 获取当前 PlaybackState
   */
  public getCurrentPlaybackState(): avSession.PlaybackState {
    return this.currentPlaybackState;
  }

  /**
   * 同步当前循环模式
   * @param mode 循环模式
   */
  public async syncLoopMode(mode: avSession.LoopMode): Promise<void> {
    if (!this.session) return;
    try {
      await this.session.setAVPlaybackState({ loopMode: mode });
    } catch (error) {
      Logger.error(TAG, 'syncLoopMode', `Failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 更新歌曲元数据
   * @param metadata    歌曲信息（标题、艺术家、封面等）
   * @param shouldCache 是否缓存该元数据，以便后续增量更新（如更新歌词）
   */
  public async updateMetadata(
    metadata: avSession.AVMetadata,
    shouldCache: boolean = true
  ): Promise<void> {
    if (!this.session) return;
    try {
      if (shouldCache) {
        this.cachedMetadata = metadata;
      }
      await this.session.setAVMetadata(metadata);
    } catch (error) {
      Logger.error(TAG, 'updateMetadata', `123123123`);
    }
  }

  /**
   * 仅更新歌词
   * @param lyric 歌词文本
   */
  public async updateLyric(lyric: string): Promise<void> {
    if (!this.session || !this.cachedMetadata) return;
    try {
      this.cachedMetadata.lyric = lyric;
      await this.session.setAVMetadata(this.cachedMetadata);
    } catch (error) {
      Logger.error(TAG, 'updateLyric', `Failed: ${JSON.stringify(error)}`);
    }
  }

  // ── 内部逻辑 ──────────────────────────────────────────────────────────────

  /**
   * 向所有订阅者广播事件
   * @param invoke 对单个 SessionCallbacks 执行的调用函数
   * @private
   */
  private dispatch(invoke: (callbacks: SessionCallbacks) => void): void {
    this.subscribers.forEach((callbacks, id) => {
      try {
        invoke(callbacks);
      } catch (error) {
        Logger.error(TAG, 'dispatch', `Subscriber "${id}" threw an error: ${JSON.stringify(error)}`);
      }
    });
  }

  /**
   * 注册系统底层事件监听，并通过 dispatch 广播给所有订阅者
   * @private
   */
  private registerSessionListeners(): void {
    if (!this.session) return;

    const session = this.session;

    // 播放/暂停/停止
    session.on('play', () => this.dispatch(cb => cb.onPlay?.()));
    session.on('pause', () => this.dispatch(cb => cb.onPause?.()));
    session.on('stop', () => this.dispatch(cb => cb.onStop?.()));

    // 进度控制
    session.on('seek', (position: number) => this.dispatch(cb => cb.onSeek?.(position)));

    // 切歌
    session.on('playNext', () => this.dispatch(cb => cb.onPlayNext?.()));
    session.on('playPrevious', () => this.dispatch(cb => cb.onPlayPrevious?.()));

    // 循环模式
    session.on('setLoopMode', (mode: avSession.LoopMode) => {
      this.dispatch(cb => cb.onSetLoopMode?.(mode));
    });

    // 收藏控制
    session.on('toggleFavorite', (assetId: string) => {
      this.dispatch(cb => cb.onToggleFavorite?.(assetId));
    });
  }

  /**
   * 获取原生 Session 实例（仅用于特殊扩展场景）
   */
  public getRawSession(): avSession.AVSession | null {
    return this.session;
  }
}

/**
 * 导出 AVSessionManager 全局单例
 */
export const avSessionManager = new AVSessionManager();