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
    local _PKGS_NOTES_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/notes"

    _pkgs_validate_name() {
        [[ "$1" =~ ^[a-zA-Z0-9.+\-]+$ ]]
    }

    _pkgs_validate_export_path() {
        local path="$1"
        [[ -z "$path" ]] && return 1
        [[ "$path" =~ ^[[:space:]] ]] && return 1
        local dir
        dir=$(dirname "$path" 2>/dev/null)
        [[ -z "$dir" || ! -d "$dir" ]] && return 1
        local resolved
        resolved=$(readlink -f "$path" 2>/dev/null || echo "$path")
        local prefix_dir
        prefix_dir=$(readlink -f "${PREFIX}" 2>/dev/null || echo "${PREFIX}")
        [[ "$resolved" == "$prefix_dir/bin/pkgs" ]] && return 1
        return 0
    }

    local _HAS_NUMFMT=0
    command -v numfmt >/dev/null 2>&1 && _HAS_NUMFMT=1

    local _PKGS_TMP_FILES=()
    _pkgs_cleanup() {
        local f
        for f in "${_PKGS_TMP_FILES[@]}"; do
            [[ -n "$f" && -f "$f" ]] && rm -f "$f" 2>/dev/null
        done
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
        if [[ -n "$size" && "$size" =~ ^[0-9]+$ ]] && (( _HAS_NUMFMT )); then
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
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/compare <a> <b>${C_RESET} Compare packages       ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/note <pkg> <text>${C_RESET} Add/view package note  ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/deps <pkg>${C_RESET}      Show dependencies      ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/tree <pkg>${C_RESET}      Dependency tree        ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/orphans${C_RESET}         Show orphaned packages ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/top${C_RESET}            Top 10 largest pkgs    ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/size${C_RESET}           Total installed size   ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/count${C_RESET}          Count packages         ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/update${C_RESET}         Update apt cache       ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/export-all${C_RESET}     Export all installed   ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/clean${C_RESET}            Clean orphans + cache   ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/installed${C_RESET}       Show only installed      ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/available${C_RESET}       Show only available      ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/recent${C_RESET}          Show installed today     ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/usage${C_RESET}           Disk usage by section    ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/all${C_RESET}             Show all packages        ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/sort name${C_RESET} or ${C_TEAL}/sort size${C_RESET}  Sort packages    ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/history${C_RESET}         View today's log         ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/backup${C_RESET}          Export full package list ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/restore <file>${C_RESET}  Install from list file  ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/undo${C_RESET}            Undo last operation      ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}/help${C_RESET}            Show this help           ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}                                              ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_AMBER}Keybindings${C_RESET}                              ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}?${C_RESET}              Toggle preview          ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}Tab${C_RESET}            Multi-select             ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}Ctrl-A${C_RESET}          Select all visible       ${C_GREEN}│${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}    ${C_TEAL}Ctrl-D${C_RESET}          Deselect all             ${C_GREEN}│${C_RESET}\n"
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

        if [[ "$filter" == "recent" ]]; then
            local today
            today=$(date +%Y-%m-%d)
            local recent_pkgs=""
            local dpkg_log="/data/data/com.termux/files/usr/var/log/dpkg.log"
            if [[ -f "$dpkg_log" ]]; then
                recent_pkgs=$(grep "^$today.* install " "$dpkg_log" 2>/dev/null | awk '{print $3}' | sort -u)
            fi
            if [[ -z "$recent_pkgs" ]]; then
                list_output=""
            else
                list_output=$(awk -v c_inst="$C_INST_PREFIX" -v c_not_inst="$C_NOT_INST_PREFIX" \
                    -v c_name="$C_PKG_NAME" -v c_desc="$C_PKG_DESC" -v c_reset="$C_RESET" '
                NR==FNR { installed[$1]=1; next }
                {
                    match($0, / - /)
                    if (RSTART > 0) {
                        name = substr($0, 1, RSTART-1)
                        gsub(/[[:space:]]/, "", name)
                        desc = substr($0, RSTART+3)
                        is_inst = (name in installed)
                        if (!is_inst) next
                        prefix = c_inst
                        printf "%s|%s %s%s%s - %s%s%s\n", name, prefix, c_name, name, c_reset, c_desc, desc, c_reset
                    }
                }
                ' <(echo "$recent_pkgs") <(apt-cache search ".*"))
            fi
        else
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
        fi

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
            chmod 600 "$_PKGS_CACHE_FILE" 2>/dev/null
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
            --bind 'ctrl-a:select-all'
            --bind 'ctrl-d:deselect-all'
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

    trap '_pkgs_invalidate_cache; _pkgs_cleanup' EXIT INT TERM

    while true; do
        local -a FZF_ARGS
        local status_msg=""
        case "$_PKGS_FILTER" in
            installed) status_msg="Showing: installed only" ;;
            available) status_msg="Showing: available only" ;;
            recent) status_msg="Showing: installed today" ;;
        esac
        [[ "$_PKGS_SORT" == "size" ]] && status_msg="${status_msg:+$status_msg | }Sorted by: size"
        _pkgs_build_fzf_args "$query" "$status_msg"

        local output
        output=$(_pkgs_get_cached_list | fzf "${FZF_ARGS[@]}")
        local ret=$?

        [[ $ret -ne 0 && -z "$output" ]] && { clear; break; }
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
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}\n"
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

        if [[ "$query" == /recent ]]; then
            _PKGS_FILTER="recent"
            _pkgs_invalidate_cache
            query=""
            continue
        fi

        if [[ "$query" == /usage ]]; then
            clear
            printf "\n  ${C_GREEN}── Disk Usage by Section ──${C_RESET}\n\n"
            local total_size=0
            local -A section_sizes
            while read -r line; do
                local pkg_name="${line%% *}"
                local rest="${line#* }"
                local inst_size="${rest%% *}"
                [[ -z "$inst_size" || "$inst_size" == "?" ]] && continue
                local section
                section=$(apt-cache show "$pkg_name" 2>/dev/null | grep '^Section:' | head -1 | sed 's/^Section: //' | cut -d'/' -f1)
                [[ -z "$section" ]] && section="other"
                section_sizes[$section]=$(( ${section_sizes[$section]:-0} + inst_size ))
                total_size=$(( total_size + inst_size ))
            done < <(dpkg-query -W -f='${Package} ${Installed-Size}\n' 2>/dev/null)

            local -a sorted_sections=()
            for section in "${(k)section_sizes[@]}"; do
                sorted_sections+=("${section_sizes[$section]} $section")
            done
            sorted_sections=("${(@o)sorted_sections}")

            local max_name_len=0
            for entry in "${sorted_sections[@]}"; do
                local sname="${entry#* }"
                (( ${#sname} > max_name_len )) && max_name_len=${#sname}
            done

            for entry in "${sorted_sections[@]}"; do
                local ssize="${entry%% *}"
                local sname="${entry#* }"
                local pct=0
                (( total_size > 0 )) && pct=$(( ssize * 100 / total_size ))
                local display_size
                if (( _HAS_NUMFMT )); then
                    display_size=$(printf "%s" "$((ssize * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${ssize} KiB")
                else
                    display_size="${ssize} KiB"
                fi
                local bar_len=$(( pct / 5 ))
                local bar=""
                local i
                for i in {1..$bar_len}; do
                    bar="${bar}█"
                done
                printf "  ${C_WHITE}%-${max_name_len}s${C_RESET}  ${C_TEAL}%-10s${C_RESET} ${C_DIM}%3d%%${C_RESET} ${C_DIM}%s${C_RESET}\n" \
                    "$sname" "$display_size" "$pct" "$bar"
            done

            local total_display
            if (( _HAS_NUMFMT )); then
                total_display=$(printf "%s" "$((total_size * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${total_size} KiB")
            else
                total_display="${total_size} KiB"
            fi
            printf "\n  ${C_GREEN}Total:${C_RESET} %s across %d sections\n" "$total_display" "${#section_sizes[@]}"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /deps* ]]; then
            if [[ "$query" == "/deps" ]]; then
                printf "${C_MSG_WARN}Usage: /deps <pkg>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local deps_pkg="${query#* }"
            deps_pkg="$(print -r -- "$deps_pkg" | xargs)"
            if [[ -z "$deps_pkg" ]]; then
                printf "${C_MSG_WARN}Usage: /deps <pkg>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            if ! _pkgs_validate_name "$deps_pkg"; then
                printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$deps_pkg"
                sleep 1
                query=""
                continue
            fi
            clear
            if ! apt-cache show "$deps_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$deps_pkg"
            else
                printf "\n${C_MSG_INFO}--- Dependencies of %s ---${C_RESET}\n\n" "$deps_pkg"
                local deps_out
                deps_out=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$deps_pkg" 2>/dev/null | grep "^\w" | sort -u)
                if [[ -z "$deps_out" ]]; then
                    printf "${C_DIM}No dependencies.${C_RESET}\n"
                else
                    printf "%s\n" "$deps_out"
                fi
            fi
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /tree* ]]; then
            if [[ "$query" == "/tree" ]]; then
                printf "${C_MSG_WARN}Usage: /tree <pkg>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local tree_pkg="${query#* }"
            tree_pkg="$(print -r -- "$tree_pkg" | xargs)"
            if [[ -z "$tree_pkg" ]]; then
                printf "${C_MSG_WARN}Usage: /tree <pkg>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            if ! _pkgs_validate_name "$tree_pkg"; then
                printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$tree_pkg"
                sleep 1
                query=""
                continue
            fi
            clear
            if ! apt-cache show "$tree_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$tree_pkg"
            else
                printf "\n${C_MSG_INFO}--- Dependency tree for %s ---${C_RESET}\n\n" "$tree_pkg"
                apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$tree_pkg" 2>/dev/null | head -50
                local total_deps
                total_deps=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$tree_pkg" 2>/dev/null | grep "^\w" | sort -u | wc -l | xargs)
                printf "\n  ${C_DIM}Total unique dependencies: %s${C_RESET}\n" "$total_deps"
            fi
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /orphans ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Orphaned Packages (auto-installed, no dependents) ---${C_RESET}\n\n"
            local orphans_out
            orphans_out=$(apt-cache showpkg 2>/dev/null | awk '/^Package:/{pkg=$2} /^ReverseDependencies:/{if(NF==1) print pkg}' | sort -u)
            if [[ -z "$orphans_out" ]]; then
                printf "${C_DIM}No orphaned packages found.${C_RESET}\n"
            else
                printf "%s\n" "$orphans_out"
                local orphans_count
                orphans_count=$(echo "$orphans_out" | wc -l | xargs)
                printf "\n  ${C_DIM}Total orphaned: %s${C_RESET}\n" "$orphans_count"
            fi
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /top ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Top 10 Largest Installed Packages ---${C_RESET}\n\n"
            printf "  ${C_DIM}%-4s %-24s %-10s${C_RESET}\n" "#" "Package" "Size"
            printf "  ${C_DIM}%-4s %-24s %-10s${C_RESET}\n" "---" "-------" "----"
            local shown=0
            while read -r line; do
                [[ $shown -ge 10 ]] && break
                local pkg_name="${line%% *}"
                local rest="${line#* }"
                local pkg_size="${rest%% *}"
                [[ -z "$pkg_size" || "$pkg_size" == "?" ]] && continue
                ((shown++))
                local display_size
                if (( _HAS_NUMFMT )); then
                    display_size=$(printf "%s" "$((pkg_size * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${pkg_size} KiB")
                else
                    display_size="${pkg_size} KiB"
                fi
                printf "  ${C_WHITE}%-4s${C_RESET} ${C_TEAL}%-24s${C_RESET} ${C_AMBER}%-10s${C_RESET}\n" "$shown" "$pkg_name" "$display_size"
            done < <(dpkg-query -W -f='${Package} ${Installed-Size}\n' 2>/dev/null | sort -k2 -rn)
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /size ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Total Installed Size ---${C_RESET}\n\n"
            local total_size_kb
            total_size_kb=$(dpkg-query -W -f='${Installed-Size}\n' 2>/dev/null | awk '{s+=$1}END{print s}')
            local total_pkgs
            total_pkgs=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | wc -l | xargs)
            local display_total
            if (( _HAS_NUMFMT )); then
                display_total=$(printf "%s" "$((total_size_kb * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${total_size_kb} KiB")
            else
                display_total="${total_size_kb} KiB"
            fi
            printf "  ${C_WHITE}Total packages:${C_RESET}    %s\n" "$total_pkgs"
            printf "  ${C_WHITE}Total size:${C_RESET}        %s\n" "$display_total"
            local avg_kb=0
            (( total_pkgs > 0 )) && avg_kb=$(( total_size_kb / total_pkgs ))
            local avg_display
            if (( _HAS_NUMFMT )); then
                avg_display=$(printf "%s" "$((avg_kb * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${avg_kb} KiB")
            else
                avg_display="${avg_kb} KiB"
            fi
            printf "  ${C_WHITE}Average per package:${C_RESET} %s\n" "$avg_display"
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /count ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Package Counts ---${C_RESET}\n\n"
            local count_installed count_available count_total
            count_installed=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | wc -l | xargs)
            count_total=$(apt-cache search ".*" 2>/dev/null | wc -l | xargs)
            count_available=$(( count_total - count_installed ))
            printf "  ${C_WHITE}Installed:${C_RESET}   %s\n" "$count_installed"
            printf "  ${C_WHITE}Available:${C_RESET}   %s\n" "$count_available"
            printf "  ${C_WHITE}Total:${C_RESET}       %s\n" "$count_total"
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /update ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Updating package cache... ---${C_RESET}\n\n"
            if "${PKG_MGR}" update 2>&1; then
                _pkgs_invalidate_cache
                printf "\n${C_MSG_DONE}Cache updated successfully.${C_RESET}\n"
            else
                printf "\n${C_MSG_REMOVE}Update encountered errors.${C_RESET}\n"
            fi
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /export-all ]]; then
            clear
            local export_all_file="pkg-export-all-$(date +%Y%m%d-%H%M%S).sh"
            printf "${C_MSG_INFO}Export path [${C_RESET}%s${C_MSG_INFO}]: ${C_RESET}" "$export_all_file"
            local user_path
            read -r user_path
            [[ -n "$user_path" ]] && export_all_file="$user_path"
            if ! _pkgs_validate_export_path "$export_all_file"; then
                printf "${C_MSG_REMOVE}Invalid or unsafe file path${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            {
                printf "#!/data/data/com.termux/files/usr/bin/sh\n"
                printf "# Exported all installed packages by pkgs on $(date)\n\n"
                printf "${PKG_MGR} install \\\\\n"
                local -a all_pkgs
                all_pkgs=(${(@f)$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)})
                local i
                for i in {1..${#all_pkgs[@]}}; do
                    if (( i < ${#all_pkgs[@]} )); then
                        printf "    %s \\\\\n" "${all_pkgs[$i]}"
                    else
                        printf "    %s\n" "${all_pkgs[$i]}"
                    fi
                done
            } > "$export_all_file"
            chmod +x "$export_all_file" 2>/dev/null
            local pkg_count
            pkg_count=$(wc -l < "$export_all_file" | xargs)
            printf "\n${C_MSG_DONE}Exported %s packages to: %s${C_RESET}\n" "$((pkg_count - 4))" "$export_all_file"
            printf "\n${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /note* ]]; then
            if [[ "$query" == "/note" ]]; then
                if [[ -f "$_PKGS_NOTES_FILE" ]] && [[ -s "$_PKGS_NOTES_FILE" ]]; then
                    clear
                    printf "\n  ${C_GREEN}── Package Notes ──${C_RESET}\n\n"
                    while IFS= read -r fullline; do
                        local npkg="${fullline%%|*}"
                        local nnote="${fullline#*|}"
                        printf "  ${C_WHITE}%-24s${C_RESET} %s\n" "$npkg" "$nnote"
                    done < "$_PKGS_NOTES_FILE"
                    printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                    read -r
                    clear
                else
                    printf "${C_DIM}No notes yet.${C_RESET}\n"
                    sleep 1
                fi
                query=""
                continue
            fi
            local note_action="${query#* }"
            if [[ "$note_action" == *" "* ]]; then
                local note_pkg="${note_action%% *}"
                local note_text="${note_action#* }"
                note_pkg="$(print -r -- "$note_pkg" | xargs)"
                note_text="$(print -r -- "$note_text" | xargs)"
                if [[ -z "$note_pkg" || -z "$note_text" ]]; then
                    printf "${C_MSG_WARN}Usage: /note <pkg> <text>${C_RESET}\n"
                    sleep 1
                    query=""
                    continue
                fi
                mkdir -p "$(dirname "$_PKGS_NOTES_FILE")" 2>/dev/null
                if [[ -f "$_PKGS_NOTES_FILE" ]] && grep -q "^${note_pkg}|" "$_PKGS_NOTES_FILE" 2>/dev/null; then
                    local tmp_notes
                    tmp_notes=$(mktemp)
                    chmod 600 "$tmp_notes" 2>/dev/null
                    _PKGS_TMP_FILES+=("$tmp_notes")
                    while IFS='|' read -r _np _nt; do
                        if [[ "$_np" == "$note_pkg" ]]; then
                            printf "%s|%s\n" "$note_pkg" "$note_text"
                        else
                            printf "%s|%s\n" "$_np" "$_nt"
                        fi
                    done < "$_PKGS_NOTES_FILE" > "$tmp_notes"
                    mv "$tmp_notes" "$_PKGS_NOTES_FILE"
                else
                    printf "%s|%s\n" "$note_pkg" "$note_text" >> "$_PKGS_NOTES_FILE"
                fi
                printf "${C_MSG_DONE}Note saved for %s${C_RESET}\n" "$note_pkg"
            else
                local note_pkg="$(print -r -- "$note_action" | xargs)"
                if [[ -z "$note_pkg" ]]; then
                    printf "${C_MSG_WARN}Usage: /note <pkg> <text> or /note <pkg>${C_RESET}\n"
                    sleep 1
                    query=""
                    continue
                fi
                if [[ -f "$_PKGS_NOTES_FILE" ]] && grep -q "^${note_pkg}|" "$_PKGS_NOTES_FILE" 2>/dev/null; then
                    local existing
                    existing=$(grep -m1 "^${note_pkg}|" "$_PKGS_NOTES_FILE" | cut -d'|' -f2-)
                    printf "  ${C_WHITE}%-24s${C_RESET} %s\n" "$note_pkg" "$existing"
                else
                    printf "${C_DIM}No note for %s${C_RESET}\n" "$note_pkg"
                fi
            fi
            sleep 1
            query=""
            continue
        fi

        if [[ "$query" == /compare* ]]; then
            local cmp_args="${query#* }"
            if [[ -z "$cmp_args" || "$cmp_args" != *" "* ]]; then
                printf "${C_MSG_WARN}Usage: /compare <pkg1> <pkg2>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local cmp_p1="${cmp_args%% *}"
            local cmp_p2="${cmp_args#* }"
            _pkgs_validate_name "$cmp_p1" || { printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$cmp_p1"; sleep 1; query=""; continue; }
            _pkgs_validate_name "$cmp_p2" || { printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$cmp_p2"; sleep 1; query=""; continue; }
            local info1 info2
            info1=$(apt-cache show "$cmp_p1" 2>/dev/null)
            info2=$(apt-cache show "$cmp_p2" 2>/dev/null)
            if [[ -z "$info1" ]]; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$cmp_p1"
                sleep 1
                query=""
                continue
            fi
            if [[ -z "$info2" ]]; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$cmp_p2"
                sleep 1
                query=""
                continue
            fi
            clear
            printf "\n  ${C_GREEN}── Compare Packages ──${C_RESET}\n\n"
            local v1 s1 d1 sz1
            v1=$(echo "$info1" | grep '^Version:' | head -1 | sed 's/^Version: //')
            s1=$(echo "$info1" | grep '^Section:' | head -1 | sed 's/^Section: //')
            d1=$(echo "$info1" | grep '^Description:' | head -1 | sed 's/^Description: //')
            sz1=$(echo "$info1" | grep '^Installed-Size:' | head -1 | sed 's/^Installed-Size: //')
            local v2 s2 d2 sz2
            v2=$(echo "$info2" | grep '^Version:' | head -1 | sed 's/^Version: //')
            s2=$(echo "$info2" | grep '^Section:' | head -1 | sed 's/^Section: //')
            d2=$(echo "$info2" | grep '^Description:' | head -1 | sed 's/^Description: //')
            sz2=$(echo "$info2" | grep '^Installed-Size:' | head -1 | sed 's/^Installed-Size: //')
            printf "  ${C_DIM}%-16s${C_RESET} ${C_WHITE}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "" "$cmp_p1" "$cmp_p2"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Version" "${v1:-?}" "${v2:-?}"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Section" "${s1:-?}" "${s2:-?}"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Size" "${sz1:-?} KiB" "${sz2:-?} KiB"
            local inst1="no" inst2="no"
            dpkg -s "$cmp_p1" 2>/dev/null | grep -q '^Status: install ok installed' && inst1="yes"
            dpkg -s "$cmp_p2" 2>/dev/null | grep -q '^Status: install ok installed' && inst2="yes"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Installed" "$inst1" "$inst2"
            printf "\n  ${C_WHITE}Description:${C_RESET}\n"
            printf "  ${C_DIM}%-20s${C_RESET} %s\n" "${d1:-?}" "${d2:-?}"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /backup ]]; then
            clear
            local backup_file="pkg-backup-$(date +%Y%m%d-%H%M%S).txt"
            printf "  ${C_MSG_INFO}Export path [${C_RESET}%s${C_MSG_INFO}]: ${C_RESET}" "$backup_file"
            local user_path
            read -r user_path
            [[ -n "$user_path" ]] && backup_file="$user_path"
            if ! _pkgs_validate_export_path "$backup_file"; then
                printf "\n  ${C_MSG_REMOVE}Invalid or unsafe file path${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            dpkg-query -W -f='${Package}\n' 2>/dev/null | sort > "$backup_file"
            if [[ -f "$backup_file" ]] && [[ -s "$backup_file" ]]; then
                local pkg_count
                pkg_count=$(wc -l < "$backup_file" | xargs)
                printf "\n  ${C_MSG_DONE}Saved %s packages to:${C_RESET} %s\n" "$pkg_count" "$backup_file"
                if [[ -f "$_PKGS_NOTES_FILE" && -s "$_PKGS_NOTES_FILE" ]]; then
                    local notes_backup="${backup_file%.txt}.notes"
                    cp "$_PKGS_NOTES_FILE" "$notes_backup" 2>/dev/null
                    [[ -f "$notes_backup" ]] && printf "  ${C_MSG_DONE}Notes saved to:${C_RESET} %s\n" "$notes_backup"
                fi
            else
                printf "\n  ${C_MSG_REMOVE}Failed to create backup${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /restore* ]]; then
            if [[ "$query" == "/restore" ]]; then
                printf "${C_MSG_WARN}Usage: /restore <file>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local restore_file="${query#* }"
            restore_file="$(print -r -- "$restore_file" | xargs)"
            if [[ ! -f "$restore_file" ]]; then
                printf "${C_MSG_REMOVE}File not found: %s${C_RESET}\n" "$restore_file"
                sleep 1
                query=""
                continue
            fi
            clear
            local -a restore_pkgs=()
            while IFS= read -r rline; do
                [[ -z "$rline" ]] && continue
                _pkgs_validate_name "$rline" || continue
                apt-cache show "$rline" >/dev/null 2>&1 && restore_pkgs+=("$rline")
            done < "$restore_file"
            if [[ ${#restore_pkgs[@]} -eq 0 ]]; then
                printf "${C_MSG_REMOVE}No valid packages found in file${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local -a to_install_r=()
            for rp in "${restore_pkgs[@]}"; do
                dpkg -s "$rp" 2>/dev/null | grep -q '^Status: install ok installed' || to_install_r+=("$rp")
            done
            printf "\n  ${C_GREEN}── Restore from ${C_WHITE}%s${C_GREEN} ──${C_RESET}\n\n" "$restore_file"
            printf "  ${C_DIM}Total in file:${C_RESET} %d\n" "${#restore_pkgs[@]}"
            printf "  ${C_MSG_INSTALL}To install:${C_RESET} %d\n\n" "${#to_install_r[@]}"
            if (( ${#to_install_r[@]} == 0 )); then
                printf "  ${C_MSG_DONE}All packages already installed.${C_RESET}\n"
            else
                for rp in "${to_install_r[@]}"; do
                    printf "    ${C_GREEN}+ %s${C_RESET}\n" "$rp"
                done
                printf "\n  ${C_MSG_INFO}Install all? (y/N) ${C_RESET}"
                read -q rconfirm; read -r
                printf "\n"
                if [[ "$rconfirm" == "y" ]]; then
                    local rok=0 rfail=0
                    local rtotal=${#to_install_r[@]}
                    for rp in "${to_install_r[@]}"; do
                        printf "${C_MSG_INFO}  [%d/%d] install %s...${C_RESET}" "$((rok+rfail+1))" "$rtotal" "$rp"
                        if "${PKG_MGR}" install -- "$rp" 2>/dev/null; then
                            _pkgs_log_history "RESTORE" "$rp"
                            printf "\r${C_MSG_DONE}  [%d/%d] ✓ %s${C_RESET}\n" "$((rok+rfail+1))" "$rtotal" "$rp"
                            ((rok++))
                        else
                            printf "\r${C_MSG_REMOVE}  [%d/%d] ✗ %s failed${C_RESET}\n" "$((rok+rfail+1))" "$rtotal" "$rp"
                            ((rfail++))
                        fi
                    done
                    _pkgs_invalidate_cache
                    printf "\n  ${C_MSG_DONE}Done:${C_RESET} %d ok, %d failed\n" "$rok" "$rfail"
                else
                    printf "  ${C_DIM}Cancelled.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
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
            if ! autoremove_out=$("${PKG_MGR}" autoremove --dry-run 2>&1); then
                printf "${C_MSG_WARN}Could not check dependencies: %s${C_RESET}\n" "$autoremove_out"
            elif echo "$autoremove_out" | grep -qE "^0 upgraded, 0 newly installed, 0 to remove"; then
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
                _pkgs_validate_name "$dname" || continue
                desc_matches+=("$dname")
                desc_texts+=("$ddesc")
                if (( ${#desc_matches[@]} >= match_limit )); then
                    break
                fi
            done < <(apt-cache search "$search_text" 2>/dev/null)
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
            if ! _pkgs_validate_name "$rdeps_pkg"; then
                printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$rdeps_pkg"
                sleep 1
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
            if [[ "$query" != *" "* ]]; then
                printf "${C_MSG_WARN}Usage: /%s <search>${C_RESET}\n" "$cmd"
                sleep 1
                query=""
                continue
            fi
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
                    if _pkgs_validate_export_path "$export_file"; then
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
                    else
                        printf "${C_MSG_REMOVE}--- Invalid or unsafe file path ---${C_RESET}\n"
                    fi
                    printf "\n"
                    ;;
            esac
            printf "${C_MSG_INFO}Press Enter to return.${C_RESET}\n"
            read -r
            clear
            continue
        fi

        [[ ${#lines[@]} -lt 2 ]] && continue

        local -a selected_names=()
        local line
        for line in "${(@)lines[2,-1]}"; do
            [[ -z "$line" ]] && continue
            local pkg_name="${line%%|*}"
            [[ -z "$pkg_name" ]] && continue
            _pkgs_validate_name "$pkg_name" || continue
            selected_names+=("$pkg_name")
        done

        [[ ${#selected_names[@]} -eq 0 ]] && continue

        local -a to_install=()
        local -a to_remove=()
        for pkg_name in "${selected_names[@]}"; do
            if dpkg -s "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
                to_remove+=("$pkg_name")
            else
                to_install+=("$pkg_name")
            fi
        done

        clear
        printf "\n  ${C_GREEN}── Selected Packages (${C_WHITE}%d${C_GREEN}) ──${C_RESET}\n\n" "${#selected_names[@]}"
        if (( ${#to_install[@]} > 0 )); then
            printf "  ${C_MSG_INSTALL}Install (${C_WHITE}%d${C_MSG_INSTALL}):${C_RESET}\n" "${#to_install[@]}"
            for pkg in "${to_install[@]}"; do
                printf "    ${C_GREEN}+ %s${C_RESET}\n" "$pkg"
            done
            printf "\n"
        fi
        if (( ${#to_remove[@]} > 0 )); then
            printf "  ${C_MSG_REMOVE}Remove (${C_WHITE}%d${C_MSG_REMOVE}):${C_RESET}\n" "${#to_remove[@]}"
            for pkg in "${to_remove[@]}"; do
                printf "    ${C_RED}- %s${C_RESET}\n" "$pkg"
            done
            printf "\n"
        fi

        printf "  ${C_MSG_INFO}Action: ${C_WHITE}y${C_MSG_INFO}=process  ${C_WHITE}d${C_MSG_INFO}=dry-run  ${C_WHITE}e${C_MSG_INFO}=export  ${C_WHITE}Enter${C_MSG_INFO}=cancel${C_RESET} "
        read -q action; read -r
        printf "\n"

        if [[ "$action" == "d" ]]; then
            clear
            printf "\n  ${C_GREEN}── Dry Run ──${C_RESET}\n\n"
            if (( ${#to_install[@]} > 0 )); then
                printf "  ${C_MSG_INSTALL}Would install:${C_RESET}\n"
                for rp in "${to_install[@]}"; do
                    local dry_deps
                    dry_deps=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$rp" 2>/dev/null | grep "^\w" | sort -u | wc -l | xargs)
                    printf "    ${C_GREEN}+ %-20s${C_RESET} ${C_DIM}%s deps${C_RESET}\n" "$rp" "${dry_deps:-0}"
                done
                printf "\n"
            fi
            if (( ${#to_remove[@]} > 0 )); then
                printf "  ${C_MSG_REMOVE}Would remove:${C_RESET}\n"
                for rp in "${to_remove[@]}"; do
                    local dry_rdeps
                    dry_rdeps=$(apt-cache rdepends "$rp" 2>/dev/null | tail -n +3 | wc -l | xargs)
                    printf "    ${C_RED}- %-20s${C_RESET} ${C_DIM}%s depend on it${C_RESET}\n" "$rp" "${dry_rdeps:-0}"
                done
                printf "\n"
            fi
            printf "  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            continue
        fi

        if [[ "$action" == "e" ]]; then
            local export_file="pkg-install-$(date +%Y%m%d-%H%M%S).sh"
            printf "  ${C_MSG_INFO}Export path [${C_RESET}%s${C_MSG_INFO}]: ${C_RESET}" "$export_file"
            local user_path
            read -r user_path
            [[ -n "$user_path" ]] && export_file="$user_path"
            if ! _pkgs_validate_export_path "$export_file"; then
                printf "  ${C_MSG_REMOVE}Invalid or unsafe file path${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                clear
                continue
            fi
            if [[ -n "$export_file" ]] && { [[ -d "$(dirname "$export_file")" ]] || [[ -d "." ]]; }; then
                {
                    printf "#!/data/data/com.termux/files/usr/bin/sh\n"
                    printf "# Exported by pkgs on $(date)\n\n"
                    if (( ${#to_install[@]} > 0 )); then
                        printf "# Packages to install\n"
                        printf "${PKG_MGR} install \\\\\n"
                        local i
                        for i in {1..${#to_install[@]}}; do
                            if (( i < ${#to_install[@]} )); then
                                printf "    %s \\\\\n" "${to_install[$i]}"
                            else
                                printf "    %s\n" "${to_install[$i]}"
                            fi
                        done
                    fi
                    if (( ${#to_remove[@]} > 0 )); then
                        printf "\n# Packages to remove\n"
                        printf "${PKG_MGR} remove \\\\\n"
                        local i
                        for i in {1..${#to_remove[@]}}; do
                            if (( i < ${#to_remove[@]} )); then
                                printf "    %s \\\\\n" "${to_remove[$i]}"
                            else
                                printf "    %s\n" "${to_remove[$i]}"
                            fi
                        done
                    fi
                } > "$export_file"
                chmod +x "$export_file" 2>/dev/null
                if [[ -f "$export_file" ]]; then
                    printf "  ${C_MSG_DONE}Saved: ${C_RESET}%s\n" "$export_file"
                else
                    printf "  ${C_MSG_REMOVE}Failed to create export file${C_RESET}\n"
                fi
            else
                printf "  ${C_MSG_REMOVE}Invalid file path${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            continue
        fi

        [[ "$action" == "y" ]] || {
            printf "  ${C_DIM}Cancelled.${C_RESET}\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            continue
        }

        clear
        local ok=0 fail=0
        local total=${#selected_names[@]}

        for pkg_name in "${to_install[@]}"; do
            if ! apt-cache show "$pkg_name" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}  [%d/${total}] %s not found in apt cache${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((fail++))
                continue
            fi
            printf "${C_MSG_INFO}  [%d/${total}] install %s...${C_RESET}" "$((ok+fail+1))" "$pkg_name"
            if "${PKG_MGR}" install -- "$pkg_name" 2>/dev/null; then
                _pkgs_log_history "INSTALL" "$pkg_name"
                printf "\r${C_MSG_DONE}  [%d/${total}] ✓ %s${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((ok++))
            else
                printf "\r${C_MSG_REMOVE}  [%d/${total}] ✗ %s failed${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((fail++))
            fi
        done

        for pkg_name in "${to_remove[@]}"; do
            printf "${C_MSG_INFO}  [%d/${total}] remove %s...${C_RESET}" "$((ok+fail+1))" "$pkg_name"
            if "${PKG_MGR}" remove -- "$pkg_name" 2>/dev/null; then
                _pkgs_log_history "REMOVE" "$pkg_name"
                printf "\r${C_MSG_DONE}  [%d/${total}] ✓ %s${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((ok++))
            else
                printf "\r${C_MSG_REMOVE}  [%d/${total}] ✗ %s failed${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((fail++))
            fi
        done

        if (( ${#to_remove[@]} > 0 )); then
            local auto_out
            if auto_out=$("${PKG_MGR}" autoremove --dry-run 2>&1) && ! echo "$auto_out" | grep -qE "^0 upgraded, 0 newly installed, 0 to remove"; then
                printf "\n  ${C_MSG_WARN}Remove orphaned dependencies? (y/N) ${C_RESET}"
                read -q auto_confirm; read -r
                printf "\n"
                if [[ "$auto_confirm" == "y" ]]; then
                    printf "  ${C_MSG_INFO}Cleaning up...${C_RESET}\n"
                    "${PKG_MGR}" autoremove -y 2>/dev/null
                    _pkgs_log_history "CLEAN" "autoremove"
                fi
            fi
        fi

        _pkgs_invalidate_cache
        printf "\n  ${C_MSG_DONE}Done:${C_RESET} %d ok, %d failed\n" "$ok" "$fail"
        printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
  /export-all           Export all installed packages
  /info <pkg>           Show full package details
  /search <text>        Search package descriptions
  /rdeps <pkg>          Show reverse dependencies
  /deps <pkg>           Show dependencies
  /tree <pkg>           Show dependency tree
  /compare <a> <b>      Compare two packages side by side
  /note <pkg> <text>    Add/view package note
  /orphans              Show orphaned packages
  /top                  Top 10 largest packages
  /size                 Total installed size
  /count                Count installed/available packages
  /update               Update apt cache
  /clean                Remove orphaned packages and cache
  /installed            Filter: show only installed
  /available            Filter: show only available
  /recent               Filter: show installed today
  /usage                Disk usage by section
  /all                  Reset filter: show everything
  /sort name or /sort size  Sort by name or size
  /history              View today's operation log
  /backup               Export full package list to file
  /restore <file>       Install packages from list file
  /undo                 Reverse last install/remove
  /help                 Show in-app help

Keybindings:
  ?                     Toggle preview panel
  Tab                   Multi-select packages
  Ctrl-A                Select all visible packages
  Ctrl-D                Deselect all packages
  Enter                 Confirm selection
  Esc                   Exit

Examples:
  pkgs                  Launch with no filter
  pkgs vim              Launch pre-filtered for "vim"
  pkgs -h               Show this help
USAGE
}

_pkgs_version() { echo "pkgs 1.2.0"; }

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    _pkgs_usage
    exit 0
fi
if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    _pkgs_version
    exit 0
fi

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && pkgs "$@"
