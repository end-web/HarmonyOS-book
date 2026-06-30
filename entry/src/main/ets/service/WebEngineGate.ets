/**
 * WebEngineGate - 隐藏 Web 宿主的按需挂载门控
 *
 * 两个隐藏 Web(Chromium) 宿主 WebViewJSEngineHost / WebViewAudioExtractorHost
 * 原本无条件常驻 MainPage，ArkWeb 内核常驻 ~150-250MB。纯 CSS/JSONPath 书源根本
 * 用不到 WebView，这部分内存对它们是纯浪费。
 *
 * 本门控让两个宿主「仅在首次真正需要时」才挂载：引擎首次被调用时把对应 @Trace 置 true，
 * MainPage 的 if 条件渲染据此挂载对应 Host。单调置位（false→true 永不回退），挂上不卸，
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

  /** 需要 WebView JS 引擎（书源复杂 JS / document. 降级） */
  @Trace needJsEngine: boolean = false;
  /** 需要音频嗅探 WebView（天下书音 / 悦听吧等加载整页提取音频 URL 的源） */
  @Trace needAudioExtractor: boolean = false;
}
