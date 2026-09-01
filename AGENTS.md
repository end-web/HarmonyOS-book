# Repository Guidelines

## Build & Run Flow

Agents should use the provided tools, not raw `hvigorw`:

1. **`arkts_check`** on changed `.ets` files — catches ArkTS strict-mode violations faster than full build
2. **`build_project`** — incremental build by default; only pass `clean=true` if cache corruption is suspected
3. **`start_app`** — launch on device/emulator; requires prior successful build

If `arkts_check` or `build_project` fails with ArkTS errors, load the `arkts-error-fixes` skill before retrying.

Raw commands (if tools unavailable):
- `ohpm install` — install HarmonyOS deps from `oh-package.json5`
- `hvigorw assembleHap --mode module -p product=default` — debug HAP
- `hvigorw assembleHap --mode module -p product=release` — release HAP
- `hvigorw clean` — remove build artifacts

## ArkTS Strict-Mode Constraints

ArkTS is **not** TypeScript. These rules trip up agents most often:

- **No `any` or `unknown`** — use explicit types
- **No `as` type assertions** — use explicit class constructors or conversion methods
- **No structural typing** — use explicit `class extends` / `implements`
- **No dynamic property access** (`obj[dynamicKey]`) — use typed accessors
- **Object literals must have explicit type context** — assign to typed variable or pass as typed parameter
- **Use `class` not `interface` for data carriers** — ArkTS requires instantiable types; see `IBuiltInSource.ets` for the pattern
- Load the `arkts-grammar-standards` skill before writing your first `.ets` file

## ArkUI V2 Only

Never mix V1 and V2 decorators:

- **Use**: `@ComponentV2`, `@Local`, `@Param`, `@Event`, `@ObservedV2`, `@Trace`
- **Never use**: `@Component`, `@State`, `@Prop`, `@Link`, `@Provide`, `@Consume`, `@Watch`, `@ObjectLink`

Pages hold `@Local` state + Service singletons. No V1 viewmodel layer exists.

## Critical Coding Rules

- **Loading indicators**: always set `.color(AppColor.Brand)` — never rely on HarmonyOS default brand blue
- **Long lists**: `LazyForEach` + stable keys (e.g. `bookUrl`). Never use index as key
- **UI copy**: change resource strings only; do not rename `.ets` files to match label text
- **New stable native sources**: implement `IBuiltInSource` → register in `registerBuiltInSources()` (in `service/builtin/index.ets`)
- **User rule sources**: extend only `service/rulesource/`; never reintroduce the old `service/js` / `service/rule` engine or bypass the bounded QuickJS facade

## Content Architecture (read this first)

The App keeps registered built-in sources as the primary path and adds user-imported Legado/Reader sources through an isolated local-rule side path:

| Source kind | ID / storage | How it works |
|---|---|---|
| Built-in | `huan_fm` | App uses its built-in encrypted protocol to access the content service directly |
| Existing text | `KkBiqugeTextSource` | Independent search task that reuses the existing detail and ReaderKit path |
| Local rules | encrypted `rule_sources.db` | Imported from My → Sources; supports declarative extraction, compact rule groups and a bounded QuickJS compatibility subset |

Search is multi-source parallel; built-ins and the existing text source start immediately, while local rules run in batches of six. Results are deduplicated by `sourceUrl + bookUrl`. `BookSourceService` checks `BuiltInSourceRegistry` first, so local database/runtime failures must not change built-in detail, chapter, playback, download, or favorite behavior. Home recommendations, categories, and discovery remain built-in only.

Local rule scripts must run through `LocalRuleScriptRuntime` → `LocalRuleQuickJsRuntime` in a taskpool, with independent contexts, native interrupt timeout, heap/stack/pending-job/input/output budgets, and guaranteed release. Do not expose unrestricted QuickJS APIs, direct `fetch`/XHR/WebSocket, platform objects, files, or databases. Hidden ArkWeb remains only the CSS/XPath DOM parser host for already-downloaded HTML. The routed source login page is the sole remote ArkWeb exception: HTTPS only, incognito mode, no platform bridge, and cookies must be copied into the encrypted source+origin store before the Web session is cleared.

The optional `server/` project is not registered or configurable as an App content source. Do not reintroduce an App API-base setting without an explicit product decision.

## Project Structure

Single HarmonyOS module (`entry/`) + optional Node server (`server/`):

- `entry/src/main/ets/pages/` — routed screens
- `entry/src/main/ets/service/` — business services (singular `service/`, not `services/`)
- `entry/src/main/ets/service/builtin/` — built-in audio source system (registry, dispatcher, source implementations)
- `entry/src/main/ets/service/rulesource/` — local rule import, persistence, HTTP, extraction, QuickJS compatibility and dispatch
- `entry/libs/quickjs.har` — locally built arm64-v8a/x86_64 bounded QuickJS dependency
- `entry/src/main/ets/model/` — domain types (`Book`, `BookSource`, `LocalRuleSource`, `PlayerState`)
- `entry/src/main/ets/components/` — reusable widgets
- `entry/src/main/ets/theme/` — theme tokens (`AppColor`, `AppMaterial`)
- `entry/src/main/ets/widget/` — desktop form widget
- `server/` — JianHu cloud API + Vue admin + Docker deploy
- `third_party/quickjs/` / `scripts/build-quickjs.ps1` — QuickJS source, licenses and reproducible HAR build

Generated dirs (never edit, never commit): `build/`, `.hvigor/`, `oh_modules/`, `server/node_modules/`, `server/dist/`, `third_party/quickjs/.hvigor/`, `third_party/quickjs/oh_modules/`, `third_party/quickjs/quickjs/.cxx/`, `third_party/quickjs/quickjs/build/`, `third_party/quickjs/quickjs/oh_modules/`

## Testing

- **App unit tests**: `entry/src/test/*.test.ets` (Hypium framework) — covers `DownloadPolicy`, `TingYouRequestPolicy`, `BuiltInAudioCapability`, `AsyncSingleFlight`
- **App device tests**: `entry/src/ohosTest/ets/test/*.test.ets`
- **Server tests**: `cd server && npm test` (Vitest) — 7 test files covering catalog, providers, auth, DB, sync
- After changing playback/builtin sources/download: smoke-test search → detail → chapter → play on device
- After changing local rule import/runtime/dispatch: verify no-local-source built-in behavior, then import → test → search → detail → read/play; disabled sources must leave existing favorites resolvable and one failed rule must not stop other sources
- After changing Home/Record UI: verify skeleton loading, pull-to-refresh, double-tap-to-top, edit/long-press selection

## Security & Config

- **`build-profile.json5` contains signing secrets** (key passwords, cert paths) — never commit changes to this file; signing is machine-specific and configured via DevEco Studio
- `code-linter.json5` enforces crypto security rules (no unsafe AES/RSA/DSA/DH/3DES) on all `.ets` files
- The App has no configurable cloud API base; `server/` remains an optional independent project and must not become an implicit runtime dependency
- QuickJS business code may call only `LocalRuleQuickJsRuntime.execute()`; that facade invokes native `evaluateBounded`. Keep the upstream license files and `THIRD_PARTY_NOTICES.md` when updating `entry/libs/quickjs.har`
- Server's Reader/Legado engine must stay internal to Docker; never expose `/reader3` to the public internet

## Reference Documents

- **`CLAUDE.md`** — product/architecture source of truth (content model, services, page flow, SDK baseline)
- **`docs/APP_UI.md`** — current UI interaction baseline and regression checklist
- **`server/README.md`** — server deployment and operations guide

## Language

- **回复语言**: 始终使用中文回复用户

## Conventions

- **Commits**: Conventional Commits (`feat:`, `fix:`, `fix(player):`, `feat(server):` …); Chinese or English summaries OK
- **Git 推送**: GitHub 远端使用 SSH 地址 `git@github.com:end-web/HarmonyOS-book.git`，优先使用本机 `C:\Users\ylwang112\.ssh\id_ed25519` 密钥推送；不要切回 HTTPS 推送。
- **Naming**: `XxxPage`, `XxxService`, `XxxComponent` (PascalCase + suffix); camelCase for fields/methods
- **SDK**: HarmonyOS 7 / API 26; `targetSdkVersion = compatibleSdkVersion = 26.0.0`; `bundleName: com.huan.listenbook`
- **Device types**: phone only (`deviceTypes: ["phone"]`)
