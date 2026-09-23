// Actual ArkTS action + bounded facade contract; Node VM substitutes for device QuickJS.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to a Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const prefix = 'service/rulesource/';
const modules = new Map();
let quickJsCalls = 0;
let forcedFailure = false;
const stubs = {
  '@kit.ArkTS': { buffer: { from: Buffer.from } },
  '@kit.CryptoArchitectureKit': { cryptoFramework: {} },
  '@kit.LocalizationKit': {},
  [prefix + 'LocalRuleQuickJsRuntime']: {
    LocalRuleQuickJsRequest: class {},
    LocalRuleQuickJsRuntime: { execute: async request => {
      quickJsCalls++;
      assert.equal(request.maxPendingJobs, 0);
      assert.ok(request.timeoutMs <= 5000);
      if (forcedFailure) return { success: false, errorMessage: 'QuickJS execution timed out' };
      try {
        return { success: true, value: vm.runInNewContext(request.script, {}, { timeout: request.timeoutMs }) };
      } catch (error) { return { success: false, errorMessage: error.message }; }
    } }
  }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name).exports;
  // Unused networking/browser/platform modules must remain inaccessible to the cipher action.
  if (![prefix + 'LocalRuleScriptActions', prefix + 'LocalRuleChaCha20Poly1305',
    prefix + 'LocalRuleRuntimeTypes'].includes(name)) return {};
  const filename = path.join(root, name + '.ets');
  const module = { exports: {} };
  modules.set(name, module);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports,
    require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
const { LocalRuleScriptActions: actions } = load(prefix + 'LocalRuleScriptActions');
const defaults = { operation: 'cipher', algorithm: 'ChaCha20-Poly1305',
  key: '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f',
  iv: '070000004041424344454647', aad: '50515253c0c1c2c3c4c5c6c7', tagLength: 128 };
async function action(args) {
  return JSON.parse(await actions.execute(actions.PREFIX + JSON.stringify({ ...defaults, ...args }), {}, {}, ''));
}
async function value(args) {
  const response = await action(args);
  assert.equal(response.error, undefined, response.error);
  return response.value;
}
function flip(hex, index = 0) {
  const data = Buffer.from(hex, 'hex'); data[index] ^= 1; return data.toString('hex');
}
async function run() {
  // RFC 8439 section 2.8.2, independent plaintext/ciphertext/tag/AAD vector.
  const plain = Buffer.from('Ladies and Gentlemen of the class of \'99: If I could offer you only one tip for the future, sunscreen would be it.').toString('hex');
  const encrypted = 'd31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6' +
    '3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36' +
    '92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3' +
    'ff4def08e4b7a9de576d26586cec64b6116' + '1ae10b594f09e26a7e902ecbd0600691';
  assert.equal(await value({ data: plain, encrypt: true }), encrypted);
  assert.equal(await value({ data: encrypted }), plain);
  for (const args of [{ data: flip(encrypted) }, { data: flip(encrypted, encrypted.length / 2 - 1) },
    { data: encrypted, aad: flip(defaults.aad) }, { data: encrypted, iv: flip(defaults.iv) },
    { data: encrypted, key: flip(defaults.key) }]) {
    const response = await action(args);
    assert.match(response.error, /authentication failed/);
    assert.equal(response.value, undefined, 'No plaintext can escape on authentication failure');
  }
  // Independent OpenSSL oracle exercises padding, empty input, and full ChaCha block boundaries.
  for (const size of [0, 1, 15, 16, 17, 63, 64, 65, 257, 65537]) {
    const key = crypto.randomBytes(32), iv = crypto.randomBytes(12);
    const data = crypto.randomBytes(size), aad = crypto.randomBytes(size % 19);
    const cipher = crypto.createCipheriv('chacha20-poly1305', key, iv, { authTagLength: 16 });
    cipher.setAAD(aad);
    const expected = Buffer.concat([cipher.update(data), cipher.final(), cipher.getAuthTag()]).toString('hex');
    const params = { key: key.toString('hex'), iv: iv.toString('hex'), aad: aad.toString('hex') };
    assert.equal(await value({ ...params, data: data.toString('hex'), encrypt: true }), expected);
    assert.equal(await value({ ...params, data: expected }), data.toString('hex'));
  }
  const beforeInvalid = quickJsCalls;
  for (const args of [{ key: '00' }, { iv: '00' }, { key: 'z'.repeat(64) }, { data: '0' },
    { tagLength: 96 }, { tagLength: 'not-a-number' }, { data: '00'.repeat(15) },
    { data: '00'.repeat(1024 * 1024 + 17) }, { data: '00'.repeat(1024 * 1024 + 1), encrypt: true },
    { aad: '00'.repeat(1024 * 1024 + 1) }]) {
    const response = await action({ data: encrypted, ...args });
    assert.ok(response.error);
    assert.equal(response.value, undefined);
  }
  assert.equal(quickJsCalls, beforeInvalid, 'Invalid inputs fail before scheduling QuickJS');
  forcedFailure = true;
  const timedOut = await action({ data: encrypted });
  assert.match(timedOut.error, /timed out/);
  assert.equal(timedOut.value, undefined);
  console.log('PASS: actual cipher action, RFC 8439 AEAD vector, OpenSSL boundary oracle, tamper rejection, input budgets and bounded runtime failure');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
