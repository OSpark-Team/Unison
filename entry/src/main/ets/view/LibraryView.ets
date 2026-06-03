import { WindowProperties } from '../model/WindowProperties';
import { AppStorageV2, PersistenceV2, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import { BreakpointConstants } from '../common/BreakpointConstants';
import CurrentSourceViewModel from '../viewmodel/CurrentSourceViewModel';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';
import { Playlist } from '../model/adapter/Playlist';
import { Album } from '../model/adapter/Album';
import { Artist } from '../model/adapter/Artist';
import { cover } from '../utils/Tools';
import { PlaylistDetailParam } from '../pages/PlaylistDetail';
import { Source } from '../model/Source';
import SettingViewModel from '../viewmodel/SettingViewModel';
import TabSettingModel from '../model/adapter/TabSetting';
import Logger from '../utils/Logger';

const TAG = 'LibraryView';

/**
 * 音乐库视图
 * 用于显示和管理用户的播放列表 / 收藏的专辑（顶部文字 Tab 切换，随内容滚动）
 */
@ComponentV2
export struct LibraryView {
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
   * 当前数据源 ViewModel
   */
  @Local currentSourceViewModel: CurrentSourceViewModel =
    AppStorageV2.connect(CurrentSourceViewModel, "CurrentSourceViewModel", () => new CurrentSourceViewModel())!;
  /**
   * 数据源列表 ViewModel
   */
  @Local sourceListViewModel: SourceListViewModel =
    AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!;

  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  /** Tab样式设置 ViewModel（用于统一 UI 参数） */
  @Local TabSettingModel: TabSettingModel = PersistenceV2.connect(TabSettingModel, 'TabSettingModel', () => new TabSettingModel())!;
  /**
   * 搜索关键词
   */
  @Local searchKeyword: string = '';

  /** 顶部分段：0=歌单，1=专辑 */
  @Local librarySegment: number = 0;
  /** 分段选项（歌单 / 专辑） */
  @Local segmentItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.library_tab_playlists') },
    { text: $r('app.string.library_tab_albums') },
  ]);
  /** 当前源的收藏专辑 */
  @Local albums: Album[] = [];
  /** 专辑加载中 */
  @Local albumsLoading: boolean = false;
  /** 专辑是否已加载（避免重复请求；源变化时重置） */
  private albumsLoaded: boolean = false;

  /**
   * 获取过滤后的歌单列表
   */
  @Computed
  get filteredPlaylists(): Playlist[] {
    let playlists = this.currentSourceViewModel.userPlaylists;

    // 过滤掉 ForU 类型的歌单（id 以 "key_" 开头）
    playlists = playlists.filter(p => !p.id.toString().startsWith("key_"));

    // 按名称搜索过滤
    if (this.searchKeyword.trim().length > 0) {
      const keyword = this.searchKeyword.toLowerCase();
      playlists = playlists.filter(p => p.name?.toLowerCase().includes(keyword));
    }

    return playlists;
  }

  /**
   * 获取当前列数（响应式）
   */
  @Computed
  get columnCount(): number {
    switch (this.windowProperties.currentBreakpoint) {
      case BreakpointConstants.BREAKPOINT_SM:
        return 2;
      case BreakpointConstants.BREAKPOINT_MD:
        return 3;
      case BreakpointConstants.BREAKPOINT_LG:
        return 4;
      default:
        return 2;
    }
  }

  /**
   * 获取列模板字符串
   */
  @Computed
  get columnsTemplate(): string {
    return Array(this.columnCount).fill('1fr').join(' ');
  }

  /** 空态/网格的统一高度（Scroll 内无法用 100%，按视口估一个高度） */
  @Computed
  get emptyStateHeight(): number {
    return this.windowProperties.winHeight > 0 ? this.windowProperties.winHeight * 0.55 : 420;
  }

  /** 当前源变化：重置专辑缓存，若正停留在专辑分段则立即重新加载 */
  @Monitor('currentSourceViewModel.source')
  onSourceChanged(): void {
    this.albumsLoaded = false;
    this.albums = [];
    if (this.librarySegment === 1) {
      this.loadAlbums();
    }
  }

  /** 分段切换：首次进入专辑分段时按需加载 */
  private onSegmentChange(index: number): void {
    if (this.librarySegment === index) {
      return;
    }
    this.librarySegment = index;
    if (index === 1 && !this.albumsLoaded) {
      this.loadAlbums();
    }
  }

  /** 加载当前源的收藏专辑（getSubscribedAlbums） */
  private async loadAlbums(): Promise<void> {
    const source: Source | null = this.currentSourceViewModel.source;
    if (!source) {
      this.albums = [];
      return;
    }
    this.albumsLoading = true;
    this.albumsLoaded = true;
    try {
      this.albums = await source.getSubscribedAlbums();
    } catch (e) {
      Logger.error(TAG, `加载收藏专辑失败: ${e}`);
      this.albums = [];
    } finally {
      this.albumsLoading = false;
    }
  }

  /**
   * 跳转到歌单详情
   */
  navigateToPlaylistDetail(playlist: Playlist): void {
    this.pageInfos.pushPathByName("PlaylistDetail", {
      playlistId: playlist.id,
      sourceId: playlist.sourceId,
      playlist: playlist
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
    this.pageInfos.pushPathByName("PlaylistDetail", {
      playlistId: album.id.toString(),
      sourceId: album.sourceId,
      playlist: pl
    } as PlaylistDetailParam, true);
  }

  // ── 顶部分段（官方 TabSegmentButtonV2，Tab 下划线样式，随内容滚动不固定） ──────
  @Builder
  buildSegmentBar() {
    Column() {
      TabSegmentButtonV2({
        items: this.segmentItems,
        selectedIndex: this.librarySegment,
        $selectedIndex: (index: number) => this.onSegmentChange(index),
      })
    }
    .width('100%')
    .padding({
      top: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? this.windowProperties.topRect + 64 : 100,
      left: 24,
      right: 24,
      bottom: 12,
    })
  }

  /**
   * 歌单卡片构建器
   */
  @Builder
  PlaylistCard(playlist: Playlist) {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 封面图
        Image(cover(playlist.cover, 300))
          .width('100%')
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)

        // 渐变遮罩和信息
        Column() {
          Text(playlist.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.playlist_text_on_image'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text($r('app.string.song_count_simple', playlist.size ?? 0))
            .fontSize(12)
            .fontColor($r('app.color.playlist_text_secondary_on_image'))
            .margin({ top: 4 })
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[$r('app.color.library_card_gradient_start'), 0], [$r('app.color.library_card_gradient_end'), 1]]
        })
      }
      .width('100%')
      .borderRadius(this.settingModel.radiusCard)
      .clip(true)
      .shadow({
        radius: 8,
        color: $r('app.color.library_card_shadow'),
        offsetX: 0,
        offsetY: 4
      })
    }
    .onClick(() => {
      this.navigateToPlaylistDetail(playlist);
    })
  }

  /**
   * 专辑卡片构建器（与歌单卡片同款，副标题改为艺术家）
   */
  @Builder
  AlbumCard(album: Album) {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Image(cover(album.cover, 300))
          .width('100%')
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)

        Column() {
          Text(album.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.playlist_text_on_image'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(album.artists?.map((a: Artist) => a.name).join('/') ?? '')
            .fontSize(12)
            .fontColor($r('app.color.playlist_text_secondary_on_image'))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[$r('app.color.library_card_gradient_start'), 0], [$r('app.color.library_card_gradient_end'), 1]]
        })
      }
      .width('100%')
      .borderRadius(this.settingModel.radiusCard)
      .clip(true)
      .shadow({
        radius: 8,
        color: $r('app.color.library_card_shadow'),
        offsetX: 0,
        offsetY: 4
      })
    }
    .onClick(() => {
      this.openAlbum(album);
    })
  }

  /**
   * 歌单空状态构建器
   */
  @Builder
  EmptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(64)
        .fontColor([$r('app.color.library_empty_icon')])

      Text($r('app.string.library_empty_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text($r('app.string.library_empty_description'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(this.emptyStateHeight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 专辑空状态 / 加载态构建器
   */
  @Builder
  AlbumEmptyState() {
    Column({ space: 16 }) {
      if (this.albumsLoading) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.accent'))
      } else {
        SymbolGlyph($r('sys.symbol.opticaldisc'))
          .fontSize(64)
          .fontColor([$r('app.color.library_empty_icon')])

        Text($r('app.string.subscribed_albums_empty'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width('100%')
    .height(this.emptyStateHeight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 歌单网格（Grid 不设 layoutWeight，随 Scroll 自适应高度）
   */
  @Builder
  PlaylistContent() {
    if (this.filteredPlaylists.length === 0) {
      this.EmptyState()
    } else {
      Grid() {
        Repeat<Playlist>(this.filteredPlaylists)
          .each((item: RepeatItem<Playlist>) => {
            GridItem() {
              this.PlaylistCard(item.item)
            }
          })
          .key((item: Playlist) => `playlist-${item.id}`)
      }
      .columnsTemplate(this.columnsTemplate)
      .columnsGap(16)
      .rowsGap(16)
      .padding({ left: 24, right: 24 })
    }
  }

  /**
   * 专辑网格（Grid 不设 layoutWeight，随 Scroll 自适应高度）
   */
  @Builder
  AlbumContent() {
    if (this.albums.length === 0) {
      this.AlbumEmptyState()
    } else {
      Grid() {
        Repeat<Album>(this.albums)
          .each((item: RepeatItem<Album>) => {
            GridItem() {
              this.AlbumCard(item.item)
            }
          })
          .key((item: Album) => `album-${item.sourceId}-${item.id}`)
      }
      .columnsTemplate(this.columnsTemplate)
      .columnsGap(16)
      .rowsGap(16)
      .padding({ left: 24, right: 24 })
    }
  }

  build() {
    Column() {
      Scroll(this.scroller) {
        Column() {
          // 顶部文字 Tab（随内容滚动，不固定）
          this.buildSegmentBar()

          // 内容区
          if (this.librarySegment === 0) {
            this.PlaylistContent()
          } else {
            this.AlbumContent()
          }
        }
        .width('100%')
        .margin({ bottom: this.windowProperties.bottomRect })
      }
      .contentEndOffset(this.TabSettingModel.barFloatingStyle ? 72 + 48 + 10 : 0)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .height('100%')
  }
}
