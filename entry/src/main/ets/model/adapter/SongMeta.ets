import { Lyric } from './Lyric';

/**
 * 歌曲元数据模型
 * 包含播放所需的URL、文件信息、歌词等
 */
@ObservedV2
export class SongMeta {
  /**
   * 歌曲播放URL
   */
  @Trace url?: string = undefined;

  /**
   * 文件MD5值
   * 用于校验文件完整性
   */
  @Trace md5?: string = undefined;

  /**
   * 文件大小（字节）
   */
  @Trace size?: number = undefined;

  /**
   * 比特率（bps）
   * 当前播放URL对应的音质
   */
  @Trace bitrate?: number = undefined;

  /**
   * 是否为收藏歌曲
   */
  @Trace isFavorite?: boolean = undefined;

  /**
   * 歌词信息
   */
  @Trace lyric?: Lyric = undefined;
}

