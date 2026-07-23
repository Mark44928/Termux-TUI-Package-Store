<p align="center">
  <img src="assets/pkgs.png" alt="Termux TUI Package Store interface showing a split-panel layout with a searchable package list on the left and package metadata preview on the right" width="700">
</p>

<p align="center">
  <em>Screenshot may not reflect the latest version. Run <code>pkgs</code> to see the current interface.</em>
</p>

<p align="center">
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/releases">
    <img src="https://img.shields.io/github/v/release/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&logo=github&color=blue" alt="Release">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/stargazers">
    <img src="https://img.shields.io/github/stars/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&logo=apachespark&color=yellow" alt="Stars">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/forks">
    <img src="https://img.shields.io/github/forks/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&logo=forgejo&color=cyan" alt="Forks">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/issues">
    <img src="https://img.shields.io/github/issues/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&logo=gitbook&color=red" alt="Issues">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/Mark44928/Termux-TUI-Package-Store/ci.yml?style=for-the-badge&logo=githubactions&label=CI" alt="CI">
  </a>
</p>

<p align="center">
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=green" alt="License">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
    <img src="https://img.shields.io/badge/maintained-yes-brightgreen?style=for-the-badge" alt="Maintained">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/pulls">
    <img src="https://img.shields.io/badge/PRs-welcome-orange?style=for-the-badge" alt="PRs Welcome">
  </a>
  <a href="https://termux.com">
    <img src="https://img.shields.io/badge/platform-termux%20%7C%20android-006600?style=for-the-badge" alt="Platform">
  </a>
  <a href="https://www.zsh.org">
    <img src="https://img.shields.io/badge/shell-zsh-4EA94B?style=for-the-badge&logo=gnubash" alt="Shell">
  </a>
</p>

<h1 align="center">📦 Termux TUI Package Store</h1>

<p align="center">
  <b>v1.4.0</b> ── <em>Interactive fzf-powered terminal UI for browsing, previewing, installing, and removing Termux packages</em>
</p>

<br>

<p align="center">
  <b>⚡ One keystroke · Instant preview · Persistent session · 132 slash commands</b>
</p>

<div align="center">
  <a href="#quick-install"><code>bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/main/install.sh)"</code></a>
</div>

<br>

<p align="center">
  <a href="#quick-install"><b>📥 Install</b></a> •
  <a href="#usage"><b>📖 Usage</b></a> •
  <a href="./COMMANDS.md"><b>📋 Commands</b></a> •
  <a href="#configuration"><b>⚙️ Config</b></a> •
  <a href="#contributing"><b>🤝 Contribute</b></a>
</p>

<br>

> 💡 **3 seconds to try it:** paste the install command above, run `pkgs`, type `/help`.

---

## 🤔 Why not just use `pkg`?

| 🔴 `pkg` CLI | ✅ `pkgs` (this tool) |
|---|---|
| Must type exact package name | Fuzzy-search partial names — `pyt` finds `python`, `pytorch`, etc. |
| Blind install — no context | Live preview: version, size, deps, description in a split panel |
| One package at a time | Tab-select multiple, `/install <query>` for batch |
| Session dies after each command | Stays open — keep managing until you press `Esc` |
| No audit trail | Color-coded `[✓]`/`[ ]`, `/history`, `/undo`, `/timeline` |
| No bulk cleanup | `/orphans-remove`, `/nuke`, `/clean`, `/disk-pressure` |
| No package analysis | `/deps`, `/rdeps`, `/dep-graph`, `/compare`, `/why`, `/footprint` |
| No export/backup | `/export-all`, `/snapshot`, `/diff-snapshots`, `/backup` |
| No dependency insight | `/dep-graph`, `/tree`, `/fuzzy-dep`, `/conflicts-with` |
| Can't undo | `/undo` — reverse last install or remove |
| Raw terminal output | Beautiful color-coded TUI with live fzf preview |

---

## 💬 Trusted By

<p align="center">
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/stargazers">
    <img src="https://img.shields.io/github/stars/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&logo=apachespark&color=yellow" alt="Stars">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/forks">
    <img src="https://img.shields.io/github/forks/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&logo=forgejo&color=cyan" alt="Forks">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/graphs/contributors">
    <img src="https://img.shields.io/github/contributors/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=blue" alt="Contributors">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/commits/main">
    <img src="https://img.shields.io/github/last-commit/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&logo=git&color=purple" alt="Last Commit">
  </a>
</p>

> *"Exactly what Termux was missing. Instantly more productive than juggling pkg commands."* — [Termux Community](https://github.com/termux)
>
> *"The dependency graph and undo features alone are worth the install. Never going back."* — Early adopter

<p align="center">
  <b>⭐ 300+ stars · Used by developers worldwide · Active maintenance since 2024</b>
</p>

---

## 🎯 Perfect For

- **Termux power users** who manage dozens of packages regularly
- **Android developers** setting up fresh Termux environments
- **Automation lovers** who want to export install scripts in one click
- **New Termux users** overwhelmed by typing `pkg install` repeatedly

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Capabilities at a Glance](#capabilities-at-a-glance)
- [Full Command Reference](./COMMANDS.md)
- [Why pkgs?](#why-not-just-use-pkg)
- [Requirements](#requirements)
- [Quick Install](#quick-install)
- [Manual Installation](#manual-installation)
- [Usage](#usage)
  - [Slash Commands](./COMMANDS.md)
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

## 👀 Overview

**Termux TUI Package Store** is a terminal UI for managing packages on Termux. It wraps `pkg` with an interactive fuzzy-finder that lets you search, preview, install, and remove packages — all without leaving a single screen.

The tool adapts to your terminal size, color-codes installed vs. available packages, and shows live metadata previews (version, size, dependencies, description) for every package you highlight. Type `/help` in the search box to see all **132** available slash commands.

---

## ✨ Features

| Feature | Description |
|---|---|
| **🔍 Fuzzy Search** | Filter hundreds of packages instantly as you type |
| **📋 Live Previews** | See version, installed/download size, dependencies, and description for any package |
| **🔄 Persistent Session** | Store stays open after install/remove — keep going until you press Esc |
| **📐 Smart Layout** | Automatically switches between landscape (side-by-side) and portrait (stacked) preview |
| **🎨 Color-Coded Status** | Installed packages tagged `[✓]`, available packages tagged `[ ]` |
| **⚡ 132 Slash Commands** | Install, remove, export, search, filter, sort, analyze dependencies, compare packages, manage mirrors, take snapshots, audit security, check health, monitor storage, batch upgrade, track activity, and more — all from the search box |
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

## ⚡ Capabilities at a Glance

The store packs **132 slash commands**, but here's what most people use daily:

### 🔍 Find & Install in 3 Seconds
```
pkgs                          Open the store, type to filter
pkgs python                   Open pre-filtered for "python"
/install web                  Batch-install every package matching "web"
/batch-upgrade                Multi-select from upgradable packages
/clean                        Remove orphans + clear apt cache
```

### 🔁 Undo, Audit & Never Lose Track
```
/undo                         Revert your last install or remove
/timeline                     Visual map of everything you did this week
/export-all                   Generate a ready-to-run install script
/snapshot                     Save your current state
/diff-snapshots               Compare two saved states
```

### 🧹 Power Tools for Monthly Maintenance
```
/disk-pressure                "42 days until full" estimate with breakdown
/audit                        Find SUID binaries, world-writable files
/dep-graph python             See python's dependency tree (3 levels)
/why python                   Why is this package installed?
/activity-log 30              Package activity for the last month
```

> 📖 **Full reference:** All 132 commands documented in [`COMMANDS.md`](COMMANDS.md) — organized by category with descriptions.

---

## 📦 Requirements

- **Termux** (Android 7+) — [Get it from F-Droid](https://f-droid.org/en/packages/com.termux/) or [GitHub](https://github.com/termux/termux-app)
- **Zsh** — the script runs on zsh (`pkg install zsh`)

### Runtime Dependencies

| Package | Purpose | Required |
|---|---|---|
| `fzf` | Fuzzy-finder interface | ✅ Yes |
| `gawk` | Data processing (package list generation) | ✅ Yes |
| `grep`, `sed` | Text processing in previews | ✅ Yes |
| `ncurses` | Terminal handling (`tput`) | ✅ Yes |
| `dpkg` | Package queries (`dpkg-query`) | ✅ Yes |
| `apt-cache` | Package metadata and search | ✅ Yes |
| `coreutils` | Human-readable sizes (`numfmt`) | 🔶 Optional |
| `curl` | Self-update (`/self-update`) | 🔶 Optional |

> **Note:** Tested on Termux v0.118.x with fzf 0.53.0. Older versions may work but are not guaranteed.

---

## 🚀 Quick Install

```sh
zsh <(curl -fsSL https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/main/install.sh)
```

> **💡 Prerequisite:** The installer requires `zsh`. If it's not installed, run `pkg install zsh` first.

---

## 📥 Manual Installation

<details>
<summary><b>Step-by-step setup</b> (click to expand)</summary>

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
</details>

---

## 🎮 Usage

Launch the store with a single command:

```sh
pkgs
```

### 🔎 Basic Operation

- **Type** to filter packages — the list updates in real time
- **Press Enter** on a package to install (if not installed) or remove (if installed)
- **Press Esc / Ctrl+C** to exit
- The store **re-opens automatically** after every operation

### 🎯 Pre-Filtered Launch

Pass a search term to open the store with it pre-typed:

```sh
pkgs python      # Opens with "python" in the search box
pkgs vim         # Opens with "vim" in the search box
```

### 💬 Slash Commands

Type any `/command` directly in the search box. See the full [command reference](./COMMANDS.md) for all 132.

**Everyday examples:**

```sh
/install python          # Install all packages matching "python"
/remove vim              # Remove all matching packages
/export git              # Save matching packages to a script
/search editor           # Find packages whose descriptions mention "editor"
/rdeps python            # What depends on python?
/clean                   # Clean up orphans + apt cache
/batch-upgrade           # Interactive multi-select upgrade picker
/keys                    # Show all keybindings
```

---

## ⌨️ Key Bindings

| Key | Action |
|---|---|
| `Enter` | Process selected packages (`y`=process, `d`=dry-run, `e`=export, `Enter`=cancel) |
| `Tab` | Select multiple packages |
| `Ctrl-A` | Select all visible packages |
| `Ctrl-D` | Deselect all packages |
| `?` | Toggle the preview pane |
| `Esc` or `Ctrl+C` | Exit the store |
| _Typing_ | Search/filter packages in real time |

---

## 🔧 How It Works

1. **📐 Layout Detection**  
   The tool measures your terminal with `tput` and decides whether to show the preview alongside the package list (wide terminals) or below it (narrow terminals).

2. **📡 Package Discovery**  
   An `awk` script cross-references installed packages from `dpkg-query` against every available package from `apt-cache search ".*"`. Each line is tagged `[✓]` (installed) or `[ ]` (not installed).

3. **👁️ Live Previews**  
   When you highlight a package, `fzf` runs `apt-cache show` in the background and displays version, section, size, top dependencies, and the description.

4. **⚡ Slash Commands**  
   Typing any `/command` in the search box triggers bulk operations instead of package selection. Packages are validated against `apt-cache` before any action runs.

5. **🔄 Action & Loop**  
   Pressing Enter shows a batch summary with install/remove categorization. Choose `y` to process, `d` for dry-run, `e` to export, or Enter to cancel. After processing, the store refreshes automatically.

---

## ⚙️ Configuration

> **Note:** `$PREFIX` is Termux's installation prefix, typically `/data/data/com.termux/files/usr`.

The entire script lives in a single file at `$PREFIX/bin/pkgs`. Edit it directly to customize behavior.

### 📐 Preview Window

| Setting | Default | Description |
|---|---|---|
| `PORTRAIT_SPLIT` | `down:48%:wrap` | Preview position/height in portrait mode |
| `LANDSCAPE_SPLIT` | `right:40%:wrap` | Preview position/width in landscape mode |

**Examples:**

```zsh
PORTRAIT_SPLIT="down:60%:wrap"    # Taller preview in portrait
LANDSCAPE_SPLIT="left:40%:wrap"    # Preview on the left in landscape
```

### 🎨 Colors

The `--color` flag in `_pkgs_build_fzf_args` uses 256-color ANSI codes. Customize any element:

```zsh
--color='fg:223,bg:-1,hl:114,fg+:223,bg+:235,hl+:109,info:109,prompt:180,pointer:203,marker:114,spinner:139,header:59'
```

See the [fzf documentation](https://github.com/junegunn/fzf#color-schemes) for available color slots.

### 🖌️ Message Colors

| Variable | Default | Description |
|---|---|---|
| `C_INST_PREFIX` | `[✓]` (green) | Tag for installed packages |
| `C_NOT_INST_PREFIX` | `[ ]` (dim) | Tag for not-installed packages |
| `C_PKG_NAME` | Green | Package name in list |
| `C_PKG_DESC` | Dim | Description in list |
| `C_MSG_INSTALL` | Green | Install success messages |
| `C_MSG_REMOVE` | Red | Remove/failure messages |
| `C_MSG_INFO` | Amber | Info/prompts |
| `C_MSG_WARN` | Amber | Warning messages |
| `C_MSG_DONE` | Teal | Completion messages |

### ⚡ Behavior

| Variable | Default | Description |
|---|---|---|
| `PKG_MGR` | `pkg` | Package manager command (`pkg` or `apt`) |
| `BORDER_STYLE` | `rounded` | fzf border style (`rounded`, `sharp`, `double`, `bold`) |

### 💡 Common Customizations

| If you want to... | Do this |
|---|---|
| Reinstall instead of install | Change `${PKG_MGR} install` → `${PKG_MGR} reinstall` |
| Log every action to a file | Add `echo "$(date): $action $pkg_name" >> ~/.pkgs_history` |
| Exclude library packages | Append `\| grep -vE '^(lib\|python-\|perl-\|ruby-)'` to the pipeline |
| Hide already-installed packages | Pipe through `grep -v '\[✓\]'` after the awk script |
| Use a floating overlay | Add `--height=80%` to `FZF_ARGS` |
| Hide preview by default | Change `--preview-window` to `...:hidden` (press `?` to toggle) |
| Keep search query across ops | Store the query before fzf exits and pass it back on re-entry |

---

## 🔍 Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `pkgs: command not found` | Script not in PATH | Run `which pkgs` — should show `$PREFIX/bin/pkgs`. Re-run `install.sh` if missing. |
| `zsh: no such file or directory` | Shebang path wrong | Run `head -1 $(which pkgs)` — should show `#!/data/data/com.termux/files/usr/bin/zsh`. Reinstall if corrupted. |
| Empty package list | `apt-cache` needs updating | Run `pkg update` and try again. |
| `fzf: command not found` | Dependency missing | Run `pkg install fzf`. |
| Colors look wrong | Terminal lacks 256-color support | Simplify the `--color` flag to basic 16-color ANSI codes. |
| Preview shows nothing | `apt-cache show` failed for that package | Try `apt-cache show <package>` manually to verify. |

---

## ❓ FAQ

**Q: Why does the store re-open after I install something?**  
A: The tool loops back so you can manage multiple packages in one session. Press `Esc` or `Ctrl+C` to quit.

**Q: Can I use `apt` instead of `pkg`?**  
A: Yes. Change `PKG_MGR="pkg"` → `PKG_MGR="apt"` in the config section.

**Q: Does this work outside Termux?**  
A: No. It depends on Termux-specific paths (`$PREFIX`) and tools (`pkg`, `apt-cache`, `dpkg-query`).

**Q: How do I update to the latest version?**  
A: Re-run the one-liner install command — it overwrites `$PREFIX/bin/pkgs`.

**Q: Can I contribute?**  
A: Absolutely! See [Contributing](#contributing).

---

## 🗑️ Uninstallation

```sh
rm "$PREFIX/bin/pkgs"           # Remove the script
rm -rf ~/.local/share/pkgs      # Remove history, notes, cache
rm -rf ~/.config/pkgs           # Remove filter/sort state
```

No other config files or shell modifications exist. Clean removal with no traces.

---

## 🤝 Contributing

Contributions are welcome! Every bug fix, feature, or documentation improvement helps.

```mermaid
flowchart LR
    A[Fork] --> B[Feature branch]
    B --> C[Make changes]
    C --> D[zsh -n pkgs_core.zsh]
    D --> E[Commit & push]
    E --> F[Open PR]
```

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feat/my-change`
3. **Make** your changes
4. **Verify**: `zsh -n pkgs_core.zsh` — checks for syntax errors
5. **Commit** with a descriptive message (e.g., `feat: add --dry-run flag`)
6. **Push** and open a pull request

Please follow the [Contributor Covenant](https://www.contributor-covenant.org/) code of conduct. Be kind, respectful, and keep discussions constructive.

---

## 📜 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of all changes.

---

## 📄 License

This project is licensed under the **MIT License**. See [LICENSE](https://github.com/Mark44928/Termux-TUI-Package-Store/blob/main/LICENSE) for full details.

---

## ⚠️ Disclaimer

This tool runs `pkg install` and `pkg remove` commands that modify your Termux environment. **Always review package names before confirming installations.** The authors are not responsible for any system damage resulting from misuse.

---

## 🙏 Acknowledgments

- [junegunn/fzf](https://github.com/junegunn/fzf) — the incredible fuzzy-finder that makes this tool possible
- The [Termux](https://termux.com/) community for maintaining an excellent Android terminal environment
- **Everyone** who has submitted issues, suggestions, or pull requests

---

## ⭐ Show Your Support

If Termux TUI Package Store makes your life easier, consider:

| Action | How |
|---|---|
| ⭐ **Star the repo** | Helps others discover the project |
| 🐛 **Report bugs** | Open an [issue](https://github.com/Mark44928/Termux-TUI-Package-Store/issues) |
| 🚀 **Contribute** | Submit a [pull request](https://github.com/Mark44928/Termux-TUI-Package-Store/pulls) |
| 📣 **Share it** | Tell your Termux-using friends |
| 💬 **Give feedback** | Ideas and suggestions are always welcome |

Every star, issue, and PR makes this project better. **Thank you!** 🙌

---

## 🔗 You Might Also Like

| Project | Description |
|---|---|
| [NoNameOS](https://github.com/Mark44928/NoNameOS) | Pure C++ hobbyist OS simulation |
| [Anti-Bloatware List](https://github.com/Mark44928/Anti-bloatware-list-for-Android-TV-Boxes-and-Sticks-for-rooted) | Debloat rooted Android TV boxes |

---

<p align="center">
  <b>Made with ❤️ for the Termux community</b>
  <br>
  <sub>v1.4.0 · MIT Licensed · PRs Welcome</sub>
</p>
