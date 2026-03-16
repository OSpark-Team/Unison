/**
 * 歌词模型
 * 使用标准的LRC格式，包含时间戳和对应的歌词文本
 * 
 * LRC格式示例：
 * [00:00.000] 作词 : 方文山
 * [00:01.000] 作曲 : 周杰伦
 * [00:02.000] 编曲 : 钟兴民
 * [00:03.000]
 * [00:04.000] 夜沉默了
 * [00:07.483] 心事浮上来
 */
@ObservedV2
export class Lyric {
  /**
   * 原文歌词（LRC格式）
   */
  @Trace normal?: string = undefined;

  /**
   * 音译歌词（LRC格式）
   * 例如：日语歌曲的罗马音
   */
  @Trace transliteration?: string = undefined;

  /**
   * 翻译歌词（LRC格式）
   * 例如：外语歌曲的中文翻译
   */
  @Trace translation?: string = undefined;
}

