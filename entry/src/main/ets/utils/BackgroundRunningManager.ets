import { Context, wantAgent } from "@kit.AbilityKit"
import { backgroundTaskManager } from "@kit.BackgroundTasksKit"
import { bundleManager } from '@kit.AbilityKit';
import Logger from "./Logger";

const TAG = 'BackgroundRunningManager';

/**
 * 后台长时任务管理类
 * * @description 主要职责：
 * 申请音频播放相关的长时任务，确保应用后台存活。
 * 管理 WantAgent 对象的创建。
 * 停止长时任务以节省系统资源。
 */
class BackgroundRunningManager {
  private context: Context | null = null;

  /**
   * 初始化管理器
   * @param Context context - 应用上下文 (建议使用 UIAbilityContext)
   */
  public init(context: Context): void {
    this.context = context
  }

  /**
   * 申请长时任务
   * * @description
   * 申请后台模式为 AUDIO_PLAYBACK 的长时任务。
   * 必须在 module.json5 的 abilities 中配置 ohos.permission.KEEP_BACKGROUND_RUNNING 权限，
   * 并且 backgroundModes 包含 audioPlayback。
   * * @returns Promise<void>
   */
  public async startBackgroundRunning(): Promise<void> {
    if (!this.context) {
      Logger.error(TAG, `Failed to start: Context is null. Call init() first.`);
      return;
    }

    try {
      let wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: "zone.yby.unison",
            abilityName: "EntryAbility",
          },
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      }

      const wantObj = await wantAgent.getWantAgent(wantAgentInfo)
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        wantObj
      )

      Logger.info(TAG, `Continuous task requested successfully (Mode: AUDIO_PLAYBACK).`);
    } catch (error) {
      Logger.error(TAG, `Request failed. Code: ${error.code}, Message: ${error.message}`);
    }
  }

  /**
   * 停止后台长时任务
   * * @param Context [ctx] - 可选上下文。若不传则使用初始化时的 context。
   * @returns {Promise<void>}
   */
  public async stopBackgroundRunning(): Promise<void> {

    if (!this.context) {
      Logger.error(TAG, `Failed to stop: Context is null. Call init() first.`);
      return;
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);

      Logger.info(TAG, `Continuous task stopped successfully.`);
    } catch (error) {
      Logger.error(TAG, `Stop failed. Code: ${error.code}, Message: ${error.message}`);
    }
  }

  /**
   * 释放资源
   * 建议在 Ability 销毁时调用
   */
  public release(): void {
    this.context = null;
    Logger.info(TAG, `Manager resources released.`);
  }
}

/**
 * 导出后台任务管理单例
 */
export const backgroundRunningManager = new BackgroundRunningManager();