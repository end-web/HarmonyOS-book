// Real ArkTS policy/service with simulated IAP; real Node ES256 checks for the JWS signature adapter.
// Native HarmonyOS PKIX validation and real purchases require device/sandbox verification.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
let now = Date.now();
class Clock extends Date { constructor(...args) { super(...(args.length ? args : [now])); } static now() { return now; } }
const util = {
  Base64Helper: class { decodeSync(s) { return new Uint8Array(Buffer.from(s, 'base64')); } },
  TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder('utf-8', { fatal: true }).decode(bytes) }) },
  TextEncoder: class { encodeInto(s) { return new Uint8Array(Buffer.from(s)); } }
};
function load(relative, overrides = {}, globals = {}) {
  const exports = {};
  const source = fs.readFileSync(path.join(root, relative), 'utf8')
    .replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(js, {
    exports, require: name => { if (name in overrides) return overrides[name]; throw new Error('Unexpected import: ' + name); },
    $r: name => name, Date: Clock, Uint8Array, Set, Map, console, canIUse: () => true,
    setTimeout: (fn, delay) => { if (delay <= 5100) { now += delay; queueMicrotask(fn); } return 1; },
    clearTimeout() {}, ...globals
  }, { filename: relative });
  return exports;
}
const data = load('service/membership/SubscriptionData.ets');
const lifetimeData = load('service/membership/LifetimeData.ets', { './SubscriptionData': data });
const { SubscriptionPolicy: policy } = data;
const clone = value => JSON.parse(JSON.stringify(value));
function lifetime(changes = {}) {
  return { applicationId: '6917615941058168740', environment: 'NORMAL', productId: 'lastVip',
    productType: '1', purchaseToken: 'life-token', purchaseOrderId: 'life-order', finishStatus: '2',
    purchaseTime: now - 50000, signedTime: now - 1000, price: 19800, currency: 'CNY', ...changes };
}
function payload(changes = {}) {
  return {
    environment: 'NORMAL', applicationId: 'app-1', packageName: 'com.huan.listenbook', subGroupId: 'icons',
    lastSubscriptionStatus: {
      status: '1', expiresTime: now + 86400000, renewalInfo: { autoRenewStatusCode: '1' },
      lastPurchaseOrder: { environment: 'NORMAL', applicationId: 'app-1', productId: 'iconMonth', productType: '2',
        purchaseToken: 'token-1', purchaseOrderId: 'order-1', finishStatus: '2', purchaseTime: now - 1000 }
    }, ...changes
  };
}
let count = 0;
async function test(name, fn) { await fn(); count++; console.log('PASS', name); }

async function main() {
  await test('Known IDs, expiry, cancellation, refund and sandbox separation', () => {
    const p = payload();
    assert.equal(policy.active(policy.validate(p, false, now), now), true);
    p.lastSubscriptionStatus.renewalInfo.autoRenewStatusCode = '0';
    assert.equal(policy.active(policy.validate(p, false, now), now), true);
    for (const status of ['2', '3', '5']) {
      p.lastSubscriptionStatus.status = status;
      assert.equal(policy.active(policy.validate(p, false, now), now), false);
    }
    p.lastSubscriptionStatus.status = '1'; p.lastSubscriptionStatus.expiresTime = now;
    assert.equal(policy.active(policy.validate(p, false, now), now), false);
    const sandbox = payload({ environment: 'SANDBOX' });
    sandbox.lastSubscriptionStatus.lastPurchaseOrder.environment = 'SANDBOX';
    assert.throws(() => policy.validate(sandbox, false, now));
    assert.ok(policy.validate(sandbox, true, now));
    for (const id of ['iconMonths', 'iconYears', 'other']) assert.equal(policy.knownProduct(id), false);
  });
  await test('Reject cross-app, malformed and inconsistent orders', () => {
    for (const mutation of [
      p => p.packageName = 'another.app', p => p.applicationId = '',
      p => p.lastSubscriptionStatus.expiresTime = '9999999999999',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.applicationId = 'another-app',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.productType = '0',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.purchaseToken = '',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.purchaseTime = now + 120000,
      p => p.lastSubscriptionStatus.status = 'unexpected'
    ]) { const p = payload(); mutation(p); assert.throws(() => policy.validate(p, false, now)); }
  });

  const keys = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  let badChain = false, badOid = false, anchorChecked = false;
  const rootCert = { root: true };
  const leafCert = { getPublicKey: () => keys.publicKey,
    getExtensionsObject: () => ({ getOidList: () => ({ data: [Buffer.from(badOid ? '1.2.3' : '1.3.6.1.4.1.2011.2.415.1.1\0')] }) }) };
  const cert = {
    EncodingFormat: { FORMAT_DER: 0 }, ExtensionOidType: { EXTENSION_OID_TYPE_UNCRITICAL: 2 },
    createX509Cert: async blob => blob.data.length > 100 ? rootCert : leafCert,
    createX509CertChain: certs => ({ validate: async options => {
      assert.equal(certs.length, 2); assert.equal(options.trustAnchors[0].CACert, rootCert);
      assert.equal(options.trustSystemCa, false); assert.match(options.date, /^\d{14}Z$/);
      anchorChecked = true; if (badChain) throw new Error('Untrusted chain');
    } })
  };
  const cryptoFramework = { createVerify: algorithm => {
    assert.equal(algorithm, 'ECC256|SHA256'); let key;
    return { init: async k => { key = k; }, verify: async (input, signature) => crypto.verify('sha256', input.data, key, signature.data) };
  } };
  const { SubscriptionVerifier: verifier } = load('service/membership/SubscriptionVerifier.ets', {
    '@kit.ArkTS': { util }, '@kit.DeviceCertificateKit': { cert }, '@kit.CryptoArchitectureKit': { cryptoFramework },
    './SubscriptionData': data
  });
  const context = { applicationInfo: { debug: false }, resourceManager: { getRawFileContent: async name =>
    new Uint8Array(fs.readFileSync(path.join(root, '../resources/rawfile', name))) } };
  function signed(p, h = {}) {
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', typ: 'JWT', x5c: ['AQ==', 'Ag==', 'Aw=='], ...h })).toString('base64url');
    const body = Buffer.from(JSON.stringify(p)).toString('base64url');
    const input = header + '.' + body;
    const sig = crypto.sign('sha256', Buffer.from(input), { key: keys.privateKey, dsaEncoding: 'ieee-p1363' });
    return JSON.stringify({ jwsSubscriptionStatus: input + '.' + sig.toString('base64url') });
  }
  await test('Real ES256 signatures and integer padding convert correctly', async () => {
    for (let i = 0; i < 32; i++) assert.equal((await verifier.verify(context, signed(payload()))).packageName, 'com.huan.listenbook');
    assert.ok(anchorChecked);
    assert.throws(() => verifier.signatureDer(new Uint8Array(63)));
  });
  await test('Reject altered JWS, algorithm confusion, untrusted chain and missing IAP OID', async () => {
    const envelope = JSON.parse(signed(payload()));
    const parts = envelope.jwsSubscriptionStatus.split('.');
    parts[1] = Buffer.from(JSON.stringify(payload({ applicationId: 'tampered' }))).toString('base64url');
    await assert.rejects(verifier.verify(context, JSON.stringify({ jwsSubscriptionStatus: parts.join('.') })));
    await assert.rejects(verifier.verify(context, signed(payload(), { alg: 'none' })));
    await assert.rejects(verifier.verify(context, signed(payload(), { crit: ['unrecognized'] })));
    badChain = true; await assert.rejects(verifier.verify(context, signed(payload()))); badChain = false;
    badOid = true; await assert.rejects(verifier.verify(context, signed(payload()))); badOid = false;
  });

  function session(developerEnabled = false) {
    const developer = load('service/membership/DeveloperMembership.ets');
    developer.DeveloperMembership.ENABLED = developerEnabled;
    let defaultsReset = 0;
    const stateModule = load('model/MembershipState.ets');
    const current = [], unfinished = [], finishes = [], icons = [];
    const lifetimeCurrent = [], lifetimeUnfinished = [], purchases = [];
    let queryError = null, finishError = null, purchaseError = null, purchaseCount = 0;
    const iap = {
      ProductType: { AUTORENEWABLE: 2, NONCONSUMABLE: 1 }, ProductStatus: { VALID: 0 }, PeriodUnit: { MONTH: 2, YEAR: 3, MINUTE: 4 },
      PurchaseQueryType: { CURRENT_ENTITLEMENT: 2, UNFINISHED: 1 }, WindowScreenMode: { FULLSCREEN: 2 },
      IAPErrorCode: { USER_CANCELED: 1001860000, PURCHASE_FINISHED: 1001860053 },
      isSandboxActivated: async () => false, queryEnvironmentStatus: async () => {},
      queryPurchases: async (_, req) => {
        if (queryError) throw queryError;
        if (req.productType === 1) return { purchaseDataList: (req.queryType === 2 ? lifetimeCurrent : lifetimeUnfinished).map(JSON.stringify) };
        return { purchaseDataList: (req.queryType === 2 ? current : unfinished).map(JSON.stringify) };
      },
      finishPurchase: async (_, order) => { finishes.push(order); if (finishError) throw finishError; },
      createPurchase: async (_, req) => {
        purchaseCount++; purchases.push(req); if (purchaseError) throw purchaseError;
        if (req.productId === 'lastVip') {
          const order = lifetime(); lifetimeCurrent.push(order); return { purchaseData: JSON.stringify(order) };
        }
        return { purchaseData: '{}' };
      },
      showManagedSubscriptions: async () => {},
      queryProducts: async (_, req) => req.productType === 1 ? [{ id: 'lastVip', type: 1, localPrice: '¥198.00', price: '¥198.00' }] :
        ['iconMonth', 'iconYear'].map(id => ({ id, type: 2, price: '¥10.00',
          subscriptionInfo: { periodUnit: id === 'iconMonth' ? 2 : 3, periodCount: 1, groupId: 'icons' } }))
    };
    const { MembershipService } = load('service/MembershipService.ets', {
      './PreferenceService': { PreferenceService: { setSearchConcurrency: async count => { assert.equal(count, 3); } } },
      './membership/DeveloperMembership': developer,
      './AutoBackupService': { AutoBackupService: { instance: { resetMembershipDefaults: async () => { defaultsReset++; } } } },
      '@kit.IAPKit': { iap }, '../model/MembershipState': stateModule,
      '@kit.PerformanceAnalysisKit': { hilog: { warn() {} } },
      '../utils/PlatformCompat': { PlatformCompat: { wearable: false } },
      './AppIconService': { AppIconService: { instance: { supported: true, select: async name => icons.push(name) } } },
      './membership/SubscriptionData': data,
      './membership/LifetimeData': lifetimeData,
      './membership/SubscriptionVerifier': { SubscriptionVerifier: {
        verify: async (_, p) => JSON.parse(p), verifyLifetime: async (_, p) => JSON.parse(p)
      } }
    });
    return { defaultsReset: () => defaultsReset, service: MembershipService.instance, state: stateModule.MembershipState.current,
      current, unfinished, finishes, icons, lifetimeCurrent, lifetimeUnfinished, purchases, setQueryError: e => { queryError = e; },
      setFinishError: e => { finishError = e; }, setPurchaseError: e => { purchaseError = e; }, purchaseCount: () => purchaseCount };
  }
  await test('Restore grants once, finishes only after entitlement, and retries acknowledgement', async () => {
    const s = session(); s.current.push(payload()); s.unfinished.push(clone(s.current[0]));
    s.setFinishError({ code: 1001860005 });
    await s.service.refresh(context, true);
    assert.equal(s.state.active, true); assert.equal(s.service.confirmationPending, true);
    const expiry = s.state.expiresAt;
    s.setFinishError(null); s.finishes.length = 0;
    await s.service.refresh(context, true);
    assert.equal(s.state.expiresAt, expiry); assert.equal(s.service.confirmationPending, false);
    assert.equal(s.finishes.length, 1);
    s.current[0].lastSubscriptionStatus.lastPurchaseOrder.finishStatus = '1'; s.unfinished.length = 0; s.finishes.length = 0;
    await s.service.refresh(context, true); assert.equal(s.finishes.length, 0);
  });
  await test('Empty/refunded authoritative query revokes; stale unfinished order cannot resurrect', async () => {
    const s = session(); s.unfinished.push(payload());
    await s.service.refresh(context, true);
    assert.equal(s.state.active, false); assert.equal(s.finishes.length, 0); assert.equal(s.icons.at(-1), '');
    s.current.push(payload()); await s.service.refresh(context, true); assert.equal(s.state.active, true);
    s.current[0].lastSubscriptionStatus.status = '5'; await s.service.refresh(context, true);
    assert.equal(s.state.active, false);
  });
  await test('Offline resets restricted settings and blocks unverified purchase', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context);
    assert.equal(s.state.active, true); const resets = s.icons.length;
    s.setQueryError({ code: 1001860005 }); await s.service.refresh(context, true);
    assert.equal(s.state.active, false); assert.equal(s.icons.length, resets + 1);
    await s.service.purchase(context, 'iconMonth'); assert.equal(s.purchaseCount(), 0);
  });
  await test('Cancellation does not grant or confirm a purchase', async () => {
    const s = session(); await s.service.load(context); s.setPurchaseError({ code: 1001860000 });
    await s.service.purchase(context, 'iconYear');
    assert.equal(s.purchaseCount(), 1); assert.equal(s.state.active, false); assert.equal(s.finishes.length, 0);
    assert.equal(s.service.message, 'app.string.membership_cancelled');
  });
  await test('Lifetime policy rejects wrong app/type, future, sandbox and revoked orders', () => {
    const p = lifetimeData.LifetimePolicy;
    assert.ok(p.validate(lifetime(), false, now));
    for (const patch of [{ applicationId: 'other' }, { productType: '2' }, { purchaseToken: '' },
      { purchaseTime: now + 120000 }, { signedTime: 0 }, { price: -1 }, { currency: '' }, { environment: 'SANDBOX' }]) {
      assert.throws(() => p.validate(lifetime(patch), false, now));
    }
    assert.equal(p.validate(lifetime({ purchaseOrderRevocationReasonCode: '0' }), false, now), undefined);
    assert.equal(p.validate(lifetime({ revocationTime: now }), false, now), undefined);
    assert.equal(p.validate(lifetime({ productId: 'other' }), false, now), undefined);
  });
  await test('Lifetime JWS uses the same real signature verification and rejects tampering', async () => {
    const jws = JSON.parse(signed(lifetime())).jwsSubscriptionStatus;
    const order = await verifier.verifyLifetime(context, JSON.stringify({ jwsPurchaseOrder: jws }));
    assert.equal(order.productId, 'lastVip');
    const parts = jws.split('.');
    parts[1] = Buffer.from(JSON.stringify(lifetime({ applicationId: 'tampered' }))).toString('base64url');
    await assert.rejects(verifier.verifyLifetime(context, JSON.stringify({ jwsPurchaseOrder: parts.join('.') })));
    await assert.rejects(verifier.verifyLifetime(context, signed(lifetime())));
  });
  await test('Lifetime restores, outranks subscription, acknowledges once and cannot resurrect from unfinished history', async () => {
    const s = session(); s.current.push(payload()); s.lifetimeCurrent.push(lifetime());
    s.lifetimeUnfinished.push(clone(s.lifetimeCurrent[0]));
    s.setFinishError({ code: 1001860005 });
    await s.service.refresh(context, true);
    assert.equal(s.state.active, true); assert.equal(s.state.lifetime, true); assert.equal(s.state.expiresAt, 0);
    assert.equal(s.service.confirmationPending, true);
    assert.equal(s.state.nameColor, 'app.color.membership_name_lifetime');
    s.setFinishError(null); s.finishes.length = 0;
    await s.service.refresh(context, true);
    assert.equal(s.finishes.filter(v => v.productType === 1).length, 1);
    s.lifetimeCurrent.length = 0;
    await s.service.refresh(context, true);
    assert.equal(s.state.lifetime, false); assert.equal(s.state.active, true);
    s.current.length = 0; await s.service.refresh(context, true);
    assert.equal(s.state.active, false); assert.equal(s.state.nameColor, 'sys.color.font_primary');
  });
  await test('Monthly member can buy lifetime once; purchases and acknowledgements use NONCONSUMABLE', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context);
    assert.equal(s.service.plans.length, 3);
    assert.equal(s.state.nameColor, 'app.color.membership_name_month');
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchases[0].productType, 1); assert.equal(s.state.lifetime, true);
    assert.equal(await s.service.hasCurrentEntitlement(), true);
    await s.service.purchase(context, 'lastVip'); await s.service.purchase(context, 'iconYear');
    assert.equal(s.purchaseCount(), 1);
    s.lifetimeCurrent[0].purchaseOrderRevocationReasonCode = '0';
    await s.service.refresh(context, true);
    assert.equal(s.state.lifetime, false);
  });
  await test('Lifetime purchase cancellation grants nothing; yearly name color follows verified state', async () => {
    const s = session(); await s.service.load(context); s.setPurchaseError({ code: 1001860000 });
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchaseCount(), 1); assert.equal(s.state.active, false); assert.equal(s.finishes.length, 0);
    const p = payload(); p.lastSubscriptionStatus.lastPurchaseOrder.productId = 'iconYear'; s.current.push(p);
    await s.service.refresh(context, true);
    assert.equal(s.state.nameColor, 'app.color.membership_name_year');
    s.setQueryError({ code: 1001860005 }); await s.service.refresh(context, true);
    assert.equal(s.state.nameColor, 'sys.color.font_primary');
  });
  await test('Missing or unavailable membership resets defaults', async () => {
    const s = session();
    await s.service.refresh(context, true);
    assert.equal(s.state.confirmedInactive, true);
    assert.equal(s.defaultsReset(), 1);
    assert.equal(s.icons.at(-1), '');
    s.setQueryError({ code: 1001860005 });
    await s.service.refresh(context, true);
    assert.equal(s.state.confirmedInactive, true);
    assert.equal(s.defaultsReset(), 2);
  });
  await test('Developer exemption requires explicit opt-in AND a debug application', async () => {
    const production = session(true);
    await production.service.refresh(context, true);
    assert.equal(production.state.hasAccess, false);
    assert.equal(production.state.developerAccess, false);
    const debugContext = { ...context, applicationInfo: { debug: true } };
    const regularDebug = session(false);
    await regularDebug.service.refresh(debugContext, true);
    assert.equal(regularDebug.state.hasAccess, false);
    const developer = session(true);
    await developer.service.refresh(debugContext, true);
    assert.equal(await developer.service.hasCurrentEntitlement(), true);
    assert.equal(developer.state.active, false, 'do not fabricate purchased membership');
    assert.equal(developer.defaultsReset(), 0);
    assert.equal(developer.icons.length, 0);
  });
  console.log(`${count} membership regression groups passed`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
