import { Song } from '../model/adapter/Song';
import { Playlist } from '../model/adapter/Playlist';
import { User } from '../model/adapter/User';
import { SongMeta } from '../model/adapter/SongMeta';
import { Source } from '../model/Source';
import Logger from './Logger';

const TAG = 'SongActions';

/**
 * 判断歌单是否「当前用户自己创建」且可作为增删歌曲的目标。
 *
 * 背景：getUserPlaylists 同时返回用户「创建的」和「收藏的」歌单，
 * 只有自己创建的才能添加 / 移除歌曲；收藏的歌单（creator 非本人）不行。
 * 另外排除 key_ 开头的特殊 / 系统歌单（如「我喜欢的音乐」等），它们不应作为普通添加目标。
 */
export function isOwnedPlaylist(playlist: Playlist, user?: User): boolean {
  if (!user || user.id === undefined || user.id === null) {
    return false;
  }
  const creatorId = playlist.creator?.id;
  if (creatorId === undefined || creatorId === null) {
    return false;
  }
  // id 可能是 number 或 string，统一按字符串比较
  if (String(creatorId) !== String(user.id)) {
    return false;
  }
  // 排除 key_ 开头的特殊歌单
  if (String(playlist.id).startsWith('key_')) {
    return false;
  }
  return true;
}

/** 过滤出「可添加歌曲」的歌单（仅自己创建、非特殊歌单） */
export function filterAddablePlaylists(playlists: Playlist[], user?: User): Playlist[] {
  return playlists.filter((pl: Playlist) => isOwnedPlaylist(pl, user));
}

/**
 * 「添加到歌单」流程控制器（可在任意展示歌曲的页面复用）
 *
 * 宿主用法：
 *   @Local addCtrl: AddToPlaylistController = new AddToPlaylistController();
 *   // 面板：
 *   .bindSheet($$this.addCtrl.shown, this.buildAddSheet(), { ... })
 *   // 菜单「添加到歌单」：
 *   this.addCtrl.open(song, this.sourceListViewModel.sources)
 *
 * 数据逻辑（找源 / 加载并过滤用户歌单 / addSongsToPlaylist / createPlaylist）集中在此，
 * 各页面只需写 bindSheet + 长按菜单，避免重复实现。
 */
@ObservedV2
export class AddToPlaylistController {
  /** 面板是否显示 */
  @Trace shown: boolean = false;
  /** 候选歌单加载中 */
  @Trace loading: boolean = false;
  /** 候选歌单（仅当前用户自己创建的歌单） */
  @Trace candidates: Playlist[] = [];

  private song: Song | null = null;
  private source: Source | null = null;

  /** 打开面板：按歌曲 sourceId 找源并加载其「自己创建」的用户歌单 */
  async open(song: Song, sources: Source[]): Promise<void> {
    const source = sources.find((s: Source) => s.id === song.sourceId);
    if (!source) {
      return;
    }
    this.song = song;
    this.source = source;
    this.candidates = [];
    this.loading = true;
    this.shown = true;
    try {
      const all = await source.getUserPlaylists(source.user?.id ?? 0);
      this.candidates = filterAddablePlaylists(all, source.user);
    } catch (e) {
      Logger.error(TAG, `加载用户歌单失败: ${e}`);
    } finally {
      this.loading = false;
    }
  }

  /** 选中歌单 → 把目标歌曲加进去；返回是否成功 */
  async select(playlist: Playlist): Promise<boolean> {
    if (!this.source || !this.song) {
      return false;
    }
    this.shown = false;
    try {
      await this.source.addSongsToPlaylist(playlist.id, [this.song.id]);
      return true;
    } catch (e) {
      Logger.error(TAG, `添加到歌单失败: ${e}`);
      return false;
    }
  }

  /** 新建歌单并把目标歌曲加进去；返回是否成功 */
  async createAndAdd(name: string): Promise<boolean> {
    if (!this.source || !this.song) {
      return false;
    }
    try {
      const created = await this.source.createPlaylist(name);
      await this.source.addSongsToPlaylist(created.id, [this.song.id]);
      this.shown = false;
      return true;
    } catch (e) {
      Logger.error(TAG, `新建歌单并添加失败: ${e}`);
      return false;
    }
  }

  /** 关闭面板 */
  close(): void {
    this.shown = false;
  }
}

/**
 * 切换歌曲收藏（喜欢）状态，并同步更新 song.meta.isFavorite（驱动菜单文案 / 红心即时刷新）。
 * @returns 新状态（true=已收藏 / false=已取消），无可用源或失败时返回 null
 */
export async function toggleSongFavorite(song: Song, sources: Source[]): Promise<boolean | null> {
  const source = sources.find((s: Source) => s.id === song.sourceId);
  if (!source) {
    return null;
  }
  try {
    const liked = await source.getLikeStatus(song.id);
    await source.likeSong(song.id, !liked);
    // 同步本地收藏标记
    if (!song.meta) {
      song.meta = new SongMeta();
    }
    song.meta.isFavorite = !liked;
    return !liked;
  } catch (e) {
    Logger.error(TAG, `收藏失败: ${e}`);
    return null;
  }
}
