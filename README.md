# GitOS

A native macOS git client (SwiftUI, macOS 27+) in the spirit of GitHub Desktop, with
**multiple GitHub accounts that switch automatically per folder or repo**.
See [SPEC.md](SPEC.md) for decisions and the roadmap.

## Download

**[Download the latest GitOS `.dmg`](https://github.com/Dhunu/gitOS/releases/latest)** from the
Assets section of the release page. You don't need to clone this repo or install any developer tools
beyond git.

**Requirements:** macOS 27 or later on Apple Silicon (M-series; Intel Macs aren't supported), and git.
If you don't have git, run `xcode-select --install` in Terminal.

## Install

1. Open the `.dmg` and drag **GitOS** onto **Applications**.
2. Open GitOS from Applications. macOS blocks it the first time because the app isn't notarized by
   Apple. Click **Done** (don't move it to the Trash).
3. Go to **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to the
   GitOS message. Confirm with your password.

You only need to do this once per version. If macOS says the app is damaged instead, run this and
open it again:

```bash
xattr -dr com.apple.quarantine /Applications/GitOS.app
```

## First-time setup

1. Nothing to configure for GitHub sign-in: GitOS ships with a built-in OAuth Client ID. To use your own
   OAuth App (homepage and callback `http://localhost`, **Enable Device Flow** ticked), paste its Client ID
   into **Settings › GitHub**.
2. **Settings › Accounts › +** for each GitHub account. Keep the browser signed into the account you're
   adding; use a private window for the second one.
3. **Settings › Folder Rules**: e.g. `~/Work` → work account. Everything else uses the default account.
   The account button in a repo's toolbar overrides it per repo.

Settings › General has background fetch, notifications, the menu bar icon, and
**Install gitos Command** (then `gitos .` in any repo opens it in GitOS).

✨ commit messages (⌘⇧G) and PR descriptions use whichever you pick in **Settings › AI**: the
[Claude Code](https://claude.com/product/claude-code) or [Codex](https://developers.openai.com/codex/cli)
CLI you're already signed in to, with no API key needed, or an Anthropic API key. To sign in, run `claude`
or `codex login` in Terminal.

Tokens live in the macOS Keychain. Account switching is done with per-command `-c` flags, so
`~/.gitconfig` and your existing keychain entries are never modified.

## Updating

GitOS checks for new versions about once a day and offers to install them. To check yourself, choose
**GitOS › Check for Updates…**, and you can turn the automatic check off in **Settings › General**.
Your accounts and settings are kept. After an update, macOS may ask to let GitOS read its saved tokens
from the Keychain: click **Always Allow**.

You can also download the new `.dmg` from [Releases](https://github.com/Dhunu/gitOS/releases) and drag
GitOS to Applications, choosing **Replace**.

## Uninstalling

1. Delete `GitOS.app` from Applications.
2. Delete `~/Library/Application Support/GitOS` to remove your settings.
3. In **Keychain Access**, delete the items named **GitOS GitHub token**.
4. If you installed the `gitos` command, delete it from `/opt/homebrew/bin`, `/usr/local/bin` or
   `~/.local/bin`.

## Build from source

```bash
./scripts/build-app.sh            # → build/GitOS.app
./scripts/build-app.sh --install  # also copies to /Applications
./scripts/make-dmg.sh             # → build/GitOS-<version>.dmg to share
./scripts/make-icon.sh            # re-renders Resources/AppIcon.icns
./scripts/release.sh 0.2.0        # publishes a GitHub Release that installed apps update to
swift test                        # parser + real-git integration tests
```
