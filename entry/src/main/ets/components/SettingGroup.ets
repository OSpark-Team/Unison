/**
 * 设置分组组件
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

@ComponentV2
export struct SettingGroup {
  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  /** 分组标题（可选） */
  @Param title?: ResourceStr = "";

  @Builder
  slotBuilder() {
  };

  @BuilderParam content: () => void = this.slotBuilder;

  build() {
    Column({ space: 0 }) {
      // 分组标题（如果有）
      if (this.title) {
        Text(this.title)
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16, top: 8, bottom: 4 })
          .width("100%")
          .textAlign(TextAlign.Start)
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 })
            .combine(TransitionEffect.translate({ x: -10 }).animation({ duration: 300 })))
      }

      // 内容区域
      Column({ space: 0 }) {
        this.content()
      }
      .width('100%')
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(this.settingModel.radiusCard)
      .padding(8)
      .transition(TransitionEffect.OPACITY.animation({ duration: 400 })
        .combine(TransitionEffect.translate({ y: 20 }).animation({ duration: 400, curve: Curve.EaseOut })))
    }
    .width('100%')
    .margin({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}
