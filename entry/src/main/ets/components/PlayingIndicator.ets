/**
 * 播放中指示器组件（Canvas 等化器动画）
 */
import { displaySync } from "@kit.ArkGraphics2D";

@ComponentV2
export struct PlayingIndicator {
  @Param isPlaying: boolean = false;
  @Param sizeValue: number = 18;
  @Param activeColor: Resource = $r('app.color.playing_indicator_active');
  @Param inactiveColor: Resource = $r('app.color.playing_indicator_inactive');
  @Param barCount: number = 3;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private barHeights: number[] = [0.55, 0.85, 0.65];
  private resolvedActiveColor: string = '#FF4ECDC4';
  private resolvedInactiveColor: string = '#66182431';

  private displaySyncInstance?: displaySync.DisplaySync;

  aboutToAppear(): void {
    this.resolveColors();
    this.draw();
    this.updateTimerState();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  @Monitor('isPlaying')
  onPlayingChanged(): void {
    this.updateTimerState();
    this.draw();
  }

  @Monitor('activeColor', 'inactiveColor')
  onColorChanged(): void {
    this.resolveColors();
    this.draw();
  }

  private updateTimerState(): void {
    if (this.isPlaying) {
      this.startTimer();
    } else {
      this.stopTimer();
    }
  }

  private startTimer(): void {
    if (this.displaySyncInstance) return;

    this.displaySyncInstance = displaySync.create();
    this.displaySyncInstance.setExpectedFrameRateRange({
      min: 30,
      max: 60,
      expected: 30
    });
    this.displaySyncInstance.on('frame', () => {
      this.tick();
    });
    this.displaySyncInstance.start();
  }

  private stopTimer(): void {
    if (!this.displaySyncInstance) return;
    this.displaySyncInstance.stop();
    this.displaySyncInstance = undefined;
  }

  private tick(): void {
    const next: number[] = [];
    const count = Math.max(1, this.barCount);
    for (let i = 0; i < count; i++) {
      const current = i < this.barHeights.length ? this.barHeights[i] : 0.6;
      const target = 0.25 + Math.random() * 0.75;
      next.push(current * 0.85 + target * 0.15);
    }
    this.barHeights = next;
    this.draw();
  }

  private resolveColors(): void {
    const uiContext = this.getUIContext();
    const hostContext = uiContext.getHostContext();
    if (!hostContext) return;

    try {
      const activeInt = hostContext.resourceManager.getColorSync(this.activeColor.id);
      const inactiveInt = hostContext.resourceManager.getColorSync(this.inactiveColor.id);
      this.resolvedActiveColor = this.argbIntToHex(activeInt);
      this.resolvedInactiveColor = this.argbIntToHex(inactiveInt);
    } catch (err) {
      // 资源解析失败时使用默认值
    }
  }

  private argbIntToHex(argb: number): string {
    let value = argb < 0 ? argb + 0x100000000 : argb;
    return `#${value.toString(16).padStart(8, '0').toUpperCase()}`;
  }

  private draw(): void {
    const ctx = this.canvasContext;
    const size = this.sizeValue;

    ctx.clearRect(0, 0, size, size);

    const count = Math.max(1, this.barCount);
    const barWidth = size / (count * 2 + 1);
    const gap = barWidth;
    const radius = barWidth / 2;
    const color = this.isPlaying ? this.resolvedActiveColor : this.resolvedInactiveColor;

    ctx.fillStyle = color;

    for (let i = 0; i < count; i++) {
      const hRatio = i < this.barHeights.length ? this.barHeights[i] : 0.6;
      const height = Math.max(1, size * hRatio);
      const x = gap + i * (barWidth + gap);
      const y = (size - height) / 2;

      ctx.beginPath();
      try {
        ctx.roundRect(x, y, barWidth, height, radius);
        ctx.fill();
      } catch (err) {
        ctx.fillRect(x, y, barWidth, height);
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.canvasContext)
        .width(this.sizeValue)
        .height(this.sizeValue)
        .onReady(() => {
          this.resolveColors();
          this.draw();
        })
    }
    .width(this.sizeValue)
    .height(this.sizeValue)
    .renderGroup(true)
  }
}