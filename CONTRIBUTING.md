# Contributing to Dopishi

Thanks for your interest. Dopishi is a small, experimental project, so contributions are
welcome but please open an issue first to discuss anything non-trivial.

## Getting started

```bash
swift build
swift test     # requires Xcode (swift-testing runner)
```

Open `Package.swift` in Xcode, or use your editor of choice. The app is assembled with
`./scripts/make-app.sh` which also code-signs it.

## Ground rules

- **Discuss first.** For features or behavior changes, open an issue before a PR.
- **Tests.** New logic in `DopishiCore` / `DopishiMemory` must come with swift-testing tests.
  These targets are pure and easy to test; keep AppKit-coupled code thin.
- **Small, focused changes.** Prefer many small files over large ones (200-400 lines typical).
- **Immutability.** Favor value types and new values over mutation.
- **No secrets.** Never commit API keys, tokens, or model files.
- **Privacy first.** Anything that reads the screen, clipboard, or stores text must stay
  opt-in, gated on non-secure / allowed apps, and must not persist secrets.

## Commit / PR style

- Conventional-ish prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`.
- Keep the PR description focused: what changed, why, how it was tested.
- Make sure `swift build` and `swift test` are green before opening a PR.

## Dependencies

The LLM dependency is a pinned fork of LocalLLMClient (by exact revision) carrying small
local patches; see `vendor-patches/localllmclient.patch.txt` for what they are. Do not switch
it back to an unpinned branch.

## Scope

Dopishi targets macOS 14+. Cross-platform support is out of scope.
