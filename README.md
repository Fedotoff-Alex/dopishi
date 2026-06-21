# Dopishi (Допиши)

System-wide inline autocomplete for macOS, powered by a fully local LLM. Dopishi shows
gray "ghost" suggestions at the caret in almost any app and completes your text when you
press Tab - similar in spirit to Cotypist and Cotabby, but built from scratch as a learning
and open-source project. Everything runs on-device; nothing is sent to the network.

> Status: experimental / personal project (v0.9.2 beta). It builds, is covered by ~510 tests,
> and works day to day, but it is not a polished release yet (see Limitations). Use at your own risk.
>
> New in v0.9.2: UI localization (ru/en, auto by system language), per-language model
> recommendation in onboarding & Model Manager (manual choice never overwritten), a cross-cutting
> secret guard (secrets never reach memory/prompt), and layout-fix for Cyrillic letters that sit on
> QWERTY punctuation keys (now convert as whole words).

## What it does

- **Inline completion** - ghost text at the caret across native and Electron apps (TextEdit,
  Notes, Mail, Slack, Claude, browsers, and more). Tab accepts a word, Tab again continues.
- **Keyboard layout fixing** - Punto-style. Detects text typed in the wrong layout and offers
  to convert RU<->EN. Manual conversion of the last word by tapping Option.
- **Spelling correction** - misspelled words get a green ghost suggestion; Tab applies it.
- **Selection actions** - select text, press the hotkey, and the local model fixes / shortens /
  rewrites / expands / translates / re-tones it; Tab replaces the selection.
- **Emoji and snippets** - type `:name` and Tab to insert an emoji or your own snippet.
- **Setup and control** - a first-run wizard (permissions, model download, test field), a
  Privacy Center (pause, per-app "don't learn here", retention window, export / clear memory),
  and a model manager (download with sha256 verification, resume / cancel, on-disk size, speed
  benchmark).
- **Context channels** (all opt-in, off by default):
  - **Screen (OCR)** - reads the text around the field via ScreenCaptureKit + Vision so
    suggestions fit the conversation or document, not just the current line.
  - **Clipboard** - recently copied text is mixed in when it is fresh and relevant.
  - **Memory** - a local SQLite store (GRDB) remembers what you wrote per window and feeds
    it back as context.

## Privacy

- The model runs **locally** via llama.cpp (Metal). No text leaves your machine.
- All three context channels are **opt-in and off by default**.
- **Secure fields** (passwords, OTP, card numbers) are never read, completed, or stored.
- Clipboard / memory content that looks like a secret (API keys, tokens) is dropped before
  it can reach the prompt.
- Per-app exclusions: turn Dopishi off for specific apps.
- Memory is plaintext SQLite under `~/Library/Application Support/Dopishi/` with owner-only
  file permissions and a configurable retention window (default 7 days). The Privacy Center
  lets you exclude specific apps from learning, and export or clear the store. Disk encryption
  is on the roadmap, so treat the store as plaintext for now.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon recommended (Metal).
- Xcode 26+ / Swift 6.2+ (the package declares swift-tools-version 6.2; the test runner needs
  Xcode, Command Line Tools alone cannot run swift-testing).
- A GGUF model (a small instruct model such as Qwen3-4B or Gemma works well).

## Permissions

Dopishi needs the following macOS permissions (grant them in System Settings -> Privacy & Security):

- **Accessibility** - to read the focused field and place the ghost text.
- **Input Monitoring** - to observe typing.
- **Screen Recording** - only if you enable the Screen (OCR) context channel.

## Build and run

```bash
git clone https://github.com/Fedotoff-Alex/dopishi.git
cd dopishi
swift build            # resolves dependencies (incl. the pinned LocalLLMClient fork) and builds
swift test             # ~470 tests (requires Xcode)
./scripts/make-app.sh  # assembles and code-signs dist/Dopishi.app
open dist/Dopishi.app
```

On first launch, grant the permissions above from the menu-bar icon, then download a model
from Settings (or drop a `.gguf` into `~/Library/Application Support/Dopishi/Models/`).

## Architecture

SwiftPM workspace with focused targets:

- **DopishiCore** - pure logic, no AppKit: prompt building, context sanitization, layout
  transliteration, completion-stop rules, settings. Heavily unit-tested.
- **DopishiLLM** - the local LLM engine (LocalLLMClient + llama.cpp, C++ interop, Metal).
- **DopishiMemory** - local SQLite memory via GRDB.
- **DopishiApp** - the menu-bar app: accessibility reader, input monitor, ghost overlay,
  OCR provider, suggestion controller, settings UI.

Suggestions never block on I/O: OCR, clipboard, and memory are precomputed snapshots that
the prompt builder reads as-is. The static few-shot prompt head is kept literal so the
llama.cpp KV cache can be reused across keystrokes.

## Dependencies and licenses

- [LocalLLMClient](https://github.com/Fedotoff-Alex/LocalLLMClient) (fork with local patches,
  pinned by revision) - wraps llama.cpp.
- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite (MIT).
- llama.cpp - bundled via LocalLLMClient (MIT).

Models you download have their **own licenses** (for example Qwen and Gemma each have their
own terms). You are responsible for complying with the license of any model you use.

## Limitations

- Dev build, not notarized. Run from `dist/Dopishi.app` on your own machine.
- Suggestion quality is bounded by the size of the local model.
- Electron/Claude support uses some private/undocumented Accessibility APIs and may break on
  OS or app updates. In Electron apps the accessibility text can also lag fast typing, so a
  mid-word completion may occasionally be spaced or skipped; native apps are unaffected.
- Prompt-injection from context channels is reduced (symbol stripping, secret dropping), not
  fully solved. Context is treated as untrusted hints.
- Dopishi does not act in Spotlight / system search: its instant-search field re-renders the
  text faster than synthetic edits can land, so layout conversion there is unreliable - the
  field is excluded by design.

## Credits

Inspired by [Cotypist](https://cotypist.app) and [Cotabby](https://cotabby.app). Dopishi is
an independent implementation; behavior was studied from their public apps and re-implemented
from scratch.

## License

MIT - see [LICENSE](LICENSE).
