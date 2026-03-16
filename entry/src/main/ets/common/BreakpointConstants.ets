/**
 * 断点常量。
 */
export class BreakpointConstants {
  /**
   * 表示小型设备类型的断点。
   */
  static readonly BREAKPOINT_SM: string = 'sm';

  /**
   * 表示中型设备类型的断点。
   */
  static readonly BREAKPOINT_MD: string = 'md';

  /**
   * 表示大型设备类型的断点。
   */
  static readonly BREAKPOINT_LG: string = 'lg';

  /**
   * 当前用于查询设备类型的断点。
   */
  static readonly CURRENT_BREAKPOINT: string = 'currentBreakpoint';

  /**
   * 小型设备宽度的范围。
   */
  static readonly RANGE_SM: string = '(320vp<=width<600vp)';

  /**
   * 中型设备宽度的范围。
   */
  static readonly RANGE_MD: string = '(600vp<=width<840vp)';

  /**
   * 大型设备宽度的范围。
   */
  static readonly RANGE_LG: string = '(840vp<=width)';
}