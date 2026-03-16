import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { Source } from '../../model/Source';
import { Playlist } from '../../model/adapter/Playlist';
import { Song } from '../../model/adapter/Song';
import { Artist } from '../../model/adapter/Artist';
import { Album } from '../../model/adapter/Album';
import { SourceDataSource } from '../../data/SourceDataSource';
import CurrentSourceViewModel from '../../viewmodel/CurrentSourceViewModel';
import SettingViewModel from '../../viewmodel/SettingViewModel';
import { SourceListViewModel } from '../../viewmodel/SourceListViewModel';
import Logger from '../../utils/Logger';
import { resourceUtil } from '../../utils/ResourceUtil';
import {
  UnisonAlbumSummary,
  UnisonArtistSummary,
  UnisonFailureResponse,
  UnisonGetSongLyricResponse,
  UnisonGetUserPlaylistsResponse,
  UnisonListSourcesResponse,
  UnisonLyricPayload,
  UnisonPlaylistSummary,
  UnisonSearchMusicResponse,
  UnisonSetMainSourceResponse,
  UnisonSongSummary,
  UnisonSourceSummary,
  UnisonToolArguments,
  UnisonToolExecutionResult,
} from './UnisonToolTypes';

const TAG = 'UnisonToolExecutor';

export class UnisonToolExecutor {
  private getString(res: Resource): string {
    return resourceUtil.getAppString(res, '');
  }

  private getCountText(count: number, res: Resource): string {
    const suffix: string = this.getString(res);
    return `${count}${suffix}`;
  }

  private getSourceSwitchedText(sourceName: string): string {
    const prefix: string = this.getString($r('app.string.unison_plus_tool_set_main_source_prefix'));
    const suffix: string = this.getString($r('app.string.unison_plus_tool_set_main_source_suffix'));
    return `${prefix}${sourceName}${suffix}`;
  }

  private getUnknownToolText(toolName: string): string {
    const prefix: string = this.getString($r('app.string.unison_plus_tool_unknown_prefix'));
    return `${prefix}${toolName}`;
  }

  private getSettingViewModel(): SettingViewModel {
    return PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  }

  private getSourceListViewModel(): SourceListViewModel {
    return AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!;
  }

  private getCurrentSourceViewModel(): CurrentSourceViewModel {
    return AppStorageV2.connect(CurrentSourceViewModel, 'CurrentSourceViewModel', () => new CurrentSourceViewModel())!;
  }

  private parseArguments(argsText: string): UnisonToolArguments {
    if (argsText.trim() === '') {
      return new UnisonToolArguments();
    }

    const parsedArgs: UnisonToolArguments = JSON.parse(argsText) as UnisonToolArguments;
    return parsedArgs;
  }

  private buildFailureContent(message: string): string {
    const response: UnisonFailureResponse = new UnisonFailureResponse();
    response.success = false;
    response.message = message;
    return JSON.stringify(response);
  }

  private markFailure(result: UnisonToolExecutionResult, message: string): void {
    result.success = false;
    result.content = this.buildFailureContent(message);
  }

  private async getAvailableSources(): Promise<Source[]> {
    const sourceListViewModel: SourceListViewModel = this.getSourceListViewModel();
    if (sourceListViewModel.sources.length > 0) {
      return sourceListViewModel.sources;
    }

    if (!SourceDataSource.isInitialized()) {
      return [];
    }

    return await SourceDataSource.getAllSources();
  }

  private async resolveSource(sourceId?: string): Promise<Source> {
    const sourceListViewModel: SourceListViewModel = this.getSourceListViewModel();
    const settingViewModel: SettingViewModel = this.getSettingViewModel();
    const currentSourceViewModel: CurrentSourceViewModel = this.getCurrentSourceViewModel();

    let targetSourceId: string = sourceId?.trim() ?? '';
    if (targetSourceId === '' && settingViewModel.mainSource.trim() !== '') {
      targetSourceId = settingViewModel.mainSource.trim();
    }
    if (targetSourceId === '' && currentSourceViewModel.source) {
      targetSourceId = currentSourceViewModel.source.id;
    }

    if (targetSourceId !== '') {
      for (let i: number = 0; i < sourceListViewModel.sources.length; i++) {
        const source: Source = sourceListViewModel.sources[i];
        if (source.id === targetSourceId) {
          return source;
        }
      }
      if (SourceDataSource.isInitialized()) {
        const source: Source | null = await SourceDataSource.getSourceById(targetSourceId);
        if (source) {
          return source;
        }
      }
    }

    const sources: Source[] = await this.getAvailableSources();
    if (sources.length > 0) {
      return sources[0];
    }

    throw new Error(this.getString($r('app.string.unison_plus_tool_no_source_available')));
  }

  private joinArtistNames(artists?: Artist[]): string {
    if (!artists || artists.length === 0) {
      return '';
    }

    let names: string = '';
    for (let i: number = 0; i < artists.length; i++) {
      if (i > 0) {
        names = `${names} / `;
      }
      names = `${names}${artists[i].name}`;
    }
    return names;
  }

  private buildSourceSummary(source: Source, mainSourceId: string): UnisonSourceSummary {
    const summary: UnisonSourceSummary = new UnisonSourceSummary();
    summary.id = source.id;
    summary.name = source.name;
    summary.type = source.type;
    summary.url = source.url;
    summary.description = source.description;
    summary.userId = source.user ? String(source.user.id) : '';
    summary.userName = source.user ? source.user.name : '';
    summary.authorized = source.token.trim() !== '';
    summary.isMain = source.id === mainSourceId;
    return summary;
  }

  private buildPlaylistSummary(playlist: Playlist): UnisonPlaylistSummary {
    const summary: UnisonPlaylistSummary = new UnisonPlaylistSummary();
    summary.id = String(playlist.id);
    summary.name = playlist.name ?? '';
    summary.cover = playlist.cover ?? '';
    summary.size = playlist.size ?? 0;
    summary.creatorName = playlist.creator?.name ?? '';
    summary.description = playlist.description ?? '';
    summary.sourceId = playlist.sourceId;
    return summary;
  }

  private buildSongSummary(song: Song): UnisonSongSummary {
    const summary: UnisonSongSummary = new UnisonSongSummary();
    summary.id = String(song.id);
    summary.name = song.name ?? '';
    summary.artistNames = this.joinArtistNames(song.artists);
    summary.albumName = song.album?.name ?? '';
    summary.duration = song.duration ?? 0;
    summary.sourceId = song.sourceId;
    return summary;
  }

  private buildArtistSummary(artist: Artist): UnisonArtistSummary {
    const summary: UnisonArtistSummary = new UnisonArtistSummary();
    summary.id = String(artist.id);
    summary.name = artist.name;
    summary.avatar = artist.avatar ?? '';
    summary.sourceId = artist.sourceId;
    return summary;
  }

  private buildAlbumSummary(album: Album): UnisonAlbumSummary {
    const summary: UnisonAlbumSummary = new UnisonAlbumSummary();
    summary.id = String(album.id);
    summary.name = album.name;
    summary.cover = album.cover ?? '';
    summary.artistNames = this.joinArtistNames(album.artists);
    summary.size = album.size ?? 0;
    summary.sourceId = album.sourceId;
    return summary;
  }

  private buildLyricPayload(sourceId: string, songId: string | number, normal: string, translation: string,
    transliteration: string): UnisonLyricPayload {
    const payload: UnisonLyricPayload = new UnisonLyricPayload();
    payload.sourceId = sourceId;
    payload.songId = String(songId);
    payload.normal = normal;
    payload.translation = translation;
    payload.transliteration = transliteration;
    return payload;
  }

  private async executeListSources(result: UnisonToolExecutionResult): Promise<void> {
    const sources: Source[] = await this.getAvailableSources();
    const settingViewModel: SettingViewModel = this.getSettingViewModel();
    const response: UnisonListSourcesResponse = new UnisonListSourcesResponse();
    response.success = true;
    response.message = this.getString($r('app.string.unison_plus_tool_returned_prefix')) +
      this.getCountText(sources.length, $r('app.string.unison_plus_tool_sources_count_suffix'));
    response.mainSourceId = settingViewModel.mainSource;
    for (let i: number = 0; i < sources.length; i++) {
      response.sources.push(this.buildSourceSummary(sources[i], settingViewModel.mainSource));
    }

    result.success = true;
    result.payload.sources = response.sources;
    result.content = JSON.stringify(response);
  }

  private async executeSetMainSource(args: UnisonToolArguments, result: UnisonToolExecutionResult): Promise<void> {
    const source: Source = await this.resolveSource(args.sourceId);
    const settingViewModel: SettingViewModel = this.getSettingViewModel();
    const currentSourceViewModel: CurrentSourceViewModel = this.getCurrentSourceViewModel();
    settingViewModel.mainSource = source.id;
    currentSourceViewModel.source = source;

    const response: UnisonSetMainSourceResponse = new UnisonSetMainSourceResponse();
    response.success = true;
    response.message = this.getSourceSwitchedText(source.name);
    response.mainSourceId = source.id;
    response.source = this.buildSourceSummary(source, source.id);

    result.success = true;
    if (response.source) {
      result.payload.sources = [response.source];
    }
    result.content = JSON.stringify(response);
  }

  private async executeGetUserPlaylists(args: UnisonToolArguments, result: UnisonToolExecutionResult): Promise<void> {
    const source: Source = await this.resolveSource(args.sourceId);
    const uidValue: number | string | undefined = args.uid ?? source.user?.id;
    if (uidValue === undefined) {
      throw new Error(this.getString($r('app.string.unison_plus_tool_missing_uid')));
    }

    const limit: number = args.limit ?? 20;
    const offset: number = args.offset ?? 0;
    const playlists: Playlist[] = await source.getUserPlaylists(uidValue, limit, offset);
    const response: UnisonGetUserPlaylistsResponse = new UnisonGetUserPlaylistsResponse();
    response.success = true;
    response.message = this.getString($r('app.string.unison_plus_tool_returned_prefix')) +
      this.getCountText(playlists.length, $r('app.string.unison_plus_tool_playlists_count_suffix'));
    response.sourceId = source.id;
    response.uid = String(uidValue);
    for (let i: number = 0; i < playlists.length; i++) {
      response.playlists.push(this.buildPlaylistSummary(playlists[i]));
    }

    result.success = true;
    result.payload.playlists = playlists;
    result.content = JSON.stringify(response);
  }

  private async executeGetSongLyric(args: UnisonToolArguments, result: UnisonToolExecutionResult): Promise<void> {
    if (args.id === undefined) {
      throw new Error(this.getString($r('app.string.unison_plus_tool_missing_song_id')));
    }

    const source: Source = await this.resolveSource(args.sourceId);
    const lyricResponse = await source.getLyric(args.id);
    const lyricPayload: UnisonLyricPayload = this.buildLyricPayload(
      source.id,
      args.id,
      lyricResponse.lyric.normal,
      lyricResponse.lyric.translation,
      lyricResponse.lyric.transliteration,
    );
    const response: UnisonGetSongLyricResponse = new UnisonGetSongLyricResponse();
    response.success = true;
    response.message = this.getString($r('app.string.unison_plus_tool_lyric_returned'));
    response.sourceId = source.id;
    response.songId = String(args.id);
    response.lyric = lyricPayload;

    result.success = true;
    result.payload.lyric = lyricPayload;
    result.content = JSON.stringify(response);
  }

  private async executeSearchMusic(args: UnisonToolArguments, result: UnisonToolExecutionResult): Promise<void> {
    if (!args.keywords || args.keywords.trim() === '') {
      throw new Error(this.getString($r('app.string.unison_plus_tool_missing_keywords')));
    }

    const source: Source = await this.resolveSource(args.sourceId);
    const limit: number = args.limit ?? 10;
    const searchResponse = await source.search(args.keywords, limit);
    const response: UnisonSearchMusicResponse = new UnisonSearchMusicResponse();
    response.success = true;
    response.message = this.getString($r('app.string.unison_plus_tool_search_returned'));
    response.sourceId = source.id;
    response.keywords = args.keywords;

    if (searchResponse.songs) {
      for (let i: number = 0; i < searchResponse.songs.length; i++) {
        response.songs.push(this.buildSongSummary(searchResponse.songs[i]));
      }
    }
    if (searchResponse.playlists) {
      for (let i: number = 0; i < searchResponse.playlists.length; i++) {
        response.playlists.push(this.buildPlaylistSummary(searchResponse.playlists[i]));
      }
    }
    if (searchResponse.artists) {
      for (let i: number = 0; i < searchResponse.artists.length; i++) {
        response.artists.push(this.buildArtistSummary(searchResponse.artists[i]));
      }
    }
    if (searchResponse.albums) {
      for (let i: number = 0; i < searchResponse.albums.length; i++) {
        response.albums.push(this.buildAlbumSummary(searchResponse.albums[i]));
      }
    }

    result.success = true;
    result.payload.songs = searchResponse.songs ?? [];
    result.payload.playlists = searchResponse.playlists ?? [];
    result.payload.artists = searchResponse.artists ?? [];
    result.payload.albums = searchResponse.albums ?? [];
    result.content = JSON.stringify(response);
  }

  public async execute(toolName: string, argsText: string, toolCallId: string): Promise<UnisonToolExecutionResult> {
    const result: UnisonToolExecutionResult = new UnisonToolExecutionResult();
    result.toolCallId = toolCallId;
    result.toolName = toolName;

    try {
      const args: UnisonToolArguments = this.parseArguments(argsText);
      Logger.info(TAG, `执行工具: ${toolName}`);

      if (toolName === 'list_sources') {
        await this.executeListSources(result);
      } else if (toolName === 'set_main_source') {
        await this.executeSetMainSource(args, result);
      } else if (toolName === 'get_user_playlists') {
        await this.executeGetUserPlaylists(args, result);
      } else if (toolName === 'get_song_lyric') {
        await this.executeGetSongLyric(args, result);
      } else if (toolName === 'search_music') {
        await this.executeSearchMusic(args, result);
      } else {
        this.markFailure(result, this.getUnknownToolText(toolName));
      }
    } catch (error) {
      const message: string = `${error}`;
      Logger.error(TAG, message);
      this.markFailure(result, message);
    }

    return result;
  }
}