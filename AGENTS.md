# Repository Guidelines

## Project Structure & Module Organization

ListenBook is a HarmonyOS Next Stage-mode app written in ArkTS. Main application code lives under `entry/src/main/ets/`: `pages/` contains routed screens, `components/` reusable ArkUI widgets, `service/` business logic and playback/data services, `model/` typed domain objects, `theme/` shared color/theme constants, and `utils/` helpers. App resources are in `entry/src/main/resources/`; global app metadata and icons are in `AppScope/`. Unit tests are in `entry/src/test/`, device/ability tests in `entry/src/ohosTest/`, and design notes or generated icon previews are under `docs/`. Treat `build/`, `.hvigor/`, and `oh_modules/` as generated outputs.

## Build, Test, and Development Commands

- `ohpm install` installs HarmonyOS package dependencies from `oh-package.json5`.
- `hvigorw assembleHap --mode module -p product=default` builds a debug/default HAP when the Hvigor wrapper is available.
- `hvigorw assembleHap --mode module -p product=release` builds the release product with configured obfuscation.
- `hvigorw clean` removes generated build artifacts.

If `hvigorw` is not present in the checkout, run the equivalent Build/Clean/Test actions from DevEco Studio.

## Coding Style & Naming Conventions

Use ArkTS with 2-space indentation and keep imports explicit. Follow ArkUI V2 state patterns already used in the app: `@ComponentV2`, `@Local`, `@Param`, `@ObservedV2`, and `@Trace`. Name pages, components, services, models, and utilities in PascalCase with clear suffixes such as `PlayerPage`, `AudioService`, or `UrlUtils`; use camelCase for variables, methods, and state fields. Keep user-facing text in resource files instead of hard-coding strings. For lists, prefer `LazyForEach` and stable keys.

## Testing Guidelines

Tests use Hypium (`@ohos/hypium`). Place local unit tests in `entry/src/test/*.test.ets` and ability/device tests in `entry/src/ohosTest/ets/test/*.test.ets`. Test suites should describe the behavior under test, and individual cases should use clear `it(...)` names. Run tests from DevEco Studio before submitting changes that affect services, parsing, playback, navigation, or persistence.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commit prefixes such as `feat:`, `fix:`, and scoped forms like `fix(player): ...`; keep that style and write concise summaries, Chinese or English. Pull requests should include the purpose, major files touched, verification performed, and screenshots or short clips for UI changes. Link related issues when available and call out changes to signing, resources, permissions, or external source parsing.

## Security & Configuration Tips

Do not commit personal signing material, new secrets, or machine-specific paths. Review `build-profile.json5`, network config, and permission-related resources carefully when changing release builds or external data access.
