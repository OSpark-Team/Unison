import http from '@ohos.net.http';
import { image } from '@kit.ImageKit';
import effectKit from '@ohos.effectKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from './Logger'; // 请确保 Logger 模块路径正确

const TAG = 'ImageColorExtractor';

/**
 * 图片颜色提取器
 * 用于从网络图片中提取主色调，支持异步操作
 *
 * 功能特性：
 * - 网络图片下载和转换为 PixelMap
 * - 主色调和多个主色调提取
 * - 错误处理和日志记录
 * - 内存管理优化
 * - 颜色混合、渐变色生成等辅助功能
 *
 * 使用场景：
 * - 歌单详情页面背景色提取
 * - 专辑封面主题色获取
 * - 动态UI主题适配
 */
export class ImageColorExtractor {
  /**
   * 从网络图片URL提取主色调
   * @param imageUrl 图片URL地址
   * @param targetSize 目标尺寸，用于优化性能（默认100x100）
   * @returns Promise<string> 返回ARGB十六进制颜色值，如 "#FFFF5733"
   */
  static async extractMainColor(imageUrl: string, targetSize: number = 100): Promise<string> {
    Logger.info(TAG, `开始提取图片主色调: ${imageUrl}`);

    try {
      // 步骤1：下载网络图片并转换为 PixelMap
      const pixelMap = await ImageColorExtractor.downloadImageToPixelMap(imageUrl, targetSize);

      // 步骤2：从 PixelMap 提取主色调
      const mainColor = await ImageColorExtractor.extractColorFromPixelMap(pixelMap);

      // 步骤3：释放 PixelMap 内存
      pixelMap.release();

      Logger.info(TAG, `主色调提取成功: ${mainColor}`);
      return mainColor;

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `主色调提取失败: ${errorMessage}`);

      // 返回默认颜色 (不透明的蓝色)
      return '#FF007DFF';
    }
  }

  /**
   * 下载网络图片并转换为 PixelMap
   * @param imageUrl 图片URL地址
   * @param targetSize 目标尺寸
   * @returns Promise<image.PixelMap>
   */
  private static async downloadImageToPixelMap(imageUrl: string, targetSize: number): Promise<image.PixelMap> {
    return new Promise<image.PixelMap>((resolve, reject) => {
      const httpRequest = http.createHttp();

      httpRequest.request(imageUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'User-Agent': 'Unison/1.0(EdgeMusic 3.0)'
        }
      }, (error: BusinessError, data: http.HttpResponse) => {
        httpRequest.destroy();

        if (error) {
          Logger.error(TAG, `图片下载失败: ${error.message}`);
          reject(error);
          return;
        }

        if (data.responseCode !== 200) {
          const errorMsg = `HTTP请求失败，状态码: ${data.responseCode}`;
          Logger.error(TAG, errorMsg);
          reject(new Error(errorMsg));
          return;
        }

        try {
          const imageData: ArrayBuffer = data.result as ArrayBuffer;
          const imageSource: image.ImageSource = image.createImageSource(imageData);

          const pixelMapOptions: image.DecodingOptions = {
            desiredSize: {
              height: targetSize,
              width: targetSize
            },
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
            editable: false
          };

          imageSource.createPixelMap(pixelMapOptions)
            .then((pixelMap: image.PixelMap) => {
              imageSource.release();
              resolve(pixelMap);
            })
            .catch((createError: BusinessError) => {
              Logger.error(TAG, `PixelMap创建失败: ${createError.message}`);
              imageSource.release();
              reject(createError);
            });

        } catch (processError) {
          const errorMessage = processError instanceof Error ? processError.message : String(processError);
          Logger.error(TAG, `图片处理失败: ${errorMessage}`);
          reject(new Error(errorMessage));
        }
      });
    });
  }

  /**
   * 从 PixelMap 提取主色调
   * @param pixelMap PixelMap对象
   * @returns Promise<string> ARGB十六进制颜色值
   */
  private static async extractColorFromPixelMap(pixelMap: image.PixelMap): Promise<string> {
    try {
      // 创建颜色提取器，聚焦于中心区域
      const colorPicker = await effectKit.createColorPicker(pixelMap, [0.25, 0.25, 0.75, 0.75]);

      // 获取主色调（最大占比颜色效果通常更好）
      const mainColor = colorPicker.getLargestProportionColor();

      // 转换为ARGB十六进制颜色值
      const hexColor = ImageColorExtractor.colorToHex(mainColor);

      Logger.info(TAG, `提取的主色调: ${hexColor}`);
      return hexColor;

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `颜色提取失败: ${errorMessage}`);
      return '#FF007DFF'; // 返回默认颜色
    }
  }

  /**
   * 将 effectKit.Color 对象转换为 ARGB 十六进制颜色字符串
   *
   * 注意：根据 HarmonyOS 官方文档，effectKit.Color 的 red/green/blue/alpha 属性
   * 取值范围是 [0, 255] 的整数，而不是 [0, 1] 的浮点数
   *
   * @param color effectKit.Color对象
   * @returns string ARGB十六进制颜色值，如 "#FFFF5733"
   */
  private static colorToHex(color: effectKit.Color): string {
    try {
      // effectKit.Color 的属性已经是 0-255 范围的整数，直接使用
      // 使用 Math.min/max 确保值在有效范围内
      const alpha = Math.min(255, Math.max(0, Math.round(color.alpha)));
      const red = Math.min(255, Math.max(0, Math.round(color.red)));
      const green = Math.min(255, Math.max(0, Math.round(color.green)));
      const blue = Math.min(255, Math.max(0, Math.round(color.blue)));

      // 转换为十六进制并补零
      const alphaHex = alpha.toString(16).padStart(2, '0');
      const redHex = red.toString(16).padStart(2, '0');
      const greenHex = green.toString(16).padStart(2, '0');
      const blueHex = blue.toString(16).padStart(2, '0');

      // 返回完整的ARGB十六进制颜色值
      return `#${alphaHex}${redHex}${greenHex}${blueHex}`.toUpperCase();

    } catch (error) {
      Logger.error(TAG, `颜色转换失败，使用默认颜色`);
      return '#FF007DFF';
    }
  }

  /**
   * 批量提取多个图片的主色调
   * @param imageUrls 图片URL数组
   * @param targetSize 目标尺寸
   * @returns Promise<string[]> 颜色数组
   */
  static async extractMultipleColors(imageUrls: string[], targetSize: number = 100): Promise<string[]> {
    Logger.info(TAG, `开始批量提取 ${imageUrls.length} 张图片的主色调`);

    const colorPromises = imageUrls.map(url => ImageColorExtractor.extractMainColor(url, targetSize));

    try {
      const colors = await Promise.all(colorPromises);
      Logger.info(TAG, `批量提取完成，成功提取 ${colors.length} 个颜色`);
      return colors;
    } catch (error) {
      Logger.error(TAG, `批量提取失败: ${error}`);
      // 返回默认颜色数组
      return imageUrls.map(() => '#FF007DFF');
    }
  }

  /**
   * 提取多个主要颜色（从单个图片中）
   * @param imageUrl 图片URL地址
   * @param targetSize 目标尺寸
   * @returns Promise<string[]> 返回多个主要颜色的ARGB十六进制数组
   */
  static async extractMultipleDominantColors(imageUrl: string, targetSize: number = 100): Promise<string[]> {
    Logger.info(TAG, `开始提取图片多个主要颜色: ${imageUrl}`);

    try {
      const pixelMap = await ImageColorExtractor.downloadImageToPixelMap(imageUrl, targetSize);
      const colors = await ImageColorExtractor.extractMultipleColorsFromPixelMap(pixelMap);
      pixelMap.release();

      Logger.info(TAG, `多颜色提取成功: ${colors.join(', ')}`);
      return colors;

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `多颜色提取失败: ${errorMessage}`);
      // 返回默认颜色组合
      return ['#FF007DFF', '#FF4ECDC4', '#FF45B7B8'];
    }
  }

  /**
   * 从 PixelMap 提取多个主要颜色
   * @param pixelMap PixelMap对象
   * @returns Promise<string[]> 多个颜色的ARGB十六进制数组
   */
  private static async extractMultipleColorsFromPixelMap(pixelMap: image.PixelMap): Promise<string[]> {
    try {
      const colorPicker = await effectKit.createColorPicker(pixelMap);

      // 获取不同特征的颜色
      const mainColor = colorPicker.getMainColorSync();
      const averageColor = colorPicker.getAverageColor();
      const largestProportionColor = colorPicker.getLargestProportionColor();

      // 转换为十六进制颜色值
      const mainHex = ImageColorExtractor.colorToHex(mainColor);
      const avgHex = ImageColorExtractor.colorToHex(averageColor);
      const largestProportionColorHex = ImageColorExtractor.colorToHex(largestProportionColor);

      return [mainHex, avgHex, largestProportionColorHex];

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      Logger.error(TAG, `多颜色提取失败: ${errorMessage}`);
      return ['#FF007DFF', '#FF4ECDC4', '#FF45B7B8'];
    }
  }

  /**
   * 混合多个颜色
   * @param colors 颜色字符串数组 (支持 #RRGGBB 或 #AARRGGBB)
   * @param ratio 混合比例 (0-1)，最终会按颜色数量平均分配权重
   * @returns string 混合后的 #RRGGBB 颜色
   */
  static mixColors(colors: string[], ratio: number = 0.5): string {
    try {
      if (!Array.isArray(colors) || colors.length === 0) {
        throw new Error("colors 参数必须是一个包含颜色字符串的数组");
      }

      const parseColor = (color: string) => {
        if (color.startsWith("#")) {
          color = color.substring(1);
        }
        if (color.length === 3) { // 处理 #RGB 简写形式
          color = color[0] + color[0] + color[1] + color[1] + color[2] + color[2];
        }
        if (color.length === 8) { // ARGB 格式，跳过 Alpha
          return [
            parseInt(color.substring(2, 4), 16), // R
            parseInt(color.substring(4, 6), 16), // G
            parseInt(color.substring(6, 8), 16)  // B
          ];
        }
        // 默认 RGB 格式
        return [
          parseInt(color.substring(0, 2), 16),
          parseInt(color.substring(2, 4), 16),
          parseInt(color.substring(4, 6), 16),
        ];
      };

      let rTot = 0, gTot = 0, bTot = 0;
      const n = colors.length;
      // 每个颜色的权重
      const weight = ratio / n;

      colors.forEach(color => {
        const res = parseColor(color);
        rTot += res[0] * weight;
        gTot += res[1] * weight;
        bTot += res[2] * weight;
      });

      const toHex = (value: number) => Math.round(value).toString(16).padStart(2, '0');
      return `#${toHex(rTot)}${toHex(gTot)}${toHex(bTot)}`;
    } catch (error) {
      Logger.error(TAG, `颜色混合失败: ${error}`);
      return "#000000"; // 发生错误时返回黑色
    }
  }

  /**
   * 生成颜色的带透明度的 RGBA 字符串
   * @param baseColor 基础颜色 (支持 #RRGGBB 或 #AARRGGBB)
   * @param opacity 透明度 (0-1)
   * @returns string RGBA 格式的颜色值
   */
  static generateGradientColor(baseColor: string, opacity: number = 0.8): string {
    try {
      const hex = baseColor.replace('#', '');
      let red:number, green:number, blue:number;

      if (hex.length === 8) { // ARGB
        red = parseInt(hex.substring(2, 4), 16);
        green = parseInt(hex.substring(4, 6), 16);
        blue = parseInt(hex.substring(6, 8), 16);
      } else { // RGB
        red = parseInt(hex.substring(0, 2), 16);
        green = parseInt(hex.substring(2, 4), 16);
        blue = parseInt(hex.substring(4, 6), 16);
      }

      return `rgba(${red}, ${green}, ${blue}, ${opacity})`;

    } catch (error) {
      Logger.error(TAG, `渐变色生成失败: ${error}`);
      return `rgba(0, 125, 255, ${opacity})`;
    }
  }

  /**
   * 生成多色线性渐变背景描述
   * @param colors 颜色数组 (支持 #RRGGBB 或 #AARRGGBB)
   * @param direction 渐变方向角度（默认135度）
   * @returns LinearGradient 渐变对象
   */
  static generateMultiColorGradient(colors: string[], direction: number = 135): LinearGradient {
    try {
      if (colors.length === 0) {
        colors = ['#FF007DFF', '#FF4ECDC4'];
      } else if (colors.length === 1) {
        const lighterColor = ImageColorExtractor.adjustColorBrightness(colors[0], 1.2);
        colors = [colors[0], lighterColor];
      }

      const colorStops: [ResourceColor, number][] = [];
      const step = 1.0 / (colors.length - 1);

      for (let i = 0; i < colors.length; i++) {
        colorStops.push([colors[i], i * step]);
      }

      return {
        angle: direction,
        colors: colorStops
      };

    } catch (error) {
      Logger.error(TAG, `多色渐变生成失败: ${error}`);
      return {
        angle: 135,
        colors: [['#FF007DFF', 0.0], ['#FF4ECDC4', 1.0]]
      };
    }
  }

  /**
   * 调整颜色亮度
   * @param hexColor 十六进制颜色 (支持 #RRGGBB 或 #AARRGGBB)
   * @param factor 亮度因子（>1变亮，<1变暗）
   * @returns string 调整后的 #RRGGBB 颜色
   */
  static adjustColorBrightness(hexColor: string, factor: number): string {
    try {
      const hex = hexColor.replace('#', '');
      let r: number, g:number, b:number;

      if (hex.length === 8) {
        r = parseInt(hex.substring(2, 4), 16);
        g = parseInt(hex.substring(4, 6), 16);
        b = parseInt(hex.substring(6, 8), 16);
      } else { // 默认 RGB
        r = parseInt(hex.substring(0, 2), 16);
        g = parseInt(hex.substring(2, 4), 16);
        b = parseInt(hex.substring(4, 6), 16);
      }

      const newR = Math.min(255, Math.round(r * factor));
      const newG = Math.min(255, Math.round(g * factor));
      const newB = Math.min(255, Math.round(b * factor));

      const rHex = newR.toString(16).padStart(2, '0');
      const gHex = newG.toString(16).padStart(2, '0');
      const bHex = newB.toString(16).padStart(2, '0');

      return `#${rHex}${gHex}${bHex}`.toUpperCase();

    } catch (error) {
      Logger.error(TAG, `亮度调整失败: ${error}`);
      return hexColor;
    }
  }
}
