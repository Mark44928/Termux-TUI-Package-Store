# Changelog

All notable changes to Termux TUI Package Store are documented here.

## [Unreleased]

### Added
- `/note <pkg> <text>` — Add/view package notes (persisted in `~/.local/share/pkgs/notes`)
- `/compare <a> <b>` — Side-by-side package comparison (version, section, size, description)
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
- README updated with all 21 slash commands documented

## [1.1.0] - 2026-07-10

### Added
- Initial release
- Fuzzy search with live previews
- 21 slash commands
- Persistent session with smart layout
- Color-coded installed/available status
- Batch operations with multi-select
- Configuration via environment variables
