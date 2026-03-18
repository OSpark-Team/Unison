/**
 * 设置项组件
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

@ComponentV2
export struct SettingItem {
  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** 设置项类型：switch（开关）、navigation（导航）、text（纯文本显示） */
  @Param type: 'switch' | 'navigation' | 'text' = 'switch';

  /** 设置项图标 */
  @Require @Param icon: Resource;

  /** 设置项标题 */
  @Param title: ResourceStr = '';

  /** 设置项描述 */
  @Param description: ResourceStr = '';

  /** 开关状态（仅 type='switch' 时使用） */
  @Param value: boolean = false;

  /** 右侧文本内容（仅 type='text' 时使用） */
  @Param rightText: ResourceStr = '';

  /** 是否为最后一项（用于控制 Divider 显示） */
  @Param isLast: boolean = false;

  /** 开关变化回调（仅 type='switch' 时使用） */
  @Param onChange: (value: boolean) => void = () => {};

  /** 点击回调（仅 type='navigation' 时使用） */
  @Param onItemClick: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        if (this.icon!=undefined){
          // 左侧图标
          SymbolGlyph(this.icon)
            .fontSize(24)
            .fontColor([$r('app.color.text_secondary')])
        }


        // 中间文本（标题 + 描述）
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)

          if (this.description && this.description.toString().length > 0) {
            Text(this.description)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)

        // 右侧内容（根据类型显示不同组件）
        if (this.type === 'switch') {
          // 类型 1：开关类型
          Toggle({ type: ToggleType.Switch, isOn: this.value })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.onChange(isOn);
            })
            .animation({
              duration: 300,
              curve: Curve.EaseInOut
            })
        } else if (this.type === 'navigation') {
          // 类型 2：导航类型
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([$r('app.color.text_tertiary')])
        } else if (this.type === 'text') {
          // 类型 3：纯文本显示类型
          Text(this.rightText)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .borderRadius(this.settingModel.radiusItem)
      .clip(true)
      .stateStyles({
        normal: {
          .backgroundColor(Color.Transparent)
        },
        pressed: {
          .backgroundColor(this.type === 'navigation' ? 'rgba(0, 0, 0, 0.1)' : Color.Transparent)
        }
      })
      .onClick(() => {
        if (this.type === 'navigation') {
          this.onItemClick();
        }
      })
      .clickEffect(this.type === 'navigation' ? { level: ClickEffectLevel.LIGHT, scale: 0.98 } : undefined)
      .hoverEffect(this.type === 'navigation' ? HoverEffect.Highlight : undefined)
      .animation({
        duration: 200,
        curve: Curve.EaseInOut
      })

      // 分隔线（非最后一项时显示）
      if (!this.isLast) {
        Divider()
          .strokeWidth(1)
          .opacity(this.settingModel.opacityWeak)
          .color($r('app.color.divider'))
          .margin({ left: 52, right: 16 })
      }
    }
    .width('100%')
  }
}
