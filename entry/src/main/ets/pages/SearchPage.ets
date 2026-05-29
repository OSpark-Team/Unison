import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';
import PlaylistViewModel from '../viewmodel/PlaylistViewModel';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { WindowProperties } from '../model/WindowProperties';
import { CustomTitleBar } from '../components/CustomTitleBar';
import { SongListItem } from '../components/SongListItem';
import { PlaylistListItem } from '../components/PlaylistListItem';
import { ArtistListItem } from '../components/ArtistListItem';
import { Song } from '../model/adapter/Song';
import { Playlist } from '../model/adapter/Playlist';
import { Artist } from '../model/adapter/Artist';
import { Album } from '../model/adapter/Album';
import { Source } from '../model/Source';
import { SearchResponse } from '../adapter/omsp';
import { cover } from '../utils/Tools';
import { PlaylistDetailParam } from './PlaylistDetail';
import Logger from '../utils/Logger';

const TAG = 'SearchPage';

/** 分类 Tab 标题 */
const TAB_TITLES: string[] = ['歌曲', '歌单', '艺术家', '专辑'];

/**
 * 搜索页面参数
 */
export interface SearchPageParam {
  /** 进入时默认选中的数据源 id（不传或未命中则默认「全部」） */
  sourceId?: string;
}

/**
 * 搜索页面 Builder（供 route_map 注册）
 */
@Builder
export function SearchPageBuilder() {
  SearchPage()
}

/**
 * 全局搜索页面
 * - 数据源切换：「全部」聚合所有源 / 单源
 * - 分类 Tab：歌曲 / 歌单 / 艺术家 / 专辑
 * - 提交触发搜索（回车 / 搜索按钮）
 */
@ComponentV2
struct SearchPage {
  @Consumer() pageInfos: NavPathStack = new NavPathStack();

  @Local sourceListViewModel: SourceListViewModel =
    AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!;
  @Local playlistViewModel: PlaylistViewModel =
    AppStorageV2.connect(PlaylistViewModel, 'PlaylistViewModel', () => new PlaylistViewModel())!;
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, 'WindowProperties', () => new WindowProperties())!;

  /** 搜索关键词 */
  @Local keyword: string = '';
  /** 选中数据源：0=全部，1..n 对应 sources[idx-1] */
  @Local selectedSourceIndex: number = 0;
  /** 当前分类 Tab */
  @Local activeTab: number = 0;
  /** 是否搜索中 */
  @Local isLoading: boolean = false;
  /** 是否已执行过搜索（区分空态文案） */
  @Local hasSearched: boolean = false;

  @Local songs: Song[] = [];
  @Local playlists: Playlist[] = [];
  @Local artists: Artist[] = [];
  @Local albums: Album[] = [];

  private param: SearchPageParam = {};
  private tabsController: TabsController = new TabsController();

  /**
   * 当前选中数据源的显示名
   */
  @Computed
  get currentSourceLabel(): string {
    if (this.selectedSourceIndex === 0) {
      return '全部数据源';
    }
    return this.sourceListViewModel.sources[this.selectedSourceIndex - 1]?.name ?? '全部数据源';
  }

  /**
   * 数据源下拉菜单项：「全部」+ 各数据源
   */
  private getSourceMenuItems(): MenuElement[] {
    const items: MenuElement[] = [{
      value: '全部数据源',
      action: () => this.onSourceSelect(0)
    }];
    this.sourceListViewModel.sources.forEach((s: Source, i: number) => {
      items.push({
        value: s.name,
        action: () => this.onSourceSelect(i + 1)
      });
    });
    return items;
  }

  /**
   * 当前要搜索的数据源集合（0=全部源；否则单源）
   */
  private getSearchSources(): Source[] {
    if (this.selectedSourceIndex === 0) {
      return this.sourceListViewModel.sources;
    }
    const s = this.sourceListViewModel.sources[this.selectedSourceIndex - 1];
    return s ? [s] : [];
  }

  /**
   * 执行搜索（提交触发）。「全部」时并发搜索各源并合并结果。
   */
  async doSearch(): Promise<void> {
    const kw = this.keyword.trim();
    if (kw.length === 0) {
      return;
    }
    this.isLoading = true;
    this.hasSearched = true;

    const sources = this.getSearchSources();
    const responses: Array<SearchResponse | null> = await Promise.all(
      sources.map((s: Source) =>
        s.search(kw).catch((e: Error): SearchResponse | null => {
          Logger.error(TAG, `搜索失败 source=${s.id}: ${e}`);
          return null;
        })
      )
    );

    const songs: Song[] = [];
    const playlists: Playlist[] = [];
    const artists: Artist[] = [];
    const albums: Album[] = [];
    responses.forEach((r: SearchResponse | null) => {
      if (!r) {
        return;
      }
      if (r.songs) {
        songs.push(...r.songs);
      }
      if (r.playlists) {
        playlists.push(...r.playlists);
      }
      if (r.artists) {
        artists.push(...r.artists);
      }
      if (r.albums) {
        albums.push(...r.albums);
      }
    });

    this.songs = songs;
    this.playlists = playlists;
    this.artists = artists;
    this.albums = albums;
    this.isLoading = false;
    Logger.info(TAG, `搜索完成: 歌曲${songs.length} 歌单${playlists.length} 艺术家${artists.length} 专辑${albums.length}`);
  }

  private onSourceSelect(index: number): void {
    this.selectedSourceIndex = index;
    if (this.keyword.trim().length > 0) {
      this.doSearch();
    }
  }

  private artistNames(song: Song): string {
    return song.artists?.map((a: Artist) => a.name).join(' / ') ?? '';
  }

  /** 点击歌曲：插入到队列最前并立即播放 */
  private playSongNow(song: Song): void {
    this.playlistViewModel.insertSongs([song], 0);
    this.playlistViewModel.playSong(song, true);
  }

  /** 菜单：添加到「下一首播放」（插入到当前歌之后，不打断当前播放） */
  private addToPlayNext(song: Song): void {
    const nextIndex = Math.max(0, this.playlistViewModel.currentIndex + 1);
    this.playlistViewModel.insertSongs([song], nextIndex);
  }

  /** 歌曲长按菜单 */
  @Builder
  buildSongMenu(song: Song) {
    Menu() {
      MenuItem({ startIcon: $r('sys.symbol.play_fill'), content: '立即播放' })
        .onClick(() => this.playSongNow(song))
      MenuItem({ startIcon: $r('sys.symbol.plus'), content: '添加到下一首播放' })
        .onClick(() => this.addToPlayNext(song))
    }
  }

  private openPlaylist(pl: Playlist): void {
    this.pageInfos.pushPathByName('PlaylistDetail', {
      playlistId: pl.id.toString(),
      sourceId: pl.sourceId,
      playlist: pl
    } as PlaylistDetailParam, true);
  }

  /** 专辑：包装成 type=album 的 Playlist，复用 PlaylistDetail（其按 type 调 getAlbumDetail） */
  private openAlbum(album: Album): void {
    const pl = new Playlist();
    pl.id = album.id;
    pl.name = album.name;
    pl.cover = album.cover;
    pl.size = album.size;
    pl.type = 'album';
    pl.sourceId = album.sourceId;
    this.pageInfos.pushPathByName('PlaylistDetail', {
      playlistId: album.id.toString(),
      sourceId: album.sourceId,
      playlist: pl
    } as PlaylistDetailParam, true);
  }

  /** 艺术家：包装成 type=artist 的 Playlist，复用 PlaylistDetail（其按 type 调 getArtistDetail） */
  private openArtist(artist: Artist): void {
    const pl = new Playlist();
    pl.id = artist.id;
    pl.name = artist.name;
    pl.cover = artist.avatar;
    pl.type = 'artist';
    pl.sourceId = artist.sourceId;
    this.pageInfos.pushPathByName('PlaylistDetail', {
      playlistId: artist.id.toString(),
      sourceId: artist.sourceId,
      playlist: pl
    } as PlaylistDetailParam, true);
  }

  // ── 数据源切换器（应用风格胶囊 + bindMenu） ─────────────────────────────────
  @Builder
  buildSourceSelector() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.rectangle_stack'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
      Text(this.currentSourceLabel)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(13)
        .fontColor([$r('app.color.text_secondary')])
    }
    .padding({ left: 14, right: 12, top: 9, bottom: 9 })
    .backgroundColor($r('app.color.library_source_selector_background'))
    .borderRadius(20)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
    .bindMenu(this.getSourceMenuItems())
  }

  // ── 自定义分类 Tab（应用色 + 选中加粗 + 短下划线） ──────────────────────────
  @Builder
  tabBarBuilder(index: number) {
    Column({ space: 6 }) {
      Text(TAB_TITLES[index])
        .fontSize(16)
        .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === index ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      Row()
        .width(this.activeTab === index ? 22 : 0)
        .height(3)
        .borderRadius(2)
        .backgroundColor($r('app.color.accent'))
        .animation({ duration: 250, curve: Curve.EaseInOut })
    }
    .padding({ top: 10, bottom: 8 })
    .onClick(() => {
      this.activeTab = index;
      this.tabsController.changeIndex(index);
    })
  }

  // ── 结果列表（白卡片容器） ───────────────────────────────────────────────────
  @Builder
  buildSongList() {
    List({ space: 0 }) {
      ForEach(this.songs, (song: Song, idx: number) => {
        ListItem() {
          SongListItem({
            coverImage: cover(song.album?.cover, 100),
            songName: song.name ?? '',
            artistName: this.artistNames(song),
            duration: song.duration ?? '',
            isActive: this.playlistViewModel.currentSong?.id === song.id
              && this.playlistViewModel.currentSong?.sourceId === song.sourceId,
            showDivider: idx < this.songs.length - 1,
            onItemClick: () => this.playSongNow(song)
          })
        }
        .bindContextMenu(this.buildSongMenu(song), ResponseType.LongPress)
      }, (song: Song, idx: number): string => `song-${song.sourceId}-${song.id}-${idx}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildPlaylistList() {
    List({ space: 0 }) {
      ForEach(this.playlists, (pl: Playlist) => {
        ListItem() {
          PlaylistListItem({
            coverImage: cover(pl.cover, 100),
            playlistName: pl.name ?? '',
            trackCount: pl.size ?? 0,
            onItemClick: () => this.openPlaylist(pl)
          })
        }
      }, (pl: Playlist, idx: number): string => `pl-${pl.sourceId}-${pl.id}-${idx}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildArtistList() {
    List({ space: 0 }) {
      ForEach(this.artists, (artist: Artist) => {
        ListItem() {
          ArtistListItem({
            coverImage: cover(artist.avatar, 100),
            artistName: artist.name,
            onItemClick: () => this.openArtist(artist)
          })
        }
      }, (artist: Artist, idx: number): string => `ar-${artist.sourceId}-${artist.id}-${idx}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildAlbumList() {
    List({ space: 0 }) {
      ForEach(this.albums, (album: Album) => {
        ListItem() {
          PlaylistListItem({
            coverImage: cover(album.cover, 100),
            playlistName: album.name,
            trackCount: album.size ?? 0,
            onItemClick: () => this.openAlbum(album)
          })
        }
      }, (album: Album, idx: number): string => `al-${album.sourceId}-${album.id}-${idx}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 空态 / 加载态占位 */
  @Builder
  buildPlaceholder() {
    Column({ space: 14 }) {
      if (this.isLoading) {
        LoadingProgress()
          .width(44)
          .height(44)
          .color($r('app.color.accent'))
        Text('搜索中…')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      } else {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(56)
          .fontColor([$r('app.color.library_empty_icon')])
        Text(this.hasSearched ? '没有找到相关结果' : '输入关键词后回车开始搜索')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (!this.hasSearched) {
          Text('支持搜索歌曲、歌单、艺术家、专辑')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Column() {
        CustomTitleBar({
          showBackButton: true,
          showSearchBox: true,
          onBackClick: () => this.pageInfos.pop(),
          onSearchChange: (k: string) => {
            this.keyword = k;
          },
          onSearchSubmit: (k: string) => {
            this.keyword = k;
            this.doSearch();
          }
        })

        // 数据源切换器（左对齐胶囊）
        Row() {
          this.buildSourceSelector()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 10 })
        .justifyContent(FlexAlign.Start)

        // 分类 Tab
        Tabs({ controller: this.tabsController }) {
          TabContent() {
            if (this.songs.length > 0) {
              this.buildSongList()
            } else {
              this.buildPlaceholder()
            }
          }
          .tabBar(this.tabBarBuilder(0))

          TabContent() {
            if (this.playlists.length > 0) {
              this.buildPlaylistList()
            } else {
              this.buildPlaceholder()
            }
          }
          .tabBar(this.tabBarBuilder(1))

          TabContent() {
            if (this.artists.length > 0) {
              this.buildArtistList()
            } else {
              this.buildPlaceholder()
            }
          }
          .tabBar(this.tabBarBuilder(2))

          TabContent() {
            if (this.albums.length > 0) {
              this.buildAlbumList()
            } else {
              this.buildPlaceholder()
            }
          }
          .tabBar(this.tabBarBuilder(3))
        }
        .barMode(BarMode.Fixed)
        .barHeight(48)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })
        .onChange((index: number) => {
          this.activeTab = index;
        })
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .mode(NavDestinationMode.STANDARD)
    .hideTitleBar(true)
    .ignoreLayoutSafeArea()
    .backgroundColor($r('app.color.background_primary'))
    .onReady((context: NavDestinationContext) => {
      this.param = context.pathInfo.param as SearchPageParam;
      // 默认源：传入 sourceId 命中某源则选它，否则保持「全部」
      if (this.param && this.param.sourceId) {
        const idx = this.sourceListViewModel.sources.findIndex((s: Source) => s.id === this.param.sourceId);
        if (idx >= 0) {
          this.selectedSourceIndex = idx + 1;
        }
      }
    })
  }
}
