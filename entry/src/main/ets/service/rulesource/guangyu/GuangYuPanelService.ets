import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { LocalRuleControl, LocalRulePanel, LocalRulePanelAction } from '../../../model/LocalRulePanel';
import { LocalRuleScriptState } from '../../../model/LocalRuleScriptState';
import { JsonObj } from '../../builtin/JsonValue';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { GuangYuApiClient } from './GuangYuApiClient';
import { GuangYuAuthService } from './GuangYuAuthService';

/** 将源内 HTML 设置表单映射为原生控件，仍使用源定义的变量和动作。 */
export class GuangYuPanelService {
  static async settings(source: LocalRuleSource, action: string): Promise<LocalRulePanel | undefined> {
    if (action !== 'getServerSettings()' && action !== 'getHtmlSettings()' && action !== 'getSvgSettings()') return undefined;
    const state = LocalRuleScriptState.parse(await LocalRuleSourceRepository.readScriptState(source.bookSourceUrl));
    const root = new JsonObj(state.variable ? JSON.parse(state.variable) : undefined);
    const panel = new LocalRulePanel();
    if (action === 'getServerSettings()') {
      GuangYuPanelService.select(panel, root, '', '线路', GuangYuApiClient.hosts(), GuangYuApiClient.preferredHost());
      GuangYuPanelService.select(panel, root, '', '自动切换', ['true', 'false'], 'true');
      GuangYuPanelService.select(panel, root, '', '超时时间', ['5', '8', '10', '15', '30', '60'], '10');
    } else if (action === 'getSvgSettings()') {
      const review = root.getObj('段评设置');
      GuangYuPanelService.select(panel, review, '段评设置', '段评开关', ['true', 'false'], 'true');
      GuangYuPanelService.select(panel, review, '段评设置', '神评论开关', ['true', 'false'], 'true');
      GuangYuPanelService.select(panel, review, '段评设置', '本章说开关', ['true', 'false'], 'true');
    } else {
      const more = root.getObj('更多设置');
      GuangYuPanelService.select(panel, more, '更多设置', '搜索模式', ['小说', '听书'], '小说');
      for (const tab of ['小说', '听书']) {
        const control = new LocalRuleControl();
        control.id = `guangyu-setting-${tab}`;
        control.title = tab;
        control.type = 'text';
        control.value = more.getString(tab, '全部');
        control.action = GuangYuPanelService.setAction('更多设置', tab);
        panel.controls.push(control);
      }
      GuangYuPanelService.select(panel, more, '更多设置', '强制搜索', ['false', 'true'], 'false');
      GuangYuPanelService.select(panel, more, '更多设置', '目录显示来源', ['true', 'false'], 'true');
      GuangYuPanelService.select(panel, more, '更多设置', '网络模式', ['服务器', '本地'], '服务器');
      GuangYuPanelService.select(panel, root, '', '发现页类型', ['小说', '听书'], '小说');
      GuangYuPanelService.select(panel, root, '', '频道', ['男频', '女频'], '男频');
      const providers = root.getObj('云端配置').getArr(root.getString('发现页类型', '小说'));
      const choices: string[] = [];
      for (let i = 0; i < providers.length(); i++) choices.push(providers.getString(i));
      if (choices.length === 0) choices.push('番茄', '七猫', '书旗', '喜马拉雅', '酷我');
      GuangYuPanelService.select(panel, root, '', '发现页来源', choices, '番茄');
    }
    return panel;
  }

  private static select(panel: LocalRulePanel, values: JsonObj, group: string,
    name: string, choices: string[], fallback: string): void {
    const control = new LocalRuleControl();
    control.id = `guangyu-setting-${group}-${name}`;
    control.title = name;
    control.type = 'select';
    control.options = choices.slice();
    control.optionValues = choices.slice();
    control.value = values.getString(name, fallback);
    control.action = GuangYuPanelService.setAction(group, name);
    panel.controls.push(control);
  }

  private static setAction(group: string, name: string): string {
    const key = JSON.stringify(name);
    if (!group) return `setVariable(${key},infoMap[${key}]);`;
    const parent = JSON.stringify(group);
    return `let settings=getVariable(${parent})||{};settings[${key}]=infoMap[${key}];setVariable(${parent},settings);`;
  }

  static async accountAction(action: string, controls: LocalRuleControl[]): Promise<LocalRulePanelAction | undefined> {
    if (action !== 'login(true)' && action !== 'logout()') return undefined;
    const result = new LocalRulePanelAction();
    if (action === 'logout()') {
      await GuangYuAuthService.logout();
      result.message = '已退出登录';
    } else {
      const email = controls.find((item: LocalRuleControl): boolean => item.title === '邮箱')?.value ?? '';
      const password = controls.find((item: LocalRuleControl): boolean => item.type === 'password')?.value ?? '';
      try {
        const response = await GuangYuAuthService.login(email, password);
        result.message = response.message;
      } finally {
        for (const control of controls) if (control.type === 'password') control.value = '';
      }
    }
    return result;
  }
}
