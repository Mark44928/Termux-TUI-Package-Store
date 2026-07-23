#!/data/data/com.termux/files/usr/bin/zsh
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
set -e

# ── Lock ────────────────────────────────────────────────────
LOCKFILE="${TMPDIR:-/tmp}/pkgs-install.lock"
if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
  echo "  ✗ Another installation is already running."
  exit 1
fi
echo $$ > "$LOCKFILE"

# ── Terminal colors ─────────────────────────────────────────
BOLD=$(tput bold 2>/dev/null || printf '')
RESET=$(tput sgr0 2>/dev/null || printf '')
GREEN=$(tput setaf 2 2>/dev/null || printf '')
YELLOW=$(tput setaf 3 2>/dev/null || printf '')
RED=$(tput setaf 1 2>/dev/null || printf '')
CYAN=$(tput setaf 6 2>/dev/null || printf '')
MAGENTA=$(tput setaf 5 2>/dev/null || printf '')

# ── Spinner ─────────────────────────────────────────────────
spinner() {
  local pid=$1 msg=$2
  local -a spin=(▰▱▱▱ ▰▰▱▱ ▰▰▰▱ ▰▰▰▰ ▱▰▰▰ ▱▱▰▰ ▱▱▱▰ ▱▱▱▱)
  local i=1

  while kill -0 "$pid" 2>/dev/null; do
    printf "\r${YELLOW}  [%s]${RESET} %s ..." "${spin[i]}" "$msg"
    (( i = i % ${#spin} + 1 ))
    sleep 0.12
  done

  local exit_code=0
  wait "$pid" || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    printf "\r${GREEN}  [✓]${RESET} %s    \n" "$msg"
  else
    printf "\r${RED}  [✗]${RESET} %s failed\n" "$msg"
  fi
  return "$exit_code"
}

cleanup() {
  [[ -n "${INSTALL_PATH:-}" ]] && rm -f "${INSTALL_PATH}.tmp" 2>/dev/null
}
trap cleanup EXIT

# ── Pre-flight ──────────────────────────────────────────────
if [ -z "$PREFIX" ]; then
  echo "${RED}  ✗ This installer is designed for Termux.${RESET}"
  echo "${YELLOW}  Please run this script inside Termux on Android.${RESET}"
  exit 1
fi

echo
echo "${BOLD}  ═══ Pre-flight check ═══${RESET}"
echo "  ${GREEN}✓${RESET} Termux detected at ${BOLD}$PREFIX${RESET}"
echo

# ── Install dependencies ────────────────────────────────────
echo "${BOLD}  ═══ Installing dependencies ═══${RESET}"
(
  pkg update -y >/dev/null 2>&1 && \
  pkg install -y zsh fzf coreutils gawk grep sed ncurses curl figlet -- >/dev/null 2>&1
) &
spinner "$!" "Updating and installing packages" || {
  echo "${RED}  ✗ Dependency installation failed. Aborting.${RESET}"
  exit 1
}

missing=''
for cmd in fzf awk zsh curl tput; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing="$missing $cmd"
  fi
done
if [ -n "$missing" ]; then
  echo "${YELLOW}  ⚠  Missing:${RESET}$missing"
  echo "${YELLOW}     Run: pkg install$missing${RESET}"
  echo "${RED}  ✗ Cannot continue without required dependencies.${RESET}"
  exit 1
fi
echo "  ${GREEN}✓${RESET} All core dependencies available"
echo

# ── Banner ──────────────────────────────────────────────────
clear 2>/dev/null || true
figlet -f smslant "Termux" 2>/dev/null | sed "s/^/${CYAN}/" | sed "s/$/${RESET}/"
figlet -f smslant "TUI Store" 2>/dev/null | sed "s/^/${MAGENTA}/" | sed "s/$/${RESET}/"
echo
echo "${CYAN}  ╔══════════════════════════════════════════╗${RESET}"
echo "${CYAN}  ║${RESET}  ${BOLD}Termux TUI Package Store${RESET}                ${CYAN}║${RESET}"
echo "${CYAN}  ║${RESET}  fzf-powered interactive package browser ${CYAN}║${RESET}"
echo "${CYAN}  ╚══════════════════════════════════════════╝${RESET}"
echo

# ── Validate env vars ──────────────────────────────────────
REPO="${REPO:-Mark44928/Termux-TUI-Package-Store}"
BRANCH="${BRANCH:-main}"
if [[ ! "$REPO" =~ ^[a-zA-Z0-9_./-]+$ ]] || [[ ! "$BRANCH" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
  echo "${RED}  ✗ Invalid REPO or BRANCH value.${RESET}"
  exit 1
fi

# ── Download ────────────────────────────────────────────────
echo "${BOLD}  ═══ Downloading pkgs ═══${RESET}"
URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/pkgs_core.zsh"
INSTALL_PATH="$PREFIX/bin/pkgs"
mkdir -p "$PREFIX/bin" 2>/dev/null

curl -#fSL "$URL" -o "${INSTALL_PATH}.tmp" 2>&1 || {
  echo
  echo "${RED}  ✗ Download failed.${RESET}"
  echo "${YELLOW}  Check your connection or URL:${RESET}"
  echo "  ${YELLOW}$URL${RESET}"
  exit 1
}

if ! head -1 "${INSTALL_PATH}.tmp" | grep -q 'zsh'; then
  echo "${RED}  ✗ Downloaded file is not a valid zsh script.${RESET}"
  rm -f "${INSTALL_PATH}.tmp"
  exit 1
fi

mv "${INSTALL_PATH}.tmp" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH" || {
  echo "${RED}  ✗ Failed to set execute permission.${RESET}"
  exit 1
}

echo "  ${GREEN}✓${RESET} Installed to ${BOLD}$INSTALL_PATH${RESET}"
echo

# ── Complete ────────────────────────────────────────────────
echo
echo "  ${BOLD}╔════════════════════════════════════╗${RESET}"
echo "  ${BOLD}║      🎉 INSTALLATION COMPLETE!     ║${RESET}"
echo "  ${BOLD}╚════════════════════════════════════╝${RESET}"
echo
echo "  ${BOLD}Run it:${RESET}"
echo "    ${CYAN}pkgs${RESET}"
echo
echo "  ${YELLOW}Pro tip:${RESET}  pkgs python   (opens with pre-filtered results)"
echo
