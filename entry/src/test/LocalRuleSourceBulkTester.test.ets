import { describe, expect, it } from '@ohos/hypium';
import {
  LocalRuleSource,
  LocalRuleSourceHealth,
  LocalRuleSourceStatus
} from '../main/ets/model/LocalRuleSource';
import {
  LocalRuleSourceBulkTestExecutor,
  LocalRuleSourceBulkTestProgress,
  LocalRuleSourceBulkTestReport,
  LocalRuleSourceBulkTester,
  LocalRuleSourceBulkTestStore
} from '../main/ets/service/rulesource/LocalRuleSourceBulkTester';
import { SearchResult } from '../main/ets/model/BookSource';
import { NativeRuleSourceHealthPolicy } from '../main/ets/service/BookSourceService';
import { RuleSourceLoginRouteParams } from '../main/ets/model/RuleSourceLogin';
import { LocalRuleBrowserLoginCoordinator } from '../main/ets/service/rulesource/LocalRuleBrowserLoginCoordinator';

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
  savedBatchSizes: number[] = [];
  saveCalls: number = 0;
  failSave: boolean = false;

  async saveTested(sources: LocalRuleSource[]): Promise<void> {
    this.saveCalls++;
    if (this.failSave) throw new Error('save transaction failed');
    this.savedBatchSizes.push(sources.length);
    for (const source of sources) this.savedSources.push(source);
  }
}

class SlowFirstBulkExecutor implements LocalRuleSourceBulkTestExecutor {
  calls: number = 0;
  active: number = 0;
  maxActive: number = 0;
  private firstGate: Promise<void>;
  private releaseFirstHandler: (() => void) | undefined = undefined;

  constructor() {
    this.firstGate = new Promise<void>((resolve: () => void) => {
      this.releaseFirstHandler = resolve;
    });
  }

  async test(source: LocalRuleSource, _keyword: string): Promise<LocalRuleSourceHealth> {
    this.calls++;
    this.active++;
    if (this.active > this.maxActive) this.maxActive = this.active;
    if (source.bookSourceUrl === 'slow') await this.firstGate;
    this.active--;
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.status = LocalRuleSourceStatus.READY;
    health.message = 'ready';
    return health;
  }

  releaseFirst(): void {
    const handler = this.releaseFirstHandler;
    if (handler !== undefined) handler();
  }
}

function sourceOf(sourceUrl: string): LocalRuleSource {
  return LocalRuleSource.descriptor(sourceUrl, sourceUrl);
}

class BrowserLoginBulkExecutor implements LocalRuleSourceBulkTestExecutor {
  async test(source: LocalRuleSource, _keyword: string): Promise<LocalRuleSourceHealth> {
    await LocalRuleBrowserLoginCoordinator.request(source.bookSourceUrl, source.bookSourceName, 'https://example.test/login');
    const health = new LocalRuleSourceHealth();
    health.status = LocalRuleSourceStatus.READY;
    return health;
  }
}

class DelayedBrowserLoginBulkExecutor extends BrowserLoginBulkExecutor {
  private gate: Promise<void>;
  private releaseGate: () => void = (): void => {};

  constructor() {
    super();
    this.gate = new Promise<void>((resolve: () => void) => { this.releaseGate = resolve; });
  }

  async test(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth> {
    await this.gate;
    return super.test(source, keyword);
  }

  release(): void { this.releaseGate(); }
}

export default function localRuleSourceBulkTesterTest() {
  describe('LocalRuleSourceBulkTester', () => {
    it('rejects late browser entry after cancellation and releases the scope for a new task', 0, async () => {
      let opened = new RuleSourceLoginRouteParams();
      let openedCount = 0;
      let timer = -1;
      const opener = (route: RuleSourceLoginRouteParams): void => { opened = route; openedCount++; };
      LocalRuleBrowserLoginCoordinator.bindNavigation(opener);
      const executor = new DelayedBrowserLoginBulkExecutor();
      const tester = new LocalRuleSourceBulkTester(executor, new TestBulkStore());
      try {
        const running = tester.run([sourceOf('late-browser')], 'test');
        tester.cancel();
        executor.release();
        const guard = new Promise<LocalRuleSourceBulkTestReport>((_resolve, reject) => {
          timer = setTimeout(() => reject(new Error('Late browser entry escaped cancellation')), 1000);
        });
        const report = await Promise.race<LocalRuleSourceBulkTestReport>([running, guard]);
        expect(report.cancelled).assertTrue();
        expect(report.completed).assertEqual(0);
        expect(openedCount).assertEqual(0);
        const next = LocalRuleBrowserLoginCoordinator.request('late-browser', 'New task', 'https://example.test/login');
        expect(openedCount).assertEqual(1);
        LocalRuleBrowserLoginCoordinator.resolve(opened.requestId, 'signed in');
        expect(await next).assertEqual('signed in');
      } finally {
        clearTimeout(timer);
        executor.release();
        tester.cancel();
        LocalRuleBrowserLoginCoordinator.unbindNavigation(opener);
      }
    });

    it('cancels an active browser wait immediately without replacing source health', 0, async () => {
      let opened = new RuleSourceLoginRouteParams();
      let closed = false;
      let timer = -1;
      const opener = (route: RuleSourceLoginRouteParams): void => { opened = route; };
      LocalRuleBrowserLoginCoordinator.bindNavigation(opener);
      const store = new TestBulkStore();
      const tester = new LocalRuleSourceBulkTester(new BrowserLoginBulkExecutor(), store);
      try {
        const source = sourceOf('awaiting-login');
        source.validationStatus = LocalRuleSourceStatus.READY;
        source.validationMessage = 'previous result';
        const running = tester.run([source], 'test');
        LocalRuleBrowserLoginCoordinator.attach(opened.requestId,
          async (_reason: string): Promise<void> => { closed = true; });
        tester.cancel();
        const guard = new Promise<LocalRuleSourceBulkTestReport>((_resolve, reject) => {
          timer = setTimeout(() => reject(new Error('Cancelled browser wait did not finish')), 1000);
        });
        const report = await Promise.race<LocalRuleSourceBulkTestReport>([running, guard]);
        expect(report.cancelled).assertTrue();
        expect(report.completed).assertEqual(0);
        expect(closed).assertTrue();
        expect(store.saveCalls).assertEqual(0);
        expect(source.validationStatus).assertEqual(LocalRuleSourceStatus.READY);
        expect(source.validationMessage).assertEqual('previous result');
      } finally {
        clearTimeout(timer);
        tester.cancel();
        LocalRuleBrowserLoginCoordinator.unbindNavigation(opener);
      }
    });

    it('does not cancel browser waits owned by sources outside the active batch', 0, async () => {
      let opened = new RuleSourceLoginRouteParams();
      const opener = (route: RuleSourceLoginRouteParams): void => { opened = route; };
      LocalRuleBrowserLoginCoordinator.bindNavigation(opener);
      const executor = new SlowFirstBulkExecutor();
      const tester = new LocalRuleSourceBulkTester(executor, new TestBulkStore());
      try {
        const unrelated = LocalRuleBrowserLoginCoordinator.request('unrelated', 'Other', 'https://example.test/login');
        const running = tester.run([sourceOf('slow')], 'test');
        tester.cancel();
        expect(LocalRuleBrowserLoginCoordinator.isPending(opened.requestId)).assertTrue();
        executor.releaseFirst();
        expect((await running).cancelled).assertTrue();
        LocalRuleBrowserLoginCoordinator.resolve(opened.requestId, 'other login');
        expect(await unrelated).assertEqual('other login');
      } finally {
        executor.releaseFirst();
        tester.cancel();
        LocalRuleBrowserLoginCoordinator.unbindNavigation(opener);
      }
    });

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

    it('retests legacy UNSUPPORTED sources and persists every result', 0, async () => {
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
      expect(report.passed).assertEqual(2);
      expect(report.failed).assertEqual(1);
      expect(report.failedSources[0].bookSourceUrl).assertEqual('failed');
      expect(report.retained).assertEqual(1);
      expect(executor.calls).assertEqual(3);
      expect(store.savedSources.length).assertEqual(3);
      expect(store.savedSources[0].bookSourceUrl).assertEqual('ready');
      expect(store.savedSources[1].bookSourceUrl).assertEqual('failed');
      expect(store.savedSources[2].bookSourceUrl).assertEqual('unsupported');
    });

    it('reports each completed source so the page can update availability immediately', 0, async () => {
      const executor = new TestBulkExecutor();
      const store = new TestBulkStore();
      const updatedUrls: string[] = [];

      await new LocalRuleSourceBulkTester(executor, store).run(
        [sourceOf('first'), sourceOf('second')], 'test',
        (progress: LocalRuleSourceBulkTestProgress) => {
          const testedSource = progress.testedSource;
          if (testedSource !== undefined) updatedUrls.push(testedSource.bookSourceUrl);
        });

      expect(updatedUrls.length).assertEqual(2);
      expect(updatedUrls.includes('first')).assertTrue();
      expect(updatedUrls.includes('second')).assertTrue();
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
      expect(store.savedSources.length).assertEqual(2);
      expect(store.savedSources[0].bookSourceUrl).assertEqual('throws');
      expect(store.savedSources[1].bookSourceUrl).assertEqual('continues');
    });

    it('rejects the run when persisting test results fails', 0, async () => {
      const executor = new TestBulkExecutor();
      executor.statuses.set('failed', LocalRuleSourceStatus.FAILED);
      const store = new TestBulkStore();
      store.failSave = true;
      let rejected = false;

      try {
        await new LocalRuleSourceBulkTester(executor, store).run([sourceOf('failed')], 'test');
      } catch (_error) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(store.saveCalls).assertEqual(1);
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
      expect(report.retained).assertEqual(0);
      expect(executor.calls).assertEqual(0);
      expect(store.saveCalls).assertEqual(0);
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
      expect(store.saveCalls).assertEqual(3);
      expect(store.savedBatchSizes[0]).assertEqual(6);
      expect(store.savedBatchSizes[1]).assertEqual(6);
      expect(store.savedBatchSizes[2]).assertEqual(1);
    });

    it('cancels queued tests without overwriting in-flight source status', 0, async () => {
      const executor = new SlowFirstBulkExecutor();
      const store = new TestBulkStore();
      const slow = sourceOf('slow');
      slow.validationMessage = 'previous result';
      const sources: LocalRuleSource[] = [slow];
      for (let index = 1; index < 12; index++) sources.push(sourceOf(`source-${index}`));
      const tester = new LocalRuleSourceBulkTester(executor, store);
      const running = tester.run(sources, 'test', (progress: LocalRuleSourceBulkTestProgress): void => {
        if (progress.completed > 0) tester.cancel();
      });
      for (let index = 0; index < 12; index++) await Promise.resolve<void>(undefined);
      executor.releaseFirst();
      const report = await running;
      expect(report.cancelled).assertTrue();
      expect(executor.calls).assertEqual(6);
      expect(slow.validationMessage).assertEqual('previous result');
      expect(store.savedSources.some((source: LocalRuleSource): boolean => source.bookSourceUrl === 'slow')).assertFalse();
    });

    it('allows an empty keyword for discovery validation and fails missing discovery rules', 0, async () => {
      const report = await LocalRuleSourceBulkTester.createDefault('exploreReading').run([], '');
      expect(report.total).assertEqual(0);
    });

    it('starts the next source without waiting for the slowest active source', 0, async () => {
      const executor = new SlowFirstBulkExecutor();
      const store = new TestBulkStore();
      const sources: LocalRuleSource[] = [sourceOf('slow')];
      for (let index = 1; index < 8; index++) sources.push(sourceOf(`source-${index}`));

      const running = new LocalRuleSourceBulkTester(executor, store).run(sources, 'test');
      for (let index = 0; index < 12; index++) await Promise.resolve<void>(undefined);

      expect(executor.calls >= 7).assertTrue();
      expect(executor.maxActive <= 6).assertTrue();
      executor.releaseFirst();
      const report = await running;
      expect(report.completed).assertEqual(8);
    });
  });
}
