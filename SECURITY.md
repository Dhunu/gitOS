# Security Policy

GitOS handles GitHub sign-ins and installs updates, so security reports matter a lot.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through
[GitHub's security advisory form](https://github.com/Dhunu/gitOS/security/advisories/new).

Include what you found, how to reproduce it, and what an attacker could do with it. I'll reply as soon as I can, and I'll credit you when the fix ships unless you'd rather stay anonymous.

## Supported versions

Only the [latest release](https://github.com/Dhunu/gitOS/releases/latest) gets security fixes.

## What's most useful to report

- GitHub tokens or Anthropic API keys being exposed or stored outside the Keychain
- One account's credentials being used for another account's repository
- Ways to get GitOS to install an update that isn't properly signed
- A repository's content making GitOS run commands or leak data

## Known limits

GitOS releases aren't notarized by Apple yet, so macOS asks you to approve the app on first launch. Only download GitOS from this repository's [Releases page](https://github.com/Dhunu/gitOS/releases).
