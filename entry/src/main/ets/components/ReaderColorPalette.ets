import { hexToHsv, hsvToHex } from '../model/ReaderTheme';
import { AppColor, AppSpace } from '../theme/Theme';

/** 二维饱和度/明度调色盘，色相滑杆覆盖全部 RGB 颜色。 */
@ComponentV2
export struct ReaderColorPalette {
  @Param color: string = '#2D2925';
  @Event onChange: (color: string, commit: boolean) => void = () => {};
  @Local hue: number = 0;
  @Local saturation: number = 0;
  @Local valueLevel: number = 1;
  private paletteWidth: number = 1;

  aboutToAppear(): void { this.restore(); }
  @Monitor('color')
  onColorChanged(): void { this.restore(); }

  private restore(): void {
    const hsv = hexToHsv(this.color);
    if (hsv.s > 0 && hsv.v > 0) this.hue = hsv.h;
    this.saturation = hsv.s;
    this.valueLevel = hsv.v;
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width('100%').height(128)
          .linearGradient({ angle: 90, colors: [['#FFFFFF', 0], [hsvToHex(this.hue, 1, 1), 1]] })
        Row().width('100%').height(128)
          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#FF000000', 1]] })
        Row().width(14).height(14).borderRadius(7).backgroundColor(Color.Transparent)
          .border({ width: 2, color: '#FFFFFF' })
          .position({ x: this.saturation * this.paletteWidth - 7, y: (1 - this.valueLevel) * 128 - 7 })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%').height(128).clip(true).borderRadius(10)
      .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width === 'number') this.paletteWidth = Math.max(1, size.width);
      })
      .gesture(PanGesture({ direction: PanDirection.All, distance: 1 }))
      .onTouch((event: TouchEvent): void => {
        const touch = event.touches[0] ?? event.changedTouches[0];
        if (touch === undefined) return;
        this.saturation = Math.max(0, Math.min(1, touch.x / this.paletteWidth));
        this.valueLevel = 1 - Math.max(0, Math.min(1, touch.y / 128));
        this.onChange(hsvToHex(this.hue, this.saturation, this.valueLevel), event.type === TouchType.Up || event.type === TouchType.Cancel);
        event.stopPropagation();
      })
      Row({ space: 12 }) {
        Slider({ value: this.hue, min: 0, max: 360, step: 1 })
          .layoutWeight(1).selectedColor(hsvToHex(this.hue, 1, 1))
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.hue = value;
            this.onChange(hsvToHex(value, this.saturation, this.valueLevel),
              mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        Text(this.color).fontSize(12).fontColor(AppColor.Brand)
        Row().width(24).height(24).borderRadius(12).backgroundColor(this.color)
      }.width('100%')
    }.width('100%')
  }
}
