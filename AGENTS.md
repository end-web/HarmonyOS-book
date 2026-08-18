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
- **New audio sources**: implement `IBuiltInSource` interface → register in `registerBuiltInSources()` (in `service/builtin/index.ets`). Rule-heavy sources go in `server/`, not the App
- **No client-side rule engine**: Legado/Reader rules run only in `server/`; do not reintroduce `service/js` or `service/rule`

## Content Architecture (read this first)

The App **no longer loads user Legado rule sources**. Online content comes only from registered built-in source IDs:

| Source ID | Name | How it works |
|---|---|---|
| `huan_fm` | 欢FM | App uses its built-in encrypted protocol to access the content service directly |
| `jianhu_server` | JianHu Cloud | HTTP to `ServerAudioConfig.apiBase`, supplied by deployment or user settings |

Search is multi-source parallel; results are deduplicated by `sourceUrl + bookUrl`. Cloud source only routes — search result `sourceName` reflects the actual upstream audio source, not "JianHu Cloud".

Third-party closed backends (other "听书" APK plugin hosts) are **not** compatible with this API shape — do not suggest substituting their URLs into `ServerAudioConfig`.

## Project Structure

Single HarmonyOS module (`entry/`) + optional Node server (`server/`):

- `entry/src/main/ets/pages/` — routed screens
- `entry/src/main/ets/service/` — business services (singular `service/`, not `services/`)
- `entry/src/main/ets/service/builtin/` — built-in audio source system (registry, dispatcher, source implementations)
- `entry/src/main/ets/model/` — domain types (`Book`, `BookSource`, `PlayerState`)
- `entry/src/main/ets/components/` — reusable widgets
- `entry/src/main/ets/theme/` — theme tokens (`AppColor`, `AppMaterial`)
- `entry/src/main/ets/widget/` — desktop form widget
- `server/` — JianHu cloud API + Vue admin + Docker deploy

Generated dirs (never edit, never commit): `build/`, `.hvigor/`, `oh_modules/`, `server/node_modules/`, `server/dist/`

## Testing

- **App unit tests**: `entry/src/test/*.test.ets` (Hypium framework) — covers `DownloadPolicy`, `TingYouRequestPolicy`, `BuiltInAudioCapability`, `AsyncSingleFlight`
- **App device tests**: `entry/src/ohosTest/ets/test/*.test.ets`
- **Server tests**: `cd server && npm test` (Vitest) — 7 test files covering catalog, providers, auth, DB, sync
- After changing playback/builtin sources/download/cloud config: smoke-test search → detail → chapter → play on device
- After changing Home/Record UI: verify skeleton loading, pull-to-refresh, double-tap-to-top, edit/long-press selection

## Security & Config

- **`build-profile.json5` contains signing secrets** (key passwords, cert paths) — never commit changes to this file; signing is machine-specific and configured via DevEco Studio
- `code-linter.json5` enforces crypto security rules (no unsafe AES/RSA/DSA/DH/3DES) on all `.ets` files
- Cloud API base is managed by `ServerAudioConfig` and may be supplied by deployment or `PreferenceService`; do not publish concrete service addresses in documentation
- Server's Reader/Legado engine must stay internal to Docker; never expose `/reader3` to the public internet

## Reference Documents

- **`CLAUDE.md`** — product/architecture source of truth (content model, services, page flow, SDK baseline)
- **`docs/APP_UI.md`** — current UI interaction baseline and regression checklist
- **`server/README.md`** — server deployment and operations guide

## Language

- **回复语言**: 始终使用中文回复用户

## Conventions

- **Commits**: Conventional Commits (`feat:`, `fix:`, `fix(player):`, `feat(server):` …); Chinese or English summaries OK
- **Naming**: `XxxPage`, `XxxService`, `XxxComponent` (PascalCase + suffix); camelCase for fields/methods
- **SDK**: HarmonyOS 7 / API 26; `targetSdkVersion = compatibleSdkVersion = 26.0.0`; `bundleName: com.huan.listenbook`
- **Device types**: phone only (`deviceTypes: ["phone"]`)
