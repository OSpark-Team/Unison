import { Source } from '../model/Source';
import { SourceDataSource } from '../data/SourceDataSource';
import Logger from '../utils/Logger';
import OMSPAdapter from '../adapter/omsp';
import axios, { AxiosInstance } from '@ohos/axios';

const TAG = 'SourceListViewModel';

/**
 * 数据源列表 ViewModel
 * 管理数据源列表的状态和业务逻辑
 */
@ObservedV2
export class SourceListViewModel {
  @Trace sources: Source[] = [];
  @Trace isLoading: boolean = false;
  @Trace errorMessage: ResourceStr = '';

  /** 二维码相关状态 */
  @Trace qrCodeUrl: string = '';
  @Trace qrCodeUnikey: string = '';
  @Trace qrCodeStatus: number = 0; // -1: 过期, 0: 等待中, 1: 确认中, 2: 成功
  @Trace isCheckingQRCode: boolean = false;
  @Trace qrCodeStatusText: ResourceStr = '';
  @Trace tokenFromQR: string = '';
  @Trace qrCodeVisible: boolean = false;

  private qrCodeCheckTimer: number = 0;

  /**
   * 从数据库加载数据源列表
   */
  async loadSources(): Promise<void> {
    if (!SourceDataSource.isInitialized()) {
      this.errorMessage = $r('app.string.error_database_not_initialized');
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      this.sources = await SourceDataSource.getAllSources();
      // 获取登录用户信息
      for (const source of this.sources) {
        await source.getLoginStatus();
      }
      Logger.info(TAG, `Loaded ${this.sources.length} sources from DB`);
    } catch (error) {
      this.errorMessage = $r('app.string.error_load_sources_failed', String(error));
      Logger.error(TAG, `Failed to load sources: ${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 添加数据源配置
   */
  async addSource(source: Source): Promise<boolean> {
    if (!SourceDataSource.isInitialized()) {
      this.errorMessage = $r('app.string.error_database_not_initialized');
      return false;
    }

    try {
      await source.create();
      this.sources.push(source);
      Logger.info(TAG, `Source added: ${source.name} (Total: ${this.sources.length})`);
      return true;
    } catch (error) {
      this.errorMessage = $r('app.string.error_add_source_failed', String(error));
      Logger.error(TAG, `Add source failed: ${error}`);
      return false;
    }
  }

  /**
   * 更新数据源配置
   */
  async updateSource(source: Source): Promise<boolean> {
    if (!SourceDataSource.isInitialized()) {
      this.errorMessage = $r('app.string.error_database_not_initialized');
      return false;
    }

    try {
      await source.update(source);
      const index = this.sources.findIndex(s => s.id === source.id);
      if (index !== -1) {
        this.sources[index] = source;
        Logger.info(TAG, `Source updated: ${source.name} at index ${index}`);
      }
      return true;
    } catch (error) {
      this.errorMessage = $r('app.string.error_update_source_failed', String(error));
      Logger.error(TAG, `Update source failed: ${error}`);
      return false;
    }
  }

  /**
   * 删除数据源配置
   */
  async deleteSource(sourceId: string): Promise<boolean> {
    if (!SourceDataSource.isInitialized()) {
      this.errorMessage = $r('app.string.error_database_not_initialized');
      return false;
    }

    try {
      const sourceToDelete = this.sources.find(source => source.id === sourceId);
      if (!sourceToDelete) {
        Logger.warn(TAG, `Delete target not found: ${sourceId}`);
        return false;
      }

      await sourceToDelete.delete();
      const index = this.sources.findIndex(source => source.id === sourceId);
      if (index !== -1) {
        this.sources.splice(index, 1);
      }
      Logger.info(TAG, `Source deleted: ${sourceId} (Remaining: ${this.sources.length})`);
      return true;
    } catch (error) {
      this.errorMessage = $r('app.string.error_delete_source_failed', String(error));
      Logger.error(TAG, `Delete source failed: ${error}`);
      return false;
    }
  }

  /**
   * 生成二维码
   */
  async generateQRCode(url: string, token: string = ''): Promise<void> {
    try {
      this.qrCodeStatus = 0;
      this.qrCodeStatusText = $r('app.string.qr_generating');
      this.tokenFromQR = '';
      this.qrCodeVisible = false;

      const tempAxiosInstance = this.createTempAxiosInstance(url, token);
      this.qrCodeUnikey = await OMSPAdapter.GetQRKey(tempAxiosInstance);

      const qrCode = await OMSPAdapter.CreateQR(tempAxiosInstance, this.qrCodeUnikey);
      this.qrCodeUrl = qrCode.qrimg;
      this.qrCodeStatusText = $r('app.string.qr_scan_prompt');
      this.qrCodeVisible = true;

      Logger.info(TAG, `QRCode generated successfully for URL: ${url}`);
      this.startCheckingQRCode(tempAxiosInstance);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      this.errorMessage = $r('app.string.error_qr_generate_failed', msg);
      this.qrCodeStatusText = $r('app.string.qr_generate_failed');
      Logger.error(TAG, `Generate QRCode failed: ${msg}`);
    }
  }

  private createTempAxiosInstance(url: string, token: string): AxiosInstance {
    return axios.create({
      baseURL: url,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
        'Token': token,
        'User-Agent': 'Unison/1.0(EdgeMusic 3.0)'
      }
    });
  }

  private startCheckingQRCode(axiosInstance: AxiosInstance): void {
    this.isCheckingQRCode = true;
    this.checkQRCodeStatus(axiosInstance);
    this.qrCodeCheckTimer = setInterval(() => {
      this.checkQRCodeStatus(axiosInstance);
    }, 3000);
    Logger.info(TAG, `QRCode status checking started`);
  }

  private async checkQRCodeStatus(axiosInstance: AxiosInstance): Promise<void> {
    if (!this.isCheckingQRCode || !this.qrCodeUnikey) return;

    try {
      const checkResult = await OMSPAdapter.CheckQR(axiosInstance, this.qrCodeUnikey);
      this.qrCodeStatus = checkResult.status;

      switch (checkResult.status) {
        case -1:
          this.qrCodeStatusText = $r('app.string.qr_status_expired');
          this.clearQRCodeTimer();
          break;
        case 2:
          this.qrCodeStatusText = $r('app.string.qr_status_success');
          this.tokenFromQR = checkResult.cookie;
          this.clearQRCodeTimer();
          Logger.info(TAG, `QRCode login success`);
          break;
      }
    } catch (error) {
      Logger.error(TAG, `Check QRCode status error: ${error}`);
      this.qrCodeStatusText = $r('app.string.qr_check_status_failed');
      this.clearQRCodeTimer();
    }
  }

  clearQRCodeTimer(): void {
    this.isCheckingQRCode = false;
    if (this.qrCodeCheckTimer) {
      clearInterval(this.qrCodeCheckTimer);
      this.qrCodeCheckTimer = 0;
      Logger.info(TAG, `QRCode timer cleared`);
    }
  }

  /**
   * 刷新数据源列表
   */
  async refresh(): Promise<void> {
    if (!SourceDataSource.isInitialized()) return;

    this.isLoading = true;
    try {
      this.sources = [];
      const newSources = await SourceDataSource.getAllSources();
      this.sources = newSources;
      Logger.info(TAG, `List refreshed, count: ${this.sources.length}`);
    } catch (error) {
      Logger.error(TAG, `Refresh failed: ${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  getSourceCount(): number {
    return this.sources.length;
  }

  isEmpty(): boolean {
    return this.sources.length === 0;
  }

  destroy(): void {
    this.clearQRCodeTimer();
    Logger.info(TAG, `ViewModel destroyed`);
  }
}