/** 九宫格：0 上一页，1 工具栏，2 下一页，3 无操作。至少保留一个工具栏入口。 */
export class ReaderTapPolicy {
  static readonly DEFAULT: string = '012012012';

  static normalize(value: string): string {
    return /^[0-3]{9}$/.test(value) && value.includes('1') ? value : ReaderTapPolicy.DEFAULT;
  }

  static resolve(value: string, x: number, y: number, width: number, height: number, left: number = 33, right: number = 33,
    top: number = 33, bottom: number = 33): number {
    if (width <= 0 || height <= 0 || x < 0 || y < 0 || x >= width || y >= height) return 3;
    const column = x / width * 100 < left ? 0 : x / width * 100 >= 100 - right ? 2 : 1;
    const row = y / height * 100 < top ? 0 : y / height * 100 >= 100 - bottom ? 2 : 1;
    const index = row * 3 + column;
    return Number(ReaderTapPolicy.normalize(value).charAt(index));
  }

  static percent(value: number, other: number = 5): number {
    return Number.isFinite(value) ? Math.round(Math.max(5, Math.min(90 - other, value))) : 33;
  }

  static cycle(value: string, index: number): string {
    const regions = ReaderTapPolicy.normalize(value);
    if (index < 0 || index > 8) return regions;
    const next = regions.substring(0, index) + ((Number(regions.charAt(index)) + 1) % 4).toString() +
      regions.substring(index + 1);
    return next.includes('1') ? next : regions;
  }
}

/** 一次触摸只要曾经移动超阈值就不能再变成点击，包括滑出后回到原点。 */
export class ReaderTouchTracker {
  private startX: number = 0;
  private startY: number = 0;
  private blocked: boolean = true;

  begin(x: number, y: number): void {
    this.startX = x;
    this.startY = y;
    this.blocked = false;
  }

  move(x: number, y: number): void {
    if (Math.hypot(x - this.startX, y - this.startY) >= 8) this.blocked = true;
  }

  cancel(): void { this.blocked = true; }
  canTap(): boolean { return !this.blocked; }

  update(event: TouchEvent): void {
    const touch = event.touches[0] ?? event.changedTouches[0];
    if (event.type === TouchType.Down && event.touches.length === 1 && touch !== undefined) {
      this.begin(touch.x, touch.y);
    } else if (event.type === TouchType.Cancel || event.touches.length > 1) {
      this.cancel();
    } else if (touch !== undefined) {
      this.move(touch.x, touch.y);
    }
  }
}
