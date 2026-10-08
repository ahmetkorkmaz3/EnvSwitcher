# Changelog

This file uses the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-10-08

### Changed

- The default protected environment is now `prod`, not `canli`. Existing projects keep their environment names.

## [0.3.0] - 2026-10-08

### Added

- English and Turkish language support. On the first start, the app uses the macOS language. You can change the language in Settings.
- The website opens in English. The TR button shows the page in Turkish.

### Changed

- The header comment of the `.env` files is in English.

## [0.2.0] - 2026-10-08

The first public release.

### Added

- Switch all `.env` files of a project, or one file, to a different environment from the menu bar.
- Add a project: scan the folder, show a `.gitignore` warning, and import the current values into the `local` environment.
- Edit window: edit values, preview the `.env` file, and paste `KEY=value` lines from the clipboard.
- Compare view: see the values of a file side by side across environments, and copy the missing keys.
- Safety checks: manual change check, empty environment warning, all-or-nothing writes, and confirmation for protected environments.
- Secret values stay in one item in the macOS Keychain.
- A new release notice and a version item in the menu.
- Install and update with one command: `install.sh`.
- Apple Silicon and Intel support.

### Changed

- Builds before 0.2.0 keep each secret value in a separate Keychain item. On the first start, the app moves these items into one item.
