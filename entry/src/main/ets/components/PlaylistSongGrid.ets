import { Song } from '../model/adapter/Song';
import { SongListItem } from './SongListItem';
import { cover } from '../utils/Tools';
import { BreakpointConstants } from '../common/BreakpointConstants';
import { WindowProperties } from '../model/WindowProperties';
import { AppStorageV2 } from '@kit.ArkUI';
import PlaylistViewModel from '../viewmodel/PlaylistViewModel';

/**
 * 歌单歌曲网格组件
 * 
 * 功能特性：
 * - 响应式Grid布局，支持三种断点
 * - LG断点：2列网格布局
 * - MD断点：1列网格布局  
 * - SM断点：单列列表布局
 * - 支持歌曲点击、长按操作
 * - 虚拟滚动优化性能
 * - 空状态和加载状态处理
 * 
 * 布局规格：
 * - BREAKPOINT_LG (840vp+): columnsTemplate: '1fr 1fr'
 * - BREAKPOINT_MD (600-840vp): columnsTemplate: '1fr'
 * - BREAKPOINT_SM (320-600vp): List 单列布局
 * 
 * @example
 * ```typescript
 * PlaylistSongGrid({
 *   songs: this.playlist.songs || [],
 *   onSongClick: (song, index) => {
 *     console.log(`播放歌曲: ${song.name}`)
 *   },
 *   onSongLongPress: (song, index) => {
 *     console.log(`长按歌曲: ${song.name}`)
 *   }
 * })
 * ```
 */
@ComponentV2
export struct PlaylistSongGrid {
  /**
   * 歌曲列表数据
   */
  @Param @Require songs: Song[];
  
  /**
   * 歌曲点击回调
   */
  @Param onSongClick?: (song: Song, index: number) => void = undefined;
  
  /**
   * 歌曲长按回调
   */
  @Param onSongLongPress?: (song: Song, index: number) => void = undefined;

  /** 滚动偏移变化回调 */
  @Param onScrollOffsetChange?: (offset: number) => void = undefined;

  /** 底部额外留白，避免浮层遮挡 */
  @Param bottomPadding: number = 0;
  
  /**
   * 是否显示索引号
   */
  @Param showIndex: boolean = true;
  
  /**
   * 是否显示更多操作按钮
   */
  @Param showMoreAction: boolean = false;
  
  /**
   * 窗口属性（用于响应式布局）
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;

  /**
   * 当前播放列表
   */
  @Local playlistViewModel: PlaylistViewModel =
    AppStorageV2.connect(PlaylistViewModel, 'PlaylistViewModel', () => new PlaylistViewModel())!;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    setTimeout(() => {
      this.emitScrollOffset();
    }, 0);
  }

  private emitScrollOffset(): void {
    if (this.onScrollOffsetChange) {
      this.onScrollOffsetChange(this.scroller.currentOffset()?.yOffset);
    }
  }

  /**
   * 判断是否显示分隔线
   */
  private shouldShowDivider(index: number): boolean {
    const totalSongs = this.songs.length;
    if (totalSongs === 0) return false;

    // 根据当前断点判断
    if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
      // LG断点：2列布局，最后2个不显示分隔线
      return index < totalSongs - 2;
    } else {
      // MD/SM断点：1列布局，最后1个不显示分隔线
      return index < totalSongs - 1;
    }
  }

  /**
   * 歌曲列表项 Builder
   */
  @Builder
  buildSongItem(song: Song, index: number) {
    Column() {
      SongListItem({
        coverImage: cover(song.album?.cover, 60),
        songName: song.name || '',
        artistName: song.artists?.map(artist => artist.name).join('/') || '',
        duration: song.duration,
        showDivider: this.shouldShowDivider(index),
        isActive: this.playlistViewModel.currentSong?.id === song.id && this.playlistViewModel.currentSong?.sourceId === song.sourceId,
        onItemClick: () => {
          if (this.onSongClick) {
            this.onSongClick(song, index);
          }
        }
      }) {
        // 操作区域插槽：更多按钮
        if (this.showMoreAction) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onSongLongPress) {
              this.onSongLongPress(song, index);
            }
          })
        }
      }
    }.gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          if (this.onSongLongPress) {
            this.onSongLongPress(song, index);
          }
        })
    )
  }
  
  /**
   * 大屏Grid布局 Builder (LG断点)
   */
  @Builder
  buildLargeScreenGrid() {
    Grid(this.scroller) {
      Repeat<Song>(this.songs)
        .each((song) => {
          GridItem() {
            this.buildSongItem(song.item, song.index)
          }
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        })
        .key((item: Song) => `song-${item.sourceId}-${item.id}`)
    }
    .columnsTemplate('1fr 1fr')
    .rowsGap(4)
    .columnsGap(8)
    .width('100%')
    .height('100%')
    .padding({ bottom: this.bottomPadding })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll(() => {
      this.emitScrollOffset();
    })
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.PARENT_FIRST
    })
  }
  
  /**
   * 中屏Grid布局 Builder (MD断点)
   */
  @Builder
  buildMediumScreenGrid() {
    Grid(this.scroller) {
      Repeat<Song>(this.songs)
        .each((song) => {
          GridItem() {
            this.buildSongItem(song.item, song.index)
          }
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        })
        .key((song) => `song-${song.id}`)
    }
    .columnsTemplate('1fr')
    .rowsGap(4)
    .width('100%')
    .height('100%')
    .padding({ bottom: this.bottomPadding })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll(() => {
      this.emitScrollOffset();
    })
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.PARENT_FIRST
    })
  }
  
  /**
   * 小屏List布局 Builder (SM断点)
   */
  @Builder
  buildSmallScreenList() {
    List({ space: 4, scroller: this.scroller }) {
      Repeat<Song>(this.songs)
        .each((song) => {
          ListItem() {
            this.buildSongItem(song.item, song.index)
          }
          .padding({ left: 4, right: 4 })
        })
        .key((song) => `song-${song.id}`)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.bottomPadding })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll(() => {
      this.emitScrollOffset();
    })
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.PARENT_FIRST
    })
  }
  
  /**
   * 空状态 Builder
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
      
      Text($r('app.string.playlist_empty'))
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(40)
  }
  
  /**
   * 加载状态 Builder
   */
  @Builder
  buildLoadingState() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.accent'))
      
      Text($r('app.string.playlist_loading'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(40)
  }
  
  /**
   * 根据断点选择布局
   */
  @Builder
  buildResponsiveLayout() {
    if (this.songs.length === 0) {
      this.buildEmptyState()
    } else {
      // 根据当前断点选择合适的布局
      if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
        this.buildLargeScreenGrid()
      } else if (this.windowProperties.currentBreakpoint === BreakpointConstants.BREAKPOINT_MD) {
        this.buildMediumScreenGrid()
      } else {
        this.buildSmallScreenList()
      }
    }
  }
  
  build() {
    Column() {
      this.buildResponsiveLayout()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
  }
}
