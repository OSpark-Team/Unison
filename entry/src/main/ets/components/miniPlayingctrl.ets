import { HdsTabs } from "@hms.hds.hdsBaseComponent";
import { hdsMaterial } from "@kit.UIDesignKit";
import TabSettingModel, { isPlaying } from "../model/adapter/TabSetting";
import { AppStorageV2, PersistenceV2 } from "@kit.ArkUI";
import PlaylistViewModel from "../viewmodel/PlaylistViewModel";
import { cover } from "../utils/Tools";
import { PlayerCallbacks, playerManager } from "../services/PlayerManager";
import { songPlayerManager } from "../services/SongPlayerManager";

@ComponentV2
export  struct  miniPlayingCtrl{
  private TabSettingModels: TabSettingModel = PersistenceV2.connect(TabSettingModel, 'TabSettingModel', () => new TabSettingModel())!;
  @Local playlistViewModel: PlaylistViewModel = AppStorageV2.connect(
    PlaylistViewModel,
    "PlaylistViewModel",
    () => new PlaylistViewModel(),
  )!;
  @Local  IsPlaying: isPlaying = AppStorageV2.connect(
    isPlaying,
    "isPlaying",
    () => new isPlaying(),
  )!;

  private playNext(): void {
    const next = this.playlistViewModel.nextSong(true);
    if (next) this.playlistViewModel.playSong(next, true);
  }
  private togglePlayPause(): void {
    if (this.IsPlaying.isPlaying) {
      playerManager.pause();
    } else {
      songPlayerManager.playCurrentSongOrResume();
    }
  }

  @Builder
  miniPlay(){
    Row(){
      if (this.playlistViewModel.currentSong) {
        Image(
          this.playlistViewModel.currentSong?.album?.cover
            ? cover(this.playlistViewModel.currentSong?.album?.cover, 128)
            : $r("sys.media.ohos_app_icon"),
        ).margin({left:8,right:8}).width(32)
          .borderRadius(4)
      }else {
        Image($r('app.media.startIcon')).width(32)
          .borderRadius(4).margin({left:8,right:8})
      }


      Text(this.playlistViewModel.currentSong?.name ?this.playlistViewModel.currentSong?.name:$r("app.string.not_playing"))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({overflow:TextOverflow.MARQUEE})
      SymbolGlyph(this.IsPlaying.isPlaying ? $r("sys.symbol.pause_fill") : $r("sys.symbol.play_fill")).fontColor([$r('sys.color.font')])
        .width(32)
        .onClick(()=>{
          this.togglePlayPause()
      })
      SymbolGlyph($r('sys.symbol.forward_end_fill')).fontColor([$r('sys.color.font')])
        .width(32)
        .onClick(()=>{
          this.playNext()
        })

    }.width('100%')
  }
  build() {
    HdsTabs(){
      TabContent() {
      }
      .tabBar(this.miniPlay())
    }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barHeight(48)
      // 设置页签栏悬浮样式。
      .barFloatingStyle({
        barWidth: { smallWidth: 300, mediumWidth: 400, largeWidth: 500 },
        systemMaterialEffect: {
          materialType: this.TabSettingModels.TabMaterial,
          materialLevel: this.TabSettingModels.TabMaterialLevel
        },
        barBottomMargin:6,
        gradientMask: { maskColor: '#00000000', maskHeight: 20 },
        // 设置迷你栏，若不设置，则仅有页签栏。
        // miniBar: {
        //   miniBarBuilder: () => this.miniBarBuilder()
        // }
      })

  }
}