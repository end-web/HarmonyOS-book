import {
  RuleSourceChild,
  RuleSourceChildKind,
  RuleSourceChildLoadResult,
  RuleSourceChildStatus
} from '../../model/RuleSourceChild';
import {
  GuangYuApiClient,
  GuangYuSearchResponseDto
} from './guangyu/GuangYuApiClient';
import {
  GUANG_YU_SOURCE_URL,
  GuangYuSourceIdentity
} from './guangyu/GuangYuSourceIdentity';
import {
  SHU_SHAN_SOURCE_URL,
  ShuShanSourceIdentity
} from './shushan/ShuShanSourceIdentity';
import {
  ShuShanApiClient,
  ShuShanSearchResponseDto
} from './shushan/ShuShanApiClient';

const CHILD_DISCOVERY_KEYWORD: string = '斗破苍穹';
const GUANG_YU_NOVEL_TAB: string = '小说';
const GUANG_YU_AUDIO_TAB: string = '听书';
const FAN_QIE_WEB_LOGIN: string = 'https://fanqienovel.com/';
const QI_MAO_WEB_LOGIN: string = 'https://www.qimao.com/';
const TA_DU_WEB_LOGIN: string = 'https://www.tadu.com/';
const QQ_READING_WEB_LOGIN: string = 'https://book.qq.com/';
const SHU_QI_WEB_LOGIN: string = 'https://www.shuqi.com/login';
const KU_WO_WEB_LOGIN: string = 'https://www.kuwo.cn/';
const JIN_JIANG_WEB_LOGIN: string = 'https://my.jjwxc.net/login.php';
const XI_MA_LA_YA_WEB_LOGIN: string = 'https://www.ximalaya.com/';
const BAIDU_WEB_LOGIN: string = 'https://passport.baidu.com/v2/?login';

class RuleSourceChildDiscoveryGroup {
  items: RuleSourceChild[] = [];
  succeeded: boolean = false;
}

/** 聚合源的子源目录。目录只读，网络探测失败时回退到适配器内置清单。 */
export class RuleSourceChildService {
  private static readonly ALLOWED_CHILD_LOGIN_URLS: string[] = [
    FAN_QIE_WEB_LOGIN, QI_MAO_WEB_LOGIN, TA_DU_WEB_LOGIN,
    QQ_READING_WEB_LOGIN, SHU_QI_WEB_LOGIN, KU_WO_WEB_LOGIN,
    JIN_JIANG_WEB_LOGIN, XI_MA_LA_YA_WEB_LOGIN, BAIDU_WEB_LOGIN
  ];
  private static readonly GUANG_YU_TEXT_SOURCES: string[] = [
    '番茄', '七猫', '塔读', 'QQ阅读', 'svip_QQ阅读', '书旗', 'svip_书旗'
  ];
  private static readonly GUANG_YU_AUDIO_SOURCES: string[] = [
    '番茄', '有声库', 'svip_酷我'
  ];
  private static readonly SHU_SHAN_TEXT_SOURCES: string[] = [
    '52书库', '69书吧', '爱乐文学', '爱下电子书', '八零小说', '百度', '半夏',
    '笔趣阁78', '茶马', '得奇', '二三中文', '番茄小说', '疯读', '腐小说', '江湖小说',
    '晋江', '看书网', '猫眼看书', '米读', '七猫', '企鹅看书', '趣书网', '全本',
    '圣武书屋', '书耽网', '书库阁', '书旗', '思兔', '台湾', '淘小说', '万相书城',
    '无忧书城', '小米阅读', '小说狂人', '新笔趣阁', '星星', '夜伴书屋', '阅友',
    '追书神器', 'QQ阅读'
  ];
  private static readonly SHU_SHAN_AUDIO_SOURCES: string[] = [
    '番茄畅听', '番茄听书', '书旗听书', '书音', '喜马拉雅'
  ];

  static supports(sourceUrl: string | undefined): boolean {
    return GuangYuSourceIdentity.isSourceUrl(sourceUrl) ||
      ShuShanSourceIdentity.isSourceUrl(sourceUrl);
  }

  static catalog(sourceUrl: string): RuleSourceChild[] {
    const output: RuleSourceChild[] = [];
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      RuleSourceChildService.appendCatalog(output, GUANG_YU_SOURCE_URL,
        RuleSourceChildService.GUANG_YU_TEXT_SOURCES, RuleSourceChildKind.TEXT);
      RuleSourceChildService.appendCatalog(output, GUANG_YU_SOURCE_URL,
        RuleSourceChildService.GUANG_YU_AUDIO_SOURCES, RuleSourceChildKind.AUDIO);
    } else if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      RuleSourceChildService.appendCatalog(output, SHU_SHAN_SOURCE_URL,
        RuleSourceChildService.SHU_SHAN_TEXT_SOURCES, RuleSourceChildKind.TEXT);
      RuleSourceChildService.appendCatalog(output, SHU_SHAN_SOURCE_URL,
        RuleSourceChildService.SHU_SHAN_AUDIO_SOURCES, RuleSourceChildKind.AUDIO);
    }
    return RuleSourceChildService.sorted(output);
  }

  static async load(sourceUrl: string): Promise<RuleSourceChildLoadResult> {
    const result = new RuleSourceChildLoadResult();
    const catalog = RuleSourceChildService.catalog(sourceUrl);
    result.items = catalog;
    if (GuangYuSourceIdentity.isSourceUrl(sourceUrl)) {
      const tasks: Promise<RuleSourceChildDiscoveryGroup>[] = [
        RuleSourceChildService.discoverGuangYuTab(
          GUANG_YU_NOVEL_TAB, RuleSourceChildKind.TEXT),
        RuleSourceChildService.discoverGuangYuTab(
          GUANG_YU_AUDIO_TAB, RuleSourceChildKind.AUDIO)
      ];
      const groups: RuleSourceChildDiscoveryGroup[] =
        await Promise.all<RuleSourceChildDiscoveryGroup>(tasks);
      return RuleSourceChildService.finishLoad(catalog, groups);
    }
    if (ShuShanSourceIdentity.isSourceUrl(sourceUrl)) {
      const tasks: Promise<RuleSourceChildDiscoveryGroup>[] = [
        RuleSourceChildService.discoverShuShanMode('novel', RuleSourceChildKind.TEXT),
        RuleSourceChildService.discoverShuShanMode('audio', RuleSourceChildKind.AUDIO)
      ];
      const groups: RuleSourceChildDiscoveryGroup[] =
        await Promise.all<RuleSourceChildDiscoveryGroup>(tasks);
      return RuleSourceChildService.finishLoad(catalog, groups);
    }
    return result;
  }

  static isAllowedLoginUrl(value: string): boolean {
    return RuleSourceChildService.ALLOWED_CHILD_LOGIN_URLS.includes(value);
  }

  private static appendCatalog(output: RuleSourceChild[], parentSourceUrl: string,
    names: string[], kind: number): void {
    for (const name of names) {
      output.push(RuleSourceChildService.createChild(parentSourceUrl, name, kind));
    }
  }

  private static createChild(parentSourceUrl: string, name: string,
    kind: number): RuleSourceChild {
    const loginUrl = RuleSourceChildService.childLoginUrl(name);
    return RuleSourceChild.of(parentSourceUrl, name, kind, loginUrl.length > 0, loginUrl);
  }

  private static childLoginUrl(name: string): string {
    const normalizedName = name.trim();
    const lowerName = normalizedName.toLowerCase();
    let provider = normalizedName;
    if (lowerName.startsWith('vip_') || lowerName.startsWith('svip_')) {
      const separatorIndex = normalizedName.indexOf('_');
      if (separatorIndex < 0 || separatorIndex >= normalizedName.length - 1) return '';
      provider = normalizedName.substring(separatorIndex + 1);
    }
    if (provider === '番茄' || provider === '番茄小说' || provider === '番茄听书' ||
      provider === '番茄畅听') return FAN_QIE_WEB_LOGIN;
    if (provider === '七猫') return QI_MAO_WEB_LOGIN;
    if (provider === '塔读') return TA_DU_WEB_LOGIN;
    if (provider === 'QQ阅读' || provider === '企鹅看书') return QQ_READING_WEB_LOGIN;
    if (provider === '书旗' || provider === '书旗听书') return SHU_QI_WEB_LOGIN;
    if (provider === '酷我') return KU_WO_WEB_LOGIN;
    if (provider === '晋江') return JIN_JIANG_WEB_LOGIN;
    if (provider === '喜马拉雅') return XI_MA_LA_YA_WEB_LOGIN;
    if (provider === '百度') return BAIDU_WEB_LOGIN;
    return '';
  }

  private static async discoverGuangYuTab(tab: string,
    kind: number): Promise<RuleSourceChildDiscoveryGroup> {
    const group = new RuleSourceChildDiscoveryGroup();
    try {
      const response: GuangYuSearchResponseDto = await GuangYuApiClient.search(
        tab, CHILD_DISCOVERY_KEYWORD, 1);
      const children = new Map<string, RuleSourceChild>();
      for (const item of response.items) {
        const name = item.source.trim();
        if (name.length === 0) continue;
        const child = RuleSourceChildService.getOrCreateChild(
          children, GUANG_YU_SOURCE_URL, name, kind);
        child.status = RuleSourceChildStatus.ACTIVE;
        child.resultCount += 1;
      }
      for (const timing of response.sourceTimings) {
        const name = timing.source.trim();
        if (name.length === 0) continue;
        const child = RuleSourceChildService.getOrCreateChild(
          children, GUANG_YU_SOURCE_URL, name, kind);
        child.status = RuleSourceChildStatus.ACTIVE;
        child.resultCount = Math.max(child.resultCount, Math.max(0, Math.trunc(timing.resultCount)));
        child.responseTimeMs = Math.max(0, Math.round(timing.timeCost));
      }
      for (const nameValue of response.disabledSources) {
        const name = nameValue.trim();
        if (name.length === 0) continue;
        const child = RuleSourceChildService.getOrCreateChild(
          children, GUANG_YU_SOURCE_URL, name, kind);
        child.status = RuleSourceChildStatus.DISABLED;
      }
      RuleSourceChildService.appendMapValues(group.items, children);
      group.succeeded = true;
    } catch (_error) {
      group.succeeded = false;
    }
    return group;
  }

  private static async discoverShuShanMode(mode: string,
    kind: number): Promise<RuleSourceChildDiscoveryGroup> {
    const group = new RuleSourceChildDiscoveryGroup();
    try {
      const response: ShuShanSearchResponseDto = await ShuShanApiClient.search(
        mode, CHILD_DISCOVERY_KEYWORD, 1);
      const children = new Map<string, RuleSourceChild>();
      for (const item of response.items) {
        const name = item.source.trim();
        if (name.length === 0) continue;
        const child = RuleSourceChildService.getOrCreateChild(
          children, SHU_SHAN_SOURCE_URL, name, kind);
        child.status = RuleSourceChildStatus.ACTIVE;
        child.resultCount += 1;
      }
      RuleSourceChildService.appendMapValues(group.items, children);
      group.succeeded = true;
    } catch (_error) {
      group.succeeded = false;
    }
    return group;
  }

  private static getOrCreateChild(children: Map<string, RuleSourceChild>,
    parentSourceUrl: string, name: string, kind: number): RuleSourceChild {
    const id = `${parentSourceUrl}:${kind}:${name}`;
    const existing = children.get(id);
    if (existing !== undefined) return existing;
    const child = RuleSourceChildService.createChild(parentSourceUrl, name, kind);
    children.set(child.id, child);
    return child;
  }

  private static appendMapValues(output: RuleSourceChild[],
    children: Map<string, RuleSourceChild>): void {
    children.forEach((child: RuleSourceChild) => {
      output.push(child);
    });
  }

  private static finishLoad(catalog: RuleSourceChild[],
    groups: RuleSourceChildDiscoveryGroup[]): RuleSourceChildLoadResult {
    const result = new RuleSourceChildLoadResult();
    const merged = new Map<string, RuleSourceChild>();
    for (const child of catalog) merged.set(child.id, child);
    for (const group of groups) {
      if (group.succeeded) result.networkUpdated = true;
      for (const discovered of group.items) {
        const existing = merged.get(discovered.id);
        if (existing === undefined) {
          merged.set(discovered.id, discovered);
        } else {
          existing.status = discovered.status;
          existing.resultCount = discovered.resultCount;
          existing.responseTimeMs = discovered.responseTimeMs;
        }
      }
    }
    RuleSourceChildService.appendMapValues(result.items, merged);
    result.items = RuleSourceChildService.sorted(result.items);
    return result;
  }

  private static sorted(items: RuleSourceChild[]): RuleSourceChild[] {
    items.sort((left: RuleSourceChild, right: RuleSourceChild): number => {
      const leftRank = RuleSourceChildService.statusRank(left.status);
      const rightRank = RuleSourceChildService.statusRank(right.status);
      if (leftRank !== rightRank) return leftRank - rightRank;
      if (left.kind !== right.kind) return left.kind - right.kind;
      return left.name.localeCompare(right.name);
    });
    return items;
  }

  private static statusRank(status: number): number {
    if (status === RuleSourceChildStatus.ACTIVE) return 0;
    if (status === RuleSourceChildStatus.KNOWN) return 1;
    return 2;
  }
}
