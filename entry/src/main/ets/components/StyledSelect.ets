import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';

@ComponentV2
export struct StyledSelect {
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  @Param options: Array<SelectOption> = [];
  @Param selectedIndex: number = 0;
  @Param valueText: ResourceStr = '';
  @Param disabled: boolean = false;
  @Param onSelect: (index: number, value: string) => void = () => {};

  build() {
    Select(this.options)
      .selected(this.selectedIndex)
      .value(this.valueText)
      .font({ size: 16, weight: FontWeight.Normal })
      .fontColor($r('app.color.text_primary'))
      .selectedOptionBgColor($r('app.color.primary_color'))
      .selectedOptionFontColor($r('app.color.label_text_color'))
      .optionBgColor($r('app.color.background_card'))
      .optionFontColor($r('app.color.text_primary'))
      .divider({ strokeWidth: '1px', color: $r('app.color.divider') })
      .borderRadius(this.settingModel.radiusItem)
      .enabled(!this.disabled)
      .onSelect((index: number, value: string) => {
        this.onSelect(index, value);
      });
  }
}
