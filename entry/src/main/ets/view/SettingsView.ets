import axios from '@ohos/axios';
import { SettingGroup } from '../components/SettingGroup';
import { SettingItem } from '../components/SettingItem';
import { StyledSelect } from '../components/StyledSelect';
import Logger from '../utils/Logger';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { PersistenceV2 } from '@kit.ArkUI';

import { bundleManager } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import hilog from '@ohos.hilog';
import hdsTabSettingCom from '../components/TabSettingcom';

const TAG = 'SettingsView';
const DOMAIN: number = 0xFF02;
const FEEDBACK_API_URL: string = 'https://app.formbricks.com/api/v1/client/cmmgi1duvwhsary014ib1w2ps/responses';
const FEEDBACK_SURVEY_ID: string = 'cmmgi2ifmw18jum01kaynpmk5';

interface FeedbackRequestData {
  bcukyn55f0uvkr0le8h7mljb: string;
  atiy3cqj849f67t76op4hfbt: string;
  olz3i6xvovios5cv1pcr5fwq: string;
}

interface FeedbackRequestPayload {
  surveyId: string;
  data: FeedbackRequestData;
  finished: boolean;
  userId: string;
}

/**
 * 设置视图
 * 负责显示各种应用设置项
 */
@ComponentV2
export struct SettingsView {
  /**
   * 路由导航
   */
  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  /**
   * 搜索关键词
   */
  @Provider() searchKeyword: string = '';

  /**
   * 系统设置 ViewModel
   */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  @Local showSheet: boolean = false;
  @Local sheetType: string = '';

  @Local aboutBundleName: string = '';
  @Local aboutVersionName: string = '';
  @Local aboutVersionCode: number = 0;
  @Local aboutAppName: string = 'Unison';
  @Local feedbackContent: string = '';
  @Local feedbackContact: string = '';
  @Local feedbackSubmitting: boolean = false;

  private openSheet(type: string): void {
    this.showSheet = false;
    this.sheetType = type;
    this.showSheet = true;
  }

  private closeSheet(): void {
    this.showSheet = false;
  }

  private buildFeedbackVersion(): string {
    if (this.aboutVersionName.length === 0) {
      return 'unknown';
    }
    if (this.aboutVersionCode > 0) {
      return `${this.aboutVersionName} (${this.aboutVersionCode})`;
    }
    return this.aboutVersionName;
  }

  private buildFeedbackUserId(): string {
    return `omsp_feedback_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  }

  private validateFeedbackForm(): boolean {
    return this.feedbackContent.trim().length > 0;
  }

  private resetFeedbackForm(): void {
    this.feedbackContent = '';
    this.feedbackContact = '';
    this.feedbackSubmitting = false;
  }

  private async submitFeedback(): Promise<void> {
    if (this.feedbackSubmitting) {
      return;
    }
    if (!this.validateFeedbackForm()) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.setting_feedback_validation_error'),
      });
      return;
    }

    this.feedbackSubmitting = true;
    try {
      if (this.aboutVersionName.length === 0) {
        await this.loadAboutInfo();
      }
      let requestData: FeedbackRequestData = {
        bcukyn55f0uvkr0le8h7mljb: this.buildFeedbackVersion(),
        atiy3cqj849f67t76op4hfbt: this.feedbackContent.trim(),
        olz3i6xvovios5cv1pcr5fwq: this.feedbackContact.trim(),
      };
      let requestPayload: FeedbackRequestPayload = {
        surveyId: FEEDBACK_SURVEY_ID,
        data: requestData,
        finished: true,
        userId: this.buildFeedbackUserId(),
      };
      await axios.post(FEEDBACK_API_URL, requestPayload);
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.setting_feedback_submit_success'),
      });
      this.resetFeedbackForm();
      this.closeSheet();
    } catch (error) {
      Logger.error(TAG, `Failed to submit feedback: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.setting_feedback_submit_failed'),
      });
    } finally {
      this.feedbackSubmitting = false;
    }
  }

  aboutToAppear(): void {
    Logger.info(TAG, 'SettingsView 即将出现');
    this.loadAboutInfo();
  }

  private async loadAboutInfo(): Promise<void> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
      );
      this.aboutBundleName = info.name;
      this.aboutVersionName = info.versionName;
      this.aboutVersionCode = info.versionCode;
      // 硬编码应用名称为 Unison
      this.aboutAppName = 'Unison';
    } catch (err) {
      Logger.error(TAG, `Failed to load bundle info: ${JSON.stringify(err)}`);
    }
  }

  private setTheme(theme: 'system' | 'light' | 'dark'): void {
    try {
      const uiContext = this.getUIContext();
      const hostContext = uiContext.getHostContext();
      if (!hostContext) {
        Logger.error(TAG, 'Failed to set theme: HostContext is null.');
        return;
      }
      const appContext = hostContext.getApplicationContext();
      if (theme === 'system') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } else if (theme === 'light') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (theme === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      }
      this.settingModel.theme = theme;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private setLanguage(lang: string): void {
    try {
      const uiContext = this.getUIContext();
      const hostContext = uiContext.getHostContext();
      if (!hostContext) {
        Logger.error(TAG, 'Failed to set language: HostContext is null.');
        return;
      }
      const appContext = hostContext.getApplicationContext();
      appContext.setLanguage(lang);
      this.settingModel.lang = lang;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set language. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private getThemeDescription(): ResourceStr {
    if (this.settingModel.theme === 'light') {
      return $r('app.string.setting_theme_light');
    }
    if (this.settingModel.theme === 'dark') {
      return $r('app.string.setting_theme_dark');
    }
    return $r('app.string.setting_theme_system');
  }

  private getLanguageDescription(): ResourceStr {
    if (this.settingModel.lang === 'en') {
      return $r('app.string.setting_language_en');
    }
    return $r('app.string.setting_language_zh');
  }

  private getPlaybackNetworkDescription(): ResourceStr {
    if (this.settingModel.dataServiceMode === 'both') {
      return $r('app.string.setting_playback_network_both');
    }
    return $r('app.string.setting_playback_network_wifi_only');
  }

  private getBitrateLabel(bitrate: string | number): ResourceStr {
    if (bitrate === 'standard') {
      return $r('app.string.setting_bitrate_standard');
    }
    if (bitrate === 'higher') {
      return $r('app.string.setting_bitrate_higher');
    }
    if (bitrate === 'exhigh') {
      return $r('app.string.setting_bitrate_exhigh');
    }
    if (bitrate === 'lossless') {
      return $r('app.string.setting_bitrate_lossless');
    }
    if (bitrate === 'hires') {
      return $r('app.string.setting_bitrate_hires');
    }
    if (bitrate === 'vivd') {
      return $r('app.string.setting_bitrate_vivd');
    }
    return String(bitrate);
  }

  // 现代化的 Sheet 头部设计：左侧大标题，右侧圆形关闭按钮
  @Builder
  private buildSheetHeader(title: ResourceStr) {
    Row({ space: 12 }) {
      Text(title)
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
          this.closeSheet();
        });
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.background_card'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildThemeSheet() {
    Column() {
      this.buildSheetHeader($r('app.string.sheet_title_theme'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Column() {
        this.buildThemeOption('system', $r('app.string.setting_theme_system'), $r('sys.symbol.paintbrush'))
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 48, right: 16 })
        this.buildThemeOption('light', $r('app.string.setting_theme_light'), $r('sys.symbol.sun_max'))
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 48, right: 16 })
        this.buildThemeOption('dark', $r('app.string.setting_theme_dark'), $r('sys.symbol.moon'))
      }
      .width('calc(100% - 32vp)')
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(16) // 现代化大圆角
      .padding(4)
      .margin({ top: 8, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start) // 关键：确保内容顶部对齐
    .backgroundColor($r('app.color.background_primary'));
  }

  @Builder
  private buildThemeOption(value: 'system' | 'light' | 'dark', title: ResourceStr, icon: Resource) {
    Row({ space: 16 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([$r('app.color.text_secondary')])

      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)

      if (this.settingModel.theme === value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_color')])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .borderRadius(12)
    .onClick(() => {
      this.setTheme(value);
      this.closeSheet();
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress });
  }

  @Builder
  private buildLanguageSheet() {
    Column() {
      this.buildSheetHeader($r('app.string.sheet_title_language'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Column() {
        this.buildLanguageOption('zh', $r('app.string.setting_language_zh'))
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
        this.buildLanguageOption('en', $r('app.string.setting_language_en'))
      }
      .width('calc(100% - 32vp)')
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(16)
      .padding(4)
      .margin({ top: 8, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));
  }

  @Builder
  private buildLanguageOption(value: string, title: ResourceStr) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)

      if (this.settingModel.lang === value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_color')])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .borderRadius(12)
    .onClick(() => {
      this.setLanguage(value);
      this.closeSheet();
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress });
  }

  @Builder
  private buildAudioQualitySheet() {
    Column() {
      this.buildSheetHeader($r('app.string.sheet_title_bitrate'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Scroll() {
        Column({ space: 16 }) {
          // 将三个选项整合在一个卡片内
          Column() {
            this.buildBitrateSelectRow(
              $r('app.string.setting_playback_bitrate_data'),
              this.settingModel.playBitrateOnData,
              (value: string | number) => {
                this.settingModel.playBitrateOnData = value;
              },
            )

            Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })

            this.buildBitrateSelectRow(
              $r('app.string.setting_playback_bitrate_wifi'),
              this.settingModel.playBitrate,
              (value: string | number) => {
                this.settingModel.playBitrate = value;
              },
            )

            Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })

            this.buildBitrateSelectRow(
              $r('app.string.setting_download_bitrate'),
              this.settingModel.downloadBitrate,
              (value: string | number) => {
                this.settingModel.downloadBitrate = value;
              },
            )
          }
          .width('100%')
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)

        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .align(Alignment.Top) // 确保Scroll内元素置顶
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));
  }

  @Builder
  private buildBitrateSelectRow(title: ResourceStr, current: string | number, onChange: (value: string | number) => void) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1) // 占用左侧空间

      StyledSelect({
        options: [
          { value: $r('app.string.setting_bitrate_standard') },
          { value: $r('app.string.setting_bitrate_higher') },
          { value: $r('app.string.setting_bitrate_exhigh') },
          { value: $r('app.string.setting_bitrate_lossless') },
          { value: $r('app.string.setting_bitrate_hires') },
          { value: $r('app.string.setting_bitrate_vivd') },
        ],
        selectedIndex: this.getBitrateIndex(current),
        valueText: this.getBitrateLabel(current),
        disabled: false,
        onSelect: (index: number, _value: string) => {
          onChange(this.getBitrateValueByIndex(index));
        },
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  private getBitrateIndex(bitrate: string | number): number {
    if (bitrate === 'standard') return 0;
    if (bitrate === 'higher') return 1;
    if (bitrate === 'exhigh') return 2;
    if (bitrate === 'lossless') return 3;
    if (bitrate === 'hires') return 4;
    if (bitrate === 'vivd') return 5;
    return 0;
  }

  private getBitrateValueByIndex(index: number): string {
    if (index === 0) return 'standard';
    if (index === 1) return 'higher';
    if (index === 2) return 'exhigh';
    if (index === 3) return 'lossless';
    if (index === 4) return 'hires';
    return 'vivd';
  }

  @Builder
  private buildExperimentalSheet() {
    Column() {
      this.buildSheetHeader($r('app.string.setting_group_experimental'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Column({ space: 16 }) {
        Text($r('app.string.setting_experimental_desc'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(20)
          .padding({ left: 4, right: 4 })

        Column({ space: 12 }) {
          Column() {
            SettingItem({
              type: 'switch',
              icon: $r('sys.symbol.textformat'),
              title: $r('app.string.setting_experimental_word_for_word_lyrics'),
              description: $r('app.string.setting_experimental_word_for_word_lyrics_desc'),
              value: this.settingModel.wordForWordLyricsEnabled,
              onChange: (value: boolean) => {
                this.settingModel.wordForWordLyricsEnabled = value;
              },
              isLast: false,
            })

            SettingItem({
              type: 'switch',
              icon: $r('sys.symbol.speaker_wave_2'),
              title: $r('app.string.setting_experimental_playing_mix'),
              description: $r('app.string.setting_experimental_playing_mix_desc'),
              value: this.settingModel.experimentalPlayingMixEnabled,
              onChange: (value: boolean) => {
                this.settingModel.experimentalPlayingMixEnabled = value;
              },
              isLast: false,
            })

            SettingItem({
              type: 'switch',
              icon: $r('sys.symbol.speaker_wave_2'),
              title: $r('app.string.setting_experimental_audio_rhythm'),
              description: $r('app.string.setting_experimental_audio_rhythm_desc'),
              value: this.settingModel.experimentalAudioHapticsEnabled,
              onChange: (value: boolean) => {
                this.settingModel.experimentalAudioHapticsEnabled = value;
              },
              isLast: true,
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)
          .padding(4)

          Text($r('app.string.setting_experimental_audio_rhythm_hint'))
            .width('100%')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .opacity(this.settingModel.opacitySecondaryText)
            .padding({ left: 4, right: 4 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));
  }

  @Builder
  private buildPlaybackNetworkSheet() {
    Column() {
      this.buildSheetHeader($r('app.string.setting_playback_network'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Column() {
        this.buildPlaybackNetworkOption('wifi-only', $r('app.string.setting_playback_network_wifi_only'))
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
        this.buildPlaybackNetworkOption('both', $r('app.string.setting_playback_network_both'))
      }
      .width('calc(100% - 32vp)')
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(16)
      .padding(4)
      .margin({ top: 8, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));
  }
  @Builder
  private buildPersonalSetting(){
    Column(){
      this.buildSheetHeader('个性化设置')
      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));
      Scroll() {

        hdsTabSettingCom()

      }
      .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .align(Alignment.Top)
    }    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));

  }
  @Builder
  private buildPlaybackNetworkOption(value: 'wifi-only' | 'both', title: ResourceStr) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)

      if (this.settingModel.dataServiceMode === value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([$r('app.color.primary_color')])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .borderRadius(12)
    .onClick(() => {
      this.settingModel.dataServiceMode = value;
      this.closeSheet();
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress });
  }

  @Builder
  private buildAboutSheet() {
    Column() {
      this.buildSheetHeader($r('app.string.setting_about_app'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Scroll() {
        Column({ space: 24 }) {
          Column() {
            Image($r('app.media.startIcon'))
              .width(88)
              .height(88)
              .borderRadius(22)
              .margin({ top: 16 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)

          Column({ space: 0 }) {
            this.buildAboutRow($r('app.string.setting_about_app_name'), this.aboutAppName, false)
            Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.buildAboutRow($r('app.string.setting_about_version'), `${this.aboutVersionName} (${this.aboutVersionCode})`, false)
            Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
            this.buildAboutRow($r('app.string.setting_about_bundle'), this.aboutBundleName, true)
          }
          .width('100%')
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));
  }

  @Builder
  private buildAboutRow(label: ResourceStr, value: ResourceStr, isLast: boolean) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  private buildByokSheet() {
    Column() {
      this.buildSheetHeader($r('app.string.setting_byok_title'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Scroll() {
        Column({ space: 24 }) {
          Column({ space: 12 }) {
            Text($r('app.string.setting_byok_api_key'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .padding({ left: 4 })

            TextInput({
              placeholder: $r('app.string.setting_byok_api_key_placeholder'),
              text: this.settingModel.byokApiKey,
            })
              .width('100%')
              .height(48)
              .type(InputType.Password)
              .showPasswordIcon(true)
              .backgroundColor($r('app.color.background_secondary', '#0D000000'))
              .borderRadius(12)
              .onChange((value) => {
                this.settingModel.byokApiKey = value;
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)

          Column({ space: 12 }) {
            Text($r('app.string.setting_byok_api_base'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .padding({ left: 4 })

            TextInput({
              placeholder: $r('app.string.setting_byok_api_base_placeholder'),
              text: this.settingModel.byokApiBase,
            })
              .width('100%')
              .height(48)
              .type(InputType.Normal)
              .backgroundColor($r('app.color.background_secondary', '#0D000000'))
              .borderRadius(12)
              .onChange((value) => {
                this.settingModel.byokApiBase = value;
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)

          Column({ space: 12 }) {
            Text($r('app.string.setting_byok_api_model'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .padding({ left: 4 })

            TextInput({
              placeholder: $r('app.string.setting_byok_api_model_placeholder'),
              text: this.settingModel.byokApiModel,
            })
              .width('100%')
              .height(48)
              .type(InputType.Normal)
              .backgroundColor($r('app.color.background_secondary', '#0D000000'))
              .borderRadius(12)
              .onChange((value) => {
                this.settingModel.byokApiModel = value;
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));
  }

  @Builder
  private buildFeedbackSheet() {
    Column() {
      this.buildSheetHeader($r('app.string.sheet_title_feedback'))

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'));

      Scroll() {
        Column({ space: 24 }) {
          Column({ space: 12 }) {
            Text($r('app.string.setting_feedback_content_label'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .padding({ left: 4 })

            TextArea({
              placeholder: $r('app.string.setting_feedback_content_placeholder'),
              text: this.feedbackContent,
            })
              .width('100%')
              .height(168)
              .backgroundColor($r('app.color.background_secondary', '#0D000000'))
              .borderRadius(12)
              .onChange((value) => {
                this.feedbackContent = value;
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)

          Column({ space: 12 }) {
            Text($r('app.string.setting_feedback_contact_label'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .padding({ left: 4 })

            TextInput({
              placeholder: $r('app.string.setting_feedback_contact_placeholder'),
              text: this.feedbackContact,
            })
              .width('100%')
              .height(48)
              .type(InputType.Normal)
              .backgroundColor($r('app.color.background_secondary', '#0D000000'))
              .borderRadius(12)
              .onChange((value) => {
                this.feedbackContact = value;
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.background_card'))
          .borderRadius(16)

          Button(this.feedbackSubmitting ? $r('app.string.setting_feedback_submitting') : $r('app.string.setting_feedback_submit'))
            .width('100%')
            .height(48)
            .backgroundColor($r('app.color.button_primary'))
            .fontColor($r('app.color.button_label_primary'))
            .borderRadius(14)
            .enabled(!this.feedbackSubmitting)
            .onClick(() => {
              this.submitFeedback();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.background_primary'));
  }

  @Builder
  private buildDynamicSheet() {
    if (this.sheetType === 'theme') {
      this.buildThemeSheet();
    } else if (this.sheetType === 'language') {
      this.buildLanguageSheet();
    } else if (this.sheetType === 'audioQuality') {
      this.buildAudioQualitySheet();
    } else if (this.sheetType === 'playbackNetwork') {
      this.buildPlaybackNetworkSheet();
    } else if (this.sheetType === 'experimental') {
      this.buildExperimentalSheet();
    } else if (this.sheetType === 'about') {
      this.buildAboutSheet();
    } else if (this.sheetType === 'byok') {
      this.buildByokSheet();
    } else if (this.sheetType === 'feedback') {
      this.buildFeedbackSheet();
    }else if (this.sheetType === 'personalSetting') {
      this.buildPersonalSetting();
    } else {
      Column() {}
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start);
    }
  }

  /**
   * 构建设置项区域
   */
  @Builder
  buildSettingsArea() {
    Column({ space: 16 }) {
      // 通用设置分组
      SettingGroup({ title: $r('app.string.setting_group_general') }) {
        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.paintbrush'),
          title: $r('app.string.setting_theme'),
          description: this.getThemeDescription(),
          isLast: false,
          onItemClick: () => {
            this.openSheet('theme');
          }
        })
        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.paintbrush'),
          title: '个性化设置',
          description: '随心所欲',
          isLast: false,
          onItemClick: () => {
            this.openSheet('personalSetting');
          }
        })
        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.textformat'),
          title: $r('app.string.setting_language'),
          description: this.getLanguageDescription(),
          isLast: true,
          onItemClick: () => {
            this.openSheet('language');
          }
        })
      }

      // 播放设置分组
      SettingGroup({ title: $r('app.string.setting_group_playback') }) {
        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.speaker_wave_2'),
          title: $r('app.string.setting_audio_quality'),
          description: $r('app.string.setting_audio_quality_desc'),
          isLast: false,
          onItemClick: () => {
            this.openSheet('audioQuality');
          }
        })

        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.network_acceleration'),
          title: $r('app.string.setting_playback_network'),
          description: this.getPlaybackNetworkDescription(),
          isLast: false,
          onItemClick: () => {
            this.openSheet('playbackNetwork');
          }
        })

        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.repeat'),
          title: $r('app.string.setting_group_experimental'),
          description: $r('app.string.setting_experimental_desc'),
          isLast: true,
          onItemClick: () => {
            this.openSheet('experimental');
          }
        })
      }

      // Unison+ 设置分组
      SettingGroup({ title: $r('app.string.setting_group_unison_plus') }) {
        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.AI'),
          title: $r('app.string.setting_byok_title'),
          description: $r('app.string.setting_byok_desc'),
          isLast: true,
          onItemClick: () => {
            this.openSheet('byok');
          }
        })
      }

      // 关于分组
      SettingGroup({ title: $r('app.string.setting_group_about') }) {
        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.info_circle'),
          title: $r('app.string.setting_about_app'),
          description: $r('app.string.setting_about_app_desc'),
          isLast: false,
          onItemClick: () => {
            this.openSheet('about');
          }
        })

        // SettingItem({
        //   type: 'navigation',
        //   icon: $r('sys.symbol.questionmark_circle'),
        //   title: $r('app.string.setting_help'),
        //   description: $r('app.string.setting_help_desc'),
        //   isLast: false,
        //   onItemClick: () => {
        //     // TODO: 打开帮助页面
        //   }
        // })

        SettingItem({
          type: 'navigation',
          icon: $r('sys.symbol.envelope'),
          title: $r('app.string.setting_feedback'),
          description: $r('app.string.setting_feedback_desc'),
          isLast: true,
          onItemClick: () => {
            this.openSheet('feedback');
          }
        })
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      this.buildSettingsArea();
    }
    .width('100%')
    .bindSheet(!!this.showSheet, this.buildDynamicSheet(), {
      height: SheetSize.LARGE,
      showClose: false,
      preferType: SheetType.CENTER,

    });
  }
}
