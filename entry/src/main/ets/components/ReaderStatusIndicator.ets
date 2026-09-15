import { batteryInfo } from '@kit.BasicServicesKit';
import { AppFont } from '../theme/Theme';

/** 独立更新页脚状态，不参与正文分页或翻页版本号。 */
@ComponentV2
export struct ReaderStatusIndicator {
  @Param color: ResourceColor = '#6F675E';
  @Local batteryLevel: number = -1;
  private batteryTimer: number = -1;

  aboutToDisappear(): void {
    this.stopBatteryUpdates();
  }

  private refreshBattery(): void {
    try {
      const level = batteryInfo.batterySOC;
      this.batteryLevel = Number.isFinite(level) && level >= 0 && level <= 100 ? Math.round(level) : -1;
    } catch (_e) {
      this.batteryLevel = -1;
    }
  }

  private startBatteryUpdates(): void {
    this.refreshBattery();
    if (this.batteryTimer !== -1) return;
    this.batteryTimer = setInterval((): void => this.refreshBattery(), 30000);
  }

  private stopBatteryUpdates(): void {
    if (this.batteryTimer === -1) return;
    clearInterval(this.batteryTimer);
    this.batteryTimer = -1;
  }

  build() {
    Row({ space: 4 }) {
      Text($r('app.string.reader_battery_level', this.batteryLevel >= 0 ? `${this.batteryLevel}%` : '--'))
        .fontSize(AppFont.Caption)
        .fontColor(this.color)
        .maxLines(1)
      Text('·')
        .fontSize(AppFont.Caption)
        .fontColor(this.color)
      TextClock()
        .format('HH:mm')
        .fontSize(AppFont.Caption)
        .fontColor(this.color)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .onVisibleAreaChange([0], (visible: boolean): void => {
      if (visible) this.startBatteryUpdates();
      else this.stopBatteryUpdates();
    })
  }
}
