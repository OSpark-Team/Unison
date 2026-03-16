/**
 * DRC 动态范围压缩编辑器组件
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { DrcPreset, DrcPresets } from '../common/AudioEffectsPresets';

const DRC_USER_PRESET_PREFIX: string = 'USER:';

@ComponentV2
export struct DrcEditor {
  /** 系统设置 ViewModel */
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** DRC 是否启用 */
  @Param @Require drcEnabled: boolean = false;

  /** 当前 DRC 预设 ID */
  @Param @Require drcPresetId: string = 'Default';

  /** DRC 是否处于自定义状态 */
  @Param drcIsCustom: boolean = false;

  /** 当前选中的用户 DRC 预设名称（空表示未选中） */
  @Param drcSelectedUserPresetName: string = '';

  /** DRC 阈值 (dB) */
  @Param @Require drcThreshold: number = -12;

  /** DRC 压缩比 */
  @Param @Require drcRatio: number = 2.0;

  /** DRC 起始时间 (ms) */
  @Param @Require drcAttack: number = 10;

  /** DRC 释放时间 (ms) */
  @Param @Require drcRelease: number = 100;

  /** DRC 补偿增益 (dB) */
  @Param @Require drcMakeup: number = 0;

  /** DRC 启用状态变化回调 */
  @Param onEnabledChange: (enabled: boolean) => void = () => {};

  /** 预设变化回调 */
  @Param onPresetChange: (presetId: string, threshold: number, ratio: number, attack: number, release: number, makeup: number) => void = () => {};

  /** 参数变化回调 */
  @Param onParamsChange: (threshold: number, ratio: number, attack: number, release: number, makeup: number) => void = () => {};

  /** 保存当前为用户预设 */
  @Param onSavePreset: () => void = () => {};

  /** 删除当前选中的用户预设 */
  @Param onDeletePreset: () => void = () => {};

  /** 是否允许删除（仅当选中用户预设时） */
  @Param canDeleteUserPreset: boolean = false;

  /** 用户预设名称列表 */
  @Param userPresetNames: string[] = [];
  @Param userPresetThreshold: number[] = [];
  @Param userPresetRatio: number[] = [];
  @Param userPresetAttack: number[] = [];
  @Param userPresetRelease: number[] = [];
  @Param userPresetMakeup: number[] = [];

  /** 预设列表 */
  private presetList: DrcPreset[] = DrcPresets.getAll();

  build() {
    Column({ space: 0 }) {
      // 开关和预设选择
      this.buildHeader();

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .margin({ top: 8, bottom: 24 });

      // 参数调节
      if (this.drcEnabled) {
        this.buildParamsEditor();
      } else {
        this.buildDisabledPlaceholder();
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start) // 显式设置为顶部对齐
  }

  @Builder
  private buildHeader() {
    Row({ space: 12 }) {
      // DRC 开关
      Toggle({ type: ToggleType.Switch, isOn: this.drcEnabled })
        .selectedColor($r('app.color.primary_color'))
        .onChange((isOn: boolean) => {
          this.onEnabledChange(isOn);
        })
        .animation({ duration: 300, curve: Curve.EaseInOut });

      Column({ space: 4 }) {
        Text($r('app.string.audio_effects_drc'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium);

        Text($r('app.string.audio_effects_drc_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 });

    // 预设选择器
    if (this.drcEnabled) {
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

          // 删除预设
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
        this.drcIsCustom
          ? $r('app.string.audio_effects_custom')
          : (this.drcSelectedUserPresetName.length > 0
            ? $r('app.string.audio_effects_custom_named', this.drcSelectedUserPresetName)
            : DrcPresets.getById(this.drcPresetId).label)
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
      ForEach(this.presetList, (preset: DrcPreset) => {
        MenuItem({
          content: preset.label,
          labelInfo: ''
        })
          .onClick(() => {
            if (this.drcPresetId !== preset.id) {
              this.onPresetChange(
                preset.id,
                preset.params.threshold,
                preset.params.ratio,
                preset.params.attack,
                preset.params.release,
                preset.params.makeup
              );
            }
          })
      })

      ForEach(this.userPresetNames, (name: string, index: number) => {
        MenuItem({
          content: $r('app.string.audio_effects_custom_named', name),
          labelInfo: ''
        })
          .onClick(() => {
            if (index >= 0 && index < this.userPresetThreshold.length) {
              this.onPresetChange(
                DRC_USER_PRESET_PREFIX + name,
                this.userPresetThreshold[index],
                this.userPresetRatio[index],
                this.userPresetAttack[index],
                this.userPresetRelease[index],
                this.userPresetMakeup[index]
              );
            }
          })
      })
    }
  }

  @Builder
  private buildParamsEditor() {
    Column({ space: 24 }) {
      // 为解决 ArkUI 原生数据绑定陷阱，这里不用通用 Builder 传值，而是直接读取实例属性
      this.buildThresholdSlider();
      this.buildRatioSlider();
      this.buildAttackSlider();
      this.buildReleaseSlider();
      this.buildMakeupSlider();
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private buildThresholdSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.audio_effects_drc_threshold')).fontSize(14).fontColor($r('app.color.text_primary'));
        Blank();
        Text(`${this.drcThreshold.toFixed(0)} dB`).fontSize(14).fontColor($r('app.color.primary_color')).fontWeight(FontWeight.Medium);
      }.width('100%');

      Slider({ value: this.drcThreshold, min: -60, max: 0, step: 1, style: SliderStyle.InSet })
        .blockColor(Color.White).selectedColor($r('app.color.primary_color')).trackColor($r('app.color.progress_track')).trackThickness(16).width('100%')
        .onChange((newValue: number) => { this.onParamsChange(newValue, this.drcRatio, this.drcAttack, this.drcRelease, this.drcMakeup); });
    }.width('100%');
  }

  @Builder
  private buildRatioSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.audio_effects_drc_ratio')).fontSize(14).fontColor($r('app.color.text_primary'));
        Blank();
        Text(`${this.drcRatio.toFixed(1)}:1`).fontSize(14).fontColor($r('app.color.primary_color')).fontWeight(FontWeight.Medium);
      }.width('100%');

      Slider({ value: this.drcRatio, min: 1, max: 20, step: 0.5, style: SliderStyle.InSet })
        .blockColor(Color.White).selectedColor($r('app.color.primary_color')).trackColor($r('app.color.progress_track')).trackThickness(16).width('100%')
        .onChange((newValue: number) => { this.onParamsChange(this.drcThreshold, newValue, this.drcAttack, this.drcRelease, this.drcMakeup); });
    }.width('100%');
  }

  @Builder
  private buildAttackSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.audio_effects_drc_attack')).fontSize(14).fontColor($r('app.color.text_primary'));
        Blank();
        Text(`${this.drcAttack.toFixed(1)} ms`).fontSize(14).fontColor($r('app.color.primary_color')).fontWeight(FontWeight.Medium);
      }.width('100%');

      Slider({ value: this.drcAttack, min: 0.1, max: 100, step: 0.5, style: SliderStyle.InSet })
        .blockColor(Color.White).selectedColor($r('app.color.primary_color')).trackColor($r('app.color.progress_track')).trackThickness(16).width('100%')
        .onChange((newValue: number) => { this.onParamsChange(this.drcThreshold, this.drcRatio, newValue, this.drcRelease, this.drcMakeup); });
    }.width('100%');
  }

  @Builder
  private buildReleaseSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.audio_effects_drc_release')).fontSize(14).fontColor($r('app.color.text_primary'));
        Blank();
        Text(`${this.drcRelease.toFixed(0)} ms`).fontSize(14).fontColor($r('app.color.primary_color')).fontWeight(FontWeight.Medium);
      }.width('100%');

      Slider({ value: this.drcRelease, min: 10, max: 1000, step: 10, style: SliderStyle.InSet })
        .blockColor(Color.White).selectedColor($r('app.color.primary_color')).trackColor($r('app.color.progress_track')).trackThickness(16).width('100%')
        .onChange((newValue: number) => { this.onParamsChange(this.drcThreshold, this.drcRatio, this.drcAttack, newValue, this.drcMakeup); });
    }.width('100%');
  }

  @Builder
  private buildMakeupSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.audio_effects_drc_makeup')).fontSize(14).fontColor($r('app.color.text_primary'));
        Blank();
        Text(`+${this.drcMakeup.toFixed(1)} dB`).fontSize(14).fontColor($r('app.color.primary_color')).fontWeight(FontWeight.Medium);
      }.width('100%');

      Slider({ value: this.drcMakeup, min: 0, max: 24, step: 0.5, style: SliderStyle.InSet })
        .blockColor(Color.White).selectedColor($r('app.color.primary_color')).trackColor($r('app.color.progress_track')).trackThickness(16).width('100%')
        .onChange((newValue: number) => { this.onParamsChange(this.drcThreshold, this.drcRatio, this.drcAttack, this.drcRelease, newValue); });
    }.width('100%');
  }

  @Builder
  private buildDisabledPlaceholder() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.waveform'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')]);

      Text($r('app.string.audio_effects_drc_disabled'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'));
    }
    .width('100%')
    .height(200)
    .justifyContent(FlexAlign.Center);
  }
}
