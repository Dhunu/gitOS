# Contributing to GitOS

Thanks for helping out. Bug reports, ideas and pull requests are all welcome.

## Before you start

- **Bugs:** [open an issue](https://github.com/Dhunu/gitOS/issues/new/choose) with the steps to reproduce it.
- **Bigger changes:** open an issue first, so we can agree on the approach before you spend time on it.
- **Security problems:** please don't open a public issue. See [SECURITY.md](SECURITY.md).

## Set up

You need macOS 26 or later on Apple Silicon, and Xcode with its command line tools.

```bash
git clone https://github.com/<your-username>/gitOS.git
cd gitOS
swift test                  # runs the tests
./scripts/build-app.sh      # builds build/GitOS.app
```

GitOS uses a built-in GitHub sign-in, so there's nothing to configure. [SPEC.md](SPEC.md) explains the design and the roadmap.

## Making a change

1. Fork the repo and create a branch from `main`.
2. Keep the pull request to one change. Small ones get reviewed faster.
3. Add or update tests when you change behavior. `Tests/GitOSTests` has examples, including tests that run real git commands.
4. Run `swift test` and make sure it passes.
5. Try the change in the real app with `./scripts/build-app.sh`, and add a screenshot if it changes the interface.
6. Open a pull request and fill in the template.

## Reviews and merging

Every change reaches `main` through a pull request. A maintainer reviews it, and only maintainers can merge. Releases are also published by maintainers, so you don't need to change the version number.

GitOS is source-available under the [PolyForm Noncommercial License](LICENSE), with the code in
`Sources/GitOS/ee/` under the [GitOS Commercial License](Sources/GitOS/ee/LICENSE). Because the
author also sells commercial licenses, contributions need broader rights than those licenses
give: by opening a pull request, you confirm that you wrote the change (or have the right to
submit it), and you grant Angel Saikia a perpetual, worldwide, royalty-free, irrevocable license
to use, change, sublicense and distribute your contribution under any license, including
commercial ones. You keep the copyright in your contribution.

## Code of conduct

Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).
