<p align="center">
   <b>Changelog</b>
</p>

<p align="center">
   <em>All notable changes to Termux TUI Package Store are documented here.</em>
</p>

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
- `/download-size <pkg>` — Show download size
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
- `/tree` captures `apt-cache depends --recurserve` once (was called twice)
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
- Help updated with all 47 commands
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
