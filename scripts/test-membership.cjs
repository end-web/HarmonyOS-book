// Current free-release contract; historical IAP verification tests remain in Git history.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide,'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname,'../entry/src/main/ets');
function load(file,dependencies={}) {
  const exports = {};
  const source = fs.readFileSync(path.join(root,file),'utf8').replace(/import lazy /g,'import ')
    .replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,'');
  const code = ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText;
  vm.runInNewContext(code,{exports,$r:name=>name,Date,Map,Set,console,
    require:name=>dependencies[name] || {}},{filename:file});
  return exports;
}
async function run() {
  const display = load('model/MembershipDisplaySnapshot.ets');
  const {MembershipState} = load('model/MembershipState.ets',{'./MembershipDisplaySnapshot':display});
  const {MembershipService} = load('service/MembershipService.ets');
  const service = MembershipService.instance;
  const state = MembershipState.current;
  assert.equal(state.active,false,'free access does not fabricate a purchase');
  for (const flags of [{},{confirmedInactive:true},{revalidating:true},{verifiedAt:1,expiresAt:2}]) {
    Object.assign(state,flags);
    assert.equal(state.hasAccess,true,'offline, old cache and previous inactivity never restrict free use');
    assert.equal(await service.hasCurrentEntitlement(),true);
  }
  service.foreground({applicationInfo:{debug:false}});
  await service.load({}); await service.refresh({},true,true); service.background();
  assert.equal(service.busy,false);
  assert.equal(service.purchase,undefined,'current service cannot open IAP');
  let icon = '';
  const compat = {supports:()=>true};
  const {AppIconService} = load('service/AppIconService.ets',{
    '@kit.AbilityKit':{bundleManager:{getAlternateIcons:async()=>[{enabled:true,iconName:icon}],
      setAlternateIcon:async name=>{icon=name;}}},
    '../utils/PlatformCompat':{PlatformCompat:compat},'../model/MembershipState':{MembershipState}
  });
  assert.equal(AppIconService.instance.membershipRequired,false);
  for (const option of AppIconService.instance.getOptions()) assert.equal(await AppIconService.instance.select(option.name),option.name);
  compat.supports=()=>false;
  await assert.rejects(AppIconService.instance.select('wave'),/API 26/);
  const {PreferenceService} = load('service/PreferenceService.ets',{
    './MembershipService':{MembershipService},'../model/MembershipState':{MembershipState}
  });
  const values = new Map();
  PreferenceService.ensureStore=async()=>({get:async(key,fallback)=>values.has(key)?values.get(key):fallback,
    put:async(key,value)=>values.set(key,value),flush:async()=>{}});
  for (const count of [1,3,6,12]) {
    await PreferenceService.setSearchConcurrency(count);
    assert.equal(await PreferenceService.getSearchConcurrency(),count);
  }
  await assert.rejects(PreferenceService.setSearchConcurrency(13),/1 to 12/);
  console.log('PASS: free release, no purchased status/IAP, offline access, all icons, API guard and persisted search concurrency');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
