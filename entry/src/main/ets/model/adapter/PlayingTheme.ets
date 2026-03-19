@ObservedV2
export class PlayTheme {

}

@ObservedV2
export class PlayThemeLandscape {
    @Trace theme:number = 0;
    @Trace backgroundStyle:number =0;
}

@ObservedV2
export class PlayTheme4Time {
  @Trace FontFamily:number = 0;
  @Trace FontSize:number =100;
  @Trace FontColor:ResourceStr = $r('sys.color.font');
}