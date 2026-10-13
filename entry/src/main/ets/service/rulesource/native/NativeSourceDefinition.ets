import { LocalRuleSource, LocalRuleSourceStatus } from '../../../model/LocalRuleSource';
import { LocalRuleControl, LocalRulePanel } from '../../../model/LocalRulePanel';
import { NativeRuleDefinition, NativeRuleSchema } from './NativeRuleSchema';

/** Native definitions share source identities, management and encrypted persistence with imported sources. */
export class NativeSourceDefinition {
  static configure(source: LocalRuleSource, mixedLegacyRules: boolean = false): void {
    source.nativeRulesValid = false;
    source.nativeSearch = false;
    try {
      if (source.engine !== 'native-v1') throw new Error('不支持的原生书源引擎版本');
      if (mixedLegacyRules) throw new Error('原生书源不能混用旧版请求或提取规则，请迁移到 nativeRules');
      if (source.jsLib || source.loginCheckJs || source.loginUi || source.loginUrl) {
        throw new Error('原生书源不接受脚本库或旧版登录规则');
      }
      const rules = NativeRuleSchema.parse(source.nativeRulesJson);
      source.nativeRulesJson = JSON.stringify(rules);
      source.nativeSearch = rules.search.request.url.value.length > 0 && rules.search.list.value.length > 0 &&
        rules.search.fields.some(field => field.name === 'name') &&
        rules.search.fields.some(field => field.name === 'bookUrl');
      source.exploreUrl = JSON.stringify(rules.discover);
      if (rules.discover.length === 0) source.exploreUrl = '';
      source.nativeRulesValid = true;
      source.validationStatus = LocalRuleSourceStatus.UNCHECKED;
      source.validationMessage = '';
    } catch (error) {
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      source.validationMessage = error instanceof Error ? error.message : '原生书源规则格式错误';
    }
  }

  static rules(source: LocalRuleSource): NativeRuleDefinition {
    if (!source.canExecute() || source.engine !== 'native-v1') {
      throw new Error(source.validationMessage || '原生书源不可执行');
    }
    return NativeRuleSchema.parse(source.nativeRulesJson);
  }

  static panel(source: LocalRuleSource): LocalRulePanel {
    const panel = new LocalRulePanel();
    for (const item of NativeSourceDefinition.rules(source).discover) {
      const control = new LocalRuleControl();
      control.id = `${item.title}:${item.url}`;
      control.title = item.title;
      control.url = item.url;
      control.type = 'category';
      panel.entries.push(control);
    }
    return panel;
  }
}
