// 通用 JS 引擎（@ohos.JSVM）原生模块类型声明
// evalJs(code, contextJson): 在 JSVM 中注入 preamble(java/source/context) 后执行 code，
// 异步(工作线程，native __httpRequest 同步阻塞)；返回 JSON 字符串 {"result":..,"sourceVar":..,"error"?:..}
export const evalJs: (code: string, contextJson: string) => Promise<string>;
