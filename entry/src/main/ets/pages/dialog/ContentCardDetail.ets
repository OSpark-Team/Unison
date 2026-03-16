import CurrentSourceViewModel from '../../viewmodel/CurrentSourceViewModel';
import { AppStorageV2, curves } from '@kit.ArkUI';
import { SongListItem } from '../../components/SongListItem';
import { cover } from '../../utils/Tools';
import { Song } from '../../model/adapter/Song';
import { Playlist } from '../../model/adapter/Playlist';
import { PlaylistListItem } from '../../components/PlaylistListItem';
import { Artist } from '../../model/adapter/Artist';
import { ArtistListItem } from '../../components/ArtistListItem';
import { WindowProperties } from '../../model/WindowProperties';
import { HdsNavDestination, HdsNavDestinationAttribute } from '@kit.UIDesignKit';
import { PlaylistDetailParam } from '../PlaylistDetail';
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../../viewmodel/SettingViewModel';
import { BreakpointConstants } from '../../common/BreakpointConstants';

/**
 * 内容卡片详情页 Builder
 */
@Builder
export function ContentCardDetailBuilder() {
  ContentCardDetail()
}

/**
 * 路由参数接口
 */
export interface ContentCardDetailParam {
  /** 弹窗标题 */
  title: ResourceStr;
  /** 弹窗副标题（可选） */
  subtitle?: ResourceStr;
  /** 内容类型："HotSongAll" | "RecommendPlaylistAll" | "RecommendArtistAll" | "RankAll" */
  type: string;
}

/**
 * 内容卡片详情页组件
 * 使用 NavDestination + NavDestinationMode.DIALOG 模式实现全局弹窗
 * 支持共享元素转场动画（geometryTransition）
 */
@ComponentV2
struct ContentCardDetail {
  /**
   * 路由导航
   */
  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  /**
   * 当前数据源 ViewModel
   */
  @Local currentSourceViewModel: CurrentSourceViewModel =
    AppStorageV2.connect(CurrentSourceViewModel, "CurrentSourceViewModel", () => new CurrentSourceViewModel())!;
  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;

  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  /**
   * 路由参数
   */
  @Local param: ContentCardDetailParam = {
    title: "",
    type: ""
  };

  @Builder
  SongItem(song: Song) {
    SongListItem({
      coverImage: cover(song.album?.cover, 100),
      songName: `${song.name}`,
      artistName: song.artists?.map(artist => artist.name).join("/"),
      duration: song.duration
    })
  }

  @Builder
  PlaylistItem(playlist: Playlist) {
    PlaylistListItem({
      coverImage: cover(playlist.cover, 100),
      playlistName: playlist.name,
      trackCount: playlist.size,
      onItemClick: () => {
        this.pageInfos.pushPathByName("PlaylistDetail", {
          playlistId: playlist.id,
          sourceId: playlist.sourceId,
          playlist: playlist
        } as PlaylistDetailParam, true);
      }
    })
  }

  @Builder
  ArtistItem(artist: Artist) {
    ArtistListItem({
      coverImage: cover(artist.avatar, 100),
      artistName: artist.name,
      onItemClick: ()=>{
        this.pageInfos.pushPathByName("PlaylistDetail", {
          playlistId: artist.id,
          sourceId: artist.sourceId,
          playlist: Playlist.Type("artist")
        } as PlaylistDetailParam, true);
      }
    })
  }

  /**
   * 标题栏 Builder
   */
  @Builder
  buildHeader() {
    Row({ space: 12 }) {
      // 标题和副标题
      Column({ space: 4 }) {
        Text(this.param.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.param.subtitle) {
          Text(this.param.subtitle)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 关闭按钮
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.background_secondary'))
      .onClick(() => {
        this.handleClose();
      })
    }
    .width('100%')
    // 标题区域保留左右内边距，避免贴边观感差
    .padding({ left: 20, right: 20, top: 16, bottom: 0 })
    .backgroundColor($r('app.color.background_card'))
  }

  /**
   * 内容区域 Builder
   * 根据 type 参数渲染不同的列表内容
   */
  @Builder
  buildContent() {
    List() {
      if (this.param.type === "HotSongAll") {
        Repeat<Song>(this.currentSourceViewModel.newSongs)
          .each((song) => {
            ListItem() {
              this.SongItem(song.item)
            }
          })
      } else if(this.param.type === "RecommendPlaylistAll"){
        Repeat<Playlist>(this.currentSourceViewModel.recommendPlaylists)
          .each((playlist) => {
            ListItem() {
              this.PlaylistItem(playlist.item)
            }
          })
      } else if(this.param.type === "RecommendArtistAll"){
        Repeat<Artist>(this.currentSourceViewModel.recommendArtists.slice(1))
          .each((artist) => {
            ListItem() {
              this.ArtistItem(artist.item)
            }
          })
      } else if(this.param.type === "RankAll"){
        Repeat<Playlist>(this.currentSourceViewModel.rankPlaylists.slice(1))
          .each((playlist) => {
            ListItem() {
              this.PlaylistItem(playlist.item)
            }
          })
      }
    }
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .width("100%")
    .height("100%")
  }

  /**
   * 关闭弹窗处理函数
   */
  handleClose() {
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 328, 37)
    }, () => {
      this.pageInfos.pop(false);
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 0 }) {
          this.buildHeader()

        Column() {
          this.buildContent()
        }
        .layoutWeight(1)
        .width('100%')
        // SM 全屏沉浸：不要缩小内容区，避免“看起来不沉浸”
        .padding(this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 0 : 16)
        .backgroundColor($r('app.color.background_card'))
        }
        .width(this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? "100%" : "50%")
        .height(this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? "100%" : "70%")
        .borderRadius(this.settingModel.radiusCardLarge)
        .clip(true)
        .transition(TransitionEffect.OPACITY)
        .id('content-card-detail')
        .geometryTransition(this.param.type, { follow:true} )
        .backgroundColor($r('app.color.background_card'))
        .onClick(() => {})
        .padding({
          top: this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? this.windowProperties.topRect : 0
        })
      }
      // .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
      .width('100%')
      .height('100%')
      .onClick(()=>{
        this.handleClose()
      })
    }
    .onReady((context: NavDestinationContext) => {
      this.param = (context.pathInfo.param as ContentCardDetailParam);
    })
    .onBackPressed(() => {
      this.handleClose();
      return true;
    })
    .hideTitleBar(true)
    .ignoreLayoutSafeArea()
    .mode(NavDestinationMode.DIALOG)
    .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Sharp }))
  }
}
