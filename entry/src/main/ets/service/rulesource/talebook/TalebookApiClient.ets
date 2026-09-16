import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { LocalRuleHttpClient } from '../LocalRuleHttpClient';
import { LocalRuleFetchResult, LocalRuleRequestPlan } from '../LocalRuleRuntimeTypes';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { LocalRuleUrlAnalyzer } from '../LocalRuleUrlAnalyzer';
import { TalebookSourceIdentity } from './TalebookSourceIdentity';

export class TalebookResponse {
  err: string = '';
  msg: string = '';
  sys: TalebookSystem = new TalebookSystem();
}

export class TalebookSystem {
  title: string = '';
  version: string = '';
}

export class TalebookConnection {
  origin: string = '';
  title: string = '';
  cookie: string = '';
}

export class TalebookApiClient {
  static check(body: string): void {
    if (!body.trim().startsWith('{')) throw new Error('NAS 未返回 Talebook 接口数据');
    const response: TalebookResponse = JSON.parse(body);
    if (response.err === 'not_invited' || response.err === 'not_login') {
      throw new Error('Talebook 会话已失效，请在书源的登录入口重新连接');
    }
    if (response.err && response.err !== 'ok' && response.err !== 'free') {
      throw new Error(response.msg || `Talebook 请求失败：${response.err}`);
    }
  }

  static address(sourceUrl: string, path: string): string {
    const origin = TalebookSourceIdentity.origin(sourceUrl);
    let target = LocalRuleUrlAnalyzer.resolveUrl(`${origin}/`, path);
    if (path.endsWith('/') && !target.endsWith('/')) target += '/';
    if (LocalRuleUrlAnalyzer.origin(target) !== origin || target.includes('@')) {
      throw new Error('Talebook 返回了非本站资源地址');
    }
    return target;
  }

  static async request(sourceUrl: string, path: string, json: boolean = true): Promise<string> {
    const source = await LocalRuleSourceRepository.get(sourceUrl);
    if (source === undefined || !TalebookSourceIdentity.isSourceUrl(sourceUrl)) {
      throw new Error('Talebook 书源已删除，请重新添加');
    }
    const address = TalebookApiClient.address(sourceUrl, path);
    // 禁止跨站重定向；原生适配只使用同一 NAS 的接口。
    const options: Record<string, Object> = { 'redirect': false };
    const result = await LocalRuleHttpClient.fetch(source, `${address},${JSON.stringify(options)}`);
    TalebookApiClient.assertFetch(result);
    if (json || result.body.trim().startsWith('{')) TalebookApiClient.check(result.body);
    return result.body;
  }

  static async connect(address: string, code: string): Promise<TalebookConnection> {
    const origin = TalebookSourceIdentity.origin(address);
    const plan = new LocalRuleRequestPlan();
    plan.url = `${origin}/api/welcome`;
    plan.method = code.trim() ? 'POST' : 'GET';
    plan.followRedirects = false;
    plan.headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
    if (code.trim()) plan.body = `invite_code=${encodeURIComponent(code.trim())}`;
    const login = await LocalRuleHttpClient.execute(plan);
    TalebookApiClient.assertFetch(login);
    TalebookApiClient.check(login.body);
    const connection = new TalebookConnection();
    connection.origin = origin;
    const cookies: string[] = [];
    for (const key of Object.keys(login.headers)) {
      if (key.toLowerCase() !== 'set-cookie') continue;
      for (const line of login.headers[key].split(new RegExp('\\r?\\n|,(?=\\s*[A-Za-z0-9_-]+=)'))) {
        const pair = line.trim().split(';')[0];
        if (pair.startsWith('invited=')) cookies.push(pair);
      }
    }
    connection.cookie = cookies.join('; ');
    const infoPlan = new LocalRuleRequestPlan();
    infoPlan.url = `${origin}/api/user/info`;
    infoPlan.headers = { 'Cookie': connection.cookie };
    const info = await LocalRuleHttpClient.execute(infoPlan);
    TalebookApiClient.assertFetch(info);
    TalebookApiClient.check(info.body);
    const details: TalebookResponse = JSON.parse(info.body);
    if (!details.sys || !details.sys.version) throw new Error('无法识别 Talebook 版本，请检查 NAS 地址');
    connection.title = details.sys.title || 'Talebook';
    return connection;
  }

  static async install(connection: TalebookConnection, reconnectSource: string = ''): Promise<void> {
    const sources: LocalRuleSource[] = [];
    if (reconnectSource) {
      const installed = await LocalRuleSourceRepository.get(reconnectSource);
      if (installed === undefined || TalebookSourceIdentity.origin(reconnectSource) !== connection.origin) {
        throw new Error('重新登录的 NAS 地址与书源不一致');
      }
      sources.push(installed);
    } else {
      for (const audio of [false, true]) {
        const definition = TalebookSourceIdentity.create(connection.origin, connection.title, audio);
        const existing = await LocalRuleSourceRepository.get(definition.bookSourceUrl);
        // 已安装的定义、锁定和启用状态不因重新连接而改变。
        sources.push(existing ?? definition);
      }
      const missing: LocalRuleSource[] = [];
      for (const source of sources) {
        if (await LocalRuleSourceRepository.get(source.bookSourceUrl) === undefined) missing.push(source);
      }
      if (missing.length > 0) await LocalRuleSourceRepository.upsertImportedBatch(missing);
    }
    for (const source of sources) {
      await LocalRuleHttpClient.saveWebCookies(source.bookSourceUrl, `${connection.origin}/`, connection.cookie);
    }
  }

  private static assertFetch(result: LocalRuleFetchResult): void {
    if (!result.ok || result.statusCode >= 300) {
      throw new Error(`Talebook 连接失败：${result.errorMessage || 'HTTP ' + result.statusCode}。仅 IPv6 的 NAS 需要当前网络支持 IPv6。`);
    }
  }
}
