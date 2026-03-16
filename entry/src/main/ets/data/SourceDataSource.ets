import { relationalStore } from '@kit.ArkData';
import { SourceDatabaseConstants } from '../common/SourceDatabaseConstants';
import { Source } from '../model/Source';
import Logger from '../utils/Logger';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';

const TAG = 'SourceDataSource';

/**
 * 同步状态枚举
 */
export enum SyncStatus {
  /** 空闲状态 */
  IDLE = 'idle',
  /** 同步中 */
  SYNCING = 'syncing',
  /** 同步成功 */
  SUCCESS = 'success',
  /** 同步失败 */
  FAILED = 'failed'
}

/**
 * 同步结果接口
 */
export interface SyncResult {
  /** 同步状态 */
  status: SyncStatus;
  /** 成功同步的设备数量 */
  successCount: number;
  /** 失败的设备数量 */
  failedCount: number;
  /** 合并的记录数量 */
  mergedCount: number;
  /** 错误信息（如果有） */
  errorMessage?: string;
}

/**
 * 数据源数据源类，封装关系型数据库的增删改查操作
 * 支持跨设备分布式数据同步
 */
export class SourceDataSource {
  /**
   * 数据库配置
   */
  private static _config: relationalStore.StoreConfig = {
    name: SourceDatabaseConstants.DATABASE_NAME,
    securityLevel: relationalStore.SecurityLevel.S3,
    encrypt: false,
  };

  /**
   * 关系型数据库存储实例
   */
  private static _rdbStore: relationalStore.RdbStore | null = null;

  /**
   * 当前同步状态
   */
  private static _syncStatus: SyncStatus = SyncStatus.IDLE;

  /**
   * 数据变化回调函数列表
   */
  private static _dataChangeCallbacks: Array<(devices: string[]) => void> = [];

  /**
   * 获取当前数据库存储实例
   */
  public static get rdbStore(): relationalStore.RdbStore | null {
    if (SourceDataSource._rdbStore === null) {
      Logger.error(TAG, 'RdbStore 未初始化，请先调用 initialize() 并等待完成。');
    }
    return SourceDataSource._rdbStore;
  }

  /**
   * 获取当前同步状态
   */
  public static get syncStatus(): SyncStatus {
    return SourceDataSource._syncStatus;
  }

  /**
   * 检查数据库是否已初始化
   */
  public static isInitialized(): boolean {
    return SourceDataSource._rdbStore !== null;
  }

  /**
   * 初始化数据库
   *
   * 同步策略说明：
   * - 在以下两种情况下执行初始同步：
   *   1. 首次创建数据库（isNewDatabase === true）
   *   2. 本地数据库为空（getLocalRecordCount() === 0）
   * - 这样即使首次同步未完成就退出，下次启动时仍会尝试同步
   * - 通过 dataChange 事件进行后续增量同步
   *
   * @param context 应用上下文
   */
  public static async initialize(context: Context): Promise<void> {
    if (SourceDataSource._rdbStore !== null) {
      Logger.warn(TAG, 'RdbStore 已初始化，跳过重复初始化。');
      return;
    }

    try {
      Logger.info(TAG, '开始初始化 RdbStore...');
      const store = await relationalStore.getRdbStore(context, SourceDataSource._config);
      SourceDataSource._rdbStore = store;

      // 请求分布式数据同步权限
      const permissions: Array<Permissions> = ['ohos.permission.DISTRIBUTED_DATASYNC'];
      const atManager = abilityAccessCtrl.createAtManager();
      await atManager.requestPermissionsFromUser(context, permissions);

      // 标记是否为首次创建数据库
      let isNewDatabase = false;

      if (store.version === 0) {
        isNewDatabase = true;
        Logger.info(TAG, '数据库首次创建，执行初始化脚本...');

        // 创建数据源表
        await store.executeSql(SourceDatabaseConstants.CREATE_TABLE_SOURCES);
        Logger.info(TAG, '创建 sources 表成功');

        // 创建索引
        await store.executeSql(SourceDatabaseConstants.CREATE_INDEX_CREATED_AT);
        await store.executeSql(SourceDatabaseConstants.CREATE_INDEX_TYPE);
        Logger.info(TAG, '创建索引成功');

        store.version = SourceDatabaseConstants.DATABASE_VERSION;
        Logger.info(TAG, 'RdbStore 初始化成功（新建数据库）。');
      } else {
        Logger.info(TAG, `RdbStore 初始化成功（已存在，版本: ${store.version}）。`);
      }

      // 设置分布式数据库表
      await store.setDistributedTables([SourceDatabaseConstants.TABLE_SOURCES]);
      Logger.info(TAG, '分布式表设置成功');

      // 订阅远程数据变化（增量同步的主要触发点）
      SourceDataSource.subscribeRemoteDataChange();

      // 判断是否需要执行初始同步（后台异步，不阻塞主线程）
      // 情况 1：首次创建数据库
      // 情况 2：本地数据库为空（可能是首次同步未完成就退出了）
      if (isNewDatabase) {
        Logger.info(TAG, '首次创建数据库，启动后台初始同步...');
        SourceDataSource.performInitialSync();
      } else {
        // 检查本地数据库是否为空
        const localCount = await SourceDataSource.getLocalRecordCount();
        if (localCount === 0) {
          Logger.info(TAG, '本地数据库为空，启动后台初始同步（可能是上次同步未完成）...');
          SourceDataSource.performInitialSync();
        } else {
          Logger.info(TAG, `本地数据库有 ${localCount} 条记录，跳过初始同步（依赖 dataChange 事件）`);
        }
      }

    } catch (error) {
      const errorMsg = `RdbStore 初始化失败: ${error.message}`;
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }
  }

  /**
   * 获取本地数据库中的记录数量
   *
   * 用途：判断本地数据库是否为空，决定是否需要执行初始同步
   *
   * @returns 本地记录数量
   */
  private static async getLocalRecordCount(): Promise<number> {
    if (!SourceDataSource._rdbStore) {
      return 0;
    }

    try {
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      const resultSet = await SourceDataSource._rdbStore.query(predicates);
      const count = resultSet.rowCount;
      resultSet.close();
      return count;
    } catch (error) {
      Logger.error(TAG, `获取本地记录数量失败: ${error.message}`);
      return 0;
    }
  }

  /**
   * 执行初始同步策略（后台异步执行，不阻塞主线程）
   *
   * 同步策略：双向合并
   * 1. 先拉取所有远程设备的数据，合并到本地（按时间戳去重，保留最新）
   * 2. 再推送本地数据到远程设备
   * 3. 这样可以确保所有设备的数据最终一致
   *
   * 合并逻辑：
   * - 远程有、本地无 → 插入到本地
   * - 远程有、本地有 → 比较时间戳，保留最新的
   * - 远程无、本地有 → 保留本地数据（推送时会同步到远程）
   */
  private static async performInitialSync(): Promise<void> {
    try {
      Logger.info(TAG, '开始后台初始同步...');

      const devices = SourceDataSource.getAvailableDevices();

      if (devices.length === 0) {
        Logger.info(TAG, '未找到可用设备，跳过初始同步');
        return;
      }

      Logger.info(TAG, `发现 ${devices.length} 个可用设备，开始双向同步...`);

      // 步骤 1：拉取远程数据并合并到本地
      // 使用 SYNC_MODE_PULL 让远程数据同步到本地分布式表
      Logger.info(TAG, '步骤 1/2：拉取远程数据...');
      await SourceDataSource.sync(relationalStore.SyncMode.SYNC_MODE_PULL);

      // 步骤 2：遍历每个设备，将其分布式表数据合并到本地主表
      let totalMerged = 0;
      for (const deviceId of devices) {
        try {
          const mergedCount = await SourceDataSource.mergeRemoteData(deviceId);
          totalMerged += mergedCount;
          Logger.info(TAG, `设备 ${deviceId} 合并完成，合并记录数: ${mergedCount}`);
        } catch (error) {
          Logger.error(TAG, `设备 ${deviceId} 合并失败: ${error.message}`);
        }
      }

      Logger.info(TAG, `远程数据合并完成，总合并记录数: ${totalMerged}`);

      // 步骤 3：推送本地数据到远程设备
      // 这样远程设备也能获取到本地独有的数据
      Logger.info(TAG, '步骤 2/2：推送本地数据到远程...');
      await SourceDataSource.sync(relationalStore.SyncMode.SYNC_MODE_PUSH);

      Logger.info(TAG, '初始同步完成');

      // 通知所有注册的回调，数据可能已更新
      if (totalMerged > 0) {
        for (const callback of SourceDataSource._dataChangeCallbacks) {
          try {
            callback(devices);
          } catch (error) {
            Logger.error(TAG, `执行数据变化回调失败: ${error.message}`);
          }
        }
      }

    } catch (error) {
      // 同步失败不影响本地数据使用
      Logger.error(TAG, `初始同步失败（不影响本地数据使用）: ${error.message}`);
    }
  }

  /**
   * 订阅远程数据变化
   * 当组网内其他设备的数据发生变化时，会触发回调
   */
  private static subscribeRemoteDataChange(): void {
    if (!SourceDataSource._rdbStore) {
      Logger.error(TAG, '订阅远程数据变化失败：数据库未初始化');
      return;
    }

    try {
      SourceDataSource._rdbStore.on('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE, async (devices) => {
        Logger.info(TAG, `收到远程数据变化通知，设备数量: ${devices.length}`);

        for (const device of devices) {
          Logger.info(TAG, `设备 ${device} 数据有更新，开始合并...`);
          try {
            await SourceDataSource.mergeRemoteData(device);
            Logger.info(TAG, `设备 ${device} 数据合并完成`);
          } catch (error) {
            Logger.error(TAG, `设备 ${device} 数据合并失败: ${error.message}`);
          }
        }

        // 通知所有注册的回调
        for (const callback of SourceDataSource._dataChangeCallbacks) {
          try {
            callback(devices);
          } catch (error) {
            Logger.error(TAG, `执行数据变化回调失败: ${error.message}`);
          }
        }
      });

      Logger.info(TAG, '远程数据变化订阅成功');
    } catch (error) {
      Logger.error(TAG, `订阅远程数据变化失败: ${error.message}`);
    }
  }

  /**
   * 注册数据变化回调
   * @param callback 当远程数据变化时调用的回调函数
   */
  public static onRemoteDataChange(callback: (devices: string[]) => void): void {
    SourceDataSource._dataChangeCallbacks.push(callback);
  }

  /**
   * 取消注册数据变化回调
   * @param callback 要取消的回调函数
   */
  public static offRemoteDataChange(callback: (devices: string[]) => void): void {
    const index = SourceDataSource._dataChangeCallbacks.indexOf(callback);
    if (index > -1) {
      SourceDataSource._dataChangeCallbacks.splice(index, 1);
    }
  }

  /**
   * 获取所有数据源
   *
   * 快速显示策略：
   * 1. 先查询本地数据库
   * 2. 如果本地有数据，直接返回（性能最优）
   * 3. 如果本地为空，立即查询所有远程设备的分布式表
   * 4. 将远程数据临时返回给 UI 显示（不写入本地数据库）
   * 5. 后台同步完成后，数据会正式写入本地数据库
   *
   * 注意：远程查询只在本地数据库为空时执行一次，后续查询直接使用本地数据库
   */
  public static async getAllSources(): Promise<Source[]> {
    if (!SourceDataSource.rdbStore) {
      const errorMsg = '数据库未初始化';
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }

    try {
      // 步骤 1：查询本地数据库
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      predicates.orderByDesc(SourceDatabaseConstants.COLUMN_CREATED_AT);

      const resultSet = await SourceDataSource.rdbStore.query(predicates);
      const localSources: Source[] = [];

      while (resultSet.goToNextRow()) {
        const source = SourceDataSource.parseSourceFromResultSet(resultSet);
        localSources.push(source);
      }

      resultSet.close();

      // 步骤 2：如果本地有数据，直接返回（性能最优）
      if (localSources.length > 0) {
        Logger.info(TAG, `查询到 ${localSources.length} 个本地数据源`);
        return localSources;
      }

      // 步骤 3：本地为空，尝试从远程设备分布式表快速获取数据
      Logger.info(TAG, '本地数据库为空，尝试从远程设备分布式表获取数据...');
      const remoteSources = await SourceDataSource.getSourcesFromRemoteDevices();

      if (remoteSources.length > 0) {
        Logger.info(TAG, `从远程设备获取到 ${remoteSources.length} 个数据源（临时显示）`);
        return remoteSources;
      }

      // 本地和远程都没有数据
      Logger.info(TAG, '本地和远程都没有数据源');
      return [];

    } catch (error) {
      const errorMsg = `查询数据源列表失败: ${error.message}`;
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }
  }

  /**
   * 远程查询超时时间（毫秒）
   */
  private static readonly REMOTE_QUERY_TIMEOUT_MS: number = 3000;

  /**
   * 从所有远程设备直接查询数据源（只读，不写入本地）
   *
   * 用途：在本地数据库为空时，快速显示远程设备的数据
   * 注意：这只是临时显示，后台同步会将数据正式写入本地数据库
   *
   * 实现方式：
   * - 使用 remoteQuery() 直接查询远程设备的原始表
   * - 使用 Promise.allSettled() 并行查询所有设备（提升性能）
   * - 设置超时时间，避免单个设备阻塞整体查询
   *
   * @returns 远程设备的数据源列表（已去重，按时间戳保留最新）
   */
  private static async getSourcesFromRemoteDevices(): Promise<Source[]> {
    if (!SourceDataSource._rdbStore) {
      return [];
    }

    const devices = SourceDataSource.getAvailableDevices();

    if (devices.length === 0) {
      Logger.info(TAG, '未找到可用设备，无法获取远程数据');
      return [];
    }

    Logger.info(TAG, `开始并行查询 ${devices.length} 个远程设备...`);

    // 定义要查询的列名
    const columns: string[] = [
      SourceDatabaseConstants.COLUMN_ID,
      SourceDatabaseConstants.COLUMN_NAME,
      SourceDatabaseConstants.COLUMN_TYPE,
      SourceDatabaseConstants.COLUMN_URL,
      SourceDatabaseConstants.COLUMN_DESCRIPTION,
      SourceDatabaseConstants.COLUMN_TOKEN,
      SourceDatabaseConstants.COLUMN_CREATED_AT,
      SourceDatabaseConstants.COLUMN_UPDATED_AT
    ];

    // 为每个设备创建查询 Promise（带超时）
    const queryPromises = devices.map((deviceId) => {
      return SourceDataSource.queryRemoteDeviceWithTimeout(deviceId, columns);
    });

    // 并行执行所有查询，使用 allSettled 确保即使部分失败也能继续
    const results = await Promise.allSettled(queryPromises);

    // 使用 Map 进行去重，key 为数据源 ID
    const sourceMap = new Map<string, Source>();

    // 处理所有查询结果
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      const deviceId = devices[i];

      if (result.status === 'fulfilled') {
        const deviceSources = result.value;
        Logger.info(TAG, `设备 ${deviceId} 查询成功，获取到 ${deviceSources.length} 条记录`);

        // 合并数据，按时间戳去重
        for (const source of deviceSources) {
          const existing = sourceMap.get(source.id);
          if (existing) {
            // 比较时间戳，保留最新的
            if (source.updated_at > existing.updated_at) {
              Logger.info(TAG, `数据源 ${source.id} 更新时间更新，替换旧数据`);
              sourceMap.set(source.id, source);
            }
          } else {
            sourceMap.set(source.id, source);
          }
        }
      } else {
        Logger.error(TAG, `设备 ${deviceId} 查询失败: ${result.reason}`);
      }
    }

    // 将 Map 转换为数组
    const sources: Source[] = [];
    sourceMap.forEach((source) => {
      sources.push(source);
    });

    Logger.info(TAG, `从远程设备获取到 ${sources.length} 个数据源`);
    return sources;
  }

  /**
   * 查询单个远程设备的数据（带超时）
   *
   * @param deviceId 设备网络 ID
   * @param columns 要查询的列名
   * @returns 该设备的数据源列表
   */
  private static async queryRemoteDeviceWithTimeout(
    deviceId: string,
    columns: string[]
  ): Promise<Source[]> {
    Logger.info(TAG, `正在从设备 ${deviceId} 远程查询数据...`);

    // 创建超时 Promise
    const timeoutPromise = new Promise<Source[]>((_, reject) => {
      setTimeout(() => {
        reject(new Error(`查询超时（${SourceDataSource.REMOTE_QUERY_TIMEOUT_MS}ms）`));
      }, SourceDataSource.REMOTE_QUERY_TIMEOUT_MS);
    });

    // 创建查询 Promise
    const queryPromise = SourceDataSource.queryRemoteDevice(deviceId, columns);

    // 使用 Promise.race 实现超时控制
    return Promise.race([queryPromise, timeoutPromise]);
  }

  /**
   * 查询单个远程设备的数据
   *
   * @param deviceId 设备网络 ID
   * @param columns 要查询的列名
   * @returns 该设备的数据源列表
   */
  private static async queryRemoteDevice(
    deviceId: string,
    columns: string[]
  ): Promise<Source[]> {
    if (!SourceDataSource._rdbStore) {
      return [];
    }

    const sources: Source[] = [];

    // 构造查询谓词
    const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);

    // 使用 remoteQuery 直接查询远程设备的原始表
    const resultSet = await SourceDataSource._rdbStore.remoteQuery(
      deviceId,
      SourceDatabaseConstants.TABLE_SOURCES,
      predicates,
      columns
    );

    const rowCount = resultSet.rowCount;

    if (rowCount <= 0) {
      Logger.info(TAG, `设备 ${deviceId} 远程表为空或查询失败`);
      resultSet.close();
      return sources;
    }

    Logger.info(TAG, `设备 ${deviceId} 远程表有 ${rowCount} 条记录`);

    // 遍历远程数据
    while (resultSet.goToNextRow()) {
      const source = SourceDataSource.parseSourceFromResultSet(resultSet);
      sources.push(source);
    }

    resultSet.close();
    return sources;
  }

  /**
   * 根据 ID 获取数据源
   */
  public static async getSourceById(id: string): Promise<Source | null> {
    if (!SourceDataSource.rdbStore) {
      const errorMsg = '数据库未初始化';
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }

    try {
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      predicates.equalTo(SourceDatabaseConstants.COLUMN_ID, id);

      const resultSet = await SourceDataSource.rdbStore.query(predicates);

      if (resultSet.goToFirstRow()) {
        const source = SourceDataSource.parseSourceFromResultSet(resultSet);
        resultSet.close();
        return source;
      }

      resultSet.close();
      return null;
    } catch (error) {
      const errorMsg = `查询数据源失败: ${error.message}`;
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }
  }

  /**
   * 根据类型获取数据源列表
   */
  public static async getSourcesByType(type: string): Promise<Source[]> {
    if (!SourceDataSource.rdbStore) {
      const errorMsg = '数据库未初始化';
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }

    try {
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      predicates.equalTo(SourceDatabaseConstants.COLUMN_TYPE, type);
      predicates.orderByDesc(SourceDatabaseConstants.COLUMN_CREATED_AT);

      const resultSet = await SourceDataSource.rdbStore.query(predicates);
      const sources: Source[] = [];

      while (resultSet.goToNextRow()) {
        const source = SourceDataSource.parseSourceFromResultSet(resultSet);
        sources.push(source);
      }

      resultSet.close();
      Logger.info(TAG, `查询到 ${sources.length} 个类型为 ${type} 的数据源`);
      return sources;
    } catch (error) {
      const errorMsg = `查询数据源列表失败: ${error.message}`;
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }
  }

  // =================== 分布式同步相关方法 ===================

  /**
   * 获取可用的远程设备列表
   * @returns 设备网络ID列表
   */
  public static getAvailableDevices(): string[] {
    try {
      const deviceManager = distributedDeviceManager.createDeviceManager('zone.yby.unison');
      const deviceList = deviceManager.getAvailableDeviceListSync();
      const devices: string[] = [];

      deviceList.forEach(item => {
        if (item.networkId) {
          Logger.info(TAG, `找到可用设备: ${item.deviceName} (${item.deviceType} - ${item.networkId})`);
          devices.push(item.networkId);
        }
      });

      return devices;
    } catch (error) {
      Logger.error(TAG, `获取可用设备列表失败: ${error.message}`);
      return [];
    }
  }

  /**
   * 同步数据到远程设备（推送模式）
   * @param mode 同步模式（推送或拉取）
   * @returns 同步结果
   */
  public static async sync(mode: relationalStore.SyncMode): Promise<SyncResult> {
    const result: SyncResult = {
      status: SyncStatus.IDLE,
      successCount: 0,
      failedCount: 0,
      mergedCount: 0
    };

    if (!SourceDataSource._rdbStore) {
      result.status = SyncStatus.FAILED;
      result.errorMessage = '数据库未初始化';
      return result;
    }

    try {
      SourceDataSource._syncStatus = SyncStatus.SYNCING;
      result.status = SyncStatus.SYNCING;

      const syncTarget = SourceDataSource.getAvailableDevices();

      if (syncTarget.length === 0) {
        Logger.info(TAG, '未找到可用设备，跳过同步');
        result.status = SyncStatus.SUCCESS;
        SourceDataSource._syncStatus = SyncStatus.IDLE;
        return result;
      }

      Logger.info(TAG, `开始${mode === relationalStore.SyncMode.SYNC_MODE_PUSH ? '推送' : '拉取'}同步，目标设备数: ${syncTarget.length}`);

      // 构造用于同步分布式表的谓词对象
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      predicates.inDevices(syncTarget);

      // 执行同步
      const syncResults = await SourceDataSource._rdbStore.sync(mode, predicates);

      // 处理同步结果
      for (const syncResultItem of syncResults) {
        const deviceId = syncResultItem[0];
        const syncStatus = syncResultItem[1];

        if (syncStatus === 0) {
          result.successCount++;
          Logger.info(TAG, `设备 ${deviceId} 同步成功`);
        } else {
          result.failedCount++;
          Logger.error(TAG, `设备 ${deviceId} 同步失败，状态码: ${syncStatus}`);
        }
      }

      result.status = result.failedCount === 0 ? SyncStatus.SUCCESS : SyncStatus.FAILED;
      SourceDataSource._syncStatus = result.status;

      Logger.info(TAG, `同步完成，成功: ${result.successCount}，失败: ${result.failedCount}`);

    } catch (error) {
      result.status = SyncStatus.FAILED;
      result.errorMessage = error.message;
      SourceDataSource._syncStatus = SyncStatus.FAILED;
      Logger.error(TAG, `同步失败: ${error.message}`);
    }

    return result;
  }

  /**
   * 从所有远程设备拉取数据并合并到本地
   * 适用于首次启动或本地数据库为空的场景
   * @returns 同步结果
   */
  public static async syncFromRemoteDevices(): Promise<SyncResult> {
    const result: SyncResult = {
      status: SyncStatus.IDLE,
      successCount: 0,
      failedCount: 0,
      mergedCount: 0
    };

    if (!SourceDataSource._rdbStore) {
      result.status = SyncStatus.FAILED;
      result.errorMessage = '数据库未初始化';
      return result;
    }

    try {
      SourceDataSource._syncStatus = SyncStatus.SYNCING;
      result.status = SyncStatus.SYNCING;

      const devices = SourceDataSource.getAvailableDevices();

      if (devices.length === 0) {
        Logger.info(TAG, '未找到可用设备，跳过远程数据拉取');
        result.status = SyncStatus.SUCCESS;
        SourceDataSource._syncStatus = SyncStatus.IDLE;
        return result;
      }

      Logger.info(TAG, `开始从 ${devices.length} 个远程设备拉取数据...`);

      // 先执行拉取同步，让远程数据同步到本地分布式表
      const syncResult = await SourceDataSource.sync(relationalStore.SyncMode.SYNC_MODE_PULL);
      result.successCount = syncResult.successCount;
      result.failedCount = syncResult.failedCount;

      // 遍历每个设备，合并其数据到本地表
      for (const deviceId of devices) {
        try {
          const mergedCount = await SourceDataSource.mergeRemoteData(deviceId);
          result.mergedCount += mergedCount;
          Logger.info(TAG, `设备 ${deviceId} 数据合并完成，合并记录数: ${mergedCount}`);
        } catch (error) {
          Logger.error(TAG, `设备 ${deviceId} 数据合并失败: ${error.message}`);
        }
      }

      result.status = SyncStatus.SUCCESS;
      SourceDataSource._syncStatus = SyncStatus.IDLE;

      Logger.info(TAG, `远程数据拉取完成，总合并记录数: ${result.mergedCount}`);

    } catch (error) {
      result.status = SyncStatus.FAILED;
      result.errorMessage = error.message;
      SourceDataSource._syncStatus = SyncStatus.FAILED;
      Logger.error(TAG, `远程数据拉取失败: ${error.message}`);
    }

    return result;
  }

  /**
   * 合并指定设备的远程数据到本地表
   *
   * 注意事项：
   * - 分布式表由系统自动管理，设备离线后会自动清理
   * - rowCount 为 -1 表示查询失败或表不存在，应跳过处理
   * - rowCount 为 0 表示远程设备数据为空，不做任何操作
   * - 只有 rowCount > 0 时才进行数据合并
   *
   * @param deviceId 设备网络ID
   * @returns 合并的记录数量
   */
  public static async mergeRemoteData(deviceId: string): Promise<number> {
    if (!SourceDataSource._rdbStore) {
      throw new Error('数据库未初始化');
    }

    let mergedCount = 0;

    try {
      // 获取该设备对应的分布式表名
      const distributedTableName = await SourceDataSource._rdbStore.obtainDistributedTableName(
        deviceId,
        SourceDatabaseConstants.TABLE_SOURCES
      );

      Logger.info(TAG, `设备 ${deviceId} 的分布式表名: ${distributedTableName}`);

      // 查询分布式表中的所有数据
      const predicates = new relationalStore.RdbPredicates(distributedTableName);
      const resultSet = await SourceDataSource._rdbStore.query(predicates);
      const rowCount = resultSet.rowCount;

      Logger.info(TAG, `设备 ${deviceId} 分布式表中有 ${rowCount} 条记录`);

      // 处理异常情况
      if (rowCount < 0) {
        // rowCount 为 -1 表示查询失败或分布式表不存在
        Logger.warn(TAG, `设备 ${deviceId} 分布式表查询失败或不存在，跳过合并`);
        resultSet.close();
        return 0;
      }

      if (rowCount === 0) {
        // 远程设备数据为空，不做任何操作，保留本地数据
        Logger.info(TAG, `设备 ${deviceId} 数据为空，跳过合并（保留本地数据）`);
        resultSet.close();
        return 0;
      }

      // 遍历远程数据并合并（只有 rowCount > 0 时才执行）
      while (resultSet.goToNextRow()) {
        const remoteSource = SourceDataSource.parseSourceFromResultSet(resultSet);
        const remoteUpdatedAt = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_UPDATED_AT));

        // 检查本地是否存在该记录
        const localSource = await SourceDataSource.getSourceById(remoteSource.id);

        if (localSource === null) {
          // 本地不存在，直接插入
          await SourceDataSource.upsertSourceInternal(remoteSource, remoteUpdatedAt);
          mergedCount++;
          Logger.info(TAG, `插入新记录: ${remoteSource.name} (${remoteSource.id})`);
        } else {
          // 本地存在，比较时间戳决定是否更新
          const localUpdatedAt = await SourceDataSource.getSourceUpdatedAt(localSource.id);

          if (SourceDataSource.resolveConflict(localUpdatedAt, remoteUpdatedAt) === 'remote') {
            // 远程数据更新，更新本地记录
            await SourceDataSource.upsertSourceInternal(remoteSource, remoteUpdatedAt);
            mergedCount++;
            Logger.info(TAG, `更新记录: ${remoteSource.name} (${remoteSource.id})`);
          } else {
            Logger.info(TAG, `跳过记录（本地更新）: ${remoteSource.name} (${remoteSource.id})`);
          }
        }
      }

      resultSet.close();

    } catch (error) {
      Logger.error(TAG, `合并设备 ${deviceId} 数据失败: ${error.message}`);
    }

    return mergedCount;
  }

  /**
   * 数据冲突解决策略
   * 采用"最后写入优先"策略，比较时间戳决定保留哪个版本
   * @param localUpdatedAt 本地记录的更新时间
   * @param remoteUpdatedAt 远程记录的更新时间
   * @returns 'local' 保留本地数据，'remote' 使用远程数据
   */
  private static resolveConflict(localUpdatedAt: string, remoteUpdatedAt: string): 'local' | 'remote' {
    try {
      const localTime = new Date(localUpdatedAt).getTime();
      const remoteTime = new Date(remoteUpdatedAt).getTime();

      // 远程时间更新则使用远程数据
      if (remoteTime > localTime) {
        return 'remote';
      }

      return 'local';
    } catch (error) {
      Logger.error(TAG, `时间戳比较失败: ${error.message}`);
      // 解析失败时保留本地数据
      return 'local';
    }
  }

  /**
   * 获取数据源的更新时间
   * @param id 数据源ID
   * @returns 更新时间字符串
   */
  private static async getSourceUpdatedAt(id: string): Promise<string> {
    if (!SourceDataSource._rdbStore) {
      throw new Error('数据库未初始化');
    }

    const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
    predicates.equalTo(SourceDatabaseConstants.COLUMN_ID, id);

    const resultSet = await SourceDataSource._rdbStore.query(predicates);

    if (resultSet.goToFirstRow()) {
      const updatedAt = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_UPDATED_AT));
      resultSet.close();
      return updatedAt;
    }

    resultSet.close();
    return '';
  }

  /**
   * 内部方法：插入或更新数据源（UPSERT）
   * 用于合并远程数据时使用，不触发同步推送
   * @param source 数据源对象
   * @param updatedAt 更新时间（保留原始时间戳）
   */
  private static async upsertSourceInternal(source: Source, updatedAt: string): Promise<void> {
    if (!SourceDataSource._rdbStore) {
      throw new Error('数据库未初始化');
    }

    const valueBucket: relationalStore.ValuesBucket = {};
    valueBucket[SourceDatabaseConstants.COLUMN_ID] = source.id;
    valueBucket[SourceDatabaseConstants.COLUMN_NAME] = source.name;
    valueBucket[SourceDatabaseConstants.COLUMN_TYPE] = source.type;
    valueBucket[SourceDatabaseConstants.COLUMN_URL] = source.url;
    valueBucket[SourceDatabaseConstants.COLUMN_DESCRIPTION] = source.description;
    valueBucket[SourceDatabaseConstants.COLUMN_TOKEN] = source.token;
    valueBucket[SourceDatabaseConstants.COLUMN_UPDATED_AT] = updatedAt;

    // 检查是否存在
    const existing = await SourceDataSource.getSourceById(source.id);

    if (existing === null) {
      // 插入新记录
      valueBucket[SourceDatabaseConstants.COLUMN_CREATED_AT] = updatedAt;
      await SourceDataSource._rdbStore.insert(SourceDatabaseConstants.TABLE_SOURCES, valueBucket);
    } else {
      // 更新现有记录
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      predicates.equalTo(SourceDatabaseConstants.COLUMN_ID, source.id);
      await SourceDataSource._rdbStore.update(valueBucket, predicates);
    }
  }

  /**
   * 手动触发完整同步
   * 先推送本地变更，再拉取远程变更并合并
   * @returns 同步结果
   */
  public static async fullSync(): Promise<SyncResult> {
    Logger.info(TAG, '开始完整同步...');

    // 先推送本地数据
    const pushResult = await SourceDataSource.sync(relationalStore.SyncMode.SYNC_MODE_PUSH);
    Logger.info(TAG, `推送完成，成功: ${pushResult.successCount}，失败: ${pushResult.failedCount}`);

    // 再拉取并合并远程数据
    const pullResult = await SourceDataSource.syncFromRemoteDevices();
    Logger.info(TAG, `拉取完成，合并记录数: ${pullResult.mergedCount}`);

    return {
      status: pushResult.status === SyncStatus.SUCCESS && pullResult.status === SyncStatus.SUCCESS
        ? SyncStatus.SUCCESS
        : SyncStatus.FAILED,
      successCount: pushResult.successCount + pullResult.successCount,
      failedCount: pushResult.failedCount + pullResult.failedCount,
      mergedCount: pullResult.mergedCount,
      errorMessage: pushResult.errorMessage || pullResult.errorMessage
    };
  }

  /**
   * 插入数据源
   */
  public static async insertSource(source: Source): Promise<void> {
    if (!SourceDataSource.rdbStore) {
      const errorMsg = '数据库未初始化';
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }

    try {
      // 检查是否已存在
      const existing = await SourceDataSource.getSourceById(source.id);
      if (existing) {
        const errorMsg = `数据源已存在: ${source.id}`;
        Logger.error(TAG, errorMsg);
        return Promise.reject(errorMsg);
      }

      // 创建 ValuesBucket 对象
      const valueBucket: relationalStore.ValuesBucket = {};
      valueBucket[SourceDatabaseConstants.COLUMN_ID] = source.id;
      valueBucket[SourceDatabaseConstants.COLUMN_NAME] = source.name;
      valueBucket[SourceDatabaseConstants.COLUMN_TYPE] = source.type;
      valueBucket[SourceDatabaseConstants.COLUMN_URL] = source.url;
      valueBucket[SourceDatabaseConstants.COLUMN_DESCRIPTION] = source.description;
      valueBucket[SourceDatabaseConstants.COLUMN_TOKEN] = source.token;
      valueBucket[SourceDatabaseConstants.COLUMN_CREATED_AT] = new Date().toISOString();
      valueBucket[SourceDatabaseConstants.COLUMN_UPDATED_AT] = new Date().toISOString();

      await SourceDataSource.rdbStore.insert(SourceDatabaseConstants.TABLE_SOURCES, valueBucket);
      SourceDataSource.sync(relationalStore.SyncMode.SYNC_MODE_PUSH);
      Logger.info(TAG, `插入数据源成功: ${source.name}`);
    } catch (error) {
      const errorMsg = `插入数据源失败: ${error.message}`;
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }
  }

  /**
   * 更新数据源
   */
  public static async updateSource(source: Source): Promise<void> {
    if (!SourceDataSource.rdbStore) {
      const errorMsg = '数据库未初始化';
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }

    try {
      // 检查数据源是否存在
      const existing = await SourceDataSource.getSourceById(source.id);
      if (!existing) {
        const errorMsg = `数据源不存在: ${source.id}`;
        Logger.error(TAG, errorMsg);
        return Promise.reject(errorMsg);
      }

      // 创建 ValuesBucket 对象
      const valueBucket: relationalStore.ValuesBucket = {};
      valueBucket[SourceDatabaseConstants.COLUMN_NAME] = source.name;
      valueBucket[SourceDatabaseConstants.COLUMN_TYPE] = source.type;
      valueBucket[SourceDatabaseConstants.COLUMN_URL] = source.url;
      valueBucket[SourceDatabaseConstants.COLUMN_DESCRIPTION] = source.description;
      valueBucket[SourceDatabaseConstants.COLUMN_TOKEN] = source.token;
      valueBucket[SourceDatabaseConstants.COLUMN_UPDATED_AT] = new Date().toISOString();

      // 更新数据库
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      predicates.equalTo(SourceDatabaseConstants.COLUMN_ID, source.id);
      const rows = await SourceDataSource.rdbStore.update(valueBucket, predicates);
      SourceDataSource.sync(relationalStore.SyncMode.SYNC_MODE_PUSH);

      Logger.info(TAG, `更新数据源成功: ${source.name}, 影响行数: ${rows}`);
    } catch (error) {
      const errorMsg = `更新数据源失败: ${error.message}`;
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }
  }

  /**
   * 删除数据源
   */
  public static async deleteSource(id: string): Promise<void> {
    if (!SourceDataSource.rdbStore) {
      const errorMsg = '数据库未初始化';
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }

    try {
      const predicates = new relationalStore.RdbPredicates(SourceDatabaseConstants.TABLE_SOURCES);
      predicates.equalTo(SourceDatabaseConstants.COLUMN_ID, id);

      const rows = await SourceDataSource.rdbStore.delete(predicates);
      SourceDataSource.sync(relationalStore.SyncMode.SYNC_MODE_PUSH);
      Logger.info(TAG, `删除数据源成功，影响行数: ${rows}`);
    } catch (error) {
      const errorMsg = `删除数据源失败: ${error.message}`;
      Logger.error(TAG, errorMsg);
      return Promise.reject(errorMsg);
    }
  }

  /**
   * 关闭数据库
   */
  public static async close(): Promise<void> {
    if (SourceDataSource._rdbStore) {
      try {
        await SourceDataSource._rdbStore.close();
        SourceDataSource._rdbStore = null;
        Logger.info(TAG, '数据库已关闭');
      } catch (error) {
        const errorMsg = `关闭数据库失败: ${error.message}`;
        Logger.error(TAG, errorMsg);
        return Promise.reject(errorMsg);
      }
    }
  }

  /**
   * 从 ResultSet 解析数据源对象
   */
  private static parseSourceFromResultSet(resultSet: relationalStore.ResultSet): Source {
    const source = new Source();

    source.id = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_ID));
    source.name = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_NAME));
    source.type = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_TYPE));
    source.url = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_URL));
    source.description = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_DESCRIPTION));
    source.token = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_TOKEN));
    source.updated_at = resultSet.getString(resultSet.getColumnIndex(SourceDatabaseConstants.COLUMN_UPDATED_AT));

    return source;
  }
}

