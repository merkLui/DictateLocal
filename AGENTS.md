# AGENTS.md

Guidance for coding agents (Claude Code, Codex, Cursor, Gemini and others) working on DictateLocal. Humans should read [CONTRIBUTING.md](CONTRIBUTING.md) first; everything here applies to them too.

## What this is

A macOS menu bar dictation app in Swift for Apple Silicon and macOS 26+. Speech recognition runs locally through FluidAudio (Core ML); optional text cleanup runs locally through MLX or online through the Anthropic API. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing the dictation flow.

## Commands

| Task | Command |
| --- | --- |
| Run the unit tests | `scripts/test.sh` (filter with `scripts/test.sh --filter Shortcut`) |
| Build and bundle the app | `scripts/build-app.sh` → `dist/DictateLocal.app` |
| Type-check only the app target | `source scripts/toolchain.sh && swift build --build-system native --product DictateLocal` |
| Stream an audio file through a model | `swift run --build-system native DictateBench recording.wav` |

Always use the scripts or `--build-system native`: the default build system tries to compile MLX's Metal shaders, which needs Xcode's Metal toolchain. `scripts/toolchain.sh` also picks a working SDK when only the Command Line Tools are installed. The first build takes several minutes because of MLX.

## Layout

```text
Sources/DictateCore/      Platform logic without UI: models, sessions, cleanup, guards. Unit-tested.
Sources/DictateLocal/     The app.
  App/                    AppDelegate split by topic (+Models, +Cleanup, +MenuBar, +Dictation), logging, permissions
  Dictation/              Shortcut handling, audio capture, typing and pasting text (TextIntegrator)
  HUD/                    The floating recording indicator
  Settings/               One file per settings page; shared rows in Settings/Components
Sources/DictateBench/     Maintainer tool for audio, model and cleanup benchmarks
Tests/DictateCoreTests/   Swift Testing suites
scripts/                  Build, test and signing scripts
Resources/                App icon and entitlements
```

## Rules

- **Keep logic testable.** Put anything that does not need AppKit into `DictateCore` and cover it with a Swift Testing case. The app target has no tests, so changes there must be verified by building and, for UI, by a screenshot.
- **Never invent text.** Every cleanup step must keep the speaker's words. Model output is only used if `CleanupGuard` (Spokenly) or `ClaudeCleanup.accepts` (Claude) accepts it; otherwise the original transcript is used. Do not weaken these guards without new test cases.
- **One model in memory.** Only the selected speech model may be loaded. Unloading is final for a transcriber instance (see `SpeechModelTests`).
- **Privacy.** Audio never leaves the Mac. Do not log dictated text when the "Hide dictated text in log" setting is on (`AppLogger.usesPrivacyLogging`). Do not add analytics or new network calls without discussing it in an issue first.
- **Secrets.** Never commit API keys, certificates (`*.p12`, `*.p8`) or exported logs. The Anthropic key lives only in the user's Application Support folder.
- **Settings UI.** Match Apple's System Settings: grouped forms, native controls, no explanatory grey subtitles. Explanations go into an info button (`TitleWithInfo` with a `SettingInfo`: one sentence plus short facts). Grey text under a row is only for live state such as download progress.
- **Do not test input against the user's apps.** Typing and pasting tests send real keystrokes. Run them only in a window the test creates itself, never in whatever app happens to be focused.
- **Swift.** The targets use the Swift 5 language mode on the Swift 6 compiler. Keep new code free of concurrency warnings. Prefer small types and files; split a file when it passes about 400 lines.
- **Dependencies.** FluidAudio is pinned to a revision on purpose; update it only with a test of both speech models. New dependencies need a reason and must have a license compatible with Apache 2.0; add them to `THIRD_PARTY_NOTICES.md`.

## Verifying a change

1. `scripts/test.sh` passes.
2. `scripts/build-app.sh` builds without new warnings in files you touched.
3. For UI changes, launch `dist/DictateLocal.app --settings=model` (or `general`, `vocabulary`, `diagnostics`) and look at the page. Quit the installed DictateLocal first, because two copies would share the shortcut.
4. For changes to recognition or cleanup, run `DictateBench` on a real recording and compare with the previous output.

## Commits and pull requests

- Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `ci:`, `chore:`. The subject is imperative and under 72 characters; the body says why.
- One topic per pull request. Fill in the template, including how you verified the change.
- Do not push to `main`, rewrite published history or create releases; maintainers do that.
