import { id, PlaylistType } from './Types';
import { User } from './User';
import { Song } from './Song';
import { Type } from '@kit.ArkUI';
import { PlaylistMeta } from './PlaylistMeta';

/**
 * 播放列表模型
 * 包含播放列表的基本信息以及包含的歌曲列表
 */
@ObservedV2
export class Playlist {
  /**
   * 播放列表ID
   */
  @Trace id: id = 0;

  /**
   * 播放列表名称
   */
  @Trace name?: string = undefined;

  /**
   * 封面图片URL
   */
  @Trace cover?: string = undefined;

  /**
   * 歌曲数量
   */
  @Trace size?: number = undefined;

  /**
   * 创建者信息
   */
  @Type(User)
  @Trace creator?: User = undefined;

  /**
   * 歌曲列表
   */
  @Type(Song)
  @Trace songs?: Song[] = undefined;

  /**
   * 播放列表类型
   * - normal: 普通播放列表
   * - album: 专辑
   * - dj: 电台节目
   * - artist: 艺术家热门歌曲
   */
  @Trace type?: PlaylistType = undefined;

  /**
   * 描述
   */
  @Trace description?: string = undefined;

  /**
   * 元数据
   * 用于存储额外信息，如是否收藏等
   */
  @Type(PlaylistMeta)
  @Trace meta?: PlaylistMeta = undefined;

  /**
   * 可溯源SourceId
   * 服务端响应无此ID，用在客户端多数据源溯源
   */
  @Trace sourceId: string = '';

  static Type(type: PlaylistType): Playlist {
    const playlist = new Playlist();
    playlist.type = type;

    return playlist
  }
}

