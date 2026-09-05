import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleControl, LocalRulePanel, LocalRulePanelAction } from '../../model/LocalRulePanel';
import { LocalRuleScriptState } from '../../model/LocalRuleScriptState';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';
import { LocalRuleScriptRuntime } from './LocalRuleScriptRuntime';

export class LocalRulePanelService {
  static async load(source: LocalRuleSource, login: boolean,
    variables: Record<string, string> = {}): Promise<LocalRulePanel> {
    const rule = login ? source.loginUi : source.exploreUrl;
    const value = LocalRuleScriptRuntime.hasScript(rule)
      ? await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        (login ? LocalRulePanelService.loginLibrary(source) : '') + (LocalRuleScriptRuntime.standaloneCode(rule) || rule), source, variables) : rule;
    const panel = LocalRulePanelService.parse(value);
    if (login && LocalRuleSourceRepository.isInitialized()) {
      const state = LocalRuleScriptState.parse(await LocalRuleSourceRepository.readScriptState(source.bookSourceUrl));
      if (state.loginInfo) {
        const saved: Record<string, Object> = JSON.parse(state.loginInfo);
        for (const control of panel.controls) {
          if (saved[control.title] !== undefined) control.value = LocalRulePanelService.scalar(saved[control.title]);
        }
      }
    }
    return panel;
  }

  static parse(value: string): LocalRulePanel {
    if (value.length > 512 * 1024) throw new Error('书源面板超过 512 KiB');
    const panel = new LocalRulePanel();
    const clean = value.trim();
    if (!clean) return panel;
    if (!clean.startsWith('[')) {
      for (const line of clean.split(new RegExp('\\r?\\n|&&'))) {
        const split = line.indexOf('::');
        if (split <= 0) continue;
        const entry = new LocalRuleControl();
        entry.title = line.substring(0, split).trim();
        entry.url = line.substring(split + 2).trim();
        entry.type = 'category';
        entry.id = `${entry.title}:${entry.url}`;
        panel.entries.push(entry);
      }
      return panel;
    }
    const items: Object[] = JSON.parse(clean);
    const seen = new Set<string>();
    LocalRulePanelService.appendItems(items, panel, seen, '', 0);
    return panel;
  }

  private static appendItems(items: Object[], panel: LocalRulePanel, seen: Set<string>,
    parent: string, depth: number): void {
    if (depth > 8) throw new Error('书源面板分组层级超过 8 层');
    let group = parent;
    for (const item of items) {
      if (seen.size >= 1000) throw new Error('书源面板项目超过 1000 项');
      if (item === null || typeof item !== 'object' || Array.isArray(item)) continue;
      const row: Record<string, Object> = JSON.parse(JSON.stringify(item));
      const control = new LocalRuleControl();
      control.title = LocalRulePanelService.scalar(row['title'] ?? row['name'] ?? row['viewName']);
      if (!control.title) continue;
      control.url = LocalRulePanelService.scalar(row['url']);
      control.action = LocalRulePanelService.scalar(row['action']);
      control.type = LocalRulePanelService.scalar(row['type']) || (control.url ? 'category' :
        control.action ? 'button' : 'group');
      const children = row['children'] ?? row['items'] ?? (Array.isArray(row['url']) ? row['url'] : undefined);
      if (Array.isArray(children)) {
        control.type = 'group';
        control.url = '';
      }
      const types: string[] = ['category', 'group', 'select', 'toggle', 'switch', 'checkbox', 'button',
        'text', 'input', 'password', 'number', 'email'];
      if (!types.includes(control.type.toLowerCase())) control.type = control.action ? 'button' : 'text';
      else control.type = control.type.toLowerCase();
      control.value = LocalRulePanelService.scalar(row['value'] ?? row['default'] ?? row['defaultValue']);
      control.placeholder = LocalRulePanelService.scalar(row['placeholder']);
      if (Array.isArray(row['chars'])) {
        const options: Object[] = JSON.parse(JSON.stringify(row['chars']));
        for (const option of options.slice(0, 200)) {
          if (option !== null && typeof option === 'object') {
            const pair: Record<string, Object> = JSON.parse(JSON.stringify(option));
            const label = LocalRulePanelService.scalar(pair['label'] ?? pair['title'] ?? pair['name'] ?? pair['value']);
            control.options.push(label);
            control.optionValues.push(LocalRulePanelService.scalar(pair['value'] ?? label));
          } else {
            control.options.push(LocalRulePanelService.scalar(option));
            control.optionValues.push(LocalRulePanelService.scalar(option));
          }
        }
      } else if (typeof row['chars'] === 'string') {
        control.options = String(row['chars']).split(new RegExp('[,|\\n]')).slice(0, 200);
        control.optionValues = control.options.slice();
      }
      if (control.type === 'select' && control.value.length === 0) control.value = control.optionValues[0] ?? '';
      if (control.type === 'group') group = control.title;
      control.group = parent || group;
      control.id = `${group}:${control.type}:${control.title}:${control.url}`;
      if (seen.has(control.id)) continue;
      seen.add(control.id);
      if (control.url || control.type === 'group') panel.entries.push(control);
      else panel.controls.push(control);
      if (Array.isArray(children)) {
        const nested: Object[] = JSON.parse(JSON.stringify(children));
        LocalRulePanelService.appendItems(nested, panel, seen, `${parent ? parent + '/' : ''}${control.title}`, depth + 1);
      }
    }
  }

  static async act(source: LocalRuleSource, control: LocalRuleControl,
    controls: LocalRuleControl[], login: boolean): Promise<LocalRulePanelAction> {
    const values: Record<string, string> = {};
    for (const input of controls) values[input.title] = input.value;
    const variables: Record<string, string> = { 'infoMap': JSON.stringify(values) };
    const code = LocalRuleScriptRuntime.standaloneCode(control.action) || control.action;
    const response = await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
      `${login ? LocalRulePanelService.loginLibrary(source) + 'source.putLoginInfo(infoMap);\n' : ''}${code}`, source, variables);
    if (login && !variables['__openBrowser']) await LocalRulePanelService.checkLogin(source, response, variables);
    const result = new LocalRulePanelAction();
    result.message = variables['__toast'] ?? '';
    result.searchKeyword = variables['__searchBook'] ?? '';
    result.refresh = login || variables['__refreshExplore'] === 'true';
    result.browserUrl = variables['__openBrowser'] ?? '';
    return result;
  }

  static async checkLogin(source: LocalRuleSource, content: string,
    variables: Record<string, string> = {}, baseUrl: string = source.bookSourceUrl): Promise<void> {
    if (!source.loginCheckJs.trim()) return;
    const check = LocalRuleScriptRuntime.standaloneCode(source.loginCheckJs) || source.loginCheckJs;
    const checked = await LocalRuleScriptRuntime.evaluate(content, baseUrl,
      LocalRulePanelService.loginLibrary(source) + check, source, variables, content);
    if (checked.trim().toLowerCase() === 'false') throw new Error('书源登录检查未通过');
  }

  private static loginLibrary(source: LocalRuleSource): string {
    const value = source.loginUrl.trim();
    if (!value || new RegExp('^https?://', 'i').test(value)) return '';
    return (LocalRuleScriptRuntime.standaloneCode(value) || value) + '\n';
  }

  private static scalar(value: Object | undefined): string {
    if (value === undefined || value === null) return '';
    return typeof value === 'object' ? JSON.stringify(value) : String(value);
  }
}
