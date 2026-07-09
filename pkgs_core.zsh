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

    # Configuration
    local PKG_MGR="pkg"
    local PORTRAIT_SPLIT="down:48%:wrap"
    local LANDSCAPE_SPLIT="right:40%:wrap"
    local BORDER_STYLE="rounded"

    # Natural/Forest theme
    local C_RESET=$'\033[0m'
    local C_GREEN=$'\033[38;5;114m'
    local C_TEAL=$'\033[38;5;109m'
    local C_AMBER=$'\033[38;5;180m'
    local C_RED=$'\033[38;5;203m'
    local C_WHITE=$'\033[38;5;223m'
    local C_DIM=$'\033[38;5;59m'

    local C_INST_PREFIX="${C_GREEN}[✓]${C_RESET}"
    local C_NOT_INST_PREFIX="${C_DIM}[ ]${C_RESET}"
    local C_PKG_NAME="${C_GREEN}"
    local C_PKG_DESC="${C_DIM}"
    local C_MSG_INSTALL="${C_GREEN}"
    local C_MSG_REMOVE="${C_RED}"
    local C_MSG_INFO="${C_AMBER}"
    local C_MSG_WARN="${C_AMBER}"
    local C_MSG_DONE="${C_TEAL}"

    local _PKGS_CACHE_FILE=""
    local _PKGS_CACHE_VALID=0
    local _PKGS_FILTER="all"
    local _PKGS_SORT="name"
    local _PKGS_HISTORY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/history"
    local _PKGS_HISTORY_FILE="${_PKGS_HISTORY_DIR}/$(date +%Y-%m-%d).log"

    _pkgs_validate_name() {
        [[ "$1" =~ ^[a-zA-Z0-9.+\-]+$ ]]
    }

    _pkgs_invalidate_cache() {
        _PKGS_CACHE_VALID=0
        [[ -n "$_PKGS_CACHE_FILE" && -f "$_PKGS_CACHE_FILE" ]] && rm -f "$_PKGS_CACHE_FILE"
        _PKGS_CACHE_FILE=""
    }

    _pkgs_log_history() {
        local action="$1" pkg_name="$2"
        mkdir -p "$_PKGS_HISTORY_DIR" 2>/dev/null
        printf "%s %s %s\n" "$(date +%H:%M:%S)" "$action" "$pkg_name" >> "$_PKGS_HISTORY_FILE"
    }

    _pkgs_show_info() {
        local pkg_name="$1"
        local info
        info=$(apt-cache show "$pkg_name" 2>/dev/null) || {
            printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$pkg_name"
            return 1
        }
        clear
        printf "\n  ${C_GREEN}┌──────────────────────────────────────────────┐${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_WHITE}%-44s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$pkg_name"
        printf "  ${C_GREEN}├──────────────────────────────────────────────┤${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Version:%-36s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$(echo "$info" | grep '^Version:' | head -1 | sed 's/^Version: //')"
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Section:%-36s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$(echo "$info" | grep '^Section:' | head -1 | sed 's/^Section: //')"
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Maintainer:%-32s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$(echo "$info" | grep '^Maintainer:' | head -1 | sed 's/^Maintainer: //' | cut -c1-32)"
        local size
        size=$(echo "$info" | grep '^Installed-Size:' | head -1 | sed 's/^Installed-Size: //')
        if [[ -n "$size" ]] && command -v numfmt >/dev/null 2>&1; then
            size=$(printf "%s" "$((size * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${size} KiB")
        else
            size="${size:-?} KiB"
        fi
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Size:%-38s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$size"
        local status_str="not installed"
        if dpkg -s "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
            status_str="${C_GREEN}installed${C_RESET}"
        fi
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Status:%-37s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$status_str"
        printf "  ${C_GREEN}├──────────────────────────────────────────────┤${C_RESET}\n"
        local desc
        desc=$(echo "$info" | sed -n '/^Description:/{ s/^Description: //p; :a; n; /^ /{ s/^ //p; ba }; }')
        printf "  ${C_GREEN}│${C_RESET}  ${C_WHITE}Description:${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}%s${C_RESET}\n" "$(echo "$desc" | head -6)"
        printf "  ${C_GREEN}└──────────────────────────────────────────────┘${C_RESET}\n"
        printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
        read -r
    }

    _pkgs_show_help() {
        clear
        printf "\n  ${C_GREEN}┌──────────────────────────────────────────────┐${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_WHITE}  Package Manager - Help${C_RESET}            ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}├──────────────────────────────────────────────┤${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}                                              ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_AMBER}Slash Commands${C_RESET}                             ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/upgrade${C_RESET}        Upgrade all packages    ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/install <pkg>${C_RESET}    Install by name         ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/remove <pkg>${C_RESET}     Remove by name          ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/export <pkg>${C_RESET}     Export install script    ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/info <pkg>${C_RESET}       Full package info       ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/search <text>${C_RESET}    Search descriptions     ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/rdeps <pkg>${C_RESET}      Reverse dependencies    ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/clean${C_RESET}            Clean orphans + cache   ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/installed${C_RESET}       Show only installed      ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/available${C_RESET}       Show only available      ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/all${C_RESET}             Show all packages        ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/sort name${C_RESET} or ${C_TEAL}/sort size${C_RESET}  Sort packages    ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/history${C_RESET}         View today's log         ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/undo${C_RESET}            Undo last operation      ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/help${C_RESET}            Show this help           ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}                                              ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_AMBER}Keybindings${C_RESET}                              ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}?${C_RESET}              Toggle preview          ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}Tab${C_RESET}            Multi-select             ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}                                              ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}└──────────────────────────────────────────────┘${C_RESET}\n"
        printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
        read -r
    }

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
        local filter="$_PKGS_FILTER"
        local sort_mode="$_PKGS_SORT"
        local list_output
        list_output=$(awk -v c_inst="$C_INST_PREFIX" -v c_not_inst="$C_NOT_INST_PREFIX" \
            -v c_name="$C_PKG_NAME" -v c_desc="$C_PKG_DESC" -v c_reset="$C_RESET" \
            -v filter="$filter" '
        NR==FNR { installed[$1]=1; next }
        {
            match($0, / - /)
            if (RSTART > 0) {
                name = substr($0, 1, RSTART-1)
                gsub(/[[:space:]]/, "", name)
                desc = substr($0, RSTART+3)
                is_inst = (name in installed)
                if (filter == "installed" && !is_inst) next
                if (filter == "available" && is_inst) next
                prefix = is_inst ? c_inst : c_not_inst
                printf "%s|%s %s%s%s - %s%s%s\n", name, prefix, c_name, name, c_reset, c_desc, desc, c_reset
            }
        }
        ' <(dpkg-query -W -f='${Package}\n') <(apt-cache search ".*"))
        if [[ "$sort_mode" == "size" ]]; then
            local -A pkg_sizes
            while read -r pname psize; do
                [[ -n "$pname" ]] && pkg_sizes[$pname]=$psize
            done < <(dpkg-query -W -f='${Package} ${Installed-Size}\n' 2>/dev/null)
            local line
            while IFS= read -r line; do
                local pkg="${line%%|*}"
                local size="${pkg_sizes[$pkg]:-0}"
                printf "%010d|%s\n" "$size" "$line"
            done <<< "$list_output" | sort -t'|' -k1,1 -rn | cut -d'|' -f2-
        else
            echo "$list_output" | sort -t'|' -k1,1
        fi
    }

    _pkgs_get_cached_list() {
        if (( _PKGS_CACHE_VALID )) && [[ -n "$_PKGS_CACHE_FILE" && -f "$_PKGS_CACHE_FILE" ]]; then
            cat "$_PKGS_CACHE_FILE"
        else
            _PKGS_CACHE_FILE=$(mktemp "${TMPDIR:-/tmp}/pkgs_cache.XXXXXX")
            _pkgs_generate_list > "$_PKGS_CACHE_FILE"
            _PKGS_CACHE_VALID=1
            cat "$_PKGS_CACHE_FILE"
        fi
    }

    _pkgs_preview_command() {
        echo 'pkg_name={1}
pkg=$(apt-cache show "$pkg_name" 2>/dev/null) || { echo "Package not found"; exit 0; }
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
printf "\n--- REVERSE DEPS ---\n"
if [ -z "$pkg" ]; then
    echo "Package not found."
else
    rdeps=$(apt-cache rdepends "$pkg_name" 2>/dev/null | tail -n +3 | head -n 5 | xargs 2>/dev/null)
    if [ -z "$rdeps" ]; then
        echo "Nothing depends on this."
    else
        echo "$rdeps"
    fi
fi
if dpkg -s "$pkg_name" 2>/dev/null | grep -q "^Status: install ok installed"; then
    printf "\n--- INSTALLED FILES ---\n"
    dpkg -L "$pkg_name" 2>/dev/null | grep -v "^/\\." | tail -n 10 | xargs
fi
printf "\n--- DESCRIPTION ---\n"
echo "$pkg" | sed -n "/^Description:/ { s/^Description: //p; :a; n; /^ / { s/^ //p; ba }; }"'
    }
    _pkgs_build_fzf_args() {
        local query="$1"
        local header="$2"
        local filter_label=""
        case "$_PKGS_FILTER" in
            installed) filter_label=" [installed]" ;;
            available) filter_label=" [available]" ;;
            *) filter_label="" ;;
        esac
        local sort_label=""
        [[ "$_PKGS_SORT" == "size" ]] && sort_label=" [by size]"
        local info_label="${filter_label}${sort_label}"
        FZF_ARGS=(
            --ansi
            --query "$query"
            --layout=reverse
            --border="$BORDER_STYLE"
            --border-label="  Packages${info_label} "
            --preview-label="  Details "
            --prompt="  > "
            --pointer="➜"
            --info=inline
            --multi
            --print-query
            --color='fg:223,bg:-1,hl:114,fg+:223,bg+:235,hl+:109,info:109,prompt:180,pointer:203,marker:114,spinner:139,header:59'
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
        [[ -n "$header" ]] && FZF_ARGS+=(--header="$header")
    }

    _pkgs_strip_ansi() {
        setopt localoptions EXTENDED_GLOB
        local text="$1"
        text="${text//$'\033'\[[0-9;]*[a-zA-Z]/}"
        print -- "$text"
    }

    local PREVIEW_LAYOUT=$(_pkgs_detect_layout)

    local query="$*"

    trap '_pkgs_invalidate_cache' EXIT INT TERM

    while true; do
        local -a FZF_ARGS
        local status_msg=""
        case "$_PKGS_FILTER" in
            installed) status_msg="Showing: installed only" ;;
            available) status_msg="Showing: available only" ;;
        esac
        [[ "$_PKGS_SORT" == "size" ]] && status_msg="${status_msg:+$status_msg | }Sorted by: size"
        _pkgs_build_fzf_args "$query" "$status_msg"

        local output
        output=$(_pkgs_get_cached_list | fzf "${FZF_ARGS[@]}")
        local ret=$?

        [[ $ret -ne 0 ]] && { clear; break; }
        [[ -z "$output" ]] && continue

        output=$(_pkgs_strip_ansi "$output")
        local -a lines=("${(@f)output}")
        [[ ${#lines[@]} -lt 1 ]] && continue

        local query="${lines[1]}"
        query="$(print -r -- "$query" | xargs)"

        if [[ "$query" == /help ]]; then
            _pkgs_show_help
            continue
        fi

        if [[ "$query" == /upgrade ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Upgrading all packages... ---${C_RESET}\n"
            if "${PKG_MGR}" upgrade --; then
                _pkgs_log_history "UPGRADE" "all"
                printf "${C_MSG_DONE}--- Upgrade completed successfully ---${C_RESET}\n"
            else
                printf "${C_MSG_REMOVE}--- Upgrade encountered errors ---${C_RESET}\n"
            fi
            _pkgs_invalidate_cache
            printf "\n${C_MSG_INFO}Press Enter to exit.${C_RESET}\n"
            read -r
            clear
            continue
        fi

        if [[ "$query" == /installed ]]; then
            _PKGS_FILTER="installed"
            _pkgs_invalidate_cache
            query=""
            continue
        fi

        if [[ "$query" == /available ]]; then
            _PKGS_FILTER="available"
            _pkgs_invalidate_cache
            query=""
            continue
        fi

        if [[ "$query" == /all ]]; then
            _PKGS_FILTER="all"
            _pkgs_invalidate_cache
            query=""
            continue
        fi

        if [[ "$query" == /sort* ]]; then
            local sort_arg=""
            if [[ "$query" != "/sort" ]]; then
                sort_arg="${query#* }"
                sort_arg="$(print -r -- "$sort_arg" | xargs)"
            fi
            if [[ "$sort_arg" == "name" || "$sort_arg" == "size" ]]; then
                _PKGS_SORT="$sort_arg"
                _pkgs_invalidate_cache
            elif [[ -z "$sort_arg" ]]; then
                printf "${C_MSG_WARN}Usage: /sort name or /sort size${C_RESET}\n"
                sleep 1
            else
                printf "${C_MSG_REMOVE}Invalid sort: %s (use name or size)${C_RESET}\n" "$sort_arg"
                sleep 1
            fi
            query=""
            continue
        fi

        if [[ "$query" == /history ]]; then
            clear
            printf "\n  ${C_GREEN}── History (${C_WHITE}$(date +%Y-%m-%d)${C_GREEN}) ──${C_RESET}\n\n"
            if [[ -f "$_PKGS_HISTORY_FILE" ]]; then
                while IFS= read -r hline; do
                    local htime="${hline%% *}"
                    local rest="${hline#* }"
                    local haction="${rest%% *}"
                    local hpkg="${rest#* }"
                    case "$haction" in
                        INSTALL) printf "  ${C_DIM}%s${C_RESET}  ${C_GREEN}%-10s${C_RESET} %s\n" "$htime" "$haction" "$hpkg" ;;
                        REMOVE)  printf "  ${C_DIM}%s${C_RESET}  ${C_RED}%-10s${C_RESET} %s\n" "$htime" "$haction" "$hpkg" ;;
                        UPGRADE) printf "  ${C_DIM}%s${C_RESET}  ${C_AMBER}%-10s${C_RESET} %s\n" "$htime" "$haction" "$hpkg" ;;
                        *)       printf "  ${C_DIM}%s${C_RESET}  ${C_DIM}%-10s${C_RESET} %s\n" "$htime" "$haction" "$hpkg" ;;
                    esac
                done < "$_PKGS_HISTORY_FILE"
            else
                printf "  ${C_DIM}No history for today.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            continue
        fi

        if [[ "$query" == /undo ]]; then
            clear
            if [[ ! -f "$_PKGS_HISTORY_FILE" ]] || [[ ! -s "$_PKGS_HISTORY_FILE" ]]; then
                printf "\n  ${C_MSG_REMOVE}Nothing to undo.${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                clear
                continue
            fi
            local last_line
            last_line=$(tail -1 "$_PKGS_HISTORY_FILE")
            local ltime="${last_line%% *}"
            local lrest="${last_line#* }"
            local laction="${lrest%% *}"
            local lpkg="${lrest#* }"
            printf "\n  ${C_MSG_INFO}Last action:${C_RESET} %s %s at %s\n" "$laction" "$lpkg" "$ltime"
            printf "  ${C_MSG_INFO}Undo? (y/N) ${C_RESET}"
            read -q confirm; read -r
            printf "\n"
            if [[ "$confirm" == "y" ]]; then
                case "$laction" in
                    INSTALL)
                        printf "  ${C_MSG_REMOVE}Removing %s...${C_RESET}\n" "$lpkg"
                        if "${PKG_MGR}" remove -- "$lpkg"; then
                            _pkgs_log_history "UNDO-REMOVE" "$lpkg"
                            printf "  ${C_MSG_DONE}Done.${C_RESET}\n"
                        else
                            printf "  ${C_MSG_REMOVE}Failed.${C_RESET}\n"
                        fi
                        ;;
                    REMOVE)
                        printf "  ${C_MSG_INSTALL}Re-installing %s...${C_RESET}\n" "$lpkg"
                        if "${PKG_MGR}" install -- "$lpkg"; then
                            _pkgs_log_history "UNDO-INSTALL" "$lpkg"
                            printf "  ${C_MSG_DONE}Done.${C_RESET}\n"
                        else
                            printf "  ${C_MSG_REMOVE}Failed.${C_RESET}\n"
                        fi
                        ;;
                    *)
                        printf "  ${C_MSG_REMOVE}Cannot undo: %s${C_RESET}\n" "$laction"
                        ;;
                esac
                _pkgs_invalidate_cache
            else
                printf "  ${C_DIM}Cancelled.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            continue
        fi

        if [[ "$query" == /info* ]]; then
            if [[ "$query" == "/info" ]]; then
                printf "${C_MSG_WARN}Usage: /info <package>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local info_pkg="${query#* }"
            info_pkg="$(print -r -- "$info_pkg" | xargs)"
            if [[ -z "$info_pkg" ]]; then
                query=""
                continue
            fi
            if ! _pkgs_validate_name "$info_pkg"; then
                printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$info_pkg"
                sleep 1
                query=""
                continue
            fi
            _pkgs_show_info "$info_pkg"
            clear
            query=""
            continue
        fi

        if [[ "$query" == /clean ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Cleaning apt cache... ---${C_RESET}\n"
            "${PKG_MGR}" clean 2>/dev/null
            printf "${C_MSG_INFO}--- Removing unused dependencies... ---${C_RESET}\n"
            local autoremove_out
            autoremove_out=$("${PKG_MGR}" autoremove --dry-run 2>&1)
            if [[ $? -ne 0 ]] || echo "$autoremove_out" | grep -qE "^0 upgraded, 0 newly installed, 0 to remove"; then
                printf "${C_MSG_DONE}Nothing to remove.${C_RESET}\n"
            else
                printf "${C_MSG_WARN}Remove unused dependencies? (y/N) ${C_RESET}"
                read -q confirm; read -r
                if [[ "$confirm" == "y" ]]; then
                    "${PKG_MGR}" autoremove -y 2>/dev/null
                    _pkgs_log_history "CLEAN" "autoremove+cache"
                    printf "${C_MSG_DONE}Done.${C_RESET}\n"
                else
                    printf "${C_DIM}Cancelled.${C_RESET}\n"
                fi
            fi
            _pkgs_invalidate_cache
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /search* ]]; then
            if [[ "$query" == "/search" ]]; then
                printf "${C_MSG_WARN}Usage: /search <text>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local search_text="${query#* }"
            search_text="$(print -r -- "$search_text" | xargs)"
            if [[ -z "$search_text" ]]; then
                query=""
                continue
            fi
            clear
            printf "\n${C_MSG_INFO}--- Searching descriptions for \"%s\"... ---${C_RESET}\n\n" "$search_text"
            local -a desc_matches=()
            local -a desc_texts=()
            local match_limit=50
            while IFS= read -r line; do
                local dname="${line%% *}"
                local ddesc="${line#* - }"
                if [[ "$ddesc" == *"$search_text"* ]]; then
                    _pkgs_validate_name "$dname" || continue
                    desc_matches+=("$dname")
                    desc_texts+=("$ddesc")
                    if (( ${#desc_matches[@]} >= match_limit )); then
                        break
                    fi
                fi
            done < <(apt-cache search "" 2>/dev/null)
            if [[ ${#desc_matches[@]} -eq 0 ]]; then
                printf "${C_MSG_REMOVE}No packages found.${C_RESET}\n"
            else
                printf "${C_MSG_DONE}Found %d packages:${C_RESET}\n\n" "${#desc_matches[@]}"
                local i
                for i in {1..${#desc_matches[@]}}; do
                    printf "  ${C_GREEN}%-24s${C_RESET} %s\n" "${desc_matches[$i]}" "${desc_texts[$i]:0:48}"
                done
                if (( ${#desc_matches[@]} >= match_limit )); then
                    printf "\n${C_MSG_WARN}Results limited to %d packages. Use a more specific search.${C_RESET}\n" "$match_limit"
                fi
            fi
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /rdeps* ]]; then
            if [[ "$query" == "/rdeps" ]]; then
                printf "${C_MSG_WARN}Usage: /rdeps <package>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local rdeps_pkg="${query#* }"
            rdeps_pkg="$(print -r -- "$rdeps_pkg" | xargs)"
            if [[ -z "$rdeps_pkg" ]]; then
                query=""
                continue
            fi
            clear
            if ! apt-cache show "$rdeps_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$rdeps_pkg"
            else
                printf "\n${C_MSG_INFO}--- Reverse dependencies of %s ---${C_RESET}\n\n" "$rdeps_pkg"
                local rdeps_out
                rdeps_out=$(apt-cache rdepends "$rdeps_pkg" 2>/dev/null | tail -n +3)
                if [[ -z "$rdeps_out" ]]; then
                    printf "${C_DIM}Nothing depends on %s.${C_RESET}\n" "$rdeps_pkg"
                else
                    printf "%s\n" "$rdeps_out"
                fi
            fi
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
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
                _pkgs_validate_name "$name" || continue
                apt-cache show "$name" >/dev/null 2>&1 && match_pkgs+=("$name")
            done < <(apt-cache search -n "$search_term" 2>/dev/null)

            if [[ ${#match_pkgs[@]} -eq 0 ]]; then
                printf "\n${C_MSG_REMOVE}--- No packages matching \"$search_term\" ---${C_RESET}\n\n"
                continue
            fi

            case "$cmd" in
                install|remove)
                    clear
                    local ok=0 fail=0
                    local total=${#match_pkgs[@]}
                    for pkg in "${match_pkgs[@]}"; do
                        printf "${C_MSG_INFO}  [%d/${total}] ${cmd} ${pkg}...${C_RESET}" "$((ok+fail+1))"
                        if "${PKG_MGR}" "$cmd" -- "$pkg"; then
                            _pkgs_log_history "${cmd:u}" "$pkg"
                            printf "\r${C_MSG_DONE}  ✓ ${pkg}${C_RESET}\n"
                            ((ok++))
                        else
                            printf "\r${C_MSG_REMOVE}  ✗ ${pkg} failed${C_RESET}\n"
                            ((fail++))
                        fi
                    done
                    _pkgs_invalidate_cache
                    printf "${C_MSG_INFO}--- %d ok, %d failed ---${C_RESET}\n" "$ok" "$fail"
                    printf "\n"
                    ;;
                export)
                    clear
                    local export_file="pkg-install-$(date +%Y%m%d-%H%M%S).sh"
                    printf "${C_MSG_INFO}Export file path [${C_RESET}%s${C_MSG_INFO}]: ${C_RESET}" "$export_file"
                    local user_path
                    read -r user_path
                    [[ -n "$user_path" ]] && export_file="$user_path"
                    if [[ -n "$export_file" ]] && { [[ -d "$(dirname "$export_file")" ]] || [[ -d "." ]]; }; then
                        {
                            printf "#!/data/data/com.termux/files/usr/bin/sh\n"
                            printf "${PKG_MGR} install \\\\\n"
                            local i
                            for i in {1..${#match_pkgs[@]}}; do
                                if (( i < ${#match_pkgs[@]} )); then
                                    printf "    %s \\\\\n" "${match_pkgs[$i]}"
                                else
                                    printf "    %s\n" "${match_pkgs[$i]}"
                                fi
                            done
                        } > "$export_file"
                        chmod +x "$export_file" 2>/dev/null
                        if [[ -f "$export_file" ]]; then
                            printf "\n${C_MSG_INFO}--- Saved: ${C_RESET}%s${C_MSG_INFO} ---${C_RESET}\n" "$export_file"
                        else
                            printf "${C_MSG_REMOVE}--- Failed to create export file ---${C_RESET}\n"
                        fi
                    else
                        printf "${C_MSG_REMOVE}--- Invalid file path ---${C_RESET}\n"
                    fi
                    printf "\n"
                    ;;
            esac
            printf "${C_MSG_INFO}Press Enter to exit.${C_RESET}\n"
            read -r
            clear
            continue
        fi

        [[ ${#lines[@]} -lt 2 ]] && continue

        local line
        for line in "${(@)lines[2,-1]}"; do
            [[ -z "$line" ]] && continue
            local pkg_name="${line%%|*}"
            [[ -z "$pkg_name" ]] && continue
            _pkgs_validate_name "$pkg_name" || {
                printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$pkg_name"
                continue
            }

            clear && printf "${C_MSG_INFO}Process %s? (y/N) ${C_RESET}" "$pkg_name"
            read -q confirm; read -r
            printf "\n"
            [[ $confirm == 'y' ]] || {
                printf "${C_MSG_INFO}Skipped.${C_RESET}\n"
                continue
            }

            clear
            if dpkg -s "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
                printf "${C_MSG_REMOVE}--- Removing %s ---${C_RESET}\n" "$pkg_name"
                "${PKG_MGR}" remove -- "$pkg_name" || printf "${C_MSG_REMOVE}Remove failed: %s${C_RESET}\n" "$pkg_name"
            else
                if ! apt-cache show "$pkg_name" >/dev/null 2>&1; then
                    printf "${C_MSG_REMOVE}--- %s not found in apt cache ---${C_RESET}\n" "$pkg_name"
                    continue
                fi
                printf "${C_MSG_INSTALL}--- Installing %s ---${C_RESET}\n" "$pkg_name"
                "${PKG_MGR}" install -- "$pkg_name" || printf "${C_MSG_REMOVE}Install failed: %s${C_RESET}\n" "$pkg_name"
            fi
            _pkgs_invalidate_cache
        done
        printf "${C_MSG_INFO}Press Enter to exit.${C_RESET}\n"
        read -r
        clear
    done
    _pkgs_invalidate_cache
    clear
}

_pkgs_usage() {
    cat <<'USAGE'
Usage: pkgs [OPTIONS] [QUERY]

Interactive TUI package manager for Termux.

Options:
  -h, --help       Show this help message
  -v, --version    Show version

Interactive Commands (type in search box):
  /upgrade              Upgrade all packages
  /install <pkg>        Install package by name
  /remove <pkg>         Remove package by name
  /export <pkg>         Export install script to .sh file
  /info <pkg>           Show full package details
  /search <text>        Search package descriptions
  /rdeps <pkg>          Show reverse dependencies
  /clean                Remove orphaned packages and cache
  /installed            Filter: show only installed
  /available            Filter: show only available
  /all                  Reset filter: show everything
  /sort name or /sort size  Sort by name or size
  /history              View today's operation log
  /undo                 Reverse last install/remove
  /help                 Show in-app help

Keybindings:
  ?                     Toggle preview panel
  Tab                   Multi-select packages
  Enter                 Confirm selection
  Esc                   Exit

Examples:
  pkgs                  Launch with no filter
  pkgs vim              Launch pre-filtered for "vim"
  pkgs -h               Show this help
USAGE
}

_pkgs_version() { echo "pkgs 1.1.0"; }

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    _pkgs_usage
    exit 0
fi
if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    _pkgs_version
    exit 0
fi

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && pkgs "$@"
