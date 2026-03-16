import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

@ComponentV2
export struct ModuleCard {
  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  @Param moduleName: ResourceStr = "Module Card"
  @Param moduleColor: ResourceStr = "#ff6e2b2b"

  build() {
    Column() {
      Stack() {
        Row() {
          Text(this.moduleName)
            .fontColor($r('app.color.label_text_color'))
            .fontSize(26)
            .fontWeight(700)
        }
        .position({ left: 0, top: 0 })
        .width("100%")
        .justifyContent(FlexAlign.Start)

        Column() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r("sys.symbol.arrow_right"))
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), 300)
              .fontColor([$r('app.color.label_icon_color'), $r('app.color.label_icon_color')])
              .fontSize(20)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePressStrong })
              .fontWeight(FontWeight.Bold)
          }
          .height("100%")
          .width("100%")
          .backgroundColor('rgba(255, 255, 255, 0.2)')
        }
        .width(36)
        .height(36)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePressTiny })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .position({ right: 0, bottom: 0 })
        .zIndex(1)
      }
      .width("100%")
      .height("100%")
    }
    .borderRadius(this.settingModel.radiusModule)
    .backgroundColor(this.moduleColor)
    .shadow({
      color: 'rgba(0, 0, 0, 0.08)',
      radius: 12,
      offsetX: 0,
      offsetY: 2,
    })
    .padding(16)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
    .hoverEffect(HoverEffect.Highlight)
  }
}
