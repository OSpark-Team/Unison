import { PersistenceV2 } from '@kit.ArkUI';
import { Album } from '../../model/adapter/Album';
import { Artist } from '../../model/adapter/Artist';
import { Playlist } from '../../model/adapter/Playlist';
import { Song } from '../../model/adapter/Song';
import Logger from '../../utils/Logger';
import { resourceUtil } from '../../utils/ResourceUtil';
import SettingViewModel from '../../viewmodel/SettingViewModel';
import { UnisonPlusRequest } from './UnisonPlusRequest';
import { UnisonToolRegistry } from './UnisonToolRegistry';
import { UnisonToolExecutor } from './UnisonToolExecutor';
import {
  OpenAIChatRequest,
  OpenAIChatResponse,
  OpenAIToolCall,
  UnisonAgentResult,
  UnisonDisplayMessage,
  UnisonLyricPayload,
  UnisonOpenAIMessage,
  UnisonSourceSummary,
  UnisonStructuredAssistantResponse,
  UnisonStructuredResponseCodec,
  UnisonStructuredResultItem,
  UnisonToolArguments,
  UnisonToolExecutionResult,
  UnisonToolStep,
} from './UnisonToolTypes';

const TAG = 'UnisonAgentService';
const MAX_TOOL_CALL_ROUNDS = 6;

export class UnisonAgentService {
  private toolExecutor: UnisonToolExecutor = new UnisonToolExecutor();

  private getString(res: Resource): string {
    return resourceUtil.getAppString(res, '');
  }

  private normalizeErrorMessage(message: string): string {
    if (message.startsWith('Error: ')) {
      return message.slice(7);
    }
    return message;
  }

  private getSongCountText(count: number): string {
    const suffix: string = this.getString($r('app.string.unison_plus_song_count_suffix')).trim();
    if (suffix === '') {
      return `${count}`;
    }
    const firstChar: string = suffix.charAt(0);
    const isLatinWord: boolean = (firstChar >= 'A' && firstChar <= 'Z') || (firstChar >= 'a' && firstChar <= 'z');
    if (isLatinWord) {
      return `${count} ${suffix}`;
    }
    return `${count}${suffix}`;
  }

  private getSettingViewModel(): SettingViewModel {
    return PersistenceV2.connect(SettingViewModel, 'SettingViewModel', () => new SettingViewModel())!;
  }

  private replaceText(value: string, search: string, replacement: string): string {
    return value.split(search).join(replacement);
  }

  private escapeXml(value: string): string {
    let escaped: string = value;
    escaped = this.replaceText(escaped, '&', '&amp;');
    escaped = this.replaceText(escaped, '<', '&lt;');
    escaped = this.replaceText(escaped, '>', '&gt;');
    escaped = this.replaceText(escaped, '"', '&quot;');
    escaped = this.replaceText(escaped, "'", '&apos;');
    return escaped;
  }

  private buildSystemPrompt(): string {
    return '<unison_system>' +
      '<role>You are Unison+, an AI assistant inside a HarmonyOS music app.</role>' +
      '<mission>Use tools when real music data is needed, and keep working across multiple tool rounds until you can give a useful final answer.</mission>' +
      '<tool_rules>' +
      '<rule>For switching the default source, call list_sources before set_main_source.</rule>' +
      '<rule>For lyrics, call search_music first to get the exact song id, then call get_song_lyric.</rule>' +
      '<rule>For songs, playlists, artists, albums, and search results, prefer tool data over guessing.</rule>' +
      '<rule>Never invent sourceId, song ids, playlist ids, artist ids, album ids, or source metadata.</rule>' +
      '<rule>The list_sources tool is already sanitized. Never ask the user to reveal tokens or credentials.</rule>' +
      '<rule>If a tool fails, use the failure details to recover or explain the limitation clearly.</rule>' +
      '</tool_rules>' +
      '<language_policy>' +
      '<rule>If the user explicitly requests a target language, use that language.</rule>' +
      '<rule>Otherwise, answer in the language of the latest user message.</rule>' +
      '<rule>Keep the final answer concise and natural.</rule>' +
      '</language_policy>' +
      '<output_rules>' +
      '<rule>If structured cards are likely to be rendered, do not repeat the full result list in prose.</rule>' +
      '<rule>Give a short summary instead of a long enumeration.</rule>' +
      '<rule>Do not output raw cover URLs in the final answer.</rule>' +
      '</output_rules>' +
      '</unison_system>';
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

  private cloneToolStep(step: UnisonToolStep): UnisonToolStep {
    const copy: UnisonToolStep = new UnisonToolStep();
    copy.id = step.id;
    copy.toolName = step.toolName;
    copy.state = step.state;
    return copy;
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

  private emitProgress(messages: UnisonDisplayMessage[], onProgress?: (messages: UnisonDisplayMessage[]) => void): void {
    if (!onProgress) {
      return;
    }
    onProgress(this.cloneDisplayMessages(messages));
  }

  private buildToolStepsSummary(message: UnisonDisplayMessage): string {
    let summary: string = '';
    for (let i: number = 0; i < message.toolSteps.length; i++) {
      if (i > 0) {
        summary = `${summary}|`;
      }
      summary = `${summary}${message.toolSteps[i].toolName}:${message.toolSteps[i].state}`;
    }
    return summary;
  }

  private logMessageState(stage: string, message: UnisonDisplayMessage): void {
    Logger.info(TAG,
      `${stage}: loading=${message.isLoading}, status=${message.status}, statusValue=${message.statusValue}, ` +
      `contentLength=${message.content.length}, toolSteps=${this.buildToolStepsSummary(message)}, ` +
      `sources=${message.sources.length}, playlists=${message.playlists.length}, songs=${message.songs.length}, ` +
      `artists=${message.artists.length}, albums=${message.albums.length}, structured=${message.structuredItems.length}, ` +
      `lyric=${message.lyric === undefined ? 'no' : 'yes'}`);
  }

  private buildDisplayMessageId(role: string): string {
    return `${role}_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
  }

  private buildConversation(history: UnisonDisplayMessage[], userInput: string): UnisonOpenAIMessage[] {
    const messages: UnisonOpenAIMessage[] = [];
    messages.push({
      role: 'system',
      content: this.buildSystemPrompt(),
    });

    for (let i: number = 0; i < history.length; i++) {
      const item: UnisonDisplayMessage = history[i];
      if (item.content.trim() === '') {
        continue;
      }
      messages.push({
        role: item.role,
        content: item.content,
      });
    }

    messages.push({
      role: 'user',
      content: userInput,
    });
    return messages;
  }

  private getAssistantMessage(response: OpenAIChatResponse): UnisonOpenAIMessage {
    if (!response.choices || response.choices.length === 0) {
      throw new Error(this.getString($r('app.string.unison_plus_no_model_result')));
    }
    return response.choices[0].message;
  }

  private tryParseToolArguments(argsText: string): UnisonToolArguments {
    if (argsText.trim() === '') {
      return new UnisonToolArguments();
    }

    try {
      return JSON.parse(argsText) as UnisonToolArguments;
    } catch (_error) {
      return new UnisonToolArguments();
    }
  }

  private setAssistantStatus(message: UnisonDisplayMessage, status: string, statusValue: string = ''): void {
    message.isLoading = true;
    message.status = status;
    message.statusValue = statusValue;
  }

  private createLoadingMessage(): UnisonDisplayMessage {
    const message: UnisonDisplayMessage = new UnisonDisplayMessage(this.buildDisplayMessageId('assistant'), 'assistant', '');
    message.isLoading = true;
    message.status = 'thinking';
    return message;
  }

  private appendToolStep(message: UnisonDisplayMessage, toolName: string): UnisonToolStep {
    const step: UnisonToolStep = new UnisonToolStep();
    step.id = this.buildDisplayMessageId(toolName);
    step.toolName = toolName;
    step.state = 'running';
    message.toolSteps.push(step);
    return step;
  }

  private findSourceIndex(target: UnisonSourceSummary[], sourceId: string): number {
    for (let i: number = 0; i < target.length; i++) {
      if (target[i].id === sourceId) {
        return i;
      }
    }
    return -1;
  }

  private mergeSources(target: UnisonSourceSummary[], incoming: UnisonSourceSummary[]): void {
    for (let i: number = 0; i < incoming.length; i++) {
      const index: number = this.findSourceIndex(target, incoming[i].id);
      const sourceCopy: UnisonSourceSummary = this.cloneSourceSummary(incoming[i]);
      if (index >= 0) {
        target[index] = sourceCopy;
      } else {
        target.push(sourceCopy);
      }
    }
  }

  private hasPlaylist(target: Playlist[], playlist: Playlist): boolean {
    for (let i: number = 0; i < target.length; i++) {
      if (String(target[i].id) === String(playlist.id) && target[i].sourceId === playlist.sourceId) {
        return true;
      }
    }
    return false;
  }

  private hasSong(target: Song[], song: Song): boolean {
    for (let i: number = 0; i < target.length; i++) {
      if (String(target[i].id) === String(song.id) && target[i].sourceId === song.sourceId) {
        return true;
      }
    }
    return false;
  }

  private hasArtist(target: Artist[], artist: Artist): boolean {
    for (let i: number = 0; i < target.length; i++) {
      if (String(target[i].id) === String(artist.id) && target[i].sourceId === artist.sourceId) {
        return true;
      }
    }
    return false;
  }

  private hasAlbum(target: Album[], album: Album): boolean {
    for (let i: number = 0; i < target.length; i++) {
      if (String(target[i].id) === String(album.id) && target[i].sourceId === album.sourceId) {
        return true;
      }
    }
    return false;
  }

  private mergePlaylists(target: Playlist[], incoming: Playlist[]): void {
    for (let i: number = 0; i < incoming.length; i++) {
      if (!this.hasPlaylist(target, incoming[i])) {
        target.push(incoming[i]);
      }
    }
  }

  private mergeSongs(target: Song[], incoming: Song[]): void {
    for (let i: number = 0; i < incoming.length; i++) {
      if (!this.hasSong(target, incoming[i])) {
        target.push(incoming[i]);
      }
    }
  }

  private mergeArtists(target: Artist[], incoming: Artist[]): void {
    for (let i: number = 0; i < incoming.length; i++) {
      if (!this.hasArtist(target, incoming[i])) {
        target.push(incoming[i]);
      }
    }
  }

  private mergeAlbums(target: Album[], incoming: Album[]): void {
    for (let i: number = 0; i < incoming.length; i++) {
      if (!this.hasAlbum(target, incoming[i])) {
        target.push(incoming[i]);
      }
    }
  }

  private mergeToolPayload(message: UnisonDisplayMessage, toolResult: UnisonToolExecutionResult): void {
    this.mergeSources(message.sources, toolResult.payload.sources);
    this.mergePlaylists(message.playlists, toolResult.payload.playlists);
    this.mergeSongs(message.songs, toolResult.payload.songs);
    this.mergeArtists(message.artists, toolResult.payload.artists);
    this.mergeAlbums(message.albums, toolResult.payload.albums);

    if (toolResult.payload.lyric) {
      message.lyric = this.cloneLyricPayload(toolResult.payload.lyric);
    }
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

  private buildPlaylistHit(playlist: Playlist): string {
    const description: string = playlist.description?.trim() ?? '';
    if (description !== '') {
      return description;
    }

    const creatorName: string = playlist.creator?.name?.trim() ?? '';
    const size: number = playlist.size ?? 0;
    if (creatorName !== '' && size > 0) {
      return `${creatorName} · ${this.getSongCountText(size)}`;
    }
    if (creatorName !== '') {
      return creatorName;
    }
    if (size > 0) {
      return this.getSongCountText(size);
    }
    return '';
  }

  private buildAlbumHit(album: Album): string {
    const artistNames: string = this.joinArtistNames(album.artists);
    if (artistNames !== '') {
      return artistNames;
    }

    const size: number = album.size ?? 0;
    if (size > 0) {
      return this.getSongCountText(size);
    }
    return '';
  }

  private buildStructuredSongItem(song: Song): UnisonStructuredResultItem {
    const item: UnisonStructuredResultItem = new UnisonStructuredResultItem();
    item.type = 'song';
    item.id = String(song.id);
    item.name = song.name ?? '';
    item.cover = song.album?.cover ?? '';
    item.hit = this.joinArtistNames(song.artists);
    return item;
  }

  private buildStructuredPlaylistItem(playlist: Playlist): UnisonStructuredResultItem {
    const item: UnisonStructuredResultItem = new UnisonStructuredResultItem();
    item.type = 'playlist';
    item.id = String(playlist.id);
    item.name = playlist.name ?? '';
    item.cover = playlist.cover ?? '';
    item.hit = this.buildPlaylistHit(playlist);
    return item;
  }

  private buildStructuredArtistItem(artist: Artist): UnisonStructuredResultItem {
    const item: UnisonStructuredResultItem = new UnisonStructuredResultItem();
    item.type = 'artist';
    item.id = String(artist.id);
    item.name = artist.name;
    item.cover = artist.avatar ?? '';
    item.hit = '';
    return item;
  }

  private buildStructuredAlbumItem(album: Album): UnisonStructuredResultItem {
    const item: UnisonStructuredResultItem = new UnisonStructuredResultItem();
    item.type = 'album';
    item.id = String(album.id);
    item.name = album.name;
    item.cover = album.cover ?? '';
    item.hit = this.buildAlbumHit(album);
    return item;
  }

  private buildStructuredCandidateItems(message: UnisonDisplayMessage): UnisonStructuredResultItem[] {
    const items: UnisonStructuredResultItem[] = [];

    for (let i: number = 0; i < message.songs.length; i++) {
      items.push(this.buildStructuredSongItem(message.songs[i]));
    }
    for (let i: number = 0; i < message.playlists.length; i++) {
      items.push(this.buildStructuredPlaylistItem(message.playlists[i]));
    }
    for (let i: number = 0; i < message.artists.length; i++) {
      items.push(this.buildStructuredArtistItem(message.artists[i]));
    }
    for (let i: number = 0; i < message.albums.length; i++) {
      items.push(this.buildStructuredAlbumItem(message.albums[i]));
    }

    return items;
  }

  private hasStructuredIdentity(target: UnisonStructuredResultItem[], item: UnisonStructuredResultItem): boolean {
    for (let i: number = 0; i < target.length; i++) {
      if (target[i].type === item.type && target[i].id === item.id) {
        return true;
      }
    }
    return false;
  }

  private findStructuredCandidate(candidates: UnisonStructuredResultItem[], item: UnisonStructuredResultItem):
    UnisonStructuredResultItem | null {
    for (let i: number = 0; i < candidates.length; i++) {
      if (candidates[i].type === item.type && candidates[i].id === item.id && candidates[i].name === item.name) {
        return candidates[i];
      }
    }

    for (let i: number = 0; i < candidates.length; i++) {
      if (candidates[i].type === item.type && candidates[i].id === item.id) {
        return candidates[i];
      }
    }
    return null;
  }

  private buildValidatedStructuredItems(message: UnisonDisplayMessage,
    structuredResponse: UnisonStructuredAssistantResponse): UnisonStructuredResultItem[] {
    const candidates: UnisonStructuredResultItem[] = this.buildStructuredCandidateItems(message);
    const validated: UnisonStructuredResultItem[] = [];

    for (let i: number = 0; i < structuredResponse.items.length; i++) {
      const candidate: UnisonStructuredResultItem | null =
        this.findStructuredCandidate(candidates, structuredResponse.items[i]);
      if (candidate === null) {
        Logger.warn(TAG,
          `structured_candidate_rejected: ${structuredResponse.items[i].type}:${structuredResponse.items[i].id}:` +
          `${structuredResponse.items[i].name}`);
        continue;
      }
      if (this.hasStructuredIdentity(validated, candidate)) {
        continue;
      }
      validated.push(this.cloneStructuredItem(candidate));
    }

    return validated;
  }

  private shouldUseStructuredResponse(message: UnisonDisplayMessage): boolean {
    if (message.lyric !== undefined) {
      return false;
    }

    return message.songs.length > 0 || message.playlists.length > 0 ||
      message.artists.length > 0 || message.albums.length > 0;
  }

  private buildStructuredFormatterSystemPrompt(): string {
    return '<unison_structured_formatter>' +
      '<role>You format verified tool results into JSON for card rendering.</role>' +
      '<hard_rules>' +
      '<rule>Return JSON only. Do not output markdown, explanations, or extra text.</rule>' +
      '<rule>Every item must be copied from the provided candidates only.</rule>' +
      '<rule>Never invent, infer, merge, translate, normalize, or repair any item field.</rule>' +
      '<rule>The type and id of each item must come from the same original candidate.</rule>' +
      '<rule>If an item is not a direct candidate match, omit it.</rule>' +
      '<rule>If cards are not needed, return an empty items array.</rule>' +
      '</hard_rules>' +
      '<language_policy>' +
      '<rule>If the user explicitly requests a target language, use that language for displayText.</rule>' +
      '<rule>Otherwise, use the language of the latest user message for displayText.</rule>' +
      '<rule>Keep displayText concise.</rule>' +
      '</language_policy>' +
      '<selection_rules>' +
      '<rule>Keep only the most relevant items for interaction.</rule>' +
      '<rule>Preserve candidate meaning exactly.</rule>' +
      '<rule>Do not restate the full list in displayText when items already cover it.</rule>' +
      '</selection_rules>' +
      '</unison_structured_formatter>';
  }

  private buildStructuredFormatterUserMessage(userInput: string, message: UnisonDisplayMessage): string {
    const candidateItems: UnisonStructuredResultItem[] = this.buildStructuredCandidateItems(message);
    return '<formatter_request>' +
      `<latest_user_message>${this.escapeXml(userInput)}</latest_user_message>` +
      '<task>Select only the best candidates for interactive cards and produce the final structured JSON.</task>' +
      '<candidate_rules>' +
      '<rule>Copy fields exactly from the candidate list.</rule>' +
      '<rule>Do not mix the type from one candidate with the id from another candidate.</rule>' +
      '<rule>Do not invent missing ids or types.</rule>' +
      '</candidate_rules>' +
      `<candidate_count>${candidateItems.length}</candidate_count>` +
      `<candidate_items_json>${this.escapeXml(JSON.stringify(candidateItems))}</candidate_items_json>` +
      '</formatter_request>';
  }

  private async requestStructuredResponse(settingViewModel: SettingViewModel, userInput: string,
    message: UnisonDisplayMessage): Promise<UnisonStructuredAssistantResponse> {
    const request: OpenAIChatRequest = {
      model: settingViewModel.byokApiModel.trim(),
      messages: [
        {
          role: 'system',
          content: this.buildStructuredFormatterSystemPrompt(),
        },
        {
          role: 'user',
          content: this.buildStructuredFormatterUserMessage(userInput, message),
        },
      ],
      response_format: UnisonStructuredResponseCodec.createResponseFormat(),
      temperature: 0.2,
    };

    const response: OpenAIChatResponse = await UnisonPlusRequest.ChatCompletions(
      settingViewModel.byokApiBase.trim(),
      settingViewModel.byokApiKey.trim(),
      request,
    );
    const assistantMessage: UnisonOpenAIMessage = this.getAssistantMessage(response);
    const content: string = assistantMessage.content?.trim() ?? '';
    if (content === '') {
      throw new Error(this.getString($r('app.string.unison_plus_empty_structured_response')));
    }
    return UnisonStructuredResponseCodec.parse(content);
  }

  private applyStructuredResponse(message: UnisonDisplayMessage,
    structuredResponse: UnisonStructuredAssistantResponse): void {
    this.finalizeAssistantMessage(message, structuredResponse.displayText);
    message.structuredItems = [];
    const validatedItems: UnisonStructuredResultItem[] = this.buildValidatedStructuredItems(message, structuredResponse);
    for (let i: number = 0; i < validatedItems.length; i++) {
      message.structuredItems.push(this.cloneStructuredItem(validatedItems[i]));
    }
    this.logMessageState('structured_applied', message);
  }

  private updateStatusForTool(message: UnisonDisplayMessage, toolName: string, argsText: string): void {
    const args: UnisonToolArguments = this.tryParseToolArguments(argsText);
    if (toolName === 'search_music') {
      this.setAssistantStatus(message, 'searching', args.keywords ?? '');
      return;
    }
    if (toolName === 'get_song_lyric') {
      this.setAssistantStatus(message, 'fetching_lyric', args.id === undefined ? '' : String(args.id));
      return;
    }
    this.setAssistantStatus(message, 'calling_tool', toolName);
  }

  private finalizeAssistantMessage(message: UnisonDisplayMessage, content: string): void {
    message.isLoading = false;
    message.status = '';
    message.statusValue = '';
    if (content.trim() === '') {
      message.content = this.getString($r('app.string.unison_plus_no_display_content'));
      return;
    }
    message.content = content;
  }

  private markAssistantError(message: UnisonDisplayMessage, status: string, statusValue: string = ''): void {
    message.isLoading = false;
    message.content = '';
    message.status = status;
    message.statusValue = statusValue;
  }

  public async run(userInput: string, history: UnisonDisplayMessage[],
    onProgress?: (messages: UnisonDisplayMessage[]) => void): Promise<UnisonAgentResult> {
    const result: UnisonAgentResult = new UnisonAgentResult();
    const displayMessages: UnisonDisplayMessage[] = this.cloneDisplayMessages(history);
    displayMessages.push(new UnisonDisplayMessage(this.buildDisplayMessageId('user'), 'user', userInput));
    result.displayMessages = displayMessages;

    const settingViewModel: SettingViewModel = this.getSettingViewModel();
    if (!settingViewModel.isByokConfigured()) {
      result.errorMessage = this.getString($r('app.string.unison_plus_config_hint'));
      result.displayMessages.push(new UnisonDisplayMessage(this.buildDisplayMessageId('assistant'), 'assistant',
        result.errorMessage));
      this.emitProgress(result.displayMessages, onProgress);
      return result;
    }

    const loadingMessage: UnisonDisplayMessage = this.createLoadingMessage();
    displayMessages.push(loadingMessage);
    this.emitProgress(displayMessages, onProgress);

    const conversation: UnisonOpenAIMessage[] = this.buildConversation(history, userInput);
    result.conversation = conversation;

    try {
      let assistantContent: string = '';
      for (let round: number = 0; round < MAX_TOOL_CALL_ROUNDS; round++) {
        this.setAssistantStatus(loadingMessage, 'thinking');
        this.emitProgress(displayMessages, onProgress);

        const request: OpenAIChatRequest = {
          model: settingViewModel.byokApiModel.trim(),
          messages: conversation,
          tools: UnisonToolRegistry.getTools(),
          tool_choice: 'auto',
          temperature: 0.3,
        };

        const response: OpenAIChatResponse = await UnisonPlusRequest.ChatCompletions(
          settingViewModel.byokApiBase.trim(),
          settingViewModel.byokApiKey.trim(),
          request,
        );
        const assistantMessage: UnisonOpenAIMessage = this.getAssistantMessage(response);
        conversation.push(assistantMessage);

        if (assistantMessage.tool_calls && assistantMessage.tool_calls.length > 0) {
          for (let i: number = 0; i < assistantMessage.tool_calls.length; i++) {
            const toolCall: OpenAIToolCall = assistantMessage.tool_calls[i];
            const toolStep: UnisonToolStep = this.appendToolStep(loadingMessage, toolCall.function.name);
            this.updateStatusForTool(loadingMessage, toolCall.function.name, toolCall.function.arguments);
            this.emitProgress(displayMessages, onProgress);

            const toolResult: UnisonToolExecutionResult = await this.toolExecutor.execute(
              toolCall.function.name,
              toolCall.function.arguments,
              toolCall.id,
            );
            toolStep.state = toolResult.success ? 'success' : 'failed';
            this.mergeToolPayload(loadingMessage, toolResult);
            this.logMessageState(`tool_completed:${toolCall.function.name}`, loadingMessage);
            conversation.push({
              role: 'tool',
              tool_call_id: toolResult.toolCallId,
              name: toolResult.toolName,
              content: toolResult.content,
            });
            this.emitProgress(displayMessages, onProgress);
          }
          continue;
        }

        assistantContent = assistantMessage.content?.trim() ?? '';
        if (this.shouldUseStructuredResponse(loadingMessage)) {
          this.setAssistantStatus(loadingMessage, 'thinking');
          this.emitProgress(displayMessages, onProgress);
          const structuredResponse: UnisonStructuredAssistantResponse = await this.requestStructuredResponse(
            settingViewModel,
            userInput,
            loadingMessage,
          );
          this.applyStructuredResponse(loadingMessage, structuredResponse);
        } else {
          this.finalizeAssistantMessage(loadingMessage, assistantContent);
          this.logMessageState('assistant_finalized', loadingMessage);
        }
        result.assistantContent = loadingMessage.content;
        result.displayMessages = this.cloneDisplayMessages(displayMessages);
        result.conversation = conversation;
        this.logMessageState('before_return', loadingMessage);
        this.emitProgress(displayMessages, onProgress);
        return result;
      }

      result.errorMessage = this.getString($r('app.string.unison_plus_round_limit'));
      this.markAssistantError(loadingMessage, 'round_limit');
      this.logMessageState('round_limit', loadingMessage);
      result.displayMessages = this.cloneDisplayMessages(displayMessages);
      result.conversation = conversation;
      this.emitProgress(displayMessages, onProgress);
      return result;
    } catch (error) {
      const message: string = this.normalizeErrorMessage(`${error}`);
      Logger.error(TAG, message);
      result.errorMessage = message;
      this.markAssistantError(loadingMessage, 'request_failed', message);
      this.logMessageState('request_failed', loadingMessage);
      result.displayMessages = this.cloneDisplayMessages(displayMessages);
      result.conversation = conversation;
      this.emitProgress(displayMessages, onProgress);
      return result;
    }
  }
}