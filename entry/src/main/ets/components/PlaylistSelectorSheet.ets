import { PersistenceV2 } from '@kit.ArkUI';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { Playlist } from '../model/adapter/Playlist';
import { PlaylistListItem } from './PlaylistListItem';
import { cover } from '../utils/Tools';

/**
 * 歌单选择面板（bindSheet 内容）
 * - 顶部「新建歌单」行：点击切换为输入态，回车/点创建触发 onCreateNew
 * - 下方：某数据源的用户歌单列表，点击触发 onSelect
 * 用于「添加到歌单」：调用方负责按歌曲 sourceId 加载候选歌单并执行实际的 addSongsToPlaylist。
 */
@ComponentV2
export struct PlaylistSelectorSheet {
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;

  /** 面板标题（默认「添加到歌单」；库页歌单管理可传「新建歌单」） */
  @Param title: ResourceStr = $r('app.string.playlist_add_to');
  /** 候选歌单（某数据源的用户歌单） */
  @Param @Require playlists: Playlist[];
  /** 是否加载中 */
  @Param isLoading: boolean = false;
  /** 选中某歌单回调 */
  @Param onSelect?: (playlist: Playlist) => void = undefined;
  /** 新建歌单回调（传入名称） */
  @Param onCreateNew?: (name: string) => void = undefined;
  /** 关闭回调 */
  @Param onClose?: () => void = undefined;

  /** 是否处于「新建输入」态 */
  @Local creating: boolean = false;
  /** 新建歌单名 */
  @Local newName: string = '';

  @Builder
  buildHeader() {
    Row() {
      Text(this.title)
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
  buildCreateRow() {
    if (this.creating) {
      Row({ space: 8 }) {
        TextInput({ placeholder: $r('app.string.playlist_name_hint'), text: this.newName })
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.background_secondary'))
          .borderRadius(this.settingModel.radiusItem)
          .onChange((v: string) => {
            this.newName = v;
          })
          .onSubmit(() => this.confirmCreate())
        // 与应用主按钮统一（参照 AudioEffectsSheet 保存按钮）：primary_color 底 + 白字 + 圆角12
        Button($r('app.string.common_create'))
          .type(ButtonType.Normal)
          .height(40)
          .padding({ left: 18, right: 18 })
          .backgroundColor($r('app.color.primary_color'))
          .fontColor(Color.White)
          .borderRadius(12)
          .enabled(this.newName.trim().length > 0)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
          .onClick(() => this.confirmCreate())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
    } else {
      // 与歌单列表项一致：左侧 48 圆角图标容器 + 文字（不用突兀的蓝字大加号）
      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(48)
        .height(48)
        .borderRadius(this.settingModel.radiusCover)
        .backgroundColor($r('app.color.background_secondary'))
        Text($r('app.string.playlist_create_new'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(64)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.settingModel.scalePress })
      .onClick(() => {
        this.creating = true;
      })
    }
  }

  private confirmCreate(): void {
    const name = this.newName.trim();
    if (name.length === 0) {
      return;
    }
    if (this.onCreateNew) {
      this.onCreateNew(name);
    }
    this.newName = '';
    this.creating = false;
  }

  build() {
    Column() {
      this.buildHeader()
      Divider().strokeWidth(1).color($r('app.color.divider'))
      this.buildCreateRow()
      Divider().strokeWidth(0.5).color($r('app.color.divider'))

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color($r('app.color.accent'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.playlists.length === 0) {
        Column() {
          Text($r('app.string.playlist_selector_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.playlists, (pl: Playlist) => {
            ListItem() {
              PlaylistListItem({
                coverImage: cover(pl.cover, 100),
                playlistName: pl.name ?? '',
                trackCount: pl.size ?? 0,
                onItemClick: () => {
                  if (this.onSelect) {
                    this.onSelect(pl);
                  }
                }
              })
            }
          }, (pl: Playlist, idx: number): string => `sel-${pl.sourceId}-${pl.id}-${idx}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
    .borderRadius(this.settingModel.radiusCardLarge)
    .clip(true)
  }
}
