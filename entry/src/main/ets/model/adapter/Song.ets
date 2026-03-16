import { id } from './Types';
import { Artist } from './Artist';
import { Album } from './Album';
import { Privilege } from './Privilege';
import { SongMeta } from './SongMeta';
import { Type } from '@ohos.arkui.StateManagement';

/**
 * 歌曲模型
 * 包含歌曲的完整信息，包括基本信息、所属专辑、艺术家、播放权限等
 */
@ObservedV2
export class Song {
  /**
   * 歌曲ID
   */
  @Trace id: id = 0;

  /**
   * 歌曲名称
   */
  @Trace name?: string = undefined;

  /**
   * 别名或翻译名
   * 例如：日语歌曲的中文译名
   */
  @Trace tns?: string[] = undefined;

  /**
   * 歌手列表
   * 一首歌可能有多个演唱者
   */
  @Type(Artist)
  @Trace artists?: Artist[] = undefined;

  /**
   * 专辑信息
   */
  @Type(Album)
  @Trace album?: Album = undefined;

  /**
   * 时长（毫秒）
   */
  @Trace duration?: number = undefined;

  /**
   * 播放权限
   * 定义该歌曲是否可播放及可用音质
   */
  @Type(Privilege)
  @Trace privilege?: Privilege = undefined;

  /**
   * 元数据
   * 包含播放URL、歌词等额外信息
   */
  @Trace meta?: SongMeta = undefined;

  /**
   * 可溯源SourceId
   * 服务端响应无此ID，用在客户端多数据源溯源
   */
  @Trace sourceId: string = '';
}

