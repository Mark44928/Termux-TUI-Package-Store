#!/data/data/com.termux/files/usr/bin/zsh
pkgs() {
    # Check prerequisites
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is required. Install with: pkg install fzf"
        return 1
    fi
    if ! command -v pkg &>/dev/null; then
        echo "Error: 'pkg' not found."
        return 1
    fi
    if ! command -v apt-cache &>/dev/null || ! command -v dpkg-query &>/dev/null; then
        echo "Error: apt-cache or dpkg-query not found."
        return 1
    fi

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
        echo 'pkg=$(apt-cache show {1} 2>/dev/null) || { echo "Package not found"; exit 0; }
echo "$pkg" | grep -E "^(Version|Section|Installed-Size):"
size=$(echo "$pkg" | grep "^Size:" | cut -d" " -f2)
printf "Size: "
if [ -n "$size" ]; then
    if command -v numfmt >/dev/null 2>&1; then
        printf "%s\n" "$size" | numfmt --to=iec --suffix=B
    else
        printf "%s B\n" "$size"
    fi
else
    printf "unknown\n"
fi
printf "\n--- DEPENDENCIES ---\n"
deps=$(echo "$pkg" | grep "^Depends:" | cut -d":" -f2 | sort -u | head -n 5 | xargs)
if [ -z "$deps" ]; then
    echo "No dependencies."
else
    echo "$deps"
fi
printf "\n--- DESCRIPTION ---\n"
echo "$pkg" | sed -n "/^Description:/ { s/^Description: //p; :a; n; /^ / { s/^ //p; ba }; }"'
    }
    _pkgs_build_fzf_args() {
        local query="$1"
        FZF_ARGS=(
            --ansi
            --query "$query"
            --layout=reverse
            --border="$BORDER_STYLE"
            --border-label="  Packages "
            --preview-label="  Package Details "
            --prompt="  Search Here... > "
            --pointer="▶"
            --info=inline
            --multi
            --print-query
            --color='fg:250,bg:-1,hl:063,fg+:231,bg+:235,hl+:063,info:144,prompt:161,pointer:161,marker:118,spinner:135,header:087'
            --preview-window="$PREVIEW_LAYOUT"
            --delimiter='[|]'
            --with-nth=2
            --nth=1,2
            --tiebreak=begin,length,index
            --no-hscroll
            --bind 'left:ignore,right:ignore,alt-left:ignore,alt-right:ignore'
            --preview "$(_pkgs_preview_command)"
            --bind '?:toggle-preview'
        )
    }

    _pkgs_strip_ansi() {
        setopt localoptions EXTENDED_GLOB
        local text="$1"
        text="${text//$'\033'\[[0-9;]#m/}"
        print -- "$text"
    }

    # Configuration
    local PKG_MGR="pkg"
    local PORTRAIT_SPLIT="down:48%:wrap"
    local LANDSCAPE_SPLIT="right:40%:wrap"
    local BORDER_STYLE="rounded"
    local C_RESET=$'\033[0m'
    local C_INST_PREFIX=$'\033[1;36m[I]\033[0m'
    local C_NOT_INST_PREFIX=$'\033[2;37m[-]\033[0m'
    local C_PKG_NAME=$'\033[1;32m'
    local C_PKG_DESC=$'\033[2;37m'
    local C_MSG_INSTALL=$'\033[1;32m'
    local C_MSG_REMOVE=$'\033[1;31m'
    local C_MSG_INFO=$'\033[1;33m'

    local PREVIEW_LAYOUT=$(_pkgs_detect_layout)

    local query="$*"

    while true; do
        local -a FZF_ARGS
        _pkgs_build_fzf_args "$query"

        local output
        output=$(_pkgs_generate_list | fzf "${FZF_ARGS[@]}")
        local ret=$?

        [[ $ret -ne 0 ]] && { clear; break; }
        [[ -z "$output" ]] && continue

        output=$(_pkgs_strip_ansi "$output")
        local -a lines=("${(@f)output}")
        local query="${lines[1]}"
        query="$(print -r -- "$query" | xargs)"

        if [[ "$query" == /upgrade ]]; then
            clear
            echo
            echo -e "${C_MSG_INFO}--- Upgrading all packages... ---${C_RESET}"
            "${PKG_MGR}" upgrade --
            echo
            echo -e "${C_MSG_INFO}Press Enter to exit.${C_RESET}"
            read -r
            clear
            continue
        fi

        if [[ "$query" == /install* || "$query" == /remove* || "$query" == /export* ]]; then
            local cmd="${query%% *}"
            local search_term="${query#* }"
            cmd="${cmd#/}"
            # Reject bare command without search term
            [[ "$query" != *" "* ]] && continue
            # Strip whitespace
            search_term="$(print -r -- "$search_term" | xargs)"
            [[ -z "$search_term" ]] && continue

            local -a match_pkgs=()
            while IFS= read -r line; do
                [[ "$line" == [WE]:* || "$line" == " "* ]] && continue
                local name="${line%% *}"
                [[ -z "$name" || "$name" == -* ]] && continue
                apt-cache show "$name" >/dev/null 2>&1 && match_pkgs+=("$name")
            done < <(apt-cache search -n "$search_term" 2>/dev/null)

            if [[ ${#match_pkgs} -eq 0 ]]; then
                echo
                echo -e "${C_MSG_REMOVE}--- No packages matching \"$search_term\" ---${C_RESET}"
                echo
                continue
            fi

            case "$cmd" in
                install|remove)
                    clear
                    local ok=0 fail=0
                    local total=${#match_pkgs[@]}
                    for pkg in "${match_pkgs[@]}"; do
                        echo -ne "${C_MSG_INFO}  [$((ok+fail+1))/${total}] ${cmd} ${pkg}...${C_RESET}"
                        if "${PKG_MGR}" "$cmd" -- "$pkg"; then
                            echo -e "\r${C_MSG_INSTALL}  ✓ ${pkg}${C_RESET}"
                            ((ok++))
                        else
                            echo -e "\r${C_MSG_REMOVE}  ✗ ${pkg} failed${C_RESET}"
                            ((fail++))
                        fi
                    done
                    echo -e "${C_MSG_INFO}--- ${ok} ok, ${fail} failed ---${C_RESET}"
                    echo
                    ;;
                export)
                    clear
                    local export_file="pkg-install-$(date +%Y%m%d-%H%M%S).sh"
                    {
                        echo "#!/data/data/com.termux/files/usr/bin/sh"
                        echo "${PKG_MGR} install \\"
                        for pkg in "${match_pkgs[@]}"; do echo "    $pkg \\"; done
                        echo "    # end"
                    } > "$export_file"
                    chmod +x "$export_file" 2>/dev/null
                    if [[ -f "$export_file" ]]; then
                        echo
                        echo -e "${C_MSG_INFO}--- Saved: ${C_RESET}$export_file${C_MSG_INFO} ---${C_RESET}"
                    else
                        echo -e "${C_MSG_REMOVE}--- Failed to create export file ---${C_RESET}"
                    fi
                    echo
                    ;;
            esac
            echo -e "${C_MSG_INFO}Press Enter to exit.${C_RESET}"
            read -r
            clear
            continue
        fi

        [[ ${#lines} -lt 2 ]] && continue

        local line
        for line in "${(@)lines[2,-1]}"; do
            [[ -z "$line" ]] && continue
            local pkg_name="${line%%|*}"
            [[ -z "$pkg_name" ]] && continue

            print -n "${C_MSG_INFO}Process $pkg_name? (y/N) ${C_RESET}"
            read -q confirm; read -r
            echo
            [[ $confirm == 'y' ]] || {
                echo -e "${C_MSG_INFO}Skipped.${C_RESET}"
                continue
            }

            clear
            if dpkg -s "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
                echo -e "${C_MSG_REMOVE}--- Removing $pkg_name ---${C_RESET}"
                "${PKG_MGR}" remove -- "$pkg_name" || echo -e "${C_MSG_REMOVE}Remove failed: $pkg_name${C_RESET}"
            else
                if ! apt-cache show "$pkg_name" >/dev/null 2>&1; then
                    echo -e "${C_MSG_REMOVE}--- $pkg_name not found in apt cache ---${C_RESET}"
                    continue
                fi
                echo -e "${C_MSG_INSTALL}--- Installing $pkg_name ---${C_RESET}"
                "${PKG_MGR}" install -- "$pkg_name" || echo -e "${C_MSG_REMOVE}Install failed: $pkg_name${C_RESET}"
            fi
        done
        echo -e "${C_MSG_INFO}Press Enter to exit.${C_RESET}"
        read -r
        clear
    done
    clear
}

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && pkgs "$@"

