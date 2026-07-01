import { HeatPoint } from '../service/StatsService';

interface HeatCell {
  col: number;
  row: number;
  seconds: number;
  monthFirst: boolean; // 该列 row0 是否为月首（用于月份标签）
  monthText: string;
}

/**
 * 听读热力图（打卡日历）
 * - 以「周」为列、周一~周日为行的贡献网格
 * - 暖色梯度按每日时长深浅表达听读习惯的连续性
 */
@ComponentV2
export struct ReadingHeatmap {
  @Param days: HeatPoint[] = [];
  @Param version: number = 0;
  @Param chartHeight: number = 150;

  // 暖色梯度：空 → 少 → 多（品牌珊瑚色 #FF6B3D）
  private readonly track: string = '#F1ECE7';
  private readonly warmScale: string[] = ['#FFD9C8', '#FFB495', '#FF8A5C', '#FF6B3D'];

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private reveal: number = 0;       // 入场揭示进度 0→1
  private revealDone: boolean = false;
  private revealTimer: number = -1;

  build() {
    Canvas(this.context)
      .width('100%')
      .height(this.chartHeight)
      .onReady(() => {
        this.canvasWidth = this.context.width;
        this.canvasHeight = this.context.height;
        this.startReveal();
      })
      .onAreaChange((_o: Area, _n: Area) => {
        setTimeout(() => this.drawChart(), 0);
      })
      .onVisibleAreaApproximateChange({ ratios: [0.0, 1.0] }, (visible: boolean) => {
        if (visible) this.startReveal();
      })
  }

  onDidBuild(): void {
    this.drawChart();
  }

  @Monitor('version')
  onDataChange(): void {
    if (this.revealTimer >= 0) {
      clearInterval(this.revealTimer);
      this.revealTimer = -1;
    }
    this.reveal = 0;
    this.revealDone = false;
    this.startReveal();
  }

  aboutToDisappear(): void {
    if (this.revealTimer >= 0) {
      clearInterval(this.revealTimer);
      this.revealTimer = -1;
    }
  }

  private startReveal(): void {
    if (this.revealDone) {
      this.drawChart();
      return;
    }
    if (this.revealTimer >= 0) return;
    if (this.days.length === 0) {
      this.drawChart();
      return;
    }
    const start = Date.now();
    const dur = 620;
    this.revealTimer = setInterval(() => {
      const p = Math.min(1, (Date.now() - start) / dur);
      this.reveal = p;
      this.drawChart();
      if (p >= 1) {
        clearInterval(this.revealTimer);
        this.revealTimer = -1;
        this.revealDone = true;
      }
    }, 16);
  }

  private easeOut(t: number): number {
    const x = Math.min(1, Math.max(0, t));
    return 1 - Math.pow(1 - x, 3);
  }

  private weekdayMon(date: Date): number {
    // 周一=0 ... 周日=6
    return (date.getDay() + 6) % 7;
  }

  private parseDay(day: string): Date {
    const p = day.split('-');
    return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
  }

  private colorOf(seconds: number): string {
    if (seconds <= 0) return this.track;
    const m = seconds / 60;
    if (m < 15) return this.warmScale[0];
    if (m < 45) return this.warmScale[1];
    if (m < 90) return this.warmScale[2];
    return this.warmScale[3];
  }

  private buildCells(): HeatCell[] {
    if (this.days.length === 0) return [];
    const oldest = this.parseDay(this.days[0].day);
    const startMonday = new Date(oldest.getFullYear(), oldest.getMonth(), oldest.getDate() - this.weekdayMon(oldest));
    const startMs = startMonday.getTime();
    const monthNames = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];
    const cells: HeatCell[] = [];
    let lastLabeledMonth = -1;
    for (let i = 0; i < this.days.length; i++) {
      const d = this.parseDay(this.days[i].day);
      const diffDays = Math.round((d.getTime() - startMs) / 86400000);
      const col = Math.floor(diffDays / 7);
      const row = diffDays % 7;
      let monthFirst = false;
      let monthText = '';
      if (row === 0 && d.getMonth() !== lastLabeledMonth) {
        monthFirst = true;
        monthText = monthNames[d.getMonth()];
        lastLabeledMonth = d.getMonth();
      }
      cells.push({ col, row, seconds: this.days[i].seconds, monthFirst, monthText });
    }
    return cells;
  }

  private drawChart(): void {
    const width = this.context.width > 0 ? this.context.width : this.canvasWidth;
    const height = this.context.height > 0 ? this.context.height : this.canvasHeight;
    if (width <= 0 || height <= 0) return;
    this.context.clearRect(0, 0, width, height);

    const cells = this.buildCells();
    if (cells.length === 0) return;
    const totalCols = cells[cells.length - 1].col + 1;

    const labelLeft = 20;   // 左侧周标签宽
    const labelTop = 16;    // 顶部月份标签高
    const legendH = 20;     // 底部图例高
    const gap = 3;

    const usableW = width - labelLeft;
    const usableH = height - labelTop - legendH;
    const cell = Math.max(6, Math.min((usableW - gap * (totalCols - 1)) / totalCols, (usableH - gap * 6) / 7));
    const gridW = cell * totalCols + gap * (totalCols - 1);
    const originX = labelLeft + (usableW - gridW) / 2;
    const originY = labelTop;
    const radius = Math.min(3, cell / 3);
    const e = this.easeOut(this.reveal);

    // 月份标签（近接则只保留靠后的月份，避免 2月/3月 挤在一起）
    const monthCols: number[] = [];
    const monthTexts: string[] = [];
    const minGap = 3;
    for (const c of cells) {
      if (!c.monthFirst) continue;
      const n = monthCols.length;
      if (n > 0 && c.col - monthCols[n - 1] < minGap) {
        monthCols[n - 1] = c.col;
        monthTexts[n - 1] = c.monthText;
      } else {
        monthCols.push(c.col);
        monthTexts.push(c.monthText);
      }
    }
    this.context.globalAlpha = e;
    this.context.fillStyle = '#9A8F86';
    this.context.font = '10vp sans-serif';
    this.context.textBaseline = 'alphabetic';
    this.context.textAlign = 'left';
    for (let i = 0; i < monthCols.length; i++) {
      const x = originX + monthCols[i] * (cell + gap);
      this.context.fillText(monthTexts[i], x, labelTop - 4);
    }

    // 周标签（一 / 三 / 五）
    this.context.textAlign = 'right';
    this.context.textBaseline = 'middle';
    const weekLabels: string[] = ['一', '', '三', '', '五', '', ''];
    for (let r = 0; r < 7; r++) {
      if (weekLabels[r] !== '') {
        const y = originY + r * (cell + gap) + cell / 2;
        this.context.fillText(weekLabels[r], labelLeft - 6, y);
      }
    }

    // 单元格（按列渐次揭示：放大 + 淡入）
    for (const c of cells) {
      const t = this.easeOut((this.reveal - (c.col / totalCols) * 0.35) / 0.65);
      if (t <= 0) continue;
      const size = cell * t;
      const off = (cell - size) / 2;
      const x = originX + c.col * (cell + gap) + off;
      const y = originY + c.row * (cell + gap) + off;
      this.context.globalAlpha = t;
      this.context.fillStyle = this.colorOf(c.seconds);
      this.roundRect(x, y, size, size, radius * t);
      this.context.fill();
    }

    this.context.globalAlpha = e;
    this.drawLegend(width, height, legendH);
    this.context.globalAlpha = 1;
  }

  private drawLegend(width: number, height: number, legendH: number): void {
    const box = 10;
    const gap = 3;
    const swatches = this.warmScale.length + 1; // 含 track
    const legendW = box * swatches + gap * (swatches - 1) + 46; // 加上「少」「多」文字宽
    let x = width - legendW;
    const y = height - legendH / 2;

    this.context.font = '10vp sans-serif';
    this.context.fillStyle = '#9A8F86';
    this.context.textBaseline = 'middle';
    this.context.textAlign = 'left';
    this.context.fillText('少', x, y);
    x += 20;

    const colors: string[] = [this.track, this.warmScale[0], this.warmScale[1], this.warmScale[2], this.warmScale[3]];
    for (let i = 0; i < colors.length; i++) {
      this.context.fillStyle = colors[i];
      this.roundRect(x, y - box / 2, box, box, 2);
      this.context.fill();
      x += box + gap;
    }
    x += 4;
    this.context.fillStyle = '#9A8F86';
    this.context.fillText('多', x, y);
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
}
