/**
 * ID类型
 * API中的ID可以是数字或字符串类型
 * 部分特殊ID（如 daily_songs）使用字符串类型
 */
export type id = number | string;

/**
 * 比特率类型
 * 用于指定音频质量
 * 常见值：
 * - 128000: 标准音质
 * - 192000: 较高音质
 * - 320000: 高音质
 * - 999000: 无损音质
 * - 999900: Audio Vivid
 */
export type Bitrate = 'standard' | 'higher' | 'exhigh' | 'lossless' | 'hires' | 'vivd' | string | number;

/**
 * 播放列表类型
 * - normal: 普通播放列表
 * - album: 专辑
 * - dj: 电台节目
 * - artist: 艺术家热门歌曲
 */
export type PlaylistType = 'normal' | 'album' | 'dj' | 'artist';

