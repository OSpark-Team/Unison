import { AppStorageV2, display, PersistenceV2, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import mediaQuery from '@ohos.mediaquery';
import { WindowProperties } from '../model/WindowProperties';
import { BreakpointConstants } from '../common/BreakpointConstants';
import Logger from './Logger';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { ConfigurationConstant } from '@kit.AbilityKit';

const TAG = 'WindowUtil';

/**
 * 窗口工具类
 * 负责窗口管理、安全区避让、响应式断点系统的统一管理
 * 整合了窗口属性监听和媒体查询断点系统
 */
class WindowUtil {
  /** 窗口属性全局实例 */
  private windowProperties: WindowProperties;

  /** 当前断点值 */
  private currentBreakpoint: string = '';

  /** 媒体查询监听器 - 小屏 */
  private smListener?: mediaQuery.MediaQueryListener;

  /** 媒体查询监听器 - 中屏 */
  private mdListener?: mediaQuery.MediaQueryListener;

  /** 媒体查询监听器 - 大屏 */
  private lgListener?: mediaQuery.MediaQueryListener;

  /** UI上下文 */
  private uiContext?: UIContext;

  /** 窗口实例引用，用于设置窗口方向 */
  private windowClass?: window.Window;

  /** 当前方向 override 的归属者 */
  private orientationOverrideOwner: string = '';

  /** 当前方向 override */
  private orientationOverride?: window.Orientation;

  constructor() {
    // 连接全局窗口属性
    this.windowProperties = AppStorageV2.connect(
      WindowProperties,
      'WindowProperties',
      () => new WindowProperties()
    )!;
  }

  /**
   * 更新当前断点
   * 只有当断点值发生变化时才更新，避免不必要的状态更新
   * 断点更新后会自动设置窗口方向
   * @param breakpoint 新的断点值
   */
  private updateCurrentBreakpoint(breakpoint: string): void {
    if (this.currentBreakpoint !== breakpoint) {
      this.currentBreakpoint = breakpoint;
      if (!this.windowProperties) {
        Logger.error(TAG, '窗口属性全局响应式不存在');
        return;
      }
      this.windowProperties.currentBreakpoint = breakpoint;
      Logger.info(TAG, `断点已更新: ${breakpoint}`);

      // 断点变化时自动设置窗口方向
      if (this.windowClass) {
        this.applyWindowOrientation();
      }
    }
  }

  /**
   * 小屏断点匹配回调
   * @param mediaQueryResult 媒体查询结果
   */
  private isBreakpointSM = (mediaQueryResult: mediaQuery.MediaQueryResult): void => {
    if (mediaQueryResult.matches) {
      this.updateCurrentBreakpoint(BreakpointConstants.BREAKPOINT_SM);
    }
  }

  /**
   * 中屏断点匹配回调
   * @param mediaQueryResult 媒体查询结果
   */
  private isBreakpointMD = (mediaQueryResult: mediaQuery.MediaQueryResult): void => {
    if (mediaQueryResult.matches) {
      this.updateCurrentBreakpoint(BreakpointConstants.BREAKPOINT_MD);
    }
  }

  /**
   * 大屏断点匹配回调
   * @param mediaQueryResult 媒体查询结果
   */
  private isBreakpointLG = (mediaQueryResult: mediaQuery.MediaQueryResult): void => {
    if (mediaQueryResult.matches) {
      this.updateCurrentBreakpoint(BreakpointConstants.BREAKPOINT_LG);
    }
  }

  /**
   * 检测当前断点
   * 使用媒体查询同步匹配当前窗口尺寸对应的断点
   */
  private detectCurrentBreakpoint(): void {
    if (!this.uiContext) {
      Logger.error(TAG, 'UIContext 未初始化');
      return;
    }

    try {
      const mediaQuery = this.uiContext.getMediaQuery();
      if (mediaQuery.matchMediaSync(BreakpointConstants.RANGE_SM).matches) {
        this.updateCurrentBreakpoint(BreakpointConstants.BREAKPOINT_SM);
      } else if (mediaQuery.matchMediaSync(BreakpointConstants.RANGE_MD).matches) {
        this.updateCurrentBreakpoint(BreakpointConstants.BREAKPOINT_MD);
      } else if (mediaQuery.matchMediaSync(BreakpointConstants.RANGE_LG).matches) {
        this.updateCurrentBreakpoint(BreakpointConstants.BREAKPOINT_LG);
      }
    } catch (error) {
      Logger.error(TAG, `检测当前断点失败: ${error.message}`);
    }
  }

  /**
   * 初始化显示信息
   * 获取并存储设备显示的宽度和高度
   */
  private initializeDisplayInfo(): void {
    try {
      const displayW = display.getDefaultDisplaySync().width;
      const displayH = display.getDefaultDisplaySync().height;
      AppStorage.setOrCreate('displayW', displayW);
      AppStorage.setOrCreate('displayH', displayH);
      Logger.info(TAG, `显示信息已初始化: ${displayW}x${displayH}`);
    } catch (error) {
      Logger.error(TAG, `初始化显示信息失败: ${error.message}`);
    }
  }

  /**
   * 注册媒体查询监听器
   * 监听窗口尺寸变化，自动更新断点
   * @param uiContext UI上下文
   */
  private registerMediaQueryListeners(uiContext: UIContext): void {
    try {
      this.uiContext = uiContext;
      const mediaQuery = uiContext.getMediaQuery();

      // 注册小屏监听器
      this.smListener = mediaQuery.matchMediaSync(BreakpointConstants.RANGE_SM);
      this.smListener.on('change', this.isBreakpointSM);

      // 注册中屏监听器
      this.mdListener = mediaQuery.matchMediaSync(BreakpointConstants.RANGE_MD);
      this.mdListener.on('change', this.isBreakpointMD);

      // 注册大屏监听器
      this.lgListener = mediaQuery.matchMediaSync(BreakpointConstants.RANGE_LG);
      this.lgListener.on('change', this.isBreakpointLG);

      Logger.info(TAG, '媒体查询监听器注册成功');
    } catch (error) {
      Logger.error(TAG, `注册媒体查询监听器失败: ${error.message}`);
    }
  }

  /**
   * 注销媒体查询监听器
   * 在页面销毁时调用，释放资源
   */
  public unregisterMediaQueryListeners(): void {
    this.smListener?.off('change', this.isBreakpointSM);
    this.mdListener?.off('change', this.isBreakpointMD);
    this.lgListener?.off('change', this.isBreakpointLG);
    Logger.info(TAG, '媒体查询监听器已注销');
  }

  /**
   * 解析当前应使用的窗口方向
   * override 优先，其次走默认断点策略
   */
  private resolveCurrentBreakpointValue(): string {
    if (this.currentBreakpoint.length > 0) {
      return this.currentBreakpoint;
    }

    if (this.windowProperties.currentBreakpoint.length > 0) {
      return this.windowProperties.currentBreakpoint;
    }

    return BreakpointConstants.BREAKPOINT_SM;
  }

  /**
   * 解析当前断点对应的默认窗口方向
   */
  private resolveDefaultWindowOrientation(): window.Orientation {
    return this.resolveCurrentBreakpointValue() === BreakpointConstants.BREAKPOINT_SM
      ? window.Orientation.PORTRAIT
      : window.Orientation.AUTO_ROTATION_RESTRICTED;
  }

  /**
   * 解析当前应使用的窗口方向
   * override 优先，其次走默认断点策略
   */
  private resolveWindowOrientation(): window.Orientation {
    if (this.orientationOverride !== undefined) {
      return this.orientationOverride;
    }

    return this.resolveDefaultWindowOrientation();
  }

  /**
   * 设置窗口方向（核心改造：使用 callback 保证窗口真正转换完成后再 resolve 释放拦截）
   * @param windowClass 窗口实例
   * @param orientation 目标方向
   */
  private setWindowOrientation(windowClass: window.Window,
    orientation: window.Orientation): Promise<void> {
    return new Promise<void>((resolve) => {
      try {
        windowClass.setPreferredOrientation(orientation, (err: BusinessError) => {
          if (err && err.code) {
            Logger.error(TAG, `设置窗口方向异常: code=${err.code}, message=${err.message}`);
          } else {
            Logger.debug(TAG, `窗口方向已物理转换完毕: ${orientation}`);
          }
          // 确保底层回调执行后，才放行上层的 Promise
          resolve();
        });
      } catch (error) {
        Logger.error(TAG, `设置窗口方向抛出异常: ${JSON.stringify(error)}`);
        resolve(); // 防止意外死锁
      }
    });
  }

  /**
   * 应用当前窗口方向
   */
  private applyWindowOrientation(): void {
    if (!this.windowClass) {
      return;
    }

    this.setWindowOrientation(this.windowClass, this.resolveWindowOrientation());
  }

  /**
   * 设置窗口监听器
   * 监听窗口尺寸变化和安全区避让变化
   * 注意：断点检测由媒体查询系统统一管理，此处只更新窗口尺寸信息
   * @param windowClass 窗口实例
   */
  private setWindowListeners(windowClass: window.Window): void {
    const uiContext = windowClass.getUIContext();

    // 监听窗口尺寸变化
    windowClass.on('windowSizeChange', (windowSize) => {
      // 更新窗口尺寸信息
      this.windowProperties.winWidth = uiContext.px2vp(windowSize.width);
      this.windowProperties.winHeight = uiContext.px2vp(windowSize.height);

      // 获取窗口装饰高度（如果支持）
      if (canIUse('SystemCapability.Window.SessionManager')) {
        const height = windowClass.getWindowDecorHeight();
        this.windowProperties.decorHeight = uiContext.px2vp(height);
      }
    });
    Logger.info(TAG, '窗口尺寸变化监听器已添加');

    // 监听安全区避让变化
    windowClass.on('avoidAreaChange', (avoidArea) => {
      if (avoidArea.type === window.AvoidAreaType.TYPE_SYSTEM) {
        // 系统状态栏避让
        this.windowProperties.topRect = uiContext.px2vp(avoidArea.area.topRect.height);
      } else if (avoidArea.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        // 导航栏避让
        this.windowProperties.bottomRect = uiContext.px2vp(avoidArea.area.bottomRect.height);
      } else if (avoidArea.type === window.AvoidAreaType.TYPE_CUTOUT) {
        // 刘海屏避让
        this.windowProperties.leftCutoutRectHeight = uiContext.px2vp(avoidArea.area.leftRect.height);
        this.windowProperties.leftCutoutRectWidth = uiContext.px2vp(avoidArea.area.leftRect.width);
        this.windowProperties.rightCutoutRectHeight = uiContext.px2vp(avoidArea.area.rightRect.height);
        this.windowProperties.rightCutoutRectWidth = uiContext.px2vp(avoidArea.area.rightRect.width);
      }
    });
    Logger.info(TAG, '安全区避让变化监听器已添加');
  }

  /**
   * 初始化窗口属性
   * 获取窗口的初始尺寸、安全区信息等
   * 注意：断点由媒体查询系统统一管理，此处不设置断点
   * @param windowClass 窗口实例
   */
  private initializeWindowProperties(windowClass: window.Window): void {
    const uiContext = windowClass.getUIContext();

    try {
      // 获取系统状态栏避让区域
      const systemAvoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.windowProperties.topRect = uiContext.px2vp(systemAvoidArea.topRect.height);
      Logger.info(TAG, `顶部安全区高度: ${this.windowProperties.topRect}vp`);

      // 获取导航栏避让区域
      const navAvoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.windowProperties.bottomRect = uiContext.px2vp(navAvoidArea.bottomRect.height);
      Logger.info(TAG, `底部安全区高度: ${this.windowProperties.bottomRect}vp`);

      // 获取窗口尺寸
      const windowSize = windowClass.getWindowProperties().windowRect;
      this.windowProperties.winWidth = uiContext.px2vp(windowSize.width);
      this.windowProperties.winHeight = uiContext.px2vp(windowSize.height);
      Logger.info(TAG, `窗口尺寸: ${this.windowProperties.winWidth}x${this.windowProperties.winHeight}vp`);

      // 获取窗口装饰高度（如果支持）
      if (canIUse('SystemCapability.Window.SessionManager')) {
        const height = windowClass.getWindowDecorHeight();
        this.windowProperties.decorHeight = uiContext.px2vp(height);
        Logger.info(TAG, `窗口装饰高度: ${this.windowProperties.decorHeight}vp`);
      }
    } catch (error) {
      Logger.error(TAG, `初始化窗口属性失败: ${error.message}`);
    }
  }

  /**
   * 设置导航条显隐
   * @param enable 显隐控制
   */
  public setSystemBarEnabled(enable: boolean = true){
    try {
      if(canIUse('SystemCapability.Window.SessionManager')){
        let promise = this.windowClass!.setSpecificSystemBarEnabled('navigationIndicator', enable, true);
        promise.then(() => {
          if(enable){
            Logger.info(TAG, 'Succeeded in setting the system bar to be visible.');
          }else{
            Logger.info(TAG, 'Succeeded in setting the system bar to be invisible.');
          }
        }).catch((err: BusinessError) => {
          Logger.error(TAG, `Failed to set the system bar to be invisible. Cause code: ${err.code}, message: ${err.message}`);
        });
      }
    } catch (exception) {
      Logger.error(TAG, `Failed to set the system bar to be invisible. Cause code: ${exception.code}, message: ${exception.message}`);
    }
  }

  /**
   * 设置屏幕常亮开关
   * @param isKeepScreenOn 开关与否
   **/
  public setWindowScreenOn(isKeepScreenOn: boolean){
    try {
      this.windowClass!.setWindowKeepScreenOn(isKeepScreenOn, (err: BusinessError) => {
        const errCode: number = err.code;
        if (errCode) {
          Logger.error(TAG, `Failed to set the screen to be always on. Cause code: ${err.code}, message: ${err.message}`);
          return;
        }
        Logger.info(TAG, `Succeeded in setting the screen to be always on: ${isKeepScreenOn}.`);
      });
    } catch (exception) {
      Logger.error(TAG, `Failed to set the screen to be always on. Cause code: ${exception.code}, message: ${exception.message}`);
    }
  }

  private applyPersistedAppearance(): void {
    let settingModel: SettingViewModel =
      PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
    let appContext = this.uiContext?.getHostContext()?.getApplicationContext();

    if (!appContext) {
      Logger.error(TAG, 'Failed to restore appearance: HostContext is null.');
      return;
    }

    try {
      if (settingModel.theme === 'light') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (settingModel.theme === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (err) {
      Logger.error(TAG, 'Failed to restore color mode. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      appContext.setLanguage(settingModel.lang);
    } catch (err) {
      Logger.error(TAG, 'Failed to restore language. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 加载页面内容
   * 初始化窗口、设置全屏布局、注册监听器、初始化断点系统
   * @param windowStage 窗口舞台
   */
  public loadContent(windowStage: window.WindowStage): void {
    if (!windowStage) {
      Logger.error(TAG, 'WindowStage 为空，无法加载内容');
      return;
    }

    const storage: LocalStorage = new LocalStorage();

    windowStage.getMainWindow().then((windowClass) => {
      // 保存窗口实例引用，用于后续设置窗口方向
      this.windowClass = windowClass;

      windowClass.loadContent('pages/Index', storage, (err: BusinessError) => {
        if (err.code) {
          Logger.error(TAG, `加载页面内容失败: code=${err.code}, message=${err.message}`);
          return;
        }

        Logger.info(TAG, '页面内容加载成功');

        try {
          // 设置全屏布局
          windowClass.setWindowLayoutFullScreen(true).catch((error: Error) => {
            Logger.error(TAG, `设置全屏布局失败: ${JSON.stringify(error)}`);
          });

          // 初始化窗口属性
          this.initializeWindowProperties(windowClass);

          // 设置窗口监听器
          this.setWindowListeners(windowClass);

          // 注册媒体查询监听器
          const uiContext = windowClass.getUIContext();
          this.registerMediaQueryListeners(uiContext);

          // 检测当前断点（会自动触发窗口方向设置）
          this.detectCurrentBreakpoint();

          // 初始化显示信息
          this.initializeDisplayInfo();

          // 初始化设置语种和配色方案
          this.applyPersistedAppearance();

          Logger.info(TAG, '窗口工具初始化完成');
        } catch (exception) {
          Logger.error(TAG, `初始化窗口监听器失败: code=${exception.code}, message=${exception.message}`);
        }
      });
    }).catch((error:Error) => {
      Logger.error(TAG, `获取主窗口失败: ${JSON.stringify(error)}`);
    });
  }

  // 获取UI上下文
  public getUIContext(): UIContext | undefined {
    return this.uiContext;
  }

  /**
   * 设置窗口方向 override (向外暴露 Promise)
   * @param owner override 归属者
   * @param orientation 目标方向
   */
  public setOrientationOverride(owner: string, orientation: window.Orientation): Promise<void> {
    this.orientationOverrideOwner = owner;
    this.orientationOverride = orientation;
    Logger.info(TAG, `设置方向 override: owner=${owner}, orientation=${orientation}`);
    if (!this.windowClass) {
      return Promise.resolve();
    }

    return this.setWindowOrientation(this.windowClass, orientation);
  }

  /**
   * 清除窗口方向 override (向外暴露 Promise)
   * @param owner override 归属者
   */
  public clearOrientationOverride(owner: string): Promise<void> {
    if (this.orientationOverrideOwner.length === 0 || this.orientationOverride === undefined) {
      return Promise.resolve();
    }

    if (this.orientationOverrideOwner !== owner) {
      Logger.debug(TAG, `忽略清理方向 override: owner=${owner}, currentOwner=${this.orientationOverrideOwner}`);
      return Promise.resolve();
    }

    this.orientationOverrideOwner = '';
    this.orientationOverride = undefined;
    Logger.info(TAG, `清理方向 override: owner=${owner}`);

    if (!this.windowClass) {
      return Promise.resolve();
    }

    return this.setWindowOrientation(this.windowClass, this.resolveDefaultWindowOrientation());
  }
}

export default new WindowUtil();