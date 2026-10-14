import { WebEngineGate } from '../../WebEngineGate';
import { LocalRuleWebSession } from '../LocalRuleWebSession';
import { LightSourceHost, LightLocalSource } from './LightSourceHost';
import { LightSourceSandbox } from './LightSourceSandbox';
import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { LocalRuleSourceCodec } from '../LocalRuleSourceCodec';
import { LocalRuleBrowserLoginCoordinator } from '../LocalRuleBrowserLoginCoordinator';
import { LightSourceCookies as LocalRuleHttpClient } from './LightSourceCookies';

export class LightSourceAppHost implements LightSourceHost {
  keepWebSession: boolean = false;
  constructor(keepWebSession: boolean = false) { this.keepWebSession = keepWebSession; }
  async acquireWeb(): Promise<number> {
    WebEngineGate.instance.needRuleBrowser = true;
    return LocalRuleWebSession.acquire(20000);
  }
  releaseWeb(lease: number): void { LocalRuleWebSession.release(lease); }
  static serialize(source: LocalRuleSource, keepWebSession: boolean = false): string {
    const local = new LightLocalSource();
    local.keepWebSession = keepWebSession;
    local.bookSourceUrl = source.bookSourceUrl;
    local.variable = source.variable;
    local.definition = LocalRuleSourceCodec.stringify(source);
    local.rawSourceJson = JSON.stringify(source);
    local.engine = source.engine;
    local.enabledExplore = source.enabledExplore;
    return JSON.stringify(local);
  }
  async evaluate(script: string, sourceUrl: string, timingId: number = 0): Promise<string> {
    return LightSourceSandbox.evaluate(script, sourceUrl, timingId);
  }
  async hydrate(url: string): Promise<string> {
    await LocalRuleHttpClient.hydrateCookies(url);
    return JSON.stringify(await LocalRuleHttpClient.getCookieSnapshot(url));
  }
  async getSource(url: string): Promise<string> {
    if (!LocalRuleSourceRepository.isInitialized()) return '';
    const source = await LocalRuleSourceRepository.get(url);
    return source ? LightSourceAppHost.serialize(source) : '';
  }
  async listSources(): Promise<string> {
    if (!LocalRuleSourceRepository.isInitialized()) return '[]';
    const values: LightLocalSource[] = [];
    for (const source of await LocalRuleSourceRepository.list()) {
      if (!source.enabled) continue;
      const value: LightLocalSource = JSON.parse(LightSourceAppHost.serialize(source));
      values.push(value);
    }
    return JSON.stringify(values);
  }
  async readState(url: string): Promise<string> {
    return LocalRuleSourceRepository.isInitialized() ? await LocalRuleSourceRepository.readScriptState(url) : '';
  }
  async writeState(url: string, state: string): Promise<void> {
    if (LocalRuleSourceRepository.isInitialized()) await LocalRuleSourceRepository.writeScriptState(url, state);
  }
  async saveCookies(sourceUrl: string, origin: string, cookies: string): Promise<void> {
    await LocalRuleHttpClient.saveWebCookies(sourceUrl, origin, cookies, true);
  }
  async fetch(_serialized: string, _address: string, _sniff: boolean): Promise<string> {
    throw new Error('旧网页请求入口已停用');
  }
  async browse(sourceUrl: string, sourceName: string, address: string, html: string,
    injectJs: string): Promise<string> {
    return LocalRuleBrowserLoginCoordinator.request(sourceUrl, sourceName, address, html, injectJs);
  }
}
