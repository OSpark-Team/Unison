import { StyledSelect } from "./StyledSelect";
import TabSettingModel from "../model/adapter/TabSetting";
import { PersistenceV2 } from "@kit.ArkUI";
import { SettingItem } from "./SettingItem";
import { deviceInfo } from "@kit.BasicServicesKit";

@ComponentV2
export default struct hdsTabSettingCom{
  @Local TypeSelectOptions:SelectOption[] =[{value:'无材质'},{value:'自适应模式'},{value:'沉浸式材质'}]
  @Local LevelSelectOptions:SelectOption[] =[{value:'精美'},{value:'轻柔'},{value:'流畅'},{value:'自适应模式'}]
  @Local TabSettingModel: TabSettingModel = PersistenceV2.connect(TabSettingModel, 'TabSettingModel', () => new TabSettingModel())!;

  // aboutToAppear(): void {
  // }
  private getTypeIndex(bitrate:number): number {
    if (bitrate === 0) return 0;
    if (bitrate === 100) return 1;
    if (bitrate === 101) return 2;
    return 0;
  }
  private getTypeValueByIndex(index: number): number {
    if (index === 0) return 0;
    if (index === 1) return 100;
    if (index === 2) return 101;
    return 0;
  }
  private getTypeLabel(bitrate:number): ResourceStr {
    if (bitrate === 0) {
      return '无材质';
    }
    if (bitrate === 100) {
      return '自适应模式';
    }
    if (bitrate === 101) {
      return '沉浸式材质';
    }

    return String(bitrate);
  }
  @Builder
  private TypeSelectRow() {
    Row({ space: 12 }) {
      Text('材质类型')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1) // 占用左侧空间

      StyledSelect({
        options: this.TypeSelectOptions,
        selectedIndex: this.getTypeIndex(this.TabSettingModel.TabMaterial),
        valueText: this.getTypeLabel(this.TabSettingModel.TabMaterial),
        disabled: false,
        onSelect: (index: number, _value: string) => {
          this.TabSettingModel.TabMaterial = this.getTypeValueByIndex(index)
        },
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
  private getLevelIndex(bitrate:number): number {
    if (bitrate === 0) return 0;
    if (bitrate === 1) return 1;
    if (bitrate === 2) return 2;
    if (bitrate === 10) return 3;
    return 0;
  }
  private getLevelValueByIndex(index: number): number {
    if (index === 0) return 0;
    if (index === 1) return 1;
    if (index === 2) return 2;
    if (index === 3) return 10;
    return 0;
  }
  private getLevelLabel(bitrate:number): ResourceStr {
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
    return String(bitrate);
  }
  @Builder
  private LevelSelectRow() {
    Row({ space: 12 }) {
      Text('材质等级')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1) // 占用左侧空间

      StyledSelect({
        options: this.LevelSelectOptions,
        selectedIndex: this.getLevelIndex(this.TabSettingModel.TabMaterialLevel),
        valueText: this.getLevelLabel(this.TabSettingModel.TabMaterialLevel),
        disabled: false,
        onSelect: (index: number, _value: string) => {
          this.TabSettingModel.TabMaterialLevel = this.getLevelValueByIndex(index)
        },
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
  build() {
    if (deviceInfo.sdkApiVersion>22){
      Column(){
        SettingItem({
          type: 'switch',
          icon: undefined,
          title: '悬浮状态栏',
          description: undefined,
          value: this.TabSettingModel.barFloatingStyle,
          onChange: (value: boolean) => {
            this.getUIContext().animateTo({
              duration: 200,
              curve: Curve.Linear
            },()=>{
              this.TabSettingModel.barFloatingStyle = value;
            })
          },
          isLast: true,
        })
        if (this.TabSettingModel.barFloatingStyle){
          this.TypeSelectRow()
          Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
          this.LevelSelectRow()
        }

      } .width('100%')
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(16)
    }



  }
}