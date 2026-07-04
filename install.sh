#!/data/data/com.termux/files/usr/bin/sh

set -e

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
  printf "\r${GREEN}  [✓]${RESET} %s    \n" "$msg"
}

cleanup() {
  rm -f "${INSTALL_PATH}.tmp" 2>/dev/null
}
trap cleanup EXIT

# ── Pre-flight ──────────────────────────────────────────────
if [ -z "$PREFIX" ]; then
  echo "${RED}  ✗ This installer is designed for Termux.${RESET}"
  echo "${YELLOW}  Please run this script inside Termux on Android.${RESET}"
  exit 1
fi

echo "${BOLD}  📋 Pre-flight check${RESET}"
echo "  ─────────────────"
echo "  ${GREEN}✓${RESET} Termux detected at $PREFIX"
echo ""

# ── Install dependencies (including figlet for the banner) ──
echo "${BOLD}  🔧 Installing dependencies${RESET}"
echo "  ─────────────────────────"
(
  pkg update -y >/dev/null 2>&1 && \
  pkg install -y zsh fzf cowsay coreutils gawk grep sed ncurses curl figlet >/dev/null 2>&1
) &
spinner $! "Updating and installing packages"

missing=''
for cmd in fzf awk zsh curl tput figlet; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing="$missing $cmd"
  fi
done
if [ -n "$missing" ]; then
  echo "${YELLOW}  ⚠  Missing:${RESET}$missing"
  echo "${YELLOW}     Run: pkg install$missing${RESET}"
else
  echo "  ${GREEN}✓${RESET} All core dependencies available"
fi
echo ""

# ── Banner (after figlet is installed) ──────────────────────
clear 2>/dev/null || true
figlet -f big "Termux" 2>/dev/null | sed "s/^/${CYAN}/" | sed "s/$/${RESET}/"
figlet -f big "TUI Store" 2>/dev/null | sed "s/^/${MAGENTA}/" | sed "s/$/${RESET}/"
echo ""
echo "${CYAN}  ╔══════════════════════════════════════════╗${RESET}"
echo "${CYAN}  ║${RESET}  ${BOLD}Termux TUI Package Store${RESET}            ${CYAN}║${RESET}"
echo "${CYAN}  ║${RESET}  fzf-powered interactive package browser ${CYAN}║${RESET}"
echo "${CYAN}  ╚══════════════════════════════════════════╝${RESET}"
echo ""

# ── Download ────────────────────────────────────────────────
echo "${BOLD}  ⬇️  Downloading pkgs${RESET}"
echo "  ─────────────────────"
URL="https://raw.githubusercontent.com/${REPO:-Mark44928/Termux-TUI-Package-Store}/${BRANCH:-main}/pkgs_core.zsh"
INSTALL_PATH="$PREFIX/bin/pkgs"

curl -#fSL "$URL" -o "${INSTALL_PATH}.tmp" 2>&1 || {
  echo ""
  echo "${RED}  ✗ Download failed.${RESET}"
  echo "${YELLOW}  Check your connection:${RESET}"
  echo "  ${YELLOW}$URL${RESET}"
  exit 1
}

mv "${INSTALL_PATH}.tmp" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo "  ${GREEN}✓${RESET} Installed to ${BOLD}$INSTALL_PATH${RESET}"
echo ""

# ── Complete ────────────────────────────────────────────────
echo "${GREEN}  ┌─────────────────────────────────────────────────────┐${RESET}"
echo "${GREEN}  │${RESET}                                                       ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}   ${BOLD}🎉  INSTALLATION COMPLETE!${RESET}                    ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}                                                       ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}   ${BOLD}Just type:${RESET}                                       ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}                                                       ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}       ${CYAN}pkgs${RESET}                                              ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}                                                       ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}   Search, preview, install & remove packages          ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}   with a single keystroke.                            ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}                                                       ${GREEN}│${RESET}"
echo "${GREEN}  │${RESET}   ${YELLOW}Pro tip:${RESET}  pkgs python   (pre-filter results)      ${GREEN}│${RESET}"
echo "${GREEN}  └─────────────────────────────────────────────────────┘${RESET}"
echo ""
