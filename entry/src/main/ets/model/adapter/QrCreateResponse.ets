/**
 * 二维码创建响应模型
 * 用于扫码登录功能
 */
@ObservedV2
export class QrCreateResponse {
  /**
   * 二维码内容URL
   * 用于生成二维码图片的原始URL
   */
  @Trace qrurl: string = '';

  /**
   * 二维码图片（Base64编码）
   * 可直接用于显示的Base64编码图片数据
   */
  @Trace qrimg: string = '';
}

