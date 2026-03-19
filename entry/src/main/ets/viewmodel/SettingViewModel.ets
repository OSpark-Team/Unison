import { Bitrate } from "../model/adapter/Types";

/**
 * 系统应用设置
 */
@ObservedV2
export default class SettingViewModel {
  /** 默认显示主题 */
  @Trace theme: "system" | "light" | "dark" = "system";

  /** 默认显示语言 */
  @Trace lang: "zh" | "en" | string = "zh";

  /** 播放码率 */
  @Trace playBitrate: Bitrate = "exhigh";

  /** 下载码率 */
  @Trace downloadBitrate: Bitrate = "lossless";

  /** 数据流量模式 */
  @Trace dataServiceMode: "wifi-only" | "both" = "wifi-only";

  /** 数据流量播放码率 */
  @Trace playBitrateOnData: Bitrate = "standard";

  /** 最大缓存大小(MB) */
  @Trace maxCacheSize: number = 1024;

  /** 实验性：音频律动震动 */
  @Trace experimentalAudioHapticsEnabled: boolean = false;

  /** 实验性：逐字歌词渲染 */
  @Trace wordForWordLyricsEnabled: boolean = false;

  /** 实验性：多音频并发播放 */
  @Trace experimentalPlayingMixEnabled: boolean = false;

  /** 统一模糊参数 */
  @Trace uniformBlur: number = 0;

  /** 统一透明参数 */
  @Trace uniformOpacity: number = 1;

  /** 统一按压缩放参数 */
  @Trace uniformScale: number = 0.98;

  /** 统一圆角参数 */
  @Trace uniformRadius: number = 12;

  /**
   * 卡片圆角（一般容器/卡片）
   * 默认值：12（对齐历史视觉）
   */
  @Trace radiusCard: number = 12;

  /**
   * 大卡片/弹窗圆角
   * 默认值：16（用于详情弹窗、信息卡片外框等）
   */
  @Trace radiusCardLarge: number = 16;

  /**
   * 列表项/按钮等交互单元圆角
   * 默认值：8
   */
  @Trace radiusItem: number = 8;

  /**
   * 封面/缩略图圆角
   * 默认值：4
   */
  @Trace radiusCover: number = 4;

  /**
   * 模块卡片圆角
   * 默认值：20（对齐历史视觉）
   */
  @Trace radiusModule: number = 20;

  /**
   * Tab 顶部圆角（Index tabBuilder）
   * 默认值：10
   */
  @Trace radiusTabTop: number = 10;

  /**
   * 次要文本透明度（如卡片描述文字）
   * 默认值：0.8
   */
  @Trace opacitySecondaryText: number = 0.8;

  /**
   * 分隔线/弱信息透明度
   * 默认值：0.6
   */
  @Trace opacityWeak: number = 0.6;

  /**
   * 歌单信息卡背景渐变层透明度
   * 默认值：0.88
   */
  @Trace opacityPlaylistGradient: number = 0.88;

  /**
   * 通用按压缩放（ClickEffect）
   * 默认值：0.98
   */
  @Trace scalePress: number = 0.98;

  /**
   * 强按压缩放（用于更“弹”的按钮等）
   * 默认值：0.8（对齐历史视觉）
   */
  @Trace scalePressStrong: number = 0.8;

  /**
   * 轻量按钮/小控件按压缩放
   * 默认值：0.5（对齐历史视觉，如 ModuleCard 角标按钮）
   */
  @Trace scalePressTiny: number = 0.5;

  /**
   * 背景模糊档位（用于 backgroundBlurStyle 场景）
   * 0=关闭 1=Thin 2=Thick
   */
  @Trace blurStyleLevel: number = 1;

  /** 默认数据源ID */
  @Trace mainSource: string = "";

  /** 第一次打开的版本 */
  @Trace firstOpenVersion: string  = "";


  /** Unison+ BYOK: OpenAI-compat API Key */
  @Trace byokApiKey: string = "";

  /** Unison+ BYOK: OpenAI-compat API Base URL */
  @Trace byokApiBase: string = "";

  /** Unison+ BYOK: OpenAI-compat API Model */
  @Trace byokApiModel: string = "gpt-4o-mini";

  isByokConfigured(): boolean {
    return this.byokApiKey.trim() !== "" && this.byokApiBase.trim() !== "" && this.byokApiModel.trim() !== "";
  }
}



