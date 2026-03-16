/**
 * 逐字歌词 Token 模型
 */
export class LyricToken {
  /** 文本片段 */
  public text: string;
  /** 绝对开始时间（毫秒） */
  public startTimeMs: number;

  constructor(text: string, startTimeMs: number) {
    this.text = text;
    this.startTimeMs = startTimeMs;
  }
}

/**
 * 歌词行数据模型（支持逐字）
 */
export class LyricLine {
  /** 整行歌词文本 */
  public text: string;
  /** 该行开始的时间点（毫秒） */
  public startTimeMs: number;
  /** 逐字 Token 序列 */
  public tokens: LyricToken[];

  constructor(text: string, startTimeMs: number, tokens: LyricToken[] = []) {
    this.text = text;
    this.startTimeMs = startTimeMs;
    this.tokens = tokens;
  }
}

/**
 * 单个时间点索引（用于 UI 快速定位）
 */
export class LyricCue {
  public timeMs: number;
  public lineIndex: number;
  public text: string;

  constructor(timeMs: number, lineIndex: number, text: string) {
    this.timeMs = timeMs;
    this.lineIndex = lineIndex;
    this.text = text;
  }
}

/**
 * 解析后的结果集
 */
export class ParsedLrc {
  public lines: LyricLine[];
  public cues: LyricCue[];

  constructor(lines: LyricLine[], cues: LyricCue[]) {
    this.lines = lines;
    this.cues = cues;
  }
}

const TIME_REG = /\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]/g;
const METADATA_REG = /^\[(ti|ar|al|by|offset|re|ve):/i;
const TOKEN_REG = /\((\d+)\)([^(\[|]*)/g;

export default class LrcParser {
  /**
   * 解析 LRC/ELRC 文本
   * 支持处理单行多个时间戳 [mm:ss.ms][mm:ss.ms]content
   */
  static parse(lrc: string | undefined | null, keepEmptyLines: boolean = false): ParsedLrc {
    if (!lrc) {
      return new ParsedLrc([], []);
    }

    const rawLines = lrc.split(/\r?\n/);
    const resultLines: LyricLine[] = [];
    const cues: LyricCue[] = [];

    for (let i = 0; i < rawLines.length; i++) {
      const raw = rawLines[i].trim();

      if (!raw || METADATA_REG.test(raw)) {
        continue;
      }

      const currentLineTimes: number[] = [];
      let match: RegExpExecArray | null;
      let lastTimestampEnd = 0;

      // 提取该物理行包含的所有时间戳
      TIME_REG.lastIndex = 0;
      while ((match = TIME_REG.exec(raw)) !== null) {
        const mm = parseInt(match[1], 10);
        const ss = parseInt(match[2], 10);
        const msStr = match[3] || '0';
        const ms = parseInt(msStr.padEnd(3, '0').substring(0, 3), 10);
        const timeMs = mm * 60000 + ss * 1000 + ms;

        currentLineTimes.push(timeMs);
        lastTimestampEnd = TIME_REG.lastIndex;
      }

      if (currentLineTimes.length === 0) continue;

      // 提取时间戳后的文本内容
      const content = raw.substring(lastTimestampEnd).trim();
      if (!content && !keepEmptyLines) continue;

      // 为每个时间戳生成一个独立的逻辑行
      for (const baseTime of currentLineTimes) {
        const tokens: LyricToken[] = [];
        let plainText = "";

        // 解析逐字标记
        TOKEN_REG.lastIndex = 0;
        let tokenMatch: RegExpExecArray | null;
        while ((tokenMatch = TOKEN_REG.exec(content)) !== null) {
          const offsetMs = parseInt(tokenMatch[1], 10);
          const tokenText = tokenMatch[2];
          // 基于当前 baseTime 计算每个词的绝对时间
          tokens.push(new LyricToken(tokenText, baseTime + offsetMs));
          plainText += tokenText;
        }

        // 如果没有逐字标记，视为普通 LRC
        if (tokens.length === 0) {
          plainText = content;
          tokens.push(new LyricToken(content, baseTime));
        }

        // 添加到结果集
        resultLines.push(new LyricLine(plainText, baseTime, tokens));
      }
    }

    // 按时间全局排序，并生成用于定位的 cues
    resultLines.sort((a, b) => a.startTimeMs - b.startTimeMs);

    resultLines.forEach((line, index) => {
      cues.push(new LyricCue(line.startTimeMs, index, line.text));
    });

    return new ParsedLrc(resultLines, cues);
  }
}