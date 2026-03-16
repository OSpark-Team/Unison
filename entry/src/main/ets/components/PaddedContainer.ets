import { WindowProperties } from "../model/WindowProperties";
import { AppStorageV2 } from "@kit.ArkUI";

/**
 * 内边距偏移接口
 * 用于定义容器四个方向的额外偏移量
 * 所有属性都是可选的，未指定时默认为 0
 */
export interface PaddedOffset {
  /** 顶部额外偏移（单位：vp），默认为 0 */
  top?: number;
  /** 左侧额外偏移（单位：vp），默认为 0 */
  left?: number;
  /** 右侧额外偏移（单位：vp），默认为 0 */
  right?: number;
  /** 底部额外偏移（单位：vp），默认为 0 */
  bottom?: number;
}

/**
 * 安全区避让方向枚举
 * 用于控制容器在哪些方向上进行安全区避让
 */
export enum SafeAreaEdge {
  /** 不避让任何方向 */
  NONE = 0,
  /** 避让顶部（状态栏） */
  TOP = 1 << 0,
  /** 避让底部（导航栏/手势条） */
  BOTTOM = 1 << 1,
  /** 避让左侧（异形屏） */
  LEFT = 1 << 2,
  /** 避让右侧（异形屏） */
  RIGHT = 1 << 3,
  /** 避让所有方向 */
  ALL = TOP | BOTTOM | LEFT | RIGHT,
  /** 避让垂直方向（顶部+底部） */
  VERTICAL = TOP | BOTTOM,
  /** 避让水平方向（左侧+右侧） */
  HORIZONTAL = LEFT | RIGHT
}

/**
 * 安全区避让容器组件
 *
 * 功能特性：
 * - 自动根据设备安全区数据添加内边距，避免内容被系统 UI 遮挡
 * - 支持响应式断点（sm/md/lg），在不同设备上应用不同的避让策略
 * - 支持自定义额外偏移量，满足特殊布局需求
 * - 支持选择性避让方向，灵活控制哪些边需要避让
 * - 考虑异形屏（刘海屏、挖孔屏）的避让需求
 *
 * 使用场景：
 * - 页面根容器：避让状态栏和导航栏
 * - 滚动内容容器：避让顶部和底部系统 UI
 * - 侧边栏容器：避让顶部、底部和异形屏区域
 *
 * @example
 * ```typescript
 * PaddedContainer({
 *   safeAreaEdges: SafeAreaEdge.ALL,
 *   extraOffset: { top: 10, left: 0, right: 0, bottom: 10 }
 * }) {
 *   // 你的内容
 *   Column() {
 *     Text("内容")
 *   }
 * }
 * ```
 */
@ComponentV2
export struct PaddedContainer {
  /**
   * 窗口属性全局实例
   * 包含安全区数据、窗口尺寸、响应式断点等信息
   */
  @Local windowProperties: WindowProperties = AppStorageV2.connect(
    WindowProperties,
    "WindowProperties",
    () => new WindowProperties()
  )!;

  /**
   * 默认插槽构建器
   * 当没有传入 content 时使用
   */
  @Builder
  slotBuilder() {
  }

  /**
   * 内容插槽
   * 用于传入需要被安全区避让包裹的内容
   */
  @BuilderParam content: () => void = this.slotBuilder;

  /**
   * 额外偏移量
   * 在安全区避让的基础上，额外添加的内边距
   * 所有属性都是可选的，未指定时默认为 0
   * 默认值：空对象（所有方向都为 0）
   */
  @Param extraOffset: PaddedOffset = {};

  /**
   * 安全区避让方向
   * 控制容器在哪些方向上进行安全区避让
   * 默认值：避让所有方向（顶部、底部、左侧、右侧）
   */
  @Param safeAreaEdges: SafeAreaEdge = SafeAreaEdge.ALL;

  /**
   * 顶部内边距计算属性
   * 根据安全区避让方向和额外偏移量自动计算顶部内边距
   * 使用 @Computed 装饰器实现自动依赖追踪和结果缓存
   * @returns 顶部内边距（单位：vp）
   */
  @Computed
  get topPadding(): number {
    // 检查是否需要避让顶部
    const shouldAvoidTop = (this.safeAreaEdges & SafeAreaEdge.TOP) !== 0;
    // 基础安全区高度 + 额外偏移（使用 ?? 0 处理可选值）
    return (shouldAvoidTop ? this.windowProperties.topRect : 0) + (this.extraOffset.top ?? 0);
  }

  /**
   * 底部内边距计算属性
   * 根据安全区避让方向和额外偏移量自动计算底部内边距
   * 使用 @Computed 装饰器实现自动依赖追踪和结果缓存
   * @returns 底部内边距（单位：vp）
   */
  @Computed
  get bottomPadding(): number {
    // 检查是否需要避让底部
    const shouldAvoidBottom = (this.safeAreaEdges & SafeAreaEdge.BOTTOM) !== 0;
    // 基础安全区高度 + 额外偏移（使用 ?? 0 处理可选值）
    return (shouldAvoidBottom ? this.windowProperties.bottomRect : 0) + (this.extraOffset.bottom ?? 0);
  }

  /**
   * 左侧内边距计算属性
   * 根据安全区避让方向、异形屏数据和额外偏移量自动计算左侧内边距
   * 使用 @Computed 装饰器实现自动依赖追踪和结果缓存
   * @returns 左侧内边距（单位：vp）
   */
  @Computed
  get leftPadding(): number {
    // 检查是否需要避让左侧
    const shouldAvoidLeft = (this.safeAreaEdges & SafeAreaEdge.LEFT) !== 0;
    // 左侧异形屏宽度（如果有）+ 额外偏移（使用 ?? 0 处理可选值）
    return (shouldAvoidLeft ? this.windowProperties.leftCutoutRectWidth : 0) + (this.extraOffset.left ?? 0);
  }

  /**
   * 右侧内边距计算属性
   * 根据安全区避让方向、异形屏数据和额外偏移量自动计算右侧内边距
   * 使用 @Computed 装饰器实现自动依赖追踪和结果缓存
   * @returns 右侧内边距（单位：vp）
   */
  @Computed
  get rightPadding(): number {
    // 检查是否需要避让右侧
    const shouldAvoidRight = (this.safeAreaEdges & SafeAreaEdge.RIGHT) !== 0;
    // 右侧异形屏宽度（如果有）+ 额外偏移（使用 ?? 0 处理可选值）
    return (shouldAvoidRight ? this.windowProperties.rightCutoutRectWidth : 0) + (this.extraOffset.right ?? 0);
  }

  build() {
    Column() {
      Blank().height(this.topPadding)
      this.content()
      Blank().height(this.bottomPadding)
    }
    .width('100%')
    .height('100%')
    // 应用计算后的安全区避让内边距
    // 使用 @Computed 计算属性，自动响应依赖项变化
    .padding({
      // top: this.topPadding,
      // bottom: this.bottomPadding,
      left: this.leftPadding,
      right: this.rightPadding
    })
  }
}