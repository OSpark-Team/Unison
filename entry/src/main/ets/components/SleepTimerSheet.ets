/**
 * 睡眠定时器（定时播放/定时暂停）Sheet
 * - 预设：5/10/30/60/120 分钟
 * - 自定义：分钟（整数）
 * - 倒计时展示
 */

import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
import PlayerViewModel from '../viewmodel/PlayerViewModel';
import { songPlayerManager } from '../services/SongPlayerManager';

@ComponentV2
export struct SleepTimerSheet {
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  @Local playerModel: PlayerViewModel =
    PersistenceV2.connect(PlayerViewModel, 'PlayerViewModel', () => new PlayerViewModel())!;

  @Local nowMs: number = Date.now();
  private tickTimerId: number = -1;

  @Local customMinutesText: string = '';

  @Param onClose?: () => void = undefined;

  aboutToAppear(): void {
    this.startTick();
  }

  aboutToDisappear(): void {
    this.stopTick();
  }

  private startTick(): void {
    if (this.tickTimerId !== -1) return;
    this.tickTimerId = setInterval(() => {
      this.nowMs = Date.now();
    }, 1000);
  }

  private stopTick(): void {
    if (this.tickTimerId !== -1) {
      clearInterval(this.tickTimerId);
      this.tickTimerId = -1;
    }
  }

  private getRemainingMs(): number {
    const endAt = this.playerModel.sleepTimerEndAtMs;
    if (endAt <= 0) return 0;
    const remain = endAt - this.nowMs;
    return remain > 0 ? remain : 0;
  }

  private isEnabled(): boolean {
    return this.playerModel.sleepTimerEndAtMs > 0 && this.getRemainingMs() > 0;
  }

  private setMinutes(minutes: number): void {
    songPlayerManager.setSleepTimerMinutes(minutes);
    this.customMinutesText = '';
  }

  private cancel(): void {
    songPlayerManager.cancelSleepTimer();
  }

  private parseCustomMinutes(): number {
    const raw = this.customMinutesText.trim();
    if (raw.length === 0) return 0;
    const n = Number(raw);
    if (!Number.isFinite(n)) return 0;
    const m = Math.floor(n);
    return m > 0 ? m : 0;
  }

  private formatRemaining(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    const mm = minutes < 10 ? `0${minutes}` : `${minutes}`;
    const ss = seconds < 10 ? `0${seconds}` : `${seconds}`;

    if (hours > 0) {
      const hh = hours < 10 ? `0${hours}` : `${hours}`;
      return `${hh}:${mm}:${ss}`;
    }
    return `${mm}:${ss}`;
  }

  build() {
    Column({ space: 0 }) {
      this.buildHeader();

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Scroll() {
        Column({ space: 24 }) {
          Column({ space: 8 }) {
            Text(this.formatRemaining(this.getRemainingMs()))
              .fontSize(56)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isEnabled() ? $r('app.color.primary_color') : $r('app.color.text_primary'))
              .animation({ duration: 300, curve: Curve.EaseInOut })


            Text($r('app.string.sleep_timer_unit_hint'))
              .fontSize(14)
              .fontColor(this.isEnabled() ? $r('app.color.text_secondary') : '#66808080')
          }
          .width('100%')
          .padding({ top: 20, bottom: 12 })
          .alignItems(HorizontalAlign.Center)

          Column({ space: 12 }) {
            Text($r('app.string.sleep_timer_custom_title')) // 复用标题作小节区分
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Start)

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach([5, 10, 30, 60, 90, 120], (m: number) => {
                Button($r('app.string.sleep_timer_minutes', m))
                  .type(ButtonType.Normal)
                  .height(44)
                  .width('31%') // 一行三个，留出少量间隙
                  .margin({ bottom: 12 })
                  .backgroundColor($r('app.color.background_secondary'))
                  .fontColor($r('app.color.text_primary'))
                  .borderRadius(this.settingModel.radiusItem)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
                  .onClick(() => {
                    this.setMinutes(m);
                  });
              })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 24, right: 24 })


          Row() {
            TextInput({
              placeholder: $r('app.string.sleep_timer_custom_placeholder'),
              text: this.customMinutesText,
            })
              .layoutWeight(1)
              .height(48)
              .type(InputType.Number) // 限制唤起数字键盘
              .backgroundColor(Color.Transparent) // 透明背景，融入外层 Row
              .onChange((value: string) => {
                this.customMinutesText = value;
              })

            Divider().vertical(true).height(24).color('#33808080').margin({ left: 8, right: 8 })

            Button($r('app.string.sleep_timer_set'))
              .type(ButtonType.Normal)
              .height(48)
              .backgroundColor(Color.Transparent)
              .fontColor(this.parseCustomMinutes() > 0 ? $r('app.color.primary_color') : $r('app.color.text_secondary'))
              .enabled(this.parseCustomMinutes() > 0)
              .onClick(() => {
                const m = this.parseCustomMinutes();
                if (m > 0) {
                  this.setMinutes(m);
                }
              });
          }
          .width('calc(100% - 48vp)')
          .margin({ left: 24, right: 24 })
          .backgroundColor($r('app.color.background_secondary'))
          .borderRadius(this.settingModel.radiusItem)
          .border({ width: 1, color: '#1A808080' }) // 增加细微的描边增加质感

          Button($r('app.string.sleep_timer_cancel'))
            .type(ButtonType.Normal)
            .width('calc(100% - 48vp)')
            .height(48)
            .margin({ bottom: 32 })
            .backgroundColor(this.isEnabled() ? '#1AFF3B30' : $r('app.color.background_secondary'))
            .fontColor(this.isEnabled() ? '#FF3B30' : '#4D808080')
            .borderRadius(this.settingModel.radiusCardLarge)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
            .enabled(this.isEnabled())
            .onClick(() => {
              this.cancel();
            });
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius({ topLeft: 24, topRight: 24 })
    .clip(true)
  }

  @Builder
  private buildHeader() {
    Row({ space: 12 }) {
      Text($r('app.string.sleep_timer_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'));

      Blank();

      Button($r('app.string.close'))
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary'))
        .borderRadius(this.settingModel.radiusItem)
        .onClick(() => {
          if (this.onClose) {
            this.onClose();
          }
        });
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.background_card'))
    .alignItems(VerticalAlign.Center)
  }
}
