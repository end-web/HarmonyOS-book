import { HomeBlockSection } from '../../model/BookSource';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { BookSourceService } from '../BookSourceService';
import { PreferenceService } from '../PreferenceService';
import { SourceDataService } from '../SourceDataService';
import { LocalRulePanelService } from './LocalRulePanelService';
import { TingYouSourceIdentity } from './tingyou/TingYouSourceIdentity';

export class HomeSourceCategory {
  name: string;
  url: string;

  constructor(name: string, url: string) {
    this.name = name;
    this.url = url;
  }
}

/** 首页使用用户选择的已启用小说或听书发现源，复用现有导入源发现链路。 */
export class HomeSourceService {
  static isEligible(source: LocalRuleSource): boolean {
    return source.enabled && (source.isAudio() || source.isText()) && source.canExecute() &&
      HomeSourceService.hasHomeContent(source) &&
      !source.bookSourceUrl.startsWith('builtin://');
  }

  static async getSources(): Promise<LocalRuleSource[]> {
    const sources = await SourceDataService.getSources();
    const eligibleSources: LocalRuleSource[] = [];
    for (const source of sources) {
      if (source instanceof LocalRuleSource && HomeSourceService.isEligible(source)) eligibleSources.push(source);
    }
    return eligibleSources;
  }

  static selectAvailable(sources: LocalRuleSource[], preferredUrl: string): LocalRuleSource | undefined {
    const eligible = sources.filter((source: LocalRuleSource): boolean => HomeSourceService.isEligible(source));
    return eligible.find((source: LocalRuleSource): boolean => source.bookSourceUrl === preferredUrl) ??
      eligible.find((source: LocalRuleSource): boolean => HomeSourceService.hasHomeContent(source)) ?? eligible[0];
  }

  static async getSelectedSource(): Promise<LocalRuleSource | undefined> {
    return HomeSourceService.selectAvailable(await HomeSourceService.getSources(),
      await PreferenceService.getHomeSourceUrl());
  }

  static async setSelectedSource(sourceUrl: string): Promise<void> {
    const sources = await HomeSourceService.getSources();
    if (!sources.some((source: LocalRuleSource): boolean => source.bookSourceUrl === sourceUrl)) {
      throw new Error('首页源必须已启用且支持发现');
    }
    await PreferenceService.setHomeSourceUrl(sourceUrl);
  }

  static hasHomeContent(source: LocalRuleSource): boolean {
    return TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl) ||
      (source.enabledExplore && source.exploreUrl.trim().length > 0);
  }

  static async getCategories(source: LocalRuleSource): Promise<HomeSourceCategory[]> {
    if (!source.enabledExplore || !source.exploreUrl.trim()) return [];
    const panel = await LocalRulePanelService.load(source, false);
    const categories: HomeSourceCategory[] = [];
    const seen = new Set<string>();
    for (const entry of panel.entries) {
      if (!entry.url.trim() || entry.action || seen.has(entry.url)) continue;
      seen.add(entry.url);
      categories.push(new HomeSourceCategory(entry.title, entry.url));
    }
    return categories;
  }

  static async getHomeBlocks(source: LocalRuleSource,
    categories: HomeSourceCategory[]): Promise<HomeBlockSection[]> {
    if (TingYouSourceIdentity.isSourceUrl(source.bookSourceUrl)) {
      return BookSourceService.getHomeBlocks(source);
    }
    // 只预览前四个发现分类；各分类独立失败，避免一个分类阻断整个首页。
    let failureMessage: string = '';
    let failed: boolean = false;
    let completed: number = 0;
    const blocks = await Promise.all(categories.slice(0, 4).map(async (category: HomeSourceCategory):
      Promise<HomeBlockSection> => {
      const block: HomeBlockSection = {
        title: category.name, books: [], moreUrl: category.url, layout: 'horizontal',
        sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl
      };
      try {
        const result = await BookSourceService.getExploreBooksByUrl(source, category.url, 1);
        block.books = result.books.slice(0, 12);
        completed++;
      } catch (error) {
        failed = true;
        failureMessage = error instanceof Error ? error.message : String(error);
      }
      return block;
    }));
    if (completed === 0 && failed) throw new Error(failureMessage);
    return blocks.filter((block: HomeBlockSection): boolean => block.books.length > 0);
  }
}
