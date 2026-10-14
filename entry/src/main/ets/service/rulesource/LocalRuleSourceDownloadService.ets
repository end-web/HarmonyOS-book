import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { CharsetCodec } from '../../utils/CharsetCodec';
import { WebEngineGate } from '../WebEngineGate';
import { LocalRuleWebSession } from './LocalRuleWebSession';

/** Source subscriptions use the same Web/download fallbacks as the upstream importer. */
export class LocalRuleSourceDownloadService {
  static readonly MAX_BYTES: number = 25 * 1024 * 1024;
  private static context: common.Context | undefined = undefined;
  private static controller: webview.WebviewController | undefined = undefined;
  private static complete: ((body: string, error: string) => void) | undefined = undefined;
  private static item: webview.WebDownloadItem | undefined = undefined;

  static attach(controller: webview.WebviewController, context: common.Context): void {
    LocalRuleSourceDownloadService.controller = controller;
    LocalRuleSourceDownloadService.context = context;
  }
  static detach(controller: webview.WebviewController): void {
    if (LocalRuleSourceDownloadService.controller !== controller) return;
    LocalRuleSourceDownloadService.complete?.('', '书源下载环境已关闭');
    LocalRuleSourceDownloadService.controller = undefined;
    LocalRuleSourceDownloadService.context = undefined;
  }
  private static read(path: string): string {
    const size = fileIo.statSync(path).size;
    if (size <= 0 || size > LocalRuleSourceDownloadService.MAX_BYTES) throw new Error('书源文件大小无效');
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const bytes = new ArrayBuffer(size);
      const count = fileIo.readSync(file.fd, bytes);
      if (count !== size) throw new Error('书源下载文件不完整');
      return CharsetCodec.decodeBuffer(bytes);
    } finally { fileIo.closeSync(file); }
  }
  private static remove(path: string): void {
    try { fileIo.unlinkSync(path); } catch (_error) {}
  }
  private static async ready(): Promise<void> {
    WebEngineGate.instance.needRuleBrowser = true;
    const deadline = Date.now() + 10000;
    while ((!LocalRuleSourceDownloadService.controller || !LocalRuleSourceDownloadService.context) &&
      Date.now() < deadline) await new Promise<void>(resolve => setTimeout(resolve, 50));
    if (!LocalRuleSourceDownloadService.context) throw new Error('书源下载环境未就绪');
  }
  static inspect(): void {
    const controller = LocalRuleSourceDownloadService.controller;
    const complete = LocalRuleSourceDownloadService.complete;
    if (!controller || !complete) return;
    controller.runJavaScript('document.body ? document.body.innerText : ""').then((raw: string): void => {
      if (LocalRuleSourceDownloadService.complete !== complete || raw.length >
        LocalRuleSourceDownloadService.MAX_BYTES * 6) return;
      try {
        const body: string = JSON.parse(raw);
        if (typeof body === 'string' && /^[\s\uFEFF]*[\[{]/.test(body)) {
          JSON.parse(body.replace(/^\uFEFF/, ''));
          complete(body, '');
        }
      } catch (_error) {}
    }).catch((): void => {});
  }
  static async browser(address: string): Promise<string> {
    await LocalRuleSourceDownloadService.ready();
    const controller = LocalRuleSourceDownloadService.controller;
    const context = LocalRuleSourceDownloadService.context;
    if (!controller || !context) throw new Error('书源下载环境未就绪');
    const lease = await LocalRuleWebSession.acquire(20000);
    const path = `${context.cacheDir}/source_web_import_${Date.now()}.json`;
    try {
      return await new Promise<string>((resolve, reject) => {
        let settled = false;
        const finish = (body: string, error: string): void => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          LocalRuleSourceDownloadService.complete = undefined;
          if (error) reject(new Error(error)); else resolve(body);
        };
        const timer = setTimeout((): void => finish('', '书源网页下载超时'), 20000);
        LocalRuleSourceDownloadService.complete = finish;
        const delegate = new webview.WebDownloadDelegate();
        delegate.onBeforeDownload((item: webview.WebDownloadItem): void => {
          if (settled) { item.cancel(); return; }
          LocalRuleSourceDownloadService.item = item;
          if (item.getTotalBytes() > LocalRuleSourceDownloadService.MAX_BYTES) {
            finish('', '书源文件超过 25 MiB'); item.cancel(); return;
          }
          try { item.start(path); } catch (_error) { finish('', '书源网页下载失败'); }
        });
        delegate.onDownloadFinish((item: webview.WebDownloadItem): void => {
          if (settled) return;
          try { finish(LocalRuleSourceDownloadService.read(item.getFullPath() || path), ''); }
          catch (_error) { finish('', '书源网页下载文件无效'); }
        });
        delegate.onDownloadUpdated((item: webview.WebDownloadItem): void => {
          if (!settled && item.getReceivedBytes() > LocalRuleSourceDownloadService.MAX_BYTES) {
            finish('', '书源文件超过 25 MiB'); item.cancel();
          }
        });
        delegate.onDownloadFailed((_item: webview.WebDownloadItem): void => finish('', '书源网页下载失败'));
        try { controller.setDownloadDelegate(delegate); controller.loadUrl(address); }
        catch (_error) { finish('', '书源网页下载启动失败'); }
      });
    } finally {
      try { LocalRuleSourceDownloadService.item?.cancel(); controller.stop(); } catch (_error) {}
      LocalRuleSourceDownloadService.item = undefined;
      LocalRuleSourceDownloadService.remove(path);
      LocalRuleWebSession.release(lease);
    }
  }
  static async system(address: string): Promise<string> {
    await LocalRuleSourceDownloadService.ready();
    const context = LocalRuleSourceDownloadService.context;
    if (!context) throw new Error('书源下载环境未就绪');
    const path = `${context.cacheDir}/source_system_import_${Date.now()}.json`;
    let task: request.DownloadTask | undefined = undefined;
    try {
      task = await request.downloadFile(context, {url:address,filePath:path,background:false,
        enableMetered:true,enableRoaming:true,header:{'Accept':'application/json,text/plain,*/*'}});
      const download = task;
      await new Promise<void>((resolve, reject) => {
        let settled = false;
        const finish = (error: string): void => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          try { download.off('complete', onComplete); download.off('fail', onFail); } catch (_error) {}
          if (error) reject(new Error(error)); else resolve();
        };
        const onComplete = (): void => finish('');
        const onFail = (_code: number): void => finish('书源系统下载失败');
        const timer = setTimeout((): void => finish('书源系统下载超时'), 20000);
        download.on('complete', onComplete); download.on('fail', onFail);
        download.query().then((info: request.DownloadInfo): void => {
          if (info.status === request.SESSION_SUCCESSFUL) finish('');
          else if (info.status === request.SESSION_FAILED) finish('书源系统下载失败');
        }).catch((): void => finish('书源系统下载状态读取失败'));
      });
      return LocalRuleSourceDownloadService.read(path);
    } finally {
      try { await task?.delete(); } catch (_error) {}
      LocalRuleSourceDownloadService.remove(path);
    }
  }
}
