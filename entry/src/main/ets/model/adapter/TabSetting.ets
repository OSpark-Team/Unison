

/**
 * tab栏设置
 */
@ObservedV2
export default   class TabSettingModel{

  @Trace barBackgroundStyle:boolean = false;
  @Trace barFloatingStyle:boolean = false;
  @Trace TabMaterial:number = 100;
  @Trace TabMaterialLevel:number = 10;
  @Trace backgroundColor:ResourceStr = ''
}