#!/data/data/com.termux/files/usr/bin/sh

set -e

REPO="Mark44928/Termux-TUI-Package-Store"
BRANCH="main"
INSTALL_PATH="$PREFIX/bin/pkgs"

echo "📦 Termux-TUI-Package-Store Installer"
echo "===================================="

# Detect Termux
if [ -z "$PREFIX" ]; then
    echo "❌ This installer is designed for Termux."
    exit 1
fi

# Update packages safely
echo "🔧 Installing dependencies..."
pkg update -y >/dev/null 2>&1 && pkg install -y zsh fzf cowsay coreutils gawk grep sed ncurses curl >/dev/null 2>&1

# Download core file
echo "⬇️ Downloading core script..."

URL="https://raw.githubusercontent.com/$REPO/$BRANCH/pkgs_core.zsh"

curl -fsSL "$URL" -o "$INSTALL_PATH"

if [ ! -f "$INSTALL_PATH" ]; then
    echo "❌ Download failed."
    exit 1
fi

chmod +x "$INSTALL_PATH"

echo "✅ Installed to $INSTALL_PATH"

echo ""
echo "🎉 Installation complete!"
echo "👉 Run: pkgs"
