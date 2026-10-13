// Reuse the real ArkTS loader, replacing only platform HTTP for targeted boundary regressions.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const fixture = path.join(__dirname, 'test-native-rule-pipeline.cjs');
const loader = fs.readFileSync(fixture, 'utf8').split('async function run() {')[0];
const checks = String.raw`
function sourceOf(definition) {
  const result = Parser.parse(JSON.stringify(definition)).sources[0];
  assert.equal(result?.canExecute(), true, result?.validationMessage);
  return result;
}
function literal(value) { return {kind:'literal',value}; }
async function boundaries() {
  const network = 'https://www.shuyinfm.com';
  const declared = structuredClone(example);
  declared.rules.headers.push(
    {name:'CoOkIe',value:literal('session=source')},
    {name:'AUTHORIZATION',value:literal('Bearer source')},
    {name:'Proxy-Authorization',value:literal('Proxy source')},
    {name:'Host',value:literal('www.shuyinfm.com')});
  declared.rules.content.request.headers=[{name:'Authorization',value:literal('Bearer explicit-stage')}];
  declared.rules.search.request.url=literal('/e/search/index.php');
  const native = sourceOf(declared);
  native.bookSourceUrl='https://stable-source-identity.example/id';
  native.nativeBaseUrl=network;
  await Dispatcher.search(native,'花颜策',1,{});
  let request=calls.at(-1);
  assert.equal(request.url,network+'/e/search/index.php');
  assert.equal(request.headers.cookie,'session=source');
  assert.equal(request.headers.authorization,'Bearer source');
  http.LocalRuleHttpClient.getCookieHeader=(_source,address)=>new URL(address).hostname==='media.example'?'session=target':'';
  const audio=await Dispatcher.content(native,network+'/play/1-245-8.html',{});
  request=calls.at(-1);
  assert.equal(new URL(request.url).hostname,'m.mekui.com');
  assert.equal(request.headers.cookie,undefined);
  assert.equal(request.headers.authorization,'Bearer explicit-stage');
  assert.equal(request.headers['proxy-authorization'],undefined);
  assert.equal(request.headers.host,undefined);
  assert.equal(audio.requestHeaders.cookie,'session=target');
  assert.equal(audio.requestHeaders.authorization,undefined);
  assert.equal(audio.requestHeaders['proxy-authorization'],undefined);
  assert.equal(audio.requestHeaders.host,undefined);
  http.LocalRuleHttpClient.getCookieHeader=()=>'';

  const direct={format:'jianting.source',version:1,source:{id:network,name:'Direct',type:'audio',baseUrl:network},
    rules:{content:{format:'text',fields:[{name:'audioUrl',value:literal('/audio.mp3')}]}}};
  let count=calls.length;
  assert.equal((await Dispatcher.content(sourceOf(direct),network+'/play/one',{})).audioUrl,network+'/audio.mp3');
  assert.equal(calls.length,count,'explicit audio direct links must not download a chapter page');
  for(const invalid of ['error','签名错误','permission denied','{"error":1}','<html>失败</html>','javascript:alert(1)','ftp://example.com/a.mp3','https://example.com/'+ 'x'.repeat(2100)]) {
    for(const converted of [false,true]) {
      const variant=structuredClone(direct);
      variant.rules.content.fields[0].value={kind:'literal',value:invalid,
        transforms:converted?[{op:'resolveUrl'}]:[]};
      await assert.rejects(()=>Dispatcher.content(sourceOf(variant),network+'/chapter/1',{}),/地址|URL|链接|HTTP|路径/);
    }
  }

  const text={format:'jianting.source',version:1,source:{id:network,name:'Text',type:'text',baseUrl:network},
    rules:{content:{format:'text',fields:[{name:'content',value:{kind:'variable',value:'response'}}]}}};
  http.LocalRuleHttpClient.fetchNativePlan=async(_source,plan)=>{
    calls.push(JSON.parse(JSON.stringify(plan)));
    return {ok:true,statusCode:200,requestUrl:plan.url,body:'真实章节正文',headers:{}};
  };
  count=calls.length;
  assert.equal((await Dispatcher.content(sourceOf(text),network+'/chapter/1',{})).content,'真实章节正文');
  assert.equal(calls.length,count+1,'text without request.url still fetches the chapter');
  assert.equal(calls.at(-1).method,'GET');

  const paged=structuredClone(text);
  paged.rules.content={format:'json',maxPages:2,fields:[{name:'content',value:{kind:'json',value:'$.content'}}],
    next:{kind:'json',value:'$.next'}};
  http.LocalRuleHttpClient.fetchNativePlan=async(_source,plan)=>{
    calls.push(JSON.parse(JSON.stringify(plan)));
    const second=new URL(plan.url).pathname==='/page2';
    return {ok:true,statusCode:200,requestUrl:plan.url,body:JSON.stringify({content:second?'第二页':'第一页',next:second?'':'/page2'}),headers:{}};
  };
  assert.equal((await Dispatcher.content(sourceOf(paged),network+'/page1',{})).content,'第一页\n第二页');
  assert.equal(calls.at(-1).url,network+'/page2');
  paged.rules.content.maxPages=1;
  await assert.rejects(()=>Dispatcher.content(sourceOf(paged),network+'/page1',{}),/maxPages/);
  assert.equal(bridgeCalls,0);
  console.log('PASS native boundaries: network identity, scoped credentials, explicit stage headers, strict audio URLs, text fetch and pagination');
}
boundaries().catch(error=>{console.error(error);process.exitCode=1;});
`;
vm.runInThisContext(`(function(require,__dirname){${loader}\n${checks}\n})`, { filename:fixture })(require,__dirname);
