import { WindowProperties } from '../model/WindowProperties';
import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BreakpointConstants } from '../common/BreakpointConstants';
import CurrentSourceViewModel from '../viewmodel/CurrentSourceViewModel';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';
import { Playlist } from '../model/adapter/Playlist';
import { cover } from '../utils/Tools';
import { PlaylistDetailParam } from '../pages/PlaylistDetail';
import { Source } from '../model/Source';
import SettingViewModel from '../viewmodel/SettingViewModel';
import TabSettingModel from '../model/adapter/TabSetting';

/**
 * 音乐库视图
 * 用于显示和管理用户的播放列表
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
   * 空状态构建器
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
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 歌单网格构建器
   */
  @Builder
  PlaylistGrid() {
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
      .layoutWeight(1)
      .margin({
        bottom: this.windowProperties.bottomRect,
        top: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? this.windowProperties.topRect + 64 : 100,
        left: 24,
        right: 24,
      })
    }
  }

  build() {
    Column() {
      // 歌单网格
      Scroll(this.scroller) {
        this.PlaylistGrid()

      }.contentEndOffset(this.TabSettingModel.barFloatingStyle?72:0)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .height('100%')
  }
}
