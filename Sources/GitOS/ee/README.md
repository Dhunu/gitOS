# GitOS Pro (`ee`)

The code in this folder powers GitOS Pro features: the Pull Requests (with triage and CI
checks), Issues and Worktrees tabs, AI commit messages, PR descriptions and code review, the
3-way conflict editor and interactive rebase. The license check and the screens free users see
in place of these features are outside `ee/`, in `Sources/GitOS/Licensing/`.
It is public so you can read, build and improve it, but it is **not** under the same license
as the rest of GitOS. It is covered by the [GitOS Commercial License](LICENSE):

- Using it needs a GitOS Pro, Lifetime or Team license.
- Building and changing it for development and testing is free, as is sending pull requests.
- Redistributing or selling it, or builds that include it, is not allowed.

Tests for this code live in `Tests/GitOSTests/ee/` under the same license.

Code outside `ee/` is under the [PolyForm Noncommercial License](../../../LICENSE): free for
personal, noncommercial use.
