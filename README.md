<p align="center"><img src="site/icon.png" alt="EnvSwitcher icon" width="96" height="96"></p>

<h1 align="center">EnvSwitcher</h1>

<p align="center">
  <a href="https://github.com/ahmetkorkmaz3/EnvSwitcher/releases/latest"><img src="https://img.shields.io/github/v/release/ahmetkorkmaz3/EnvSwitcher" alt="Latest release"></a>
  <a href="https://github.com/ahmetkorkmaz3/EnvSwitcher/actions/workflows/ci.yml"><img src="https://github.com/ahmetkorkmaz3/EnvSwitcher/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14 or later">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/ahmetkorkmaz3/EnvSwitcher" alt="MIT license"></a>
</p>

<p align="center"><a href="https://ahmetkorkmaz3.github.io/EnvSwitcher/">Website</a> · <a href="#install">Install</a> · <a href="#quick-start">Quick start</a> · <a href="CONTRIBUTING.md">Contributing</a></p>

EnvSwitcher is a macOS menu bar app that switches the `.env` files of a project between environments. Example: change between the `local`, `test`, and `prod` values with one click.

- Enter the values in the app one time. When you change the environment, the app writes the `.env` files again.
- Secret values (tokens, passwords, keys) stay in the macOS Keychain. They do not go into the `store.json` file.
- All `.env` files of a monorepo change together or one at a time.

## Install

Run this command in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/EnvSwitcher/main/install.sh | sh
```

The command downloads the latest release, checks the SHA-256 value, installs the app in `/Applications`, and opens it. Requirement: macOS 14 or later. The app supports Apple Silicon and Intel.

**Update:** Run the same command again. When a new release is available, the menu shows an "Update Available" item. This item copies the command to the clipboard.

**A specific version:** `curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/EnvSwitcher/main/install.sh | ENVSWITCHER_VERSION=0.2.0 sh`

**Manual install:**

1. Download the `EnvSwitcher-X.Y.Z.zip` file from the [Releases](https://github.com/ahmetkorkmaz3/EnvSwitcher/releases) page.
2. Open the zip file. Move `EnvSwitcher.app` into `/Applications`.
3. Open the app. macOS shows the "Apple could not verify" warning. Click **Done**.
4. Open System Settings → Privacy & Security. At the bottom of the page, click **Open Anyway**.

The app is not notarized, so a file from the browser shows this warning. The install command does not show this warning.

**Uninstall:**

```sh
osascript -e 'quit app "EnvSwitcher"'
rm -rf /Applications/EnvSwitcher.app
rm -rf ~/Library/Application\ Support/EnvSwitcher
security delete-generic-password -s EnvSwitcher -a vault
defaults delete com.ahmetkorkmaz.envswitcher
```

These commands do not change your `.env` files.

## Quick start

1. Install the app (see [Install](#install)) and open it. The menu bar shows `EnvSwitcher`.
2. In the menu, choose **Add Project…**. Choose the project folder or drag it into the window.
3. Check the `.env` files that the app finds. Click **Add**. The app imports the current content of the files into the `local` environment.
4. In the **Manage…** window, choose a file. At the top, choose the **Compare** view.
5. For the missing keys, choose **Copy to Missing → Copy the local Value**. Then change the values that are different for `test`.
6. In the menu, choose the project → **All Files → test**. The app writes all files with the `test` values.

## Concepts

| Concept | Meaning |
|---|---|
| Project | A root folder. Each folder is in one project only. |
| Environment | A set of values, for example `local`, `test`, `prod`. Each environment has a color. |
| Protected environment | The app asks for confirmation before it switches to this environment. `prod` starts as protected. |
| Target file | A `.env` file that the app manages, for example `apps/cart/.env.local`. |
| Environment on disk | The last environment that the app wrote to a file. The menu and the sidebar show it with a colored dot. |
| Secret value | A value that the Keychain keeps. Keys with `SECRET`, `PASSWORD`, `TOKEN`, or `PRIVATE` in the name, or keys that end with `_KEY`, become secret automatically. Keys that start with `NEXT_PUBLIC_` do not become secret. |

## Daily use

**Switch the environment (menu bar):**
- An environment under **All Files** switches all files of the project.
- The submenu of a file under **Files** switches only that file.
- When the files are in different environments, the title shows `mixed`.

**Edit values (Manage… window):**
- Choose a file and choose the environment at the top. The app saves each change immediately.
- After you change a key name, press Return or move to a different field.
- When you edit the environment on disk, the window shows "The changes are not on disk yet." Click **Write to Disk**.
- **Preview .env** shows the file that the app will write. Secret values show as `••••••••`.
- **Paste from Clipboard** adds the `KEY=value` lines on the clipboard to the selected environment.
  - The app adds the keys that are not in the environment. It fills the empty values. It asks no question.
  - When a key has a different value, the app asks: **Overwrite** or **Add Only Missing Keys**.
  - When a new key looks like a secret (`_KEY`, `TOKEN`, `SECRET`), the app writes it to the Keychain.

**Compare environments (Manage… → file → Compare):**
- Each key has one row. The values of each environment show side by side.
- The mark at the start of the row shows the status: red = missing in an environment, orange = the values are different, gray = the same in all environments.
- The **Missing** and **Different** filters show only the related rows.
- Type a value in a missing cell and press Return. The app adds the key to that environment.
- **Copy to Missing** writes the value of one environment to all environments that do not have the key.
- **Copy to All Missing** does the same for all missing keys in one step. It asks for confirmation first. Existing values do not change.
  - **From the First Filled Environment of Each Key**: each key gets its value from the first environment that has the key.
  - **Copy the <environment> Values**: the values come from the selected environment. The app skips the keys that this environment does not have and lists them.
- Secret values show as `••••`. The eye button in the row shows the values.
- When the Edit view has missing keys in an environment, the bottom bar shows a "Keys missing in this environment: N" button.

**Project settings (project name in the sidebar):**
- Add environments. Change their name, color, and protection.
- Use **Add File** to add a `.env` file that you create later. The app imports its content into the environment on disk of the project.
- When you delete a project, the `.env` files on disk do not change.

## Safety checks

- **Manual change check:** When you edit a file in an editor, the app shows the difference before the environment changes. Options: save the change to an environment, discard and switch, or cancel.
- **Empty environment warning:** When the selected environment has no values for a file, the app asks first. This warning prevents empty files by mistake.
- **All or nothing:** When the app cannot write one file, the files that it wrote go back to their old content.
- **File permissions:** The app keeps the permissions of the file (for example `600`) and writes to the target of a symbolic link.
- **Git warning:** When a `.env` file is not in `.gitignore`, the app shows a warning when you add the project.

## Folders that the scan skips

`node_modules`, `vendor`, `.git`, `dist`, `build`, `.next`, `.turbo`, `.claude`, and subfolders with their own `.git` entry (separate repositories, worktree copies). Files that end with `.example`, `.sample`, or `.template` show in the list, but the app does not select them.

## Data location

| What | Where |
|---|---|
| Projects, environments, values that are not secret | `~/Library/Application Support/EnvSwitcher/store.json` |
| Last backup | `~/Library/Application Support/EnvSwitcher/store.json.bak` |
| Secret values | Keychain, service name `EnvSwitcher`, account name `vault` (one item) |
| Update check | `defaults read com.ahmetkorkmaz.envswitcher storedUpdate` |
| Old content when a rollback fails | `~/Library/Application Support/EnvSwitcher/recovery/` |

When `store.json` is damaged, the app loads the backup and shows a warning.

## Contributing

Build, tests, project structure, and pull request rules: [CONTRIBUTING.md](CONTRIBUTING.md). Release steps: [`docs/release.md`](docs/release.md).

## License

MIT. See [LICENSE](LICENSE).
