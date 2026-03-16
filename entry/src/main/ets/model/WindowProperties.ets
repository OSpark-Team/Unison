/**
 * 窗口属性类
 * 用于存储和管理应用窗口的各种属性信息
 * 包括窗口尺寸、安全区避让、响应式断点等
 * 使用 @ObservedV2 装饰器实现状态观察，属性变化时自动通知UI更新
 */
@ObservedV2
export class WindowProperties {
  /**
   * 当前响应式断点
   * - sm: 小屏设备 (320vp <= width < 600vp)，通常为手机竖屏
   * - md: 中屏设备 (600vp <= width < 840vp)，通常为手机横屏或小平板
   * - lg: 大屏设备 (840vp <= width)，通常为平板或折叠屏
   * 默认值为 'sm'
   */
  @Trace currentBreakpoint: string = 'sm';

  /**
   * 窗口宽度（单位：vp）
   * 表示应用窗口的可用宽度，不包括系统装饰
   * 初始值为 0，在窗口初始化后会被更新
   */
  @Trace winWidth: number = 0;

  /**
   * 窗口高度（单位：vp）
   * 表示应用窗口的可用高度，不包括系统装饰
   * 初始值为 0，在窗口初始化后会被更新
   */
  @Trace winHeight: number = 0;

  /**
   * 底部安全区高度（单位：vp）
   * 表示底部导航栏或手势条的避让高度
   * 用于避免内容被底部系统UI遮挡
   * 对应 AvoidAreaType.TYPE_NAVIGATION_INDICATOR
   */
  @Trace bottomRect: number = 0;

  /**
   * 顶部安全区高度（单位：vp）
   * 表示顶部状态栏的避让高度
   * 用于避免内容被顶部系统UI遮挡
   * 对应 AvoidAreaType.TYPE_SYSTEM
   */
  @Trace topRect: number = 0;

  /**
   * 窗口装饰高度（单位：vp）
   * 表示窗口标题栏等装饰元素的高度
   * 仅在支持 SystemCapability.Window.SessionManager 的设备上可用
   * 不支持的设备上保持默认值 0
   */
  @Trace decorHeight: number = 0;

  /**
   * 左侧刘海屏/挖孔屏高度（单位：vp）
   * 表示屏幕左侧异形区域的高度
   * 用于避免内容被异形屏遮挡
   * 对应 AvoidAreaType.TYPE_CUTOUT 的 leftRect.height
   */
  @Trace leftCutoutRectHeight: number = 0;

  /**
   * 左侧刘海屏/挖孔屏宽度（单位：vp）
   * 表示屏幕左侧异形区域的宽度
   * 用于避免内容被异形屏遮挡
   * 对应 AvoidAreaType.TYPE_CUTOUT 的 leftRect.width
   */
  @Trace leftCutoutRectWidth: number = 0;

  /**
   * 右侧刘海屏/挖孔屏高度（单位：vp）
   * 表示屏幕右侧异形区域的高度
   * 用于避免内容被异形屏遮挡
   * 对应 AvoidAreaType.TYPE_CUTOUT 的 rightRect.height
   */
  @Trace rightCutoutRectHeight: number = 0;

  /**
   * 右侧刘海屏/挖孔屏宽度（单位：vp）
   * 表示屏幕右侧异形区域的宽度
   * 用于避免内容被异形屏遮挡
   * 对应 AvoidAreaType.TYPE_CUTOUT 的 rightRect.width
   */
  @Trace rightCutoutRectWidth: number = 0;
}