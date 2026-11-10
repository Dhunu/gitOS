# GitOS — spec

A native macOS (SwiftUI, macOS 27+) git client modelled on GitHub Desktop, built around
**multiple GitHub accounts** that switch automatically per folder/repo.

## Decisions (from the kickoff Q&A, 2026-11-01)

| Area | Decision |
|---|---|
| Account switching | Folder rules (`~/Work` → work account) + per-repo override + global default |
| Hosts | GitHub.com |
| Auth | Browser OAuth (GitHub device flow); tokens in the macOS Keychain |
| macOS | 27+ only (latest SwiftUI, Liquid Glass) |
| Git engine | System `git` CLI, output parsed (`--porcelain=v2 -z`, custom `--format`) |
| Power features | Commit graph, line/hunk staging, interactive rebase UI, stash & worktrees |
| Conflicts | Built-in 3-way merge editor |
| GitHub | Pull requests, CI/checks status, clone from account, issues |
| Identity per account | Commit name/email, SSH/GPG signing, co-author picker, push mismatch warning |
| Extras | AI commit messages (Claude), menu bar switcher, `gitos` CLI, background fetch |
| Distribution | Local build only (no sandbox) |
| Name | GitOS |

## How multi-account works

Every git command GitOS runs gets per-invocation config, so nothing in `~/.gitconfig`
or the macOS keychain is changed:

- **Credentials** — `-c credential.https://github.com.helper=` (clears every other helper,
  e.g. osxkeychain, *for github.com only*) followed by an inline helper that returns the
  resolved account's OAuth token from env vars. Other hosts keep the user's normal helpers.
- **SSH remotes** — `url.https://github.com/.insteadOf=git@github.com:` so SSH remotes also
  go through the account's token (no `~/.ssh/config` host aliases needed).
- **Identity** — `user.name`, `user.email`, and when configured `gpg.format`,
  `user.signingkey`, `commit.gpgsign=true`.

Account resolution for a repo: repo override → longest matching folder rule → default account.

## Roadmap

**Phase 1 — done**
- Accounts: GitHub device-flow sign-in, Keychain, label, commit identity, signing config
- Folder rules, per-repo override, default account; toolbar account switcher that says *why*
- Repos: add local repo, sidebar list, reveal/open in Terminal
- Changes: staged / unstaged / conflicted lists, stage/unstage/discard, diff view,
  **hunk** stage/unstage/discard
- Commit box (summary + description, ⌘↩), committing as the resolved identity
- Branches: switch, create
- Fetch / pull / push with ahead/behind; push mismatch warning (author email ∉ account emails)
- History list + commit diff

**Phase 2 — done**
- Commit graph lanes in History (current branch or all branches)
- Line-level staging/unstaging/discarding (click the line-number gutter, Shift-click for ranges)
- Clone from account (lists user + org repos; defaults to the account's folder rule; pins the account if needed)
- Stashes tab (stash incl. untracked, apply/pop/drop, diff preview) and Worktrees tab (add/remove/open)
- Co-author picker (recent authors + manual), `Co-authored-by` trailers
- Menu bar extra: default-account switcher, per-repo status, Fetch All
- `gitos` CLI (Settings › General installs it), opens/adds the repo
- Background fetch per account (interval in Settings), FSEvents auto-refresh, "new commits upstream" notifications

**Phase 3 — done**
- Pull Requests tab: open PRs with checks and labels, check out (same-repo → tracking branch, fork → `pr/<n>`),
  open on GitHub, create PR (pushes first, base picker, draft, ✨ title/description from commits + diff)
- Checks badge in the toolbar for HEAD (check runs + commit statuses), per-PR checks
- Issues tab: list/filter, create, "Close with next commit" (`Fixes #n`) / "Reference" (`Refs #n`)
- Interactive rebase from History (reorder, pick/reword/squash/fixup/drop) driven through
  `GIT_SEQUENCE_EDITOR`; rewords use `exec git commit --amend -F`; warns when rewriting pushed commits
- Banner for stopped rebase/merge/cherry-pick/revert with Continue / Skip / Abort; Merge branch; Force push with lease
- 3-way conflict editor: per-conflict ours / base (diff3) / theirs, both orders, custom edit, editable result,
  whole-file ours/theirs/delete; CRLF-safe
- ✨ Commit messages and PR descriptions with Claude (Messages API, `claude-opus-5-5` by default, effort `low`,
  server-side refusal fallback); key in Keychain, model in Settings › AI

**Phase 4 — done**
- AI code review for PRs, commits and uncommitted changes (0.2.0)
- Focus mode (⇧⌘F or the expand button on any detail pane; Esc leaves): the pane you're reading —
  diff, conflict editor, commit, pull request, issue or stash — takes the whole window, hiding the
  sidebar, list, tab bar and status bar. ⌘1–⌘6 switch tabs while the tab bar is hidden.

## Setup note

Device flow needs a GitHub OAuth App client ID (one-time):
github.com/settings/applications/new → any name, homepage/callback `http://localhost`
→ tick **Enable Device Flow** → paste the Client ID into GitOS Settings › GitHub. The app ships with one built in (`AppState.builtInGitHubClientID`); Settings overrides it.
