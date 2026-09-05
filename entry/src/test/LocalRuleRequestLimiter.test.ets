import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleRequestLimiter } from '../main/ets/service/rulesource/LocalRuleRequestLimiter';
import { LocalRuleDiagnostics } from '../main/ets/service/rulesource/LocalRuleDiagnostics';

export default function localRuleRequestLimiterTest() {
  describe('LocalRuleRequestLimiter', () => {
    it('accepts disabled and legacy interval configurations', 0, async () => {
      const key = `rate-interval-${Date.now()}`;
      (await LocalRuleRequestLimiter.acquire(key, '0', 500, {})).release();
      (await LocalRuleRequestLimiter.acquire(key, '', 500, {})).release();
      (await LocalRuleRequestLimiter.acquire(key, '35', 500, {})).release();
      const startedAt = Date.now();
      (await LocalRuleRequestLimiter.acquire(key, '35', 500, {})).release();
      expect(Date.now() - startedAt >= 30).assertTrue();
    });

    it('releases concurrent permits once and isolates sources', 0, async () => {
      const key = `rate-concurrent-${Date.now()}`;
      const first = await LocalRuleRequestLimiter.acquire(key, '-1', 500, {});
      const other = await LocalRuleRequestLimiter.acquire(key + '-other', '-1', 500, {});
      other.release();
      let entered = false;
      const pending = LocalRuleRequestLimiter.acquire(key, '-1', 500, {}).then(permit => {
        entered = true;
        return permit;
      });
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 40); });
      expect(entered).assertFalse();
      first.release();
      const second = await pending;
      first.release();
      let timedOut = false;
      try { await LocalRuleRequestLimiter.acquire(key, '-1', 20, {}); }
      catch (_error) { timedOut = true; }
      expect(timedOut).assertTrue();
      second.release();
      (await LocalRuleRequestLimiter.acquire(key, '-1', 500, {})).release();
    });

    it('keeps requests usable when optional rate metadata is malformed', 0, async () => {
      const messages: string[] = [];
      const variables = LocalRuleDiagnostics.open(event => { messages.push(event.message); });
      try {
        (await LocalRuleRequestLimiter.acquire('rate-invalid', 'invalid', 500, variables)).release();
        (await LocalRuleRequestLimiter.acquire('rate-invalid', '1/0', 500, variables)).release();
        expect(messages.length).assertEqual(2);
      } finally {
        LocalRuleDiagnostics.close(variables);
      }
    });

    it('cancels a queued request without consuming the released permit', 0, async () => {
      const key = `rate-cancel-${Date.now()}`;
      const first = await LocalRuleRequestLimiter.acquire(key, '-1', 500, {});
      const variables = LocalRuleDiagnostics.open(() => {});
      const pending = LocalRuleRequestLimiter.acquire(key, '-1', 500, variables)
        .then(permit => { permit.release(); return false; }, () => true);
      LocalRuleDiagnostics.cancel(variables);
      expect(await pending).assertTrue();
      LocalRuleDiagnostics.close(variables);
      first.release();
      (await LocalRuleRequestLimiter.acquire(key, '-1', 500, {})).release();
    });
  });
}
