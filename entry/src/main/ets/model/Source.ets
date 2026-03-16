import SourceRequest from "../utils/SouceRequest";
import { SourceDataSource } from "../data/SourceDataSource";
import { util } from "@kit.ArkTS";
import OMSPAdapter, { LyricResponse, QRCheck, QRCode, SearchResponse } from "../adapter/omsp";
import { User } from "./adapter/User";
import { AppStorageV2, Type } from "@kit.ArkUI";
import { Playlist } from "./adapter/Playlist";
import { Song } from "./adapter/Song";
import { Artist } from "./adapter/Artist";
import Logger from "../utils/Logger";
import { Album } from "./adapter/Album";
import { emitter } from "@kit.BasicServicesKit";
import { EmitEventConstants } from "../common/EmitEventConstants";
import { Bitrate } from "./adapter/Types";

/**
 * 数据源类型
 */
export type SourceType = "omsp" | "navidorme" | string;

/**
 * 数据源
 */
@ObservedV2
export class Source {
  /**
   * 数据源ID
   */
  @Trace id = "";
  /**
   * 数据源名称
   */
  @Trace name = "";
  /**
   * 数据源类型
   * - omsp: omsp数据源
   * - navidorme: navidorme数据源
   */
  @Trace type: SourceType = "omsp";
  /**
   * 数据源地址
   */
  @Trace url = "";
  /**
   * 数据源描述
   */
  @Trace description = "";
  /**
   * 数据源凭证
   * - 可以是Cookie也可能是JWT
   */
  @Trace token = "";
  /**
   * 更新时间（ISO 8601 格式）
   * - 用于分布式数据同步时的冲突解决
   */
  @Trace updated_at = "";
  /**
   * 登录用户
   */
  @Type(User)
  @Trace
  user?: User = undefined;

  /**
   * 初始化构建
   */
  constructor() {
    this.id = util.generateRandomUUID(true);
    // if (!this.url) return;
    // SourceRequest.Create(this.id, this.url, this.token);
    // this.getLoginStatus().then((user)=>{
    //   this.user = user;
    // })
  }

  /**
   * 获取请求实例
   * 这是一个懒加载的 getter，确保每个 Source 对象都有一个独立的、可重置的 Axios实例。
   */
  get request() {
    return SourceRequest.Create(this.id, this.url, this.token);
  }

  // =================== 实例生命周期管理 ===================
  /**
   * 将当前数据源创建到持久化存储中，并初始化网络请求实例。
   */
  async create(): Promise<void> {
    await SourceDataSource.insertSource(this);
    SourceRequest.Create(this.id, this.url, this.token);
    this.getLoginStatus();
  }

  /**
   * 使用新的数据更新当前实例的属性，并持久化到存储。
   * @param source 包含更新字段的 Source 对象
   */
  async update(source: Partial<Source>): Promise<void> {
    let shouldRefreshLoginStatus: boolean = false;

    if (source.id !== undefined) {
      this.id = source.id;
    }
    if (source.name !== undefined) {
      this.name = source.name;
    }
    if (source.type !== undefined) {
      this.type = source.type;
    }
    if (source.url !== undefined) {
      this.url = source.url;
      shouldRefreshLoginStatus = true;
    }
    if (source.description !== undefined) {
      this.description = source.description;
    }
    if (source.token !== undefined) {
      this.token = source.token;
      shouldRefreshLoginStatus = true;
    }
    if (source.updated_at !== undefined) {
      this.updated_at = source.updated_at;
    }
    if (source.user !== undefined) {
      this.user = source.user;
    }

    if (shouldRefreshLoginStatus) {
      await this.getLoginStatus();
    }
    await SourceDataSource.updateSource(this);
  }

  /**
   * 从持久化存储中删除这个数据源。
   */
  async delete(): Promise<void> {
    await SourceDataSource.deleteSource(this.id);
  }

  /**
   * 当 URL 或 Token 变化时，自动重新创建 Axios 实例以应用新配置。
   */
  @Monitor("url", "token")
  reloadAxios() {
    SourceRequest.Reload(this.id, this.url, this.token);
    emitter.emit(
      {
        eventId: EmitEventConstants.SOURCE_URL_TOKEN_UPDATED,
        priority: emitter.EventPriority.HIGH,
      },
      {
        data: {
          id: this.id,
        },
      },
    );
  }

  // =================== 数据源请求操作 (API代理方法) ===================
  /**
   * 获取登陆二维码密钥
   */
  async getQRKey(): Promise<string> {
    return OMSPAdapter.GetQRKey(this.request);
  }

  /**
   * 创建登陆二维码
   */
  async createQR(unikey: string): Promise<QRCode> {
    return OMSPAdapter.CreateQR(this.request, unikey);
  }

  /**
   * 检查二维码状态
   */
  async checkQR(unikey: string): Promise<QRCheck> {
    return OMSPAdapter.CheckQR(this.request, unikey);
  }

  /**
   * 获取当前数据源的登录状态
   */
  async getLoginStatus(): Promise<User> {
    const user = await OMSPAdapter.GetLoginStatus(this.request);
    this.user = user;
    return user;
  }

  // ---- 播放列表 API ----
  /**
   * 获取指定用户的播放列表
   */
  async getUserPlaylists(
    uid: number | string,
    limit: number = 1000,
    offset: number = 0,
  ): Promise<Playlist[]> {
    return OMSPAdapter.GetUserPlaylists(this.request, uid, limit, offset);
  }

  /**
   * 获取推荐播放列表
   */
  async getRecommendPlaylists(limit: number = 10): Promise<Playlist[]> {
    return OMSPAdapter.GetRecommendPlaylists(this.request, limit);
  }

  /**
   * 获取排行榜
   */
  async getTopPlaylists(limit: number = 10): Promise<Playlist[]> {
    return OMSPAdapter.GetTopPlaylists(this.request, limit);
  }

  /**
   * 获取播放列表详情
   */
  async getPlaylistDetail(id: number | string, limit: number = 2000): Promise<Playlist> {
    return OMSPAdapter.GetPlaylistDetail(this.request, id, limit);
  }

  /**
   * 创建歌曲
   */
  async createPlaylist(name: string): Promise<Playlist> {
    return OMSPAdapter.CreatePlaylist(this.request, name);
  }

  /**
   * 添加歌曲到播放列表
   */
  async addSongsToPlaylist(
    playlistId: number | string,
    songIds: (number | string)[],
  ): Promise<void> {
    return OMSPAdapter.AddSongsToPlaylist(this.request, playlistId, songIds);
  }

  /**
   * 从播放列表移除歌曲
   */
  async removeSongsFromPlaylist(
    playlistId: number | string,
    songIds: (number | string)[],
  ): Promise<void> {
    return OMSPAdapter.RemoveSongsFromPlaylist(this.request, playlistId, songIds);
  }

  /**
    * 收藏播放列表
    */
  async subscribePlaylist(id: number | string): Promise<void> {
    return OMSPAdapter.SubscribePlaylist(this.request, id);
  }

  /**
   * 取消收藏播放列表
   */
  async unsubscribePlaylist(id: number | string): Promise<void> {
    return OMSPAdapter.UnsubscribePlaylist(this.request, id);
  }

  // ---- 歌曲 API ----
  /**
   * 获取推荐歌曲
   */
  async getRecommendSongs(limit: number = 10): Promise<Song[]> {
    return OMSPAdapter.GetRecommendSongs(this.request, limit);
  }

  /**
   * 获取歌曲详情
   */
  async getSongDetail(id: number | string, uid: number | string = this.user?.id ?? 0,
    br: Bitrate = "standard"): Promise<Song> {
    return OMSPAdapter.GetSongDetail(this.request, id, uid, br);
  }

  /**
   * 喜欢/取消喜欢歌曲
   */
  async likeSong(id: number | string, like: boolean = true): Promise<void> {
    return OMSPAdapter.LikeSong(this.request, id, like);
  }

  /**
   * 获取歌曲是否被喜欢（实时状态）
   */
  async getLikeStatus(id: number | string): Promise<boolean> {
    return OMSPAdapter.GetLikeStatus(this.request, id);
  }

  /**
   * 获取歌词详情
   */
  async getLyric(id: number | string): Promise<LyricResponse> {
    return OMSPAdapter.GetLyric(this.request, id);
  }

  // ---- 艺术家 API ----
  /**
   * 获取推荐艺术家
   */
  async getRecommendArtists(limit: number = 10): Promise<Artist[]> {
    return OMSPAdapter.GetRecommendArtists(this.request, limit);
  }

  /**
   * 获取艺术家详情
   */
  async getArtistDetail(id: number | string, limit: number = 1000): Promise<Playlist> {
    return OMSPAdapter.GetArtistDetail(this.request, id, limit);
  }

  // ---- 专辑 API ----
  /**
   * 获取艺术家详情
   */
  async getAlbumDetail(id: number | string, limit: number = 1000): Promise<Playlist> {
    return OMSPAdapter.GetAlbumDetail(this.request, id, limit);
  }

  /**
   * 获取收藏专辑
   */
  async getSubscribedAlbums(limit: number = 1000, offset: number = 0): Promise<Album[]> {
    return OMSPAdapter.GetSubscribedAlbums(this.request, limit, offset);
  }

  /**
   * 喜欢/取消喜欢专辑
   */
  async likeAlbum(id: number | string, like: boolean = true): Promise<void> {
    return OMSPAdapter.LikeAlbum(this.request, id, like);
  }

  // ---- 搜索 API ----
  /**
   * 综合搜索
   */
  async search(keywords: string, limit: number = 20): Promise<SearchResponse> {
    return OMSPAdapter.Search(this.request, keywords, limit);
  }
}
