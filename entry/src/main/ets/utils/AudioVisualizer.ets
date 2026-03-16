/**
 * 音频可视化状态
 */
export class AudioVisualState {
  level: number = 0;
  bass: number = 0;
  mid: number = 0;
  treble: number = 0;
}

const AUDIO_VISUALIZER_FFT_SIZE: number = 256;

function decayState(previous: AudioVisualState): AudioVisualState {
  const next = new AudioVisualState();
  next.level = previous.level * 0.86;
  next.bass = previous.bass * 0.84;
  next.mid = previous.mid * 0.84;
  next.treble = previous.treble * 0.82;
  return next;
}

function collectSamples(data: ArrayBuffer): number[] {
  const pcm = new Int16Array(data);
  const samples: number[] = [];
  if (pcm.length === 0) {
    return samples;
  }
  const step = Math.max(1, Math.floor(pcm.length / AUDIO_VISUALIZER_FFT_SIZE));
  let cursor = 0;
  let i = 0;
  while (i < AUDIO_VISUALIZER_FFT_SIZE) {
    const index = Math.min(cursor, pcm.length - 1);
    const normalized = pcm[index] / 32768;
    const windowValue = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (AUDIO_VISUALIZER_FFT_SIZE - 1));
    samples.push(normalized * windowValue);
    cursor += step;
    i += 1;
  }
  return samples;
}

function calculateRms(samples: number[]): number {
  let sum = 0;
  let i = 0;
  while (i < samples.length) {
    sum += samples[i] * samples[i];
    i += 1;
  }
  return Math.sqrt(sum / samples.length);
}

function reverseBits(value: number, bits: number): number {
  let result = 0;
  let mutableValue = value;
  let i = 0;
  while (i < bits) {
    result = (result << 1) | (mutableValue & 1);
    mutableValue >>= 1;
    i += 1;
  }
  return result;
}

function runFft(re: number[], im: number[]): void {
  const size = re.length;
  let i = 0;
  while (i < size) {
    const j = reverseBits(i, 8);
    if (j > i) {
      const tmpRe = re[i];
      re[i] = re[j];
      re[j] = tmpRe;
      const tmpIm = im[i];
      im[i] = im[j];
      im[j] = tmpIm;
    }
    i += 1;
  }

  let blockSize = 2;
  while (blockSize <= size) {
    const half = Math.floor(blockSize / 2);
    const theta = (-2 * Math.PI) / blockSize;
    let start = 0;
    while (start < size) {
      let offset = 0;
      while (offset < half) {
        const angle = theta * offset;
        const wr = Math.cos(angle);
        const wi = Math.sin(angle);
        const evenIndex = start + offset;
        const oddIndex = evenIndex + half;
        const tr = wr * re[oddIndex] - wi * im[oddIndex];
        const ti = wr * im[oddIndex] + wi * re[oddIndex];
        re[oddIndex] = re[evenIndex] - tr;
        im[oddIndex] = im[evenIndex] - ti;
        re[evenIndex] += tr;
        im[evenIndex] += ti;
        offset += 1;
      }
      start += blockSize;
    }
    blockSize *= 2;
  }
}

function readBand(re: number[], im: number[], start: number, end: number): number {
  let total = 0;
  let count = 0;
  let i = start;
  while (i <= end && i < re.length / 2) {
    total += Math.sqrt(re[i] * re[i] + im[i] * im[i]);
    count += 1;
    i += 1;
  }
  return count === 0 ? 0 : total / count;
}

function clamp(value: number): number {
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

function normalizeBand(value: number): number {
  const compressed = Math.log(1 + value * 14) / Math.log(15);
  return clamp(compressed);
}

function smooth(target: number, previous: number): number {
  if (target >= previous) {
    return previous + (target - previous) * 0.35;
  }
  return previous * 0.82 + target * 0.18;
}

/**
 * 基于 256 点 FFT 的 PCM 音频分析工具
 */
export class AudioVisualizer {
  static analyze(data: ArrayBuffer, previous: AudioVisualState): AudioVisualState {
    const samples = collectSamples(data);
    if (samples.length === 0) {
      return decayState(previous);
    }

    const rms = calculateRms(samples);
    const re: number[] = [];
    const im: number[] = [];
    let i = 0;
    while (i < AUDIO_VISUALIZER_FFT_SIZE) {
      re.push(samples[i]);
      im.push(0);
      i += 1;
    }

    runFft(re, im);
    const bass = readBand(re, im, 1, 8);
    const mid = readBand(re, im, 9, 32);
    const treble = readBand(re, im, 33, 96);

    const next = new AudioVisualState();
    next.level = smooth(clamp(rms * 3.2), previous.level);
    next.bass = smooth(normalizeBand(bass), previous.bass);
    next.mid = smooth(normalizeBand(mid), previous.mid);
    next.treble = smooth(normalizeBand(treble), previous.treble);
    return next;
  }
}