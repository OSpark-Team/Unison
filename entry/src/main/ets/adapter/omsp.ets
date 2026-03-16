import { AxiosInstance, AxiosResponse } from "@ohos/axios";
import { Album } from "../model/adapter/Album";
import { Artist } from "../model/adapter/Artist";
import { Playlist } from "../model/adapter/Playlist";
import { Song } from "../model/adapter/Song";
import { Bitrate } from "../model/adapter/Types";
import { User } from "../model/adapter/User";

export interface BaseResponse<T> {
  code: number;
  message: string;
  data: T;
  timestamp: number;
}

export interface UniKey {
  unikey: string;
}

export interface QRCode {
  qrurl: string;
  qrimg: string;
}

export interface QRCheck {
  status: number; // -1 过期，0 等待扫码，1 等待确认，2 授权登录成功，等待验证
  cookie: string;
}

export interface SearchResponse {
  // 歌曲列表
  songs?: Song[];
  // 歌单列表
  playlists?: Playlist[];
  // 歌手列表
  artists?: Artist[];
  // 专辑列表
  albums?: Album[];
}

// 歌词详情
export interface LyricDetail {
  normal: string;
  translation: string;
  transliteration: string;
  wordforword: string;
}

// 歌词接口响应
export interface LyricResponse {
  id: string | number;
  lyric: LyricDetail;
}

// 喜欢状态接口响应
export interface LikeStatusResponse {
  id: string | number;
  isLiked: boolean;
}

export default class OMSPAdapter {
  // ---- 认证 API ----

  /**
   * 获取二维码密钥
   * @param instance AxiosInstance
   * @returns unikey
   */
  public static async GetQRKey(instance: AxiosInstance) {
    const response: BaseResponse<UniKey> = (
      await instance.get<BaseResponse<UniKey>>("/connect/qr/key")
    ).data;
    return response.data.unikey;
  }

  /**
   * 创建二维码
   * @param instance AxiosInstance
   * @param unikey 二维码密钥
   * @returns QRCode
   */
  public static async CreateQR(instance: AxiosInstance, unikey: string) {
    const response: BaseResponse<QRCode> = (
      await instance.get<BaseResponse<QRCode>>(`/connect/qr/create?key=${unikey}`)
    ).data;
    return response.data;
  }

  /**
   * 检查二维码状态
   * @param instance AxiosInstance
   * @param unikey 二维码密钥
   * @returns QRCheck
   */
  public static async CheckQR(instance: AxiosInstance, unikey: string) {
    const response: BaseResponse<QRCheck> = (
      await instance.get<BaseResponse<QRCheck>>(`/connect/qr/check?key=${unikey}`)
    ).data;
    return response.data;
  }

  /**
   * 获取登录状态
   * @param instance AxiosInstance
   * @returns User
   */
  public static async GetLoginStatus(instance: AxiosInstance) {
    const response: BaseResponse<User> = (await instance.get<BaseResponse<User>>("/connect/status"))
      .data;
    return response.data;
  }

  // ---- 播放列表 API ----

  /**
   * 获取用户播放列表
   * @param instance AxiosInstance
   * @param uid 用户ID
   * @param limit 返回数量上限，默认1000
   * @param offset 偏移量，默认0
   * @returns Playlist[]
   */
  public static async GetUserPlaylists(
    instance: AxiosInstance,
    uid: number | string,
    limit: number = 1000,
    offset: number = 0,
  ) {
    const response: BaseResponse<Playlist[]> = (
      await instance.get<BaseResponse<Playlist[]>>(
        `/playlist/list?uid=${uid}&limit=${limit}&offset=${offset}`,
      )
    ).data;
    // 添加可溯源SourceId
    response.data.forEach((playlist) => {
      playlist.sourceId = instance.defaults.headers.Key as string;
      // 给每一首歌添加sourceId
      playlist.songs?.forEach((song) => {
        song.sourceId = instance.defaults.headers.Key as string;
      });
    });
    return response.data;
  }

  /**
   * 获取推荐播放列表
   * @param instance AxiosInstance
   * @param limit 返回数量上限，默认10
   * @returns Playlist[]
   */
  public static async GetRecommendPlaylists(instance: AxiosInstance, limit: number = 10) {
    const response: BaseResponse<Playlist[]> = (
      await instance.get<BaseResponse<Playlist[]>>(`/playlist/recommend?limit=${limit}`)
    ).data;
    // 添加可溯源SourceId
    response.data.forEach((playlist) => {
      playlist.sourceId = instance.defaults.headers.Key as string;
      // 给每一首歌添加sourceId
      playlist.songs?.forEach((song) => {
        song.sourceId = instance.defaults.headers.Key as string;
      });
    });
    return response.data;
  }

  /**
   * 获取排行榜
   * @param instance AxiosInstance
   * @param limit 返回数量上限，默认10
   * @returns Playlist[]
   */
  public static async GetTopPlaylists(instance: AxiosInstance, limit: number = 10) {
    const response: BaseResponse<Playlist[]> = (
      await instance.get<BaseResponse<Playlist[]>>(`/playlist/toplist?limit=${limit}`)
    ).data;
    // 添加可溯源SourceId
    response.data.forEach((playlist) => {
      playlist.sourceId = instance.defaults.headers.Key as string;
      // 给每一首歌添加sourceId
      playlist.songs?.forEach((song) => {
        song.sourceId = instance.defaults.headers.Key as string;
      });
    });
    return response.data;
  }

  /**
   * 获取播放列表详情
   * @param instance AxiosInstance
   * @param id 播放列表ID
   * @returns Playlist
   */
  public static async GetPlaylistDetail(
    instance: AxiosInstance,
    id: number | string,
    limit: number = 2000,
  ) {
    const response: BaseResponse<Playlist> = (
      await instance.get<BaseResponse<Playlist>>(`/playlist/detail?id=${id}&limit=${limit}`)
    ).data;
    // 添加可溯源SourceId
    response.data.sourceId = instance.defaults.headers.Key as string;
    // 给每一首歌添加sourceId
    response.data.songs?.forEach((song) => {
      song.sourceId = instance.defaults.headers.Key as string;
    });
    return response.data;
  }

  /**
   * 创建播放歌单
   * @param instance AxiosInstance
   * @param name 歌单名称
   * @returns Playlist
   */
  public static async CreatePlaylist(instance: AxiosInstance, name: string) {
    const response: BaseResponse<Playlist> = (
      await instance.post<BaseResponse<Playlist>>(
        `/playlist/create?name=${encodeURIComponent(name)}`,
      )
    ).data;
    // 添加可溯源SourceId
    response.data.sourceId = instance.defaults.headers.Key as string;
    return response.data;
  }

  /**
   * 添加歌曲到歌单
   * @param instance AxiosInstance
   * @param pid 歌单ID
   * @param sid 歌曲ID
   */
  public static async AddSongsToPlaylist(
    instance: AxiosInstance,
    pid: number | string,
    sids: Array<number | string>,
  ) {
    await instance.post(`/playlist/songs?pid=${pid}&sid=${sids.join(",")}`);
  }

  /**
   * 从歌单移除歌曲
   * @param instance AxiosInstance
   * @param pid 歌单ID
   * @param sid 歌曲ID
   */
  public static async RemoveSongsFromPlaylist(
    instance: AxiosInstance,
    pid: number | string,
    sids: Array<number | string>,
  ) {
    await instance.delete(`/playlist/songs?pid=${pid}&sid=${sids.join(",")}`);
  }

  /**
    * 收藏歌单
    * @param instance AxiosInstance
    * @param id 歌单ID
    */
  public static async SubscribePlaylist(instance: AxiosInstance, id: number | string) {
    await instance.post(`/playlist/subscribe?id=${id}`);
  }

  /**
   * 取消收藏歌单
   * @param instance AxiosInstance
   * @param id 歌单ID
   */
  public static async UnsubscribePlaylist(instance: AxiosInstance, id: number | string) {
    await instance.delete(`/playlist/subscribe?id=${id}`);
  }

  // ---- 歌曲 API ----

  /**
   * 获取推荐歌曲
   * @param instance AxiosInstance
   * @param limit 返回数量上限，默认10
   * @returns Song[]
   */
  public static async GetRecommendSongs(instance: AxiosInstance, limit: number = 10) {
    const response: BaseResponse<Song[]> = (
      await instance.get<BaseResponse<Song[]>>(`/song/recommend?limit=${limit}`)
    ).data;
    // 添加可溯源SourceId
    response.data.forEach((song) => {
      song.sourceId = instance.defaults.headers.Key as string;
    });
    return response.data;
  }

  /**
   * 获取歌曲详情
   * @param instance AxiosInstance
   * @param id 歌曲ID
   * @param uid 用户ID
   * @param br 比特率，默认320000
   * @returns Song
   */
  public static async GetSongDetail(
    instance: AxiosInstance,
    id: number | string,
    uid: number | string,
    br: Bitrate = "standard",
  ) {
    const response: BaseResponse<Song> = (
      await instance.get<BaseResponse<Song>>(`/song/detail?id=${id}&uid=${uid}&br=${br}`)
    ).data;
    // 添加可溯源SourceId
    response.data.sourceId = instance.defaults.headers.Key as string;
    return response.data;
  }

  /**
   * 喜欢/取消喜欢歌曲
   * @param instance AxiosInstance
   * @param id 歌曲ID
   * @param like 是否喜欢，默认true
   */
  public static async LikeSong(instance: AxiosInstance, id: number | string, like: boolean = true) {
    await instance.put(`/song/like?id=${id}&like=${like}`);
  }

  /**
   * 获取歌词详情
   * @param instance AxiosInstance
   * @param id 歌曲ID
   */
  public static async GetLyric(
    instance: AxiosInstance,
    id: number | string,
  ): Promise<LyricResponse> {
    const response = (await instance.get<BaseResponse<LyricResponse>>(`/song/lyric?id=${id}`)).data;
    return response.data;
  }

  /**
   * 获取歌曲是否被喜欢（实时状态）
   * @param instance AxiosInstance
   * @param id 歌曲ID
   */
  public static async GetLikeStatus(
    instance: AxiosInstance,
    id: number | string,
  ): Promise<boolean> {
    const response = (await instance.get<BaseResponse<LikeStatusResponse>>(`/song/like?id=${id}`))
      .data;
    return response.data.isLiked;
  }

  // ---- 艺术家 API ----

  /**
   * 获取推荐艺术家
   * @param instance AxiosInstance
   * @param limit 返回数量上限，默认10
   * @returns Artist[]
   */
  public static async GetRecommendArtists(instance: AxiosInstance, limit: number = 10) {
    const response: BaseResponse<Artist[]> = (
      await instance.get<BaseResponse<Artist[]>>(`/artist/recommend?limit=${limit}`)
    ).data;
    // 添加可溯源SourceId
    response.data.forEach((artist) => {
      artist.sourceId = instance.defaults.headers.Key as string;
    });
    return response.data;
  }

  /**
   * 获取艺术家详情
   * @param instance AxiosInstance
   * @param id 艺术家ID
   * @param limit 返回数量上限，默认1000
   * @returns Playlist
   */
  public static async GetArtistDetail(
    instance: AxiosInstance,
    id: number | string,
    limit: number = 1000,
  ) {
    const response: BaseResponse<Playlist> = (
      await instance.get<BaseResponse<Playlist>>(`/artist/detail?id=${id}&limit=${limit}`)
    ).data;
    // 添加可溯源SourceId
    response.data.sourceId = instance.defaults.headers.Key as string;
    // 给每一首歌添加sourceId
    response.data.songs?.forEach((song) => {
      song.sourceId = instance.defaults.headers.Key as string;
    });
    return response.data;
  }

  /**
   * 喜欢/取消喜欢专辑
   * @param instance AxiosInstance
   * @param id 专辑
   * @param like 是否喜欢，默认true
   */
  public static async LikeAlbum(
    instance: AxiosInstance,
    id: number | string,
    like: boolean = true,
  ) {
    await instance.put(`/album/like?id=${id}&like=${like}`);
  }

  /**
   * 获取专辑详情
   * @param instance AxiosInstance
   * @param id 专辑ID
   * @param limit 返回数量上限，默认1000
   * @returns Playlist
   */
  public static async GetAlbumDetail(
    instance: AxiosInstance,
    id: number | string,
    limit: number = 1000,
  ) {
    const response: BaseResponse<Playlist> = (
      await instance.get<BaseResponse<Playlist>>(`/album/detail?id=${id}&limit=${limit}`)
    ).data;
    // 添加可溯源SourceId
    response.data.sourceId = instance.defaults.headers.Key as string;
    // 给每一首歌添加sourceId
    response.data.songs?.forEach((song) => {
      song.sourceId = instance.defaults.headers.Key as string;
    });
    return response.data;
  }

  /**
   * 获取收藏专辑
   * @param instance AxiosInstance
   * @param limit 返回数量上限，默认1000
   * @param offset 偏移量，默认0
   * @returns Album[]
   */
  public static async GetSubscribedAlbums(
    instance: AxiosInstance,
    limit: number = 1000,
    offset: number = 0,
  ) {
    const response: BaseResponse<Album[]> = (
      await instance.get<BaseResponse<Album[]>>(`/album/sublist?limit=${limit}&offset=${offset}`)
    ).data;
    // 添加可溯源SourceId
    response.data.forEach((album) => {
      album.sourceId = instance.defaults.headers.Key as string;
    });

    return response.data;
  }

  // ---- 搜索 API ----

  /**
   * 综合搜索
   * @param instance AxiosInstance
   * @param keywords 搜索关键词
   * @param limit 每种类型返回的数量上限，默认20
   * @returns SearchResponse
   */
  public static async Search(instance: AxiosInstance, keywords: string, limit: number = 20) {
    const response: BaseResponse<SearchResponse> = (
      await instance.get<BaseResponse<SearchResponse>>(
        `/search?keywords=${encodeURIComponent(keywords)}&limit=${limit}`,
      )
    ).data;
    // 添加可溯源SourceId
    const songs = response.data.songs;
    const playlists = response.data.playlists;
    const artists = response.data.artists;
    const albums = response.data.albums;
    if (songs) {
      songs.forEach((song) => {
        song.sourceId = instance.defaults.headers.Key as string;
      });
    }
    if (playlists) {
      playlists.forEach((playlist) => {
        playlist.sourceId = instance.defaults.headers.Key as string;
      });
    }
    if (artists) {
      artists.forEach((artist) => {
        artist.sourceId = instance.defaults.headers.Key as string;
      });
    }
    if (albums) {
      albums.forEach((album) => {
        album.sourceId = instance.defaults.headers.Key as string;
      });
    }
    return response.data;
  }
}
