import { PersistenceV2 } from '@kit.ArkUI';
import { Song } from '../model/adapter/Song';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { cover } from '../utils/Tools';
import { SongListItem } from './SongListItem';

@ComponentV2
export struct NowPlayingQueueSheet {
  /** 系统设置 ViewModel（用于统一 UI 参数） */
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** 播放队列 */
  @Param @Require songs: Song[];

  /** 当前正在播放的歌曲（用于高亮） */
  @Param activeSong?: Song = undefined;

  /** 打开后滚动到的索引（例如 currentIndex） */
  @Param scrollToIndex: number = -1;

  /** 点击歌曲回调 */
  @Param onSongClick?: (song: Song, index: number) => void = undefined;

  /** 关闭面板回调 */
  @Param onClose?: () => void = undefined;

  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const idx = this.scrollToIndex;
    if (idx >= 0 && idx < this.songs.length) {
      // 等待首帧布局完成后再滚动，避免 scrollToIndex 无效
      setTimeout(() => {
        this.listScroller.scrollToIndex(idx);
      }, 0);
    }
  }

  private isSongActive(song: Song): boolean {
    if (!this.activeSong) {
      return false;
    }
    return this.activeSong.id === song.id && this.activeSong.sourceId === song.sourceId;
  }

  private shouldShowDivider(index: number): boolean {
    return index < this.songs.length - 1;
  }

  @Builder
  private buildHeader() {
    Row() {
      Text($r('app.string.now_playing_queue_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Blank()

      Button($r('app.string.close'))
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary'))
        .borderRadius(this.settingModel.radiusItem)
        .onClick(() => {
          if (this.onClose) {
            this.onClose();
          }
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.background_card'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildEmptyState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])

      Text($r('app.string.now_playing_queue_empty'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  private buildSongList() {
    List({ space: 4, scroller: this.listScroller }) {
      Repeat<Song>(this.songs)
        .each((song) => {
          ListItem() {
            SongListItem({
              coverImage: cover(song.item.album?.cover, 60),
              songName: song.item.name || '',
              artistName: song.item.artists?.map((artist) => artist.name).join('/') || '',
              duration: song.item.duration,
              showDivider: this.shouldShowDivider(song.index),
              isActive: this.isSongActive(song.item),
              onItemClick: () => {
                if (this.onSongClick) {
                  this.onSongClick(song.item, song.index);
                }
              }
            })
          }
          .padding({ left: 4, right: 4 })
        })
        .key((item: Song) => `queue-${item.sourceId}-${item.id}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 220, curve: Curve.EaseOut })
    )
  }

  build() {
    Column({ space: 0 }) {
      this.buildHeader()

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))

      if (this.songs.length === 0) {
        this.buildEmptyState()
      } else {
        this.buildSongList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius(this.settingModel.radiusCardLarge)
    .clip(true)
  }
}
