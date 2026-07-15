import { describe, it, expect } from '@ohos/hypium';
import {
  TingYouRequestPolicy, TingYouRetryAction
} from '../main/ets/service/builtin/sources/TingYouRequestPolicy';

export default function tingYouRequestPolicyTest() {
  describe('TingYouRequestPolicy', () => {
    it('refreshes the token only for the first unauthorized response', 0, () => {
      expect(TingYouRequestPolicy.forHttpStatus(401, 0)).assertEqual(TingYouRetryAction.REFRESH_TOKEN);
      expect(TingYouRequestPolicy.forHttpStatus(401, 1)).assertEqual(TingYouRetryAction.FAIL);
    });

    it('retries one server or network failure without refreshing the token', 0, () => {
      expect(TingYouRequestPolicy.forHttpStatus(502, 0)).assertEqual(TingYouRetryAction.RETRY_REQUEST);
      expect(TingYouRequestPolicy.forHttpStatus(502, 1)).assertEqual(TingYouRetryAction.FAIL);
      expect(TingYouRequestPolicy.shouldRetryNetworkError(0)).assertEqual(true);
      expect(TingYouRequestPolicy.shouldRetryNetworkError(1)).assertEqual(false);
    });

    it('does not retry unrelated client errors', 0, () => {
      expect(TingYouRequestPolicy.forHttpStatus(400, 0)).assertEqual(TingYouRetryAction.FAIL);
      expect(TingYouRequestPolicy.forHttpStatus(429, 0)).assertEqual(TingYouRetryAction.FAIL);
    });
  });
}
