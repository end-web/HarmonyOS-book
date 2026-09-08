import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleTlsTrustStore } from '../main/ets/service/rulesource/LocalRuleTlsTrustStore';

export default function localRuleTlsTrustTest() {
  describe('LocalRuleTlsTrust', () => {
    it('extracts only HTTPS hostnames and rejects embedded credentials', 0, () => {
      expect(LocalRuleTlsTrustStore.hostFromUrl('https://Books.Example.com:8443/path')).assertEqual('books.example.com');
      expect(LocalRuleTlsTrustStore.hostFromUrl('https://trusted.example@other.example')).assertEqual('');
      expect(LocalRuleTlsTrustStore.hostFromUrl('http://books.example.com')).assertEqual('');
      expect(LocalRuleTlsTrustStore.hostFromUrl('file:///books.example.com')).assertEqual('');
      expect(LocalRuleTlsTrustStore.hostFromUrl('https://[::1]:8443/')).assertEqual('[::1]');
    });

    it('identifies the failing redirect host without misclassifying connection errors', 0, () => {
      const message = LocalRuleTlsTrustStore.describeFailure('1007900060 peer certificate invalid', 'https://redirect.example/book');
      expect(LocalRuleTlsTrustStore.certificateErrorHost(message, 'https://original.example')).assertEqual('redirect.example');
      expect(LocalRuleTlsTrustStore.certificateErrorHost('connection timeout', 'https://original.example')).assertEqual('');
    });
  });
}
