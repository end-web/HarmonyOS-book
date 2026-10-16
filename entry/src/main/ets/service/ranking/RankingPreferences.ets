import { RankingPlatform } from '../../model/Ranking';
import { PreferenceService } from '../PreferenceService';
import { RankingService } from './RankingService';

export class RankingCategorySetting {
  id: string;
  name: Resource;
  enabled: boolean;
  constructor(platform: RankingPlatform, enabled: boolean = true) {
    this.id = platform.id;
    this.name = platform.name;
    this.enabled = enabled;
  }
}

/** 顺序及开关存为一个偏好值；新增平台自动追加，旧配置中的未知平台忽略。 */
export class RankingPreferences {
  private static listeners: Set<() => void> = new Set<() => void>();

  static async load(): Promise<RankingCategorySetting[]> {
    const raw = await PreferenceService.getRankingCategories();
    const platforms = RankingService.platforms().filter((p: RankingPlatform): boolean => p.id.length > 0);
    const result: RankingCategorySetting[] = [];
    for (const token of raw.split(',')) {
      const id = token.replace(/^!/, '');
      const platform = platforms.find((p: RankingPlatform): boolean => p.id === id);
      if (platform && !result.some((p: RankingCategorySetting): boolean => p.id === id)) {
        result.push(new RankingCategorySetting(platform, !token.startsWith('!')));
      }
    }
    for (const platform of platforms) {
      if (!result.some((p: RankingCategorySetting): boolean => p.id === platform.id)) {
        result.push(new RankingCategorySetting(platform));
      }
    }
    return result;
  }

  static async save(items: RankingCategorySetting[]): Promise<void> {
    await PreferenceService.setRankingCategories(items.map((p: RankingCategorySetting): string =>
      `${p.enabled ? '' : '!'}${p.id}`).join(','));
    RankingPreferences.listeners.forEach((listener: () => void): void => listener());
  }
  static subscribe(listener: () => void): void { RankingPreferences.listeners.add(listener); }
  static unsubscribe(listener: () => void): void { RankingPreferences.listeners.delete(listener); }
}
