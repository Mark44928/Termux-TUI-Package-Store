# 📖 Slash Commands Reference

**140+ unique slash commands** available inside the pkgs TUI. Type `/help` in the search box to see them in-app, or browse them here.

---

## 📦 Package Operations

| Command | Description |
|---|---|
| `/install <query>` | Install all packages matching `<query>` |
| `/remove <query>` | Remove all packages matching `<query>` |
| `/purge <pkg>` | Remove package + config files |
| `/reinstall <pkg>` | Reinstall a package |
| `/hold <pkg>` | Pin package (prevent upgrade) |
| `/unhold <pkg>` | Unpin package (allow upgrade) |
| `/upgrade` | Upgrade all installed packages |
| `/batch-upgrade` | Interactive fzf multi-select of upgradable packages |
| `/update` | Update apt cache |
| `/clean` | Remove orphans + clean apt cache |
| `/auto-clean` | Set up scheduled cleanup via cronie (requires `cronie` + `crond`) |
| `/export <query>` | Export matching packages to a runnable shell script |
| `/export-all` | Export all installed packages to a script |
| `/export-versions` | Export package list with version numbers + sizes |

## 📋 Queue System

| Command | Description |
|---|---|
| `/queue-add <pkg>` | Add a package to the install queue |
| `/queue-remove <pkg>` | Remove a package from the queue |
| `/queue` | View queue, process (y), dry-run (d), or clear (r) |
| `/queue-clear` | Clear all queued packages |

The queue persists across sessions at `~/.local/share/pkgs/queue`. Add packages with `/queue-add`, then run `/queue` to review and process them all at once.

## 🔍 Search & Filter

| Command | Description |
|---|---|
| `/search <text>` | Search package descriptions (not just names) |
| `/search-file <text>` | Search installed files by name |
| `/search-size <min> <max>` | Find packages by size range (KiB) |
| `/search-providers <cmd>` | Find packages providing a command/binary |
| `/search-history <text>` | Search operation history |
| `/installed` | Filter: show only installed packages |
| `/available` | Filter: show only available packages |
| `/recent` | Filter: show only packages installed today |
| `/all` | Reset filter: show all packages |
| `/sort name` or `/sort size` | Sort packages by name or size |
| `/size-filter <min> <max>` | Filter by installed size (KiB) |
| `/compact` | Toggle compact fzf mode |
| `/size` | Total installed size |
| `/count` | Count installed/available packages |
| `/group` | Group packages by section |
| `/upgradable` | Upgradable packages with version diff |
| `/size-histogram` | Visual package size distribution |

## 📊 Information & Analysis

| Command | Description |
|---|---|
| `/info <pkg>` | Full package details in a panel |
| `/deps <pkg>` | What a package depends on |
| `/rdeps <pkg>` | Reverse dependencies (what depends on this) |
| `/depends-on <pkg>` | Installed packages that depend on this |
| `/depends-chain <a> <b>` | Dependency chain between two packages |
| `/depends-on-list <pkgs>` | Shared dependencies of multiple packages |
| `/tree <pkg>` | Show dependency tree |
| `/deptree <pkg>` | Visual ASCII dependency tree |
| `/reverse-tree <pkg>` | Reverse dependency tree |
| `/dep-graph <pkg>` | ASCII dependency tree (3 levels, circular detection) |
| `/fuzzy-dep` | Interactive dependency explorer |
| `/compare <pkg1> <pkg2>` | Side-by-side field comparison + dep overlap |
| `/why <pkg>` | Show why a package is installed |
| `/suggest <pkg>` | Show suggested/recommended/depending packages |
| `/pkg-recommendations <pkg>` | Who recommends this package |
| `/pkg-suggests <pkg>` | Who suggests this package |
| `/pkg-breaks <pkg>` | What breaks if this is installed |
| `/pkg-replaces <pkg>` | What this package replaces |
| `/conflicts-with <pkg>` | Show conflicting packages |
| `/provides <pkg>` | Show virtual packages provided |
| `/broken` | Find broken packages via dpkg --audit |
| `/manually-installed` | Show manually installed packages with size |
| `/auto-installed` | Show auto-installed packages with parent |
| `/owner <file>` | Which package owns this file (dpkg -S) |
| `/whatprovides <file>` | Which package provides a binary |
| `/check` | Verify installed packages integrity |
| `/check-deps` | Scan project for missing tool dependencies |
| `/missing` | Check for missing dependencies |
| `/footprint <pkg>` | Total install footprint including deps |
| `/pkg-impact <pkg>` | Pre-install impact analysis (new deps, disk cost) |

## 🕐 History & Activity

| Command | Description |
|---|---|
| `/history` | View last 7 days of operation log |
| `/activity-log [days]` | Activity summary with per-action counts |
| `/review` | Today's activity summary |
| `/stats` | Today's install/remove counts |
| `/pkg-history <pkg>` | Per-package install/upgrade/remove history |
| `/pkg-changes` | What changed in last apt upgrade |
| `/pkg-ages` | Age of each installed package |
| `/changelog <pkg>` | Package changelog |
| `/diff <pkg>` | Changelog diff of last upgrade |
| `/whatsnew` | Recent upgrade changelogs |
| `/timeline` | Visual install/upgrade activity map |
| `/undo` | Reverse last install or remove |
| `/removed` | Packages removed in last upgrade |
| `/new-pkgs` | Packages installed this week |

## 🛠️ Maintenance & Cleanup

| Command | Description |
|---|---|
| `/orphans` | Show orphaned packages |
| `/orphans-safe` | Safe orphans (no essential dependents) |
| `/orphans-remove` | Remove all orphaned packages |
| `/outdated` | Packages with available updates |
| `/outdated-top <n>` | Top N packages with updates by size |
| `/top [n]` | Top N largest installed packages (default: 10) |
| `/usage` | Disk usage breakdown by section |
| `/usage <pkg>` | Installed files for a package |
| `/usage-top` | Disk usage bar chart (top packages) |
| `/storage-report` | Detailed storage consumption report |
| `/disk-pressure` | Storage pressure estimate + days-till-full |
| `/nuke` | Interactive storage cleanup |
| `/unused-libs` | Find orphaned .so libraries |
| `/unused` | Find installed packages never invoked |
| `/duplicate` | Find duplicate/virtual packages |
| `/same-size` | Packages with identical installed size |
| `/security` | Check for outdated packages |
| `/audit` | Scan for SUID/SGID + world-writable files |
| `/repo-check` | Flag packages from untrusted repos |
| `/repo-stats` | Packages per repository breakdown |
| `/health` | Full system health check |
| `/cache-stats` | Cache + stats dashboard |
| `/backup` | Export full package list to a file |
| `/restore <file>` | Install all packages from a backup file |
| `/snapshot` | Save installed package snapshot |
| `/snapshot-list` | List saved snapshots |
| `/snapshot-restore` | Restore from a snapshot |
| `/diff-snapshots` | Diff two saved snapshots |

## 🔗 Mirror & Repository

| Command | Description |
|---|---|
| `/mirror` | Switch apt mirror |
| `/mirror-backup` | Backup/restore sources.list snapshots |
| `/mirror-latency` | Ping-test mirrors, rank by latency |
| `/mirror-bandwidth` | Bandwidth-test mirrors, rank by speed |

## ⭐ Favorites & Profiles

| Command | Description |
|---|---|
| `/fav <pkg>` | Toggle package favorite |
| `/fav-list` | Show all favorites |
| `/fav-remove` | Remove a favorite |
| `/profile` | Switch between named package profiles |
| `/import <file>` | Install from package list file |
| `/quick` | Quick install popular package sets |
| `/popular` | Curated list of popular Termux packages |

## 📝 Notes & Docs

| Command | Description |
|---|---|
| `/note <pkg> <text>` | Add or view a note for a package |
| `/tips` | Termux tips and tricks |
| `/maintainer <name>` | Search packages by maintainer |
| `/log-search <text>` | Search dpkg/apt history logs |

## ⚙️ System & Utilities

| Command | Description |
|---|---|
| `/version` | Show system version info |
| `/config` | Edit settings in-app (theme, filter, sort, compact, history) |
| `/theme` | Switch color scheme (7 themes) |
| `/theme-preview` | Preview current color scheme |
| `/keys` | Fzf keybinding reference overlay |
| `/boot-time` | Benchmark Termux shell startup time |
| `/schedule` | Set up update reminders (requires `termux-api` + cronie for auto-trigger) |
| `/shell-hook` | Generate shell integration hook |
| `/self-update` | Update pkgs from GitHub |
| `/plan <cmd>` | Dry-run preview (install/remove/upgrade) |
| `/upgrade-plan` | Simulate upgrade, show what would change |
| `/upgrade-size` | Total download size before upgrading |
| `/download <pkg>` | Download without installing |
| `/download-size <pkg>` | Download + installed size |
| `/download-est <pkg>` | Download + installed size + expansion ratio |
| `/verify <pkg>` | Verify package checksums/integrity |
| `/simulate-remove <pkg>` | Simulate removal, show consequences |
| `/snap-install <file>` | Install from local .deb file |
| `/help` | Show in-app help |
