/**
 * WebEngineGate - 隐藏 Web 宿主的按需挂载门控
 *
 * 欢 FM 在直链解析失败时会使用隐藏 WebView 提取音频地址。
 * 本门控让宿主仅在首次真正需要时挂载。单调置位（false→true 永不回退），挂上不卸，
 * 避免卸载→controller 野引用的竞态。
 *
 * 模式仿 AuthService：@ObservedV2 + static get instance() + @Trace，UI 直接读字段即可响应。
 */
@ObservedV2
export class WebEngineGate {
  private static _instance: WebEngineGate | null = null;

  static get instance(): WebEngineGate {
    if (!WebEngineGate._instance) {
      WebEngineGate._instance = new WebEngineGate();
    }
    return WebEngineGate._instance;
  }

  /** 需要欢音频嗅探 WebView。 */
  @Trace needAudioExtractor: boolean = false;
}
