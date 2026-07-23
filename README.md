<p align="center">
   <img src="assets/pkgs.png" alt="Termux TUI Package Store interface showing a split-panel layout with a searchable package list on the left and package metadata preview on the right" width="700">
</p>

<p align="center">
   <em><sub>Screenshot may not reflect the latest version. Run <code>pkgs</code> to see the current interface.</sub></em>
</p>

<p align="center">
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/releases">
     <img src="https://img.shields.io/github/v/release/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=blue" alt="Release">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/stargazers">
     <img src="https://img.shields.io/github/stars/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=yellow" alt="Stars">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/forks">
     <img src="https://img.shields.io/github/forks/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=cyan" alt="Forks">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/issues">
     <img src="https://img.shields.io/github/issues/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=red" alt="Issues">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/pulls">
     <img src="https://img.shields.io/github/issues-pr/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=blueviolet" alt="PRs">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
     <img src="https://img.shields.io/github/repo-size/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=orange" alt="Repo Size">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
     <img src="https://img.shields.io/github/languages/top/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=ff69b4" alt="Language">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/blob/main/LICENSE">
     <img src="https://img.shields.io/github/license/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=green" alt="License">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
     <img src="https://img.shields.io/badge/maintained-yes-brightgreen?style=for-the-badge" alt="Maintained">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
     <img src="https://img.shields.io/badge/PRs-welcome-orange?style=for-the-badge" alt="PRs Welcome">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
     <img src="https://img.shields.io/badge/last_commit-active-blue?style=for-the-badge" alt="Active">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
     <img src="https://img.shields.io/badge/platform-termux%20%7C%20android-006600?style=for-the-badge" alt="Platform">
   </a>
   <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
     <img src="https://img.shields.io/badge/shell-zsh-blue?style=for-the-badge" alt="Shell">
   </a>
</p>

<h1 align="center">Termux TUI Package Store 📦</h1>
<p align="center">
   <em>Interactive fzf-powered terminal UI for browsing, previewing, installing, and removing Termux packages — no more typing repetitive <code>pkg install</code> commands.</em>
</p>

<p align="center">
   <b>v1.4.0</b>
</p>

<p align="center">
   <b>⚡ One keystroke. Instant preview. Persistent session. Search, install, remove, and export packages without leaving your terminal.</b>
</p>

<p align="center">
  <a href="#quick-install">Quick Install</a> •
  <a href="#usage">Usage</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <b>⭐ Star this repo if you find it useful! It helps others discover it.</b>
</p>

---

## Why pkgs?

| Problem with `pkg` | How pkgs solves it |
|---|---|
| Typing full package names every time | Fuzzy search matches partial names instantly |
| No preview of what you're installing | Live pane shows version, size, deps, and description |
| Have to run install/remove separately for each package | Tab to select multiple, or use `/install <query>` for bulk ops |
| Session closes after every install | Persistent loop — keep managing packages until you press Esc |
| No way to audit installed packages | Color-coded `[✓]` / `[ ]` tags at a glance |

---

## Perfect For

- **Termux power users** who manage dozens of packages regularly
- **Android developers** setting up fresh Termux environments
- **Automation lovers** who want to export install scripts in one click
- **New Termux users** overwhelmed by typing `pkg install` repeatedly

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Install](#quick-install)
- [Manual Installation](#manual-installation)
- [Usage](#usage)
  - [Slash Commands](#slash-commands)
- [Key Bindings](#key-bindings)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Uninstallation](#uninstallation)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [License](#license)
- [Disclaimer](#disclaimer)
- [Acknowledgments](#acknowledgments)

---

## Overview

Termux TUI Package Store is a terminal UI for managing packages on Termux. It wraps `pkg` with an interactive fuzzy-finder that lets you search, preview, install, and remove packages — all without leaving a single screen.

The tool adapts to your terminal size, color-codes installed vs. available packages, and shows live metadata previews (version, size, dependencies, description) for every package you highlight. Type `/help` in the search box to see all 130 available slash commands.

---

## Features

| Feature | Description |
|---|---|
| **🔍 Fuzzy Search** | Filter hundreds of packages instantly as you type |
| **📋 Live Previews** | See version, installed/download size, dependencies, and description for any package |
| **🔄 Persistent Session** | Store stays open after install/remove — keep going until you press Esc |
| **📐 Smart Layout** | Automatically switches between landscape (side-by-side) and portrait (stacked) preview |
| **🎨 Color-Coded Status** | Installed packages tagged `[✓]`, available packages tagged `[ ]` |
| **⚡ 140 Slash Commands** | Bulk install/remove/export, filters, sorting, notes, comparison, backup/restore, dependency analysis, hold/unhold, changelogs, file search, mirror management, themes, snapshots, quick install, security checks, profiles, health checks, storage monitoring, cache dashboard, batch upgrade, activity log, dependency graph, and more |
| **📦 Batch Operations** | Multi-select with Tab, preview with dry-run, categorized summary with progress |
| **🛡️ Prerequisite Checks** | Validates fzf, pkg, apt-cache, and dpkg-query on startup |
| **📊 Disk Usage** | Visual breakdown by section with bar charts |
| **📝 Package Notes** | Add/edit notes per package, persisted across sessions |
| **⚖️ Package Comparison** | Side-by-side view of two packages |
| **💾 Backup & Restore** | Export full package list, reinstall from it later |
| **🕐 Recent Activity** | Filter packages installed today via dpkg logs |
| **📜 Operation History** | Daily log of all install/remove/export operations |
| **↩️ Undo Support** | Reverse last install or remove operation |
| **⚡ Zero Config** | No config files needed — runs as a single script at `$PREFIX/bin/pkgs` |

### Slash Commands (140 total)

| Command | Description |
|---|---|
| `/upgrade` | Upgrade all installed packages |
| `/install <query>` | Install all packages matching `<query>` |
| `/remove <query>` | Remove all packages matching `<query>` |
| `/purge <pkg>` | Remove package + config files |
| `/hold <pkg>` | Pin package (prevent upgrade) |
| `/unhold <pkg>` | Unpin package (allow upgrade) |
| `/export <query>` | Export matching packages to a runnable shell script |
| `/export-all` | Export all installed packages to a shell script |
| `/info <pkg>` | Show full package details in a panel |
| `/search <text>` | Search package descriptions (not just names) |
| `/search-file <text>` | Search installed files by name |
| `/search-size <min> <max>` | Find packages by size range (KiB) |
| `/rdeps <pkg>` | Show reverse dependencies (what depends on this) |
| `/deps <pkg>` | Show what a package depends on |
| `/depends-on <pkg>` | Show installed packages that depend on this |
| `/depends-chain <a> <b>` | Show dependency chain between two packages |
| `/tree <pkg>` | Show dependency tree |
| `/deptree <pkg>` | Visual ASCII dependency tree with box drawing |
| `/reverse-tree <pkg>` | Reverse dependency tree (what depends on me) |
| `/compare <a> <b>` | Compare two packages side by side |
| `/note <pkg> <text>` | Add or view a note for a package |
| `/orphans` | Show orphaned packages |
| `/orphans-safe` | Show safe orphans (no essential dependents) |
| `/orphans-remove` | Remove all orphaned packages |
| `/outdated` | Show packages with available updates |
| `/outdated-top <n>` | Top N packages with updates by size |
| `/top` | Top 10 largest installed packages |
| `/top <n>` | Top N largest installed packages |
| `/size` | Total installed size |
| `/count` | Count installed/available packages |
| `/update` | Update apt cache |
| `/clean` | Remove orphaned packages and clean apt cache |
| `/installed` | Filter: show only installed packages |
| `/available` | Filter: show only available packages |
| `/recent` | Filter: show only packages installed today |
| `/usage` | Show disk usage breakdown by section |
| `/usage <pkg>` | Show installed files for a package |
| `/usage-top` | Disk usage bar chart (top packages) |
| `/group` | Group packages by section |
| `/check` | Verify installed packages integrity |
| `/changelog <pkg>` | Show package changelog |
| `/diff <pkg>` | Changelog diff of last upgrade |
| `/reinstall <pkg>` | Reinstall a package |
| `/download <pkg>` | Download package without installing |
| `/download-size <pkg>` | Show download + installed size |
| `/download-est <pkg>` | Download + installed size with expansion ratio |
| `/verify <pkg>` | Verify package checksums/integrity |
| `/version` | Show system version info |
| `/review` | Today's activity summary |
| `/stats` | Today's install/remove counts |
| `/all` | Reset filter: show all packages |
| `/sort name` or `/sort size` | Sort packages by name or size |
| `/history` | View last 7 days of operation log |
| `/backup` | Export your full package list to a file |
| `/restore <file>` | Install all packages from a backup file |
| `/undo` | Reverse last install or remove |
| `/mirror` | Switch apt mirror |
| `/mirror-backup` | Backup/restore sources.list snapshots |
| `/mirror-latency` | Ping-test all mirrors, rank by latency |
| `/mirror-bandwidth` | Bandwidth-test mirrors, rank by speed |
| `/fav <pkg>` | Toggle package favorite |
| `/fav-list` | Show all favorites |
| `/fav-remove` | Remove a favorite |
| `/import <file>` | Install from package list file |
| `/why <pkg>` | Show why a package is installed |
| `/suggest <pkg>` | Show recommended packages |
| `/nuke` | Interactive storage cleanup |
| `/whatsnew` | Show recent upgrade changelogs |
| `/tips` | Termux tips and tricks |
| `/self-update` | Update pkgs from GitHub |
| `/theme` | Switch color scheme (dark/light/minimal/neon/dracula/monokai/solarized) |
| `/pkg-history <pkg>` | Per-package install/upgrade/remove history |
| `/pkg-changes` | Show what changed in last apt upgrade |
| `/pkg-ages` | Show age of each installed package |
| `/pkg-recommendations <pkg>` | Show who recommends this package |
| `/pkg-suggests <pkg>` | Show who suggests this package |
| `/pkg-breaks <pkg>` | Show what breaks if this is installed |
| `/pkg-replaces <pkg>` | Show what this package replaces |
| `/broken` | Find broken/half-installed packages |
| `/conflicts-with <pkg>` | Show conflicting packages |
| `/provides <pkg>` | Show virtual packages provided |
| `/manually-installed` | Show only manually installed packages |
| `/auto-installed` | Show only auto-installed packages |
| `/upgrade-plan` | Simulate upgrade, show what would change |
| `/upgrade-size` | Total download size before upgrading |
| `/unused-libs` | Find orphaned .so libraries |
| `/maintainer <name>` | Search packages by maintainer |
| `/log-search <text>` | Search dpkg/apt history logs |
| `/size-histogram` | Visual package size distribution |
| `/owner <file>` | Which package owns this file (dpkg -S) |
| `/removed` | Packages removed in last upgrade |
| `/new-pkgs` | Packages installed this week |
| `/same-size` | Packages with identical installed size |
| `/depends-on-list <pkgs>` | Shared dependencies of multiple packages |
| `/upgradable` | Upgradable packages with version diff |
| `/whatprovides <file>` | Find which package provides a binary |
| `/snap-install <file>` | Install from local .deb file |
| `/simulate-remove <pkg>` | Simulate removal, show consequences |
| `/repo-stats` | Packages per repository breakdown |
| `/snapshot` | Save installed package snapshot |
| `/snapshot-list` | List saved snapshots |
| `/snapshot-restore` | Restore from a snapshot |
| `/plan <cmd>` | Dry-run preview (install/remove/upgrade) |
| `/missing` | Check for missing dependencies |
| `/export-versions` | Export installed package list with version numbers and sizes |
| `/theme-preview` | Preview current color scheme in use |
| `/keys` | Fzf keybinding reference overlay |
| `/cache-stats` | Cache and stats dashboard (validity, counts, history, disk usage) |
| `/suggest <pkg>` | Show suggested/recommended/depending packages for any package |
| `/dep-graph <pkg>` | Visual ASCII dependency tree (3 levels, circular ref detection) |
| `/batch-upgrade` | Interactive fzf multi-select of upgradable packages with batch processing |
| `/activity-log [days]` | Activity summary with per-action counts and recent entries |
| `/compare <pkg1> <pkg2>` | Side-by-side field comparison plus dependency overlap analysis |
| `/compact` | Toggle compact fzf mode |
| `/search-history <text>` | Search operation history |
| `/quick` | Quick install popular package sets |
| `/fuzzy-dep` | Interactive dependency explorer |
| `/size-filter <min> <max>` | Filter by installed size (KiB) |
| `/security` | Check for outdated packages |
| `/duplicate` | Find duplicate/virtual packages |
| `/help` | Show in-app help |

---

## Requirements

- **Termux** (Android 7+) — [Get it from F-Droid](https://f-droid.org/en/packages/com.termux/) or GitHub
- **Zsh** — the script runs on zsh
- **Runtime dependencies:**

| Package | Purpose | Required |
|---|---|---|
| `fzf` | Fuzzy-finder interface | Yes |
| `awk` | Data processing (package list generation) | Yes |
| `grep`, `sed` | Text processing in previews | Yes |
| `ncurses` | Terminal handling (`tput`) | Yes |
| `dpkg` | Package queries (`dpkg-query`) | Yes |
| `apt-cache` | Package metadata and search | Yes |
| `coreutils` | Human-readable sizes (`numfmt`) | Optional |

The installer also pulls `curl` and `figlet` for the install banner — these are not needed at runtime.

> **Note:** Tested on Termux v0.118.x with fzf 0.53.0. Older versions may work but are not guaranteed.

---

## Quick Install

```sh
zsh <(curl -fsSL https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/main/install.sh)
```

> **Note:** The installer requires `zsh`. If it's not installed, run `pkg install zsh` first, then retry.

---

## Manual Installation

1. **Install dependencies:**

   ```sh
   pkg update && pkg upgrade
   pkg install zsh fzf coreutils gawk grep sed ncurses curl figlet
   ```

2. **Download the script and make it executable:**

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/main/pkgs_core.zsh -o "$PREFIX/bin/pkgs"
   chmod +x "$PREFIX/bin/pkgs"
   ```

> **Note:** The source file is `pkgs_core.zsh` in this repo, but it is installed as `$PREFIX/bin/pkgs` on your device. Edit that file to customize behavior.

3. **Run it:**

   ```sh
   pkgs
   ```

---

## Usage

Launch the store by typing:

```sh
pkgs
```

Type to filter packages. The list updates in real time. Press **Enter** on any package to install it (if not installed) or remove it (if installed). After the operation completes, the store re-opens automatically. Press **Esc** or **Ctrl+C** to exit.

You can also pre-filter by passing a search term:

```sh
pkgs python
```

This opens the store with "python" already typed in the search box.

### Slash Commands

Type these directly in the search box. See the [Features](#features) section for the full list.

Examples:
- `/install python` — installs all packages with "python" in the name
- `/remove vim` — removes all matching packages
- `/export git` — saves matching packages to `pkg-install-YYYYMMDD-HHMMSS.sh`
- `/search editor` — finds packages whose descriptions mention "editor"
- `/rdeps python` — shows what depends on python
- `/clean` — cleans up orphaned packages and apt cache

---

## Key Bindings

| Key | Action |
|---|---|
| `Enter` | Process selected packages (shows batch summary: `y`=process, `d`=dry-run, `e`=export, `Enter`=cancel) |
| `Tab` | Select multiple packages |
| `Ctrl-A` | Select all visible packages |
| `Ctrl-D` | Deselect all packages |
| `?` | Toggle the preview pane |
| `Esc` or `Ctrl+C` | Exit the store |
| Typing | Search/filter packages in real time |

---

## How It Works

1. **Layout Detection**  
   The tool measures your terminal with `tput` and decides whether to show the preview alongside the package list (wide terminals) or below it (narrow terminals).

2. **Package Discovery**  
   An `awk` (gawk) script cross-references installed packages from `dpkg-query` against every available package from `apt-cache search ".*"`. Each line is tagged `[✓]` (installed) or `[ ]` (not installed).

3. **Live Previews**  
   When you highlight a package, `fzf` runs `apt-cache show` in the background and displays version, section, size, top dependencies, and the description.

4. **Slash Commands**  
   Typing `/install <query>`, `/remove <query>`, `/export <query>`, or any of the 130 slash commands in the search box triggers bulk operations instead of package selection. Packages are validated against `apt-cache` before any action runs.

5. **Action & Loop**  
   Pressing Enter shows a batch summary of selected packages with install/remove categorization. Choose `y` to process, `d` for a dry-run preview, `e` to export to a script, or press Enter to cancel. After processing, the store refreshes and re-opens — no need to relaunch.

---

## Configuration

> **Note:** `$PREFIX` is Termux's installation prefix, typically `/data/data/com.termux/files/usr`.

The entire script lives in a single file at `$PREFIX/bin/pkgs`. Edit it directly to customize behavior.

### Preview Window

| Setting | Default | Description |
|---|---|---|
| `PORTRAIT_SPLIT` | `down:48%:wrap` | Preview position/height in portrait mode |
| `LANDSCAPE_SPLIT` | `right:40%:wrap` | Preview position/width in landscape mode |

**Examples:**

```zsh
PORTRAIT_SPLIT="down:60%:wrap"   # taller preview in portrait
LANDSCAPE_SPLIT="left:40%:wrap"   # preview on the left in landscape
```

### Colors

The `--color` flag in `_pkgs_build_fzf_args` uses 256-color ANSI codes. Customize any element:

```zsh
--color='fg:223,bg:-1,hl:114,fg+:223,bg+:235,hl+:109,info:109,prompt:180,pointer:203,marker:114,spinner:139,header:59'
```

See the [fzf documentation](https://github.com/junegunn/fzf#color-schemes) for available color slots.

### Message Colors

| Variable | Default | Description |
|---|---|---|
| `C_INST_PREFIX` | `[✓]` (green) | Tag for installed packages |
| `C_NOT_INST_PREFIX` | `[ ]` (dim) | Tag for not-installed packages |
| `C_PKG_NAME` | Green | Package name in list |
| `C_PKG_DESC` | Dim | Description in list |
| `C_MSG_INSTALL` | Green | Install success messages |
| `C_MSG_REMOVE` | Red | Remove/failure messages |
| `C_MSG_INFO` | Amber | Info/prompts |

### Behavior

| Variable | Default | Description |
|---|---|---|
| `PKG_MGR` | `pkg` | Package manager command (`pkg` or `apt`) |
| `BORDER_STYLE` | `rounded` | fzf border style (`rounded`, `sharp`, `double`, `bold`) |

### Common Customizations

- **Reinstall instead of install:** Change `${PKG_MGR} install "$pkg_name"` to `${PKG_MGR} reinstall "$pkg_name"`.
- **Log every action:** Add `echo "$(date): $action $pkg_name" >> ~/.pkgs_history` inside the loop.
- **Exclude library packages:** Append `| grep -vE '^(lib|python-|perl-|ruby-)'` to the `_pkgs_generate_list` pipeline.
- **Hide already-installed packages:** Pipe through `grep -v '\[✓\]'` after the awk script.
- **Floating overlay:** Add `--height=80%` to `FZF_ARGS` for a non-fullscreen view.
- **Hide preview by default:** Change `--preview-window="$PREVIEW_LAYOUT"` to `--preview-window="$PREVIEW_LAYOUT:hidden"`. Press `?` to toggle.
- **Keep search query across operations:** Store the query in a variable before fzf exits and pass it back on re-entry.

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `pkgs: command not found` | Script not in PATH | Run `which pkgs` — should show `$PREFIX/bin/pkgs`. Re-run `install.sh` if missing. |
| `zsh: no such file or directory` | Shebang path wrong | Run `head -1 $(which pkgs)` — should show `#!/data/data/com.termux/files/usr/bin/zsh`. Reinstall if corrupted. |
| Empty package list | `apt-cache` needs updating | Run `pkg update` and try again. |
| `fzf: command not found` | Dependency missing | Run `pkg install fzf`. |
| Colors look wrong | Terminal lacks 256-color support | Simplify the `--color` flag to basic 16-color ANSI codes. |
| Preview shows nothing | `apt-cache show` failed for that package | Try `apt-cache show <package>` manually to verify. |

---

## FAQ

**Q: Why does the store re-open after I install something?**  
A: The tool loops back to the package list so you can manage multiple packages in one session. Press Esc or Ctrl+C to quit.

**Q: Can I use `apt` instead of `pkg`?**  
A: Yes. Change `PKG_MGR="pkg"` to `PKG_MGR="apt"` in the configuration section.

**Q: Does this work outside Termux?**  
A: No. The script depends on Termux-specific paths (`$PREFIX`) and package management tools (`pkg`, `apt-cache`, `dpkg-query`).

**Q: How do I update to the latest version?**  
A: Re-run the one-liner install command. It overwrites `$PREFIX/bin/pkgs` with the latest version.

**Q: Can I contribute?**  
A: Absolutely — see [Contributing](#contributing).

---

## Uninstallation

```sh
rm "$PREFIX/bin/pkgs"
rm -rf ~/.local/share/pkgs
rm -rf ~/.config/pkgs
```

The first command removes the script. The second removes history logs, notes, and cache stored at `~/.local/share/pkgs/`. The third removes persistent filter/sort state stored at `~/.config/pkgs/`. No other config files or shell modifications exist.

---

## Contributing

Contributions are welcome! Whether it's a bug fix, a new feature, or improved documentation:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feat/my-change`).
3. Make your changes.
4. Run `zsh -n pkgs_core.zsh` to check for syntax errors.
5. Commit with a descriptive message (e.g., `feat: add --dry-run flag`).
6. Push and open a pull request.

Please follow the [Contributor Covenant](https://www.contributor-covenant.org/) code of conduct. Be kind, be respectful, and keep discussions constructive.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed list of all changes.

---

## License

This project is licensed under the **MIT License**. See [LICENSE](https://github.com/Mark44928/Termux-TUI-Package-Store/blob/main/LICENSE) for details.

---

## Disclaimer

This tool runs `pkg install` and `pkg remove` commands that modify your Termux environment. Always review package names before confirming installations. The authors are not responsible for any system damage resulting from misuse.

---

## Acknowledgments

- [junegunn/fzf](https://github.com/junegunn/fzf) — the incredible fuzzy-finder that makes this tool possible
- The [Termux](https://termux.com/) community for maintaining an excellent Android terminal environment
- Everyone who has submitted issues, suggestions, or pull requests

---

## Show Your Support

If Termux TUI Package Store makes your Termux life easier, consider:

- **Star the repo** — it helps others discover the project
- **Report bugs** — open an [issue](https://github.com/Mark44928/Termux-TUI-Package-Store/issues)
- **Contribute** — submit a [pull request](https://github.com/Mark44928/Termux-TUI-Package-Store/pulls)
- **Share it** — tell your Termux-using friends
- **Give feedback** — ideas and suggestions are always welcome

Every star, issue, and PR makes this project better. Thank you!

---

## You Might Also Like

- [NoNameOS](https://github.com/Mark44928/NoNameOS) - Pure C++ hobbyist OS simulation
- [Anti-Bloatware List](https://github.com/Mark44928/Anti-bloatware-list-for-Android-TV-Boxes-and-Sticks-for-rooted) - Debloat rooted Android TV sticks

---

<p align="center">
  Made with ❤️ for the Termux community
</p>
