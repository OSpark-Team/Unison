import { id } from './Types';

/**
 * 用户模型
 * 包含基本的用户信息，如ID、名称、头像等
 */
@ObservedV2
export class User {
  /**
   * 用户ID
   */
  @Trace id: id = 0;

  /**
   * 用户名称
   */
  @Trace name: string = '';

  /**
   * 用户头像URL
   */
  @Trace avatar?: string = undefined;

  /**
   * 用户简介
   */
  @Trace description?: string = undefined;
}

