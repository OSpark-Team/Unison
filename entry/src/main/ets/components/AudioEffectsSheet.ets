/**
 * 音频效果设置 Sheet 组件
 * 包含 EQ、DRC、音量系数三个 Tab
 */
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
import AudioEffectsViewModel from '../viewmodel/AudioEffectsViewModel';
import { EqEditor } from './EqEditor';
import { DrcEditor } from './DrcEditor';
import { VolumeCoeffEditor } from './VolumeCoeffEditor';
import { playerManager } from '../services/PlayerManager';

const USER_PRESET_PREFIX: string = 'USER:';

@ComponentV2
export struct AudioEffectsSheet {
  /** 系统设置 ViewModel */
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** 音频效果 ViewModel */
  @Local audioEffectsModel: AudioEffectsViewModel =
    PersistenceV2.connect(AudioEffectsViewModel, 'AudioEffectsViewModel', () => new AudioEffectsViewModel())!;

  /** 当前选中的 Tab 索引 */
  @Local currentTabIndex: number = 0;

  /** 保存预设弹窗 */
  @Local savePresetDialogId: number = 0;
  @Local savePresetDialogType: string = ''; // 'eq' | 'drc'
  @Local savePresetName: string = '';

  /** 删除预设弹窗 */
  @Local deletePresetDialogId: number = 0;
  @Local deletePresetDialogType: string = ''; // 'eq' | 'drc'

  /** 关闭回调 */
  @Param onClose?: () => void = undefined;

  /** 应用效果回调 */
  @Param onApply?: () => void = undefined;

  aboutToAppear(): void {
    // 初始化时应用持久化的效果配置
    this.applyEffectsToPlayer();
  }

  /**
   * 应用当前效果配置到播放器
   */
  private applyEffectsToPlayer(): void {
    const pureEqGains = [...this.audioEffectsModel.eqGains];

    playerManager.applyAudioEffects(
      this.audioEffectsModel.eqEnabled,
      pureEqGains,
      this.audioEffectsModel.drcEnabled,
      this.audioEffectsModel.drcThreshold,
      this.audioEffectsModel.drcRatio,
      this.audioEffectsModel.drcAttack,
      this.audioEffectsModel.drcRelease,
      this.audioEffectsModel.drcMakeup,
      this.audioEffectsModel.volumeCoeffEnabled,
      this.audioEffectsModel.leftVolumeCoeff,
      this.audioEffectsModel.rightVolumeCoeff
    );
  }

  private openSavePresetDialog(type: string): void {
    this.savePresetDialogType = type;
    // 默认填充：若已选中用户预设则用其名称，否则空
    if (type === 'eq') {
      this.savePresetName = this.audioEffectsModel.eqSelectedUserPresetName;
    } else if (type === 'drc') {
      this.savePresetName = this.audioEffectsModel.drcSelectedUserPresetName;
    } else {
      this.savePresetName = '';
    }

    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => {
        this.buildSavePresetDialog();
      },
      onWillDismiss: (dismissDialogAction) => {
        dismissDialogAction.dismiss();
      }
    }).then((dialogId: number) => {
      this.savePresetDialogId = dialogId;
    })
  }

  private closeSavePresetDialog(): void {
    if (this.savePresetDialogId > 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.savePresetDialogId);
      this.savePresetDialogId = 0;
    }
  }

  private openDeletePresetDialog(type: string): void {
    this.deletePresetDialogType = type;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => {
        this.buildDeletePresetDialog();
      },
      onWillDismiss: (dismissDialogAction) => {
        dismissDialogAction.dismiss();
      }
    }).then((dialogId: number) => {
      this.deletePresetDialogId = dialogId;
    })
  }

  private closeDeletePresetDialog(): void {
    if (this.deletePresetDialogId > 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.deletePresetDialogId);
      this.deletePresetDialogId = 0;
    }
  }

  private confirmDeletePreset(): void {
    if (this.deletePresetDialogType === 'eq') {
      const name = this.audioEffectsModel.eqSelectedUserPresetName;
      if (name.length > 0) {
        this.audioEffectsModel.deleteEqUserPreset(name);
        this.applyEffectsToPlayer();
      }
    }

    if (this.deletePresetDialogType === 'drc') {
      const name = this.audioEffectsModel.drcSelectedUserPresetName;
      if (name.length > 0) {
        this.audioEffectsModel.deleteDrcUserPreset(name);
        this.applyEffectsToPlayer();
      }
    }

    this.closeDeletePresetDialog();
  }

  @Builder
  private buildDeletePresetDialog() {
    Column({ space: 12 }) {
      Text($r('app.string.audio_effects_delete_preset_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'));

      Text($r('app.string.audio_effects_delete_preset_message', this.deletePresetDialogType === 'eq'
        ? this.audioEffectsModel.eqSelectedUserPresetName
        : this.audioEffectsModel.drcSelectedUserPresetName))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20);

      Row({ space: 12 }) {
        Button($r('app.string.audio_effects_action_cancel'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.background_secondary'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(12)
          .onClick(() => {
            this.closeDeletePresetDialog();
          });

        Button($r('app.string.audio_effects_action_delete'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.error'))
          .fontColor(Color.White)
          .borderRadius(12)
          .onClick(() => {
            this.confirmDeletePreset();
          });
      }
      .width('100%')
    }
    .width('90%')
    .padding(20)
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius(this.settingModel.radiusCardLarge)
  }

  private confirmSavePreset(): void {
    const name = this.savePresetName.trim();
    if (name.length === 0) {
      return;
    }

    if (this.savePresetDialogType === 'eq') {
      this.audioEffectsModel.upsertEqUserPreset(name, this.audioEffectsModel.eqGains);
      this.audioEffectsModel.eqSelectedUserPresetName = name;
      this.audioEffectsModel.eqIsCustom = false;
      this.audioEffectsModel.eqPresetId = USER_PRESET_PREFIX + name;
    }

    if (this.savePresetDialogType === 'drc') {
      this.audioEffectsModel.upsertDrcUserPreset(
        name,
        this.audioEffectsModel.drcThreshold,
        this.audioEffectsModel.drcRatio,
        this.audioEffectsModel.drcAttack,
        this.audioEffectsModel.drcRelease,
        this.audioEffectsModel.drcMakeup
      );
      this.audioEffectsModel.drcSelectedUserPresetName = name;
      this.audioEffectsModel.drcIsCustom = false;
      this.audioEffectsModel.drcPresetId = USER_PRESET_PREFIX + name;
    }

    this.applyEffectsToPlayer();
    this.closeSavePresetDialog();
  }

  @Builder
  private buildSavePresetDialog() {
    Column({ space: 12 }) {
      Text($r('app.string.audio_effects_save_preset_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'));

      TextInput({
        placeholder: $r('app.string.audio_effects_save_preset_placeholder'),
        text: this.savePresetName
      })
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.background_secondary', '#0D000000'))
        .borderRadius(12)
        .onChange((value: string) => {
          this.savePresetName = value;
        });

      Row({ space: 12 }) {
        Button($r('app.string.audio_effects_action_cancel'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.background_secondary'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(12)
          .onClick(() => {
            this.closeSavePresetDialog();
          });

        Button($r('app.string.audio_effects_action_save'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.primary_color'))
          .fontColor(Color.White)
          .borderRadius(12)
          .onClick(() => {
            this.confirmSavePreset();
          });
      }
      .width('100%')
    }
    .width('90%')
    .padding(20)
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius(this.settingModel.radiusCardLarge)
  }

  @Builder
  private buildTabBar(title: ResourceStr, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTabIndex === index ? $r('app.color.primary_color') : $r('app.color.text_secondary'))
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(this.settingModel.radiusItem)
  }

  build() {
    Column({ space: 0 }) {
      // 标题栏
      this.buildHeader();

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      // Tab 内容
      Tabs({ index: $$this.currentTabIndex }) {
        TabContent() {
          this.buildEqTab();
        }
        .tabBar(this.buildTabBar($r('app.string.audio_effects_eq'), 0))
        .align(Alignment.TopStart) // 确保 Tab 内部内容置顶

        TabContent() {
          this.buildDrcTab();
        }
        .tabBar(this.buildTabBar($r('app.string.audio_effects_drc'), 1))
        .align(Alignment.TopStart) // 确保 Tab 内部内容置顶

        TabContent() {
          this.buildVolumeCoeffTab();
        }
        .tabBar(this.buildTabBar($r('app.string.audio_effects_volume_coeff_short'), 2))
        .align(Alignment.TopStart) // 确保 Tab 内部内容置顶
      }
      .barMode(BarMode.Fixed)
      .barPosition(BarPosition.Start)
      .vertical(false)
      .scrollable(true)
      .barBackgroundColor($r('app.color.background_primary'))
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius(this.settingModel.radiusCardLarge)
    .clip(true)
  }

  @Builder
  private buildHeader() {
    Row({ space: 12 }) {
      Text($r('app.string.audio_effects_title'))
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

  @Builder
  private buildEqTab() {
    Scroll() {
      Column() {
        EqEditor({
          eqEnabled: this.audioEffectsModel.eqEnabled,
          eqPresetId: this.audioEffectsModel.eqPresetId,
          eqIsCustom: this.audioEffectsModel.eqIsCustom,
          eqSelectedUserPresetName: this.audioEffectsModel.eqSelectedUserPresetName,
          eqGains: this.audioEffectsModel.eqGains,
          userPresetNames: this.audioEffectsModel.eqUserPresetNames,
          userPresetGains: this.audioEffectsModel.eqUserPresetGains,
          canDeleteUserPreset: this.audioEffectsModel.eqSelectedUserPresetName.length > 0,
          onEnabledChange: (enabled: boolean) => {
            this.audioEffectsModel.eqEnabled = enabled;
            this.applyEffectsToPlayer();
          },
          onPresetChange: (presetId: string, gains: number[]) => {
            this.audioEffectsModel.eqPresetId = presetId;
            this.audioEffectsModel.eqGains = gains;
            this.audioEffectsModel.eqIsCustom = false;
            if (presetId.startsWith(USER_PRESET_PREFIX)) {
              this.audioEffectsModel.eqSelectedUserPresetName = presetId.substring(USER_PRESET_PREFIX.length);
            } else {
              this.audioEffectsModel.eqSelectedUserPresetName = '';
            }
            this.applyEffectsToPlayer();
          },
          onGainsChange: (gains: number[]) => {
            this.audioEffectsModel.eqGains = gains;
            this.audioEffectsModel.eqIsCustom = true;
            this.audioEffectsModel.eqSelectedUserPresetName = '';
            this.applyEffectsToPlayer();
          },
          onSavePreset: () => {
            this.openSavePresetDialog('eq');
          },
          onDeletePreset: () => {
            this.openDeletePresetDialog('eq');
          }
        });
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: 16, bottom: 24 });
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top) // 滚动组件内容置顶对齐
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring);
  }

  @Builder
  private buildDrcTab() {
    Scroll() {
      Column() {
        DrcEditor({
          drcEnabled: this.audioEffectsModel.drcEnabled,
          drcPresetId: this.audioEffectsModel.drcPresetId,
          drcIsCustom: this.audioEffectsModel.drcIsCustom,
          drcSelectedUserPresetName: this.audioEffectsModel.drcSelectedUserPresetName,
          drcThreshold: this.audioEffectsModel.drcThreshold,
          drcRatio: this.audioEffectsModel.drcRatio,
          drcAttack: this.audioEffectsModel.drcAttack,
          drcRelease: this.audioEffectsModel.drcRelease,
          drcMakeup: this.audioEffectsModel.drcMakeup,
          userPresetNames: this.audioEffectsModel.drcUserPresetNames,
          userPresetThreshold: this.audioEffectsModel.drcUserPresetThreshold,
          userPresetRatio: this.audioEffectsModel.drcUserPresetRatio,
          userPresetAttack: this.audioEffectsModel.drcUserPresetAttack,
          userPresetRelease: this.audioEffectsModel.drcUserPresetRelease,
          userPresetMakeup: this.audioEffectsModel.drcUserPresetMakeup,
          canDeleteUserPreset: this.audioEffectsModel.drcSelectedUserPresetName.length > 0,
          onEnabledChange: (enabled: boolean) => {
            this.audioEffectsModel.drcEnabled = enabled;
            this.applyEffectsToPlayer();
          },
          onPresetChange: (presetId: string, threshold: number, ratio: number, attack: number, release: number, makeup: number) => {
            this.audioEffectsModel.drcPresetId = presetId;
            this.audioEffectsModel.drcThreshold = threshold;
            this.audioEffectsModel.drcRatio = ratio;
            this.audioEffectsModel.drcAttack = attack;
            this.audioEffectsModel.drcRelease = release;
            this.audioEffectsModel.drcMakeup = makeup;
            this.audioEffectsModel.drcIsCustom = false;
            if (presetId.startsWith(USER_PRESET_PREFIX)) {
              this.audioEffectsModel.drcSelectedUserPresetName = presetId.substring(USER_PRESET_PREFIX.length);
            } else {
              this.audioEffectsModel.drcSelectedUserPresetName = '';
            }
            this.applyEffectsToPlayer();
          },
          onParamsChange: (threshold: number, ratio: number, attack: number, release: number, makeup: number) => {
            this.audioEffectsModel.drcThreshold = threshold;
            this.audioEffectsModel.drcRatio = ratio;
            this.audioEffectsModel.drcAttack = attack;
            this.audioEffectsModel.drcRelease = release;
            this.audioEffectsModel.drcMakeup = makeup;
            this.audioEffectsModel.drcIsCustom = true;
            this.audioEffectsModel.drcSelectedUserPresetName = '';
            this.applyEffectsToPlayer();
          },
          onSavePreset: () => {
            this.openSavePresetDialog('drc');
          },
          onDeletePreset: () => {
            this.openDeletePresetDialog('drc');
          }
        });
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: 16, bottom: 24 });
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top) // 滚动组件内容置顶对齐
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring);
  }

  @Builder
  private buildVolumeCoeffTab() {
    Scroll() {
      Column() {
        VolumeCoeffEditor({
          volumeCoeffEnabled: this.audioEffectsModel.volumeCoeffEnabled,
          leftVolumeCoeff: this.audioEffectsModel.leftVolumeCoeff,
          rightVolumeCoeff: this.audioEffectsModel.rightVolumeCoeff,
          onEnabledChange: (enabled: boolean) => {
            this.audioEffectsModel.volumeCoeffEnabled = enabled;
            this.applyEffectsToPlayer();
          },
          onVolumeCoeffChange: (left: number, right: number) => {
            this.audioEffectsModel.leftVolumeCoeff = left;
            this.audioEffectsModel.rightVolumeCoeff = right;
            this.applyEffectsToPlayer();
          }
        });
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: 16, bottom: 24 });
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top) // 滚动组件内容置顶对齐
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring);
  }
}
