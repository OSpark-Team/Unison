/**
 * EQ 均衡器编辑器组件
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { EqBandLabels, EqPreset, EqPresets } from '../common/AudioEffectsPresets';

const EQ_USER_PRESET_PREFIX: string = 'USER:';

@ComponentV2
export struct EqEditor {
  /** 系统设置 ViewModel */
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** EQ 是否启用 */
  @Param @Require eqEnabled: boolean = false;

  /** 当前 EQ 预设 ID */
  @Param @Require eqPresetId: string = 'Default';

  /** EQ 是否处于自定义状态 */
  @Param eqIsCustom: boolean = false;

  /** 当前选中的用户 EQ 预设名称（空表示未选中） */
  @Param eqSelectedUserPresetName: string = '';

  /** EQ 十段增益值 */
  @Param @Require eqGains: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  /** EQ 启用状态变化回调 */
  @Param onEnabledChange: (enabled: boolean) => void = () => {};

  /** 预设变化回调 */
  @Param onPresetChange: (presetId: string, gains: number[]) => void = () => {};

  /** 增益值变化回调 */
  @Param onGainsChange: (gains: number[]) => void = () => {};

  /** 保存当前为用户预设 */
  @Param onSavePreset: () => void = () => {};

  /** 删除当前选中的用户预设 */
  @Param onDeletePreset: () => void = () => {};

  /** 是否允许删除（仅当选中用户预设时） */
  @Param canDeleteUserPreset: boolean = false;

  /** 用户预设名称列表 */
  @Param userPresetNames: string[] = [];

  /** 用户预设 gains 列表 */
  @Param userPresetGains: number[][] = [];

  /** 预设列表 */
  private presetList: EqPreset[] = EqPresets.getAll();

  /** 频段标签 */
  private bandLabels: string[] = EqBandLabels.ALL;

  build() {
    Column({ space: 0 }) {
      // 开关和预设选择
      this.buildHeader();

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .margin({ top: 8, bottom: 24 });

      // 十段增益滑块 (无滚动条，自适应等分)
      if (this.eqEnabled) {
        this.buildBandsEditor();
      } else {
        this.buildDisabledPlaceholder();
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildHeader() {
    Row({ space: 12 }) {
      // EQ 开关
      Toggle({ type: ToggleType.Switch, isOn: this.eqEnabled })
        .selectedColor($r('app.color.primary_color'))
        .onChange((isOn: boolean) => {
          this.onEnabledChange(isOn);
        })
        .animation({ duration: 300, curve: Curve.EaseInOut });

      Column({ space: 4 }) {
        Text($r('app.string.audio_effects_eq'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium);

        Text($r('app.string.audio_effects_eq_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 });

    // 预设选择器
    if (this.eqEnabled) {
      Row({ space: 8 }) {
        Text($r('app.string.audio_effects_preset'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'));

        Blank();

        Row({ space: 8 }) {
          // 新增（保存）预设
          Button() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(16)
              .fontColor([$r('app.color.primary_color')]);
          }
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.background_secondary'))
          .width(32)
          .height(32)
          .onClick(() => {
            this.onSavePreset();
          })

          // 删除预设（仅用户预设可删）
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(16)
              .fontColor([this.canDeleteUserPreset ? $r('app.color.error') : $r('app.color.text_tertiary')]);
          }
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.background_secondary'))
          .width(32)
          .height(32)
          .enabled(this.canDeleteUserPreset)
          .onClick(() => {
            this.onDeletePreset();
          })

          // 右侧 Select
          this.buildPresetSelector();
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 });
    }
  }

  @Builder
  private buildPresetSelector() {
    Row({ space: 4 }) {
      Text(
        this.eqIsCustom
          ? $r('app.string.audio_effects_custom')
          : (this.eqSelectedUserPresetName.length > 0
            ? $r('app.string.audio_effects_custom_named', this.eqSelectedUserPresetName)
            : EqPresets.getById(this.eqPresetId).label)
      )
        .fontSize(14)
        .fontColor($r('app.color.primary_color'));

      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontColor([$r('app.color.primary_color')]);
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(this.settingModel.radiusItem)
    .bindMenu(this.buildPresetMenuItems())
  }

  @Builder
  private buildPresetMenuItems() {
    Menu() {
      // 官方预设
      ForEach(this.presetList, (preset: EqPreset) => {
        MenuItem({
          content: preset.label,
          labelInfo: ''
        })
          .onClick(() => {
            if (this.eqPresetId !== preset.id) {
              // 传递时解包成普通数组
              this.onPresetChange(preset.id, [...preset.gainsDb]);
            }
          })
      })

      // 用户预设
      ForEach(this.userPresetNames, (name: string, index: number) => {
        MenuItem({
          content: $r('app.string.audio_effects_custom_named', name),
          labelInfo: ''
        })
          .onClick(() => {
            if (index >= 0 && index < this.userPresetGains.length) {
              this.onPresetChange(EQ_USER_PRESET_PREFIX + name, [...this.userPresetGains[index]]);
            }
          })
      })
    }
  }

  @Builder
  private buildBandsEditor() {
    // 移除 Scroll，直接使用 Row 配合 layoutWeight(1) 平分空间
    Row() {
      ForEach(this.bandLabels, (label: string, index: number) => {
        this.buildBandSlider(index, label);
      })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 16, bottom: 16 })
  }

  @Builder
  private buildBandSlider(index: number, label: string) {
    Column({ space: 6 }) {
      // 顶部数值
      Text(this.formatGain(this.eqGains[index]))
        .fontSize(10)
        .fontColor($r('app.color.primary_color'))
        .fontWeight(FontWeight.Medium)
        .height(14);

      // 竖向滑块，自适应高度
      Slider({
        value: this.eqGains[index],
        min: -12,
        max: 12,
        step: 0.5,
        style: SliderStyle.InSet,
        direction: Axis.Vertical,
        reverse: true
      })
        .blockColor(Color.White)
        .selectedColor($r('app.color.primary_color'))
        .trackColor($r('app.color.progress_track'))
        .trackThickness(14)
        .layoutWeight(1)
        .onChange((value: number) => {
          const newGains = [...this.eqGains];
          newGains[index] = value;
          this.onGainsChange(newGains);
        });

      // 底部频段标签
      Text(label)
        .fontSize(9)
        .fontColor($r('app.color.text_secondary'))
        .height(14);
    }
    .layoutWeight(1)
    .height(240)
  }

  @Builder
  private buildDisabledPlaceholder() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')]);

      Text($r('app.string.audio_effects_eq_disabled'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'));
    }
    .width('100%')
    .height(200)
    .justifyContent(FlexAlign.Center);
  }

  private formatGain(value: number): string {
    const sign = value > 0 ? '+' : '';
    return `${sign}${Math.round(value)}`;
  }
}
