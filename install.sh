#!/data/data/com.termux/files/usr/bin/sh

set -e

REPO="Mark44928/Termux-TUI-Package-Store"
BRANCH="main"
INSTALL_PATH="$HOME/.pkgs_core.zsh"

echo "📦 Termux-TUI-Package-Store Installer"
echo "===================================="

# Detect Termux
if [ -z "$PREFIX" ]; then
    echo "❌ This installer is designed for Termux."
    exit 1
fi

# Update packages safely
echo "🔧 Installing dependencies..."
pkg update -y >/dev/null 2>&1
pkg install -y zsh fzf cowsay coreutils gawk grep sed ncurses curl >/dev/null 2>&1

# Download core file
echo "⬇️ Downloading core script..."

URL="https://raw.githubusercontent.com/$REPO/$BRANCH/.pkgs_core.zsh"

curl -fsSL "$URL" -o "$INSTALL_PATH"

if [ ! -f "$INSTALL_PATH" ]; then
    echo "❌ Download failed."
    exit 1
fi

echo "✅ Downloaded to $INSTALL_PATH"

# Detect shell
echo "🧠 Configuring shell..."

SHELL_FILE=""

if [ -n "$ZSH_VERSION" ] || echo "$SHELL" | grep -q "zsh"; then
    SHELL_FILE="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ] || echo "$SHELL" | grep -q "bash"; then
    SHELL_FILE="$HOME/.bashrc"
else
    SHELL_FILE="$HOME/.profile"
fi

# Avoid duplicate sourcing
if ! grep -q ".pkgs_core.zsh" "$SHELL_FILE" 2>/dev/null; then
    echo "source $INSTALL_PATH" >> "$SHELL_FILE"
    echo "✅ Added to $SHELL_FILE"
else
    echo "⚠️ Already configured in $SHELL_FILE"
fi

echo ""
echo "🎉 Installation complete!"
echo "👉 Restart Termux then run: pkgs"
