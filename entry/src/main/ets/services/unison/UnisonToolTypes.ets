import { Playlist } from '../../model/adapter/Playlist';
import { Song } from '../../model/adapter/Song';
import { Artist } from '../../model/adapter/Artist';
import { Album } from '../../model/adapter/Album';

export interface OpenAIJsonProperty {
  type: string;
  description: string;
}

export interface OpenAIJsonEnumProperty {
  type: string;
  enum: string[];
  description: string;
}

export interface OpenAIJsonProperties {
  sourceId?: OpenAIJsonProperty;
  uid?: OpenAIJsonProperty;
  id?: OpenAIJsonProperty;
  keywords?: OpenAIJsonProperty;
  limit?: OpenAIJsonProperty;
  offset?: OpenAIJsonProperty;
}

export interface OpenAIJsonSchema {
  type: string;
  properties: OpenAIJsonProperties;
  required?: string[];
  additionalProperties?: boolean;
}

export interface OpenAIStructuredResultItemSchemaProperties {
  type: OpenAIJsonEnumProperty;
  id: OpenAIJsonProperty;
  name: OpenAIJsonProperty;
  cover: OpenAIJsonProperty;
  hit: OpenAIJsonProperty;
}

export interface OpenAIStructuredResultItemSchema {
  type: string;
  properties: OpenAIStructuredResultItemSchemaProperties;
  required: string[];
  additionalProperties: boolean;
}

export interface OpenAIJsonArrayProperty {
  type: string;
  items: OpenAIStructuredResultItemSchema;
  description: string;
}

export interface OpenAIStructuredAssistantSchemaProperties {
  displayText: OpenAIJsonProperty;
  items: OpenAIJsonArrayProperty;
}

export interface OpenAIStructuredAssistantSchema {
  type: string;
  properties: OpenAIStructuredAssistantSchemaProperties;
  required: string[];
  additionalProperties: boolean;
}

export interface OpenAIResponseJsonSchema {
  name: string;
  strict: boolean;
  schema: OpenAIStructuredAssistantSchema;
}

export interface OpenAIResponseFormat {
  type: string;
  json_schema: OpenAIResponseJsonSchema;
}

export interface OpenAIToolFunction {
  name: string;
  description: string;
  parameters: OpenAIJsonSchema;
}

export interface OpenAIToolDefinition {
  type: string;
  function: OpenAIToolFunction;
}

export interface OpenAIToolFunctionCall {
  name: string;
  arguments: string;
}

export interface OpenAIToolCall {
  id: string;
  type: string;
  function: OpenAIToolFunctionCall;
}

export interface UnisonOpenAIMessage {
  role: string;
  content?: string;
  name?: string;
  tool_call_id?: string;
  tool_calls?: OpenAIToolCall[];
}

export interface OpenAIChatRequest {
  model: string;
  messages: UnisonOpenAIMessage[];
  tools?: OpenAIToolDefinition[];
  tool_choice?: string;
  temperature?: number;
  response_format?: OpenAIResponseFormat;
}

export interface OpenAIChatChoice {
  index: number;
  message: UnisonOpenAIMessage;
  finish_reason?: string;
}

export interface OpenAIChatResponse {
  id?: string;
  choices?: OpenAIChatChoice[];
  error?: OpenAIChatError;
}

export interface OpenAIChatError {
  message?: string;
}

export class UnisonToolArguments {
  sourceId?: string = undefined;
  uid?: number | string = undefined;
  id?: number | string = undefined;
  keywords?: string = undefined;
  limit?: number = undefined;
  offset?: number = undefined;
}

export class UnisonToolExecutionResult {
  toolCallId: string = '';
  toolName: string = '';
  content: string = '';
  success: boolean = false;
  payload: UnisonToolPayload = new UnisonToolPayload();
}

@ObservedV2
export class UnisonToolStep {
  @Trace id: string = '';
  @Trace toolName: string = '';
  @Trace state: string = 'running';
}

export class UnisonStructuredResultItem {
  type: string = 'song';
  id: string = '';
  name: string = '';
  cover: string = '';
  hit: string = '';
}

export class UnisonStructuredAssistantResponse {
  displayText: string = '';
  items: UnisonStructuredResultItem[] = [];
}

interface UnisonStructuredResultItemPayload {
  type?: string;
  id?: string;
  name?: string;
  cover?: string;
  hit?: string;
}

interface UnisonStructuredAssistantResponsePayload {
  displayText?: string;
  items?: UnisonStructuredResultItemPayload[];
}

export class UnisonStructuredResponseCodec {
  public static createResponseFormat(): OpenAIResponseFormat {
    return {
      type: 'json_schema',
      json_schema: {
        name: 'unison_structured_response',
        strict: true,
        schema: {
          type: 'object',
          properties: {
            displayText: {
              type: 'string',
              description: 'A short user facing summary. It may include the next suggested action.',
            },
            items: {
              type: 'array',
              description: 'A list of results that will be rendered as interactive cards.',
              items: {
                type: 'object',
                properties: {
                  type: {
                    type: 'string',
                    enum: ['song', 'playlist', 'artist', 'album'],
                    description: 'The result type.',
                  },
                  id: {
                    type: 'string',
                    description: 'The result id.',
                  },
                  name: {
                    type: 'string',
                    description: 'The display name.',
                  },
                  cover: {
                    type: 'string',
                    description: 'The cover or avatar URL. Return an empty string when unavailable.',
                  },
                  hit: {
                    type: 'string',
                    description: 'The subtitle text for the card. Return an empty string when unavailable.',
                  },
                },
                required: ['type', 'id', 'name', 'cover', 'hit'],
                additionalProperties: false,
              },
            },
          },
          required: ['displayText', 'items'],
          additionalProperties: false,
        },
      },
    };
  }

  public static parse(content: string): UnisonStructuredAssistantResponse {
    const parsed: UnisonStructuredAssistantResponsePayload =
      JSON.parse(content) as UnisonStructuredAssistantResponsePayload;
    const response: UnisonStructuredAssistantResponse = new UnisonStructuredAssistantResponse();
    response.displayText = parsed.displayText?.trim() ?? '';

    if (parsed.items) {
      for (let i: number = 0; i < parsed.items.length; i++) {
        const item: UnisonStructuredResultItem | null = UnisonStructuredResponseCodec.parseItem(parsed.items[i]);
        if (item !== null) {
          response.items.push(item);
        }
      }
    }

    return response;
  }

  private static parseItem(payload: UnisonStructuredResultItemPayload): UnisonStructuredResultItem | null {
    const type: string = payload.type?.trim() ?? '';
    if (type !== 'song' && type !== 'playlist' && type !== 'artist' && type !== 'album') {
      return null;
    }

    const id: string = payload.id?.trim() ?? '';
    const name: string = payload.name?.trim() ?? '';
    if (id === '' || name === '') {
      return null;
    }

    const item: UnisonStructuredResultItem = new UnisonStructuredResultItem();
    item.type = type;
    item.id = id;
    item.name = name;
    item.cover = payload.cover?.trim() ?? '';
    item.hit = payload.hit?.trim() ?? '';
    return item;
  }
}

export class UnisonSourceSummary {
  id: string = '';
  name: string = '';
  type: string = '';
  url: string = '';
  description: string = '';
  userId: string = '';
  userName: string = '';
  authorized: boolean = false;
  isMain: boolean = false;
}

export class UnisonPlaylistSummary {
  id: string = '';
  name: string = '';
  cover: string = '';
  size: number = 0;
  creatorName: string = '';
  description: string = '';
  sourceId: string = '';
}

export class UnisonSongSummary {
  id: string = '';
  name: string = '';
  artistNames: string = '';
  albumName: string = '';
  duration: number = 0;
  sourceId: string = '';
}

export class UnisonArtistSummary {
  id: string = '';
  name: string = '';
  avatar: string = '';
  sourceId: string = '';
}

export class UnisonAlbumSummary {
  id: string = '';
  name: string = '';
  cover: string = '';
  artistNames: string = '';
  size: number = 0;
  sourceId: string = '';
}

export class UnisonLyricPayload {
  sourceId: string = '';
  songId: string = '';
  normal: string = '';
  translation: string = '';
  transliteration: string = '';
}

export class UnisonToolPayload {
  sources: UnisonSourceSummary[] = [];
  playlists: Playlist[] = [];
  songs: Song[] = [];
  artists: Artist[] = [];
  albums: Album[] = [];
  lyric?: UnisonLyricPayload = undefined;
}

export class UnisonListSourcesResponse {
  success: boolean = false;
  message: string = '';
  mainSourceId: string = '';
  sources: UnisonSourceSummary[] = [];
}

export class UnisonSetMainSourceResponse {
  success: boolean = false;
  message: string = '';
  mainSourceId: string = '';
  source?: UnisonSourceSummary = undefined;
}

export class UnisonGetUserPlaylistsResponse {
  success: boolean = false;
  message: string = '';
  sourceId: string = '';
  uid: string = '';
  playlists: UnisonPlaylistSummary[] = [];
}

export class UnisonGetSongLyricResponse {
  success: boolean = false;
  message: string = '';
  sourceId: string = '';
  songId: string = '';
  lyric?: UnisonLyricPayload = undefined;
}

export class UnisonSearchMusicResponse {
  success: boolean = false;
  message: string = '';
  sourceId: string = '';
  keywords: string = '';
  songs: UnisonSongSummary[] = [];
  playlists: UnisonPlaylistSummary[] = [];
  artists: UnisonArtistSummary[] = [];
  albums: UnisonAlbumSummary[] = [];
}

export class UnisonFailureResponse {
  success: boolean = false;
  message: string = '';
}

@ObservedV2
export class UnisonDisplayMessage {
  @Trace id: string = '';
  @Trace role: string = 'assistant';
  @Trace content: string = '';
  @Trace isLoading: boolean = false;
  @Trace status: string = '';
  @Trace statusValue: string = '';
  @Trace toolSteps: UnisonToolStep[] = [];
  @Trace sources: UnisonSourceSummary[] = [];
  @Trace playlists: Playlist[] = [];
  @Trace songs: Song[] = [];
  @Trace artists: Artist[] = [];
  @Trace albums: Album[] = [];
  @Trace structuredItems: UnisonStructuredResultItem[] = [];
  @Trace lyric?: UnisonLyricPayload = undefined;

  constructor(id: string = '', role: string = 'assistant', content: string = '') {
    this.id = id;
    this.role = role;
    this.content = content;
  }
}

export class UnisonAgentResult {
  conversation: UnisonOpenAIMessage[] = [];
  displayMessages: UnisonDisplayMessage[] = [];
  assistantContent: string = '';
  errorMessage: string = '';
}