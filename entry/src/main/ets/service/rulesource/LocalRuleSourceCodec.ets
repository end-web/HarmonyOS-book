import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleSourceImportParser } from './LocalRuleSourceImportParser';

/** Merge editable fields into the original definition so extension fields survive a round trip. */
export class LocalRuleSourceCodec {
  static stringify(source: LocalRuleSource): string {
    const original: Record<string, Object> = source.rawSourceJson.trim().length > 0
      ? JSON.parse(source.rawSourceJson) : {};
    const current: Record<string, Object> = JSON.parse(JSON.stringify(source));
    const originals = LocalRuleSourceImportParser.parse(source.rawSourceJson).sources;
    const baseline: Record<string, Object> = originals.length === 1 ? JSON.parse(JSON.stringify(originals[0])) : {};
    const result: Record<string, Object> = {};
    const omitted: string[] = ['rawSourceJson', 'validationStatus', 'validationMessage'];
    for (const key of Object.keys(original)) {
      if (!omitted.includes(key)) result[key] = original[key];
    }
    const groups: string[] = ['ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent'];
    for (const key of Object.keys(current)) {
      if (omitted.includes(key)) continue;
      if (groups.includes(key)) {
        result[key] = original[key] !== undefined && JSON.stringify(current[key]) === JSON.stringify(baseline[key])
          ? original[key] : LocalRuleSourceCodec.mergeGroup(original[key], current[key]);
      } else {
        result[key] = current[key];
      }
    }
    return JSON.stringify(result);
  }

  private static mergeGroup(original: Object | undefined, current: Object): Record<string, Object> {
    const result: Record<string, Object> = {};
    if (original !== undefined && original !== null && typeof original === 'object' && !Array.isArray(original)) {
      const fields: Record<string, Object> = JSON.parse(JSON.stringify(original));
      for (const key of Object.keys(fields)) result[key] = fields[key];
    }
    const edited: Record<string, Object> = JSON.parse(JSON.stringify(current));
    for (const key of Object.keys(edited)) result[key] = edited[key];
    return result;
  }
}
