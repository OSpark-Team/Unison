import { Playlist } from "../model/adapter/Playlist";
import { Bitrate } from "../model/adapter/Types";
import { Source } from "../model/Source";
import { Type } from "@kit.ArkUI";
import { Song } from "../model/adapter/Song";
import { Artist } from "../model/adapter/Artist";

/**
 * 当前数据源 ViewModel
 */
@ObservedV2
export default class CurrentSourceViewModel {
  /** 当前数据源 */
  @Type(Source)
  @Trace source: Source | null = null;

  /** 用户歌单 */
  @Type(Playlist)
  @Trace userPlaylists: Playlist[] = [];

  /** 新歌速递 */
  @Type(Song)
  @Trace newSongs: Song[] = [];

  /** 推荐歌单 */
  @Type(Playlist)
  @Trace recommendPlaylists: Playlist[] = [];

  /** 推荐艺人 */
  @Type(Artist)
  @Trace recommendArtists: Artist[] = [];

  /** 排行榜 */
  @Type(Playlist)
  @Trace rankPlaylists: Playlist[] = [];

  /** 常规歌单第一首歌曲 */
  @Type(Song)
  @Trace firstSongOfUserPlaylist?: Song = undefined;

  /** 推荐艺人第一首歌曲 */
  @Type(Song)
  @Trace firstSongOfRecommendArtist?: Song = undefined;

  /** 榜单推荐第一首歌曲 */
  @Type(Song)
  @Trace firstSongOfRank?: Song = undefined;

  /** ForU Items */
  @Type(Playlist)
  @Trace forUItems: Playlist[] = [];

  @Type(Playlist)
  @Trace firstUserPlaylist?: Playlist = undefined;

  @Type(Artist)
  @Trace firstRecommendArtist?: Artist = undefined;

  @Type(Playlist)
  @Trace firstRankPlaylist?: Playlist = undefined;

  /** 布局枚举 */
  @Trace items: string[] = ["ForU", "UserPlaylist-First", "HotSong-All", "RecommendPlaylist-All", "RecommendArtist-First",
    "RecommendArtist-All", "Rank-First", "Rank-All"];


  async loadAll() {
    if (!this.source) return;

    this.items = ["ForU", "UserPlaylist-First", "HotSong-All", "RecommendPlaylist-All", "RecommendArtist-First",
      "RecommendArtist-All", "Rank-First", "Rank-All"];

    const initialPromises: Promise<void>[] = [];

    initialPromises.push(
      this.source.getUserPlaylists(this.source.user?.id ?? 0)
        .then(data => {
          this.userPlaylists = data;
          this.forUItems = this.userPlaylists.filter((item) => item.id.toString().startsWith("key_"));
          if (this.userPlaylists.length === 0) {
            this.items = this.items.filter((item) => item !== "UserPlaylist-First" && item !== "ForU");
          }
          if (this.forUItems.length === 0) {
            this.items = this.items.filter((item) => item !== "ForU");
          }
        })
    );

    initialPromises.push(
      this.source.getRecommendSongs()
        .then(data => {
          this.newSongs = data;
          if (this.newSongs.length === 0) {
            this.items = this.items.filter((item) => item !== "HotSong-All");
          }
        })
    );

    initialPromises.push(
      this.source.getRecommendPlaylists(30)
        .then(data => {
          this.recommendPlaylists = data;
          if (this.recommendPlaylists.length === 0) {
            this.items = this.items.filter((item) => item !== "RecommendPlaylist-All");
          }
        })
    );

    initialPromises.push(
      this.source.getRecommendArtists(50)
        .then(data => {
          this.recommendArtists = data;
          if (this.recommendArtists.length === 0) {
            this.items = this.items.filter((item) => item !== "RecommendArtist-First" && item !== "RecommendArtist-All");
          }
        })
    );

    initialPromises.push(
      this.source.getTopPlaylists(20)
        .then(data => {
          this.rankPlaylists = data;
          if (this.rankPlaylists.length === 0) {
            this.items = this.items.filter((item) => item !== "Rank-First" && item !== "Rank-All");
          }
        })
    );

    await Promise.allSettled(initialPromises);

    const detailPromises: Promise<void>[] = [];

    this.firstUserPlaylist = this.userPlaylists.filter((e) => !(e.id.toString().startsWith("key_")))[0];
    if (this.firstUserPlaylist) {
      detailPromises.push(
        this.source.getPlaylistDetail(this.firstUserPlaylist.id)
          .then(detail => {
            this.firstSongOfUserPlaylist = detail.songs?.[0] ?? undefined;
          })
      );
    }

    this.firstRecommendArtist = this.recommendArtists[0];
    if (this.firstRecommendArtist) {
      detailPromises.push(
        this.source.getArtistDetail(this.firstRecommendArtist.id)
          .then(detail => {
            this.firstSongOfRecommendArtist = detail.songs?.[0] ?? undefined;
          })
      );
    }

    this.firstRankPlaylist = this.rankPlaylists[0];
    if (this.firstRankPlaylist) {
      detailPromises.push(
        this.source.getPlaylistDetail(this.firstRankPlaylist.id)
          .then(detail => {
            this.firstSongOfRank = detail.songs?.[0] ?? undefined;
          })
      );
    }

    await Promise.allSettled(detailPromises);
  }


  /**
   * 单独刷新用户歌单
   * 同步更新 forUItems / firstUserPlaylist / firstSongOfUserPlaylist
   */
  async refreshUserPlaylists(): Promise<void> {
    if (!this.source) return;
    const data = await this.source.getUserPlaylists(this.source.user?.id ?? 0);
    this.userPlaylists = data;
    this.forUItems = data.filter(item => item.id.toString().startsWith("key_"));
    this.firstUserPlaylist = data.filter(e => !e.id.toString().startsWith("key_"))[0];
    if (this.firstUserPlaylist) {
      const detail = await this.source.getPlaylistDetail(this.firstUserPlaylist.id);
      this.firstSongOfUserPlaylist = detail.songs?.[0] ?? undefined;
    }
  }

  /**
   * 单独刷新推荐歌曲（新歌速递）
   */
  async refreshRecommendSongs(): Promise<void> {
    if (!this.source) return;
    this.newSongs = await this.source.getRecommendSongs();
  }

  /**
   * 单独刷新推荐歌单
   */
  async refreshRecommendPlaylists(): Promise<void> {
    if (!this.source) return;
    this.recommendPlaylists = await this.source.getRecommendPlaylists(30);
  }

  /**
   * 单独刷新推荐艺人
   * 同步更新 firstRecommendArtist / firstSongOfRecommendArtist
   */
  async refreshRecommendArtists(): Promise<void> {
    if (!this.source) return;
    const data = await this.source.getRecommendArtists(50);
    this.recommendArtists = data;
    this.firstRecommendArtist = data[0];
    if (this.firstRecommendArtist) {
      const detail = await this.source.getArtistDetail(this.firstRecommendArtist.id);
      this.firstSongOfRecommendArtist = detail.songs?.[0] ?? undefined;
    }
  }

  /**
   * 单独刷新排行榜
   * 同步更新 firstRankPlaylist / firstSongOfRank
   */
  async refreshRankPlaylists(): Promise<void> {
    if (!this.source) return;
    const data = await this.source.getTopPlaylists(20);
    this.rankPlaylists = data;
    this.firstRankPlaylist = data[0];
    if (this.firstRankPlaylist) {
      const detail = await this.source.getPlaylistDetail(this.firstRankPlaylist.id);
      this.firstSongOfRank = detail.songs?.[0] ?? undefined;
    }
  }

  // ─────────────────────────────────────────────
  // 数据源切换监听
  // ─────────────────────────────────────────────

  @Monitor("source")
  async loadAllWhenSourceChanged() {
    if (!this.source) {
      this.userPlaylists = [];
      this.newSongs = [];
      this.recommendPlaylists = [];
      this.recommendArtists = [];
      this.rankPlaylists = [];
      this.forUItems = [];
      this.firstUserPlaylist = undefined;
      this.firstRecommendArtist = undefined;
      this.firstRankPlaylist = undefined;
      this.firstSongOfUserPlaylist = undefined;
      this.firstSongOfRecommendArtist = undefined;
      this.firstSongOfRank = undefined;
      this.items = [];
      return;
    }
    await this.loadAll();
  }
}
