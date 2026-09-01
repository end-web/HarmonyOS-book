import {
  LocalRuleSource,
  LocalRuleSourceHealth,
  LocalRuleSourceStatus
} from '../../model/LocalRuleSource';
import { BookSourceService } from '../BookSourceService';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';

const BULK_TEST_BATCH_SIZE: number = 6;

export class LocalRuleSourceBulkTestProgress {
  total: number = 0;
  completed: number = 0;
  passed: number = 0;
  failed: number = 0;

  static copy(report: LocalRuleSourceBulkTestReport): LocalRuleSourceBulkTestProgress {
    const progress = new LocalRuleSourceBulkTestProgress();
    progress.total = report.total;
    progress.completed = report.completed;
    progress.passed = report.passed;
    progress.failed = report.failed;
    return progress;
  }
}

export class LocalRuleSourceBulkTestReport extends LocalRuleSourceBulkTestProgress {
  deleted: number = 0;
}

export type LocalRuleSourceBulkTestProgressHandler =
  (progress: LocalRuleSourceBulkTestProgress) => void;

export interface LocalRuleSourceBulkTestExecutor {
  test(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth>;
}

export interface LocalRuleSourceBulkTestStore {
  saveReady(sources: LocalRuleSource[]): Promise<void>;
  deleteFailed(sourceUrls: string[]): Promise<number>;
}

class DefaultLocalRuleSourceBulkTestExecutor implements LocalRuleSourceBulkTestExecutor {
  async test(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth> {
    return BookSourceService.testLocalSource(source, keyword);
  }
}

class DefaultLocalRuleSourceBulkTestStore implements LocalRuleSourceBulkTestStore {
  async saveReady(sources: LocalRuleSource[]): Promise<void> {
    await LocalRuleSourceRepository.upsertBatch(sources);
  }

  async deleteFailed(sourceUrls: string[]): Promise<number> {
    return LocalRuleSourceRepository.deleteBatch(sourceUrls);
  }
}

class LocalRuleSourceBulkTestOutcome {
  source: LocalRuleSource = new LocalRuleSource();
  ready: boolean = false;
}

export class LocalRuleSourceBulkTester {
  private executor: LocalRuleSourceBulkTestExecutor;
  private store: LocalRuleSourceBulkTestStore;

  constructor(executor: LocalRuleSourceBulkTestExecutor, store: LocalRuleSourceBulkTestStore) {
    this.executor = executor;
    this.store = store;
  }

  static createDefault(): LocalRuleSourceBulkTester {
    return new LocalRuleSourceBulkTester(
      new DefaultLocalRuleSourceBulkTestExecutor(), new DefaultLocalRuleSourceBulkTestStore());
  }

  async run(sources: LocalRuleSource[], keyword: string,
    onProgress?: LocalRuleSourceBulkTestProgressHandler): Promise<LocalRuleSourceBulkTestReport> {
    const cleanKeyword = keyword.trim();
    if (cleanKeyword.length === 0) throw new Error('搜索测试关键词不能为空');

    const report = new LocalRuleSourceBulkTestReport();
    report.total = sources.length;
    const readySources: LocalRuleSource[] = [];
    const failedUrls: string[] = [];
    LocalRuleSourceBulkTester.notifyProgress(report, onProgress);

    for (let start = 0; start < sources.length; start += BULK_TEST_BATCH_SIZE) {
      const tasks: Promise<LocalRuleSourceBulkTestOutcome>[] = [];
      const end = Math.min(start + BULK_TEST_BATCH_SIZE, sources.length);
      for (let index = start; index < end; index++) {
        tasks.push(this.testOne(sources[index], cleanKeyword));
      }
      const outcomes: LocalRuleSourceBulkTestOutcome[] = await Promise.all(tasks);
      for (const outcome of outcomes) {
        report.completed++;
        if (outcome.ready) {
          report.passed++;
          readySources.push(outcome.source);
        } else {
          report.failed++;
          failedUrls.push(outcome.source.bookSourceUrl);
        }
        LocalRuleSourceBulkTester.notifyProgress(report, onProgress);
      }
    }

    if (readySources.length > 0) await this.store.saveReady(readySources);
    if (failedUrls.length > 0) report.deleted = await this.store.deleteFailed(failedUrls);
    return report;
  }

  private async testOne(source: LocalRuleSource,
    keyword: string): Promise<LocalRuleSourceBulkTestOutcome> {
    const outcome = new LocalRuleSourceBulkTestOutcome();
    outcome.source = source;
    if (!source.canExecute()) {
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      if (source.validationMessage.length === 0) {
        source.validationMessage = '书源包含当前版本不支持的能力';
      }
      return outcome;
    }

    try {
      const health = await this.executor.test(source, keyword);
      source.validationStatus = health.status;
      source.validationMessage = health.message;
      outcome.ready = health.status === LocalRuleSourceStatus.READY;
    } catch (error) {
      source.validationStatus = LocalRuleSourceStatus.FAILED;
      source.validationMessage = error instanceof Error ? error.message : String(error);
    }
    return outcome;
  }

  private static notifyProgress(report: LocalRuleSourceBulkTestReport,
    onProgress?: LocalRuleSourceBulkTestProgressHandler): void {
    if (onProgress !== undefined) {
      onProgress(LocalRuleSourceBulkTestProgress.copy(report));
    }
  }
}
