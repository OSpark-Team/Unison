import { Bitrate } from './Types';

/**
 * 播放权限模型
 * 定义歌曲是否可播放以及可用的音质选项
 */
@ObservedV2
export class Privilege {
  /**
   * 是否可播放
   */
  @Trace playable: boolean = false;

  /**
   * 不可播放原因
   * 例如：版权限制、VIP专享等
   */
  @Trace reason?: string = undefined;

  /**
   * 可用码率列表
   * 包含该歌曲所有可用的音质选项
   */
  @Trace bitrates?: Bitrate[] = undefined;

  /**
   * 最高可用码率
   * 用户当前权限下可播放的最高音质
   */
  @Trace maxBitrate?: Bitrate = undefined;
}

