# Contributing

Thanks for helping. DictateLocal is a small project, so a short issue before a large change saves everyone time.

## Setup

You need an Apple Silicon Mac with macOS 26 and either the Xcode Command Line Tools (`xcode-select --install`) or Xcode 26.

```bash
git clone https://github.com/merkLui/DictateLocal.git
cd DictateLocal
scripts/test.sh          # unit tests; the first run builds MLX and takes a few minutes
scripts/build-app.sh     # builds dist/DictateLocal.app
```

Quit an installed DictateLocal before running your build, because both would react to the shortcut.

### Keep permissions across builds

macOS ties Accessibility, Input Monitoring and Microphone permissions to the app's signature. An ad-hoc signed build changes it every time, and you would have to grant the permissions again after each build. Create a local certificate once:

```bash
scripts/create-signing-certificate.sh
```

`scripts/build-app.sh` then signs with "DictateLocal Development" automatically.

## Making a change

1. Fork the repository and create a branch from `main`.
2. Keep the change focused on one topic. Logic that does not need AppKit belongs in `DictateCore`, with a test in `Tests/DictateCoreTests`.
3. Follow the conventions in [AGENTS.md](AGENTS.md): they apply to humans and agents alike.
4. Run `scripts/test.sh` and `scripts/build-app.sh`. For UI changes, add screenshots to the pull request.
5. Write commit messages in the [Conventional Commits](https://www.conventionalcommits.org/) style, for example `fix: keep the clipboard when pasting fails`.
6. Open a pull request and fill in the template. CI must pass, and a maintainer reviews every change.

## Reporting bugs

Use the bug report form. The log from **Settings > Diagnostics > Export** helps most; turn on "Hide dictated text in log" first if you do not want to share what you said.

## Code of conduct

Be kind and assume good intent. Harassment or personal attacks are not tolerated in issues, pull requests or discussions, and maintainers may remove such content or block its author.
