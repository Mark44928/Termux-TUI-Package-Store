#!/data/data/com.termux/files/usr/bin/zsh

set -e

# Prevent concurrent runs
LOCKFILE="${TMPDIR:-/tmp}/pkgs-install.lock"
if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
  echo "  ✗ Another installation is already running."
  exit 1
fi
echo $$ > "$LOCKFILE"

BOLD=$(tput bold 2>/dev/null || printf '')
RESET=$(tput sgr0 2>/dev/null || printf '')
GREEN=$(tput setaf 2 2>/dev/null || printf '')
YELLOW=$(tput setaf 3 2>/dev/null || printf '')
RED=$(tput setaf 1 2>/dev/null || printf '')
CYAN=$(tput setaf 6 2>/dev/null || printf '')
MAGENTA=$(tput setaf 5 2>/dev/null || printf '')

spinner() {
  local pid=$1 msg=$2 spin='-\|/' i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\r${YELLOW}  [%c]${RESET} %s ..." "${spin:$i:1}" "$msg"
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
echo "${BOLD}  📋 Pre-flight check${RESET}"
echo "  ─────────────────"
echo "  ${GREEN}✓${RESET} Termux detected at $PREFIX"
echo ""

# ── Install dependencies (including figlet for the banner) ──
echo "${BOLD}  🔧 Installing dependencies${RESET}"
echo "  ─────────────────────────"
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
else
  echo "  ${GREEN}✓${RESET} All core dependencies available"
fi
echo ""

# ── Banner (after figlet is installed) ──────────────────────
clear 2>/dev/null || true
figlet -f smslant "Termux" 2>/dev/null | sed "s/^/${CYAN}/" | sed "s/$/${RESET}/"
figlet -f smslant "TUI Store" 2>/dev/null | sed "s/^/${MAGENTA}/" | sed "s/$/${RESET}/"
echo ""
echo "${CYAN}  ╔══════════════════════════════════════════╗${RESET}"
echo "${CYAN}  ║${RESET}  ${BOLD}Termux TUI Package Store${RESET}                ${CYAN}║${RESET}"
echo "${CYAN}  ║${RESET}  fzf-powered interactive package browser ${CYAN}║${RESET}"
echo "${CYAN}  ╚══════════════════════════════════════════╝${RESET}"
echo ""

# ── Validate env vars ──────────────────────────────────────
REPO="${REPO:-Mark44928/Termux-TUI-Package-Store}"
BRANCH="${BRANCH:-main}"
if [[ ! "$REPO" =~ ^[a-zA-Z0-9_./-]+$ ]] || [[ ! "$BRANCH" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
  echo "${RED}  ✗ Invalid REPO or BRANCH value.${RESET}"
  exit 1
fi

# ── Download ────────────────────────────────────────────────
echo "${BOLD}  ⬇️  Downloading pkgs${RESET}"
echo "  ─────────────────────"
URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/pkgs_core.zsh"
INSTALL_PATH="$PREFIX/bin/pkgs"
mkdir -p "$PREFIX/bin" 2>/dev/null

curl -#fSL "$URL" -o "${INSTALL_PATH}.tmp" 2>&1 || {
  echo ""
  echo "${RED}  ✗ Download failed.${RESET}"
  echo "${YELLOW}  Check your connection:${RESET}"
  echo "  ${YELLOW}$URL${RESET}"
  exit 1
}

# Verify download is a valid zsh script (basic sanity check)
if ! head -1 "${INSTALL_PATH}.tmp" | grep -q 'zsh'; then
  echo "${RED}  ✗ Downloaded file does not look like the expected script.${RESET}"
  rm -f "${INSTALL_PATH}.tmp"
  exit 1
fi

# Verify SHA256 checksum (mandatory — abort if unavailable)
SHA_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/pkgs_core.zsh.sha256"
EXPECTED_SHA=$(curl -fsSL "$SHA_URL" 2>/dev/null | awk '{print $1}')
if [[ -z "$EXPECTED_SHA" ]]; then
  echo "${RED}  ✗ Could not retrieve checksum file. Aborting for safety.${RESET}"
  echo "${YELLOW}  URL: $SHA_URL${RESET}"
  rm -f "${INSTALL_PATH}.tmp"
  exit 1
fi
ACTUAL_SHA=$(sha256sum "${INSTALL_PATH}.tmp" 2>/dev/null | awk '{print $1}')
if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
  echo "${RED}  ✗ Checksum mismatch — download may be corrupted or tampered.${RESET}"
  echo "${YELLOW}  Expected: $EXPECTED_SHA${RESET}"
  echo "${YELLOW}  Got:      $ACTUAL_SHA${RESET}"
  rm -f "${INSTALL_PATH}.tmp"
  exit 1
fi

mv "${INSTALL_PATH}.tmp" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH" || {
  echo "${RED}  ✗ Failed to set execute permission.${RESET}"
  exit 1
}

echo "  ${GREEN}✓${RESET} Installed to ${BOLD}$INSTALL_PATH${RESET}"
echo ""

# ── Complete ────────────────────────────────────────────────
echo ""
echo "  ${BOLD}🎉  INSTALLATION COMPLETE!${RESET}"
echo ""
echo "  ${BOLD}Just type:${RESET}"
echo ""
echo "    ${CYAN}pkgs${RESET}"
echo ""
echo "  Search, preview, install & remove packages"
echo "  with a single keystroke."
echo ""
echo "  ${YELLOW}Pro tip:${RESET}  pkgs python   (pre-filter results)"
echo ""
