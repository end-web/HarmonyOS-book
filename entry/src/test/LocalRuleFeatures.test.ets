import { afterEach, describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../main/ets/model/LocalRuleSource';
import { LocalRuleScriptState } from '../main/ets/model/LocalRuleScriptState';
import { LocalRuleSourceCodec } from '../main/ets/service/rulesource/LocalRuleSourceCodec';
import { LocalRuleSourceImportParser } from '../main/ets/service/rulesource/LocalRuleSourceImportParser';
import { LocalRuleSourceRepository } from '../main/ets/service/rulesource/LocalRuleSourceRepository';
import { LocalRuleScriptRuntime } from '../main/ets/service/rulesource/LocalRuleScriptRuntime';
import { LocalRuleChapterRequest } from '../main/ets/service/rulesource/LocalRuleChapterRequest';
import { LocalRuleStageExtractor } from '../main/ets/service/rulesource/LocalRuleStageExtractor';
import { LocalRulePanelService } from '../main/ets/service/rulesource/LocalRulePanelService';
import { LocalRuleDiagnostics } from '../main/ets/service/rulesource/LocalRuleDiagnostics';
import { LocalRuleDebugService } from '../main/ets/service/rulesource/LocalRuleDebugService';
import { LocalRuleHttpClient } from '../main/ets/service/rulesource/LocalRuleHttpClient';
import { LocalRuleUrlAnalyzer } from '../main/ets/service/rulesource/LocalRuleUrlAnalyzer';
import { LocalRuleRequestLimiter } from '../main/ets/service/rulesource/LocalRuleRequestLimiter';

export default function localRuleFeaturesTest() {
  describe('LocalRuleFeatures', () => {
    const created: string[] = [];
    const fixture = async (): Promise<LocalRuleSource> => {
      const source = LocalRuleSource.descriptor(`https://compat-test.invalid/${Date.now()}-${created.length}`, 'Compatibility fixture');
      created.push(source.bookSourceUrl);
      if (LocalRuleSourceRepository.isInitialized()) await LocalRuleSourceRepository.insert(source);
      return source;
    };
    afterEach(async () => {
      if (LocalRuleSourceRepository.isInitialized()) {
        for (const url of created) await LocalRuleSourceRepository.remove(url);
      }
      LocalRuleHttpClient.clearCookieCacheBatch(created);
      created.length = 0;
    });

    it('preserves extension fields while saving edited rules', 0, () => {
      const source = LocalRuleSourceImportParser.parse('{"bookSourceUrl":"https://example.com",' +
        '"bookSourceName":"Old","customOrder":9,"ruleExplore":{"bookList":"$.old","extension":"kept"}}').sources[0];
      source.bookSourceName = 'Edited';
      source.ruleExplore.bookList = '$.new';
      const encoded = LocalRuleSourceCodec.stringify(source);
      const roundTrip = LocalRuleSourceImportParser.parse(encoded).sources[0];
      expect(roundTrip.bookSourceName).assertEqual('Edited');
      expect(roundTrip.ruleExplore.bookList).assertEqual('$.new');
      expect(encoded).assertContain('"customOrder":9');
      expect(encoded).assertContain('"extension":"kept"');
      expect(encoded.includes('rawSourceJson')).assertFalse();
    });

    it('keeps source and cache values across calls and rolls back failed scripts', 0, async () => {
      const source = await fixture();
      await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'source.setVariable("saved");source.put("key","value");cache.put("entry","cached",60);', source, {});
      let failed = false;
      try {
        await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
          'source.setVariable("bad");source.put("key","bad");throw new Error("fixture");', source, {});
      } catch (_error) { failed = true; }
      expect(failed).assertTrue();
      const result = await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        '[source.getVariable(),source.get("key"),cache.get("entry")].join("|")', source, {});
      expect(result).assertEqual('saved|value|cached');
    });

    it('serializes state changes and keeps different sources isolated', 0, async () => {
      const source = await fixture();
      const other = await fixture();
      const work: Promise<string>[] = [];
      for (let i = 0; i < 4; i++) {
        work.push(LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
          'source.setVariable(String(Number(source.getVariable()||0)+1))', source, {}));
      }
      await Promise.all(work);
      expect(await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'source.getVariable()', source, {})).assertEqual('4');
      expect(await LocalRuleScriptRuntime.evaluate('', other.bookSourceUrl,
        'source.getVariable()', other, {})).assertEqual('');
    });

    it('invalidates the runtime variable only when its definition changes', 0, () => {
      const state = new LocalRuleScriptState();
      state.variable = 'runtime';
      state.definitionVariable = 'initial';
      state.loginHeader = '{"Authorization":"fixture"}';
      expect(LocalRuleScriptState.parse(JSON.stringify(state), 'initial').variable).assertEqual('runtime');
      const changed = LocalRuleScriptState.parse(JSON.stringify(state), 'edited');
      expect(changed.variable).assertEqual('edited');
      expect(changed.loginHeader).assertEqual(state.loginHeader);
    });

    it('defers signed chapter rules and restores them from the stable chapter address', 0, async () => {
      const source = await fixture();
      source.ruleToc.chapterUrl = '@js: source.setVariable(String(Number(source.getVariable()||0)+1));' +
        'baseUrl.split("/toc")[0]+"/chapter/"+java.getString("$.id")+"?attempt="+source.getVariable();';
      const element = LocalRuleStageExtractor.createDocument('{"id":42}', 'https://example.com/toc');
      const address = LocalRuleChapterRequest.create(element, {});
      expect(await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'source.getVariable()', source, {})).assertEqual('');
      expect(await LocalRuleChapterRequest.resolve(address, source, {}))
        .assertEqual('https://example.com/chapter/42?attempt=1');
      expect(await LocalRuleChapterRequest.resolve(address, source, {}))
        .assertEqual('https://example.com/chapter/42?attempt=2');
      expect(LocalRuleChapterRequest.create(element, {})).assertEqual(address);
    });

    it('handles discovery controls and bounded actions', 0, async () => {
      const source = await fixture();
      const panel = LocalRulePanelService.parse('[{"title":"Channel","type":"select",' +
        '"chars":["A","B"],"default":"A","action":"source.setVariable(infoMap.Channel);java.refreshExplore();"},' +
        '{"title":"Popular","url":"/books?page={{page}}"}]');
      expect(panel.entries.length).assertEqual(1);
      panel.controls[0].value = 'B';
      const result = await LocalRulePanelService.act(source, panel.controls[0], panel.controls, false);
      expect(result.refresh).assertTrue();
      expect(await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'source.getVariable()', source, {})).assertEqual('B');
    });

    it('persists explicit cookies by origin without leaking to another host', 0, async () => {
      const source = await fixture();
      await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'cookie.setCookie("https://example.com","a=1");cookie.setCookie("https://example.com","b=2");', source, {});
      expect(await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'cookie.getCookie("https://example.com")', source, {})).assertContain('b=2');
      expect(await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'cookie.getCookie("https://other.example.com")', source, {})).assertEqual('');
      await LocalRuleScriptRuntime.evaluate('', source.bookSourceUrl,
        'cookie.removeCookie("https://example.com","a")', source, {});
      expect(await LocalRuleHttpClient.getStoredCookieHeader(source.bookSourceUrl, 'https://example.com'))
        .assertEqual('b=2');
    });

    it('does not report cancelled debug work as successful', 0, async () => {
      const source = await fixture();
      const variables = LocalRuleDiagnostics.open(() => {});
      LocalRuleDiagnostics.cancel(variables);
      const result = await LocalRuleDebugService.run(source, 'full', 'test', '', variables);
      LocalRuleDiagnostics.close(variables);
      expect(result.success).assertFalse();
      expect(result.error).assertContain('停止');
    });

    it('preserves explicit browser request options and redacts sensitive values', 0, () => {
      const source = LocalRuleSource.descriptor('https://example.com', 'Fixture');
      expect(LocalRuleUrlAnalyzer.analyze(source, '/render,{"webView":true}').webView).assertTrue();
      expect(LocalRuleDiagnostics.redact('https://example.com/?token=private&name=visible'))
        .assertEqual('https://example.com/?token=[redacted]&name=visible');
    });

    it('reserves rate-limit slots across concurrent callers', 0, async () => {
      const source = await fixture();
      const starts: number[] = [];
      const take = async (): Promise<void> => {
        await LocalRuleRequestLimiter.acquire(source.bookSourceUrl, '1/35', 500, {});
        starts.push(Date.now());
      };
      await Promise.all([take(), take(), take()]);
      expect(starts[2] - starts[0] >= 65).assertTrue();
    });

    it('parses request options containing escaped quotes and nested braces', 0, () => {
      const source = LocalRuleSource.descriptor('https://example.com', 'Fixture');
      const headers: Record<string, string> = { 'X-Fixture': 'value' };
      const options: Record<string, Object> = { 'method': 'POST', 'body': '{"name":"a{b}c","text":"quoted \\"value\\""}',
        'header': headers };
      const plan = LocalRuleUrlAnalyzer.analyze(source, '/request,' + JSON.stringify(options));
      expect(plan.url).assertEqual('https://example.com/request');
      expect(plan.method).assertEqual('POST');
      expect(plan.headers['X-Fixture']).assertEqual('value');
      expect(String(plan.body)).assertEqual(String(options['body']));
    });

    it('preserves keyword encoding through the script address resolver', 0, async () => {
      const source = await fixture();
      const variables: Record<string, string> = {};
      const address = await LocalRuleScriptRuntime.resolveAddress('/search?q={{key}}&page={{page-1}}',
        source, variables, 'A&B+C', 2);
      const plan = LocalRuleUrlAnalyzer.analyze(source, address, variables, 'A&B+C', 2);
      expect(plan.url).assertEqual(source.bookSourceUrl.substring(0, source.bookSourceUrl.indexOf('/', 8)) +
        '/search?q=A%26B%2BC&page=1');
    });
  });
}
