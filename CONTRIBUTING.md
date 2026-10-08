# Contributing guide

Thank you for your contribution to EnvSwitcher. This file describes the development setup, the test steps, and the pull request rules.

## Report a bug or make a suggestion

1. First, search for the same topic on the [Issues](https://github.com/ahmetkorkmaz3/EnvSwitcher/issues) page.
2. Open a new issue. Write this information:
   - The macOS version and the processor (Apple Silicon or Intel).
   - The EnvSwitcher version. The version shows at the bottom of the menu.
   - The steps, the expected result, and the actual result.
3. Do not write real `.env` values, tokens, or passwords in the issue. Use example values.

Before a large change, open an issue and discuss the idea.

## Development setup

**Requirements:** macOS 14 or later and Xcode. Make Xcode the active developer directory:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

**Build and run:**

```sh
swift test                         # EnvCore tests
scripts/bundle.sh                  # creates build/EnvSwitcher.app
open build/EnvSwitcher.app
```

**Real Keychain test:**

```sh
ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests
```

This test writes to the real Keychain. For this reason, it does not run by default.

**Script check:** CI checks all scripts with `shellcheck`. Do the same check before you push:

```sh
brew install shellcheck
shellcheck scripts/*.sh install.sh
```

**Translation check:** CI checks the `.strings` files with `scripts/check-strings.sh`. Run it after you change a text that the user sees.

### Signing and the Keychain permission prompt

The Keychain identifies the app that creates an item by its signature. An ad-hoc signature changes with each build. For this reason, macOS asks for permission one time after an ad-hoc build. All secret values are in one item, so the prompt shows one time.

To prevent this prompt, sign with a local certificate:

1. Create the certificate one time: `scripts/make-signing-cert.sh`. If the certificate already exists and you have the `.p12` file, double-click the file to import it into the login Keychain.
2. Build: `CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh`

## Project structure

| Folder | Content |
|---|---|
| `Sources/EnvCore` | Logic without UI: parsing, scanning, Keychain, environment switching. The tests cover this module. |
| `Sources/EnvSwitcher` | The SwiftUI app: menu bar, manage window, difference window. |
| `Resources/` | App icon and the `en` and `tr` translation files. |
| `Tests/EnvCoreTests` | Unit tests. `Support/` has a fake file writer and a fake Keychain. |
| `site/` | The website. GitHub Pages publishes this folder. |
| `docs/manual-test.md` | The manual test list to do before each release. |
| `docs/release.md` | Release steps. |
| `docs/superpowers/specs/` | Design documents. |
| `scripts/` | Build, icon, certificate, translation, and CHANGELOG scripts. |
| `install.sh` | Install and update script. |
| `.github/workflows/` | CI, release, and Pages workflows. |

## Code rules

- Write the logic in `EnvCore`. The `EnvSwitcher` module contains only the UI.
- Add a test for each change in `EnvCore`. For the disk and the Keychain, use the fake classes in `Tests/EnvCoreTests/Support`.
- Do not write secret values to logs, error messages, or `store.json`.
- The app shows its texts in English and Turkish. Add each new text to both `Resources/en.lproj/Localizable.strings` and `Resources/tr.lproj/Localizable.strings`. Use short and clear sentences.
- Follow the style of the code around your change.

## Commit messages

Write commit messages in English, in the [Conventional Commits](https://www.conventionalcommits.org/) format:

```
feat(core): check GitHub for a newer release
fix: keep the old app when the install copy fails
ci: use actions/checkout@v5, because v4 runs on the deprecated Node.js 20
```

Types in use: `feat`, `fix`, `docs`, `ci`, `build`, `test`, `refactor`. The scope is optional: `core`, `app`, or `site`. When there is a reason, add it to the message with `because`.

## Pull requests

1. Create a new branch from `main`. Examples: `feat/compare-filter`, `fix/install-path`.
2. Make the change. Run `swift test`, `shellcheck`, and `scripts/check-strings.sh`.
3. When the UI changes, add a screenshot.
4. When the user can see the change, add a line to the `## [Unreleased]` section at the top of `CHANGELOG.md`.
5. Open the pull request. The review starts when CI passes.

## Website

The website is the `site/index.html` file. The page is one HTML file. It has no build step.

- To see it locally: `open site/index.html`
- When you push to the `main` branch, `.github/workflows/pages.yml` publishes the page.
- One time before the first publish: go to GitHub → Settings → Pages → Source and choose **GitHub Actions**.

## Releases

Release steps: [`docs/release.md`](docs/release.md). Before a release, do the steps in [`docs/manual-test.md`](docs/manual-test.md).

## License

Your contributions are published under the [MIT license](LICENSE).
