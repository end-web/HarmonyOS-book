import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { url } from '@kit.ArkTS';

/** Device-local, explicit host exceptions; never included in source exports or backups. */
export class LocalRuleTlsTrustStore {
  private static store: preferences.Preferences | undefined = undefined;
  private static loading: Promise<void> | undefined = undefined;
  private static writes: Promise<void> = Promise.resolve();
  private static hosts: string[] = [];

  static async init(context: common.BaseContext): Promise<void> {
    if (LocalRuleTlsTrustStore.store !== undefined) return;
    if (LocalRuleTlsTrustStore.loading === undefined) {
      LocalRuleTlsTrustStore.loading = LocalRuleTlsTrustStore.load(context);
    }
    try {
      await LocalRuleTlsTrustStore.loading;
    } finally {
      LocalRuleTlsTrustStore.loading = undefined;
    }
  }

  private static async load(context: common.BaseContext): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'local_rule_tls_trust' });
    const raw = await store.get('hosts', '[]');
    const hosts: string[] = [];
    if (typeof raw === 'string') {
      try {
        const items: Object[] = JSON.parse(raw);
        if (Array.isArray(items)) {
          for (const item of items.slice(0, 256)) {
            if (typeof item !== 'string') continue;
            const host = LocalRuleTlsTrustStore.normalizeHost(item);
            if (host && !hosts.includes(host)) hosts.push(host);
          }
        }
      } catch (_error) { /* Invalid local data grants no certificate exceptions. */ }
    }
    LocalRuleTlsTrustStore.hosts = hosts.sort();
    LocalRuleTlsTrustStore.store = store;
  }

  static async listTrustedHosts(): Promise<string[]> {
    if (LocalRuleTlsTrustStore.loading !== undefined) await LocalRuleTlsTrustStore.loading;
    await LocalRuleTlsTrustStore.writes;
    return LocalRuleTlsTrustStore.hosts.slice();
  }

  static async isTrustedUrl(address: string): Promise<boolean> {
    await LocalRuleTlsTrustStore.listTrustedHosts();
    return LocalRuleTlsTrustStore.isTrustedUrlSync(address);
  }

  static isTrustedUrlSync(address: string): boolean {
    const host = LocalRuleTlsTrustStore.hostFromUrl(address);
    return host.length > 0 && LocalRuleTlsTrustStore.hosts.includes(host);
  }

  static async trustHosts(hosts: string[]): Promise<void> {
    const normalized: string[] = [];
    for (const item of hosts) {
      const host = LocalRuleTlsTrustStore.normalizeHost(item);
      if (!host) throw new Error('证书主机无效');
      if (!normalized.includes(host)) normalized.push(host);
    }
    await LocalRuleTlsTrustStore.change(normalized, '');
  }

  static async revokeHost(host: string): Promise<void> {
    const normalized = LocalRuleTlsTrustStore.normalizeHost(host);
    if (!normalized) throw new Error('证书主机无效');
    await LocalRuleTlsTrustStore.change([], normalized);
  }

  private static async change(additions: string[], removed: string): Promise<void> {
    if (LocalRuleTlsTrustStore.loading !== undefined) await LocalRuleTlsTrustStore.loading;
    const pending = LocalRuleTlsTrustStore.writes.then(async (): Promise<void> => {
      const store = LocalRuleTlsTrustStore.store;
      if (store === undefined) throw new Error('证书信任存储尚未初始化');
      const next = LocalRuleTlsTrustStore.hosts.filter((host: string): boolean => host !== removed);
      for (const host of additions) if (!next.includes(host)) next.push(host);
      if (next.length > 256) throw new Error('证书信任主机超过 256 个');
      next.sort();
      await store.put('hosts', JSON.stringify(next));
      await store.flush();
      LocalRuleTlsTrustStore.hosts = next;
    });
    LocalRuleTlsTrustStore.writes = pending.catch((): void => {});
    await pending;
  }

  static hostFromUrl(address: string): string {
    try {
      const parsed = new url.URL(address.trim());
      if (parsed.protocol !== 'https:' || parsed.username || parsed.password) return '';
      return parsed.hostname.toLowerCase();
    } catch (_error) {
      return '';
    }
  }

  private static normalizeHost(host: string): string {
    const clean = host.trim().toLowerCase();
    if (!clean || /[\s\/@?#*]/.test(clean)) return '';
    const parsed = LocalRuleTlsTrustStore.hostFromUrl(`https://${clean}/`);
    return parsed === clean ? parsed : '';
  }

  static isCertificateError(reason: string): boolean {
    return /2300060|1007900060|1007900051|invalid ssl peer certificate|certificate.*(?:verify|verification|validation|expired|self.signed)|SSL peer certificate|证书校验失败/i.test(reason);
  }

  static certificateErrorHost(reason: string, fallbackUrl: string = ''): string {
    if (!LocalRuleTlsTrustStore.isCertificateError(reason)) return '';
    const marked = reason.match(/证书主机\s*[：:]\s*([^\s）：)]+)/);
    return marked !== null ? LocalRuleTlsTrustStore.normalizeHost(marked[1]) :
      LocalRuleTlsTrustStore.hostFromUrl(fallbackUrl);
  }

  static describeFailure(reason: string, address: string): string {
    if (!LocalRuleTlsTrustStore.isCertificateError(reason) || reason.includes('证书主机')) return reason;
    const host = LocalRuleTlsTrustStore.hostFromUrl(address);
    return host ? `证书校验失败（证书主机：${host}）：${reason}` : reason;
  }
}
