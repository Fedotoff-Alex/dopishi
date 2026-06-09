# Security Policy

Dopishi is an experimental, locally-running macOS app. It reads the focused text field and
(optionally) the screen, clipboard, and a local history to build prompts for an on-device LLM.
Nothing is sent to the network.

## Reporting a vulnerability

Please report privately, not in a public issue:

- Open a [private security advisory](https://github.com/Fedotoff-Alex/dopishi/security/advisories/new), or
- Email fedotoff.alex@gmail.com with "Dopishi security" in the subject.

Include steps to reproduce and the impact. Please give a reasonable window to address it
before any public disclosure.

## Scope and known limitations

- The local memory store (`~/Library/Application Support/Dopishi/`) is **plaintext SQLite**
  with owner-only file permissions and a 14-day TTL. Encryption (SQLCipher) is on the roadmap.
- Secure fields (passwords, OTP, card numbers) are excluded from reading, completion, and
  storage. Clipboard/memory content that looks like a secret is dropped, but this is a
  heuristic, not a guarantee.
- Context fed to the model (screen/clipboard/memory) is treated as untrusted input. Prompt
  injection is mitigated (symbol stripping, secret dropping) but not fully solved.
- Builds are not notarized; run only builds you trust.
