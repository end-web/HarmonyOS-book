import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource, LocalRuleSourceStatus } from '../main/ets/model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../main/ets/service/rulesource/LocalRuleSourceRepository';
import { LocalRuleSourceCodec } from '../main/ets/service/rulesource/LocalRuleSourceCodec';
import { LocalRuleSourceImportParser } from '../main/ets/service/rulesource/LocalRuleSourceImportParser';

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

    it('preserves local source management choices when importing an update', 0, () => {
      const previous = sourceOf('https://management.invalid', false);
      previous.enabledExplore = true;
      previous.bookSourceGroup = 'Local group';
      previous.isLocked = true;
      previous.isPinned = true;
      previous.customOrder = 7;
      const incoming = sourceOf(previous.bookSourceUrl, true);
      LocalRuleSourceRepository.preserveEnabledStates([incoming], [previous]);
      expect(incoming.enabled).assertFalse();
      expect(incoming.enabledExplore).assertTrue();
      expect(incoming.bookSourceGroup).assertEqual('Local group');
      expect(incoming.isLocked).assertTrue();
      expect(incoming.isPinned).assertTrue();
      expect(incoming.customOrder).assertEqual(7);
    });

    it('exports management flags and unknown rules without runtime credentials', 0, () => {
      const source = LocalRuleSourceImportParser.parse('{"bookSourceUrl":"https://export.invalid",' +
        '"bookSourceName":"Fixture","locked":true,"isPinned":true,"customOrder":12,' +
        '"ruleSearch":{"bookList":"$.items","extension":"kept"},"futureRule":{"setting":3},' +
        '"loginHeader":"secret-header","loginInfo":"secret-account","session":{"token":"secret-token"},' +
        '"cookieHeader":"secret-cookie"}').sources[0];
      expect(source.isLocked).assertTrue();
      expect(source.customOrder).assertEqual(12);
      source.ruleSearch.bookList = '$.updated';
      const exported = LocalRuleSourceCodec.exportBatch([source]);
      expect(exported.includes('secret-')).assertFalse();
      const restored = LocalRuleSourceImportParser.parse(exported).sources[0];
      expect(restored.isLocked).assertTrue();
      expect(restored.isPinned).assertTrue();
      expect(restored.customOrder).assertEqual(12);
      expect(restored.ruleSearch.bookList).assertEqual('$.updated');
      expect(restored.rawSourceJson).assertContain('"extension":"kept"');
      expect(restored.rawSourceJson).assertContain('"futureRule":{"setting":3}');
      source.isLocked = false;
      const unlocked = LocalRuleSourceCodec.exportBatch([source]);
      expect(unlocked.includes('"locked":')).assertFalse();
      expect(LocalRuleSourceImportParser.parse(unlocked).sources[0].isLocked).assertFalse();
    });
  });
}
