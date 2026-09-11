import { deviceInfo } from '@kit.BasicServicesKit';

/** 最低支持 API 20；按接口引入版本选择实现，不能用编译版本判断设备能力。 */
export class PlatformCompat {
  static supports(apiVersion: number): boolean {
    return deviceInfo.sdkApiVersion >= apiVersion;
  }

  static get immersiveMaterial(): boolean {
    return PlatformCompat.supports(26);
  }

  static get floatingTabs(): boolean {
    return PlatformCompat.supports(23);
  }
}

/** Grid 的内容偏移从 API 22 开始支持；API 20 用内边距保护首尾内容。 */
export class CompatibleGridInsets implements AttributeModifier<GridAttribute> {
  private top: number;
  private bottom: number;
  private horizontal: number;

  constructor(top: number, bottom: number, horizontal: number) {
    this.top = top;
    this.bottom = bottom;
    this.horizontal = horizontal;
  }

  applyNormalAttribute(instance: GridAttribute): void {
    if (PlatformCompat.supports(22)) {
      instance.padding({ left: this.horizontal, right: this.horizontal })
        .contentStartOffset(this.top).contentEndOffset(this.bottom);
    } else {
      instance.padding({ left: this.horizontal, right: this.horizontal, top: this.top, bottom: this.bottom });
    }
  }
}
