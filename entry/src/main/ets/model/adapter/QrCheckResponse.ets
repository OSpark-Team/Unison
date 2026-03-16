/**
 * 二维码检查响应模型
 * 用于轮询检查二维码扫描状态
 */
@ObservedV2
export class QrCheckResponse {
  /**
   * 状态码
   * - -1: 二维码已过期
   * - 0: 等待扫码
   * - 1: 已扫码，等待确认
   * - 2: 授权登录成功
   */
  @Trace status: number = 0;

  /**
   * Cookie信息
   * 登录成功后返回的Cookie字符串
   */
  @Trace cookie: string = '';
}

