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
              size=\$(apt-cache show {1} | grep '^Size:' | cut -d' ' -f2)
              if command -v numfmt >/dev/null 2>&1; then
                  echo \"\$size\" | numfmt --to=iec --suffix=B
              else
                  echo \"\${size:-0} B\"
              fi
              echo -e '\n--- DEPENDENCIES ---'
              deps=\$(apt-cache depends {1} | grep 'Depends:' | cut -d':' -f2 | sort -u | head -n 5 | xargs)
              if [ -z \"\$deps\" ]; then
                  echo 'No dependencies.'
              else
                  echo \"\$deps\"
              fi
              echo -e '\n--- DESCRIPTION ---'
              apt-cache show {1} | sed -n '/^Description:/ { s/^Description: //p; :a; n; /^ / { s/^ //p; ba }; }'"
    }
    _pkgs_build_fzf_args() {
        local query="$1"
        FZF_ARGS=(
            --ansi
            --query "$query"
            --layout=reverse
            --border="$BORDER_STYLE"
            --border-label=" Packages "
            --preview-label=" Package Details "
            --prompt="  Find > "
            --pointer="▶"
            --info=inline
            --multi
            --print-query
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
    local C_RESET=$'\033[0m'
    local C_INST_PREFIX=$'\033[1;36m[I]\033[0m'
    local C_NOT_INST_PREFIX=$'\033[1;30m[-]\033[0m'
    local C_PKG_NAME=$'\033[1;32m'
    local C_PKG_DESC=$'\033[2;37m'
    local C_MSG_INSTALL=$'\033[1;32m'
    local C_MSG_REMOVE=$'\033[1;31m'
    local C_MSG_INFO=$'\033[1;33m'

    local PREVIEW_LAYOUT=$(_pkgs_detect_layout)

    local initial_query="$*"
    local query="$initial_query"

    while true; do
        local -a FZF_ARGS
        _pkgs_build_fzf_args "$query"

        local output
        output=$({
            echo "__UPGRADE__|${C_MSG_INFO}⬆  Upgrade all packages${C_RESET}"
            echo "__EXPORT__|${C_MSG_INFO}💾  Export package list${C_RESET}"
            _pkgs_generate_list
        } | fzf "${FZF_ARGS[@]}")
        local ret=$?

        [[ $ret -ne 0 ]] && break
        [[ -z "$output" ]] && continue

        local lines=("${(@f)output}")
        local query="${lines[1]}"

        [[ ${#lines} -lt 2 ]] && continue

        local line
        for line in "${(@)lines[2,-1]}"; do
            [[ -z "$line" ]] && continue
            local pkg_name="${line%%|*}"
            [[ -z "$pkg_name" ]] && continue

            case "$pkg_name" in
                __UPGRADE__)
                    echo
                    echo -e "${C_MSG_INFO}--- Upgrading all packages... ---${C_RESET}"
                    "${PKG_MGR}" upgrade
                    echo
                    continue
                    ;;
                __EXPORT__)
                    local export_file="termux-packages-export-$(date +%Y%m%d-%H%M%S).txt"
                    if dpkg-query -W -f='${Package}\n' > "$export_file"; then
                        echo
                        echo -e "${C_MSG_INFO}--- Exported package list to ${C_RESET}$export_file"
                        echo
                    else
                        echo -e "${C_MSG_REMOVE}--- Export failed ---${C_RESET}"
                    fi
                    continue
                    ;;
            esac

            print -n "${C_MSG_INFO}Process $pkg_name? (y/N) ${C_RESET}"
            read -q confirm
            echo
            [[ $confirm == 'y' ]] || {
                echo -e "${C_MSG_INFO}Skipped.${C_RESET}"
                continue
            }

            if dpkg -s "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
                echo -e "${C_MSG_REMOVE}--- Removing $pkg_name ---${C_RESET}"
                "${PKG_MGR}" remove "$pkg_name" || echo -e "${C_MSG_REMOVE}Remove failed${C_RESET}"
            else
                echo -e "${C_MSG_INSTALL}--- Installing $pkg_name ---${C_RESET}"
                "${PKG_MGR}" install "$pkg_name" || echo -e "${C_MSG_REMOVE}Install failed${C_RESET}"
            fi
        done
    done
}

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && pkgs "$@"

