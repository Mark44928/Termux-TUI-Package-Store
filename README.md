<p align="center">
  <img src="assets/pkgs.png" alt="Termux TUI Package Store interface showing a split-panel layout with a searchable package list on the left and package metadata preview on the right" width="700">
</p>

<p align="center">
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/releases">
    <img src="https://img.shields.io/github/v/release/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=blue" alt="Release">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/stargazers">
    <img src="https://img.shields.io/github/stars/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=yellow" alt="Stars">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=green" alt="License">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
    <img src="https://img.shields.io/github/repo-size/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=orange" alt="Repo Size">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/issues">
    <img src="https://img.shields.io/github/issues/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=red" alt="Issues">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store/pulls">
    <img src="https://img.shields.io/github/issues-pr/Mark44928/Termux-TUI-Package-Store?style=for-the-badge&color=blueviolet" alt="PRs">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
    <img src="https://img.shields.io/badge/maintained-yes-brightgreen?style=for-the-badge" alt="Maintained">
  </a>
  <a href="https://github.com/Mark44928/Termux-TUI-Package-Store">
    <img src="https://img.shields.io/badge/PRs-welcome-orange?style=for-the-badge" alt="PRs Welcome">
  </a>
</p>

<h1 align="center">Termux TUI Package Store 📦</h1>

<p align="center">
  <em>An interactive, fzf-powered package browser for Termux — search, preview, install, and remove packages without typing individual package-manager commands.</em>
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

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Install](#quick-install)
- [Manual Installation](#manual-installation)
- [Usage](#usage)
- [Key Bindings](#key-bindings)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Uninstallation](#uninstallation)
- [Contributing](#contributing)
- [License](#license)
- [Disclaimer](#disclaimer)
- [Acknowledgments](#acknowledgments)

---

## Overview

Termux TUI Package Store is a high-performance terminal interface for managing packages on Termux. It wraps `pkg` (Termux's package manager) with an interactive fuzzy-finder that lets you search, preview, install, and remove packages in a single keystroke.

The tool adapts to your terminal size, color-codes installed vs. available packages, and shows live metadata previews — version, size, dependencies, and description — for every package you highlight.

---

## Features

| Feature | Description |
|---|---|
| **🔍 Fuzzy Search** | Filter hundreds of packages instantly as you type |
| **📋 Live Previews** | See version, size, dependencies, and description for any package |
| **🔄 Persistent Session** | Store stays open after install/remove — keep going until you press Esc |
| **📐 Smart Layout** | Automatically switches between landscape (side-by-side) and portrait (stacked) preview |
| **🎨 Color-Coded Status** | Installed packages tagged `[I]`, available packages tagged `[-]` |
| **⚡ Slash Commands** | Type `/install <query>`, `/remove <query>`, `/export <query>`, or `/upgrade` in the search box |
| **🛡️ Prerequisite Checks** | Validates fzf and package manager tools on startup |
| **⚡ Zero Config** | Works out of the box — no config files or shell integration required |

---

## Requirements

- **Termux** (Android 7+) — [Get it from F-Droid](https://f-droid.org/en/packages/com.termux/) or GitHub
- **Zsh** — the script runs on zsh
- **Runtime dependencies** (installed automatically by the installer):

| Package | Purpose | Required |
|---|---|---|
| `fzf` | Fuzzy-finder interface | Yes |
| `gawk` | Data processing (package list generation) | Yes |
| `coreutils` | `numfmt` for human-readable size formatting | Yes |
| `cowsay` | Fun status messages when a package has no dependencies | No |
| `grep`, `sed` | Text processing in previews | Yes |
| `ncurses` | Terminal handling (`tput`) | Yes |
| `curl` | Downloading the script during installation | Yes |

> **Note:** Tested on Termux v0.118.x with fzf 0.53.0. Older versions may work but are not guaranteed.

---

## Quick Install

```sh
zsh <(curl -fsSL https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/main/install.sh)
```

> **Note:** If `zsh` is not your current shell, run `bash` instead of `zsh` in the command above. The installer will set everything up regardless.

---

## Manual Installation

1. **Install dependencies:**

   ```sh
   pkg update && pkg upgrade
   pkg install zsh fzf cowsay coreutils gawk grep sed ncurses curl
   ```

2. **Download the script and make it executable:**

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/main/pkgs_core.zsh -o $PREFIX/bin/pkgs
   chmod +x $PREFIX/bin/pkgs
   ```

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

Type these directly in the search box:

| Command | Description |
|---|---|
| `/upgrade` | Upgrade all installed packages |
| `/install <query>` | Install all packages matching `<query>` |
| `/remove <query>` | Remove all packages matching `<query>` |
| `/export <query>` | Export matching packages to a runnable shell script |

Examples:
- `/install python` — installs all packages with "python" in the name
- `/remove vim` — removes all matching packages
- `/export git` — saves matching packages to `pkg-install-*.sh`

---

## Key Bindings

| Key | Action |
|---|---|
| `Enter` | Install or remove the selected package |
| `Tab` | Select multiple packages (when `--multi` is enabled) |
| `?` | Toggle the preview pane |
| `Esc` or `Ctrl+C` | Exit the store |
| Typing | Search/filter packages in real time |

---

## How It Works

1. **Layout Detection**  
   The tool measures your terminal with `tput` and decides whether to show the preview alongside the package list (wide terminals) or below it (narrow terminals).

2. **Package Discovery**  
   An `awk` script reads installed packages from `dpkg-query`, then merges them with every available package from `apt-cache search`. Each line is tagged `[I]` (installed) or `[-]` (available).

3. **Live Previews**  
   When you highlight a package, `fzf` runs `apt-cache show` in the background and displays version, section, size, top dependencies, and the description.

4. **Action & Loop**  
   Pressing Enter triggers `pkg install` or `pkg remove`. When the command finishes, the store refreshes the package list and re-opens — no need to relaunch.

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
--color='fg:250,bg:-1,hl:063,fg+:231,bg+:235,hl+:063,info:144,prompt:161,pointer:045,marker:118,spinner:135,header:087'
```

See the [fzf documentation](https://github.com/junegunn/fzf#color-schemes) for available color slots.

### Behavior

| Variable | Default | Description |
|---|---|---|
| `PKG_MGR` | `pkg` | Package manager command (`pkg` or `apt`) |
| `BORDER_STYLE` | `rounded` | fzf border style (`rounded`, `sharp`, `double`, `bold`) |

### Common Customizations

- **Reinstall instead of install:** Change `${PKG_MGR} install "$pkg_name"` to `${PKG_MGR} reinstall "$pkg_name"`.
- **Confirm before acting:** Wrap the install/remove line with a `read -q` prompt.
- **Log every action:** Add `echo "$(date): $action $pkg_name" >> ~/.pkgs_history` inside the loop.
- **Exclude library packages:** Append `| grep -vE '^(lib|python-|perl-|ruby-)'` to the `_pkgs_generate_list` pipeline.
- **Hide already-installed packages:** Pipe through `grep -v '\[I\]'` after the awk script.
- **Floating overlay:** Add `--height=80%` to `FZF_ARGS` for a non-fullscreen view.
- **Multi-select:** Add `--multi` to `FZF_ARGS` to select multiple packages with Tab.
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
rm $PREFIX/bin/pkgs
```

That's it. No config files, no sourced shell lines, no lingering data.

---

## Contributing

Contributions are welcome! Whether it's a bug fix, a new feature, or improved documentation:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feat/my-change`).
3. Make your changes.
4. Run `shellcheck install.sh` if you modified the installer. (Note: `shellcheck` does not support zsh syntax natively; test zsh scripts manually.)
5. Commit with a descriptive message (e.g., `feat: add --dry-run flag`).
6. Push and open a pull request.

Please follow the [Contributor Covenant](https://www.contributor-covenant.org/) code of conduct. Be kind, be respectful, and keep discussions constructive.

---

## License

This project is licensed under the **MIT License**. See [LICENSE](https://github.com/Mark44928/Termux-TUI-Package-Store/blob/main/LICENSE) for details.

---

## Disclaimer

This tool runs `pkg install` and `pkg remove` commands with elevated privileges within the Termux environment. Always review package names before confirming installations. The authors are not responsible for any system damage resulting from misuse.

---

## Acknowledgments

- [junegunn/fzf](https://github.com/junegunn/fzf) — the incredible fuzzy-finder that makes this tool possible
- The [Termux](https://termux.com/) community for maintaining an excellent Android terminal environment
- Everyone who has submitted issues, suggestions, or pull requests

---

## Show Your Support

If Termux TUI Package Store makes your Termux life easier, consider:

| | |
|---|---|
| ⭐ | **Star the repo** — it helps others discover the project |
| 🐛 | **Report bugs** — open an [issue](https://github.com/Mark44928/Termux-TUI-Package-Store/issues) |
| 🔧 | **Contribute** — submit a [pull request](https://github.com/Mark44928/Termux-TUI-Package-Store/pulls) |
| 📢 | **Share it** — tell your Termux-using friends |
| 💬 | **Give feedback** — ideas and suggestions are always welcome |

Every star, issue, and PR makes this project better. Thank you!

---

<p align="center">
  Made with ❤️ for the Termux community
</p>
