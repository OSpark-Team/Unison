import { AbilityConstant, common } from '@kit.AbilityKit';
import { ContinueData } from '../model/ContinueData';
import { PreferencesUtil } from './PreferencesUtil';

/**
 * 应用接续开关工具类
 */
export class ContinueSwitch {
  private static _context: common.UIAbilityContext | null = null;

  /**
   * 初始化应用上下文
   * @param context 应用上下文
   */
  public static initialize(context: common.UIAbilityContext): void {
    ContinueSwitch._context = context;
  }

  /**
   * 开启应用接续
   * @returns 是否成功
   */
  public static async enableContinue(): Promise<boolean> {
    if (!ContinueSwitch._context) {
      return false;
    }
    try {
      await ContinueSwitch._context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE);
      return true;
    }
    catch (error) {
      return false;
    }
  }

  /**
   * 禁用应用接续
   * @returns 是否成功
   */
  public static async disableContinue(): Promise<boolean> {
    if (!ContinueSwitch._context) {
      return false;
    }
    try {
      await ContinueSwitch._context.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE);
      return true;
    }
    catch (error) {
      return false;
    }
  }

  /**
   * 设置应用接续数据
   * @param data 接续数据
   */
  public static setContinueData(data: ContinueData) {
    AppStorage.setOrCreate<ContinueData>('continue_data', data);
  }

  /**
   * 获取应用接续数据
   * @returns 接续数据
   */
  public static getContinueData(): ContinueData | undefined {
    const data = AppStorage.get<ContinueData>('continue_data');
    return data
  }
}