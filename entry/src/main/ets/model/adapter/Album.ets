import { id } from './Types';
import { Artist } from './Artist';
import { Type } from '@kit.ArkUI';

/**
 * 专辑模型
 * 包含专辑的基本信息及所属艺术家
 */
@ObservedV2
export class Album {
  /**
   * 专辑ID
   */
  @Trace id: id = 0;

  /**
   * 专辑名称
   */
  @Trace name: string = '';

  /**
   * 专辑封面URL
   */
  @Trace cover?: string = undefined;

  /**
   * 艺术家列表
   */
  @Type(Artist)
  @Trace artists?: Artist[] = undefined;

  /**
   * 歌曲数量
   */
  @Trace size?: number = undefined;

  /**
   * 可溯源SourceId
   * 服务端响应无此ID，用在客户端多数据源溯源
   */
  @Trace sourceId: string = '';
}

