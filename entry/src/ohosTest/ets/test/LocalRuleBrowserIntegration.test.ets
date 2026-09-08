import { abilityDelegatorRegistry } from '@kit.TestKit';
import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../../../main/ets/model/LocalRuleSource';
import { LocalRuleHttpClient } from '../../../main/ets/service/rulesource/LocalRuleHttpClient';
import { LocalRuleScriptRuntime } from '../../../main/ets/service/rulesource/LocalRuleScriptRuntime';
import { LocalRuleWebSession } from '../../../main/ets/service/rulesource/LocalRuleWebSession';
import { LocalRuleSourceRepository } from '../../../main/ets/service/rulesource/LocalRuleSourceRepository';
import { LocalRuleDispatcher } from '../../../main/ets/service/rulesource/LocalRuleDispatcher';

export default function localRuleBrowserIntegrationTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const base = String(parameters['-s fixtureUrl'] ?? '');
  if (!base) return;
  describe('LocalRuleBrowserIntegration', () => {
    const source = LocalRuleSource.descriptor(base + '/fixture-source/' + Date.now(), 'HTTP integration fixture');
    beforeAll(async () => {
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.huan.listenbook', abilityName: 'EntryAbility' });
      await LocalRuleSourceRepository.init(abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry'));
      await LocalRuleSourceRepository.insert(source);
    });
    afterAll(async () => { await LocalRuleSourceRepository.remove(source.bookSourceUrl); });

    it('preserves raw redirect headers and unsuccessful bodies for source scripts', 0, async () => {
      expect(await LocalRuleScriptRuntime.evaluate('', base,
        'var r=java.post(baseUrl+"/redirect","key=value",{});r.code()+"|"+r.header("LOCATION")+"|"+r.body()', source, {}))
        .assertEqual('302|/echo|redirect body');
      expect(await LocalRuleScriptRuntime.evaluate('', base,
        'var r=java.get(baseUrl+"/missing",{});r.code()+"|"+r.body()', source, {}))
        .assertEqual('404|{"error":"fixture missing"}');
    });

    it('follows redirects in document requests and carries source cookies', 0, async () => {
      const response = await LocalRuleHttpClient.fetch(source, base + '/redirect');
      expect(response.ok).assertTrue();
      expect(response.requestUrl).assertEqual(base + '/echo');
      expect(response.body).assertContain('fixture=redirect');
    });

    it('loads source-declared remote libraries through the bounded runtime', 0, async () => {
      const remote = LocalRuleSource.descriptor(source.bookSourceUrl, 'Remote library fixture');
      remote.jsLib = base + '/library.js';
      expect(await LocalRuleScriptRuntime.evaluate('', base, 'fixtureLibrary("ok")', remote, {})).assertEqual('library:ok');
    });

    it('renders page scripts and evaluates webJs over a bounded DOM snapshot', 0, async () => {
      const initial = await LocalRuleHttpClient.fetch(source, base + '/render,{"webView":true}');
      abilityDelegatorRegistry.getAbilityDelegator().printSync(`Rendered fixture: ${initial.errorMessage} ${initial.body.substring(0, 300)}\n`);
      expect(initial.body).assertContain('rendered chapter');
      const options: Record<string, Object> = { 'webView': true,
        'webJs': 'document.querySelector("#chapter").innerText+"|"+window.__BOOK_STATE__.title' };
      const response = await LocalRuleHttpClient.fetch(source, base + '/render,' + JSON.stringify(options));
      abilityDelegatorRegistry.getAbilityDelegator().printSync(`Browser fixture: ${response.errorMessage} ${response.body.substring(0, 120)}\n`);
      expect(response.ok).assertTrue();
      expect(response.body).assertEqual('rendered chapter|rendered state');
      expect(await LocalRuleHttpClient.getStoredCookieHeader(source.bookSourceUrl, base)).assertContain('fixture=browser');
      expect(await LocalRuleScriptRuntime.evaluate('', base,
        'java.webView("<html><body><p id=chapter>inline page</p></body></html>",baseUrl+"/inline","document.querySelector(\\"#chapter\\").innerText")', source, {}))
        .assertEqual('inline page');
    });

    it('releases shared web sessions after a queued waiter times out', 0, async () => {
      const lease = await LocalRuleWebSession.acquire(100);
      let timedOut = false;
      try { await LocalRuleWebSession.acquire(10); } catch (_error) { timedOut = true; }
      expect(timedOut).assertTrue();
      LocalRuleWebSession.release(lease);
      const next = await LocalRuleWebSession.acquire(100);
      LocalRuleWebSession.release(next);
    });

    it('interacts with the live DOM and replays each click exactly once', 0, async () => {
      const options: Record<string, Object> = { 'webView': true, 'webJs':
        'var input=document.getElementById("query");input.value="book";' +
        'input.dispatchEvent(new Event("input",{bubbles:true}));' +
        'var button=document.querySelector("#go");button.click();button.click();java.sleep(250);' +
        'document.querySelector("#result").textContent+"|"+document.querySelector("#events").textContent+' +
        '"|"+document.querySelector("#clicks").textContent+"|"+window.pageState.count' };
      const response = await LocalRuleHttpClient.fetch(source, base + '/interactive,' + JSON.stringify(options));
      abilityDelegatorRegistry.getAbilityDelegator().printSync(`Interactive: ${response.errorMessage} ${response.body}\n`);
      expect(response.ok).assertTrue();
      expect(response.body).assertEqual('loaded:book|1|2|2');
    });

    it('runs delayed callbacks and supports form navigation without stale elements', 0, async () => {
      const options: Record<string, Object> = { 'webView': true, 'webJs':
        'var old=document.querySelector("#result");document.querySelector("#form").submit();java.sleep(500);' +
        'var stale=false;try{old.textContent;}catch(e){stale=true;}' +
        'document.body.querySelector("#result").innerText+"|"+stale+"|"+location.href.includes("/navigated")' };
      const response = await LocalRuleHttpClient.fetch(source, base + '/interactive,' + JSON.stringify(options));
      abilityDelegatorRegistry.getAbilityDelegator().printSync(`Navigation: ${response.errorMessage} ${response.body}\n`);
      expect(response.body).assertEqual('navigation complete|true|true');
      options['webJs'] = 'setTimeout(function(){document.querySelector("#query").value="timer";document.querySelector("#go").click();},50);"scheduled"';
      const timed = await LocalRuleHttpClient.fetch(source, base + '/interactive,' + JSON.stringify(options));
      expect(timed.ok).assertTrue();
      expect(timed.body).assertEqual('scheduled');
      options['webJs'] = '(async function(){await new Promise(r=>setTimeout(r,50));' +
        'document.querySelector("#query").value="async";document.querySelector("#go").click();' +
        'await new Promise(r=>setTimeout(r,200));return document.querySelector("#result").textContent;})()';
      const asynchronous = await LocalRuleHttpClient.fetch(source, base + '/interactive,' + JSON.stringify(options));
      expect(asynchronous.body).assertEqual('loaded:async');
    });

    it('rejects executable DOM writes and releases the browser after failures', 0, async () => {
      const options: Record<string, Object> = { 'webView': true,
        'webJs': 'document.querySelector("#go").setAttribute("onclick","while(true){}");"bad"' };
      const rejected = await LocalRuleHttpClient.fetch(source, base + '/interactive,' + JSON.stringify(options));
      expect(rejected.ok).assertFalse();
      expect(rejected.errorMessage).assertContain('Unsupported DOM attribute');
      options['webJs'] = 'java.sleep(10001)';
      expect((await LocalRuleHttpClient.fetch(source, base + '/interactive,' + JSON.stringify(options))).ok).assertFalse();
      options['webJs'] = 'document.querySelector("#result").textContent';
      expect((await LocalRuleHttpClient.fetch(source, base + '/interactive,' + JSON.stringify(options))).body).assertEqual('waiting');
    });

    it('keeps supplied HTML scripts inert while allowing bounded DOM actions', 0, async () => {
      const options: Record<string, Object> = {
        'webView': true,
        'webHtml': '<!doctype html><html><body><p id="value">safe</p>' +
          '<script>document.querySelector("#value").textContent="unsafe";</script></body></html>',
        'webJs': 'var before=document.querySelector("#value").textContent;' +
          'document.querySelector("#value").textContent="updated";before'
      };
      const response = await LocalRuleHttpClient.fetch(source, base + '/supplied,' + JSON.stringify(options));
      expect(response.ok).assertTrue();
      expect(response.body).assertEqual('safe');
      expect(response.renderedHtml).assertContain('updated');
    });

    it('persists generated session cookies per source and destination', 0, async () => {
      const response = await LocalRuleHttpClient.fetch(source, base + '/echo?reader=fixture-token,' +
        '{"session":{"queryCookies":{"readerToken":"reader"},"generatedCookies":{"device":"@uuid"},"referer":"origin"}}');
      expect(response.ok).assertTrue();
      expect(response.body).assertContain('readerToken=fixture-token');
      const first = await LocalRuleHttpClient.getStoredCookieHeader(source.bookSourceUrl, base);
      expect(first).assertContain('device=');
      const again = await LocalRuleHttpClient.fetch(source, base + '/echo,{"session":{"generatedCookies":{"device":"@uuid"}}}');
      expect(again.body).assertContain(first);
      expect(await LocalRuleHttpClient.getStoredCookieHeader(source.bookSourceUrl + '-other', base)).assertEqual('');
    });

    it('resolves an audio URL created by a page script', 0, async () => {
      const audio = LocalRuleSource.descriptor(source.bookSourceUrl, 'Rendered audio fixture');
      audio.bookSourceType = 1;
      audio.ruleContent.sourceRegex = 'https?://[^\\s"<>]+/fixture-audio\\.mp3';
      const result = await LocalRuleDispatcher.resolveContent(audio, base + '/render-media,{"webView":true}');
      expect(result.audioUrl).assertEqual(base + '/fixture-audio.mp3');
    });
  });
}
