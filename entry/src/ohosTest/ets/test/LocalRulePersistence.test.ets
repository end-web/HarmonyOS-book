import { abilityDelegatorRegistry } from '@kit.TestKit';
import { afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource, LocalRuleSourceStatus } from '../../../main/ets/model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../../../main/ets/service/rulesource/LocalRuleSourceRepository';
import { LocalRuleScriptRuntime } from '../../../main/ets/service/rulesource/LocalRuleScriptRuntime';
import { LocalRuleHttpClient } from '../../../main/ets/service/rulesource/LocalRuleHttpClient';
import { LocalRuleDebugService } from '../../../main/ets/service/rulesource/LocalRuleDebugService';
import { LocalRuleDiagnostics } from '../../../main/ets/service/rulesource/LocalRuleDiagnostics';
import { LocalRuleSourceImportParser } from '../../../main/ets/service/rulesource/LocalRuleSourceImportParser';
import { HttpClient } from '../../../main/ets/service/http/HttpClient';

export default function localRulePersistenceTest() {
  describe('LocalRulePersistence', () => {
    let fixtureUrl = '';
    beforeAll(async () => {
      await LocalRuleSourceRepository.init(abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry'));
    });
    afterEach(async () => {
      if (fixtureUrl && await LocalRuleSourceRepository.get(fixtureUrl) !== undefined) {
        await LocalRuleSourceRepository.setLockedBatch([fixtureUrl], false);
        await LocalRuleSourceRepository.remove(fixtureUrl);
      }
      LocalRuleHttpClient.clearCookieCacheBatch([fixtureUrl]);
      fixtureUrl = '';
    });
    it('reloads encrypted state and removes it when a source is deleted', 0, async () => {
      fixtureUrl = `https://persistence-test.invalid/${Date.now()}`;
      const source = LocalRuleSource.descriptor(fixtureUrl, 'Persistence fixture');
      await LocalRuleSourceRepository.insert(source);
      await LocalRuleScriptRuntime.evaluate('', fixtureUrl,
        'source.setVariable("persisted");cache.put("key","cached");' +
        'source.putLoginHeader({Authorization:"fixture"});cookie.setCookie("https://example.com","session=fixture");', source, {});
      const reloaded = await LocalRuleSourceRepository.get(fixtureUrl);
      expect(reloaded !== undefined).assertTrue();
      if (reloaded === undefined) return;
      expect(await LocalRuleScriptRuntime.evaluate('', fixtureUrl,
        'source.getVariable()+"|"+cache.get("key")', reloaded, {})).assertEqual('persisted|cached');
      LocalRuleHttpClient.clearCookieCacheBatch([fixtureUrl]);
      expect(await LocalRuleHttpClient.getStoredCookieHeader(fixtureUrl, 'https://example.com')).assertEqual('session=fixture');
      reloaded.bookSourceName = 'Edited fixture';
      await LocalRuleSourceRepository.update(reloaded);
      expect((await LocalRuleSourceRepository.get(fixtureUrl))?.bookSourceName).assertEqual('Edited fixture');
      await LocalRuleSourceRepository.remove(fixtureUrl);
      expect(await LocalRuleSourceRepository.readScriptState(fixtureUrl)).assertEqual('');
      await LocalRuleSourceRepository.writeScriptState(fixtureUrl, '{"variable":"stale"}');
      expect(await LocalRuleSourceRepository.readScriptState(fixtureUrl)).assertEqual('');
      expect((await LocalRuleSourceRepository.listCookies(fixtureUrl)).length).assertEqual(0);
    });

    it('persists source management and protects locked definitions in batch operations', 0, async () => {
      const suffix = String(Date.now());
      fixtureUrl = `https://management-test.invalid/${suffix}/locked`;
      const secondUrl = `https://management-test.invalid/${suffix}/editable`;
      const group = `management-${suffix}`;
      const renamedGroup = `${group}-renamed`;
      const locked = LocalRuleSource.descriptor(fixtureUrl, 'Locked fixture');
      const editable = LocalRuleSource.descriptor(secondUrl, 'Editable fixture');
      await LocalRuleSourceRepository.upsertBatch([locked, editable]);
      try {
        await LocalRuleSourceRepository.createGroup(group);
        expect((await LocalRuleSourceRepository.listGroups()).includes(group)).assertTrue();
        expect(await LocalRuleSourceRepository.setGroupBatch([fixtureUrl, secondUrl], group)).assertEqual(2);
        await LocalRuleSourceRepository.setLockedBatch([fixtureUrl], true);
        const replacement = LocalRuleSource.descriptor(fixtureUrl, 'Must not replace');
        const replacementOther = LocalRuleSource.descriptor(secondUrl, 'Updated fixture');
        expect(await LocalRuleSourceRepository.upsertImportedBatch([replacement, replacementOther])).assertEqual(1);
        expect((await LocalRuleSourceRepository.get(fixtureUrl))?.bookSourceName).assertEqual('Locked fixture');
        expect((await LocalRuleSourceRepository.get(secondUrl))?.bookSourceGroup).assertEqual(group);
        let editRejected = false;
        try {
          await LocalRuleSourceRepository.update(replacement);
        } catch (_error) {
          editRejected = true;
        }
        expect(editRejected).assertTrue();
        expect(await LocalRuleSourceRepository.setEnabledBatch([fixtureUrl, secondUrl], false)).assertEqual(1);
        expect(await LocalRuleSourceRepository.setExploreEnabledBatch([fixtureUrl, secondUrl], true)).assertEqual(1);
        expect(await LocalRuleSourceRepository.setGroupBatch([fixtureUrl, secondUrl], '')).assertEqual(1);
        const persisted = await LocalRuleSourceRepository.get(fixtureUrl);
        expect(persisted !== undefined).assertTrue();
        if (persisted === undefined) return;
        expect(persisted.enabled).assertTrue();
        expect(persisted.enabledExplore).assertFalse();
        expect(persisted.bookSourceGroup).assertEqual(group);
        persisted.validationStatus = LocalRuleSourceStatus.READY;
        await LocalRuleSourceRepository.updateValidationBatch([persisted]);
        await LocalRuleSourceRepository.setPinned(fixtureUrl, true);
        await LocalRuleSourceRepository.saveOrder([secondUrl, fixtureUrl]);
        const ordered = (await LocalRuleSourceRepository.list()).filter((source: LocalRuleSource): boolean =>
          source.bookSourceUrl === fixtureUrl || source.bookSourceUrl === secondUrl);
        expect(ordered[0].bookSourceUrl).assertEqual(fixtureUrl);
        expect(ordered[0].validationStatus).assertEqual(LocalRuleSourceStatus.READY);
        expect(ordered[0].isPinned).assertTrue();
        await LocalRuleSourceRepository.writeScriptState(fixtureUrl, '{"variable":"keep"}');
        await LocalRuleSourceRepository.writeScriptState(secondUrl, '{"variable":"remove"}');
        expect(await LocalRuleSourceRepository.deleteBatch([fixtureUrl, secondUrl])).assertEqual(1);
        expect(await LocalRuleSourceRepository.readScriptState(fixtureUrl)).assertEqual('{"variable":"keep"}');
        expect(await LocalRuleSourceRepository.readScriptState(secondUrl)).assertEqual('');
        await LocalRuleSourceRepository.renameGroup(group, renamedGroup);
        expect((await LocalRuleSourceRepository.get(fixtureUrl))?.bookSourceGroup).assertEqual(group);
        await LocalRuleSourceRepository.deleteGroup(renamedGroup);
        expect((await LocalRuleSourceRepository.get(fixtureUrl))?.bookSourceGroup).assertEqual(group);
        expect((await LocalRuleSourceRepository.get(fixtureUrl))?.isLocked).assertTrue();
      } finally {
        await LocalRuleSourceRepository.remove(secondUrl);
        const groups = await LocalRuleSourceRepository.listGroups();
        if (groups.includes(group)) await LocalRuleSourceRepository.deleteGroup(group);
        if (groups.includes(renamedGroup)) await LocalRuleSourceRepository.deleteGroup(renamedGroup);
      }
    });

    it('manages individual imported groups while retaining other memberships and locked sources', 0, async () => {
      const suffix = String(Date.now());
      fixtureUrl = `https://multi-group-test.invalid/${suffix}/editable`;
      const lockedUrl = `https://multi-group-test.invalid/${suffix}/locked`;
      const firstGroup = `multi-${suffix}-A`;
      const secondGroup = `multi-${suffix}-B`;
      const renamedGroup = `multi-${suffix}-C`;
      const definition: Record<string, Object> = {
        'bookSourceUrl': fixtureUrl, 'bookSourceName': 'Multi-group fixture',
        'bookSourceGroup': `${firstGroup},${secondGroup}`
      };
      const imported = LocalRuleSourceImportParser.parse(JSON.stringify(definition)).sources[0];
      const locked = LocalRuleSource.descriptor(lockedUrl, 'Locked multi-group fixture');
      locked.bookSourceGroup = `${firstGroup},${secondGroup}`;
      locked.isLocked = true;
      await LocalRuleSourceRepository.upsertImportedBatch([imported, locked]);
      try {
        const groups = await LocalRuleSourceRepository.listGroups();
        expect(groups.includes(firstGroup)).assertTrue();
        expect(groups.includes(secondGroup)).assertTrue();
        expect(groups.includes(`${firstGroup},${secondGroup}`)).assertFalse();
        expect(await LocalRuleSourceRepository.renameGroup(firstGroup, renamedGroup)).assertEqual(1);
        expect((await LocalRuleSourceRepository.get(fixtureUrl))?.bookSourceGroup)
          .assertEqual(`${renamedGroup},${secondGroup}`);
        expect((await LocalRuleSourceRepository.get(lockedUrl))?.bookSourceGroup)
          .assertEqual(`${firstGroup},${secondGroup}`);
        expect(await LocalRuleSourceRepository.deleteGroup(renamedGroup)).assertEqual(1);
        expect((await LocalRuleSourceRepository.get(fixtureUrl))?.bookSourceGroup).assertEqual(secondGroup);
        expect(await LocalRuleSourceRepository.deleteGroup(firstGroup)).assertEqual(0);
        expect((await LocalRuleSourceRepository.get(lockedUrl))?.bookSourceGroup)
          .assertEqual(`${firstGroup},${secondGroup}`);
        expect(await LocalRuleSourceRepository.setGroupBatch([fixtureUrl, lockedUrl],
          `${renamedGroup},${secondGroup},${renamedGroup}`)).assertEqual(1);
        expect((await LocalRuleSourceRepository.get(fixtureUrl))?.bookSourceGroup)
          .assertEqual(`${renamedGroup},${secondGroup}`);
        expect(LocalRuleSourceRepository.groupNames(`${renamedGroup}，${secondGroup} · ${renamedGroup}`).length)
          .assertEqual(2);
      } finally {
        await LocalRuleSourceRepository.setLockedBatch([lockedUrl], false);
        await LocalRuleSourceRepository.remove(lockedUrl);
        for (const group of [firstGroup, secondGroup, renamedGroup]) {
          if ((await LocalRuleSourceRepository.listGroups()).includes(group)) {
            await LocalRuleSourceRepository.deleteGroup(group);
          }
        }
      }
    });
  });

  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const smokeSource = String(parameters['-s sourceUrl'] ?? parameters['sourceUrl'] ?? '');
  if (smokeSource) {
    describe('LocalRuleImportedSmoke', () => {
      beforeAll(async () => {
        await LocalRuleSourceRepository.init(abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry'));
      });
      it('runs the explicitly selected installed source through the real pipeline', 0, async () => {
        let source = await LocalRuleSourceRepository.get(smokeSource);
        let temporary = false;
        const importUrl = parameters['-s importUrl'] ?? parameters['importUrl'] ?? '';
        if (source === undefined && importUrl) {
          const response = await HttpClient.get(importUrl);
          source = LocalRuleSourceImportParser.parse(response).sources.find(item => item.bookSourceUrl === smokeSource);
          if (source !== undefined) {
            await LocalRuleSourceRepository.insert(source);
            temporary = true;
          }
        }
        expect(source !== undefined).assertTrue();
        if (source === undefined) return;
        const variables = LocalRuleDiagnostics.open(event => {
          if (event.level !== 'info') {
            abilityDelegatorRegistry.getAbilityDelegator().printSync(
              `[SourceSmoke] ${event.stage} ${event.message} ${event.level === 'error' ? event.detail : ''}\n`);
          }
        });
        try {
          const result = await LocalRuleDebugService.run(source, String(parameters['-s stage'] ?? parameters['stage'] ?? 'full'),
            String(parameters['-s keyword'] ?? parameters['keyword'] ?? '我的'), '', variables);
          console.info(`[SourceSmoke] success=${result.success} error=${result.error}`);
          if (String(parameters['-s verbose'] ?? '') === 'true') {
            abilityDelegatorRegistry.getAbilityDelegator().printSync(result.data.substring(0, 2000) + '\n');
          }
          if (!result.success) abilityDelegatorRegistry.getAbilityDelegator().printSync(result.error + '\n');
          expect(result.success).assertTrue();
        } finally {
          LocalRuleDiagnostics.close(variables);
          if (temporary) await LocalRuleSourceRepository.remove(smokeSource);
        }
      });
    });
  }
}
