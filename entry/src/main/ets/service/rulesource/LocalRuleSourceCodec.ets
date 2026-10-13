import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleSourceImportParser } from './LocalRuleSourceImportParser';
import { NativeSourceFile } from './native/NativeSourceFile';

/** Merge editable fields into the original definition so extension fields survive a round trip. */
export class LocalRuleSourceCodec {
  static exportBatch(sources: LocalRuleSource[]): string {
    const definitions: Record<string, Object>[] = [];
    for (const source of sources) {
      const definition: Record<string, Object> = JSON.parse(LocalRuleSourceCodec.stringify(source));
      definitions.push(definition);
    }
    return JSON.stringify(definitions);
  }

  static stringify(source: LocalRuleSource): string {
    if (source.engine === 'native-v1') {
      if (!source.nativeRulesValid) return source.rawSourceJson;
      return NativeSourceFile.stringify(source);
    }
    const original: Record<string, Object> = source.rawSourceJson.trim().length > 0
      ? JSON.parse(source.rawSourceJson) : {};
    const current: Record<string, Object> = JSON.parse(JSON.stringify(source));
    const originals = LocalRuleSourceImportParser.parse(source.rawSourceJson).sources;
    const baselineSource = originals.length === 1 ? originals[0] : new LocalRuleSource();
    // The parser supplies the current time when the definition has no timestamp.
    // It is an import default, not an edit to the portable definition.
    if (originals.length === 1 && original['lastUpdateTime'] === undefined) {
      baselineSource.lastUpdateTime = source.lastUpdateTime;
    }
    const baseline: Record<string, Object> = JSON.parse(JSON.stringify(baselineSource));
    const result: Record<string, Object> = {};
    const omitted: string[] = ['rawSourceJson', 'nativeBaseUrl', 'nativeRulesJson', 'nativeRulesValid', 'nativeSearch',
      'validationStatus', 'validationMessage', 'locked',
      'loginHeader', 'loginInfo', 'loginResult', 'cookie', 'cookies', 'cookieHeader',
      'token', 'accessToken', 'refreshToken', 'deviceId', 'accountLabel', 'session', 'scriptState'];
    for (const key of Object.keys(original)) {
      if (!omitted.includes(key)) result[key] = original[key];
    }
    const groups: string[] = ['ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent'];
    for (const key of Object.keys(current)) {
      if (omitted.includes(key)) continue;
      const needsExploreFlag = key === 'enabledExplore' && original[key] === undefined &&
        source.enabledExplore !== (source.exploreUrl.length > 0);
      if (originals.length === 1 && JSON.stringify(current[key]) === JSON.stringify(baseline[key]) &&
        !(key === 'isLocked' && original['locked'] !== undefined) && !needsExploreFlag) continue;
      if (groups.includes(key)) {
        result[key] = LocalRuleSourceCodec.mergeGroup(original[key], current[key], baseline[key]);
      } else {
        result[key] = current[key];
      }
    }
    return JSON.stringify(result);
  }

  private static mergeGroup(original: Object | undefined, current: Object,
    baseline: Object): Record<string, Object> {
    const result: Record<string, Object> = {};
    const hasOriginalFields = original !== undefined && original !== null &&
      typeof original === 'object' && !Array.isArray(original);
    if (hasOriginalFields) {
      const fields: Record<string, Object> = JSON.parse(JSON.stringify(original));
      for (const key of Object.keys(fields)) result[key] = fields[key];
    }
    const edited: Record<string, Object> = JSON.parse(JSON.stringify(current));
    const previous: Record<string, Object> = JSON.parse(JSON.stringify(baseline));
    for (const key of Object.keys(edited)) {
      if (hasOriginalFields && JSON.stringify(edited[key]) === JSON.stringify(previous[key])) continue;
      if (!hasOriginalFields && edited[key] === '') continue;
      result[key] = edited[key];
    }
    return result;
  }
}
