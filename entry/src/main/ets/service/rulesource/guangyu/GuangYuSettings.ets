import { LocalRuleScriptState } from '../../../model/LocalRuleScriptState';
import { JsonObj } from '../../builtin/JsonValue';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { GUANG_YU_SOURCE_URL } from './GuangYuSourceIdentity';

/** 与导入规则的源变量共用存储，原生请求和规则面板读取同一份设置。 */
export class GuangYuSettings {
  host: string = '';
  timeoutMs: number = 10000;
  autoSwitch: boolean = true;
  mode: string = '小说';
  novelSources: string = '全部';
  audioSources: string = '全部';
  forceSearch: boolean = false;
  showSource: boolean = true;
  reviews: boolean = true;
  godReviews: boolean = true;
  localNetwork: boolean = false;

  static async load(): Promise<GuangYuSettings> {
    const settings = new GuangYuSettings();
    if (!LocalRuleSourceRepository.isInitialized()) return settings;
    const state = LocalRuleScriptState.parse(await LocalRuleSourceRepository.readScriptState(GUANG_YU_SOURCE_URL));
    if (!state.variable.trim()) return settings;
    const root = new JsonObj(JSON.parse(state.variable));
    const more = root.getObj('更多设置');
    const review = root.getObj('段评设置');
    settings.host = root.getString('线路');
    settings.timeoutMs = Math.max(3000, Math.min(60000, root.getInt('超时时间', 10) * 1000));
    settings.autoSwitch = root.getString('自动切换', 'true') !== 'false';
    settings.mode = more.getString('搜索模式', '小说');
    settings.novelSources = more.getString('小说', '全部') || '全部';
    settings.audioSources = more.getString('听书', '全部') || '全部';
    settings.forceSearch = more.getString('强制搜索') === 'true';
    settings.showSource = more.getString('目录显示来源', 'true') !== 'false';
    settings.reviews = review.getString('段评开关', 'true') !== 'false';
    settings.godReviews = review.getString('神评论开关', 'true') !== 'false';
    settings.localNetwork = more.getString('网络模式') === '本地';
    return settings;
  }
}
