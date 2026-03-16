import { displaySync } from '@kit.ArkGraphics2D';

// ── 核心类型定义 ──────────────────────────────────────
class StrokeData {
  pts: [number, number][];
  color: string;

  constructor(pts: [number, number][], color: string) {
    this.pts = pts;
    this.color = color;
  }
}

class Stick {
  target: [number, number][];
  cur: [number, number][];
  vel: [number, number][];
  color: string;
  delay: number;
  formed: boolean;

  constructor(
    target: [number, number][],
    cur: [number, number][],
    vel: [number, number][],
    color: string,
    delay: number,
    formed: boolean
  ) {
    this.target = target;
    this.cur = cur;
    this.vel = vel;
    this.color = color;
    this.delay = delay;
    this.formed = formed;
  }
}

class GlyphDef {
  fn: (ox: number, oy: number) => StrokeData[];
  w: number;

  constructor(fn: (ox: number, oy: number) => StrokeData[], w: number) {
    this.fn = fn;
    this.w = w;
  }
}

// ── 基础常量设置 ──────────────────────────────────────
const ORANGE: string = '#FF6B00';
// 移除了原有的 DARK 和 BG 常量，改为组件传参控制

// ── 统一高度与笔触 ────────────────────────────────────
const GH: number = 72;  // glyph height
const SW: number = 3.2; // stroke width reference

// 极限紧凑逻辑分辨率：精准包裹总宽(440)和总高(72)，消灭空间浪费
const LOGICAL_CW: number = 450;
const LOGICAL_CH: number = 90;

// ── 路径采样辅助函数 ───────────────────────────────────
function sampleLine(x1: number, y1: number, x2: number, y2: number, n: number = 16): [number, number][] {
  const pts: [number, number][] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    pts.push([x1 + (x2 - x1) * t, y1 + (y2 - y1) * t]);
  }
  return pts;
}

function sampleArc(cx: number, cy: number, rx: number, ry: number, a0: number, a1: number, n: number = 32): [number, number][] {
  const pts: [number, number][] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, a = a0 + (a1 - a0) * t;
    pts.push([cx + Math.cos(a) * rx, cy + Math.sin(a) * ry]);
  }
  return pts;
}

function sampleBez(x1: number, y1: number, cx1: number, cy1: number, cx2: number, cy2: number, x2: number, y2: number, n: number = 28): [number, number][] {
  const pts: [number, number][] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, mt = 1 - t;
    pts.push([
      mt * mt * mt * x1 + 3 * mt * mt * t * cx1 + 3 * mt * t * t * cx2 + t * t * t * x2,
      mt * mt * mt * y1 + 3 * mt * mt * t * cy1 + 3 * mt * t * t * cy2 + t * t * t * y2
    ]);
  }
  return pts;
}

// ── 严密的字形绘制算法 (增加 color 参数) ──────────────────
function gO(ox: number, oy: number, color: string): StrokeData[] {
  const cx = ox + 28, cy = oy + GH * 0.5;
  const rx = 24, ry = GH * 0.48;
  return [
    new StrokeData(sampleArc(cx, cy, rx, ry, 0, Math.PI * 2, 48), color)
  ];
}

function gS(ox: number, oy: number, color: string): StrokeData[] {
  const l = ox + 6, r = ox + 46;
  const t = oy, b = oy + GH, m = oy + GH * 0.5;
  return [
    new StrokeData(sampleBez(r, t + GH * 0.22, r, t - GH * 0.08, l, t - GH * 0.08, l, m - GH * 0.04, 28), color),
    new StrokeData(sampleBez(l, m - GH * 0.04, l, m + GH * 0.06, r, m - GH * 0.06, r, m + GH * 0.04, 16), color),
    new StrokeData(sampleBez(r, m + GH * 0.04, r, b + GH * 0.08, l, b + GH * 0.08, l, b - GH * 0.22, 28), color)
  ];
}

function gP(ox: number, oy: number, color: string): StrokeData[] {
  const lx = ox + 8;
  const t = oy, b = oy + GH;
  const capY = t, midY = oy + GH * 0.48, rx = ox + 44;
  return [
    new StrokeData(sampleLine(lx, t, lx, b, 20), color),
    new StrokeData(sampleLine(lx, capY, rx - 2, capY, 8), color),
    new StrokeData(sampleBez(rx - 2, capY, ox + 58, capY, ox + 58, midY, rx - 2, midY, 24), color),
    new StrokeData(sampleLine(rx - 2, midY, lx, midY, 8), color)
  ];
}

function gA(ox: number, oy: number, color: string): StrokeData[] {
  const midX = ox + 26;
  const t = oy, b = oy + GH;
  const crossY = oy + GH * 0.62;
  return [
    new StrokeData(sampleLine(midX, t, ox + 4, b, 22), color),
    new StrokeData(sampleLine(midX, t, ox + 48, b, 22), color),
    new StrokeData(sampleLine(ox + 14, crossY, ox + 38, crossY, 12), color)
  ];
}

function gR(ox: number, oy: number, color: string): StrokeData[] {
  const lx = ox + 8;
  const t = oy, b = oy + GH;
  const midY = oy + GH * 0.48, rx = ox + 42;
  return [
    new StrokeData(sampleLine(lx, t, lx, b, 20), color),
    new StrokeData(sampleLine(lx, t, rx - 2, t, 8), color),
    new StrokeData(sampleBez(rx - 2, t, ox + 56, t, ox + 56, midY, rx - 2, midY, 24), color),
    new StrokeData(sampleLine(rx - 2, midY, lx + 4, midY, 8), color),
    new StrokeData(sampleLine(lx + 4, midY, ox + 50, b, 18), color)
  ];
}

function gK(ox: number, oy: number, color: string): StrokeData[] {
  const lx = ox + 8;
  const t = oy, b = oy + GH;
  const midY = oy + GH * 0.50;
  return [
    new StrokeData(sampleLine(lx, t, lx, b, 20), color),
    new StrokeData(sampleLine(ox + 50, t, lx, midY, 18), color),
    new StrokeData(sampleLine(lx, midY, ox + 52, b, 18), color)
  ];
}

function gSpark(cx: number, cy: number): StrokeData[] {
  const r = 22;
  return [0, 1, 2].map((i: number) => {
    const a = (i / 3) * Math.PI;
    return new StrokeData(
      sampleLine(
        cx + Math.cos(a) * r, cy + Math.sin(a) * r,
        cx - Math.cos(a) * r, cy - Math.sin(a) * r,
        12
      ),
      ORANGE
    );
  });
}

/**
 * OSpark 粒子 Logo 组件
 */
@ComponentV2
export struct OSparkLogo {
  @Param compWidth: number = 360;
  @Param compHeight: number = 160;
  @Param density: number = 6;

  // 新增：线条颜色。由于你要用在暗色背景，默认改成白色。外部调用时也可以自由修改
  @Param lineColor: string = '#ffffff';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private backDisplaySync: displaySync.DisplaySync | undefined = undefined;

  // 物理系统状态
  private sticks: Stick[] = [];
  private sysState: 'formed' | 'drifting' | 'forming' = 'formed';
  private frameN: number = 0;
  private idleFrames: number = -60;
  private driftFrame: number = 0;

  aboutToAppear() {
    this.initSticks();
  }

  aboutToDisappear() {
    if (this.backDisplaySync) {
      this.backDisplaySync.stop();
      this.backDisplaySync = undefined;
    }
  }

  private initSticks() {
    // 将 this.lineColor 传入字形绘制函数
    const glyphDefs: GlyphDef[] = [
      new GlyphDef((ox, oy) => gO(ox, oy, this.lineColor), 56),
      new GlyphDef((ox, oy) => gS(ox, oy, this.lineColor), 52),
      new GlyphDef((ox, oy) => gP(ox, oy, this.lineColor), 56),
      new GlyphDef((ox, oy) => gA(ox, oy, this.lineColor), 52),
      new GlyphDef((ox, oy) => gR(ox, oy, this.lineColor), 56),
      new GlyphDef((ox, oy) => gK(ox, oy, this.lineColor), 56)
    ];
    const GAP = 10;
    const SPARK_W = 52;

    const totalW = glyphDefs.reduce((s, g) => s + g.w, 0) + GAP * (glyphDefs.length - 1) + GAP + SPARK_W;
    let curX = (LOGICAL_CW - totalW) / 2;
    const oy = (LOGICAL_CH - GH) / 2;

    const allStrokes: StrokeData[] = [];

    glyphDefs.forEach((g: GlyphDef) => {
      g.fn(curX, oy).forEach((s: StrokeData) => allStrokes.push(s));
      curX += g.w + GAP;
    });

    const sparkCX = curX + SPARK_W * 0.4;
    const sparkCY = oy + GH * 0.5;
    gSpark(sparkCX, sparkCY).forEach((s: StrokeData) => allStrokes.push(s));

    this.sticks = allStrokes.map((stroke: StrokeData, i: number) => {
      const pts = stroke.pts;
      const cur: [number, number][] = pts.map((pt: [number, number]) => [pt[0], pt[1]] as [number, number]);
      const vel: [number, number][] = cur.map(() => [0, 0] as [number, number]);

      return new Stick(pts, cur, vel, stroke.color, i * 1.6, true);
    });
  }

  private handleInteract() {
    if (this.sysState === 'drifting' || this.sysState === 'forming') {
      this.sysState = 'forming';
      this.frameN = 0;
      this.sticks.forEach((s) => {
        s.delay = Math.random() * 20;
        s.formed = false;
      });
    } else if (this.sysState === 'formed') {
      this.idleFrames = 0;
    }
  }

  private drawStroke(pts: [number, number][], color: string, lw: number, glow: number) {
    if (pts.length < 2) return;
    this.context.save();
    this.context.strokeStyle = color;
    this.context.lineWidth = lw;
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';

    if (glow > 0) {
      this.context.shadowColor = color;
      this.context.shadowBlur = glow;
    }

    this.context.beginPath();
    this.context.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) {
      this.context.lineTo(pts[i][0], pts[i][1]);
    }
    this.context.stroke();

    this.context.shadowBlur = 0;
    this.context.restore();
  }

  private tick() {
    this.frameN++;

    if (this.sysState === 'formed') {
      this.idleFrames++;
      if (this.idleFrames > 240) {
        this.sysState = 'drifting';
        this.driftFrame = 0;
        this.sticks.forEach((s) => {
          s.vel = s.cur.map(() => [(Math.random() - 0.5) * 0.2, (Math.random() - 0.5) * 0.2]);
        });
      }
    }

    if (this.sysState === 'drifting') {
      this.driftFrame++;
    }

    this.context.setTransform(1, 0, 0, 1, 0, 0);
    this.context.clearRect(0, 0, this.compWidth, this.compHeight);
    // [修改点]：去除了 fillStyle 和 fillRect 的调用，使 Canvas 画布背景完全透明。

    const scale = Math.min(this.compWidth / LOGICAL_CW, this.compHeight / LOGICAL_CH);
    const offsetX = (this.compWidth - LOGICAL_CW * scale) / 2;
    const offsetY = (this.compHeight - LOGICAL_CH * scale) / 2;
    this.context.translate(offsetX, offsetY);
    this.context.scale(scale, scale);

    let allFormed = true;

    this.sticks.forEach((s) => {
      const n = s.cur.length;

      if (this.sysState === 'drifting') {
        allFormed = false;
        const intensity = Math.min(1, this.driftFrame / 300);

        for (let i = 0; i < n; i++) {
          const dx = s.cur[i][0] - LOGICAL_CW / 2;
          const dy = s.cur[i][1] - LOGICAL_CH / 2;
          const dist = Math.hypot(dx, dy) || 1;

          s.vel[i][0] += ((dx / dist) * 0.01 + (Math.random() - .5) * 0.05) * intensity;
          s.vel[i][1] += ((dy / dist) * 0.005 + (Math.random() - .5) * 0.05 + 0.12) * intensity;

          s.vel[i][0] *= .96;
          s.vel[i][1] *= .96;
          s.cur[i][0] += s.vel[i][0];
          s.cur[i][1] += s.vel[i][1];

          const ground = LOGICAL_CH - 2;
          const leftWall = 2;
          const rightWall = LOGICAL_CW - 2;

          if (s.cur[i][1] > ground) {
            s.cur[i][1] = ground;
            s.vel[i][1] *= -0.3;
            s.vel[i][0] *= 0.7;
          }
          if (s.cur[i][0] < leftWall) {
            s.cur[i][0] = leftWall;
            s.vel[i][0] *= -0.4;
          } else if (s.cur[i][0] > rightWall) {
            s.cur[i][0] = rightWall;
            s.vel[i][0] *= -0.4;
          }
        }
      } else if (this.sysState === 'forming') {
        if (this.frameN < s.delay) {
          allFormed = false;
        } else {
          let settled = true;
          for (let i = 0; i < n; i++) {
            s.vel[i][0] += (s.target[i][0] - s.cur[i][0]) * .08;
            s.vel[i][1] += (s.target[i][1] - s.cur[i][1]) * .08;
            s.vel[i][0] *= .78;
            s.vel[i][1] *= .78;
            s.cur[i][0] += s.vel[i][0];
            s.cur[i][1] += s.vel[i][1];

            if (Math.hypot(s.cur[i][0] - s.target[i][0], s.cur[i][1] - s.target[i][1]) > .8) {
              settled = false;
            }
          }
          if (!settled) {
            allFormed = false;
          } else {
            s.formed = true;
            for (let i = 0; i < n; i++) {
              s.cur[i] = [s.target[i][0], s.target[i][1]];
            }
          }
        }
      } else if (this.sysState === 'formed') {
        if (s.color === ORANGE) {
          for (let i = 0; i < n; i++) {
            s.cur[i][0] = s.target[i][0] + Math.sin(this.frameN * .045 + i) * .5;
            s.cur[i][1] = s.target[i][1] + Math.cos(this.frameN * .045 + i) * .5;
          }
        }
      }

      const glow = (s.color === ORANGE && (this.sysState === 'formed' || this.sysState === 'forming'))
        ? 8 + Math.sin(this.frameN * .05) * 4 : 0;

      this.drawStroke(s.cur, s.color, this.sysState === 'formed' ? SW : SW * 0.85, glow);
    });

    if (this.sysState === 'forming' && allFormed) {
      this.sysState = 'formed';
      this.idleFrames = 0;
    }

    // 绘制底部透明小字
    this.context.save();
    this.context.globalAlpha = .35 + Math.sin(this.frameN * .04) * .15;
    this.context.fillStyle = '#aeaeb2';
    this.context.font = '11px -apple-system, sans-serif';
    this.context.textAlign = 'center';
    if (this.sysState === 'drifting') {
      this.context.fillText('tap to assemble', LOGICAL_CW / 2, LOGICAL_CH - 4);
    }
    this.context.restore();
  }

  build() {
    Column() {
      Canvas(this.context)
        .width(this.compWidth)
        .height(this.compHeight)
        .onClick(() => {
          this.handleInteract();
        })
        .onReady(() => {
          if (!this.backDisplaySync) {
            this.backDisplaySync = displaySync.create();
            this.backDisplaySync.on('frame', () => {
              this.tick();
            });
            this.backDisplaySync.start();
          }
        })
    }
    .width(this.compWidth)
    .height(this.compHeight)
  }
}