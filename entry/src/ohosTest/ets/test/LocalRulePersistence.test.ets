import { abilityDelegatorRegistry } from '@kit.TestKit';
import { afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../../../main/ets/model/LocalRuleSource';
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
      if (fixtureUrl) await LocalRuleSourceRepository.remove(fixtureUrl);
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
