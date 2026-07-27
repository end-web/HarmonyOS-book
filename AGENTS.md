# Repository Guidelines

## Project Structure & Module Organization

ListenBook is a HarmonyOS Next Stage-mode app (ArkTS) plus an optional Node audio aggregation server.

| Path | Role |
|---|---|
| `entry/src/main/ets/pages/` | Routed screens (`MainPage` tabs, player, detail, import, downloads, settings…) |
| `entry/src/main/ets/components/` | Reusable ArkUI widgets (`MiniPlayer`, `BookCard`) |
| `entry/src/main/ets/service/` | Business services (playback, download, prefs, builtin sources) |
| `entry/src/main/ets/service/builtin/` | Built-in audio sources (`TingYouFM`, `ServerAudioSource`, registry/dispatcher) |
| `entry/src/main/ets/model/` | Domain types (`Book`, `BookSource`, `PlayerState`) |
| `entry/src/main/ets/theme/` | Shared theme tokens |
| `entry/src/main/ets/utils/` | Helpers (`SearchCache`, lazy data sources, window utils) |
| `entry/src/main/ets/widget/` | Form widget / desktop player card |
| `entry/src/main/resources/` | App resources |
| `AppScope/` | Global metadata and icons |
| `server/` | JianHu cloud audio API + Vue admin + Docker deploy |
| `entry/src/test/` | Hypium unit tests |
| `entry/src/ohosTest/` | Device/ability tests |
| `docs/` | Design notes and specs |

Treat `build/`, `.hvigor/`, `oh_modules/`, `server/node_modules/`, and `server/dist/` as generated outputs.

**Content model (read this first):** the App no longer loads user Legado rule sources. Online content comes only from registered built-in sources (`builtin://eprendre/<id>`). Cloud/rule execution lives in `server/`; the App consumes stable HTTP APIs via `ServerAudioSource`.

Authoritative product/architecture notes: `CLAUDE.md`. Server ops: `server/README.md`.

## Build, Test, and Development Commands

### App

- `ohpm install` — install HarmonyOS package deps from `oh-package.json5`
- `hvigorw assembleHap --mode module -p product=default` — debug/default HAP
- `hvigorw assembleHap --mode module -p product=release` — release HAP
- `hvigorw clean` — remove build artifacts

If `hvigorw` is missing, use DevEco Studio Build/Clean/Test.

### Server

```bash
cd server
npm install && npm --prefix admin install
npm run typecheck
npm test
npm run admin:build
```

Deploy: see `server/deploy/compose.yml` and `server/README.md`.

## Coding Style & Naming Conventions

- ArkTS, 2-space indent, explicit imports
- ArkUI **V2 only**: `@ComponentV2`, `@Local`, `@Param`, `@Event`, `@ObservedV2`, `@Trace`
- Names: `PlayerPage`, `AudioService`, `ServerAudioSource` (PascalCase + clear suffix); camelCase for fields/methods
- Prefer resource strings for user-facing copy; do not rename `.ets` files just to match label text
- Long lists: `LazyForEach` + stable keys (never index keys)
- New online sources: implement `IBuiltInSource` and register in `registerBuiltInSources()`; rule-heavy sources belong on the server
- Do not reintroduce client-side Legado rule engines under `service/js` or `service/rule` unless explicitly designed

## Testing Guidelines

- App: Hypium in `entry/src/test/*.test.ets` and `entry/src/ohosTest/ets/test/*.test.ets`
- Server: Vitest in `server/test/*.test.ts` (`npm test` under `server/`)
- Name suites/cases by behavior (`it('quarantines unusable audio sources')`)
- Before merging changes to playback, builtin sources, download, cloud API config, or server catalog sync: run relevant unit tests and smoke search → detail → chapter → resolve/play on device or against the API

## Commit & Pull Request Guidelines

Use Conventional Commits (`feat:`, `fix:`, `fix(player):`, `feat(server):` …); Chinese or English summaries are fine.

PRs should include:

1. Purpose
2. Major files / modules touched (App vs `server/`)
3. Verification performed (commands + device/API checks)
4. Screenshots/clips for UI changes
5. Callouts for signing, permissions, cloud API defaults, deploy/env, or external source parsing

## Security & Configuration Tips

- Do not commit personal signing material, admin password hashes intended for production, session secrets, or machine-specific paths
- Cloud API base default is `https://121.196.223.85/api/v1` (`ServerAudioConfig`); user overrides are stored via `PreferenceService`
- Third-party closed backends (e.g. other “听书” APK plugin hosts) are **not** drop-in replacements for this API shape
- Review `build-profile.json5`, network config, and permission resources when changing release builds or external data access
- Reader/Legado engine used by the server must stay internal to Docker; do not expose raw `/reader3` to the public internet
