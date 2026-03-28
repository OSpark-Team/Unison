import { hdsMaterial, HdsTabsAttribute } from "@kit.UIDesignKit";
import { deviceInfo } from "@kit.BasicServicesKit";
import { PersistenceV2 } from "@kit.ArkUI";
import TabSettingModel from "../model/adapter/TabSetting";

 @ObservedV2
export class hdsTabModifier implements AttributeModifier<HdsTabsAttribute> {
  private TabSettingModels: TabSettingModel = PersistenceV2.connect(TabSettingModel, 'TabSettingModel', () => new TabSettingModel())!;

  applyNormalAttribute(instance: HdsTabsAttribute){

    if (deviceInfo.distributionOSApiVersion >= 60100) {

      if (this.TabSettingModels.barFloatingStyle){
        instance.barOverlap(true)
        instance.vertical(false)
        instance.barFloatingStyle({
          barWidth: { smallWidth: 300, mediumWidth: 400, largeWidth: 500 },
          barBottomMargin: 28,
          // gradientMask: { maskColor: '#66F1F3F5', maskHeight: 0 },
          gradientMask: { maskColor: '#00000000', maskHeight: 20 },

          systemMaterialEffect: {
            materialType: this.TabSettingModels.TabMaterial,
            materialLevel: this.TabSettingModels.TabMaterialLevel
          }
          // 设置迷你栏，若不设置，则仅有页签栏。

        })
      }else {
        instance.barOverlap(false)
      }





    }
  }
}