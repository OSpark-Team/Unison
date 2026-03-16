import { AppStorageV2, PersistenceV2 } from '@kit.ArkUI';
import { BreakpointConstants } from '../common/BreakpointConstants';
import { ArtistListItem } from '../components/ArtistListItem';
import { PlaylistListItem } from '../components/PlaylistListItem';
import { SongListItem } from '../components/SongListItem';
import { Album } from '../model/adapter/Album';
import { Artist } from '../model/adapter/Artist';
import { Playlist } from '../model/adapter/Playlist';
import { Song } from '../model/adapter/Song';
import { Source } from '../model/Source';
import { WindowProperties } from '../model/WindowProperties';
import { PlaylistDetailParam } from '../pages/PlaylistDetail';
import { UnisonAgentService } from '../services/unison/UnisonAgentService';
import {
  UnisonAgentResult,
  UnisonDisplayMessage,
  UnisonLyricPayload,
  UnisonSourceSummary,
  UnisonStructuredAssistantResponse,
  UnisonStructuredResultItem,
  UnisonStructuredResponseCodec,
  UnisonToolStep,
} from '../services/unison/UnisonToolTypes';
import Logger from '../utils/Logger';
import { resourceUtil } from '../utils/ResourceUtil';
import { cover } from '../utils/Tools';
import CurrentSourceViewModel from '../viewmodel/CurrentSourceViewModel';
import PlaylistViewModel from '../viewmodel/PlaylistViewModel';
import SettingViewModel from '../viewmodel/SettingViewModel';
import { SourceListViewModel } from '../viewmodel/SourceListViewModel';

const TAG: string = 'UnisonPlusView';

@ComponentV2
export struct UnisonPlusView {
  // @Require @Param scroller: Scroller ;

  @Consumer() pageInfos: NavPathStack = new NavPathStack();
  @Local settingModel: SettingViewModel =
    PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  @Local currentSourceViewModel: CurrentSourceViewModel =
    AppStorageV2.connect(CurrentSourceViewModel, 'CurrentSourceViewModel', () => new CurrentSourceViewModel())!;
  @Local sourceListViewModel: SourceListViewModel =
    AppStorageV2.connect(SourceListViewModel, 'SourceListViewModel', () => new SourceListViewModel())!;
  @Local playlistViewModel: PlaylistViewModel =
    AppStorageV2.connect(PlaylistViewModel, 'PlaylistViewModel', () => new PlaylistViewModel())!;
  @Local messages: UnisonDisplayMessage[] = [];
  @Local renderMessages: UnisonDisplayMessage[] = [];
  @Local inputText: string = '';
  @Local isSending: boolean = false;
  @Local errorMessage: string = '';
  private agentService: UnisonAgentService = new UnisonAgentService();
  private listScroller: Scroller = new Scroller();

  /**
   * 窗口属性
   */
  @Local windowProperties: WindowProperties =
    AppStorageV2.connect(WindowProperties, "WindowProperties", () => new WindowProperties())!;

  @Computed
  get canSend(): boolean {
    return !this.isSending && this.inputText.trim() !== '' && this.settingModel.isByokConfigured();
  }

  private getString(res: Resource): string {
    return resourceUtil.getString(this.getUIContext()!.getHostContext()!, res);
  }

  private withValue(label: string, value: string): string {
    if (value.trim() === '') {
      return label;
    }
    return `${label}：${value}`;
  }

  private getToolNameText(toolName: string): string {
    if (toolName === 'list_sources') {
      return this.getString($r('app.string.unison_plus_tool_list_sources'));
    }
    if (toolName === 'set_main_source') {
      return this.getString($r('app.string.unison_plus_tool_set_main_source'));
    }
    if (toolName === 'get_user_playlists') {
      return this.getString($r('app.string.unison_plus_tool_get_user_playlists'));
    }
    if (toolName === 'get_song_lyric') {
      return this.getString($r('app.string.unison_plus_tool_get_song_lyric'));
    }
    if (toolName === 'search_music') {
      return this.getString($r('app.string.unison_plus_tool_search_music'));
    }
    return toolName;
  }

  private getToolStepStateText(state: string): string {
    if (state === 'running') {
      return this.getString($r('app.string.unison_plus_tool_running'));
    }
    if (state === 'success') {
      return this.getString($r('app.string.unison_plus_tool_done'));
    }
    if (state === 'failed') {
      return this.getString($r('app.string.unison_plus_tool_failed'));
    }
    return state;
  }

  private getStatusText(message: UnisonDisplayMessage): string {
    if (message.status === 'thinking') {
      return this.getString($r('app.string.unison_plus_thinking'));
    }
    if (message.status === 'searching') {
      return this.withValue(this.getString($r('app.string.unison_plus_searching')), message.statusValue);
    }
    if (message.status === 'calling_tool') {
      return this.withValue(this.getString($r('app.string.unison_plus_calling_tool')),
        this.getToolNameText(message.statusValue));
    }
    if (message.status === 'fetching_lyric') {
      return this.withValue(this.getString($r('app.string.unison_plus_fetching_lyric')), message.statusValue);
    }
    if (message.status === 'round_limit') {
      return this.getString($r('app.string.unison_plus_round_limit'));
    }
    if (message.status === 'request_failed') {
      return this.withValue(this.getString($r('app.string.unison_plus_request_failed')), message.statusValue);
    }
    if (message.statusValue.trim() !== '') {
      return this.withValue(this.getString($r('app.string.unison_plus_status')), message.statusValue);
    }
    return this.getString($r('app.string.unison_plus_status'));
  }

  private hasPayload(message: UnisonDisplayMessage): boolean {
    return message.sources.length > 0 || message.structuredItems.length > 0 || message.lyric !== undefined;
  }

  private hasRenderableAssistantResult(message: UnisonDisplayMessage): boolean {
    return message.content.trim() !== '' || this.hasPayload(message);
  }

  private hasTerminalAssistantState(message: UnisonDisplayMessage): boolean {
    return message.role === 'assistant' && (this.hasRenderableAssistantResult(message) ||
      message.status === 'round_limit' || message.status === 'request_failed');
  }

  private shouldShowStatusBubble(message: UnisonDisplayMessage): boolean {
    if (message.status === 'round_limit' || message.status === 'request_failed') {
      return true;
    }
    if (this.hasRenderableAssistantResult(message)) {
      return false;
    }
    return message.status.trim() !== '' || message.isLoading;
  }

  private getSongArtistNames(song: Song): string {
    if (!song.artists || song.artists.length === 0) {
      return '';
    }
    return song.artists.map((artist: Artist) => artist.name).join('/');
  }

  private getAlbumArtistNames(album: Album): string {
    if (!album.artists || album.artists.length === 0) {
      return '';
    }
    return album.artists.map((artist: Artist) => artist.name).join('/');
  }

  private getSourceDescription(source: UnisonSourceSummary): string {
    if (source.description.trim() !== '') {
      return source.description;
    }
    if (source.url.trim() !== '') {
      return source.url;
    }
    return source.type;
  }

  private isSourceActive(source: UnisonSourceSummary): boolean {
    return source.isMain || this.settingModel.mainSource === source.id;
  }

  private findSourceById(sourceId: string): Source | null {
    for (let i: number = 0; i < this.sourceListViewModel.sources.length; i++) {
      const source: Source = this.sourceListViewModel.sources[i];
      if (source.id === sourceId) {
        return source;
      }
    }
    return null;
  }

  private findSongByStructuredItem(message: UnisonDisplayMessage, item: UnisonStructuredResultItem): Song | null {
    for (let i: number = 0; i < message.songs.length; i++) {
      const song: Song = message.songs[i];
      if (String(song.id) === item.id && (song.name ?? '') === item.name) {
        return song;
      }
    }
    for (let i: number = 0; i < message.songs.length; i++) {
      const song: Song = message.songs[i];
      if (String(song.id) === item.id) {
        return song;
      }
    }
    return null;
  }

  private findPlaylistByStructuredItem(message: UnisonDisplayMessage, item: UnisonStructuredResultItem): Playlist | null {
    for (let i: number = 0; i < message.playlists.length; i++) {
      const playlist: Playlist = message.playlists[i];
      if (String(playlist.id) === item.id && (playlist.name ?? '') === item.name) {
        return playlist;
      }
    }
    for (let i: number = 0; i < message.playlists.length; i++) {
      const playlist: Playlist = message.playlists[i];
      if (String(playlist.id) === item.id) {
        return playlist;
      }
    }
    return null;
  }

  private findArtistByStructuredItem(message: UnisonDisplayMessage, item: UnisonStructuredResultItem): Artist | null {
    for (let i: number = 0; i < message.artists.length; i++) {
      const artist: Artist = message.artists[i];
      if (String(artist.id) === item.id && artist.name === item.name) {
        return artist;
      }
    }
    for (let i: number = 0; i < message.artists.length; i++) {
      const artist: Artist = message.artists[i];
      if (String(artist.id) === item.id) {
        return artist;
      }
    }
    return null;
  }

  private findAlbumByStructuredItem(message: UnisonDisplayMessage, item: UnisonStructuredResultItem): Album | null {
    for (let i: number = 0; i < message.albums.length; i++) {
      const album: Album = message.albums[i];
      if (String(album.id) === item.id && album.name === item.name) {
        return album;
      }
    }
    for (let i: number = 0; i < message.albums.length; i++) {
      const album: Album = message.albums[i];
      if (String(album.id) === item.id) {
        return album;
      }
    }
    return null;
  }

  private resolvePlaylistSourceId(playlist: Playlist): string {
    if (playlist.sourceId.trim() !== '') {
      return playlist.sourceId;
    }
    if (this.currentSourceViewModel.source) {
      return this.currentSourceViewModel.source.id;
    }
    return this.settingModel.mainSource;
  }

  private normalizePlaylistForDetail(playlist: Playlist): Playlist {
    const normalized: Playlist = new Playlist();
    normalized.id = playlist.id;
    normalized.name = playlist.name;
    normalized.cover = playlist.cover;
    normalized.size = playlist.size;
    normalized.creator = playlist.creator;
    normalized.songs = playlist.songs;
    normalized.description = playlist.description;
    normalized.meta = playlist.meta;
    normalized.type = playlist.type === undefined ? 'normal' : playlist.type;
    normalized.sourceId = this.resolvePlaylistSourceId(playlist);
    return normalized;
  }

  private openStructuredItem(message: UnisonDisplayMessage, item: UnisonStructuredResultItem): void {
    if (item.type === 'song') {
      const song: Song | null = this.findSongByStructuredItem(message, item);
      if (song !== null) {
        this.playSong(song);
      }
      return;
    }
    if (item.type === 'playlist') {
      const playlist: Playlist | null = this.findPlaylistByStructuredItem(message, item);
      if (playlist !== null) {
        this.openPlaylistDetail(playlist);
      }
      return;
    }
    if (item.type === 'artist') {
      const artist: Artist | null = this.findArtistByStructuredItem(message, item);
      if (artist !== null) {
        this.openArtistDetail(artist);
      }
      return;
    }
    if (item.type === 'album') {
      const album: Album | null = this.findAlbumByStructuredItem(message, item);
      if (album !== null) {
        this.openAlbumDetail(album);
      }
    }
  }

  private normalizeFinalMessages(messages: UnisonDisplayMessage[]): UnisonDisplayMessage[] {
    const normalized: UnisonDisplayMessage[] = this.cloneDisplayMessages(messages);
    for (let i: number = 0; i < normalized.length; i++) {
      this.normalizeStructuredMessage(normalized[i]);
      this.clearTransientAssistantState(normalized[i]);
    }
    return this.pruneStaleTransientAssistantMessages(normalized);
  }

  private createAssistantStatusSnapshot(message: UnisonDisplayMessage): UnisonDisplayMessage {
    const snapshot: UnisonDisplayMessage = this.cloneDisplayMessage(message);
    snapshot.content = '';
    snapshot.sources = [];
    snapshot.playlists = [];
    snapshot.songs = [];
    snapshot.artists = [];
    snapshot.albums = [];
    snapshot.structuredItems = [];
    snapshot.lyric = undefined;
    return snapshot;
  }

  private createAssistantResultSnapshot(message: UnisonDisplayMessage): UnisonDisplayMessage {
    const snapshot: UnisonDisplayMessage = this.cloneDisplayMessage(message);
    snapshot.isLoading = false;
    snapshot.status = '';
    snapshot.statusValue = '';
    return snapshot;
  }

  private buildRenderMessages(messages: UnisonDisplayMessage[]): UnisonDisplayMessage[] {
    const renderMessages: UnisonDisplayMessage[] = [];
    for (let i: number = 0; i < messages.length; i++) {
      const message: UnisonDisplayMessage = messages[i];
      if (message.role === 'user') {
        renderMessages.push(this.cloneDisplayMessage(message));
        continue;
      }
      if (this.hasRenderableAssistantResult(message)) {
        renderMessages.push(this.createAssistantResultSnapshot(message));
        continue;
      }
      if (this.shouldShowStatusBubble(message)) {
        renderMessages.push(this.createAssistantStatusSnapshot(message));
      }
    }
    return renderMessages;
  }

  private isTransientAssistantMessage(message: UnisonDisplayMessage): boolean {
    return message.role === 'assistant' && !this.hasRenderableAssistantResult(message) &&
      message.status !== 'round_limit' && message.status !== 'request_failed';
  }

  private hasLaterTerminalAssistantMessage(messages: UnisonDisplayMessage[], index: number): boolean {
    for (let i: number = index + 1; i < messages.length; i++) {
      if (this.hasTerminalAssistantState(messages[i])) {
        return true;
      }
    }
    return false;
  }

  private pruneStaleTransientAssistantMessages(messages: UnisonDisplayMessage[]): UnisonDisplayMessage[] {
    const filtered: UnisonDisplayMessage[] = [];
    for (let i: number = 0; i < messages.length; i++) {
      if (this.isTransientAssistantMessage(messages[i]) && this.hasLaterTerminalAssistantMessage(messages, i)) {
        continue;
      }
      filtered.push(messages[i]);
    }
    return filtered;
  }

  private clearTransientAssistantState(message: UnisonDisplayMessage): void {
    if (message.role !== 'assistant') {
      return;
    }
    if (message.status === 'round_limit' || message.status === 'request_failed') {
      return;
    }
    if (!this.hasRenderableAssistantResult(message)) {
      return;
    }
    message.isLoading = false;
    message.status = '';
    message.statusValue = '';
  }

  private cloneToolStep(step: UnisonToolStep): UnisonToolStep {
    const copy: UnisonToolStep = new UnisonToolStep();
    copy.id = step.id;
    copy.toolName = step.toolName;
    copy.state = step.state;
    return copy;
  }

  private cloneSourceSummary(source: UnisonSourceSummary): UnisonSourceSummary {
    const copy: UnisonSourceSummary = new UnisonSourceSummary();
    copy.id = source.id;
    copy.name = source.name;
    copy.type = source.type;
    copy.url = source.url;
    copy.description = source.description;
    copy.userId = source.userId;
    copy.userName = source.userName;
    copy.authorized = source.authorized;
    copy.isMain = source.isMain;
    return copy;
  }

  private cloneLyricPayload(lyric?: UnisonLyricPayload): UnisonLyricPayload | undefined {
    if (!lyric) {
      return undefined;
    }

    const copy: UnisonLyricPayload = new UnisonLyricPayload();
    copy.sourceId = lyric.sourceId;
    copy.songId = lyric.songId;
    copy.normal = lyric.normal;
    copy.translation = lyric.translation;
    copy.transliteration = lyric.transliteration;
    return copy;
  }

  private cloneDisplayMessage(message: UnisonDisplayMessage): UnisonDisplayMessage {
    const copy: UnisonDisplayMessage = new UnisonDisplayMessage(message.id, message.role, message.content);
    copy.isLoading = message.isLoading;
    copy.status = message.status;
    copy.statusValue = message.statusValue;

    for (let i: number = 0; i < message.toolSteps.length; i++) {
      copy.toolSteps.push(this.cloneToolStep(message.toolSteps[i]));
    }
    for (let i: number = 0; i < message.sources.length; i++) {
      copy.sources.push(this.cloneSourceSummary(message.sources[i]));
    }
    copy.playlists = message.playlists.slice();
    copy.songs = message.songs.slice();
    copy.artists = message.artists.slice();
    copy.albums = message.albums.slice();
    for (let i: number = 0; i < message.structuredItems.length; i++) {
      copy.structuredItems.push(this.cloneStructuredItem(message.structuredItems[i]));
    }
    copy.lyric = this.cloneLyricPayload(message.lyric);
    return copy;
  }

  private cloneDisplayMessages(messages: UnisonDisplayMessage[]): UnisonDisplayMessage[] {
    const copies: UnisonDisplayMessage[] = [];
    for (let i: number = 0; i < messages.length; i++) {
      copies.push(this.cloneDisplayMessage(messages[i]));
    }
    return copies;
  }

  private cloneStructuredItem(item: UnisonStructuredResultItem): UnisonStructuredResultItem {
    const copy: UnisonStructuredResultItem = new UnisonStructuredResultItem();
    copy.type = item.type;
    copy.id = item.id;
    copy.name = item.name;
    copy.cover = item.cover;
    copy.hit = item.hit;
    return copy;
  }

  private tryParseStructuredContent(content: string): UnisonStructuredAssistantResponse | null {
    const text: string = content.trim();
    if (text === '' || !text.startsWith('{')) {
      return null;
    }
    if (text.indexOf('"displayText"') < 0 || text.indexOf('"items"') < 0) {
      return null;
    }

    try {
      return UnisonStructuredResponseCodec.parse(text);
    } catch {
      return null;
    }
  }

  private normalizeStructuredMessage(message: UnisonDisplayMessage): void {
    if (message.role !== 'assistant' || message.lyric !== undefined) {
      return;
    }

    const structuredResponse: UnisonStructuredAssistantResponse | null = this.tryParseStructuredContent(message.content);
    if (structuredResponse === null) {
      return;
    }

    if (structuredResponse.displayText.trim() !== '') {
      message.content = structuredResponse.displayText;
    }

    if (message.structuredItems.length === 0) {
      for (let i: number = 0; i < structuredResponse.items.length; i++) {
        message.structuredItems.push(this.cloneStructuredItem(structuredResponse.items[i]));
      }
    }

    this.clearTransientAssistantState(message);
  }

  private scrollToBottom(): void {
    if (this.renderMessages.length === 0) {
      return;
    }
    const idx: number = this.renderMessages.length - 1;
    setTimeout(() => {
      this.listScroller.scrollToIndex(idx, false, ScrollAlign.END);
    }, 0);
  }

  private applyMessages(messages: UnisonDisplayMessage[]): UnisonDisplayMessage[] {
    const normalizedMessages: UnisonDisplayMessage[] = this.normalizeFinalMessages(messages);
    this.messages = normalizedMessages;
    this.renderMessages = this.buildRenderMessages(normalizedMessages);
    this.syncSendingState(normalizedMessages);
    return normalizedMessages;
  }

  private buildToolStepsSignature(message: UnisonDisplayMessage): string {
    let summary: string = '';
    for (let i: number = 0; i < message.toolSteps.length; i++) {
      if (i > 0) {
        summary = `${summary}|`;
      }
      summary = `${summary}${message.toolSteps[i].toolName}:${message.toolSteps[i].state}`;
    }
    return summary;
  }

  private buildSourcesSignature(message: UnisonDisplayMessage): string {
    let summary: string = '';
    for (let i: number = 0; i < message.sources.length; i++) {
      if (i > 0) {
        summary = `${summary}|`;
      }
      summary = `${summary}${message.sources[i].id}:${message.sources[i].isMain ? 'main' : 'normal'}`;
    }
    return summary;
  }

  private buildStructuredItemsSignature(message: UnisonDisplayMessage): string {
    let summary: string = '';
    for (let i: number = 0; i < message.structuredItems.length; i++) {
      if (i > 0) {
        summary = `${summary}|`;
      }
      summary = `${summary}${message.structuredItems[i].type}:${message.structuredItems[i].id}`;
    }
    return summary;
  }

  private syncSendingState(messages: UnisonDisplayMessage[]): void {
    if (messages.length === 0) {
      return;
    }

    const lastMessage: UnisonDisplayMessage = messages[messages.length - 1];
    if (this.hasTerminalAssistantState(lastMessage)) {
      this.isSending = false;
    }
  }

  private logLatestMessageState(stage: string, messages: UnisonDisplayMessage[]): void {
    if (messages.length === 0) {
      Logger.info(TAG, `${stage}: empty`);
      return;
    }

    const lastMessage: UnisonDisplayMessage = messages[messages.length - 1];
    Logger.info(TAG,
      `${stage}: role=${lastMessage.role}, loading=${lastMessage.isLoading}, status=${lastMessage.status}, ` +
      `statusValue=${lastMessage.statusValue}, contentLength=${lastMessage.content.length}, ` +
      `toolSteps=${this.buildToolStepsSignature(lastMessage)}, sources=${lastMessage.sources.length}, ` +
      `structured=${lastMessage.structuredItems.length}, lyric=${lastMessage.lyric === undefined ? 'no' : 'yes'}, ` +
      `sending=${this.isSending}`);
  }

  private getMessageRenderKey(message: UnisonDisplayMessage): string {
    const lyricKey: string = message.lyric === undefined ? 'no-lyric' : `${message.lyric.songId}-${message.lyric.sourceId}`;
    return `message-${message.id}-${this.getRenderTemplateId(message)}-${message.isLoading ? 'loading' : 'ready'}-${message.status}-` +
      `${message.statusValue}-${message.content.length}-${this.buildToolStepsSignature(message)}-` +
      `${this.buildSourcesSignature(message)}-${this.buildStructuredItemsSignature(message)}-${lyricKey}`;
  }

  private getRenderTemplateId(message: UnisonDisplayMessage): string {
    if (message.role === 'user') {
      return 'user';
    }
    if (this.hasRenderableAssistantResult(message)) {
      return 'assistant_result';
    }
    return 'assistant_status';
  }

  private playSong(song: Song): void {
    this.playlistViewModel.insertSongs([song]);
    this.playlistViewModel.playSong(song, true);
  }

  private openPlaylistDetail(playlist: Playlist): void {
    const normalizedPlaylist: Playlist = this.normalizePlaylistForDetail(playlist);
    this.pageInfos.pushPathByName('PlaylistDetail', {
      playlistId: String(normalizedPlaylist.id),
      sourceId: normalizedPlaylist.sourceId,
      playlist: normalizedPlaylist,
    } as PlaylistDetailParam, true);
  }

  private openArtistDetail(artist: Artist): void {
    this.pageInfos.pushPathByName('PlaylistDetail', {
      playlistId: String(artist.id),
      sourceId: artist.sourceId,
      playlist: Playlist.Type('artist'),
    } as PlaylistDetailParam, true);
  }

  private openAlbumDetail(album: Album): void {
    this.pageInfos.pushPathByName('PlaylistDetail', {
      playlistId: String(album.id),
      sourceId: album.sourceId,
      playlist: Playlist.Type('album'),
    } as PlaylistDetailParam, true);
  }

  private async switchMainSource(summary: UnisonSourceSummary): Promise<void> {
    this.settingModel.mainSource = summary.id;
    const currentSource: Source | null = this.findSourceById(summary.id);
    if (currentSource !== null) {
      this.currentSourceViewModel.source = currentSource;
    }
    await this.sourceListViewModel.refresh();
    const refreshedSource: Source | null = this.findSourceById(summary.id);
    if (refreshedSource !== null) {
      this.currentSourceViewModel.source = refreshedSource;
    }
    this.errorMessage = this.withValue(this.getString($r('app.string.unison_plus_switched_to')), summary.name);
  }

  @Builder
  buildConfigHint() {
    if (!this.settingModel.isByokConfigured()) {
      Column({ space: 6 }) {
        Text($r('app.string.unison_plus_missing_config'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)

        Text($r('app.string.unison_plus_config_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.background_secondary'))
      .borderRadius(this.settingModel.radiusCard)
    }
  }

  @Builder
  buildEmptyState() {
    Column({ space: 10 }) {
      Text($r('app.string.unison_plus_empty_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text($r('app.string.unison_plus_empty_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 32, bottom: 32 })
    .backgroundColor($r('app.color.background_card'))
    .borderRadius(this.settingModel.radiusCardLarge)
  }

  @Builder
  buildSectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  buildStatusBubble(message: UnisonDisplayMessage) {
    Row({ space: 8 }) {
      if (message.isLoading && !this.hasRenderableAssistantResult(message)) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('app.color.primary_color'))
      }
      Text(this.getStatusText(message))
        .layoutWeight(1)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(this.settingModel.radiusItem)
  }

  @Builder
  buildToolTimeline(message: UnisonDisplayMessage) {
    if (message.toolSteps.length > 0) {
      Column({ space: 8 }) {
        this.buildSectionTitle(this.getString($r('app.string.unison_plus_tool_timeline')))
        Repeat<UnisonToolStep>(message.toolSteps)
          .each((item: RepeatItem<UnisonToolStep>) => {
            Row({ space: 8 }) {
              Text(this.getToolNameText(item.item.toolName))
                .layoutWeight(1)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
              Text(this.getToolStepStateText(item.item.state))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.background_secondary'))
            .borderRadius(this.settingModel.radiusItem)
          })
          .key((item: UnisonToolStep) => `tool-step-${item.id}-${item.state}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildSourceResults(sources: UnisonSourceSummary[]) {
    if (sources.length > 0) {
      Column({ space: 8 }) {
        this.buildSectionTitle(this.getString($r('app.string.unison_plus_sources')))
        Repeat<UnisonSourceSummary>(sources)
          .each((item: RepeatItem<UnisonSourceSummary>) => {
            Column({ space: 6 }) {
              Row() {
                Text(item.item.name)
                  .layoutWeight(1)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                if (this.isSourceActive(item.item)) {
                  Text($r('app.string.unison_plus_source_switched'))
                    .fontSize(10)
                    .fontColor($r('app.color.label_text_color'))
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor($r('app.color.primary_color'))
                    .borderRadius(this.settingModel.radiusItem)
                }
              }
              .width('100%')

              Text(this.getSourceDescription(item.item))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(item.item.type)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.background_secondary'))
            .borderRadius(this.settingModel.radiusItem)
            .onClick(async () => {
              await this.switchMainSource(item.item);
            })
          })
          .key((item: UnisonSourceSummary) => `source-${item.id}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildSongResults(songs: Song[]) {
    if (songs.length > 0) {
      Column({ space: 4 }) {
        this.buildSectionTitle(this.getString($r('app.string.unison_plus_songs')))
        Repeat<Song>(songs)
          .each((item: RepeatItem<Song>) => {
            SongListItem({
              coverImage: cover(item.item.album?.cover, 96),
              songName: item.item.name,
              artistName: this.getSongArtistNames(item.item),
              duration: item.item.duration ?? 0,
              bgColor: $r('app.color.background_secondary'),
              coverRadius: this.settingModel.radiusCover,
              onItemClick: () => {
                this.playSong(item.item);
              },
            })
          })
          .key((item: Song) => `song-${item.sourceId}-${item.id}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildPlaylistResults(playlists: Playlist[]) {
    if (playlists.length > 0) {
      Column({ space: 4 }) {
        this.buildSectionTitle(this.getString($r('app.string.unison_plus_playlists')))
        Repeat<Playlist>(playlists)
          .each((item: RepeatItem<Playlist>) => {
            PlaylistListItem({
              coverImage: cover(item.item.cover, 96),
              playlistName: item.item.name,
              trackCount: item.item.size ?? 0,
              bgColor: $r('app.color.background_secondary'),
              coverRadius: this.settingModel.radiusCover,
              onItemClick: () => {
                this.openPlaylistDetail(item.item);
              },
            })
          })
          .key((item: Playlist) => `playlist-${item.sourceId}-${item.id}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildArtistResults(artists: Artist[]) {
    if (artists.length > 0) {
      Column({ space: 4 }) {
        this.buildSectionTitle(this.getString($r('app.string.unison_plus_artists')))
        Repeat<Artist>(artists)
          .each((item: RepeatItem<Artist>) => {
            ArtistListItem({
              coverImage: cover(item.item.avatar, 96),
              artistName: item.item.name,
              bgColor: $r('app.color.background_secondary'),
              coverRadius: this.settingModel.radiusCover,
              onItemClick: () => {
                this.openArtistDetail(item.item);
              },
            })
          })
          .key((item: Artist) => `artist-${item.sourceId}-${item.id}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildAlbumResults(albums: Album[]) {
    if (albums.length > 0) {
      Column({ space: 8 }) {
        this.buildSectionTitle(this.getString($r('app.string.unison_plus_albums')))
        Repeat<Album>(albums)
          .each((item: RepeatItem<Album>) => {
            PlaylistListItem({
              coverImage: cover(item.item.cover, 96),
              playlistName: item.item.name,
              trackCount: item.item.size ?? 0,
              bgColor: $r('app.color.background_secondary'),
              coverRadius: this.settingModel.radiusCover,
              onItemClick: () => {
                this.openAlbumDetail(item.item);
              },
            })
          })
          .key((item: Album) => `album-${item.sourceId}-${item.id}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildStructuredResults(message: UnisonDisplayMessage) {
    if (message.structuredItems.length > 0) {
      Column({ space: 8 }) {
        this.buildSectionTitle(this.getString($r('app.string.unison_plus_results')))
        Repeat<UnisonStructuredResultItem>(message.structuredItems)
          .each((item: RepeatItem<UnisonStructuredResultItem>) => {
            Row({ space: 12 }) {
              Image(cover(item.item.cover, 96))
                .width(52)
                .height(52)
                .borderRadius(this.settingModel.radiusCover)

              Column({ space: 6 }) {
                Text(item.item.name)
                  .width('100%')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if (item.item.hit.trim() !== '') {
                  Text(item.item.hit)
                    .width('100%')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.background_secondary'))
            .borderRadius(this.settingModel.radiusItem)
            .onClick(() => {
              this.openStructuredItem(message, item.item);
            })
          })
          .key((item: UnisonStructuredResultItem) => `structured-${item.type}-${item.id}-${item.name}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildLyricBlock(lyric: UnisonLyricPayload) {
    Column({ space: 10 }) {
      this.buildSectionTitle(this.getString($r('app.string.unison_plus_lyrics')))
      if (lyric.normal.trim() !== '') {
        Text(lyric.normal)
          .width('100%')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(20)
      } else {
        Text($r('app.string.unison_plus_no_lyric'))
          .width('100%')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      if (lyric.translation.trim() !== '') {
        Column({ space: 4 }) {
          Text($r('app.string.unison_plus_translation'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Text(lyric.translation)
            .width('100%')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(20)
        }
        .width('100%')
      }
      if (lyric.transliteration.trim() !== '') {
        Column({ space: 4 }) {
          Text($r('app.string.unison_plus_transliteration'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Text(lyric.transliteration)
            .width('100%')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(20)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(this.settingModel.radiusItem)
  }

  @Builder
  buildAssistantPayload(message: UnisonDisplayMessage) {
    if (this.hasPayload(message)) {
      Column({ space: 10 }) {
        this.buildSourceResults(message.sources)
        this.buildStructuredResults(message)
        if (message.lyric !== undefined) {
          this.buildLyricBlock(message.lyric!)
        }
      }
      .width('100%')
    }
  }

  @Builder
  buildAssistantContent(message: UnisonDisplayMessage) {
    if (message.content.trim() !== '') {
      Text(message.content)
        .width('100%')
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(22)
    }
    this.buildToolTimeline(message)
    this.buildAssistantPayload(message)
  }

  @Builder
  buildAssistantStatusMessage(message: UnisonDisplayMessage) {
    Row() {
      Column({ space: 10 }) {
        this.buildStatusBubble(message)
        this.buildToolTimeline(message)
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(this.settingModel.radiusCard)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  buildAssistantResultMessage(message: UnisonDisplayMessage) {
    Row() {
      Column({ space: 10 }) {
        this.buildAssistantContent(message)
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.background_card'))
      .borderRadius(this.settingModel.radiusCard)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  buildUserMessage(message: UnisonDisplayMessage) {
    Row() {
      Text(message.content)
        .fontSize(14)
        .fontColor($r('app.color.label_text_color'))
        .lineHeight(22)
        .padding(12)
        .backgroundColor($r('app.color.primary_color'))
        .borderRadius(this.settingModel.radiusCard)
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  buildMessageListItem(message: UnisonDisplayMessage) {
    ListItem() {
      if (message.role === 'user') {
        this.buildUserMessage(message)
      } else if (this.hasRenderableAssistantResult(message)) {
        this.buildAssistantResultMessage(message)
      } else {
        this.buildAssistantStatusMessage(message)
      }
    }
  }

  @Builder
  buildMessages() {
    List({ space: 12, scroller: this.listScroller }) {
      if (this.renderMessages.length === 0) {
        ListItem() {
          this.buildEmptyState()
        }
      } else {
        ForEach(this.renderMessages, (message: UnisonDisplayMessage) => {
          this.buildMessageListItem(message)
        }, (message: UnisonDisplayMessage): string => {
          return this.getMessageRenderKey(message);
        })
      }
    }
    .maintainVisibleContentPosition(true)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  buildErrorMessage() {
    if (this.errorMessage.trim() !== '') {
      Text(this.errorMessage)
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding(12)
        .backgroundColor($r('app.color.background_secondary'))
        .borderRadius(this.settingModel.radiusItem)
    }
  }

  @Builder
  buildComposer() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      TextArea({
        placeholder: $r('app.string.unison_plus_input_placeholder'),
        text: this.inputText,
      })
        .width('100%')
        .height(112)
        .padding({ left: 14, right: 64, top: 14, bottom: 14 })
        .backgroundColor($r('app.color.background_card'))
        .borderRadius(this.settingModel.radiusCard)
        .onChange((value: string) => {
          this.inputText = value;
        })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        if (this.isSending) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.label_text_color'))
        } else {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(20)
            .fontColor([this.canSend ? $r('app.color.label_text_color') : $r('app.color.text_disabled')])
        }
      }
      .width(44)
      .height(44)
      .margin({ right: 12, bottom: 12 })
      .backgroundColor(this.canSend ? $r('app.color.primary_color') : $r('app.color.button_secondary'))
      .enabled(this.canSend)
      .onClick(async () => {
        await this.submitMessage();
      })
    }
    .width('100%')
  }

  private async submitMessage(): Promise<void> {
    if (!this.canSend) {
      return;
    }

    const input: string = this.inputText.trim();
    const history: UnisonDisplayMessage[] = this.messages.slice();
    this.inputText = '';
    this.errorMessage = '';
    this.isSending = true;

    try {
      const result: UnisonAgentResult = await this.agentService.run(input, history, (messages: UnisonDisplayMessage[]) => {
        const normalizedMessages: UnisonDisplayMessage[] = this.applyMessages(messages);
        this.logLatestMessageState('onProgress', normalizedMessages);
        this.scrollToBottom();
      });
      const finalMessages: UnisonDisplayMessage[] = this.applyMessages(result.displayMessages);
      this.logLatestMessageState('finalResult', finalMessages);
      this.errorMessage = result.errorMessage;
      this.scrollToBottom();
    } finally {
      this.isSending = false;
      const finalMessages: UnisonDisplayMessage[] = this.applyMessages(this.messages);
      this.logLatestMessageState('finally', finalMessages);
    }
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        this.buildConfigHint()
        this.buildMessages()
        this.buildErrorMessage()
        this.buildComposer()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_primary'))
    }
    .margin({
      bottom: this.windowProperties.bottomRect,
      top: this.windowProperties.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? this.windowProperties.topRect + 64 : 100,
      left: 24,
      right: 24,
    })
  }
}