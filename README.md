# Termux-TUI-Package-Store 📦

**The TUI package manager wrapper for Termux.**

Termux-TUI-Package-Store is a high-performance, fzf-powered interface that replaces tedious manual pkg commands with a smooth, interactive TUI. It intelligently detects your terminal layout, visually highlights installed vs. available packages, and manages your software installation with a single keystroke.
# Warning: This only for ZSH, Bash and KSH! sh, fish, and etc may not work, sorry! 🥲⚠️
## 🛠 How It Works
The script operates as a bridge between your system's package database and an interactive fuzzy-finder.
 1. **Layout Detection**: Uses tput to measure your window size and automatically decides whether to split the screen horizontally or vertically.
 2. **Data Processing**: Runs a two-pass awk script. It first reads dpkg-query to identify installed items, then merges this with apt-cache search to provide a comprehensive list of every available package.
 3. **Live Previews**: As you highlight a package, the script dynamically pulls its metadata (Version, Section, Size) and dependency tree using apt-cache.
 4. **Action Binding**: Upon hitting Enter, it performs a status check on the package. If installed, it prepares to remove; if missing, it initiates an install.

## 📸 Screenshot

![pkgs screenshot](assets/pkgs.png)

## 🚀 Full Step-by-Step Installation
Follow these steps to integrate pkgs.zsh into your Termux environment.
### 1. Install Dependencies
You need fzf for the interface, gawk for data processing, and cowsay for the status feedback.
```bash
pkg update && pkg upgrade && pkg install zsh fzf cowsay coreutils gawk grep sed ncurses

```
Ignore when packages already installed.
### 2. Create the Script File
Create a dedicated file in your home directory to house the function:
```bash
nano ~/.pkgs_core.zsh

```
Paste this code:
```bash
pkgs() {
    _pkgs_detect_layout() {
        local cols lines
        cols=$(tput cols); lines=$(tput lines)
        [[ -z $cols ]] && cols=80
        [[ -z $lines ]] && lines=24
        if (( cols > lines * 3 || cols > 110 )); then
            echo "$LANDSCAPE_SPLIT"
        else
            echo "$PORTRAIT_SPLIT"
        fi
    }

    _pkgs_generate_list() {
        awk -v c_inst="$C_INST_PREFIX" -v c_not_inst="$C_NOT_INST_PREFIX" \
            -v c_name="$C_PKG_NAME" -v c_desc="$C_PKG_DESC" -v c_reset="$C_RESET" '
        NR==FNR { installed[$1]=1; next }
        {
            match($0, / - /)
            if (RSTART > 0) {
                name = substr($0, 1, RSTART-1)
                gsub(/[[:space:]]/, "", name)
                desc = substr($0, RSTART+3)
                prefix = (name in installed) ? c_inst : c_not_inst
                printf "%s|%s %s%s%s - %s%s%s\n", name, prefix, c_name, name, c_reset, c_desc, desc, c_reset
            }
        }
        ' <(dpkg-query -W -f='${Package}\n') <(apt-cache search ".*")
    }

_pkgs_preview_command() {
    echo "apt-cache show {1} | grep -E '^(Version|Section|Installed-Size):'
          echo -n 'Size: '
          apt-cache show {1} | grep '^Size:' | cut -d' ' -f2 | numfmt --to=iec --suffix=B
          echo -e '\n--- DEPENDENCIES ---'
          deps=\$(apt-cache depends {1} | grep 'Depends:' | cut -d':' -f2 | sort -u | head -n 5 | xargs)
          if [ -z \"\$deps\" ]; then
              cowsay 'This Package had no dependencies yet.'
          else
              echo \"\$deps\"
          fi
          echo -e '\n--- DESCRIPTION ---'
          apt-cache show {1} | sed -n 's/^Description: //p'"
}
    _pkgs_build_fzf_args() {
        local query="$1"
        FZF_ARGS=(
            --ansi
            --query "$query"
            --layout=reverse
            --border=$BORDER_STYLE
            --border-label=" Packages "
            --preview-label=" Package Details "
            --prompt="  Find > "
            --pointer="▶"
            --info=inline
            --color='fg:250,bg:-1,hl:063,fg+:231,bg+:235,hl+:063,info:144,prompt:161,pointer:161,marker:118,spinner:135,header:087'
            --preview-window="$PREVIEW_LAYOUT"
            --delimiter='\|'
            --with-nth=2
            --nth=1,2
            --tiebreak=begin,length,index
            --no-hscroll
            --bind 'left:ignore,right:ignore,alt-left:ignore,alt-right:ignore'
            --preview "$(_pkgs_preview_command)"
            --bind "enter:become(
                if dpkg -s {1} >/dev/null 2>&1; then
                    echo -e '${C_MSG_REMOVE}--- package is installed. Preparing to REMOVE... ---${C_RESET}'
                    ${PKG_MGR} remove {1}
                else
                    echo -e '${C_MSG_INSTALL}--- package is not installed. Preparing to INSTALL... ---${C_RESET}'
                    ${PKG_MGR} install {1}
                fi
            )"
            --bind '?:toggle-preview'
        )
    }

    # Configuration
    local PKG_MGR="pkg"
    local BAT_THEME="${PKGL_BAT_THEME:-OneHalfDark}"
    local PORTRAIT_SPLIT="down:48%:wrap"
    local LANDSCAPE_SPLIT="right:40%:wrap"
    local BORDER_STYLE="rounded"
    local C_RESET='\033[0m'
    local C_INST_PREFIX='\x1b[1;36m[I]\x1b[0m'
    local C_NOT_INST_PREFIX='\x1b[1;30m[-]\x1b[0m'
    local C_PKG_NAME='\x1b[1;32m'
    local C_PKG_DESC='\x1b[2;37m'
    local C_MSG_INSTALL='\033[1;32m'
    local C_MSG_REMOVE='\033[1;31m'

    local PREVIEW_LAYOUT=$(_pkgs_detect_layout)
    local -a FZF_ARGS
    _pkgs_build_fzf_args "$*"

    _pkgs_generate_list | fzf "${FZF_ARGS[@]}"
}
```
Ctrl + O, Enter, and Ctrl + X. 😌
### 3. Integrate with Zsh
Add the file to your shell configuration so it's available every time you open Termux:
```bash
echo "source ~/.pkgs_core.zsh" >> ~/.zshrc # or ~/.bashrc for bash users
source ~/.zshrc # Or ~/.bashrc if youre bash

```
### 4. Usage
Simply type the following into your terminal:
```bash
pkgs

```
## 🔧 Advanced Tweaks & Configuration
You can go beyond the basics by fine-tuning the internal logic of pkgs.zsh. Modify these sections within the pkgs function in ~/.pkgs_core.zsh to make the tool truly yours:
 * **Customizing the Preview Window**:
   * Want the preview to be larger? Modify PORTRAIT_SPLIT="down:48%:wrap" to a higher percentage like down:60%:wrap.
   * Prefer the preview on the left instead of the right? In LANDSCAPE_SPLIT="right:40%:wrap", change right to left.
   * You can also add --cycle or --scrollbar to the FZF_ARGS array if you want more navigation control.
 * **Deep Color Palette Tweaking**:
   * The --color flag in the _pkgs_build_fzf_args function is the key to a custom aesthetic. You can map any of the ANSI 256 colors to specific elements like fg+ (current line foreground), bg+ (current line background), or hl+ (highlighted match in the current line).
   * Example: Change pointer:161 (a vibrant red/pink) to pointer:045 for a crisp cyan accent.
 * **Enhancing the "Action" Logic**:
   * Look at the enter:become block in _pkgs_build_fzf_args. You can change the behavior of the Enter key.
   * Want to perform a reinstall instead of a basic install? Swap ${PKG_MGR} install {1} for ${PKG_MGR} reinstall {1}.
   * Need to see more info before acting? Add an echo line inside the become block to log your actions to a file (e.g., echo "$(date): Installed {1}" >> ~/.pkgs_log).
 * **Tuning the Preview Command**:
   * Want to see *more* than just the top 5 dependencies? Find the deps=$(...) line in _pkgs_preview_command and change head -n 5 to head -n 10 or remove the | head -n 5 pipe entirely to see the full list.
   * Tired of the cowsay message? Replace the cowsay line in _pkgs_preview_command with a simple echo "No dependencies found." to speed up the preview rendering.
 * **Optimizing Performance**:
   * If you have a massive amount of packages and the awk processing feels slow, you can cache the package list to a temporary file. Simply point _pkgs_generate_list to read from a file that updates only once a day instead of running apt-cache search every single time you launch the script.
 * **Data Parsing Precision**:
   * The awk block uses match($0, / - /) to split the package name from the description. If your specific apt output format varies or contains unusual characters, you can adjust this regex. For example, changing it to match($0, / {2,}/) might be better if your package descriptions are separated by multiple spaces rather than a hyphen.
 * **Terminal Environment Overrides**:
   * If your terminal emulator struggles with specific ANSI colors, you can override the C_ variables to use standard 16-color codes instead of the complex escape sequences. This ensures maximum compatibility across different Termux themes or fonts.
 * **Log Everything**:
   * Add a helper variable local LOG_FILE="$HOME/.pkgs_history" and append to it within your enter:become logic. This gives you a permanent record of every package you've ever installed or removed via the script—super useful for cleaning up your system later.
> **Pro Tip 2 (The "Stealth" Mode)**: If you're tired of seeing the package description every time, you can hide the preview window by default by changing --preview-window="$PREVIEW_LAYOUT" to --preview-window="$PREVIEW_LAYOUT:hidden". You can then press ? to toggle it on only when you need it.
> 
> **Pro Tip 3 (Dynamic Scaling)**: Instead of hard-coding PORTRAIT_SPLIT, you can write a secondary if/else block that calculates the percentage based on total screen height, ensuring that the preview window is always exactly 5 lines less than your terminal height.
> 
> **Pro Tip 4 (Filter Optimization)**: You can expand the _pkgs_generate_list command by adding a grep -v filter to exclude specific library packages (like lib* or python-dev-*) from the list, keeping your search results cleaner and focusing only on end-user software.
> 

