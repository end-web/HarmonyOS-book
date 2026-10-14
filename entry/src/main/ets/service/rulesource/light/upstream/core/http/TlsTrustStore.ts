import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/**
 * Local, user-controlled exceptions for hosts whose TLS certificate cannot be
 * validated by the system trust store. Trust is exact-host only: trusting
 * example.com never trusts subdomains, sibling domains, or redirect targets.
 */
export class TlsTrustStore {
  private static readonly STORE_NAME: string = 'tls_trust_settings';
  private static readonly KEY_TRUSTED_HOSTS: string = 'trustedHosts';
  private static trustedHosts: Set<string> = new Set<string>();
  private static loaded: boolean = false;

  static async load(context: common.Context): Promise<void> {
    if (TlsTrustStore.loaded) return;
    const store = await preferences.getPreferences(context, TlsTrustStore.STORE_NAME);
    const raw = await store.get(TlsTrustStore.KEY_TRUSTED_HOSTS, '[]');
    const hosts = new Set<string>();
    try {
      const values = JSON.parse(typeof raw === 'string' ? raw : '[]') as string[];
      for (const value of values) {
        const host = TlsTrustStore.normalizeHost(value);
        if (host) hosts.add(host);
      }
    } catch (_) {}
    TlsTrustStore.trustedHosts = hosts;
    TlsTrustStore.loaded = true;
  }

  static isTrustedUrl(url: string): boolean {
    return TlsTrustStore.isTrustedHost(TlsTrustStore.hostFromUrl(url));
  }

  static isTrustedHost(host: string): boolean {
    const normalized = TlsTrustStore.normalizeHost(host);
    return !!normalized && TlsTrustStore.trustedHosts.has(normalized);
  }

  static async trustHosts(context: common.Context, hosts: string[]): Promise<void> {
    await TlsTrustStore.load(context);
    for (const value of hosts) {
      const host = TlsTrustStore.normalizeHost(value);
      if (host) TlsTrustStore.trustedHosts.add(host);
    }
    await TlsTrustStore.persist(context);
  }

  static async revokeHost(context: common.Context, host: string): Promise<void> {
    await TlsTrustStore.load(context);
    const normalized = TlsTrustStore.normalizeHost(host);
    if (normalized) TlsTrustStore.trustedHosts.delete(normalized);
    await TlsTrustStore.persist(context);
  }

  static hostFromUrl(url: string): string {
    const match = (url || '').trim().match(/^https?:\/\/([^\/:?#]+)/i);
    return match && match[1] ? TlsTrustStore.normalizeHost(match[1]) : '';
  }

  static certificateErrorHost(reason: string, fallbackUrl: string = ''): string {
    if (!TlsTrustStore.isCertificateError(reason)) return '';
    const marked = (reason || '').match(/证书主机\s*[：:]\s*([A-Za-z0-9.-]+)/i);
    return marked && marked[1] ? TlsTrustStore.normalizeHost(marked[1]) :
      TlsTrustStore.hostFromUrl(fallbackUrl);
  }

  static isCertificateError(reason: string): boolean {
    return /2300060|invalid ssl peer certificate|certificate (?:verify|validation)|证书校验失败/i
      .test(reason || '');
  }

  private static async persist(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, TlsTrustStore.STORE_NAME);
    await store.put(TlsTrustStore.KEY_TRUSTED_HOSTS,
      JSON.stringify(Array.from(TlsTrustStore.trustedHosts).sort()));
    await store.flush();
  }

  private static normalizeHost(host: string): string {
    const value = (host || '').trim().toLowerCase().replace(/^\[|\]$/g, '');
    return /^[a-z0-9.-]+$/.test(value) && value.includes('.') ? value : '';
  }
}
