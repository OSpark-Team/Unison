import connection from "@ohos.net.connection";

/**
 * 轮询检查一个函数，直到它返回 true
 * @param {Function} checkFunction - 返回布尔值的检查函数
 * @param {number} [interval=100] - 检查间隔（毫秒）
 * @param {number} [timeout=10000] - 超时时间（毫秒），0 表示永不超时
 * @returns {Promise<void>} 一个 Promise，在条件满足时 resolve，超时时 reject
 * @throws {Error} 当超时时间内条件仍未满足时抛出错误
 * @example
 * // 等待某个全局标志变为 true，每 200ms 检查一次，最多等待 5 秒
 * await waitForCondition(() => isReady, 200, 5000);
 */
export function waitForCondition(checkFunction: Function, interval = 100, timeout = 10000) {
  return new Promise<void>((resolve, reject) => {
    const startTime = Date.now();

    const checkCondition = () => {
      if (checkFunction()) {
        resolve();
        return;
      }

      if (timeout > 0 && Date.now() - startTime >= timeout) {
        reject(new Error(`条件在 ${timeout} 毫秒后仍未满足`));
        return;
      }

      setTimeout(checkCondition, interval);
    };

    checkCondition();
  });
}

/**
 * 将媒体资源 URL 转换为指定尺寸的缩略图地址
 * @param {string | Resource} [url] - 原始资源 URL 或 HarmonyOS Resource 对象；为 undefined 时原样返回
 * @param {number} [size=100] - 缩略图的边长（像素），同时作为宽高参数
 * @returns {string | Resource} 处理后的缩略图 URL 或原始 Resource 对象
 * @example
 * // 字符串 URL：追加尺寸参数
 * cover("https://example.com/img.jpg", 200);
 * // => "https://example.com/img.jpg?param=200y200"
 *
 * // ui-avatars.com 的链接直接返回，不追加参数
 * cover("https://ui-avatars.com/api/?name=Tom");
 * // => "https://ui-avatars.com/api/?name=Tom"
 */
export function cover(url?: string | Resource, size = 100): string | Resource {
  if (typeof url === "string") {
    if (url.indexOf("ui-avatars.com") !== -1) {
      return url as string;
    }
    return `${url}?param=${size}y${size}`;
  } else {
    return url as Resource;
  }
}

/**
 * 从数组中随机取出一个元素
 * @template T
 * @param {T[]} arr - 目标数组
 * @returns {T} 随机选取的元素
 * @example
 * sample([1, 2, 3, 4]); // => 随机返回其中一个数字
 */
export function sample<T>(arr: Array<T>) {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * 对数组进行随机洗牌，并返回指定数量的元素
 * @template T
 * @param {T[]} arr - 原始数组（不会被修改）
 * @param {number} [count=arr.length] - 返回元素的数量，默认返回全部元素
 * @returns {T[]} 随机排列后截取的新数组
 * @example
 * shuffle([1, 2, 3, 4, 5], 3); // => 随机取 3 个，如 [3, 1, 5]
 */
export function shuffle<T>(arr: T[], count: number = arr.length): T[] {
  const shuffled = [...arr].sort(() => 0.5 - Math.random());
  return shuffled.slice(0, count);
}

/**
 * 解析后的媒体资产数据
 * @interface AssetData
 * @property {string} sourceId - 资产所属的数据源 ID
 * @property {string} id - 资产自身的唯一标识符
 */
interface AssetData {
  sourceId: string;
  id: string;
}

/**
 * 解析 omsp:// 协议格式的资产 ID 字符串
 * @param {string} assetId - 形如 `omsp://<sourceId>?id=<id>&isFavorite=<bool>` 的资产标识符
 * @returns {AssetData} 解析后的资产数据对象
 * @example
 * parseAssetId("omsp://source123?id=asset456&isFavorite=true");
 * // => { sourceId: "source123", id: "asset456", isFavorite: true }
 */
export function parseAssetId(assetId: string): AssetData {
  const withoutProtocol = assetId.slice("omsp://".length);
  const queryIndex = withoutProtocol.indexOf("?");
  const sourceId = withoutProtocol.slice(0, queryIndex);
  const query = withoutProtocol.slice(queryIndex + 1);

  const id = parseParam(query, "id");
  return { sourceId, id };
}

/**
 * 从 URL 查询字符串中提取指定键的值
 * @param {string} query - 不含 `?` 前缀的查询字符串，如 `"id=123&isFavorite=true"`
 * @param {string} key - 要提取的参数名
 * @returns {string} 对应参数的值；若参数不存在则返回空字符串
 * @example
 * parseParam("id=123&isFavorite=true", "id");       // => "123"
 * parseParam("id=123&isFavorite=true", "missing");  // => ""
 */
function parseParam(query: string, key: string): string {
  const prefix = key + "=";
  const start = query.indexOf(prefix);
  if (start === -1) return "";
  const valueStart = start + prefix.length;
  const end = query.indexOf("&", valueStart);
  return end === -1 ? query.slice(valueStart) : query.slice(valueStart, end);
}

/**
 * 获取当前默认网络的句柄
 * @returns {Promise<connection.NetHandle>} 解析为当前默认网络句柄的 Promise
 * @throws {Error} 当无法获取默认网络时抛出错误
 * @example
 * const netHandle = await getDefaultNet();
 */
export async function getDefaultNet(): Promise<connection.NetHandle> {
  const netHandle = await connection.getDefaultNet();
  return netHandle;
}

/**
 * 获取当前设备的网络连接类型
 * @returns {Promise<"WLAN" | "ONDATA" | "UNKNOWN" | "NO_NETWORK">} 解析为网络类型的 Promise：
 * - `"WLAN"` — Wi-Fi 连接
 * - `"ONDATA"` — 蜂窝数据连接
 * - `"UNKNOWN"` — 无法识别的连接类型
 * - `"NO_NETWORK"` — 没有网络连接
 * @throws {Error} 当获取网络能力信息失败时抛出错误
 * @example
 * const type = await getNetworkType();
 * if (type === "WLAN") {
 *   console.log("当前使用 Wi-Fi");
 * }
 */
export async function getNetworkType(): Promise<"WLAN" | "ONDATA" | "UNKNOWN" | "NO_NETWORK"> {
  const netHandle = await getDefaultNet();
  if (!netHandle || netHandle.netId === 0) {
    return "NO_NETWORK";
  }
  const netCapabilities = await connection.getNetCapabilities(netHandle);
  const bearerType = netCapabilities.bearerTypes[0];
  if (bearerType === connection.NetBearType.BEARER_WIFI) {
    return "WLAN";
  } else if (bearerType === connection.NetBearType.BEARER_CELLULAR) {
    return "ONDATA";
  }
  return "UNKNOWN";
}