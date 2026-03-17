import { WindowProperties } from '../model/WindowProperties';
import { AppStorageV2, curves, PersistenceV2 } from '@kit.ArkUI';
import { MediaCard } from '../components/MediaCard';
import { BreakpointConstants } from '../common/BreakpointConstants';
import { SongListItem } from '../components/SongListItem';
import { ModuleCard } from '../components/ModuleCard';
import { ContentCard } from '../components/ContentCard';
import CurrentSourceViewModel from '../viewmodel/CurrentSourceViewModel';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { Playlist } from '../model/adapter/Playlist';
import { Song } from '../model/adapter/Song';
import { cover } from '../utils/Tools';
import { PlaylistListItem } from '../components/PlaylistListItem';
import { Artist } from '../model/adapter/Artist';
import { ArtistListItem } from '../components/ArtistListItem';
import Logger from '../utils/Logger';
import { ContentCardDetailParam } from '../pages/dialog/ContentCardDetail';
import { PlaylistDetailParam } from '../pages/PlaylistDetail';
import { emitter } from '@kit.BasicServicesKit';
import { EmitEventConstants } from '../common/EmitEventConstants';
import PlaylistViewModel from '../viewmodel/PlaylistViewModel';


@ComponentV2
export struct HomeView {
  @Require @Param scroller: Scroller ;
  /**
   * 路由导航
   */
  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;
  /**
   * 当前数据源
   */
  @Local currentSourceViewModel: CurrentSourceViewModel =
    AppStorageV2.connect(CurrentSourceViewModel, "CurrentSourceViewModel", () => new CurrentSourceViewModel())!;
  /**
   * 数据源列表 ViewModel
   */
  @Local viewModel: SourceListViewModel =
    AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!;
  /**
   * 系统设置 ViewModel
   */
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  /**
   * 当前播放列表
   */
  @Local playlistViewModel: PlaylistViewModel =
    AppStorageV2.connect(PlaylistViewModel, 'PlaylistViewModel', () => new PlaylistViewModel())!;

  /**
   * ForU 颜色枚举值
   */
  private ForUColors = ["#E6593BFF", "#E6FF7A5A", "#E624CCA3", "#E6A85EFF"];

  /**
   * 选择数据源
   */
  selectSource() {
    this.currentSourceViewModel.source =
      this.viewModel.sources.find(source => source.id === this.settingModel.mainSource) ?? this.viewModel.sources[0];
  }

  /**
   * 当前选择
   */
  @Monitor("viewModel.sources","viewModel.sources.length")
  sourceChanged() {
    Logger.info("HomeView", "Source Changed")
    const tempId = this.currentSourceViewModel.source?.id;
    // 如果这个ID的数据源还在列表中，则不改变
    if (this.viewModel.sources.find(source => source.id === tempId)) {
      return;
    }
    // 如果本身不存在和tempId已经被删除了，则选择第一个
    this.selectSource()
  }

  /**
   * 初始化Emit监听
   */
  initEmitListener() {
    // 监听数据源URL、Token更新
    emitter.on({
      eventId: EmitEventConstants.SOURCE_URL_TOKEN_UPDATED,
    }, (eventData: emitter.EventData)=>{
      const data = eventData.data!;
      if (data.id === this.currentSourceViewModel.source?.id) {
        this.currentSourceViewModel.loadAll();
      }
    })
  }

  aboutToAppear(): void {
    this.selectSource();
    this.initEmitListener();
  }

  @Builder
  SongItem(song: Song) {
    SongListItem({
      coverImage: cover(song.album?.cover, 100),
      songName: `${song.name}`,
      artistName: song.artists?.map(artist => artist.name).join("/"),
      duration: song.duration,
      onItemClick: ()=>{
        this.playlistViewModel.insertSongs([song]);
        this.playlistViewModel.playSong(song, true);
      }
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

  @Builder
  ForU() {
    if (this.currentSourceViewModel.forUItems && this.currentSourceViewModel.forUItems.length) {
      Grid() {
        Repeat<Playlist>(this.currentSourceViewModel.forUItems)
          .each((playlist) => {
            GridItem() {
              ModuleCard({
                moduleName: playlist.item.name,
                moduleColor: this.ForUColors[playlist.index]
              })
            }.onClick(()=>{
                this.pageInfos.pushPathByName("PlaylistDetail", {
                  playlistId: playlist.item.id,
                  sourceId: playlist.item.sourceId,
                  playlist: playlist.item
                } as PlaylistDetailParam, true);
            })
          })
      }
      .height(this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 400 : 240)
      .rowsTemplate("1fr 1fr")
      .columnsTemplate("1fr 1fr")
      .columnsGap(16)
      .rowsGap(16)
    }
  }

  @Builder
  UserPlaylistFirst() {
    if (this.currentSourceViewModel.firstSongOfUserPlaylist) {
      MediaCard({
        backgroundImg: cover(this.currentSourceViewModel.firstUserPlaylist?.cover, 200),
        title: this.currentSourceViewModel.firstUserPlaylist?.name,
        heightValue: this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 240 : 400,
        actionContent: () => {
          this.SongItem(this.currentSourceViewModel.firstSongOfUserPlaylist!)
        },
        onCardClick: ()=>{
          this.pageInfos.pushPathByName("PlaylistDetail", {
            playlistId: this.currentSourceViewModel.firstUserPlaylist!.id,
            sourceId: this.currentSourceViewModel.firstUserPlaylist!.sourceId,
            playlist: this.currentSourceViewModel.firstUserPlaylist
          } as PlaylistDetailParam, true);
        }
      })
    }
  }

  @Builder
  HotSongAll() {
    if (this.currentSourceViewModel.newSongs && this.currentSourceViewModel.newSongs.length) {
      Column() {
        ContentCard({ title: $r("app.string.menu_new_songs"), heightValue: 400 }) {
          List() {
            Repeat<Song>(this.currentSourceViewModel.newSongs.slice(0, 5))
              .each((song) => {
                ListItem() {
                  this.SongItem(song.item)
                }
              })
          }
          .width("100%")
          .height("100%")
        }
      }
      .id("HotSongAll")
      .transition(TransitionEffect.OPACITY)
      .geometryTransition("HotSongAll", { follow: true })
      .onClick(() => {
        this.getUIContext().animateTo({
          curve: curves.interpolatingSpring(0, 1, 328, 37)
        }, () => {
          this.pageInfos.pushPathByName("ContentCardDetail", {
            title: $r("app.string.menu_new_songs"),
            type: "HotSongAll"
          } as ContentCardDetailParam, false);
        });
      })
    }
  }

  @Builder
  RecommendPlaylistAll() {
    if (this.currentSourceViewModel.recommendPlaylists && this.currentSourceViewModel.recommendPlaylists.length) {
      Column() {
        ContentCard({ title: $r("app.string.menu_recommended_playlists"), heightValue: 400 }) {
          List() {
            Repeat<Playlist>(this.currentSourceViewModel.recommendPlaylists.slice(0, 5))
              .each((playlist) => {
                ListItem() {
                  this.PlaylistItem(playlist.item)
                }
              })
          }
          .width("100%")
          .height("100%")
        }
      }
      .id("RecommendPlaylistAll")
      .transition(TransitionEffect.OPACITY)
      .geometryTransition("RecommendPlaylistAll",{ follow: true })
      .onClick(() => {
        this.getUIContext().animateTo({
          curve: curves.interpolatingSpring(0, 1, 328, 37)
        }, () => {
          this.pageInfos.pushPathByName("ContentCardDetail", {
            title: $r("app.string.menu_recommended_playlists"),
            type: "RecommendPlaylistAll"
          } as ContentCardDetailParam, false);
        });
      })
    }
  }

  @Builder
  RecommendArtistFirst() {
    if (this.currentSourceViewModel.firstSongOfRecommendArtist) {
      MediaCard({
        backgroundImg: this.currentSourceViewModel.firstRecommendArtist?.avatar,
        title: this.currentSourceViewModel.firstRecommendArtist?.name,
        heightValue: this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 240 : 400,
        actionContent: () => {
          this.SongItem(this.currentSourceViewModel.firstSongOfRecommendArtist!)
        },
        onCardClick: () => {
          this.pageInfos.pushPathByName("PlaylistDetail", {
            playlistId: this.currentSourceViewModel.firstRecommendArtist!.id,
            sourceId: this.currentSourceViewModel.firstRecommendArtist!.sourceId,
            playlist: Playlist.Type("artist")
          } as PlaylistDetailParam, true);
        }
      })
    }
  }

  @Builder
  RecommendArtistAll() {
    if (this.currentSourceViewModel.recommendArtists && this.currentSourceViewModel.recommendArtists.length) {
      Column() {
        ContentCard({ title: $r("app.string.menu_recommended_artists"), heightValue: 400 }) {
          List() {
            Repeat<Artist>(this.currentSourceViewModel.recommendArtists.slice(1, 6))
              .each((artist) => {
                ListItem() {
                  this.ArtistItem(artist.item)
                }
              })
          }
          .width("100%")
          .height("100%")
        }
      }
      .id("RecommendArtistAll")
      .transition(TransitionEffect.OPACITY)
      .geometryTransition("RecommendArtistAll",{ follow: true })
      .onClick(() => {
        this.getUIContext().animateTo({
          curve: curves.interpolatingSpring(0, 1, 328, 37)
        }, () => {
          this.pageInfos.pushPathByName("ContentCardDetail", {
            title: $r("app.string.menu_recommended_artists"),
            type: "RecommendArtistAll"
          } as ContentCardDetailParam, false);
        });
      })
    }
  }

  @Builder
  RankFirst() {
    if (this.currentSourceViewModel.firstSongOfRank) {
      MediaCard({
        backgroundImg: cover(this.currentSourceViewModel.firstRankPlaylist?.cover, 200),
        title: this.currentSourceViewModel.firstRankPlaylist?.name,
        description: this.currentSourceViewModel.firstRankPlaylist?.description,
        heightValue: this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 240 : 400,
        actionContent: () => {
          this.SongItem(this.currentSourceViewModel.firstSongOfRank!)
        },
        onCardClick: () => {
          this.pageInfos.pushPathByName("PlaylistDetail", {
            playlistId: this.currentSourceViewModel.firstRankPlaylist!.id,
            sourceId: this.currentSourceViewModel.firstRankPlaylist!.sourceId,
            playlist: this.currentSourceViewModel.firstRankPlaylist
          } as PlaylistDetailParam, true);
        }
      })
    }
  }

  @Builder
  RankAll() {
    if (this.currentSourceViewModel.rankPlaylists && this.currentSourceViewModel.rankPlaylists.length) {
      Column() {
        ContentCard({ title: $r("app.string.menu_top_charts"), heightValue: 400 }) {
          List() {
            Repeat<Playlist>(this.currentSourceViewModel.rankPlaylists.slice(1, 6))
              .each((playlist) => {
                ListItem() {
                  this.PlaylistItem(playlist.item)
                }
              })
          }
          .width("100%")
          .height("100%")
        }
      }
      .id("RankAll")
      .transition(TransitionEffect.OPACITY)
      .geometryTransition("RankAll", { follow: true })
      .onClick(() => {
        this.getUIContext().animateTo({
          curve: curves.interpolatingSpring(0, 1, 328, 37)
        }, () => {
          this.pageInfos.pushPathByName("ContentCardDetail", {
            title: $r("app.string.menu_top_charts"),
            type: "RankAll"
          } as ContentCardDetailParam, false);
        });
      })
    }
  }

  @Builder
  Item(type: string) {
    if (type === "ForU") {
      this.ForU()
    } else if (type === "UserPlaylist-First") {
      this.UserPlaylistFirst()
    } else if (type === "HotSong-All") {
      this.HotSongAll()
    } else if (type === "RecommendPlaylist-All") {
      this.RecommendPlaylistAll()
    } else if (type === "RecommendArtist-First") {
      this.RecommendArtistFirst()
    } else if (type === "RecommendArtist-All") {
      this.RecommendArtistAll()
    } else if (type === "Rank-First") {
      this.RankFirst()
    } else if (type === "Rank-All") {
      this.RankAll()
    }
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        Grid() {
          Repeat<string>(this.currentSourceViewModel.items)
            .each((obj: RepeatItem<string>) => {
              GridItem() {
                this.Item(obj.item)
              }
            })
        }
        .columnsTemplate(this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? '1fr 1fr' :
          '1fr')
        .columnsGap(16)
        .rowsGap(16)
      }
      .margin({
        bottom: this.windowProperties.bottomRect,
        top: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? this.windowProperties.topRect + 64 : 100,
        left: 24,
        right: 24,
      })
    }
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .height("100%")
    .width("100%")
  }
}
