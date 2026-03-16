import axios, { AxiosError, AxiosInstance, AxiosResponse } from "@ohos/axios";
import Logger from "./Logger";
import { getNetworkType } from "./Tools";

const TAG = "SourceRequest";

/**
 * 资源请求器
 */
export default class SourceRequest {
  private static instance: Map<string, AxiosInstance> = new Map();

  /**
   * 获取资源请求器的缓存Keys
   * @returns
   */
  public static Keys() {
    return SourceRequest.instance.keys();
  }

  /**
   * 判断是否存在该Key的资源缓存
   */
  public static Has(key: string) {
    return SourceRequest.instance.has(key);
  }

  /**
   * 获取资源请求器
   * @param key
   * @returns AxiosInstance
   */
  public static Get(key: string) {
    const instance = SourceRequest.instance.get(key);
    if (!instance) {
      throw new Error("instance is null");
    }
    Logger.info(TAG, `获取资源请求器: ${key}`);
    return instance;
  }

  /**
   * 创建资源请求器
   * @param key
   * @param url
   * @param token
   * @returns AxiosInstance
   */
  public static Create(key: string, url: string, token: string): AxiosInstance {
    if (SourceRequest.Has(key)) {
      return SourceRequest.Get(key);
    }
    Logger.info(TAG, `创建资源请求器: ${key}, url: ${url}, token: ${token}`);
    const instance = axios.create({
      baseURL: url,
      timeout: 10000,
      headers: {
        "Content-Type": "application/json",
        Token: token,
        "User-Agent": "Unison/1.0(EdgeMusic 3.0)",
        Key: key,
      },
    });
    // 添加响应拦截器，统一处理响应日志和错误日志
    instance.interceptors.response.use(
      (response: AxiosResponse): AxiosResponse => {
        const responseStr = JSON.stringify(response.data);
        // 分段打印日志，避免日志过长
        const maxLength = 2000;
        for (let i = 0; i < responseStr.length; i += maxLength) {
          Logger.info(TAG, responseStr.slice(i, i + maxLength));
        }
        return response;
      },
      (error: AxiosError): Promise<AxiosError> => {
        Logger.error(TAG, error.message);
        return Promise.reject(error);
      },
    );
    SourceRequest.instance.set(key, instance);
    return instance;
  }

  /**
   * 重载某个资源请求器
   * @param key
   * @param url
   * @returns AxiosInstance
   */
  public static Reload(key: string, url: string, token: string) {
    if (!SourceRequest.Has(key)) {
      // 创建添加
      return SourceRequest.Create(key, url, token);
    }
    const instance = SourceRequest.Get(key);
    instance.defaults.baseURL = url;
    instance.defaults.headers.Token = token;
    Logger.info(TAG, `重载资源请求器: ${key}, url: ${url}, token: ${token}`);
    return instance;
  }

  /**
   * 获取所有的资源请求器
   */
  public static All() {
    const instances = SourceRequest.instance.values();
    return instances;
  }
}
