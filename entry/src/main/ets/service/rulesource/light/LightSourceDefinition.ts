import { NativeSourceSpec } from './upstream/core/nativesource/NativeSourceSpec';
import { NativeSourceService } from './upstream/LightNativeImport';
import { LightSourceImport } from './upstream/LightSourceImport';

/** Import validation does not initialize network, scripts or runtime singletons. */
export class LightSourceDefinition {
  static appDefinition(raw: string): string {
    const value = JSON.parse(raw) as Record<string, Object>;
    if (value.format || value.engine === 'native-v1' || value.nativeRules) {
      throw new Error('此定义属于已停用的简听规则格式，请导入轻页支持的书源');
    }
    const native = NativeSourceSpec.isDefinitionObject(value);
    const source = native ? NativeSourceService.importObject(value) : new LightSourceImport().parseBookSource(value);
    if (!source.bookSourceUrl || !source.bookSourceName) throw new Error('书源缺少名称或地址');
    return JSON.stringify({...source, engine: native ? 'light-native' : 'light', nativeSearch: !!source.searchUrl,
      ruleSearch: source.searchRule, ruleExplore: source.exploreRule, ruleBookInfo: source.bookInfoRule,
      ruleToc: source.tocRule, ruleContent: source.contentRule, rawSourceJson: raw});
  }
  static normalizeDefinition(raw: string): string {
    const value = JSON.parse(raw) as Record<string, Object>;
    return JSON.stringify(NativeSourceSpec.isDefinitionObject(value) ? NativeSourceService.importObject(value) :
      new LightSourceImport().parseBookSource(value));
  }
}
