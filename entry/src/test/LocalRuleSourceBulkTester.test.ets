import { describe, expect, it } from '@ohos/hypium';
import {
  LocalRuleSource,
  LocalRuleSourceHealth,
  LocalRuleSourceStatus
} from '../main/ets/model/LocalRuleSource';
import {
  LocalRuleSourceBulkTestExecutor,
  LocalRuleSourceBulkTestReport,
  LocalRuleSourceBulkTester,
  LocalRuleSourceBulkTestStore
} from '../main/ets/service/rulesource/LocalRuleSourceBulkTester';
import { SearchResult } from '../main/ets/model/BookSource';
import { NativeRuleSourceHealthPolicy } from '../main/ets/service/BookSourceService';

class TestHealthSearchResult implements SearchResult {
  name: string = 'test';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = 'test';
  intro: string = '';
  kind: string = '';
  contentType: 'audio' | 'text' = 'text';
  lastChapter: string = '';
  sourceName: string = 'test';
  sourceUrl: string = 'test';

  static of(contentType: 'audio' | 'text'): TestHealthSearchResult {
    const result = new TestHealthSearchResult();
    result.contentType = contentType;
    result.bookUrl = contentType;
    return result;
  }
}

class TestBulkExecutor implements LocalRuleSourceBulkTestExecutor {
  statuses: Map<string, number> = new Map<string, number>();
  throwingSourceUrls: Set<string> = new Set<string>();
  calls: number = 0;
  active: number = 0;
  maxActive: number = 0;

  async test(source: LocalRuleSource, _keyword: string): Promise<LocalRuleSourceHealth> {
    this.calls++;
    this.active++;
    if (this.active > this.maxActive) {
      this.maxActive = this.active;
    }
    await Promise.resolve();
    this.active--;

    if (this.throwingSourceUrls.has(source.bookSourceUrl)) {
      throw new Error(`test failed: ${source.bookSourceUrl}`);
    }

    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.status = this.statuses.get(source.bookSourceUrl) ?? LocalRuleSourceStatus.READY;
    health.message = health.status === LocalRuleSourceStatus.READY ? 'ready' : 'not ready';
    return health;
  }
}

class TestBulkStore implements LocalRuleSourceBulkTestStore {
  savedSources: LocalRuleSource[] = [];
  deletedSourceUrls: string[] = [];
  saveCalls: number = 0;
  deleteAttempts: number = 0;
  successfulDeleteCount: number = 0;
  failDelete: boolean = false;

  async saveReady(sources: LocalRuleSource[]): Promise<void> {
    this.saveCalls++;
    this.savedSources = sources.slice();
  }

  async deleteFailed(sourceUrls: string[]): Promise<number> {
    this.deleteAttempts++;
    this.deletedSourceUrls = sourceUrls.slice();
    if (this.failDelete) {
      throw new Error('delete transaction failed');
    }
    this.successfulDeleteCount = sourceUrls.length;
    return this.successfulDeleteCount;
  }
}

function sourceOf(sourceUrl: string): LocalRuleSource {
  return LocalRuleSource.descriptor(sourceUrl, sourceUrl);
}

export default function localRuleSourceBulkTesterTest() {
  describe('LocalRuleSourceBulkTester', () => {
    it('rejects native health coverage when audio search failed after novel success', 0, () => {
      let thrown = false;
      let message = '';
      try {
        NativeRuleSourceHealthPolicy.assertSearchCoverage(
          [TestHealthSearchResult.of('text')], ['听书搜索失败：network error']);
      } catch (error) {
        thrown = true;
        message = error instanceof Error ? error.message : String(error);
      }
      expect(thrown).assertTrue();
      expect(message).assertContain('听书搜索失败');
    });

    it('rejects native health coverage when one content type has zero results', 0, () => {
      let thrown = false;
      let message = '';
      try {
        NativeRuleSourceHealthPolicy.assertSearchCoverage(
          [TestHealthSearchResult.of('text')], []);
      } catch (error) {
        thrown = true;
        message = error instanceof Error ? error.message : String(error);
      }
      expect(thrown).assertTrue();
      expect(message).assertContain('听书搜索未返回可验证书籍');
    });

    it('accepts native health coverage only when novel and audio are both present', 0, () => {
      NativeRuleSourceHealthPolicy.assertSearchCoverage(
        [TestHealthSearchResult.of('text'), TestHealthSearchResult.of('audio')], []);
      expect(true).assertTrue();
    });

    it('keeps READY sources and deletes FAILED or UNSUPPORTED sources', 0, async () => {
      const executor = new TestBulkExecutor();
      executor.statuses.set('ready', LocalRuleSourceStatus.READY);
      executor.statuses.set('failed', LocalRuleSourceStatus.FAILED);
      const store = new TestBulkStore();
      const unsupported = sourceOf('unsupported');
      unsupported.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      const sources: LocalRuleSource[] = [sourceOf('ready'), sourceOf('failed'), unsupported];

      const report = await new LocalRuleSourceBulkTester(executor, store).run(sources, 'test');

      expect(report.total).assertEqual(3);
      expect(report.completed).assertEqual(3);
      expect(report.passed).assertEqual(1);
      expect(report.failed).assertEqual(2);
      expect(report.deleted).assertEqual(2);
      expect(executor.calls).assertEqual(2);
      expect(store.savedSources.length).assertEqual(1);
      expect(store.savedSources[0].bookSourceUrl).assertEqual('ready');
      expect(store.deletedSourceUrls.length).assertEqual(2);
      expect(store.deletedSourceUrls[0]).assertEqual('failed');
      expect(store.deletedSourceUrls[1]).assertEqual('unsupported');
    });

    it('continues testing other sources when one executor call throws', 0, async () => {
      const executor = new TestBulkExecutor();
      executor.throwingSourceUrls.add('throws');
      const store = new TestBulkStore();
      const failedSource = sourceOf('throws');
      const readySource = sourceOf('continues');

      const report = await new LocalRuleSourceBulkTester(executor, store)
        .run([failedSource, readySource], 'test');

      expect(executor.calls).assertEqual(2);
      expect(report.completed).assertEqual(2);
      expect(report.passed).assertEqual(1);
      expect(report.failed).assertEqual(1);
      expect(failedSource.validationStatus).assertEqual(LocalRuleSourceStatus.FAILED);
      expect(failedSource.validationMessage).assertContain('test failed');
      expect(store.savedSources[0].bookSourceUrl).assertEqual('continues');
      expect(store.deletedSourceUrls[0]).assertEqual('throws');
    });

    it('rejects the run instead of reporting deletion success when delete fails', 0, async () => {
      const executor = new TestBulkExecutor();
      executor.statuses.set('failed', LocalRuleSourceStatus.FAILED);
      const store = new TestBulkStore();
      store.failDelete = true;
      let rejected = false;

      try {
        await new LocalRuleSourceBulkTester(executor, store).run([sourceOf('failed')], 'test');
      } catch (_error) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(store.deleteAttempts).assertEqual(1);
      expect(store.successfulDeleteCount).assertEqual(0);
    });

    it('returns an empty report without touching storage for an empty source list', 0, async () => {
      const executor = new TestBulkExecutor();
      const store = new TestBulkStore();

      const report: LocalRuleSourceBulkTestReport =
        await new LocalRuleSourceBulkTester(executor, store).run([], 'test');

      expect(report.total).assertEqual(0);
      expect(report.completed).assertEqual(0);
      expect(report.passed).assertEqual(0);
      expect(report.failed).assertEqual(0);
      expect(report.deleted).assertEqual(0);
      expect(executor.calls).assertEqual(0);
      expect(store.saveCalls).assertEqual(0);
      expect(store.deleteAttempts).assertEqual(0);
    });

    it('runs at most six source tests concurrently', 0, async () => {
      const executor = new TestBulkExecutor();
      const store = new TestBulkStore();
      const sources: LocalRuleSource[] = [];
      for (let index = 0; index < 13; index++) {
        sources.push(sourceOf(`source-${index}`));
      }

      const report = await new LocalRuleSourceBulkTester(executor, store).run(sources, 'test');

      expect(report.passed).assertEqual(13);
      expect(executor.maxActive).assertEqual(6);
      expect(executor.maxActive <= 6).assertTrue();
    });
  });
}
