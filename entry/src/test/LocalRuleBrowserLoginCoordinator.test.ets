import { describe, expect, it } from '@ohos/hypium';
import { RuleSourceLoginRouteParams } from '../main/ets/model/RuleSourceLogin';
import { LocalRuleBrowserLoginCoordinator } from '../main/ets/service/rulesource/LocalRuleBrowserLoginCoordinator';

export default function localRuleBrowserLoginCoordinatorTests() {
  describe('LocalRuleBrowserLoginCoordinatorTests', () => {
    it('resolves_only_the_matching_request_once_and_keeps_the_snapshot', 0, async () => {
      let opened = new RuleSourceLoginRouteParams();
      const opener = (route: RuleSourceLoginRouteParams): void => { opened = route; };
      LocalRuleBrowserLoginCoordinator.bindNavigation(opener);
      try {
        const pending = LocalRuleBrowserLoginCoordinator.request('source-a', 'Source A',
          'https://example.test/login#form', '<html><form></form></html>');
        expect(opened.sourceUrl).assertEqual('source-a');
        expect(opened.initialHtml).assertEqual('<html><form></form></html>');
        expect(opened.documentUrl()).assertEqual('https://example.test/login');
        expect(LocalRuleBrowserLoginCoordinator.isPending(opened.requestId)).assertTrue();
        LocalRuleBrowserLoginCoordinator.resolve('stale-request', 'wrong');
        expect(LocalRuleBrowserLoginCoordinator.isPending(opened.requestId)).assertTrue();
        LocalRuleBrowserLoginCoordinator.resolve(opened.requestId, '<html>signed in</html>');
        LocalRuleBrowserLoginCoordinator.reject(opened.requestId, 'late cancellation');
        expect(await pending).assertEqual('<html>signed in</html>');
        expect(LocalRuleBrowserLoginCoordinator.isPending(opened.requestId)).assertFalse();
      } finally { LocalRuleBrowserLoginCoordinator.unbindNavigation(opener); }
    });

    it('rejects_parallel_browser_logins_without_cancelling_the_original', 0, async () => {
      let opened = new RuleSourceLoginRouteParams();
      const opener = (route: RuleSourceLoginRouteParams): void => { opened = route; };
      LocalRuleBrowserLoginCoordinator.bindNavigation(opener);
      try {
        const first = LocalRuleBrowserLoginCoordinator.request('source-a', 'A', 'https://example.test/login');
        const secondError = await LocalRuleBrowserLoginCoordinator.request('source-b', 'B', 'https://example.test/other')
          .then((): string => '', (error: Error): string => error.message);
        expect(secondError.length > 0).assertTrue();
        expect(opened.sourceUrl).assertEqual('source-a');
        expect(LocalRuleBrowserLoginCoordinator.isPending(opened.requestId)).assertTrue();
        LocalRuleBrowserLoginCoordinator.resolve(opened.requestId, 'done');
        expect(await first).assertEqual('done');
        const next = LocalRuleBrowserLoginCoordinator.request('source-b', 'B', 'https://example.test/other');
        LocalRuleBrowserLoginCoordinator.resolve(opened.requestId, 'next');
        expect(await next).assertEqual('next');
      } finally { LocalRuleBrowserLoginCoordinator.unbindNavigation(opener); }
    });

    it('cancels_the_wait_and_closes_the_owned_page_when_navigation_is_removed', 0, async () => {
      let opened = new RuleSourceLoginRouteParams();
      let closes = 0;
      const opener = (route: RuleSourceLoginRouteParams): void => { opened = route; };
      LocalRuleBrowserLoginCoordinator.bindNavigation(opener);
      const outcome = LocalRuleBrowserLoginCoordinator.request('source-a', 'A', 'https://example.test/login')
        .then((): string => '', (error: Error): string => error.message);
      const attached = LocalRuleBrowserLoginCoordinator.attach(opened.requestId,
        async (_reason: string): Promise<void> => { closes++; });
      expect(attached).assertTrue();
      LocalRuleBrowserLoginCoordinator.unbindNavigation(opener);
      expect((await outcome).length > 0).assertTrue();
      expect(closes).assertEqual(1);
      expect(LocalRuleBrowserLoginCoordinator.isPending(opened.requestId)).assertFalse();
      await Promise.resolve();
    });

    it('rejects_insecure_credentials_and_oversized_html_before_opening_a_page', 0, async () => {
      let opened = 0;
      const opener = (_route: RuleSourceLoginRouteParams): void => { opened++; };
      LocalRuleBrowserLoginCoordinator.bindNavigation(opener);
      try {
        const insecure = await LocalRuleBrowserLoginCoordinator.request('source-a', 'A', 'http://example.test/login')
          .then((): string => '', (error: Error): string => error.message);
        const credentials = await LocalRuleBrowserLoginCoordinator.request('source-a', 'A', 'https://user:pass@example.test/login')
          .then((): string => '', (error: Error): string => error.message);
        const oversized = await LocalRuleBrowserLoginCoordinator.request('source-a', 'A', 'https://example.test/login',
          'x'.repeat(LocalRuleBrowserLoginCoordinator.MAX_HTML_LENGTH + 1))
          .then((): string => '', (error: Error): string => error.message);
        expect(insecure.length > 0).assertTrue();
        expect(credentials.length > 0).assertTrue();
        expect(oversized.length > 0).assertTrue();
        expect(opened).assertEqual(0);
      } finally { LocalRuleBrowserLoginCoordinator.unbindNavigation(opener); }
    });
  });
}
