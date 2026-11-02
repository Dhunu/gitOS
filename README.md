# GitOS

A native macOS git client (SwiftUI, macOS 27+) in the spirit of GitHub Desktop, with
**multiple GitHub accounts that switch automatically per folder or repo**.
See [SPEC.md](SPEC.md) for decisions and the roadmap.

## Build & run

```bash
./scripts/build-app.sh            # → build/GitOS.app
./scripts/build-app.sh --install  # also copies to /Applications
swift test                        # parser + real-git integration tests
```

## First-time setup

1. Create a GitHub OAuth App (one-time): github.com/settings/applications/new, with homepage and callback
   `http://localhost` and **Enable Device Flow** ticked. Paste its Client ID into **Settings › GitHub**.
2. **Settings › Accounts › +** for each GitHub account. Keep the browser signed into the account you're
   adding; use a private window for the second one.
3. **Settings › Folder Rules**: e.g. `~/Work` → work account. Everything else uses the default account.
   The account button in a repo's toolbar overrides it per repo.

Settings › General has background fetch, notifications, the menu bar icon, and
**Install gitos Command** (then `gitos .` in any repo opens it in GitOS).

Settings › AI takes an Anthropic API key for ✨ commit messages (⌘⇧G) and PR descriptions.

Tokens live in the macOS Keychain. Account switching is done with per-command `-c` flags, so
`~/.gitconfig` and your existing keychain entries are never modified.
