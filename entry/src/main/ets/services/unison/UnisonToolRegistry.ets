import { OpenAIToolDefinition, OpenAIJsonProperties } from './UnisonToolTypes';

export class UnisonToolRegistry {
  private static emptyProperties(): OpenAIJsonProperties {
    return {};
  }

  public static getTools(): OpenAIToolDefinition[] {
    return [
      {
        type: 'function',
        function: {
          name: 'list_sources',
          description: '列出当前应用中所有可用数据源，返回不包含 token 的安全摘要。',
          parameters: {
            type: 'object',
            properties: UnisonToolRegistry.emptyProperties(),
            additionalProperties: false,
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'set_main_source',
          description: '将某个数据源设置为默认数据源。调用前应先通过 list_sources 获取候选 sourceId。',
          parameters: {
            type: 'object',
            properties: {
              sourceId: {
                type: 'string',
                description: '要设置为默认数据源的 sourceId。',
              },
            },
            required: ['sourceId'],
            additionalProperties: false,
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'get_user_playlists',
          description: '获取某个数据源上当前登录用户的播放列表。sourceId 省略时回退到 mainSource。',
          parameters: {
            type: 'object',
            properties: {
              sourceId: {
                type: 'string',
                description: '可选，目标数据源 ID。未传时回退到默认数据源。',
              },
              uid: {
                type: 'string',
                description: '可选，用户 ID。未传时回退到 source.user.id。',
              },
              limit: {
                type: 'number',
                description: '可选，返回数量，默认 20。',
              },
              offset: {
                type: 'number',
                description: '可选，偏移量，默认 0。',
              },
            },
            additionalProperties: false,
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'get_song_lyric',
          description: '获取歌曲歌词。通常应先通过 search_music 搜索歌曲并拿到 id，再调用本工具。sourceId 省略时回退到 mainSource。',
          parameters: {
            type: 'object',
            properties: {
              sourceId: {
                type: 'string',
                description: '可选，目标数据源 ID。未传时回退到默认数据源。',
              },
              uid: {
                type: 'string',
                description: '可选，保留字段，通常无需传入。',
              },
              id: {
                type: 'string',
                description: '必填，歌曲 ID。建议先通过 search_music 获取。',
              },
            },
            required: ['id'],
            additionalProperties: false,
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'search_music',
          description: '在某个数据源上执行综合搜索，返回歌曲、歌单、艺术家、专辑摘要。',
          parameters: {
            type: 'object',
            properties: {
              sourceId: {
                type: 'string',
                description: '可选，目标数据源 ID。未传时回退到默认数据源。',
              },
              keywords: {
                type: 'string',
                description: '必填，搜索关键词。',
              },
              limit: {
                type: 'number',
                description: '可选，返回数量，默认 10。',
              },
            },
            required: ['keywords'],
            additionalProperties: false,
          },
        },
      },
    ];
  }
}