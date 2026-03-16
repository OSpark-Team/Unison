/**
 * 播放器相关持久化 ViewModel
 * - 睡眠定时器（定时播放/定时暂停）
 */

@ObservedV2
export default class PlayerViewModel {
  /** 睡眠定时器结束时间戳（ms）。0 表示未开启 */
  @Trace sleepTimerEndAtMs: number = 0;

  /** 设置/取消睡眠定时器（分钟）。0 = 取消 */
  setSleepTimerMinutes(minutes: number): void {
    if (minutes <= 0) {
      this.sleepTimerEndAtMs = 0;
      return;
    }
    this.sleepTimerEndAtMs = Date.now() + minutes * 60 * 1000;
  }

  /** 取消睡眠定时器 */
  cancelSleepTimer(): void {
    this.sleepTimerEndAtMs = 0;
  }
}
