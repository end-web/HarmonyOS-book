/** 写日志前对内容做脱敏。 */
export class LogText {
  /**
   * 请求地址只保留到路径：查询串、片段以及书源写法里 `,{...}` 的请求选项（可能带令牌、Cookie、表单）
   * 都不进日志，只留下原始长度便于比对。
   */
  static url(value: string): string {
    const text = (value || '').trim();
    const optionIndex = text.indexOf(',{');
    const base = optionIndex >= 0 ? text.substring(0, optionIndex) : text;
    const queryIndex = base.search(/[?#]/);
    const head = (queryIndex >= 0 ? base.substring(0, queryIndex) : base).substring(0, 200);
    return queryIndex >= 0 || optionIndex >= 0 || base.length > 200 ? `${head}?<len=${text.length}>` : head;
  }
}
