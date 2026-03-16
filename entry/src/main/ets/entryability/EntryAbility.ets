import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2, PersistenceV2, promptAction, window } from '@kit.ArkUI';
import WindowUtil from '../utils/WindowUtil';
import { SourceDataSource } from '../data/SourceDataSource';
import { waitForCondition } from '../utils/Tools';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import BuildProfile from 'BuildProfile';
import { ContinueSwitch } from '../utils/Continue';
import { ContinueData } from '../model/ContinueData';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { avSessionManager } from '../services/AVSessionManager';
import { backgroundRunningManager } from '../utils/BackgroundRunningManager';
import { songPlayerManager } from '../services/SongPlayerManager';
import { resourceUtil } from '../utils/ResourceUtil';
import SettingViewModel from '../viewmodel/SettingViewModel';

const DOMAIN = 0x0000;


export default class EntryAbility extends UIAbility {
  private initialized: boolean = false;

  /**
   * 初始化
   */
  async init(want: Want, launchParam: AbilityConstant.LaunchParam){
    resourceUtil.setAppContext(this.context);

    // 初始化数据源持久化数据库
    await SourceDataSource.initialize(this.context);
    await waitForCondition(() => SourceDataSource.isInitialized(), 50);

    // 初始化应用接续
    ContinueSwitch.initialize(this.context);
    // 默认进行关闭
    await ContinueSwitch.disableContinue();

    // 初始化首选项存储
    await PreferencesUtil.init(this.context);

    // 初始化后台任务
    backgroundRunningManager.init(this.context);

    // 初始化AvSessionManager
    await avSessionManager.init(this.context);

    // 初始化歌曲管理器（提前初始化，避免与UI加载竞态导致首次播放失败）
    songPlayerManager.init();

    // 加载所有数据源
    const sourceListViewModel = AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!
    await sourceListViewModel.loadSources();


    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      // 将上述的保存的数据取出恢复
      if (want.parameters !== undefined) {
        const data = want.parameters.data as ContinueData;
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'ContinueData: ' + JSON.stringify(data));
        ContinueSwitch.setContinueData(data);
      }
    }

    this.initialized = true;
  }

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');

    await this.init(want, launchParam);
  }

  async onDestroy(): Promise<void> {
    backgroundRunningManager.release();
    await songPlayerManager.destroy();
    await SourceDataSource.close();
    await avSessionManager.destroy();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    // DEBUG模式下加载数据库调试
    if (BuildProfile.DEBUG) {
      import('@hulu/debug-db').then(async (ns: ESObject) => {
        await ns.DebugDB.initialize(this.context, { port: 8080, defaultStart: true });
      });
    }
    WindowUtil.loadContent(windowStage);

    let permissions: Array<Permissions> = ['ohos.permission.DISTRIBUTED_DATASYNC'];
    let atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.context, permissions)
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  /**
   * 应用接续页面跳转
   */
  async onWindowStageRestore(windowStage: window.WindowStage) {
    await waitForCondition(() => this.initialized, 50);

    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageRestore');
    // DEBUG模式下加载数据库调试
    if (BuildProfile.DEBUG) {
      import('@hulu/debug-db').then(async (ns: ESObject) => {
        await ns.DebugDB.initialize(this.context, { port: 8080, defaultStart: true });
      });
    }
    WindowUtil.loadContent(windowStage);

    let permissions: Array<Permissions> = ['ohos.permission.DISTRIBUTED_DATASYNC'];
    let atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.context, permissions)
  }

  /**
   * 应用接续
   */
  async onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    await this.init(want, launchParam);
  }

  /**
   * 应用接续
   */
  onContinue(wantParam: Record<string, Object>) {
    const targetVersion = wantParam.version;
    const versionThreshold: number = 0; // 最小支持版本
    // 兼容性校验
    if (targetVersion < versionThreshold) {
      promptAction.openToast({
        message: $r('app.string.unsupported_version')
      })
      return AbilityConstant.OnContinueResult.MISMATCH;
    }
    wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
    // 迁移数据
    const data = ContinueSwitch.getContinueData();
    if (data) {
      wantParam['data'] = data;
    }
    return AbilityConstant.OnContinueResult.AGREE;
  }
}