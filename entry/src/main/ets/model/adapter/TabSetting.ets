/**
 * tab栏设置
 */
@ObservedV2
export default class TabSettingModel {

  // Tab栏背景样式开关，true表示启用自定义背景样式，false表示使用默认样式
  @Trace barBackgroundStyle: boolean = false;

  // Tab栏浮动样式开关，true表示启用浮动效果，false表示使用常规样式
  @Trace barFloatingStyle: boolean = false;

  // Tab栏材质类型，用于定义Tab栏的视觉材质效果（如磨砂、透明等）
  @Trace TabMaterial: number = 100;

  // Tab栏材质层级，用于控制材质效果的强度或深度
  @Trace TabMaterialLevel: number = 10;

  // Tab栏背景颜色，支持资源字符串类型（如颜色资源引用或十六进制颜色值）
  @Trace useBackgroundColor: boolean = false

  @Trace backgroundColor: ResourceStr = '#cc123456'
  // Tab栏背景颜色，支持资源字符串类型（如颜色资源引用或十六进制颜色值）
}

@ObservedV2
export  class isPlaying {
  @Trace isPlaying:boolean =false
}