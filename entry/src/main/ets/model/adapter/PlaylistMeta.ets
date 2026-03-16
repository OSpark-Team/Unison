
/**
 * 歌单元数据
 */
@ObservedV2
export class PlaylistMeta {
  /**
   * 是否为收藏歌单
   */
  @Trace subscribed?: boolean = undefined;
}

