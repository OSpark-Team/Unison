import { id } from './Types';

/**
 * 艺术家模型
 * 包含艺术家的基本信息
 */
@ObservedV2
export class Artist {
  /**
   * 艺术家ID
   */
  @Trace id: id = 0;

  /**
   * 艺术家名称
   */
  @Trace name: string = '';

  /**
   * 艺术家头像URL
   */
  @Trace avatar?: string = undefined;

  /**
   * 可溯源SourceId
   * 服务端响应无此ID，用在客户端多数据源溯源
   */
  @Trace sourceId: string = '';
}

