import { webview } from '@kit.ArkWeb';

/** Only fixed, data-only HTML codec expressions run in this Web controller. */
export class LightSourceHtmlCodec {
  private static controller: webview.WebviewController | null = null;
  static attach(controller: webview.WebviewController): void { this.controller = controller; }
  static detach(controller: webview.WebviewController): void {
    if (this.controller === controller) this.controller = null;
  }
  static async execute(kind: string, text: string): Promise<string> {
    const deadline = Date.now()+8000;
    while (!this.controller && Date.now()<deadline) await new Promise<void>(resolve => setTimeout(resolve,50));
    if (!this.controller || text.length>4*1024*1024) throw new Error('HTML 编解码环境未就绪或输入过大');
    const operation = kind === 'html-encode' ?
      'const d=document.createElement("div");d.textContent=input;return JSON.stringify({value:d.innerHTML});' :
      'const d=document.createElement("textarea");d.innerHTML=input;return JSON.stringify({value:d.value});';
    const controller = this.controller;
    const raw = await new Promise<string>((resolve,reject) => {
      const timer = setTimeout(() => reject(new Error('HTML 编解码超时')),Math.max(1,deadline-Date.now()));
      controller.runJavaScript('(()=>{const input='+JSON.stringify(text)+';'+operation+'})()')
        .then(value => {clearTimeout(timer);resolve(value);})
        .catch(error => {clearTimeout(timer);reject(error);});
    });
    let value = raw;
    if (value.startsWith('"')) value = JSON.parse(value);
    const parsed = JSON.parse(value) as {value:string};
    if (typeof parsed.value !== 'string') throw new Error('HTML 编解码返回格式无效');
    return parsed.value;
  }
}
