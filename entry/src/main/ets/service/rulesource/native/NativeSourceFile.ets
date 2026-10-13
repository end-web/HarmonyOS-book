import { url } from '@kit.ArkTS';
import { LocalRuleSource, LocalRuleSourceStatus } from '../../../model/LocalRuleSource';
import { NativeRuleDefinition, NativeRuleSchema, NativeNamedValue, NativeDiscovery, NativeStage } from './NativeRuleSchema';
import { NativeSourceDefinition } from './NativeSourceDefinition';

class NativeSourceMetadata {
  id: string = '';
  name: string = '';
  type: string = 'text';
  baseUrl: string = '';
  group: string = '';
  description: string = '';
}

class NativeSourceSettings {
  enabled: boolean = true;
  discoveryEnabled: boolean = true;
  locked: boolean = false;
  pinned: boolean = false;
  order: number = 0;
}

class NativeSourceEnvelope {
  format: string = 'jianting.source';
  version: number = 1;
  source: NativeSourceMetadata = new NativeSourceMetadata();
  rules: NativeRuleDefinition = new NativeRuleDefinition();
  settings: NativeSourceSettings | undefined = undefined;
}

class NativePublicRules {
  headers: NativeNamedValue[] = [];
  discover: NativeDiscovery[] = [];
  search: NativeStage = new NativeStage();
  explore: NativeStage = new NativeStage();
  detail: NativeStage = new NativeStage();
  toc: NativeStage = new NativeStage();
  content: NativeStage = new NativeStage();
}

class NativePublicEnvelope {
  format: string = 'jianting.source';
  version: number = 1;
  source: NativeSourceMetadata = new NativeSourceMetadata();
  rules: NativePublicRules = new NativePublicRules();
  settings: NativeSourceSettings = new NativeSourceSettings();
}

/** The portable format is independent from the legacy importer and its field names. */
export class NativeSourceFile {
  static parse(json: string): LocalRuleSource | undefined {
    if (!json || json.length > 512 * 1024) throw new Error('原生书源文件为空或超过单源大小限制');
    const raw: NativeSourceEnvelope = JSON.parse(json);
    NativeSourceFile.shape(raw, ['format', 'version', 'source', 'rules', 'settings']);
    if (raw.format !== 'jianting.source') throw new Error('不是简听原生书源格式');
    NativeSourceFile.shape(raw.source, ['id', 'name', 'type', 'baseUrl', 'group', 'description']);
    const id = NativeSourceFile.string(raw.source.id, '', 2048);
    const name = NativeSourceFile.string(raw.source.name, '', 256);
    if (!id || !name) return undefined;
    NativeSourceFile.address(id);
    const source = new LocalRuleSource();
    source.engine = 'native-v1';
    source.bookSourceUrl = id;
    source.bookSourceName = name;
    source.rawSourceJson = json;
    source.nativeBaseUrl = NativeSourceFile.string(raw.source.baseUrl, '', 2048);
    NativeSourceFile.address(source.nativeBaseUrl);
    const type = NativeSourceFile.string(raw.source.type, '', 16);
    if (type !== 'audio' && type !== 'text') throw new Error('原生书源 type 只支持 audio/text');
    source.bookSourceType = type === 'audio' ? 1 : 0;
    source.bookSourceGroup = NativeSourceFile.string(raw.source.group, '', 256);
    source.bookSourceComment = NativeSourceFile.string(raw.source.description, '', 8192);
    source.lastUpdateTime = Date.now();
    if (raw.settings !== undefined) {
      NativeSourceFile.shape(raw.settings, ['enabled', 'discoveryEnabled', 'locked', 'pinned', 'order']);
      source.enabled = NativeSourceFile.boolean(raw.settings.enabled, true);
      source.enabledExplore = NativeSourceFile.boolean(raw.settings.discoveryEnabled, true);
      source.isLocked = NativeSourceFile.boolean(raw.settings.locked, false);
      source.isPinned = NativeSourceFile.boolean(raw.settings.pinned, false);
      if (raw.settings.order !== undefined && !Number.isSafeInteger(raw.settings.order)) {
        throw new Error('原生书源排序值必须为安全整数');
      }
      source.customOrder = raw.settings.order ?? 0;
    } else source.enabledExplore = true;
    if (raw.version !== 1) {
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      source.validationMessage = '不支持的简听原生书源版本';
      return source;
    }
    NativeSourceFile.shape(raw.rules, ['version', 'headers', 'discover', 'search', 'explore', 'detail', 'toc', 'content']);
    if (raw.rules.version !== undefined && raw.rules.version !== 1) throw new Error('规则版本与文件版本冲突');
    const rules = new NativeRuleDefinition();
    rules.headers = raw.rules.headers;
    rules.discover = raw.rules.discover;
    rules.search = raw.rules.search;
    rules.explore = raw.rules.explore;
    rules.detail = raw.rules.detail;
    rules.toc = raw.rules.toc;
    rules.content = raw.rules.content;
    source.nativeRulesJson = JSON.stringify(NativeRuleSchema.parse(JSON.stringify(rules)));
    NativeSourceDefinition.configure(source);
    return source;
  }

  static stringify(source: LocalRuleSource): string {
    const rules = NativeRuleSchema.parse(source.nativeRulesJson);
    const result = new NativePublicEnvelope();
    result.source.id = source.bookSourceUrl;
    result.source.name = source.bookSourceName;
    result.source.type = source.isAudio() ? 'audio' : 'text';
    result.source.baseUrl = source.nativeBaseUrl || source.bookSourceUrl;
    result.source.group = source.bookSourceGroup;
    result.source.description = source.bookSourceComment;
    result.rules.headers = rules.headers;
    result.rules.discover = rules.discover;
    result.rules.search = rules.search;
    result.rules.explore = rules.explore;
    result.rules.detail = rules.detail;
    result.rules.toc = rules.toc;
    result.rules.content = rules.content;
    result.settings.enabled = source.enabled;
    result.settings.discoveryEnabled = source.enabledExplore;
    result.settings.locked = source.isLocked;
    result.settings.pinned = source.isPinned;
    result.settings.order = source.customOrder;
    return JSON.stringify(result);
  }

  private static shape(value: NativeSourceEnvelope | NativeSourceMetadata | NativeSourceSettings | NativeRuleDefinition,
    keys: string[]): void {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('原生书源节点必须为对象');
    for (const key of Object.keys(value)) if (!keys.includes(key)) throw new Error(`原生书源不支持字段：${key}`);
  }

  private static string(value: string | undefined, fallback: string, limit: number): string {
    if (value === undefined) return fallback;
    if (typeof value !== 'string' || value.length > limit) throw new Error('原生书源字符串类型或长度错误');
    return value.trim();
  }

  private static boolean(value: boolean | undefined, fallback: boolean): boolean {
    if (value === undefined) return fallback;
    if (typeof value !== 'boolean') throw new Error('原生书源设置必须为布尔值');
    return value;
  }

  private static address(value: string): void {
    try {
      if (!new RegExp('^https?://', 'i').test(value) || new RegExp('[\\s]').test(value)) throw new Error('invalid');
      const parsed = url.URL.parseURL(value);
      if (!parsed.hostname || parsed.username || parsed.password) throw new Error('invalid');
    } catch (_error) {
      throw new Error('原生书源 id/baseUrl 必须为不含账号密码的 HTTP(S) 地址');
    }
  }
}
