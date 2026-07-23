#!/usr/bin/env zsh
set -eu
set -o pipefail

export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}

# ── Terminal colors (defined early for lock/pre-flight errors) ─
BOLD=$(tput bold 2>/dev/null || printf '')
RESET=$(tput sgr0 2>/dev/null || printf '')
GREEN=$(tput setaf 2 2>/dev/null || printf '')
YELLOW=$(tput setaf 3 2>/dev/null || printf '')
RED=$(tput setaf 1 2>/dev/null || printf '')
CYAN=$(tput setaf 6 2>/dev/null || printf '')
MAGENTA=$(tput setaf 5 2>/dev/null || printf '')
DIM=$(tput dim 2>/dev/null || printf '')

# ── Pre-flight ──────────────────────────────────────────────
if [ -z "$PREFIX" ]; then
  echo "${RED}  ✖ This installer is designed for Termux.${RESET}"
  echo "${YELLOW}  Please run this script inside Termux on Android.${RESET}"
  exit 1
fi

# ── Lock helpers ────────────────────────────────────────────
_is_alive() {
  [ -f "$1" ] || return 1
  local pid
  pid=$(head -1 "$1" 2>/dev/null) || return 1
  [ -z "$pid" ] && return 1
  kill -0 "$pid" 2>/dev/null || return 1
  local age
  age=$(($(date +%s 2>/dev/null || echo 0) - $(stat -c %Y "$1" 2>/dev/null || echo 0)))
  [ "$age" -lt 3600 ] 2>/dev/null || return 1
  return 0
}

cleanup() {
  rm -f "${INSTALL_PATH:-}.tmp" 2>/dev/null
  rm -f "${LOCKFILE:-}" 2>/dev/null
}
trap cleanup EXIT INT TERM HUP QUIT PIPE

# ── Lock ────────────────────────────────────────────────────
LOCKFILE="${TMPDIR:-/tmp}/pkgs-install.lock"
if [ -f "$LOCKFILE" ] && _is_alive "$LOCKFILE"; then
  echo "${RED}  ✖ Another installation is already running.${RESET}"
  exit 1
fi
mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null || true
printf '%s\n' "$$" > "$LOCKFILE"

# ── Spinner ─────────────────────────────────────────────────
# run_with_spinner <title> <cmd...>
# Runs a command with a spinner. Exits with the command's exit code.
run_with_spinner() {
  local title=$1; shift
  if _gum; then
    gum spin --spinner dot --spinner.foreground 6 --title "$title" -- "$@"
    return $?
  else
    local exit_code=0
    "$@" &
    wait $! || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
      echo "  ✔ $title"
    else
      echo "  ✖ $title failed"
    fi
    return "$exit_code"
  fi
}

echo

# ── Gum helpers ──────────────────────────────────────────────
USE_GUM=1  # default on; refined after gum install attempt

_gum() {
  [[ "$USE_GUM" == "1" ]] && command -v gum >/dev/null 2>&1
}

box() {  # box <color> <text...>
  local c=$1; shift
  if _gum; then
    gum style --border rounded --border-foreground "$c" --padding "0 2" "$@"
  else
    echo "$@"
  fi
}

boxf() {  # boxf <color> <text...>
  local c=$1; shift
  if _gum; then
    gum style --border rounded --border-foreground "$c" --padding "0 2" --faint "$@"
  else
    echo "$@"
  fi
}

header() {  # header <text...>
  if _gum; then
    gum style --border rounded --border-foreground 6 --bold --padding "0 2" "$@"
  else
    echo "${CYAN}  ┌────────────────────────────────────────┐${RESET}"
    echo "${CYAN}  │${RESET}  ${BOLD}$1${RESET}                                  ${CYAN}│${RESET}"
    echo "${CYAN}  └────────────────────────────────────────┘${RESET}"
  fi
}

ok() {
  if _gum; then
    gum log --formatter text --message.foreground 2 -- "✔ $1"
  else
    echo "  ${GREEN}✔${RESET} $1"
  fi
}

err() {
  if _gum; then
    gum log --formatter text --message.foreground 1 -- "✖ $1"
  else
    echo "  ${RED}✖${RESET} $1"
  fi
}

warn() {
  if _gum; then
    gum log --formatter text --message.foreground 3 -- "⚠  $1"
  else
    echo "  ${YELLOW}⚠  $1${RESET}"
  fi
}

header "⚡ Pre-flight check"
ok "Termux detected at ${CYAN}${BOLD}$PREFIX${RESET}"
echo

header "📦 Installing dependencies"
run_with_spinner "Updating and installing packages" sh -c '
  set +e
  pkg update -y
  pkg install -y zsh fzf coreutils gawk grep sed ncurses curl figlet --
' || {
  err "Dependency installation failed. Aborting."
  exit 1
}

# Install gum (Go binary) if not present
if ! command -v gum >/dev/null 2>&1; then
  warn "gum not found; skipping auto-install (install manually with pkg install gum or from source if desired)."
  USE_GUM=0
fi

missing=''
for cmd in fzf awk zsh curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing="$missing $cmd"
  fi
done
if ! command -v tput >/dev/null 2>&1; then
  missing="$missing ncurses"
fi
if [ -n "$missing" ]; then
  echo
  if _gum; then
    warn "Missing: ${missing# }"
  else
    warn "Missing:${RED} ${missing# }${RESET}"
  fi
  echo "${DIM}     Run: pkg install ${missing# }${RESET}"
  err "Cannot continue without required dependencies."
  exit 1
fi
ok "All core dependencies available"
echo

# ── Banner ──────────────────────────────────────────────────
clear 2>/dev/null || true

FIGLET_FONT=""
for f in smslant small slant; do
  if figlet -f "$f" ' ' >/dev/null 2>&1; then
    FIGLET_FONT="$f"
    break
  fi
done
if [ -n "$FIGLET_FONT" ]; then
  BANNER=$(figlet -f "$FIGLET_FONT" "Termux" 2>/dev/null)
  BANNER2=$(figlet -f "$FIGLET_FONT" "TUI Store" 2>/dev/null)
  if _gum; then
    echo "$BANNER" | gum style --foreground 6 --bold
    echo "$BANNER2" | gum style --foreground 5 --bold
  else
    echo "$BANNER" | sed "s/.*/${CYAN}&${RESET}/"
    echo "$BANNER2" | sed "s/.*/${MAGENTA}&${RESET}/"
  fi
else
  echo "${CYAN}${BOLD}  Termux${RESET}"
  echo "${MAGENTA}${BOLD}  TUI Store${RESET}"
fi
echo
box 6 "Termux TUI Package Store"
boxf 6 "fzf-powered interactive package browser"
echo

# ── Validate env vars ──────────────────────────────────────
REPO="${REPO:-Mark44928/Termux-TUI-Package-Store}"
BRANCH="${BRANCH:-main}"
if [[ ! "$REPO" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]] || [[ ! "$BRANCH" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
  err "Invalid REPO or BRANCH value."
  exit 1
fi

# ── Download ────────────────────────────────────────────────
header "⬇  Downloading pkgs"
URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/pkgs_core.zsh"
INSTALL_PATH="$PREFIX/bin/pkgs"
mkdir -p "$PREFIX/bin" 2>/dev/null

curl --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 5 --retry-connrefused --retry-all-errors -fsSL "$URL" -o "${INSTALL_PATH}.tmp" || {
  echo
  err "Download failed."
  echo "${YELLOW}  Check your connection or URL:${RESET}"
  echo "  ${YELLOW}$URL${RESET}"
  exit 1
}

if ! head -1 "${INSTALL_PATH}.tmp" | grep -q '^#!/.*zsh'; then
  err "Downloaded file is not a valid zsh script."
  rm -f "${INSTALL_PATH}.tmp"
  exit 1
fi

mv "${INSTALL_PATH}.tmp" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH" || {
  err "Failed to set execute permission."
  exit 1
}

ok "Installed to ${BOLD}$INSTALL_PATH${RESET}"
echo

# ── Complete ────────────────────────────────────────────────
echo
box 2 "🎉  INSTALLATION COMPLETE!  🎉"
echo

if _gum; then
  gum style --border rounded --border-foreground 6 --padding "0 2" --bold \
    "pkgs              # browse all packages
pkgs python        # pre-filtered search
pkgs -i neovim     # direct install
pkgs -r neovim     # remove a package"
else
  echo "  ${BOLD}Quick start:${RESET}"
  echo
  echo "    ${CYAN}${BOLD}pkgs${RESET}                  ${DIM}# browse all packages${RESET}"
  echo "    ${CYAN}${BOLD}pkgs python${RESET}            ${DIM}# pre-filtered search${RESET}"
  echo "    ${CYAN}${BOLD}pkgs -i neovim${RESET}         ${DIM}# direct install${RESET}"
  echo "    ${CYAN}${BOLD}pkgs -r neovim${RESET}         ${DIM}# remove a package${RESET}"
fi
echo
echo "  ${DIM}──────────────────────────────────────────${RESET}"
echo "  ${DIM}github.com/Mark44928/Termux-TUI-Package-Store${RESET}"
echo
