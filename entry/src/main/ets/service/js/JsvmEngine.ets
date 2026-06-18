/**
 * JsvmEngine - 通用 JS 引擎（@ohos.JSVM C++ 模块 libjsvmengine.so 的 ArkTS 封装）
 *
 * 把书源 @js: 的 context 序列化成 JSON 交给 native evalJs(在 JSVM 中注入 preamble: java/source/context 后执行)，
 * 解析返回 {result, sourceVar, error}，回填 source.setVariable，并把结果还原成 legado 期望的形态。
 * native 端用 net_http 同步阻塞实现同步 java.ajax；纯 JS preamble 提供 md5/base64/hex/AES/timeFormat。
 * 失败(error/异常)返回 undefined，调用方据此回落到 WebView 等其它引擎。
 */
import jsvm from 'libjsvmengine.so';
import { getSourceContext } from '../rule/SourceContext';

interface JsvmResult {
  result?: string;
  sourceVar?: string;
  error?: string;
}

export class JsvmEngine {
  /** 返回 undefined 表示 JSVM 未能处理(失败/不支持)，应回落其它引擎 */
  static async eval(code: string, context: Record<string, Object>): Promise<Object | null | undefined> {
    let ctxJson = '';
    try {
      ctxJson = JsvmEngine.buildContextJson(context);
    } catch (e) {
      return undefined;
    }
    let raw = '';
    try {
      raw = await jsvm.evalJs(code, ctxJson);
    } catch (e) {
      console.error(`[JsvmEngine] native evalJs failed: ${e}`);
      return undefined;
    }
    let parsed: JsvmResult;
    try {
      parsed = JSON.parse(raw) as JsvmResult;
    } catch (e) {
      return undefined;
    }
    if (parsed.error && parsed.error.length > 0) {
      console.warn(`[JsvmEngine] script error: ${parsed.error}`);
      return undefined;
    }
    // 回填 source.setVariable 的新值
    if (parsed.sourceVar && parsed.sourceVar.length > 0) {
      try { getSourceContext().setVariable(parsed.sourceVar); } catch (e) { /* ignore */ }
    }
    return JsvmEngine.parseResult(parsed.result ?? '');
  }

  private static buildContextJson(context: Record<string, Object>): string {
    const o: Record<string, Object> = {};
    o['result'] = JsvmEngine.asStr(context['result']);
    if (context['baseUrl'] !== undefined) o['baseUrl'] = context['baseUrl'];
    if (context['key'] !== undefined) o['key'] = context['key'];
    if (context['page'] !== undefined) o['page'] = context['page'];
    if (context['book'] !== undefined) o['book'] = context['book'];
    if (context['chapter'] !== undefined) o['chapter'] = context['chapter'];
    const sc = getSourceContext();
    const src = sc.getSource();
    if (src) {
      o['bookSourceUrl'] = src.bookSourceUrl;
      o['bookSourceName'] = src.bookSourceName;
      if (src.bookSourceComment) o['bookSourceComment'] = src.bookSourceComment;
    }
    try {
      const sv = sc.getVariable();
      if (sv) o['sourceVar'] = sv;
    } catch (e) { /* ignore */ }
    return JSON.stringify(o);
  }

  private static asStr(v: Object | undefined): string {
    if (v === undefined || v === null) return '';
    return typeof v === 'string' ? v as string : JSON.stringify(v);
  }

  /** result 是 native 把完成值 stringify 后的字符串：数组/对象再 parse 回来，普通串原样返回 */
  private static parseResult(s: string): Object | null {
    if (!s) return '';
    const t = s.trim();
    if (t.length > 0 && (t.charAt(0) === '[' || t.charAt(0) === '{')) {
      try { return JSON.parse(t) as Object; } catch (e) { return s; }
    }
    return s;
  }
}
