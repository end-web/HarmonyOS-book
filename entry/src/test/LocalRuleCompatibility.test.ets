import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleSource } from '../main/ets/model/LocalRuleSource';
import { LocalRuleScriptRuntime } from '../main/ets/service/rulesource/LocalRuleScriptRuntime';
import { LocalRuleStageExtractor } from '../main/ets/service/rulesource/LocalRuleStageExtractor';
import { LocalRuleUrlAnalyzer } from '../main/ets/service/rulesource/LocalRuleUrlAnalyzer';
import { LocalRuleHttpClient } from '../main/ets/service/rulesource/LocalRuleHttpClient';
import { LocalRuleDispatcher } from '../main/ets/service/rulesource/LocalRuleDispatcher';
import { LocalRulePanelService } from '../main/ets/service/rulesource/LocalRulePanelService';
import { LocalRuleRequestSession } from '../main/ets/service/rulesource/LocalRuleRequestSession';
import { LocalRuleCryptoFixtures } from './LocalRuleCryptoFixtures';
import { LocalRuleQuickJsRequest, LocalRuleQuickJsRuntime } from '../main/ets/service/rulesource/LocalRuleQuickJsRuntime';
import { LocalRuleJsonLiteral } from '../main/ets/service/rulesource/LocalRuleJsonLiteral';

export default function localRuleCompatibilityTest() {
  describe('LocalRuleCompatibility', () => {
    const source = LocalRuleSource.descriptor('https://compatibility.invalid', 'Compatibility');
    const evaluate = async (code: string, content: string = ''): Promise<string> =>
      LocalRuleScriptRuntime.evaluate(content, source.bookSourceUrl, code, source, {});

    it('decodes data payloads without interpreting payload JSON as options', 0, async () => {
      const response = await LocalRuleHttpClient.fetch(source, 'data:application/json,{"books":[{"id":1}]}');
      expect(response.ok).assertTrue();
      expect(response.body).assertEqual('{"books":[{"id":1}]}');
      expect((await LocalRuleHttpClient.fetch(source, 'data:;base64,5Lmm5rqQ,{"charset":"utf-8"}')).body)
        .assertEqual('书源');
      expect((await LocalRuleHttpClient.fetch(source, 'data:,%E4%B9%A6%E6%BA%90+test')).body).assertEqual('书源+test');
      expect((await LocalRuleHttpClient.fetch(source, 'data:;base64,%%%')).ok).assertFalse();
    });

    it('executes only explicit data request options', 0, () => {
      const plan = LocalRuleUrlAnalyzer.analyze(source,
        'data:,ignored,{"type":"request","url":"https://example.com/api","method":"POST","body":"a=1"}');
      expect(plan.inlineBody === undefined).assertTrue();
      expect(plan.url).assertEqual('https://example.com/api');
      expect(plan.method).assertEqual('POST');
      expect(String(plan.body)).assertEqual('a=1');
      expect(LocalRuleUrlAnalyzer.analyze(source, '/redirect,{"redirect":false}').followRedirects).assertFalse();
    });

    it('returns bytes as hex for typed aggregate data URLs and keeps ordinary data as text', 0, async () => {
      const plain = 'data:;base64,eyJpZCI6N30=';
      const typed = await LocalRuleHttpClient.fetch(source, plain + ',{"type":"gydetail"}');
      expect(typed.ok).assertTrue();
      expect(typed.body).assertEqual('7b226964223a377d');
      expect(await evaluate('JSON.parse(java.hexDecodeToString(result)).id', typed.body)).assertEqual('7');
      expect((await LocalRuleHttpClient.fetch(source, plain)).body).assertEqual('{"id":7}');
      expect((await LocalRuleHttpClient.fetch(source, 'data:;base64,AP+A/g==,{"type":"binary"}')).body)
        .assertEqual('00ff80fe');
    });

    it('preserves object fields when aggregate rules construct detail and chapter URLs', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"data":[{"id":7,"title":"Novel"}]}', source.bookSourceUrl);
      const items = await LocalRuleStageExtractor.selectList(document, '$.data', source);
      const address = await LocalRuleStageExtractor.extract(items[0],
        '<js>"data:;base64,"+java.base64Encode(JSON.stringify({id:result.id,title:result.title}))+",{\\"type\\":\\"detail\\"}"</js>', source);
      const response = await LocalRuleHttpClient.fetch(source, address);
      expect(await evaluate('java.hexDecodeToString(result)', response.body)).assertEqual('{"id":7,"title":"Novel"}');
      expect(await LocalRuleStageExtractor.extract(items[0], '@js:JSON.parse(result).title', source)).assertEqual('Novel');
    });

    it('preserves binary Base64 and common Android Java aliases', 0, async () => {
      expect(await evaluate('java.hexEncodeToString(android.util.Base64.decode("AP+A/g==",0))')).assertEqual('00ff80fe');
      expect(await evaluate('new java.lang.String(java.util.Base64.getDecoder().decode("5Lmm5rqQ"),"UTF-8").toString()'))
        .assertEqual('书源');
      expect(await evaluate('java.base64UrlEncode([255,254,253])+"|"+java.hexEncodeToString(java.base64Decode("__79"))'))
        .assertEqual('__79|fffefd');
    });

    it('applies declarative session values without cookie header injection', 0, () => {
      const plan = LocalRuleUrlAnalyzer.analyze(source, 'https://example.com/read?token=a%2Bb&bad=x%3By%3Dz,' +
        '{"headers":{"Cookie":"device=existing"},"session":{"queryCookies":{"auth":"token","unsafe":"bad"},' +
        '"generatedCookies":{"device":"@uuid"},"referer":"origin"}}');
      expect(LocalRuleRequestSession.apply(plan)).assertEqual('device=existing; auth=a+b');
      expect(plan.headers['Referer']).assertEqual('https://example.com/');
    });

    it('preserves JSON structure when search keywords contain quotes or backslashes', 0, () => {
      const plan = LocalRuleUrlAnalyzer.analyze(source,
        '/search,{"method":"POST","body":{"query":"{{key}}","nested":["{{key}}"],"page":1}}', {}, 'a"b\\c', 1);
      expect(JSON.stringify(plan.body)).assertEqual('{"query":"a\\"b\\\\c","nested":["a\\"b\\\\c"],"page":1}');
    });

    it('transforms response bodies in the bounded runtime', 0, async () => {
      const transform = LocalRuleSource.descriptor('https://transform.invalid', 'Transform');
      transform.jsLib = 'function titleOf(value){return JSON.parse(value).title;}';
      const response = await LocalRuleHttpClient.fetch(transform,
        'data:application/json,%7B%22title%22%3A%22Book%22%7D,{"bodyJs":"titleOf(result)"}');
      expect(response.ok).assertTrue();
      expect(response.body).assertEqual('Book');
    });

    it('matches standard SHA and HMAC vectors through bounded actions', 0, async () => {
      expect(await evaluate('java.sha256("abc")')).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(await evaluate('java.hmacSha256("The quick brown fox jumps over the lazy dog","key")'))
        .assertEqual('f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
      expect(await evaluate('java.hexEncodeToString(java.security.MessageDigest.getInstance("SHA-1").digest("abc".getBytes()))'))
        .assertEqual('a9993e364706816aba3e25717850c26c9cd0d89d');
    });

    it('matches the NIST AES CBC vector through Cipher aliases', 0, async () => {
      expect(await evaluate('var cipher=javax.crypto.Cipher.getInstance("AES/CBC/NoPadding");' +
        'cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(java.hexDecode("2b7e151628aed2a6abf7158809cf4f3c"),"AES"),' +
        'new IvParameterSpec(java.hexDecode("000102030405060708090a0b0c0d0e0f")));' +
        'java.hexEncodeToString(cipher.doFinal(java.hexDecode("6bc1bee22e409f96e93d7e117393172a")))'))
        .assertEqual('7649abac8119b246cee98e9b12e9197d');
      expect(await evaluate('createSymmetricCrypto("AES/CBC/PKCS5Padding","0123456789abcdef","fedcba9876543210")' +
        '.decryptBase64ToString(createSymmetricCrypto("AES/CBC/PKCS5Padding","0123456789abcdef","fedcba9876543210").encryptBase64("书源"))'))
        .assertEqual('书源');
    });

    it('supports collection and form URL encoding semantics', 0, async () => {
      expect(await evaluate('var m=new java.util.HashMap();m.put("title","book");var a=new java.util.ArrayList();' +
        'a.add(m.get("title"));new java.lang.StringBuilder().append(a.get(0)).append(a.size()).toString()')).assertEqual('book1');
      expect(await evaluate('java.urlEncode("A B+C&")+"|"+java.urlDecode("A+B%2BC%26")')).assertEqual('A+B%2BC%26|A B+C&');
    });

    it('supports the upstream AES helper names and argument order', 0, async () => {
      expect(await evaluate('var value=java.aesEncodeToBase64String("book","0123456789abcdef","AES/CBC/PKCS5Padding","fedcba9876543210");' +
        'java.aesBase64DecodeToString(value,"0123456789abcdef","AES/CBC/PKCS5Padding","fedcba9876543210")')).assertEqual('book');
      expect(await evaluate('java.hexEncodeToString(java.base64DecodeToByteArray("AP+A/g=="))')).assertEqual('00ff80fe');
    });

    it('runs legacy DES protocol vectors only inside the bounded script runtime', 0, async () => {
      expect(await evaluate('java.createSymmetricCrypto("DES/ECB/NoPadding",java.hexDecode("133457799bbcdff1"))' +
        '.encryptHex(java.hexDecode("0123456789abcdef"))')).assertEqual('85e813540f0ab405');
      expect(await evaluate('java.desBase64DecodeToString(java.desEncodeToBase64String("book","12345678","DES/CBC/PKCS5Padding","87654321"),' +
        '"12345678","DES/CBC/PKCS5Padding","87654321")')).assertEqual('book');
      expect(await evaluate('var bad=false;try{java.createSymmetricCrypto("DES/ECB/PKCS5Padding",java.hexDecode("133457799bbcdff1"))' +
        '.decryptHex("85e813540f0ab405");}catch(e){bad=true;}String(bad)')).assertEqual('true');
    });

    it('preserves quoted request data in loose source literals and rejects executable values', 0, () => {
      const literal = LocalRuleJsonLiteral.parse("{method:'POST',body:{text:\"don't alter {key:value},}\",escaped:'a\\'b'},}");
      expect(JSON.stringify(literal)).assertEqual('{"method":"POST","body":{"text":"don\'t alter {key:value},}","escaped":"a\'b"}}');
      let failed = false;
      try { LocalRuleJsonLiteral.parse('{body:(function(){return 7;})()}'); } catch (_error) { failed = true; }
      expect(failed).assertTrue();
    });

    it('preserves named source variables and exposes effective source metadata', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://metadata.invalid', 'Metadata');
      fixture.header = '{"Referer":"https://metadata.invalid/"}';
      fixture.bookSourceComment = 'comment';
      const variables: Record<string, string> = { 'keyword': 'novel', 'customStageValue': 'context' };
      const value = await LocalRuleScriptRuntime.evaluate('', fixture.bookSourceUrl,
        'source.setVariable("selected");source.setVariable("token","value");source.putLoginInfo({account:"reader"});' +
        'cache.putMemory("preview","ok");source.getVariable()+"|"+source.getVariable("token")+"|"+' +
        'source.getHeaderMap().Referer+"|"+source.getLoginInfo("account")+"|"+cache.getFromMemory("preview")+"|"+' +
        'keyword+"|"+customStageValue+"|"+source.bookSourceComment', fixture, variables);
      expect(value).assertEqual('selected|value|https://metadata.invalid/|reader|ok|novel|context|comment');
    });

    it('persists typed cache values and changes made through the login map', 0, async () => {
      await evaluate('source.putLoginInfo("token","secret");source.getLoginInfoMap().put("account","updated");' +
        'source.put("typed",{value:1});source.get("typed").value++;cache.put("typed",{value:3});cache.get("typed").value++;' +
        'cache.put("jsonString",JSON.stringify({value:5}));');
      expect(await evaluate('source.get("typed").value+"|"+cache.get("typed").value+"|"+typeof cache.get("jsonString")+"|"+' +
        'source.getLoginInfo("account")')).assertEqual('2|4|string|updated');
    });

    it('postprocesses complete lists with typed JSON items and supports reverse rules', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"items":[{"id":1},{"id":2},{"id":3}]}', source.bookSourceUrl);
      const items = await LocalRuleStageExtractor.selectList(document,
        '$.items[*]<js>result.filter(function(item){return item.id>1;}).reverse()</js>', source);
      expect(items.length).assertEqual(2);
      expect(items[0].payload).assertEqual('{"id":3}');
      expect(items[1].payload).assertEqual('{"id":2}');
      const reversed = await LocalRuleStageExtractor.selectList(document, '-$.items[*]', source);
      expect(reversed[0].payload).assertEqual('{"id":3}');
    });

    it('applies JavaScript and regex field processors without leaking the suffix into script code', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"title":"prefix 123 suffix 456"}', source.bookSourceUrl);
      expect(await LocalRuleStageExtractor.extract(document, '$.title##(\\d+)##ID:$1###', source)).assertEqual('ID:123');
      expect(await LocalRuleStageExtractor.extract(document,
        '$.title@js:result.toUpperCase()##PREFIX##Book', source)).assertEqual('Book 123 SUFFIX 456');
      expect(await LocalRuleStageExtractor.extract(document,
        '$.title##PREFIX##Book@js:result.toUpperCase()', source)).assertEqual('Book 123 SUFFIX 456');
    });

    it('formats epoch zero and freezes Date constructors during action replay', 0, async () => {
      expect(await evaluate('java.timeFormatUTC(0,"yyyy-MM-dd HH:mm:ss.SSS",8)')).assertEqual('1970-01-01 08:00:00.000');
      expect(await evaluate('var started=new Date().getTime();java.sha256(String(started));String(started===Date.now())')).assertEqual('true');
    });

    it('supports sorted Java maps and collection iterators used in signatures', 0, async () => {
      expect(await evaluate('importClass(java.util.TreeMap);var map=new TreeMap();map.put("z",3);map.put("a",1);map.put("m",2);' +
        'var entries=map.entrySet().iterator(),parts=[];while(entries.hasNext()){var e=entries.next();parts.push(e.getKey()+"="+e.getValue());}' +
        'parts.join("&")+"|"+map.values().get(1)')).assertEqual('a=1&m=2&z=3|2');
      expect(await evaluate('var classes=new JavaImporter(java.util,java.util.regex);with(classes){var set=new HashSet(["a","a","b"]);' +
        'var list=Arrays.asList([3,1,2]);Collections.sort(list);set.size()+"|"+list.join(",")}')).assertEqual('2|1,2,3');
    });

    it('preserves Java integer precision and rejects partial numeric strings', 0, async () => {
      expect(await evaluate('java.lang.Long.parseLong("9223372036854775807").toString()')).assertEqual('9223372036854775807');
      expect(await evaluate('new java.math.BigInteger(1,java.hexDecode("ff80")).toString(16)+"|"+' +
        'new java.math.BigInteger("12345678901234567890").add(new BigInteger("1")).toString()'))
        .assertEqual('ff80|12345678901234567891');
      expect(await evaluate('var bad=false;try{java.lang.Integer.parseInt("12x");}catch(e){bad=true;}String(bad)')).assertEqual('true');
    });

    it('provides Java pattern groups and quoted literal matching', 0, async () => {
      expect(await evaluate('importClass(java.util.regex.Pattern);var m=Pattern.compile("第(\\\\d+)章").matcher("第12章 第34章");' +
        'var out=[];while(m.find())out.push(m.group(1));out.join(",")')).assertEqual('12,34');
      expect(await evaluate('java.util.regex.Pattern.matches(java.util.regex.Pattern.quote("a+b[1]"),"a+b[1]")')).assertEqual('true');
    });

    it('supports typed JSON access and memory-only Java streams', 0, async () => {
      expect(await evaluate('importClass(org.json.JSONObject);var obj=new JSONObject(\'{"items":[{"id":7}],"enabled":true}\');' +
        'obj.getJSONArray("items").getJSONObject(0).getInt("id")+"|"+obj.getBoolean("enabled")+"|"+obj.optString("missing","fallback")'))
        .assertEqual('7|true|fallback');
      expect(await evaluate('var output=new java.io.ByteArrayOutputStream();output.write("书源\\nnext".getBytes("UTF-8"));' +
        'var reader=new java.io.BufferedReader(new java.io.InputStreamReader(new java.io.ByteArrayInputStream(output.toByteArray()),"UTF-8"));' +
        'reader.readLine()+"|"+reader.readLine()+"|"+reader.readLine()')).assertEqual('书源|next|null');
    });

    it('implements incremental Java Mac and blocks imports outside the class registry', 0, async () => {
      expect(await evaluate('importClass(javax.crypto.Mac);var mac=Mac.getInstance("HmacSHA256");mac.init(new SecretKeySpec("key".getBytes(),"HmacSHA256"));' +
        'mac.update("The quick brown fox ".getBytes());java.hexEncodeToString(mac.doFinal("jumps over the lazy dog".getBytes()))'))
        .assertEqual('f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
      expect(await evaluate('var n=0;["java.io.File","java.lang.Runtime","java.lang.System.constructor"].forEach(function(t){try{Java.type(t);}catch(e){n++;}});String(n)'))
        .assertEqual('3');
    });

    it('supports Java binary compression with bounded memory and standard fixtures', 0, async () => {
      expect(await evaluate('new java.lang.String(new java.util.zip.GZIPInputStream(new java.io.ByteArrayInputStream(java.hexDecode("' +
        LocalRuleCryptoFixtures.GZIP + '"))).readAllBytes(),"UTF-8").toString()')).assertEqual('书源\nnext');
      expect(await evaluate('var output=new java.io.ByteArrayOutputStream();var zip=new java.util.zip.GZIPOutputStream(output);' +
        'zip.write("roundtrip".getBytes());zip.finish();new java.lang.String(new java.util.zip.GZIPInputStream(' +
        'new java.io.ByteArrayInputStream(output.toByteArray())).readAllBytes(),"UTF-8").toString()')).assertEqual('roundtrip');
      expect(await evaluate('var inflater=new java.util.zip.Inflater();inflater.setInput(java.hexDecode("' +
        LocalRuleCryptoFixtures.ZLIB + '"));var bytes=new (Java.type("byte[]"))(32);var count=inflater.inflate(bytes);' +
        'new java.lang.String(bytes.slice(0,count),"UTF-8").toString()+"|"+inflater.finished()')).assertEqual('book source|true');
      expect(await evaluate('var crc=new java.util.zip.CRC32();crc.update("123456789".getBytes());String(crc.getValue())')).assertEqual('3421780262');
    });

    it('uses Java RSA key specifications and standard signature vectors', 0, async () => {
      const keys = 'var factory=java.security.KeyFactory.getInstance("RSA");' +
        'var publicKey=factory.generatePublic(new java.security.spec.X509EncodedKeySpec(java.base64Decode("' +
        LocalRuleCryptoFixtures.PUBLIC_KEY + '")));' +
        'var privateKey=factory.generatePrivate(new java.security.spec.PKCS8EncodedKeySpec(java.base64Decode("' +
        LocalRuleCryptoFixtures.PRIVATE_KEY + '")));';
      expect(await evaluate(keys + 'var signer=java.security.Signature.getInstance("SHA256withRSA");signer.initSign(privateKey);' +
        'signer.update("source-compatibility".getBytes());java.hexEncodeToString(signer.sign())')).assertEqual(LocalRuleCryptoFixtures.SIGNATURE);
      expect(await evaluate(keys + 'var verifier=java.security.Signature.getInstance("SHA256withRSA");verifier.initVerify(publicKey);' +
        'verifier.update("source-compatibility".getBytes());String(verifier.verify(java.hexDecode("' +
        LocalRuleCryptoFixtures.SIGNATURE + '")))')).assertEqual('true');
      expect(await evaluate(keys + 'var cipher=javax.crypto.Cipher.getInstance("RSA/ECB/PKCS1Padding");cipher.init(Cipher.ENCRYPT_MODE,publicKey);' +
        'var encrypted=cipher.doFinal("book".getBytes());cipher.init(Cipher.DECRYPT_MODE,privateKey);' +
        'new java.lang.String(cipher.doFinal(encrypted),"UTF-8").toString()')).assertEqual('book');
    });

    it('preserves Java Base64 padding and date formatting semantics', 0, async () => {
      expect(await evaluate('java.util.Base64.getUrlEncoder().encodeToString([255])+"|"+' +
        'java.util.Base64.getUrlEncoder().withoutPadding().encodeToString([255])+"|"+android.util.Base64.encodeToString([255],10)'))
        .assertEqual('_w==|_w|_w==');
      expect(await evaluate('var format=new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss");' +
        'format.setTimeZone(java.util.TimeZone.getTimeZone("GMT+08:00"));format.format(format.parse("1970-01-01 08:00:00"))'))
        .assertEqual('1970-01-01 08:00:00');
      expect(await evaluate('importClass(java.lang.String);new String(java.base64Decode("Ym9vaw=="),"UTF-8").toString()')).assertEqual('book');
    });

    it('resolves Java URI and URL components through structured parsers', 0, async () => {
      expect(await evaluate('var u=new java.net.URI("https://example.com/a/b?x=1").resolve("../book?id=2#read");' +
        'u.getHost()+"|"+u.getPath()+"|"+u.getQuery()+"|"+u.getFragment()')).assertEqual('example.com|/book|id=2|read');
      expect(await evaluate('new java.net.URL("https://example.com/a/","../book").toExternalForm()')).assertEqual('https://example.com/book');
    });

    it('settles returned promises inside native QuickJS execution budgets', 0, async () => {
      const request = new LocalRuleQuickJsRequest();
      request.script = 'Promise.resolve("book").then(value=>value+" source")';
      request.maxPendingJobs = 32;
      const settled = await LocalRuleQuickJsRuntime.execute(request);
      expect(settled.success).assertTrue();
      expect(settled.value).assertEqual('book source');
      request.script = 'new Promise(function(){})';
      const pending = await LocalRuleQuickJsRuntime.execute(request);
      expect(pending.success).assertFalse();
      expect(pending.errorMessage).assertContain('pending-job budget');
      request.script = 'Promise.resolve().then(function(){while(true){}})';
      request.timeoutMs = 20;
      const timeout = await LocalRuleQuickJsRuntime.execute(request);
      expect(timeout.success).assertFalse();
      expect(timeout.timedOut).assertTrue();
      expect(await evaluate('(async function(){return await Promise.resolve("recovered");})()')).assertEqual('recovered');
    });

    it('implements Java Thread sleep with deterministic elapsed time during replay', 0, async () => {
      expect(await evaluate('var before=Date.now();Java.type("java.lang.Thread").sleep(10);java.lang.Thread.sleep(10);' +
        'String(Date.now()-before)+"|"+String(new Date().getTime()===java.lang.System.currentTimeMillis())')).assertEqual('20|true');
    });

    it('provides Java source globals to library function receivers', 0, async () => {
      expect(await evaluate('String(this.source===source&&this.java===java&&this.book===book&&this.baseUrl===baseUrl)')).assertEqual('true');
    });

    it('shares library helpers with their global receiver through replay and isolates subsequent executions', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://library-scope.invalid', 'Library scope');
      fixture.jsLib = 'const prefix="scope:";function getSetting(){return this.source.getVariable()||"initial";}' +
        'function update(){this.source.setVariable("updated");this.java.sha256(this.getSetting());return prefix+this.getSetting();}';
      expect(await LocalRuleScriptRuntime.evaluate('', fixture.bookSourceUrl, 'update()', fixture, {})).assertEqual('scope:updated');
      expect(await LocalRuleScriptRuntime.evaluate('', fixture.bookSourceUrl, 'return this.getSetting();', fixture, {})).assertEqual('updated');
      expect(await evaluate('typeof getSetting')).assertEqual('undefined');
    });

    it('submits discovery inputs before search actions and executes script category entries', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://discovery-actions.invalid', 'Discovery actions');
      fixture.jsLib = 'function search(){this.java.searchBook(this.source.getVariable());}';
      const definitions: Record<string, string>[] = [
        { 'title': 'Keyword', 'type': 'text', 'action': 'source.setVariable(infoMap.Keyword)' },
        { 'title': 'Search', 'type': 'button', 'action': 'search()' },
        { 'title': 'Login', 'url': '{{java.startBrowser("https://example.com/login");}}' },
        { 'title': 'Dynamic', 'url': '@js:"https://example.com/category"' },
        { 'title': 'Paged', 'url': 'https://example.com/category?page={{page}}' }
      ];
      const panel = LocalRulePanelService.parse(JSON.stringify(definitions));
      panel.controls[0].value = 'Novel';
      expect((await LocalRulePanelService.act(fixture, panel.controls[1], panel.controls, false)).searchKeyword).assertEqual('Novel');
      expect((await LocalRulePanelService.act(fixture, panel.controls[2], panel.controls, false)).browserUrl)
        .assertEqual('https://example.com/login');
      expect((await LocalRulePanelService.act(fixture, panel.controls[3], panel.controls, false)).browseUrl)
        .assertEqual('https://example.com/category');
      expect(panel.entries.length).assertEqual(1);
      expect(panel.entries[0].url).assertContain('{{page}}');
    });

    it('converts Chinese text and chapter numerals without changing title words', 0, async () => {
      expect(await evaluate('java.t2s("繁體閱讀小說")+"|"+java.s2t("简体阅读小说")'))
        .assertEqual('繁体阅读小说|簡體閱讀小說');
      expect(await evaluate('java.toNumChapter("第一千零二十三章 一生所爱")')).assertEqual('第1023章 一生所爱');
      expect(await evaluate('java.toNumChapter("第两万零六回")')).assertEqual('第20006回');
    });

    it('evaluates full JSONPath inside scripts and preserves list methods', 0, async () => {
      expect(await evaluate('java.getStringList("$.items[*].name").size()+"|"+java.getStringList("$.items[*].name").get(1)',
        '{"items":[{"name":"one"},{"name":"two"}]}')).assertEqual('2|two');
      expect(await evaluate('java.setContent("{\\"name\\":\\"changed\\"}");java.getString("$.name")')).assertEqual('changed');
    });

    it('evaluates field templates with quoted braces and JavaScript calls', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"count":12}', source.bookSourceUrl);
      expect(await LocalRuleStageExtractor.extract(document,
        '{{JSON.stringify({suffix:"}}",count:java.getString("$.count")})}}', source, {}))
        .assertEqual('{"suffix":"}}","count":"12"}');
    });

    it('resolves relative JSON paths and trailing put directives in detail rules', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"data":[{"name":"Book","id":42}]}', source.bookSourceUrl);
      const initialized = await LocalRuleStageExtractor.extract(document, 'data[0]', source, {});
      const current = LocalRuleStageExtractor.createDocument(initialized, source.bookSourceUrl);
      const variables: Record<string, string> = {};
      expect(await LocalRuleStageExtractor.extract(current, 'name@put:{book_id:id}', source, variables)).assertEqual('Book');
      expect(variables['book_id']).assertEqual('42');
      expect(await LocalRuleStageExtractor.extract(current, 'https://example.com/toc?id=@get:{book_id}', source, variables, true))
        .assertEqual('https://example.com/toc?id=42');
    });

    it('applies a trailing JSON selector before expanding script arrays', 0, async () => {
      const document = LocalRuleStageExtractor.createDocument('{"data":[{"name":"one","id":1},{"name":"two","id":2}]}', source.bookSourceUrl);
      const items = await LocalRuleStageExtractor.selectList(document,
        '<js>JSON.stringify(JSON.parse(result).data)</js>$[*]', source, {});
      expect(items.length).assertEqual(2);
      expect(await LocalRuleStageExtractor.extract(items[0], 'name', source, {})).assertEqual('one');
      expect(await LocalRuleStageExtractor.extract(items[1], 'id', source, {})).assertEqual('2');
    });

    it('runs an inline JSON source through search detail toc and content', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://inline.invalid', 'Inline');
      const contentUrl = 'data:,chapter%20body';
      const toc: Record<string, string>[] = [{ 'title': 'Chapter', 'url': contentUrl }];
      const tocUrl = 'data:application/json,' + encodeURIComponent(JSON.stringify(toc));
      const detail: Record<string, string> = { 'name': 'Book', 'toc': tocUrl };
      const detailUrl = 'data:application/json,' + encodeURIComponent(JSON.stringify(detail));
      const search: Record<string, string>[] = [{ 'name': 'Book', 'url': detailUrl }];
      fixture.searchUrl = 'data:application/json,' + encodeURIComponent(JSON.stringify(search));
      fixture.ruleSearch.bookList = '$';
      fixture.ruleSearch.name = '$.name';
      fixture.ruleSearch.bookUrl = '$.url';
      fixture.ruleBookInfo.name = '$.name';
      fixture.ruleBookInfo.tocUrl = '$.toc';
      fixture.ruleToc.chapterList = '$';
      fixture.ruleToc.chapterName = '$.title';
      fixture.ruleToc.chapterUrl = '$.url';
      fixture.ruleContent.content = '@text';
      const books = await LocalRuleDispatcher.searchForHealthCheck(fixture, 'Book');
      expect(books.length).assertEqual(1);
      const info = await LocalRuleDispatcher.getBookInfo(fixture, books[0].bookUrl, books[0].variables);
      expect(info !== null).assertTrue();
      if (info === null) return;
      const chapters = await LocalRuleDispatcher.getBookToc(fixture, info.tocUrl, info.variables);
      expect(chapters.length).assertEqual(1);
      expect(await LocalRuleDispatcher.getContent(fixture, chapters[0].url, chapters[0].variables)).assertEqual('chapter body');
    });

    it('rejects audio error text instead of constructing a successful relative address', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://audio.invalid', 'Audio');
      fixture.bookSourceType = 1;
      fixture.ruleContent.content = '@js:"获取音频失败：token expired"';
      expect((await LocalRuleDispatcher.resolveContent(fixture, 'data:,fixture')).audioUrl).assertEqual('');
      fixture.ruleContent.content = '@js:java.base64Encode("https://audio.invalid/play.mp3?token=fixture")';
      expect((await LocalRuleDispatcher.resolveContent(fixture, 'data:,fixture')).audioUrl)
        .assertEqual('https://audio.invalid/play.mp3?token=fixture');
      fixture.ruleContent.content = '@js:\'https://audio.invalid/play.mp3,{"headers":{"X-Audio":"signed"}}\'';
      const signed = await LocalRuleDispatcher.resolveContent(fixture, 'data:,fixture');
      expect(signed.audioUrl).assertEqual('https://audio.invalid/play.mp3');
      expect(signed.requestHeaders['X-Audio']).assertEqual('signed');
    });

    it('normalizes nested discovery groups and labelled control values', 0, () => {
      const panel = LocalRulePanelService.parse('[{"title":"Library","children":[{"title":"Popular","url":"/hot"}]},' +
        '{"title":"Sort","type":"select","chars":[{"label":"Recent","value":"new"},{"label":"Popular","value":"hot"}]}]');
      expect(panel.entries.length).assertEqual(2);
      expect(panel.entries[1].url).assertEqual('/hot');
      expect(panel.controls[0].options[0]).assertEqual('Recent');
      expect(panel.controls[0].value).assertEqual('new');
      expect(panel.controls[0].optionValues[1]).assertEqual('hot');
    });

    it('loads login functions and routes browser actions without exposing platform APIs', 0, async () => {
      const login = LocalRuleSource.descriptor('https://login.invalid', 'Login');
      login.loginUrl = '@js:function openLogin(){java.startBrowser("https://login.invalid/account");}';
      login.loginUi = '[{"title":"Sign in","type":"button","action":"openLogin()"}]';
      login.loginCheckJs = 'false';
      const panel = await LocalRulePanelService.load(login, true);
      const action = await LocalRulePanelService.act(login, panel.controls[0], panel.controls, true);
      expect(action.browserUrl).assertEqual('https://login.invalid/account');
      let failed = false;
      try { await LocalRulePanelService.checkLogin(login, ''); } catch (_error) { failed = true; }
      expect(failed).assertTrue();
    });

    it('loads legacy login panels with JavaScript literal syntax', 0, async () => {
      const fixture = LocalRuleSource.descriptor('https://panel-literal.invalid', 'Panel literal');
      fixture.loginUi = "[{name:'Account',type:'text',default:'reader',},{name:'Sign in',type:'button',action:'login()',},]";
      const panel = await LocalRulePanelService.load(fixture, true);
      expect(panel.controls.length).assertEqual(2);
      expect(panel.controls[0].value).assertEqual('reader');
      expect(panel.controls[1].action).assertEqual('login()');
    });
  });
}
