/**
 * 音量系数编辑器组件
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

@ComponentV2
export struct VolumeCoeffEditor {
  /** 系统设置 ViewModel */
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** 音量系数是否启用 */
  @Param @Require volumeCoeffEnabled: boolean = false;

  /** 左声道音量系数 (真实系数 0.0 - 2.0) */
  @Param @Require leftVolumeCoeff: number = 1.0;

  /** 右声道音量系数 (真实系数 0.0 - 2.0) */
  @Param @Require rightVolumeCoeff: number = 1.0;

  /** 启用状态变化回调 */
  @Param onEnabledChange: (enabled: boolean) => void = () => {};

  /** 音量系数变化回调 */
  @Param onVolumeCoeffChange: (left: number, right: number) => void = () => {};

  /**
   * 将 UI 滑块值 (0-100) 转换为非线性系数 (0.0-2.0)
   * 采用指数曲线增强低音量时的调整精度
   */
  private sliderToCoeff(sliderValue: number): number {
    const normalized = sliderValue / 100.0;
    return Math.pow(normalized, 2) * 2.0;
  }

  /**
   * 将非线性系数 (0.0-2.0) 还原为 UI 滑块值 (0-100)
   */
  private coeffToSlider(coeff: number): number {
    const clampedCoeff = Math.max(0, Math.min(2.0, coeff));
    const normalized = Math.sqrt(clampedCoeff / 2.0);
    return normalized * 100.0;
  }

  build() {
    Column({ space: 0 }) {
      // 开关
      this.buildHeader();

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .margin({ top: 8, bottom: 24 });

      // 音量系数调节
      if (this.volumeCoeffEnabled) {
        this.buildCoeffEditor();
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
      // 音量系数开关
      Toggle({ type: ToggleType.Switch, isOn: this.volumeCoeffEnabled })
        .selectedColor($r('app.color.primary_color'))
        .onChange((isOn: boolean) => {
          this.onEnabledChange(isOn);
        })
        .animation({ duration: 300, curve: Curve.EaseInOut });

      Column({ space: 4 }) {
        Text($r('app.string.audio_effects_volume_coeff'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium);

        Text($r('app.string.audio_effects_volume_coeff_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 });
  }

  @Builder
  private buildCoeffEditor() {
    Column({ space: 24 }) {
      // 左声道（直接读取 this.leftVolumeCoeff，保留响应式）
      this.buildLeftCoeffSlider();

      // 右声道（直接读取 this.rightVolumeCoeff，保留响应式）
      this.buildRightCoeffSlider();

      // 快捷平衡按钮
      this.buildBalanceButtons();
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private buildLeftCoeffSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.audio_effects_volume_left'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'));
        Blank();
        Text(this.formatCoeff(this.leftVolumeCoeff))
          .fontSize(14)
          .fontColor($r('app.color.primary_color'))
          .fontWeight(FontWeight.Medium);
      }
      .width('100%');

      Slider({
        value: this.coeffToSlider(this.leftVolumeCoeff),
        min: 0,
        max: 100,
        step: 0.1,
        style: SliderStyle.InSet
      })
        .blockColor(Color.White)
        .selectedColor($r('app.color.primary_color'))
        .trackColor($r('app.color.progress_track'))
        .trackThickness(16)
        .width('100%')
        .onChange((newSliderValue: number) => {
          const newCoeff = this.sliderToCoeff(newSliderValue);
          this.onVolumeCoeffChange(newCoeff, this.rightVolumeCoeff);
        });
    }
    .width('100%');
  }

  @Builder
  private buildRightCoeffSlider() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.audio_effects_volume_right'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'));
        Blank();
        Text(this.formatCoeff(this.rightVolumeCoeff))
          .fontSize(14)
          .fontColor($r('app.color.primary_color'))
          .fontWeight(FontWeight.Medium);
      }
      .width('100%');

      Slider({
        value: this.coeffToSlider(this.rightVolumeCoeff),
        min: 0,
        max: 100,
        step: 0.1,
        style: SliderStyle.InSet
      })
        .blockColor(Color.White)
        .selectedColor($r('app.color.primary_color'))
        .trackColor($r('app.color.progress_track'))
        .trackThickness(16)
        .width('100%')
        .onChange((newSliderValue: number) => {
          const newCoeff = this.sliderToCoeff(newSliderValue);
          this.onVolumeCoeffChange(this.leftVolumeCoeff, newCoeff);
        });
    }
    .width('100%');
  }

  @Builder
  private buildBalanceButtons() {
    Row({ space: 12 }) {
      Button($r('app.string.audio_effects_balance_left'))
        .type(ButtonType.Normal)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(this.settingModel.radiusItem)
        .height(36)
        .layoutWeight(1)
        .onClick(() => {
          this.onVolumeCoeffChange(1.0, 0.0);
        });

      Button($r('app.string.audio_effects_balance_center'))
        .type(ButtonType.Normal)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(this.settingModel.radiusItem)
        .height(36)
        .layoutWeight(1)
        .onClick(() => {
          this.onVolumeCoeffChange(1.0, 1.0);
        });

      Button($r('app.string.audio_effects_balance_right'))
        .type(ButtonType.Normal)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(this.settingModel.radiusItem)
        .height(36)
        .layoutWeight(1)
        .onClick(() => {
          this.onVolumeCoeffChange(0.0, 1.0);
        });
    }
    .width('100%')
    .margin({ top: 8 });
  }

  @Builder
  private buildDisabledPlaceholder() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.speaker_wave_2'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')]);

      Text($r('app.string.audio_effects_volume_coeff_disabled'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'));
    }
    .width('100%')
    .height(200)
    .justifyContent(FlexAlign.Center);
  }

  private formatCoeff(coeff: number): string {
    const percentage = Math.round(coeff * 100);
    return `${percentage}%`;
  }
}