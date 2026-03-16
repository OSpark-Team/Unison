import { Type } from '@kit.ArkUI';
import { Song } from '../model/adapter/Song';
import { Album } from '../model/adapter/Album';
import { Artist } from '../model/adapter/Artist';
import { id } from '../model/adapter/Types';
import { avSession } from '@kit.AVSessionKit';
import { emitter } from '@kit.BasicServicesKit';
import { EmitEventConstants } from '../common/EmitEventConstants';
import Logger from '../utils/Logger';
import { shuffle } from '../utils/Tools';
import { PreferencesUtil } from '../utils/PreferencesUtil';

class CachedArtist {
  id: id = 0;
  name: string = '';
  avatar?: string = undefined;
  sourceId: string = '';
}

class CachedAlbum {
  id: id = 0;
  name: string = '';
  cover?: string = undefined;
  artists?: CachedArtist[] = undefined;
  size?: number = undefined;
  sourceId: string = '';
}

class CachedSong {
  id: id = 0;
  name?: string = undefined;
  tns?: string[] = undefined;
  artists?: CachedArtist[] = undefined;
  album?: CachedAlbum = undefined;
  duration?: number = undefined;
  sourceId: string = '';
}

class PlaybackCacheSnapshot {
  version: number = 1;
  playlist: CachedSong[] = [];
  originalPlaylist: CachedSong[] = [];
  currentSong?: CachedSong = undefined;
  currentIndex: number = -1;
  mode: number = avSession.LoopMode.LOOP_MODE_LIST;
}

/**
 * 播放列表 ViewModel
 * 核心思路：playlist 始终作为 UI 显示的最终数据源。
 * 原始顺序保存在私有变量 _originalPlaylist 中。
 */
@ObservedV2
export default class PlaylistViewModel {
  private static readonly TAG: string = 'PlaylistViewModel';
  private static readonly PLAYBACK_CACHE_KEY: string = 'playlist_view_model_playback_cache_v1';
  private static readonly PLAYBACK_CACHE_VERSION: number = 1;

  /**
   * 当前播放索引（对应当前 playlist 中的位置）
   */
  @Trace currentIndex: number = -1;
  /**
   * 响应式播放列表（UI 直接引用此字段）
   */
  @Type(Song)
  @Trace
  playlist: Song[] = [];
  /**
   * 当前正在播放的歌曲
   */
  @Trace currentSong?: Song = undefined;
  /**
   * 存储原始顺序的列表（非随机模式下的备份）
   */
  private _originalPlaylist: Song[] = [];
  /**
   * 当前播放模式
   */
  @Trace mode: avSession.LoopMode = avSession.LoopMode.LOOP_MODE_LIST;

  // --- 防抖定时器 ID ---
  private emitTimerId: number = -1;
  private isRestoringCache: boolean = false;
  private hasRestoredCache: boolean = false;

  constructor() {
    this.restorePlaybackCacheIfReady();
  }

  /**
   * 设置播放模式并触发列表重组
   * @param mode 可选模式
   */
  setMode(mode?: avSession.LoopMode): avSession.LoopMode {
    this.restorePlaybackCacheIfReady();

    if (mode !== undefined) {
      switch (mode) {
        case avSession.LoopMode.LOOP_MODE_LIST:
          this.mode = avSession.LoopMode.LOOP_MODE_SINGLE;
          break;
        case avSession.LoopMode.LOOP_MODE_SINGLE:
          this.mode = avSession.LoopMode.LOOP_MODE_SHUFFLE;
          break;
        case avSession.LoopMode.LOOP_MODE_SHUFFLE:
          this.mode = avSession.LoopMode.LOOP_MODE_LIST;
          break;
        default:
          this.mode = avSession.LoopMode.LOOP_MODE_LIST;
          break;
      }
    } else {
      // 循环切换逻辑
      const modes = [
        avSession.LoopMode.LOOP_MODE_LIST,
        avSession.LoopMode.LOOP_MODE_SINGLE,
        avSession.LoopMode.LOOP_MODE_SHUFFLE,
      ];
      let nextIndex = (modes.indexOf(this.mode) + 1) % modes.length;
      this.mode = modes[nextIndex];
    }

    return this.mode;
  }

  /**
   * 监听模式变化，动态调整 playlist 的内容顺序
   */
  @Monitor("mode")
  onModeChanged(): void {
    if (this.isRestoringCache) {
      return;
    }

    Logger.info(PlaylistViewModel.TAG, 'Mode changed: ' + this.mode);
    // 记录当前正在播放的那首歌，防止乱序后找不到
    const currentSong = this.playlist[this.currentIndex];

    if (this.mode === avSession.LoopMode.LOOP_MODE_SHUFFLE) {
      // 进入随机模式：基于当前 playlist 生成随机列表
      this.playlist = shuffle([...this.playlist]);
    } else {
      // 退出随机模式：还原回原始顺序
      this.playlist = [...this._originalPlaylist];
    }

    // 重新计算当前歌曲在新列表中的索引，保持播放状态连续
    if (currentSong) {
      this.currentIndex = this.playlist.findIndex((s) => s.id === currentSong.id);
    }

    this.syncCurrentSongWithIndex();

    this.savePlaybackCache();
  }

  /**
   * 插入歌曲（支持批量、去重、定位）
   * @param songs 要插入的歌曲列表
   * @param index 插入位置，默认 0 (最前面)
   */
  insertSongs(songs: Song[], index: number = 0): void {
    this.restorePlaybackCacheIfReady();

    if (!songs || songs.length === 0) {
      return;
    }

    // 获取当前正在播放的歌曲，以便后续修正索引
    const currentSong = this.playlist[this.currentIndex];

    // 处理原始备份列表
    this._processListInsertion(this._originalPlaylist, songs, index);

    // 处理当前显示的列表
    this._processListInsertion(this.playlist, songs, index);

    // 重新修正 currentIndex
    if (currentSong) {
      this.currentIndex = this.playlist.findIndex((s) => s.id === currentSong.id);
    } else if (this.playlist.length > 0 && this.currentIndex === -1) {
      // 如果之前是空的，现在有歌了，默认指向第一首
      this.currentIndex = 0;
    }

    this.syncCurrentSongWithIndex();

    this.savePlaybackCache();
  }

  /**
   * 内部方法：处理列表的插入与去重移动逻辑
   */
  private _processListInsertion(targetList: Song[], newSongs: Song[], insertAt: number): void {
    // 倒序插入以保持传入数组的原始相对顺序
    const reversedNewSongs = [...newSongs].reverse();

    reversedNewSongs.forEach((song) => {
      const existingIndex = targetList.findIndex((s) => s.id === song.id);

      if (existingIndex !== -1) {
        const removedSongs = targetList.splice(existingIndex, 1);
        const movedSong = removedSongs[0];

        // 如果移除的位置在插入位置之前，插入位置需要前移
        const adjustedInsertAt = existingIndex < insertAt ? insertAt - 1 : insertAt;
        targetList.splice(Math.max(0, adjustedInsertAt), 0, movedSong);
      } else {
        // 不存在则直接插入
        targetList.splice(Math.max(0, insertAt), 0, song);
      }
    });
  }

  /**
   * 获取下一首
   */
  public nextSong(force: boolean = false): Song | undefined {
    this.restorePlaybackCacheIfReady();

    if (this.playlist.length === 0) {
      return undefined;
    }
    // 如果是单曲循环模式，下一首就是当前这首
    if (this.mode === avSession.LoopMode.LOOP_MODE_SINGLE && !force) {
      return this.currentSong;
    }
    let nextIdx = this.currentIndex + 1;
    if (nextIdx >= this.playlist.length) {
      nextIdx = 0; // 列表循环
    }
    return this.playlist[nextIdx];
  }

  /**
   * 获取上一首
   */
  public prevSong(force: boolean = false): Song | undefined {
    this.restorePlaybackCacheIfReady();

    if (this.playlist.length === 0) {
      return undefined;
    }
    // 如果是单曲循环模式，上一首就是这首
    if (this.mode === avSession.LoopMode.LOOP_MODE_SINGLE && !force) {
      return this.currentSong;
    }
    let prevIdx = this.currentIndex - 1;
    if (prevIdx < 0) {
      prevIdx = this.playlist.length - 1;
    }
    return this.playlist[prevIdx];
  }

  /**
   * 抽取 emit 逻辑 (已加入防抖)
   */
  private emitCurrentSongUpdated(song: Song): void {
    // 如果之前有定时器，清除它
    if (this.emitTimerId !== -1) {
      clearTimeout(this.emitTimerId);
    }

    // 设置新的防抖定时器，延迟 350 毫秒执行 (可根据需要调整时间)
    this.emitTimerId = setTimeout(() => {
      Logger.info(PlaylistViewModel.TAG, 'Current song actually changed (Debounced): ' + (song.name ?? ''));
      emitter.emit(
        { eventId: EmitEventConstants.CURRENT_SONG_UPDATED, priority: emitter.EventPriority.IMMEDIATE },
        {
          data: {
            songId: song.id,
            sourceId: song.sourceId,
          }
        }
      );
      this.emitTimerId = -1; // 执行完毕后重置 ID
    }, 350);
  }

  /**
   * 播放指定歌曲
   * @param forcePlay 为 true 时即使是同一首歌也强制重新触发播放事件
   */
  playSong(song: Song, forcePlay: boolean = false): void {
    this.restorePlaybackCacheIfReady();

    const idx = this.playlist.findIndex((s) => s.id === song.id && s.sourceId === song.sourceId);
    if (idx === -1) {
      return;
    }

    const target = this.playlist[idx];
    const isSameSong = this.currentSong?.id === target.id && this.currentSong?.sourceId === target.sourceId;
    this.currentIndex = idx;
    this.syncCurrentSongWithIndex();

    if (forcePlay && isSameSong) {
      // 歌曲未变，@Monitor 不会触发，手动 emit
      this.emitCurrentSongUpdated(target);
      this.savePlaybackCache();
      return;
    }

    if (isSameSong) {
      this.savePlaybackCache();
    }
  }

  /**
   * 播放指定索引的歌曲
   */
  playSongByIndex(index: number, forcePlay: boolean = false): void {
    this.restorePlaybackCacheIfReady();

    if (index < 0 || index >= this.playlist.length) {
      return;
    }

    const target = this.playlist[index];
    const isSameSong = this.currentSong?.id === target.id && this.currentSong?.sourceId === target.sourceId;
    this.currentIndex = index;
    this.syncCurrentSongWithIndex();

    if (forcePlay && isSameSong) {
      this.emitCurrentSongUpdated(target);
      this.savePlaybackCache();
      return;
    }

    if (isSameSong) {
      this.savePlaybackCache();
    }
  }

  @Monitor("currentIndex")
  onCurrentIndexChanged(): void {
    this.syncCurrentSongWithIndex();
  }

  /**
   * 监听 currentSong 变化，触发事件
   */
  @Monitor("currentSong")
  onCurrentSongChanged(): void {
    if (this.currentSong) {
      if (this.isRestoringCache) {
        return;
      }

      this.emitCurrentSongUpdated(this.currentSong);
      this.savePlaybackCache();
      return;
    }

    if (!this.isRestoringCache) {
      this.savePlaybackCache();
    }
  }

  private restorePlaybackCacheIfReady(): void {
    if (this.hasRestoredCache || !PreferencesUtil.isInitialized()) {
      return;
    }

    this.hasRestoredCache = true;

    if (!PreferencesUtil.hasKey(PlaylistViewModel.PLAYBACK_CACHE_KEY)) {
      return;
    }

    const cacheContent = PreferencesUtil.get<string>(PlaylistViewModel.PLAYBACK_CACHE_KEY, '');
    if (!cacheContent) {
      return;
    }

    const snapshot = this.parsePlaybackCache(cacheContent);
    if (!snapshot) {
      return;
    }

    let restoredPlaylist = this.deserializeSongList(snapshot.playlist);
    let restoredOriginalPlaylist = this.deserializeSongList(snapshot.originalPlaylist);
    const restoredCurrentSong = this.deserializeSong(snapshot.currentSong);

    if (restoredPlaylist.length === 0 && restoredCurrentSong) {
      restoredPlaylist = [restoredCurrentSong];
    }

    if (restoredOriginalPlaylist.length === 0 && restoredPlaylist.length > 0) {
      restoredOriginalPlaylist = [...restoredPlaylist];
    }

    this.isRestoringCache = true;
    this.playlist = restoredPlaylist;
    this._originalPlaylist = restoredOriginalPlaylist;
    this.mode = this.normalizeLoopMode(snapshot.mode);

    const resolvedIndex = this.resolveCurrentSongIndex(restoredCurrentSong, snapshot.currentIndex);
    if (resolvedIndex >= 0 && resolvedIndex < this.playlist.length) {
      this.currentIndex = resolvedIndex;
    } else {
      this.currentIndex = -1;
    }
    this.syncCurrentSongWithIndex();
    this.isRestoringCache = false;

    Logger.info(PlaylistViewModel.TAG, 'Playback cache restored');
  }

  private savePlaybackCache(): void {
    if (this.isRestoringCache || !PreferencesUtil.isInitialized()) {
      return;
    }

    const cachedCurrentSong = this.getCachedCurrentSong();

    if (this.playlist.length === 0 && this._originalPlaylist.length === 0 && !cachedCurrentSong) {
      if (PreferencesUtil.hasKey(PlaylistViewModel.PLAYBACK_CACHE_KEY)) {
        PreferencesUtil.delete(PlaylistViewModel.PLAYBACK_CACHE_KEY);
      }
      return;
    }

    const snapshot = new PlaybackCacheSnapshot();
    snapshot.version = PlaylistViewModel.PLAYBACK_CACHE_VERSION;
    snapshot.playlist = this.serializeSongList(this.playlist);
    snapshot.originalPlaylist = this.serializeSongList(this._originalPlaylist);
    snapshot.currentSong = this.serializeSong(cachedCurrentSong);
    snapshot.currentIndex = this.resolveCachedCurrentIndex(cachedCurrentSong);
    snapshot.mode = this.mode as number;

    try {
      PreferencesUtil.put(PlaylistViewModel.PLAYBACK_CACHE_KEY, JSON.stringify(snapshot));
    } catch (err) {
      Logger.error(PlaylistViewModel.TAG, 'Failed to save playback cache');
    }
  }

  private parsePlaybackCache(cacheContent: string): PlaybackCacheSnapshot | null {
    try {
      const snapshot = JSON.parse(cacheContent) as PlaybackCacheSnapshot;
      if (snapshot.version !== PlaylistViewModel.PLAYBACK_CACHE_VERSION) {
        Logger.warn(PlaylistViewModel.TAG, 'Playback cache version mismatch');
        return null;
      }
      return snapshot;
    } catch (err) {
      Logger.error(PlaylistViewModel.TAG, 'Failed to parse playback cache');
      return null;
    }
  }

  private normalizeLoopMode(mode: number): avSession.LoopMode {
    switch (mode) {
      case avSession.LoopMode.LOOP_MODE_SINGLE:
        return avSession.LoopMode.LOOP_MODE_SINGLE;
      case avSession.LoopMode.LOOP_MODE_SHUFFLE:
        return avSession.LoopMode.LOOP_MODE_SHUFFLE;
      case avSession.LoopMode.LOOP_MODE_LIST:
      default:
        return avSession.LoopMode.LOOP_MODE_LIST;
    }
  }

  private syncCurrentSongWithIndex(): void {
    const targetSong = this.resolveSongByIndex(this.currentIndex);
    if (targetSong) {
      if (this.currentSong !== targetSong) {
        this.currentSong = targetSong;
      }
      return;
    }

    if (this.currentSong !== undefined) {
      this.currentSong = undefined;
    }
  }

  private resolveSongByIndex(index: number): Song | undefined {
    if (index < 0 || index >= this.playlist.length) {
      return undefined;
    }
    return this.playlist[index];
  }

  private getCachedCurrentSong(): Song | undefined {
    const indexedSong = this.resolveSongByIndex(this.currentIndex);
    if (indexedSong) {
      return indexedSong;
    }
    return this.currentSong;
  }

  private resolveCachedCurrentIndex(song: Song | undefined): number {
    if (!song) {
      return this.currentIndex;
    }

    return this.findSongIndex(song, this.playlist);
  }

  private resolveCurrentSongIndex(song: Song | undefined, fallbackIndex: number): number {
    if (song) {
      const targetIndex = this.findSongIndex(song, this.playlist);
      if (targetIndex !== -1) {
        return targetIndex;
      }
    }

    if (fallbackIndex >= 0 && fallbackIndex < this.playlist.length) {
      return fallbackIndex;
    }

    if (this.playlist.length > 0) {
      return 0;
    }

    return -1;
  }

  private findSongIndex(song: Song, songs: Song[]): number {
    for (let i = 0; i < songs.length; i++) {
      const item = songs[i];
      if (this.isSameSong(item, song)) {
        return i;
      }
    }
    return -1;
  }

  private isSameSong(left: Song | undefined, right: Song | undefined): boolean {
    if (!left || !right) {
      return false;
    }
    return left.id === right.id && left.sourceId === right.sourceId;
  }

  private serializeSongList(songs: Song[]): CachedSong[] {
    const cachedSongs: CachedSong[] = [];
    for (let i = 0; i < songs.length; i++) {
      const cachedSong = this.serializeSong(songs[i]);
      if (cachedSong) {
        cachedSongs.push(cachedSong);
      }
    }
    return cachedSongs;
  }

  private deserializeSongList(cachedSongs: CachedSong[]): Song[] {
    const songs: Song[] = [];
    for (let i = 0; i < cachedSongs.length; i++) {
      const song = this.deserializeSong(cachedSongs[i]);
      if (song) {
        songs.push(song);
      }
    }
    return songs;
  }

  private serializeSong(song: Song | undefined): CachedSong | undefined {
    if (!song) {
      return undefined;
    }

    const cachedSong = new CachedSong();
    cachedSong.id = song.id;
    cachedSong.name = song.name;
    cachedSong.tns = this.cloneStringArray(song.tns);
    cachedSong.artists = this.serializeArtists(song.artists);
    cachedSong.album = this.serializeAlbum(song.album);
    cachedSong.duration = song.duration;
    cachedSong.sourceId = song.sourceId;
    return cachedSong;
  }

  private deserializeSong(cachedSong: CachedSong | undefined): Song | undefined {
    if (!cachedSong) {
      return undefined;
    }

    const song = new Song();
    song.id = cachedSong.id;
    song.name = cachedSong.name;
    song.tns = this.cloneStringArray(cachedSong.tns);
    song.artists = this.deserializeArtists(cachedSong.artists);
    song.album = this.deserializeAlbum(cachedSong.album);
    song.duration = cachedSong.duration;
    song.sourceId = cachedSong.sourceId;
    return song;
  }

  private serializeAlbum(album: Album | undefined): CachedAlbum | undefined {
    if (!album) {
      return undefined;
    }

    const cachedAlbum = new CachedAlbum();
    cachedAlbum.id = album.id;
    cachedAlbum.name = album.name;
    cachedAlbum.cover = album.cover;
    cachedAlbum.artists = this.serializeArtists(album.artists);
    cachedAlbum.size = album.size;
    cachedAlbum.sourceId = album.sourceId;
    return cachedAlbum;
  }

  private deserializeAlbum(cachedAlbum: CachedAlbum | undefined): Album | undefined {
    if (!cachedAlbum) {
      return undefined;
    }

    const album = new Album();
    album.id = cachedAlbum.id;
    album.name = cachedAlbum.name;
    album.cover = cachedAlbum.cover;
    album.artists = this.deserializeArtists(cachedAlbum.artists);
    album.size = cachedAlbum.size;
    album.sourceId = cachedAlbum.sourceId;
    return album;
  }

  private serializeArtists(artists: Artist[] | undefined): CachedArtist[] | undefined {
    if (!artists || artists.length === 0) {
      return undefined;
    }

    const cachedArtists: CachedArtist[] = [];
    for (let i = 0; i < artists.length; i++) {
      const artist = artists[i];
      const cachedArtist = new CachedArtist();
      cachedArtist.id = artist.id;
      cachedArtist.name = artist.name;
      cachedArtist.avatar = artist.avatar;
      cachedArtist.sourceId = artist.sourceId;
      cachedArtists.push(cachedArtist);
    }
    return cachedArtists;
  }

  private deserializeArtists(cachedArtists: CachedArtist[] | undefined): Artist[] | undefined {
    if (!cachedArtists || cachedArtists.length === 0) {
      return undefined;
    }

    const artists: Artist[] = [];
    for (let i = 0; i < cachedArtists.length; i++) {
      const cachedArtist = cachedArtists[i];
      const artist = new Artist();
      artist.id = cachedArtist.id;
      artist.name = cachedArtist.name;
      artist.avatar = cachedArtist.avatar;
      artist.sourceId = cachedArtist.sourceId;
      artists.push(artist);
    }
    return artists;
  }

  private cloneStringArray(values: string[] | undefined): string[] | undefined {
    if (!values || values.length === 0) {
      return undefined;
    }

    const result: string[] = [];
    for (let i = 0; i < values.length; i++) {
      result.push(values[i]);
    }
    return result;
  }

  public clearPlaylist(): void {
    this.playlist = [];
    this._originalPlaylist = [];
    this.currentIndex = -1;
    this.currentSong = undefined;
    this.savePlaybackCache();
  }
}