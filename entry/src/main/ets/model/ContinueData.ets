import { Playlist } from "./adapter/Playlist";
import { Song } from "./adapter/Song";
import { id } from "./adapter/Types";

/**
 * 应用接续数据
 */
export class ContinueData {
  /**
   * 行为
   * - playing: 播放页
   * - detail: 歌单详情页
   */
  page: "playing" | "detail" = "detail";

  /**
   * 歌曲/歌单ID
   */
  id: id = "";

  /**
   * 数据源ID
   */
  sourceId: string = "";

  /**
   * 歌单
   */
  playlist?: Playlist = undefined;

  /**
   * 歌曲
   */
  song?: Song = undefined;
}