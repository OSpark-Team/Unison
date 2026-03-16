import axios, { AxiosError, AxiosInstance, AxiosResponse } from '@ohos/axios';
import Logger from '../../utils/Logger';
import { OpenAIChatRequest, OpenAIChatResponse } from './UnisonToolTypes';

const TAG = 'UnisonPlusRequest';

export class UnisonPlusRequest {
  private static instance: Map<string, AxiosInstance> = new Map();

  private static buildKey(baseUrl: string, apiKey: string): string {
    return `${UnisonPlusRequest.normalizeBaseUrl(baseUrl)}|${apiKey}`;
  }

  private static normalizeBaseUrl(baseUrl: string): string {
    let normalizedUrl: string = baseUrl.trim();
    while (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.slice(0, normalizedUrl.length - 1);
    }
    return normalizedUrl;
  }

  private static maskApiKey(apiKey: string): string {
    if (apiKey.length <= 8) {
      return '****';
    }
    return `${apiKey.slice(0, 4)}****${apiKey.slice(apiKey.length - 4)}`;
  }

  public static Has(baseUrl: string, apiKey: string): boolean {
    return UnisonPlusRequest.instance.has(UnisonPlusRequest.buildKey(baseUrl, apiKey));
  }

  public static Get(baseUrl: string, apiKey: string): AxiosInstance {
    const instanceKey: string = UnisonPlusRequest.buildKey(baseUrl, apiKey);
    const instance: AxiosInstance | undefined = UnisonPlusRequest.instance.get(instanceKey);
    if (!instance) {
      throw new Error('unison request instance is null');
    }
    return instance;
  }

  public static Create(baseUrl: string, apiKey: string): AxiosInstance {
    if (UnisonPlusRequest.Has(baseUrl, apiKey)) {
      return UnisonPlusRequest.Get(baseUrl, apiKey);
    }

    const normalizedUrl: string = UnisonPlusRequest.normalizeBaseUrl(baseUrl);
    Logger.info(TAG, `创建 Unison+ 请求器: ${normalizedUrl}, key: ${UnisonPlusRequest.maskApiKey(apiKey)}`);

    const instance: AxiosInstance = axios.create({
      baseURL: normalizedUrl,
      timeout: 120000,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
        'User-Agent': 'Unison/1.0(EdgeMusic 3.0)',
      },
    });

    instance.interceptors.response.use(
      (response: AxiosResponse): AxiosResponse => {
        const responseStr: string = JSON.stringify(response.data);
        const maxLength: number = 2000;
        for (let i: number = 0; i < responseStr.length; i += maxLength) {
          Logger.info(TAG, responseStr.slice(i, i + maxLength));
        }
        return response;
      },
      (error: AxiosError): Promise<AxiosError> => {
        Logger.error(TAG, error.message);
        return Promise.reject(error);
      },
    );

    UnisonPlusRequest.instance.set(UnisonPlusRequest.buildKey(baseUrl, apiKey), instance);
    return instance;
  }

  public static Reload(baseUrl: string, apiKey: string): AxiosInstance {
    if (!UnisonPlusRequest.Has(baseUrl, apiKey)) {
      return UnisonPlusRequest.Create(baseUrl, apiKey);
    }

    const instance: AxiosInstance = UnisonPlusRequest.Get(baseUrl, apiKey);
    instance.defaults.baseURL = UnisonPlusRequest.normalizeBaseUrl(baseUrl);
    instance.defaults.headers.Authorization = `Bearer ${apiKey}`;
    return instance;
  }

  public static async ChatCompletions(baseUrl: string, apiKey: string,
    request: OpenAIChatRequest): Promise<OpenAIChatResponse> {
    const instance: AxiosInstance = UnisonPlusRequest.Create(baseUrl, apiKey);
    const endpoint: string = UnisonPlusRequest.normalizeBaseUrl(baseUrl).endsWith('/chat/completions') ? '' :
      '/chat/completions';
    const response: AxiosResponse = await instance.post(endpoint, request);
    const data: OpenAIChatResponse = response.data as OpenAIChatResponse;
    if (data.error && data.error.message) {
      throw new Error(data.error.message);
    }
    return data;
  }
}