import { AppStorageV2 } from '@kit.ArkUI';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';
import { WindowProperties } from '../model/WindowProperties';
import { BreakpointConstants } from '../common/BreakpointConstants';
import { Playlist } from '../model/adapter/Playlist';
import { Song } from '../model/adapter/Song';
import { PlaylistInfoCard } from '../components/PlaylistInfoCard';
import { PlaylistSongGrid } from '../components/PlaylistSongGrid';
import { CustomTitleBar } from '../components/CustomTitleBar';
import Logger from '../utils/Logger';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { ContinueSwitch } from '../utils/Continue';
import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
import PlaylistViewModel from '../viewmodel/PlaylistViewModel';
import { PlaylistMeta } from '../model/adapter/PlaylistMeta';
import { shuffle } from '../utils/Tools';
import { MiniPlayerUiState } from '../model/MiniPlayerUiState';

const TAG = 'PlaylistDetail';

/**
 * 歌单详情页面参数接口
 */
export interface PlaylistDetailParam {
  playlistId: string;
  sourceId: string;
  playlist: Playlist;
}

/**
 * 歌单详情页面 Builder
 */
@Builder
export function PlaylistDetailBuilder() {
  PlaylistDetail()
}

/**
 * 歌单详情页面组件
 *
 * 功能特性：
 * - 支持三种断点的响应式布局
 * - MVVM V2 架构模式
 * - 歌单信息展示和歌曲列表
 * - 播放控制和操作功能
 * - 动态主题色适配
 * - 错误处理和重试机制
 *
 * 布局规格：
 * - BREAKPOINT_LG: 1:1:1 三列布局 (信息卡片 | 歌曲网格 1fr 1fr | 歌曲网格 1fr 1fr)
 * - BREAKPOINT_MD: 1:1 两列布局 (信息卡片 | 歌曲网格 1fr)
 * - BREAKPOINT_SM: 垂直单列布局 (信息卡片 → 固定操作栏 → 可滚动歌曲列表)
 */
@ComponentV2
struct PlaylistDetail {
  /**
   * 路由导航
   */
  @Consumer() pageInfos: NavPathStack = new NavPathStack();

  /**
   * 数据源列表 ViewModel
   */
  @Local viewModel: SourceListViewModel =
    AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!;

  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;

  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel = PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /**
   * 播放列表 ViewModel
   */
  @Local playlistViewModel: PlaylistViewModel =
    AppStorageV2.connect(PlaylistViewModel, 'PlaylistViewModel', () => new PlaylistViewModel())!;
  @Local miniPlayerUiState: MiniPlayerUiState =
    AppStorageV2.connect(MiniPlayerUiState, 'MiniPlayerUiState', () => new MiniPlayerUiState())!;


  /**
   * 路由参数
   */
  @Local param: PlaylistDetailParam = {
    playlistId: '',
    sourceId: '',
    playlist: new Playlist()
  };

  /**
   * 歌单数据
   * 始终保持为 new Playlist() 的实例，确保 @ObservedV2 + @Trace 响应式生效
   */
  @Local playlist: Playlist = new Playlist();

  /**
   * 加载状态
   */
  @Local isLoading: boolean = true;

  /**
   * 错误状态
   */
  @Local hasError: boolean = false;

  /**
   * 错误信息
   */
  @Local errorMessage: string = '';

  /**
   * 搜索关键词
   */
  @Local searchKeyword: string = '';
  private miniPlayerResumeTimerId: number = -1;

  aboutToAppear(): void {
    this.miniPlayerUiState.playlistDetailActive = true;
    this.clearMiniPlayerVisibilityTimer();
    this.setMiniPlayerVisibility(true);
  }

  aboutToDisappear(): void {
    this.miniPlayerUiState.playlistDetailActive = false;
    this.clearMiniPlayerVisibilityTimer();
    this.setMiniPlayerVisibility(true);
  }

  private setMiniPlayerVisibility(visible: boolean): void {
    this.miniPlayerUiState.playlistDetailVisible = visible;
  }

  private clearMiniPlayerVisibilityTimer(): void {
    if (this.miniPlayerResumeTimerId !== -1) {
      clearTimeout(this.miniPlayerResumeTimerId);
      this.miniPlayerResumeTimerId = -1;
    }
  }

  private handleSongGridScroll(): void {
    this.setMiniPlayerVisibility(false);
    this.clearMiniPlayerVisibilityTimer();
    this.miniPlayerResumeTimerId = setTimeout(() => {
      this.setMiniPlayerVisibility(true);
      this.miniPlayerResumeTimerId = -1;
    }, 220);
  }

  /**
   * 初始化歌单基础信息
   */
  private initializePlaylistInfo(): void {
    if (this.param.playlist) {
      // 使用 new Playlist() 实例赋值，保留 @ObservedV2 响应式能力
      const initial = new Playlist();
      initial.id = this.param.playlist.id;
      initial.name = this.param.playlist.name;
      initial.cover = this.param.playlist.cover;
      initial.description = this.param.playlist.description;
      initial.size = this.param.playlist.size;
      initial.songs = this.param.playlist.songs;
      initial.type = this.param.playlist.type;
      initial.creator = this.param.playlist.creator;
      initial.sourceId = this.param.playlist.sourceId;
      if (this.param.playlist.meta) {
        const meta = new PlaylistMeta();
        meta.subscribed = this.param.playlist.meta.subscribed;
        initial.meta = meta;
      }
      this.playlist = initial;
      Logger.info(TAG, `初始化歌单基础信息: ${this.playlist.name}`);
    }
  }

  /**
   * 处理搜索关键词变化
   */
  private handleSearchChange(keyword: string): void {
    this.searchKeyword = keyword;
  }

  private shouldShowFavoriteButton(): boolean {
    return this.playlist.type === 'normal' &&
      !this.playlist.id.toString().startsWith('key_') &&
      this.viewModel.sources.find(source => source.id === this.playlist.sourceId)?.user?.id !== this.playlist.creator?.id;
  }

  /**
   * 过滤歌曲列表
   */
  @Computed
  get filterSongs(): Song[] {
    if (!this.playlist.songs) {
      return [];
    }

    if (!this.searchKeyword || this.searchKeyword.trim() === '') {
      return this.playlist.songs;
    }

    const keyword = this.searchKeyword.toLowerCase().trim();

    const filteredSongs = this.playlist.songs.filter((song: Song) => {
      const songNameMatch = song.name && song.name.toLowerCase().includes(keyword);
      const artistNameMatch = song.artists && song.artists.some(artist =>
      artist.name && artist.name.toLowerCase().includes(keyword)
      );
      const albumNameMatch = song.album && song.album.name &&
      song.album.name.toLowerCase().includes(keyword);
      return songNameMatch || artistNameMatch || albumNameMatch;
    });

    Logger.info(TAG, `搜索关键词: ${keyword}, 过滤结果: ${filteredSongs.length}/${this.playlist.songs.length}`);
    return filteredSongs;
  }

  /**
   * 加载歌单详情数据
   */
  private async loadPlaylistDetail(): Promise<void> {
    if (!this.param.playlistId || !this.param.sourceId) {
      Logger.error(TAG, '歌单ID或数据源ID为空');
      this.hasError = true;
      this.errorMessage = '参数错误';
      this.isLoading = false;
      return;
    }

    try {
      this.isLoading = true;
      this.hasError = false;

      const source = this.viewModel.sources.find(s => s.id === this.param.sourceId);
      if (!source) {
        throw new Error(`未找到数据源: ${this.param.sourceId}`);
      }

      let detailData: Playlist = new Playlist();

      if (this.playlist.type === "normal") {
        detailData = await source.getPlaylistDetail(this.param.playlistId);
      } else if (this.playlist.type === "album") {
        detailData = await source.getAlbumDetail(this.param.playlistId);
      } else if (this.playlist.type === "artist") {
        detailData = await source.getArtistDetail(this.param.playlistId);
      }

      // 始终用 new Playlist() 实例构造，保留 @ObservedV2 响应式能力
      // 直接赋值字面量对象会丢失 @ObservedV2 实例，导致 @Trace 失效
      const merged = new Playlist();
      merged.id = this.param.playlistId;
      merged.sourceId = this.param.sourceId;
      merged.name = this.param.playlist.name ?? detailData.name;
      merged.cover = this.param.playlist.cover ?? detailData.cover;
      merged.description = this.param.playlist.description ?? detailData.description;
      merged.size = this.param.playlist.size ?? detailData.size;
      merged.songs = detailData.songs;
      merged.type = this.param.playlist.type ?? detailData.type;
      merged.creator = this.param.playlist.creator ?? detailData.creator;

      // meta 也必须是 new PlaylistMeta() 实例
      const meta = new PlaylistMeta();
      meta.subscribed = detailData.meta?.subscribed;
      merged.meta = meta;

      this.playlist = merged;

      Logger.info(TAG, `歌单详情加载成功: ${this.playlist.name}, 歌曲数量: ${this.playlist.songs?.length || 0}, 是否喜欢: ${this.playlist.meta?.subscribed}, 类型: ${this.playlist.type}`);

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `歌单详情加载失败: ${errorMsg}`);
      this.hasError = true;
      this.errorMessage = errorMsg;
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 重试加载
   */
  private handleRetry(): void {
    this.loadPlaylistDetail();
  }

  /**
   * 播放全部歌曲
   */
  private handlePlayAll(): void {
    if (!this.playlist.songs || this.playlist.songs.length === 0) {
      Logger.warn(TAG, '歌单为空，无法播放');
      return;
    }

    Logger.info(TAG, `播放全部歌曲，共 ${this.playlist.songs.length} 首`);
    this.playlistViewModel.clearPlaylist();
    this.playlistViewModel.insertSongs(this.playlist.songs ?? []);
    this.playlistViewModel.playSongByIndex(0, true);
  }

  /**
   * 收藏或取消收藏歌单
   *
   * 修复：this.playlist 是 @ObservedV2 实例，meta.subscribed 有 @Trace
   * 直接修改属性即可驱动 UI 刷新，无需重建整个对象
   */
  private async handleToggleFavorite(): Promise<void> {
    if (!this.playlist.id) {
      Logger.warn(TAG, '歌单ID为空，无法收藏');
      return;
    }

    try {
      const dialog = await this.getUIContext().getPromptAction().showDialog({
        title: this.playlist.meta?.subscribed ? $r('app.string.cancel_favorite') : $r('app.string.favorite'),
        message: this.playlist.meta?.subscribed
          ? $r('app.string.cancel_favorite_message', this.playlist.name)
          : $r('app.string.favorite_message', this.playlist.name),
        buttons: [
          { text: $r('app.string.cancel'), color: $r('app.color.dialog_text_secondary') },
          { text: $r('app.string.confirm'), color: $r('app.color.dialog_text_primary') }
        ]
      });

      if (dialog.index === 0) {
        return;
      }

      const source = this.viewModel.sources.find(s => s.id === this.playlist.sourceId);
      if (!source) {
        throw new Error(`未找到数据源: ${this.playlist.sourceId}`);
      }

      if (this.playlist.meta?.subscribed) {
        await source.unsubscribePlaylist(this.playlist.id);
      } else {
        await source.subscribePlaylist(this.playlist.id);
      }

      // 直接修改 @Trace 属性，框架自动驱动 UI 刷新
      // 前提：this.playlist 必须是 new Playlist() 实例（见 loadPlaylistDetail / initializePlaylistInfo）
      if (!this.playlist.meta) {
        this.playlist.meta = new PlaylistMeta();
      }
      this.playlist.meta.subscribed = !this.playlist.meta.subscribed;

      this.getUIContext().getPromptAction().showToast({
        message: this.playlist.meta.subscribed
          ? $r('app.string.favorite_success')
          : $r('app.string.cancel_favorite_success')
      });

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `收藏/取消收藏失败: ${errorMsg}`);
    }
  }

  /**
   * 随机播放
   */
  private handleShuffle(): void {
    if (!this.playlist.songs || this.playlist.songs.length === 0) {
      Logger.warn(TAG, '歌单为空，无法随机播放');
      return;
    }

    Logger.info(TAG, '随机播放歌单');
    this.playlistViewModel.clearPlaylist();
    this.playlistViewModel.insertSongs(shuffle(this.playlist.songs ?? []));
    this.playlistViewModel.playSongByIndex(0, true);
  }

  /**
   * 歌曲点击处理
   */
  private handleSongClick(song: Song, index: number): void {
    Logger.info(TAG, `点击歌曲: ${song.name}, 索引: ${index}`);
    this.playlistViewModel.clearPlaylist();
    this.playlistViewModel.insertSongs(this.playlist.songs ?? []);
    this.playlistViewModel.playSong(song, true);
  }

  /**
   * 歌曲长按处理
   */
  private handleSongLongPress(song: Song, index: number): void {
    Logger.info(TAG, `长按歌曲: ${song.name}, 索引: ${index}`);
    // TODO: 实现歌曲操作菜单
  }

  /**
   * 返回按钮处理
   */
  private handleBack(): void {
    this.pageInfos.pop();
  }

  /**
   * 大屏布局 Builder (LG断点)
   */
  @Builder
  buildSongGrid() {
    PlaylistSongGrid({
      songs: this.filterSongs,
      onSongClick: (song, index) => this.handleSongClick(song, index),
      onSongLongPress: (song, index) => this.handleSongLongPress(song, index),
      onScrollOffsetChange: (_offset: number) => this.handleSongGridScroll()
    })
  }

  /**
   * 大屏布局 Builder (LG断点)
   */
  @Builder
  buildLargeScreenLayout() {
    Row({ space: 20 }) {
      Column() {
        PlaylistInfoCard({
          playlist: this.playlist,
          showFavoriteButton: this.shouldShowFavoriteButton(),
          isSubscribed: this.playlist.meta?.subscribed ?? false,
          onPlayAll: () => this.handlePlayAll(),
          onShuffle: () => this.handleShuffle(),
          onToggleFavorite: () => this.handleToggleFavorite(),
          cardHeight: 'auto',
          coverSize: 210,
          isVerticalLayout: false
        })
      }
      .width('33.33%')
      .height('100%')

      Column() {
        this.buildSongGrid()
      }
        .layoutWeight(1)
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 0 })
    .alignItems(VerticalAlign.Top)
  }

  /**
   * 中屏布局 Builder (MD断点)
   */
  @Builder
  buildMediumScreenLayout() {
    Row({ space: 18 }) {
      Column() {
        PlaylistInfoCard({
          playlist: this.playlist,
          showFavoriteButton: this.shouldShowFavoriteButton(),
          isSubscribed: this.playlist.meta?.subscribed ?? false,
          onPlayAll: () => this.handlePlayAll(),
          onShuffle: () => this.handleShuffle(),
          onToggleFavorite: () => this.handleToggleFavorite(),
          cardHeight: 'auto',
          coverSize: 190,
          isVerticalLayout: false
        })
      }
      .width('40%')
      .height('100%')

      Column() {
        this.buildSongGrid()
      }
        .layoutWeight(1)
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 0 })
    .alignItems(VerticalAlign.Top)
  }

  /**
   * 小屏布局 Builder (SM断点)
   */
  @Builder
  buildSmallScreenLayout() {
    Column({ space: 12 }) {
      PlaylistInfoCard({
        playlist: this.playlist,
        showFavoriteButton: this.shouldShowFavoriteButton(),
        isSubscribed: this.playlist.meta?.subscribed ?? false,
        onPlayAll: () => this.handlePlayAll(),
        onShuffle: () => this.handleShuffle(),
        onToggleFavorite: () => this.handleToggleFavorite(),
        cardHeight: 230,
        coverSize: 140,
        isVerticalLayout: true
      })
      .width('100%')
      .height(230)

      Column() {
        this.buildSongGrid()
      }
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 0 })
  }

  /**
   * 响应式布局 Builder
   */
  @Builder
  buildResponsiveLayout() {
    if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
      this.buildLargeScreenLayout()
    } else if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_MD) {
      this.buildMediumScreenLayout()
    } else {
      this.buildSmallScreenLayout()
    }
  }

  /**
   * 加载状态 Builder
   */
  @Builder
  buildLoadingState() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.accent'))

      Text($r('app.string.playlist_loading'))
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.background_primary'))
  }

  /**
   * 错误状态 Builder
   */
  @Builder
  buildErrorState() {
    Column({ space: 20 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(48)
        .fontColor([$r('app.color.error')])

      Text($r('app.string.playlist_load_failed'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(3)
      }

      Button($r('app.string.playlist_retry'))
        .type(ButtonType.Normal)
        .backgroundColor($r('app.color.button_retry_background'))
        .fontColor($r('app.color.button_retry_text'))
        .borderRadius(12)
        .padding({ left: 32, right: 32, top: 14, bottom: 14 })
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .shadow({
          radius: 8,
          color: $r('app.color.shadow_medium'),
          offsetX: 0,
          offsetY: 2
        })
        .onClick(() => this.handleRetry())
        .animation({
          duration: 200,
          curve: Curve.EaseInOut
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(40)
    .backgroundColor($r('app.color.background_primary'))
  }

  build() {
    HdsNavDestination() {
      Column() {
        CustomTitleBar({
          title: this.playlist.name || $r('app.string.playlist_detail_title'),
          showSearchBox: true,
          onBackClick: () => this.handleBack(),
          onSearchChange: (keyword: string) => this.handleSearchChange(keyword),
          searchPlaceholder: $r('app.string.search_placeholder')
        })

        Column() {
          if (this.isLoading) {
            this.buildLoadingState()
          } else if (this.hasError) {
            this.buildErrorState()
          } else {
            this.buildResponsiveLayout()
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .onBackPressed(() => {
      if (this.miniPlayerUiState.isExpanded) {
        this.miniPlayerUiState.collapseRequestVersion += 1;
        return true;
      }
      this.handleBack();
      return true;
    })
    .mode(NavDestinationMode.STANDARD)
    .hideTitleBar(true)
    .ignoreLayoutSafeArea()
    .backgroundColor($r('app.color.background_primary'))
    .onReady((context: NavDestinationContext) => {
      this.param = (context.pathInfo.param as PlaylistDetailParam);
      this.initializePlaylistInfo();
      this.loadPlaylistDetail();
      Logger.info(TAG, `接收到路由参数: playlistId=${this.param.playlistId}, sourceId=${this.param.sourceId}`);
    })
    .onShown(() => {
      this.miniPlayerUiState.playlistDetailActive = true;
      this.setMiniPlayerVisibility(true);
      ContinueSwitch.setContinueData({
        page: "detail",
        id: this.param.playlistId,
        sourceId: this.param.sourceId,
        playlist: this.param.playlist
      })
      ContinueSwitch.enableContinue();
    })
    .onHidden(() => {
      this.miniPlayerUiState.playlistDetailActive = false;
      this.clearMiniPlayerVisibilityTimer();
      this.setMiniPlayerVisibility(true);
      ContinueSwitch.disableContinue();
    })
  }
}
