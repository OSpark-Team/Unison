/**
 * Tab栏设置组件
 * 用于配置Tab栏的显示样式，包括悬浮效果、材质类型和材质等级
 * 设置数据通过PersistenceV2持久化存储
 */
import { StyledSelect } from "./StyledSelect";
import TabSettingModel from "../model/adapter/TabSetting";
import { PersistenceV2 } from "@kit.ArkUI";
import { SettingItem } from "./SettingItem";
import { deviceInfo } from "@kit.BasicServicesKit";

/**
 * Tab栏设置组件
 * 提供悬浮状态栏开关、材质类型选择、材质等级选择等功能
 * 仅在API版本大于22时显示完整功能
 */
@ComponentV2
export default struct TabSettingCom {
  // 材质类型选择选项列表：无材质、自适应模式、沉浸式材质
  @Local TypeSelectOptions: SelectOption[] = [
    { value: '无材质' },
    { value: '自适应模式' },
    { value: '沉浸式材质' }
  ]

  // 材质等级选择选项列表：精美、轻柔、流畅、自适应模式
  @Local LevelSelectOptions: SelectOption[] = [
    { value: '精美' },
    { value: '轻柔' },
    { value: '流畅' },
    { value: '自适应模式' }
  ]

  // Tab设置数据模型，通过PersistenceV2实现数据持久化存储
  @Local TabSettingModel: TabSettingModel = PersistenceV2.connect(TabSettingModel, 'TabSettingModel', () => new TabSettingModel())!;

  // aboutToAppear(): void {
  // }

  /**
   * 根据材质值获取对应的选项索引
   * @param bitrate 材质值（0:无材质, 100:自适应模式, 101:沉浸式材质）
   * @returns 对应的选项索引
   */
  private getTypeIndex(bitrate: number): number {
    if (bitrate === 0) return 0;   // 无材质
    if (bitrate === 100) return 1; // 自适应模式
    if (bitrate === 101) return 2; // 沉浸式材质
    return 0; // 默认返回无材质
  }

  /**
   * 根据选项索引获取对应的材质值
   * @param index 选项索引
   * @returns 对应的材质值
   */
  private getTypeValueByIndex(index: number): number {
    if (index === 0) return 0;   // 无材质
    if (index === 1) return 100; // 自适应模式
    if (index === 2) return 101; // 沉浸式材质
    return 0; // 默认返回无材质
  }

  /**
   * 根据材质值获取显示标签文本
   * @param bitrate 材质值
   * @returns 对应的显示标签
   */
  private getTypeLabel(bitrate: number): ResourceStr {
    if (bitrate === 0) {
      return '无材质';
    }
    if (bitrate === 100) {
      return '自适应模式';
    }
    if (bitrate === 101) {
      return '沉浸式材质';
    }
    // 非标准值时直接显示数值
    return String(bitrate);
  }

  /**
   * 材质类型选择行构建器
   * 包含"材质类型"标签和下拉选择器
   */
  @Builder
  private TypeSelectRow() {
    Row({ space: 12 }) {
      // 左侧标签文本
      Text('材质类型')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1) // 占用左侧空间

      // 右侧下拉选择器
      StyledSelect({
        options: this.TypeSelectOptions,
        selectedIndex: this.getTypeIndex(this.TabSettingModel.TabMaterial),
        valueText: this.getTypeLabel(this.TabSettingModel.TabMaterial),
        disabled: false,
        onSelect: (index: number, _value: string) => {
          // 选择后更新材质类型值
          this.TabSettingModel.TabMaterial = this.getTypeValueByIndex(index)
        },
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /**
   * 根据等级值获取对应的选项索引
   * @param bitrate 等级值（0:精美, 1:轻柔, 2:流畅, 10:自适应模式）
   * @returns 对应的选项索引
   */
  private getLevelIndex(bitrate: number): number {
    if (bitrate === 0) return 0;  // 精美
    if (bitrate === 1) return 1;  // 轻柔
    if (bitrate === 2) return 2;  // 流畅
    if (bitrate === 10) return 3; // 自适应模式
    return 0; // 默认返回精美
  }

  /**
   * 根据选项索引获取对应的等级值
   * @param index 选项索引
   * @returns 对应的等级值
   */
  private getLevelValueByIndex(index: number): number {
    if (index === 0) return 0;  // 精美
    if (index === 1) return 1;  // 轻柔
    if (index === 2) return 2;  // 流畅
    if (index === 3) return 10; // 自适应模式
    return 0; // 默认返回精美
  }

  /**
   * 根据等级值获取显示标签文本
   * @param bitrate 等级值
   * @returns 对应的显示标签
   */
  private getLevelLabel(bitrate: number): ResourceStr {
    if (bitrate === 0) {
      return '精美';
    }
    if (bitrate === 1) {
      return '轻柔';
    }
    if (bitrate === 2) {
      return '流畅';
    }
    if (bitrate === 10) {
      return '自适应模式';
    }
    // 非标准值时直接显示数值
    return String(bitrate);
  }

  /**
   * 材质等级选择行构建器
   * 包含"材质等级"标签和下拉选择器
   */
  @Builder
  private LevelSelectRow() {
    Row({ space: 12 }) {
      // 左侧标签文本
      Text('材质等级')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1) // 占用左侧空间

      // 右侧下拉选择器
      StyledSelect({
        options: this.LevelSelectOptions,
        selectedIndex: this.getLevelIndex(this.TabSettingModel.TabMaterialLevel),
        valueText: this.getLevelLabel(this.TabSettingModel.TabMaterialLevel),
        disabled: false,
        onSelect: (index: number, _value: string) => {
          // 选择后更新材质等级值
          this.TabSettingModel.TabMaterialLevel = this.getLevelValueByIndex(index)
        },
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /**
   * 构建组件UI
   * 仅在API版本大于22时显示设置项
   */
  build() {
    // API版本检查，确保功能兼容性
    if (deviceInfo.sdkApiVersion > 22) {
      Column() {
        // 悬浮状态栏开关设置项
        SettingItem({
          type: 'switch',
          icon: undefined,
          title: '悬浮状态栏',
          description: undefined,
          value: this.TabSettingModel.barFloatingStyle,
          onChange: (value: boolean) => {
            // 使用动画过渡效果更新状态
            this.getUIContext().animateTo({
              duration: 200,
              curve: Curve.Linear
            }, () => {
              this.TabSettingModel.barFloatingStyle = value;
            })
          },
          isLast:!this.TabSettingModel.barFloatingStyle,
        })

        // 当启用悬浮状态栏时，显示材质相关设置
        if (this.TabSettingModel.barFloatingStyle) {
          this.TypeSelectRow() // 材质类型选择
          Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
          this.LevelSelectRow() // 材质等级选择
          Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
          SettingItem({
            type: 'switch',
            icon: undefined,
            title: '选中背景色',
            description: undefined,
            value: this.TabSettingModel.useBackgroundColor,
            onChange: (value: boolean) => {
              // 使用动画过渡效果更新状态
              this.getUIContext().animateTo({
                duration: 200,
                curve: Curve.Linear
              }, () => {
                this.TabSettingModel.useBackgroundColor = value;
                if (value) {
                  if (this.TabSettingModel.backgroundColor ==''||this.TabSettingModel.backgroundColor == undefined||this.TabSettingModel.backgroundColor == null) {
                    this.TabSettingModel.backgroundColor ='#cc123456'
                  }
                }

              })
            },
            isLast:true,
          })
        }
      }
      .width('100%')
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(16)
    }
  }
}