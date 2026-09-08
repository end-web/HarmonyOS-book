# CryptoJS Legacy Protocol Compatibility

CryptoJS 4.2.0, MIT licensed. Only imported-source DES/TripleDES compatibility uses this library, inside the existing bounded QuickJS context. It does not encrypt application databases, credentials, cookies, or network transport.

The runtime string in `entry/src/main/ets/service/rulesource/LocalRuleLegacyCrypto.ets` consists of these unmodified upstream modules, concatenated in order and minified with Terser (`--compress --mangle --comments false`):

- `core.js`
- `cipher-core.js`
- `tripledes.js`
- `mode-ecb.js`
- `pad-nopadding.js`

Pinned package: https://registry.npmjs.org/crypto-js/-/crypto-js-4.2.0.tgz

Package SHA-512: `KALDyEYgpY+Rlob/iriUtjV6d5Eq+Y191A5g4UqLAi8CyGP9N1+FdVbkc1SxKc2r4YAYqG8JzO2KGL+AizD70Q==`

The wrapper disables module loading, keeps the library private, requires explicit key bytes, validates key/IV/block lengths and padding, and uses the runtime's native interruption, heap, stack, and output budgets. Password-based key derivation and native random providers are not exposed.
