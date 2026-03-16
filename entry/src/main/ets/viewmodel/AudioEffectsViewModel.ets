/**
 * 音频效果配置 ViewModel
 * 使用 PersistenceV2 持久化 EQ、DRC、音量系数配置
 */
import { Type } from "@kit.ArkUI";

@ObservedV2
export default class AudioEffectsViewModel {
  // ========== EQ 均衡器配置 ==========

  /** EQ 是否启用 */
  @Trace eqEnabled: boolean = false;

  /** 当前 EQ 预设 ID */
  @Trace eqPresetId: string = 'Default';

  /** 是否处于 EQ 自定义状态（用户手动调整） */
  @Trace eqIsCustom: boolean = false;

  /** 当前选中的用户 EQ 预设名称（空表示未选中） */
  @Trace eqSelectedUserPresetName: string = '';

  /** EQ 十段增益值 (dB)，范围 -12 ~ +12 */
  @Trace eqGains: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  /** 用户保存的 EQ 自定义预设（名称 -> gains） */
  @Type(String)
  @Trace eqUserPresetNames: string[] = [];

  @Type(Array) @Type(Number)
  @Trace eqUserPresetGains: number[][] = [];

  // ========== DRC 动态范围压缩配置 ==========

  /** DRC 是否启用 */
  @Trace drcEnabled: boolean = false;

  /** 当前 DRC 预设 ID */
  @Trace drcPresetId: string = 'Default';

  /** 是否处于 DRC 自定义状态（用户手动调整） */
  @Trace drcIsCustom: boolean = false;

  /** 当前选中的用户 DRC 预设名称（空表示未选中） */
  @Trace drcSelectedUserPresetName: string = '';

  /** DRC 阈值 (dB)，范围 -60 ~ 0 */
  @Trace drcThreshold: number = -12;

  /** DRC 压缩比，范围 1 ~ 20 */
  @Trace drcRatio: number = 2.0;

  /** DRC 起始时间 (ms)，范围 0.1 ~ 100 */
  @Trace drcAttack: number = 10;

  /** DRC 释放时间 (ms)，范围 10 ~ 1000 */
  @Trace drcRelease: number = 100;

  /** DRC 补偿增益 (dB)，范围 0 ~ 24 */
  @Trace drcMakeup: number = 0;

  /** 用户保存的 DRC 自定义预设（名称 -> params） */
  @Trace drcUserPresetNames: string[] = [];
  @Trace drcUserPresetThreshold: number[] = [];
  @Trace drcUserPresetRatio: number[] = [];
  @Trace drcUserPresetAttack: number[] = [];
  @Trace drcUserPresetRelease: number[] = [];
  @Trace drcUserPresetMakeup: number[] = [];

  // ========== 音量系数配置 ==========

  /** 音量系数是否启用（独立声道控制） */
  @Trace volumeCoeffEnabled: boolean = false;

  /** 左声道音量系数，范围 0 ~ 2 */
  @Trace leftVolumeCoeff: number = 1.0;

  /** 右声道音量系数，范围 0 ~ 2 */
  @Trace rightVolumeCoeff: number = 1.0;

  // ========== 工具方法 ==========

  /**
   * 重置 EQ 到指定预设
   */
  setEqPreset(presetId: string, gains: number[]): void {
    this.eqPresetId = presetId;
    this.eqGains = [...gains];
    this.eqIsCustom = false;
    this.eqSelectedUserPresetName = '';
  }

  /**
   * 重置 DRC 到指定预设
   */
  setDrcPreset(presetId: string, threshold: number, ratio: number, attack: number, release: number, makeup: number): void {
    this.drcPresetId = presetId;
    this.drcThreshold = threshold;
    this.drcRatio = ratio;
    this.drcAttack = attack;
    this.drcRelease = release;
    this.drcMakeup = makeup;
    this.drcIsCustom = false;
    this.drcSelectedUserPresetName = '';
  }

  /**
   * 重置所有音频效果到默认值
   */
  resetAll(): void {
    this.eqEnabled = false;
    this.eqPresetId = 'Default';
    this.eqGains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    this.eqIsCustom = false;

    this.drcEnabled = false;
    this.drcPresetId = 'Default';
    this.drcThreshold = -12;
    this.drcRatio = 2.0;
    this.drcAttack = 10;
    this.drcRelease = 100;
    this.drcMakeup = 0;
    this.drcIsCustom = false;

    this.volumeCoeffEnabled = false;
    this.leftVolumeCoeff = 1.0;
    this.rightVolumeCoeff = 1.0;
  }

  /** 新增或更新 EQ 用户预设（同名覆盖） */
  upsertEqUserPreset(name: string, gains: number[]): void {
    const trimmedName = name.trim();
    if (trimmedName.length === 0) return;

    let index: number = -1;
    for (let i = 0; i < this.eqUserPresetNames.length; i++) {
      if (this.eqUserPresetNames[i] === trimmedName) {
        index = i;
        break;
      }
    }

    if (index >= 0) {
      const newGainsList = [...this.eqUserPresetGains];
      newGainsList[index] = [...gains];
      this.eqUserPresetGains = newGainsList;
      return;
    }

    this.eqUserPresetNames = [...this.eqUserPresetNames, trimmedName];
    this.eqUserPresetGains = [...this.eqUserPresetGains, [...gains]];
  }

  /** 删除 EQ 用户预设（按名称） */
  deleteEqUserPreset(name: string): void {
    const trimmedName = name.trim();
    if (trimmedName.length === 0) return;

    let index: number = -1;
    for (let i = 0; i < this.eqUserPresetNames.length; i++) {
      if (this.eqUserPresetNames[i] === trimmedName) {
        index = i;
        break;
      }
    }
    if (index < 0) return;

    const newNames: string[] = [];
    const newGains: number[][] = [];
    for (let i = 0; i < this.eqUserPresetNames.length; i++) {
      if (i === index) continue;
      newNames.push(this.eqUserPresetNames[i]);
      newGains.push(this.eqUserPresetGains[i]);
    }
    this.eqUserPresetNames = newNames;
    this.eqUserPresetGains = newGains;

    if (this.eqSelectedUserPresetName === trimmedName) {
      this.eqSelectedUserPresetName = '';
      // 删除后保留当前参数，但切回“自定义”状态
      this.eqPresetId = 'Default';
      this.eqIsCustom = true;
    }
  }

  /** 新增或更新 DRC 用户预设（同名覆盖） */
  upsertDrcUserPreset(name: string, threshold: number, ratio: number, attack: number, release: number, makeup: number): void {
    const trimmedName = name.trim();
    if (trimmedName.length === 0) return;

    let index: number = -1;
    for (let i = 0; i < this.drcUserPresetNames.length; i++) {
      if (this.drcUserPresetNames[i] === trimmedName) {
        index = i;
        break;
      }
    }

    if (index >= 0) {
      const newThreshold = [...this.drcUserPresetThreshold];
      const newRatio = [...this.drcUserPresetRatio];
      const newAttack = [...this.drcUserPresetAttack];
      const newRelease = [...this.drcUserPresetRelease];
      const newMakeup = [...this.drcUserPresetMakeup];

      newThreshold[index] = threshold;
      newRatio[index] = ratio;
      newAttack[index] = attack;
      newRelease[index] = release;
      newMakeup[index] = makeup;

      this.drcUserPresetThreshold = newThreshold;
      this.drcUserPresetRatio = newRatio;
      this.drcUserPresetAttack = newAttack;
      this.drcUserPresetRelease = newRelease;
      this.drcUserPresetMakeup = newMakeup;
      return;
    }

    this.drcUserPresetNames = [...this.drcUserPresetNames, trimmedName];
    this.drcUserPresetThreshold = [...this.drcUserPresetThreshold, threshold];
    this.drcUserPresetRatio = [...this.drcUserPresetRatio, ratio];
    this.drcUserPresetAttack = [...this.drcUserPresetAttack, attack];
    this.drcUserPresetRelease = [...this.drcUserPresetRelease, release];
    this.drcUserPresetMakeup = [...this.drcUserPresetMakeup, makeup];
  }

  /** 删除 DRC 用户预设（按名称） */
  deleteDrcUserPreset(name: string): void {
    const trimmedName = name.trim();
    if (trimmedName.length === 0) return;

    let index: number = -1;
    for (let i = 0; i < this.drcUserPresetNames.length; i++) {
      if (this.drcUserPresetNames[i] === trimmedName) {
        index = i;
        break;
      }
    }
    if (index < 0) return;

    const newNames: string[] = [];
    const newThreshold: number[] = [];
    const newRatio: number[] = [];
    const newAttack: number[] = [];
    const newRelease: number[] = [];
    const newMakeup: number[] = [];

    for (let i = 0; i < this.drcUserPresetNames.length; i++) {
      if (i === index) continue;
      newNames.push(this.drcUserPresetNames[i]);
      newThreshold.push(this.drcUserPresetThreshold[i]);
      newRatio.push(this.drcUserPresetRatio[i]);
      newAttack.push(this.drcUserPresetAttack[i]);
      newRelease.push(this.drcUserPresetRelease[i]);
      newMakeup.push(this.drcUserPresetMakeup[i]);
    }

    this.drcUserPresetNames = newNames;
    this.drcUserPresetThreshold = newThreshold;
    this.drcUserPresetRatio = newRatio;
    this.drcUserPresetAttack = newAttack;
    this.drcUserPresetRelease = newRelease;
    this.drcUserPresetMakeup = newMakeup;

    if (this.drcSelectedUserPresetName === trimmedName) {
      this.drcSelectedUserPresetName = '';
      // 删除后保留当前参数，但切回“自定义”状态
      this.drcPresetId = 'Default';
      this.drcIsCustom = true;
    }
  }
}
