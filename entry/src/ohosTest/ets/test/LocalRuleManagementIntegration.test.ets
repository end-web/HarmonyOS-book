import { preferences } from '@kit.ArkData';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource, LocalRuleSourceStatus } from '../../../main/ets/model/LocalRuleSource';
import { BookSourceService } from '../../../main/ets/service/BookSourceService';
import { LocalRuleDispatcher } from '../../../main/ets/service/rulesource/LocalRuleDispatcher';
import { LocalRuleHttpClient } from '../../../main/ets/service/rulesource/LocalRuleHttpClient';
import { LocalRuleSourceBulkTester } from '../../../main/ets/service/rulesource/LocalRuleSourceBulkTester';
import { LocalRuleSourceRepository } from '../../../main/ets/service/rulesource/LocalRuleSourceRepository';
import { LocalRuleTlsTrustStore } from '../../../main/ets/service/rulesource/LocalRuleTlsTrustStore';

function managementFixture(base: string, mode: string): LocalRuleSource {
  const source = LocalRuleSource.descriptor(`${base}/management-source/${mode}/${Date.now()}`,
    'Management integration fixture');
  source.enabled = false;
  source.enabledExplore = true;
  source.exploreUrl = `Fixture::${base}/management/explore?mode=${mode}`;
  source.searchUrl = `${base}/management/explore?mode=normal`;
  source.ruleSearch.bookList = '$.books';
  source.ruleSearch.name = '$.name';
  source.ruleSearch.bookUrl = '$.bookUrl';
  source.ruleExplore.bookList = '$.books';
  source.ruleExplore.name = '$.name';
  source.ruleExplore.bookUrl = '$.bookUrl';
  source.ruleBookInfo.name = '$.name';
  source.ruleBookInfo.tocUrl = '$.tocUrl';
  source.ruleToc.chapterList = '$.chapters';
  source.ruleToc.chapterName = '$.name';
  source.ruleToc.chapterUrl = '$.url';
  source.ruleToc.isPay = '$.isPay';
  source.ruleToc.isVip = '$.isVip';
  source.ruleToc.isVolume = '$.isVolume';
  source.ruleContent.content = '$.content';
  return source;
}

export default function localRuleManagementIntegrationTest() {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const context = delegator.getAppContext().createModuleContext('entry');
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const base = String(parameters['-s fixtureUrl'] ?? parameters['fixtureUrl'] ?? '');

  describe('LocalRuleTlsTrustIntegration', () => {
    beforeAll(async () => {
      await LocalRuleTlsTrustStore.init(context);
    });

    it('stores exact HTTPS hosts and revokes only the temporary fixture host', 0, async () => {
      const host = `tls-${Date.now()}-${Math.floor(Math.random() * 1000000)}.management-fixture.invalid`;
      const previous = await LocalRuleTlsTrustStore.listTrustedHosts();
      expect(previous.includes(host)).assertFalse();
      try {
        await LocalRuleTlsTrustStore.trustHosts([host.toUpperCase()]);
        expect(await LocalRuleTlsTrustStore.isTrustedUrl(`https://${host}/chapter`)).assertTrue();
        expect(await LocalRuleTlsTrustStore.isTrustedUrl(`https://${host}:8443/chapter`)).assertTrue();
        expect(await LocalRuleTlsTrustStore.isTrustedUrl(`https://child.${host}/chapter`)).assertFalse();
        expect(await LocalRuleTlsTrustStore.isTrustedUrl(`https://${host}.other.invalid/chapter`)).assertFalse();
        expect(await LocalRuleTlsTrustStore.isTrustedUrl(`http://${host}/chapter`)).assertFalse();
        expect(await LocalRuleTlsTrustStore.isTrustedUrl(`https://account@${host}/chapter`)).assertFalse();
        const stored = await preferences.getPreferences(context, { name: 'local_rule_tls_trust' });
        const trustedRaw = await stored.get('hosts', '[]');
        const trustedHosts: string[] = JSON.parse(String(trustedRaw));
        expect(trustedHosts.includes(host)).assertTrue();
        await LocalRuleTlsTrustStore.revokeHost(host);
        expect(await LocalRuleTlsTrustStore.isTrustedUrl(`https://${host}/chapter`)).assertFalse();
        const revokedRaw = await stored.get('hosts', '[]');
        const revokedHosts: string[] = JSON.parse(String(revokedRaw));
        expect(revokedHosts.includes(host)).assertFalse();
        for (const existing of previous) expect(revokedHosts.includes(existing)).assertTrue();
      } finally {
        if (!previous.includes(host)) await LocalRuleTlsTrustStore.revokeHost(host);
      }
    });
  });

  if (!base) return;
  describe('LocalRuleExploreReadingIntegration', () => {
    const created: string[] = [];
    const install = async (mode: string): Promise<LocalRuleSource> => {
      const source = managementFixture(base, mode);
      await LocalRuleSourceRepository.insert(source);
      created.push(source.bookSourceUrl);
      return source;
    };
    beforeAll(async () => {
      await delegator.startAbility({ bundleName: 'com.huan.listenbook', abilityName: 'EntryAbility' });
      await LocalRuleSourceRepository.init(context);
    });
    afterEach(async () => {
      for (const sourceUrl of created) await LocalRuleSourceRepository.remove(sourceUrl);
      LocalRuleHttpClient.clearCookieCacheBatch(created);
      created.length = 0;
    });

    it('validates discovery through text with search disabled', 0, async () => {
      const source = await install('normal');
      expect(source.hasSearchCapability()).assertTrue();
      expect((await LocalRuleDispatcher.search(source, 'fixture')).length).assertEqual(0);
      const health = await BookSourceService.testLocalSourceExploreReading(source);
      delegator.printSync(`[ExploreReadingFixture] ${health.status}: ${health.message}\n`);
      expect(health.status).assertEqual(LocalRuleSourceStatus.READY);
      expect(source.enabled).assertFalse();
      expect((await LocalRuleSourceRepository.get(source.bookSourceUrl))?.enabled).assertFalse();
    });

    it('fails discovery when the category contains no books', 0, async () => {
      const source = await install('empty');
      const health = await BookSourceService.testLocalSourceExploreReading(source);
      expect(health.status).assertEqual(LocalRuleSourceStatus.FAILED);
      expect(health.message).assertContain('发现分类未返回');
    });

    it('does not count a paid-only catalog as a successful reading validation', 0, async () => {
      const source = await install('paid');
      const health = await BookSourceService.testLocalSourceExploreReading(source);
      expect(health.status).assertEqual(LocalRuleSourceStatus.FAILED);
      expect(health.message).assertContain('免费章节');
    });

    it('keeps the previous persisted health when a running batch is cancelled', 0, async () => {
      const source = await install('slow');
      source.validationStatus = LocalRuleSourceStatus.READY;
      source.validationMessage = 'Previous fixture result';
      await LocalRuleSourceRepository.updateValidationBatch([source]);
      const tester = LocalRuleSourceBulkTester.createDefault('exploreReading');
      const pending = tester.run([source], '');
      const timer = setTimeout((): void => tester.cancel(), 50);
      try {
        const report = await pending;
        expect(report.cancelled).assertTrue();
        expect(report.completed).assertEqual(0);
        expect(report.failed).assertEqual(0);
        expect(source.validationStatus).assertEqual(LocalRuleSourceStatus.READY);
        expect(source.validationMessage).assertEqual('Previous fixture result');
        const persisted = await LocalRuleSourceRepository.get(source.bookSourceUrl);
        expect(persisted?.validationStatus).assertEqual(LocalRuleSourceStatus.READY);
        expect(persisted?.validationMessage).assertEqual('Previous fixture result');
      } finally {
        clearTimeout(timer);
        tester.cancel();
      }
    });
  });
}
