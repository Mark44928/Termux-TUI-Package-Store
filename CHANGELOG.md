<p align="center">
   <b>Changelog</b>
</p>

<p align="center">
   <em>All notable changes to Termux TUI Package Store are documented here.</em>
</p>

---

## [1.5.0] - 2026-07-24

### Added
- `/config` — In-TUI settings editor (theme, filter, sort, compact mode, history retention)
- `/queue` — View and process persistent package queue
- `/queue-add <pkg>` — Add packages to install queue
- `/queue-remove <pkg>` — Remove packages from queue
- `/queue-clear` — Clear all queued packages
- Animated spinners during `/upgrade` and `/update` operations
- Package count display in fzf border label `[installed]`/`[available]`/`[by size]`
- Back navigation (`b` key) in `/info` and `/deptree` screens
- Download/install size estimate before batch install confirmation
- Network connectivity check before `/update` and `/upgrade`

### Changed
- Total slash commands: 135 → 140
- Network check uses `packages.termux.dev` (Termux mirror) instead of `archive.ubuntu.com`
- All temp files now use `$TMPDIR` instead of hardcoded `/tmp`
- Queue persistence stored at `~/.local/share/pkgs/queue`

### Fixed
- `/upgrade` and `/update` spinner was broken — missing `&` to background the process
- `$ret` variable referenced before definition in fzf main loop (mktemp failure path)
- `_pkgs_check_network` used `ping -W` flag which is not supported in Termux toybox ping
- Temp files in spinners used hardcoded `/tmp` instead of `$TMPDIR`
- Queue save now uses atomic temp-file + mv pattern
- `_pkgs_spinner` unquoted `$pid` — added guard and proper quoting
- `/history` hardcoded 7-day retention — now uses `_PKGS_HISTORY_KEEP_DAYS`
- `/compact` not wired to fzf — now toggles `height_arg` in `FZF_ARGS`
- `/unused` parsed raw HISTFILE — now uses `fc -l1` for Zsh compatibility
- `/batch-upgrade` missing network check — now calls `_pkgs_check_network`
- `/keys` help text typo "Keybing" — fixed to "Keybinding"
- `/schedule` and `/auto-clean` help text now note cronie dependency

## [1.4.0] - 2026-07-20

### Added
- `/profile` — Save/restore named package profiles (save, restore, list, delete)
- `/check-deps` — Scan project directory for missing tools/packages
- `/shell-hook` — Auto-generate zsh aliases from installed packages
- `/storage-report` — Android-aware storage breakdown with quota estimates
- `/health` — System health score (0-100) with prioritized fix list
- `/auto-clean` — Set up scheduled cleanup via cronie
- `/footprint <pkg>` — Total disk cost including all transitive dependencies
- `/unused` — Find installed packages you never actually invoke
- `/timeline` — Visual heatmap of install/upgrade activity
- `/schedule` — Set up update reminders via termux-notification
- `/search-providers <cmd>` — Find which packages provide a command
- `/diff-snapshots` — Color-coded diff between two saved snapshots
- `/audit` — Scan for SUID/SGID binaries and world-writable files
- `/repo-check` — Flag packages from non-official/untrusted repos
- `/popular` — Curated list of popular Termux packages
- `/boot-time` — Benchmark Termux cold-start time with optimization tips
- `/disk-pressure` — Storage pressure monitor with days-till-full estimate
- `/pkg-impact <pkg>` — Pre-install impact analysis (deps, sizes, conflicts)

### Changed
- Refactored 18 copy-pasted fzf picker patterns into `_pkgs_fzf_pick_pkg` helper
- Performance: `/outdated`, `/security`, `/manually-installed`, `/auto-installed`, `/upgradable` now use bulk apt-cache calls instead of per-package subprocess spawning
- Improved `CONTRIBUTING.md` with coding style guide and testing instructions

### Fixed
- `install.sh`: SHA256 checksum verification is now mandatory (aborts if unavailable)
- `pkgs -v` now correctly displays version number (variable was used before declaration)
- `/snap-install`: Now validates both original path and symlink target to prevent symlink attacks
- `_pkgs_validate_export_path`: Now blocks `.ssh`, `.gnupg`, `/proc`, `/sys`, `/dev` paths
- `/search-history`: Uses `grep -Fi` for literal matching instead of regex

### Security
- Added CI/CD workflows: syntax check on PRs, auto-generate SHA256 checksum on push to main

## [1.3.0] - 2026-07-16

### Added
- `/mirror` — Switch apt mirror
- `/fav <pkg>` — Toggle package favorite
- `/fav-list` — Show all favorites
- `/fav-remove` — Remove a favorite
- `/import <file>` — Install from package list file
- `/why <pkg>` — Show why a package is installed
- `/suggest <pkg>` — Show recommended packages
- `/nuke` — Interactive storage cleanup
- `/whatsnew` — Show recent upgrade changelogs
- `/tips` — Termux tips and tricks
- `/self-update` — Update pkgs from GitHub
- `/search-size <min> <max>` — Find packages by size range
- `/pkg-history <pkg>` — Per-package install/upgrade/remove history
- `/depends-chain <a> <b>` — Show dependency chain between two packages
- `/broken` — Find broken/half-installed packages
- `/conflicts-with <pkg>` — Show conflicting packages
- `/provides <pkg>` — Show virtual packages provided
- `/manually-installed` — Show only manually installed packages
- `/auto-installed` — Show only auto-installed packages
- `/upgrade-plan` — Simulate upgrade, show what would change
- `/pkg-ages` — Show age of each installed package
- `/unused-libs` — Find orphaned .so libraries
- `/maintainer <name>` — Search packages by maintainer
- `/log-search <text>` — Search dpkg/apt history logs
- `/mirror-backup` — Backup/restore sources.list snapshots
- `/size-histogram` — Visual package size distribution
- `/deptree <pkg>` — Visual ASCII dependency tree with box drawing
- `/reverse-tree <pkg>` — Reverse dependency tree
- `/upgrade-size` — Total download size before upgrading
- `/download <pkg>` — Download package without installing
- `/verify <pkg>` — Verify package checksums/integrity
- `/mirror-latency` — Ping-test all mirrors, rank by latency
- `/mirror-bandwidth` — Bandwidth-test mirrors, rank by speed
- `/pkg-changes` — Show what changed in last apt upgrade
- `/pkg-recommendations <pkg>` — Show who recommends this package
- `/pkg-suggests <pkg>` — Show who suggests this package
- `/pkg-breaks <pkg>` — Show what breaks if this is installed
- `/pkg-replaces <pkg>` — Show what this package replaces
- `/owner <file>` — Which package owns this file (dpkg -S)
- `/removed` — Packages removed in last upgrade
- `/new-pkgs` — Packages installed this week
- `/same-size` — Packages with identical installed size
- `/depends-on-list <pkgs>` — Shared dependencies of multiple packages
- `/upgradable` — Upgradable packages with version diff
- `/whatprovides <file>` — Find which package provides a binary
- `/snap-install <file>` — Install from local .deb file
- `/simulate-remove <pkg>` — Simulate removal, show consequences
- `/repo-stats` — Packages per repository breakdown
- `/download-est <pkg>` — Download + installed size with expansion ratio
- `/diff <pkg>` — Changelog diff of last upgrade
- 7 theme color schemes: dark, light, minimal, neon, dracula, monokai, solarized
- `/theme` — Switch color scheme (persisted across sessions)
- `_PKGS_FAVORITES_FILE` — Persistent favorites storage
- `_PKGS_CONFIG_FILE` — Theme and filter persistence
- `_PKGS_SELF_URL` — Configurable self-update URL

### Fixed
- Batch 2 features (14 commands) were outside main while loop — dead code that never executed. Moved inside loop.
- All paths now use `$PREFIX` — no hardcoded `/var` paths (Termux compatibility)
- Removed hardcoded box deco from `_pkgs_show_info()` (was `┌───┐│└───┘`)
- `echo` with flag replaced by `printf` for portable output

### Changed
- Total slash commands: 47 → 100
- Help text updated in both in-app (`/help`) and CLI (`pkgs -h`)
- README updated with all 100 commands

---

## [1.2.0] - 2026-07-15

### Added
- `/deps <pkg>` — Show what a package depends on
- `/tree <pkg>` — Show full dependency tree
- `/orphans-safe` — Show safe orphans (no essential dependents)
- `/orphans-remove` — Remove all orphaned packages
- `/export-all` — Export all installed packages to a shell script
- `/purge <pkg>` — Remove package + config files
- `/hold <pkg>` — Pin package (prevent upgrade)
- `/unhold <pkg>` — Unpin package (allow upgrade)
- `/depends-on <pkg>` — Show installed packages that depend on this
- `/outdated` — Show packages with available updates
- `/outdated-top <n>` — Top N packages with updates by size
- `/review` — Today's activity summary
- `/stats` — Today's install/remove counts
- `/changelog <pkg>` — Show package changelog
- `/reinstall <pkg>` — Reinstall a package
- `/search-file <text>` — Search installed files by name
- `/download-size <pkg>` — Show download + installed size
- `/check` — Verify installed package integrity
- `/group` — Group packages by section
- `/version` — Show system version info
- `/usage-top` — Disk usage bar chart (top packages)
- Persistent filter/sort state (`~/.config/pkgs/config`)
- Log rotation (30-day retention, configurable via `_PKGS_HISTORY_KEEP_DAYS`)
- Preview panel expanded to 12 sections (description, deps, size, files, reverse deps, etc.)

### Fixed
- `_pkgs_validate_name` regex now requires leading alpha character
- `/note` path blocks grep regex injection
- `readlink -f` fallback now rejects on failure
- `/restore` path validation via `_pkgs_validate_export_path`
- All `xargs` trimming replaced with `_pkgs_trim()` helper
- All `dpkg`/`apt-cache` calls use `--` argument separator (13+ call sites)
- `/tree` captures `apt-cache depends --recurse` once (was called twice)
- `/undo` returns on non-undoable actions
- Layout re-detected every loop iteration
- `/export-all` zero packages edge case handled
- Standardized all "Press Enter to return" prompts
- `/info` box truncation fixed
- Preview: removed stray `'` on `head -8'` (caused `zsh:101: unmatched '`)
- Preview: `dpkg -L` and `apt-cache rdepends` called once (were called twice)
- Preview: switched from `echo '...'` to `cat <<'PREVIEW_EOF'` heredoc
- Preview: removed dead `priority`/`section` variable extractions
- `/usage-top` unreachable due to `/usage*` catch-all (now excluded)
- `/depends-on` unreachable due to `/deps*` catch-all (now excluded)
- Duplicate `/history` handler removed
- `exit 0` changed to `return 0` when sourced (prevents killing shell)
- Path traversal check fixed for paths with spaces
- `_pkgs_invalidate_cach...` parse error fixed (stray `fi` in `/unhold`)
- `/unhold` handler: missing `fi` for `if ! dpkg -s` block fixed

### Changed
- `_pkgs_apt_field` rewritten as pure zsh (3 subprocesses→0)
- `_pkgs_parse_pkg_arg` wired into 11 handlers (`/deps`, `/tree`, `/purge`, `/hold`, `/unhold`, `/depends-on`, `/changelog`, `/reinstall`, `/download-size`, `/rdeps`, `/info`)
- `_pkgs_format_size` helper eliminates 8 duplicated numfmt blocks
- `/usage` and `/group` section lookup uses single `apt-cache dump` (was O(n) `apt-cache show`)
- `/search-file` validation simplified (text, not package name)
- `/install` and `/remove` slash commands now show confirmation before processing
- `/restore` now parses both plain lists and shell scripts from `/export`
- `/clean` now uses single confirmation for both autoremove and cache clean
- Signal trap includes HUP
- Help updated with all 100 commands
- install.sh: aborts on dependency failure, validates REPO/BRANCH env vars, verifies download integrity
- Cache generation separated from fzf subshell (fixes resource leak)

---

## [1.1.0] - 2026-07-10

### Added
- `/note <pkg> <text>` — Add/view package notes (persisted in `~/.local/share/pkgs/notes`)
- `/recent` — Filter packages installed today (via dpkg log)
- `/usage` — Disk usage breakdown by section with visual bar charts
- `/backup` — Export full package list to a `.txt` file (with notes backup)
- `/restore <file>` — Install packages from a backup file with progress
- `Ctrl-A` / `Ctrl-D` — Select all / deselect all visible packages in multi-select mode
- Auto-clean after remove — Prompts to run `autoremove` when orphaned deps exist
- Dry-run preview (`d` option) — Shows dep counts for installs, reverse dep counts for removals
- Batch export (`e` option) — Categorized summary with `.sh` script generation
- Usage messages on bare `/install`, `/remove`, `/export` commands

### Fixed
- Multi-select exit bug — Enter without selection no longer exits the app
- Batch confirm/cancel logic was inverted (`!= "y"` → `== "y"`)
- `/note` — Replaced sed-based update with temp-file loop to avoid regex issues
- `/clean` — Fixed error handling when dpkg lock prevents `autoremove` check
- `/compare` — Fixed argument validation (was rejecting valid 2-arg commands)
- Bare `/install` silently did nothing — Now shows usage message

### Changed
- Multi-select processing rewritten with batch confirmation
- Post-processing flow: "Press Enter to exit" → "Press Enter to return" (continues loop)
- README updated with all 24 slash commands documented

---

## [1.0.0] - 2026-07-09

### Added
- Initial release of Termux TUI Package Store
- Interactive fzf-powered package browser with live preview
- Slash commands: `/upgrade`, `/install`, `/remove`, `/export`, `/info`, `/search`, `/rdeps`, `/compare`, `/orphans`, `/top`, `/size`, `/count`, `/update`, `/clean`, `/installed`, `/available`, `/all`, `/sort`, `/history`, `/undo`, `/help`
- Persistent session loop (re-opens after operations)
- Auto-install of dependencies (fzf, pkg, apt-cache, dpkg-query)
- Layout detection (portrait/landscape) based on terminal size
- Package list with `[✓]`/`[ ]` installed status tags
- Preview panel with version, section, size, deps, and description
- Batch operations with dry-run and export options
