import { UsageStatsBucket } from '../service/StatsService';

@ComponentV2
export struct TimeStatsBarChart {
  @Param buckets: UsageStatsBucket[] = [];
  @Param version: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  build() {
    Canvas(this.context)
      .width('100%')
      .height(220)
      .onReady(() => {
        this.canvasWidth = this.context.width;
        this.canvasHeight = this.context.height;
        this.drawChart();
      })
      .onAreaChange((_oldArea: Area, _newArea: Area) => {
        setTimeout(() => this.drawChart(), 0);
      })
      .onVisibleAreaApproximateChange({ ratios: [0.0, 1.0] }, (isVisible: boolean) => {
        if (isVisible) {
          this.drawChart();
        }
      })
  }

  onDidBuild(): void {
    this.drawChart();
  }

  private drawChart(): void {
    const width = this.context.width > 0 ? this.context.width : this.canvasWidth;
    const height = this.context.height > 0 ? this.context.height : this.canvasHeight;
    if (width <= 0 || height <= 0) return;

    this.context.clearRect(0, 0, width, height);
    const left = 34;
    const right = 16;
    const top = 18;
    const bottom = 34;
    const chartWidth = width - left - right;
    const chartHeight = height - top - bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    const maxSeconds = Math.max(1, ...this.buckets.map((item) => item.listenSeconds + item.readSeconds));
    const niceMax = this.niceMax(maxSeconds);

    this.drawGrid(left, top, chartWidth, chartHeight, niceMax);
    this.drawBars(left, top, chartWidth, chartHeight, niceMax);
    this.drawLegend(width, height);
  }

  private drawGrid(left: number, top: number, chartWidth: number, chartHeight: number, maxSeconds: number): void {
    const lines = 3;
    this.context.lineWidth = 0.6;
    this.context.strokeStyle = '#1F000000';
    this.context.fillStyle = '#99000000';
    this.context.font = '10vp sans-serif';
    this.context.textAlign = 'right';
    this.context.textBaseline = 'middle';

    for (let i = 0; i <= lines; i++) {
      const y = top + chartHeight - chartHeight * i / lines;
      this.context.beginPath();
      this.context.moveTo(left, y);
      this.context.lineTo(left + chartWidth, y);
      this.context.stroke();

      const value = Math.round(maxSeconds * i / lines);
      this.context.fillText(this.formatAxisTime(value), left - 6, y);
    }
  }

  private drawBars(left: number, top: number, chartWidth: number, chartHeight: number, maxSeconds: number): void {
    const count = Math.max(1, this.buckets.length);
    const slotWidth = chartWidth / count;
    const barWidth = Math.min(24, Math.max(8, slotWidth * 0.48));
    const baseY = top + chartHeight;

    for (let i = 0; i < this.buckets.length; i++) {
      const item = this.buckets[i];
      const x = left + slotWidth * i + (slotWidth - barWidth) / 2;
      const listenHeight = chartHeight * item.listenSeconds / maxSeconds;
      const readHeight = chartHeight * item.readSeconds / maxSeconds;
      const totalHeight = listenHeight + readHeight;

      this.context.fillStyle = '#16000000';
      this.roundRect(x, top, barWidth, chartHeight, 6);
      this.context.fill();

      if (totalHeight > 0) {
        this.context.fillStyle = '#2F7DF6';
        this.roundRect(x, baseY - listenHeight, barWidth, listenHeight, 5);
        this.context.fill();

        if (readHeight > 0) {
          this.context.fillStyle = '#FFB547';
          this.roundRect(x, baseY - listenHeight - readHeight, barWidth, readHeight, 5);
          this.context.fill();
        }
      }

      this.context.fillStyle = '#99000000';
      this.context.font = '10vp sans-serif';
      this.context.textAlign = 'center';
      this.context.textBaseline = 'top';
      this.context.fillText(item.label, x + barWidth / 2, baseY + 8);
    }
  }

  private drawLegend(width: number, height: number): void {
    const y = height - 8;
    this.context.font = '10vp sans-serif';
    this.context.textBaseline = 'middle';
    this.context.textAlign = 'left';

    this.context.fillStyle = '#2F7DF6';
    this.roundRect(width - 118, y - 5, 10, 10, 3);
    this.context.fill();
    this.context.fillStyle = '#99000000';
    this.context.fillText('听书', width - 104, y);

    this.context.fillStyle = '#FFB547';
    this.roundRect(width - 58, y - 5, 10, 10, 3);
    this.context.fill();
    this.context.fillStyle = '#99000000';
    this.context.fillText('阅读', width - 44, y);
  }

  private roundRect(x: number, y: number, w: number, h: number, r: number): void {
    const radius = Math.max(0, Math.min(r, w / 2, h / 2));
    this.context.beginPath();
    this.context.moveTo(x + radius, y);
    this.context.lineTo(x + w - radius, y);
    this.context.arcTo(x + w, y, x + w, y + radius, radius);
    this.context.lineTo(x + w, y + h - radius);
    this.context.arcTo(x + w, y + h, x + w - radius, y + h, radius);
    this.context.lineTo(x + radius, y + h);
    this.context.arcTo(x, y + h, x, y + h - radius, radius);
    this.context.lineTo(x, y + radius);
    this.context.arcTo(x, y, x + radius, y, radius);
    this.context.closePath();
  }

  private niceMax(seconds: number): number {
    if (seconds <= 30 * 60) return 30 * 60;
    if (seconds <= 60 * 60) return 60 * 60;
    if (seconds <= 2 * 60 * 60) return 2 * 60 * 60;
    if (seconds <= 4 * 60 * 60) return 4 * 60 * 60;
    if (seconds <= 8 * 60 * 60) return 8 * 60 * 60;
    return Math.ceil(seconds / (4 * 60 * 60)) * 4 * 60 * 60;
  }

  private formatAxisTime(seconds: number): string {
    if (seconds <= 0) return '0';
    if (seconds < 3600) return `${Math.round(seconds / 60)}分`;
    return `${Math.round(seconds / 3600)}时`;
  }
}
