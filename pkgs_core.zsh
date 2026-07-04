#!/data/data/com.termux/files/usr/bin/zsh
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
            --bind '?:toggle-preview'
        )
    }

    # Configuration
    local PKG_MGR="pkg"
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

    while true; do
        local -a FZF_ARGS
        _pkgs_build_fzf_args "$*"

        local selection
        selection=$(_pkgs_generate_list | fzf "${FZF_ARGS[@]}")
        local ret=$?

        [[ $ret -ne 0 ]] && break

        local pkg_name="${selection%%|*}"

        if dpkg -s "$pkg_name" >/dev/null 2>&1; then
            echo -e "${C_MSG_REMOVE}--- package is installed. Preparing to REMOVE... ---${C_RESET}"
            ${PKG_MGR} remove "$pkg_name"
        else
            echo -e "${C_MSG_INSTALL}--- package is not installed. Preparing to INSTALL... ---${C_RESET}"
            ${PKG_MGR} install "$pkg_name"
        fi
    done
}

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && pkgs "$@"

