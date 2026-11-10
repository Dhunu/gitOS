# GitOS

A native macOS git client (SwiftUI, macOS 27+) in the spirit of GitHub Desktop, with
**multiple GitHub accounts that switch automatically per folder or repo**.
See [SPEC.md](SPEC.md) for decisions and the roadmap.

**Website:** [gitos.angelsaikia.com](https://gitos.angelsaikia.com)

## Download

**[Download the latest GitOS `.dmg`](https://github.com/Dhunu/gitOS/releases/latest)** from the
Assets section of the release page. You don't need to clone this repo or install any developer tools
beyond git.

**Requirements:** macOS 27 or later on Apple Silicon (M-series; Intel Macs aren't supported), and git.
If you don't have git, run `xcode-select --install` in Terminal.

**Or install with Homebrew:**

```sh
brew tap dhunu/tap
brew install --cask gitos
```

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
   If an organization hasn't approved GitOS, its private repositories show as "not found", even though your
   account has access. You can ask the organization to approve GitOS, or click **Use a Token…** when adding the
   account and paste a [classic personal access token](https://github.com/settings/tokens/new?description=GitOS&scopes=repo,read:org,workflow,user:email).
   Tokens don't need organization approval unless the organization blocks them. If it uses SSO, also choose
   **Configure SSO** next to the token on GitHub.
3. **Settings › Folder Rules**: e.g. `~/Work` → work account. Everything else uses the default account.
   The account button in a repo's toolbar overrides it per repo.

Settings › General has themes (Monokai, Tokyo Night, Dracula, One Dark Pro, GitHub, Nord, Catppuccin, Solarized
and more), background fetch, notifications, the menu bar icon, and
**Install gitos Command** (then `gitos .` in any repo opens it in GitOS).

**Focus mode** (⇧⌘F, or the expand button on any detail pane) gives the pane you're reading — a file's
diff, the conflict editor, a commit, pull request, issue or stash — the whole window. Esc brings
everything back, and ⌘1–⌘6 switch tabs while the tab bar is hidden.

✨ commit messages (⌘⇧G) and PR descriptions use whichever you pick in **Settings › AI**: the
[Claude Code](https://claude.com/product/claude-code) or [Codex](https://developers.openai.com/codex/cli)
CLI you're already signed in to, with no API key needed, or an Anthropic API key. To sign in, run `claude`
or `codex login` in Terminal.

Tokens live in the macOS Keychain. Account switching is done with per-command `-c` flags, so
`~/.gitconfig` and your existing keychain entries are never modified.

## Updating

GitOS checks for new versions when it opens and every hour while it's running, and downloads them in the
background. When an update is ready, **Restart to Update** appears in the sidebar, the GitOS menu and
**Settings › General**. Nothing installs until you click it: if you quit instead, the update downloads again
next time. You can turn the automatic check off in **Settings › General**, or check yourself with
**GitOS › Check for Updates…**. Your accounts and settings are kept. After an update, macOS may ask to let GitOS
read its saved tokens from the Keychain: click **Always Allow**.

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

## Contributing

Contributions are welcome. See the [contributing guide](CONTRIBUTING.md) to get started, and [SECURITY.md](SECURITY.md) to report a security problem.

## License

GitOS is available under the [MIT License](LICENSE).
