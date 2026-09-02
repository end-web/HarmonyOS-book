import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource, LocalRuleSourceStatus } from '../main/ets/model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../main/ets/service/rulesource/LocalRuleSourceRepository';

function sourceOf(sourceUrl: string, enabled: boolean): LocalRuleSource {
  const source = LocalRuleSource.descriptor(sourceUrl, sourceUrl);
  source.enabled = enabled;
  return source;
}

export default function localRuleSourceRepositoryTest() {
  describe('LocalRuleSourceRepository', () => {
    it('preserves enabled states when imported sources already exist', 0, () => {
      const incoming: LocalRuleSource[] = [sourceOf('disabled', true), sourceOf('enabled', false)];
      const existing: LocalRuleSource[] = [sourceOf('disabled', false), sourceOf('enabled', true)];

      LocalRuleSourceRepository.preserveEnabledStates(incoming, existing);

      expect(incoming[0].enabled).assertFalse();
      expect(incoming[1].enabled).assertTrue();
    });

    it('preserves the user enabled state for a legacy unsupported source', 0, () => {
      const incoming = sourceOf('unsupported', true);
      incoming.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      const existing = sourceOf('unsupported', true);

      LocalRuleSourceRepository.preserveEnabledStates([incoming], [existing]);

      expect(incoming.enabled).assertTrue();
    });
  });
}
