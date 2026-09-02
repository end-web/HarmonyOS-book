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
  testedSource: LocalRuleSource | undefined = undefined;

  static copy(report: LocalRuleSourceBulkTestReport,
    testedSource?: LocalRuleSource): LocalRuleSourceBulkTestProgress {
    const progress = new LocalRuleSourceBulkTestProgress();
    progress.total = report.total;
    progress.completed = report.completed;
    progress.passed = report.passed;
    progress.failed = report.failed;
    progress.testedSource = testedSource;
    return progress;
  }
}

export class LocalRuleSourceBulkTestReport extends LocalRuleSourceBulkTestProgress {
  retained: number = 0;
}

export type LocalRuleSourceBulkTestProgressHandler =
  (progress: LocalRuleSourceBulkTestProgress) => void;

export interface LocalRuleSourceBulkTestExecutor {
  test(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth>;
}

export interface LocalRuleSourceBulkTestStore {
  saveTested(sources: LocalRuleSource[]): Promise<void>;
}

class DefaultLocalRuleSourceBulkTestExecutor implements LocalRuleSourceBulkTestExecutor {
  async test(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth> {
    return BookSourceService.testLocalSourceAvailability(source, keyword);
  }
}

class DefaultLocalRuleSourceBulkTestStore implements LocalRuleSourceBulkTestStore {
  async saveTested(sources: LocalRuleSource[]): Promise<void> {
    await LocalRuleSourceRepository.updateValidationBatch(sources);
  }
}

class LocalRuleSourceBulkTestOutcome {
  source: LocalRuleSource = new LocalRuleSource();
  ready: boolean = false;
  sourceIndex: number = -1;
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
    const activeTasks: Promise<LocalRuleSourceBulkTestOutcome>[] = [];
    const activeIndexes: number[] = [];
    const pendingSave: LocalRuleSource[] = [];
    let nextIndex = 0;
    LocalRuleSourceBulkTester.notifyProgress(report, onProgress);

    while (nextIndex < sources.length && activeTasks.length < BULK_TEST_BATCH_SIZE) {
      activeTasks.push(this.testOne(sources[nextIndex], cleanKeyword, nextIndex));
      activeIndexes.push(nextIndex);
      nextIndex++;
    }

    while (activeTasks.length > 0) {
      const outcome: LocalRuleSourceBulkTestOutcome =
        await Promise.race<LocalRuleSourceBulkTestOutcome>(activeTasks);
      const activePosition = activeIndexes.indexOf(outcome.sourceIndex);
      if (activePosition >= 0) {
        activeTasks.splice(activePosition, 1);
        activeIndexes.splice(activePosition, 1);
      }
      if (nextIndex < sources.length) {
        activeTasks.push(this.testOne(sources[nextIndex], cleanKeyword, nextIndex));
        activeIndexes.push(nextIndex);
        nextIndex++;
      }

      report.completed++;
      pendingSave.push(outcome.source);
      if (outcome.ready) {
        report.passed++;
      } else {
        report.failed++;
      }
      LocalRuleSourceBulkTester.notifyProgress(report, onProgress, outcome.source);

      if (pendingSave.length >= BULK_TEST_BATCH_SIZE) {
        await this.store.saveTested(pendingSave.slice());
        pendingSave.length = 0;
      }
    }

    if (pendingSave.length > 0) await this.store.saveTested(pendingSave);
    report.retained = report.failed;
    return report;
  }

  private async testOne(source: LocalRuleSource,
    keyword: string, sourceIndex: number): Promise<LocalRuleSourceBulkTestOutcome> {
    const outcome = new LocalRuleSourceBulkTestOutcome();
    outcome.source = source;
    outcome.sourceIndex = sourceIndex;
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
    onProgress?: LocalRuleSourceBulkTestProgressHandler, testedSource?: LocalRuleSource): void {
    if (onProgress !== undefined) {
      onProgress(LocalRuleSourceBulkTestProgress.copy(report, testedSource));
    }
  }
}
