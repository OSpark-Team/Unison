/**
 * 音频效果预设配置
 * 包含 EQ 均衡器和 DRC 动态范围压缩的预设
 */

// ========== EQ 预设 ==========

/**
 * EQ 预设 ID 枚举
 */
export class EqPresetId {
  static readonly Default: string = 'Default';
  static readonly Pop: string = 'Pop';
  static readonly Rock: string = 'Rock';
  static readonly Jazz: string = 'Jazz';
  static readonly Classical: string = 'Classical';
  static readonly Dance: string = 'Dance';
  static readonly Ballads: string = 'Ballads';
  static readonly RnB: string = 'RnB';
  static readonly Voice: string = 'Voice';
  static readonly Electronic: string = 'Electronic';
}

/**
 * EQ 预设数据结构
 */
export class EqPreset {
  id: string = '';
  label: ResourceStr;
  gainsDb: number[] = [];

  constructor(id: string, label: ResourceStr, gainsDb: number[]) {
    this.id = id;
    this.label = label;
    this.gainsDb = gainsDb;
  }
}

/**
 * EQ 频段标签
 */
export class EqBandLabels {
  static readonly BAND_31HZ: string = '31Hz';
  static readonly BAND_62HZ: string = '62Hz';
  static readonly BAND_125HZ: string = '125Hz';
  static readonly BAND_250HZ: string = '250Hz';
  static readonly BAND_500HZ: string = '500Hz';
  static readonly BAND_1KHZ: string = '1kHz';
  static readonly BAND_2KHZ: string = '2kHz';
  static readonly BAND_4KHZ: string = '4kHz';
  static readonly BAND_8KHZ: string = '8kHz';
  static readonly BAND_16KHZ: string = '16kHz';

  static readonly ALL: string[] = [
    EqBandLabels.BAND_31HZ,
    EqBandLabels.BAND_62HZ,
    EqBandLabels.BAND_125HZ,
    EqBandLabels.BAND_250HZ,
    EqBandLabels.BAND_500HZ,
    EqBandLabels.BAND_1KHZ,
    EqBandLabels.BAND_2KHZ,
    EqBandLabels.BAND_4KHZ,
    EqBandLabels.BAND_8KHZ,
    EqBandLabels.BAND_16KHZ
  ];
}

/**
 * EQ 预设列表
 */
export class EqPresets {
  static readonly DEFAULT: EqPreset = new EqPreset(
    EqPresetId.Default,
    $r('app.string.eq_preset_default'),
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  );

  static readonly POP: EqPreset = new EqPreset(
    EqPresetId.Pop,
    $r('app.string.eq_preset_pop'),
    [3, 2, 1, 0, -1, -1, 0, 1, 2, 3]
  );

  static readonly ROCK: EqPreset = new EqPreset(
    EqPresetId.Rock,
    $r('app.string.eq_preset_rock'),
    [5, 4, 3, 1, -1, -1, 1, 3, 4, 4]
  );

  static readonly JAZZ: EqPreset = new EqPreset(
    EqPresetId.Jazz,
    $r('app.string.eq_preset_jazz'),
    [3, 2, 1, 2, 1, 1, 2, 2, 3, 2]
  );

  static readonly CLASSICAL: EqPreset = new EqPreset(
    EqPresetId.Classical,
    $r('app.string.eq_preset_classical'),
    [3, 3, 2, 1, 0, 0, 1, 2, 2, 3]
  );

  static readonly DANCE: EqPreset = new EqPreset(
    EqPresetId.Dance,
    $r('app.string.eq_preset_dance'),
    [6, 5, 2, 0, 1, 2, 3, 2, 4, 5]
  );

  static readonly BALLADS: EqPreset = new EqPreset(
    EqPresetId.Ballads,
    $r('app.string.eq_preset_ballads'),
    [2, 1, 1, 2, 3, 2, 1, 2, 3, 3]
  );

  static readonly RNB: EqPreset = new EqPreset(
    EqPresetId.RnB,
    $r('app.string.eq_preset_rnb'),
    [5, 4, 2, 1, -2, -1, 1, 2, 4, 5]
  );

  static readonly VOICE: EqPreset = new EqPreset(
    EqPresetId.Voice,
    $r('app.string.eq_preset_voice'),
    [-2, -2, 0, 1, 2, 4, 4, 3, 1, 0]
  );

  static readonly ELECTRONIC: EqPreset = new EqPreset(
    EqPresetId.Electronic,
    $r('app.string.eq_preset_electronic'),
    [6, 4, 0, -2, -2, 0, 2, 4, 6, 5]
  );

  /**
   * 获取所有预设列表
   */
  static getAll(): EqPreset[] {
    return [
      EqPresets.DEFAULT,
      EqPresets.POP,
      EqPresets.ROCK,
      EqPresets.JAZZ,
      EqPresets.CLASSICAL,
      EqPresets.DANCE,
      EqPresets.BALLADS,
      EqPresets.RNB,
      EqPresets.VOICE,
      EqPresets.ELECTRONIC
    ];
  }

  /**
   * 根据 ID 获取预设
   */
  static getById(id: string): EqPreset {
    const presets = EqPresets.getAll();
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].id === id) {
        return presets[i];
      }
    }
    return EqPresets.DEFAULT;
  }
}

// ========== DRC 预设 ==========

/**
 * DRC 预设 ID 枚举
 */
export class DrcPresetId {
  static readonly Default: string = 'Default';
  static readonly Speech: string = 'Speech';
  static readonly Vocal: string = 'Vocal';
  static readonly Night: string = 'Night';
  static readonly Mastering: string = 'Mastering';
  static readonly Punch: string = 'Punch';
  static readonly Broadcast: string = 'Broadcast';
  static readonly Limiter: string = 'Limiter';
  static readonly Crush: string = 'Crush';
}

/**
 * DRC 参数数据结构
 */
export class DrcParams {
  threshold: number = -12;
  ratio: number = 2.0;
  attack: number = 10;
  release: number = 100;
  makeup: number = 0;

  constructor(threshold: number, ratio: number, attack: number, release: number, makeup: number) {
    this.threshold = threshold;
    this.ratio = ratio;
    this.attack = attack;
    this.release = release;
    this.makeup = makeup;
  }
}

/**
 * DRC 预设数据结构
 */
export class DrcPreset {
  id: string = '';
  label: ResourceStr;
  params: DrcParams = new DrcParams(-12, 2.0, 10, 100, 0);

  constructor(id: string, label: ResourceStr, params: DrcParams) {
    this.id = id;
    this.label = label;
    this.params = params;
  }
}

/**
 * DRC 预设列表
 */
export class DrcPresets {
  static readonly DEFAULT: DrcPreset = new DrcPreset(
    DrcPresetId.Default,
    $r('app.string.drc_preset_default'),
    new DrcParams(-12, 2.0, 10, 100, 0)
  );

  static readonly SPEECH: DrcPreset = new DrcPreset(
    DrcPresetId.Speech,
    $r('app.string.drc_preset_speech'),
    new DrcParams(-24, 4.0, 5, 80, 6)
  );

  static readonly VOCAL: DrcPreset = new DrcPreset(
    DrcPresetId.Vocal,
    $r('app.string.drc_preset_vocal'),
    new DrcParams(-20, 3.0, 20, 300, 3)
  );

  static readonly NIGHT: DrcPreset = new DrcPreset(
    DrcPresetId.Night,
    $r('app.string.drc_preset_night'),
    new DrcParams(-35, 10.0, 5, 500, 12)
  );

  static readonly MASTERING: DrcPreset = new DrcPreset(
    DrcPresetId.Mastering,
    $r('app.string.drc_preset_mastering'),
    new DrcParams(-10, 1.5, 30, 400, 1)
  );

  static readonly PUNCH: DrcPreset = new DrcPreset(
    DrcPresetId.Punch,
    $r('app.string.drc_preset_punch'),
    new DrcParams(-18, 4.0, 30, 50, 4)
  );

  static readonly BROADCAST: DrcPreset = new DrcPreset(
    DrcPresetId.Broadcast,
    $r('app.string.drc_preset_broadcast'),
    new DrcParams(-20, 6.0, 15, 200, 6)
  );

  static readonly LIMITER: DrcPreset = new DrcPreset(
    DrcPresetId.Limiter,
    $r('app.string.drc_preset_limiter'),
    new DrcParams(-0.5, 20.0, 0.1, 50, 0)
  );

  static readonly CRUSH: DrcPreset = new DrcPreset(
    DrcPresetId.Crush,
    $r('app.string.drc_preset_crush'),
    new DrcParams(-40, 20.0, 0.1, 30, 18)
  );

  /**
   * 获取所有预设列表
   */
  static getAll(): DrcPreset[] {
    return [
      DrcPresets.DEFAULT,
      DrcPresets.SPEECH,
      DrcPresets.VOCAL,
      DrcPresets.NIGHT,
      DrcPresets.MASTERING,
      DrcPresets.PUNCH,
      DrcPresets.BROADCAST,
      DrcPresets.LIMITER,
      DrcPresets.CRUSH
    ];
  }

  /**
   * 根据 ID 获取预设
   */
  static getById(id: string): DrcPreset {
    const presets = DrcPresets.getAll();
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].id === id) {
        return presets[i];
      }
    }
    return DrcPresets.DEFAULT;
  }
}
