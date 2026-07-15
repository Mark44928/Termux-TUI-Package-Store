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
    local _PKGS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pkgs"
    local _PKGS_CONFIG_FILE="${_PKGS_CONFIG_DIR}/config"
    local _PKGS_HISTORY_KEEP_DAYS=30

    _pkgs_validate_name() {
        [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9.+\-]*$ ]]
    }

    _pkgs_validate_export_path() {
        local path="$1"
        [[ -z "$path" ]] && return 1
        [[ "$path" =~ ^[[:space:]] ]] && return 1
        local dir
        dir=$(dirname "$path" 2>/dev/null)
        [[ -z "$dir" || ! -d "$dir" ]] && return 1
        local resolved
        resolved=$(readlink -f "$path" 2>/dev/null) || return 1
        local prefix_dir
        prefix_dir=$(readlink -f "${PREFIX}" 2>/dev/null || echo "${PREFIX}")
        [[ -z "$prefix_dir" ]] && return 1
        [[ "$resolved" == "$prefix_dir/bin/pkgs" ]] && return 1
        [[ "$resolved" == *"/.ssh/"* || "$resolved" == *"/.gnupg/"* || "$resolved" == "/etc/"* ]] && return 1
        [[ "$resolved" != "$HOME"/* ]] && return 1
        return 0
    }

    local _HAS_NUMFMT=0
    command -v numfmt >/dev/null 2>&1 && _HAS_NUMFMT=1

    _pkgs_apt_field() {
        local text="$1" field="$2"
        local line
        for line in ${(f)text}; do
            [[ "$line" == "$field: "* ]] && { print -r -- "${line#"$field: "}"; return; }
        done
    }

    _pkgs_trim() {
        local var="$1"
        var="${var##[[:space:]]#}"
        var="${var%%[[:space:]]#}"
        print -r -- "$var"
    }

    _pkgs_format_size() {
        local kb="$1"
        if (( _HAS_NUMFMT )); then
            printf "%s" "$((kb * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${kb} KiB"
        else
            echo "${kb} KiB"
        fi
    }

    _pkgs_parse_pkg_arg() {
        local cmd="$1" full_query="$2"
        if [[ "$full_query" == "/$cmd" || "$full_query" == "/$cmd " ]]; then
            printf "${C_MSG_WARN}Usage: /%s <pkg>${C_RESET}\n" "$cmd"
            return 1
        fi
        local pkg="${full_query#* }"
        pkg="$(_pkgs_trim "$pkg")"
        if [[ -z "$pkg" ]]; then
            printf "${C_MSG_WARN}Usage: /%s <pkg>${C_RESET}\n" "$cmd"
            return 1
        fi
        if ! _pkgs_validate_name "$pkg"; then
            printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$pkg"
            return 1
        fi
        echo "$pkg"
    }

    _pkgs_save_state() {
        mkdir -p "$_PKGS_CONFIG_DIR" 2>/dev/null
        {
            printf "FILTER=%s\n" "$_PKGS_FILTER"
            printf "SORT=%s\n" "$_PKGS_SORT"
        } > "$_PKGS_CONFIG_FILE" 2>/dev/null
    }

    _pkgs_load_state() {
        if [[ -f "$_PKGS_CONFIG_FILE" ]]; then
            local line
            while IFS='=' read -r key val; do
                case "$key" in
                    FILTER) _PKGS_FILTER="$val" ;;
                    SORT) _PKGS_SORT="$val" ;;
                esac
            done < "$_PKGS_CONFIG_FILE"
            case "$_PKGS_FILTER" in
                installed|available|all|recent) ;;
                *) _PKGS_FILTER="all" ;;
            esac
            case "$_PKGS_SORT" in
                name|size) ;;
                *) _PKGS_SORT="name" ;;
            esac
        fi
    }

    _pkgs_rotate_history() {
        [[ ! -d "$_PKGS_HISTORY_DIR" ]] && return
        local cutoff_date
        cutoff_date=$(date -d "-${_PKGS_HISTORY_KEEP_DAYS} days" +%Y-%m-%d 2>/dev/null) || return
        setopt localoptions nullglob
        local f
        for f in "$_PKGS_HISTORY_DIR"/*.log; do
            local fname="${f:t}"
            local fdate="${fname%.log}"
            [[ "$fdate" < "$cutoff_date" ]] && rm -f "$f" 2>/dev/null
        done
    }

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
        if [[ ! -f "$_PKGS_HISTORY_FILE" ]]; then
            touch "$_PKGS_HISTORY_FILE" 2>/dev/null
            chmod 600 "$_PKGS_HISTORY_FILE" 2>/dev/null
        fi
        printf "%s %s %s\n" "$(date +%H:%M:%S)" "$action" "$pkg_name" >> "$_PKGS_HISTORY_FILE"
    }

    _pkgs_show_info() {
        local pkg_name="$1"
        local info
        info=$(apt-cache show -- "$pkg_name" 2>/dev/null) || {
            printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$pkg_name"
            return 1
        }
        clear
        local pkg_display="${pkg_name:0:44}"
        printf "\n  ${C_GREEN}┌──────────────────────────────────────────────┐${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_WHITE}%-44s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$pkg_display"
        printf "  ${C_GREEN}├──────────────────────────────────────────────┤${C_RESET}\n"
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Version:%-36s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$(_pkgs_apt_field "$info" Version)"
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Section:%-36s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$(_pkgs_apt_field "$info" Section)"
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Maintainer:%-32s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$(print -r -- "$(_pkgs_apt_field "$info" Maintainer)" | cut -c1-32)"
        local size
        size=$(_pkgs_apt_field "$info" Installed-Size)
        if [[ -n "$size" && "$size" =~ ^[0-9]+$ ]]; then
            size=$(_pkgs_format_size "$size")
        else
            size="${size:-?} KiB"
        fi
        printf "  ${C_GREEN}│${C_RESET}  ${C_DIM}Size:%-38s${C_RESET} ${C_GREEN}│${C_RESET}\n" "$size"
        local status_str="not installed"
        if dpkg -s -- "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
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
        printf "\n  ${C_WHITE}Package Manager - Help${C_RESET}\n"
        printf "\n  ${C_AMBER}Slash Commands${C_RESET}\n"
        printf "    ${C_TEAL}/upgrade${C_RESET}          Upgrade all packages\n"
        printf "    ${C_TEAL}/install <pkg>${C_RESET}      Install by name\n"
        printf "    ${C_TEAL}/remove <pkg>${C_RESET}       Remove by name\n"
        printf "    ${C_TEAL}/purge <pkg>${C_RESET}        Remove + config files\n"
        printf "    ${C_TEAL}/hold <pkg>${C_RESET}         Pin package (no upgrade)\n"
        printf "    ${C_TEAL}/unhold <pkg>${C_RESET}       Unpin package\n"
        printf "    ${C_TEAL}/export <pkg>${C_RESET}       Export install script\n"
        printf "    ${C_TEAL}/info <pkg>${C_RESET}         Full package info\n"
        printf "    ${C_TEAL}/search <text>${C_RESET}      Search descriptions\n"
        printf "    ${C_TEAL}/rdeps <pkg>${C_RESET}        Reverse dependencies\n"
        printf "    ${C_TEAL}/depends-on <pkg>${C_RESET}   Installed dependents\n"
        printf "    ${C_TEAL}/compare <a> <b>${C_RESET}   Compare packages\n"
        printf "    ${C_TEAL}/note <pkg> <text>${C_RESET}  Add/view package note\n"
        printf "    ${C_TEAL}/deps <pkg>${C_RESET}        Show dependencies\n"
        printf "    ${C_TEAL}/tree <pkg>${C_RESET}        Dependency tree\n"
        printf "    ${C_TEAL}/orphans${C_RESET}           Show orphaned packages\n"
        printf "    ${C_TEAL}/orphans-safe${C_RESET}      Safe orphans (no essential)\n"
        printf "    ${C_TEAL}/orphans-remove${C_RESET}   Remove all orphans\n"
        printf "    ${C_TEAL}/outdated${C_RESET}          Packages with updates\n"
        printf "    ${C_TEAL}/top${C_RESET}              Top 10 largest pkgs\n"
        printf "    ${C_TEAL}/top <n>${C_RESET}           Top N largest pkgs\n"
        printf "    ${C_TEAL}/size${C_RESET}             Total installed size\n"
        printf "    ${C_TEAL}/count${C_RESET}            Count packages\n"
        printf "    ${C_TEAL}/update${C_RESET}           Update apt cache\n"
        printf "    ${C_TEAL}/export-all${C_RESET}       Export all installed\n"
        printf "    ${C_TEAL}/clean${C_RESET}            Clean orphans + cache\n"
        printf "    ${C_TEAL}/installed${C_RESET}         Show only installed\n"
        printf "    ${C_TEAL}/available${C_RESET}         Show only available\n"
        printf "    ${C_TEAL}/recent${C_RESET}            Show installed today\n"
        printf "    ${C_TEAL}/usage${C_RESET}             Disk usage by section\n"
        printf "    ${C_TEAL}/usage <pkg>${C_RESET}       Per-package file list\n"
        printf "    ${C_TEAL}/changelog <pkg>${C_RESET}  Show package changelog\n"
        printf "    ${C_TEAL}/reinstall <pkg>${C_RESET}  Reinstall package\n"
        printf "    ${C_TEAL}/search-file <text>${C_RESET} Search installed files\n"
        printf "    ${C_TEAL}/download-size <pkg>${C_RESET} Show download size\n"
        printf "    ${C_TEAL}/check${C_RESET}            Verify installed packages\n"
        printf "    ${C_TEAL}/group${C_RESET}            Packages by section\n"
        printf "    ${C_TEAL}/outdated-top${C_RESET}     Top N packages with updates\n"
        printf "    ${C_TEAL}/usage-top${C_RESET}        Disk usage bar chart\n"
        printf "    ${C_TEAL}/version${C_RESET}          System version info\n"
        printf "    ${C_TEAL}/all${C_RESET}               Show all packages\n"
        printf "    ${C_TEAL}/sort name${C_RESET} or ${C_TEAL}/sort size${C_RESET}    Sort packages\n"
        printf "    ${C_TEAL}/history${C_RESET}           View last 7 days of commands\n"
        printf "    ${C_TEAL}/review${C_RESET}            Today's activity summary\n"
        printf "    ${C_TEAL}/stats${C_RESET}             Today's install/remove counts\n"
        printf "    ${C_TEAL}/backup${C_RESET}            Export full package list\n"
        printf "    ${C_TEAL}/restore <file>${C_RESET}    Install from list file\n"
        printf "    ${C_TEAL}/undo${C_RESET}              Undo last operation\n"
        printf "    ${C_TEAL}/help${C_RESET}              Show this help\n"
        printf "\n  ${C_AMBER}Keybindings${C_RESET}\n"
        printf "    ${C_TEAL}?${C_RESET}                Toggle preview\n"
        printf "    ${C_TEAL}Tab${C_RESET}              Multi-select\n"
        printf "    ${C_TEAL}Ctrl-A${C_RESET}            Select all visible\n"
        printf "    ${C_TEAL}Ctrl-D${C_RESET}            Deselect all\n"
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
        cat <<'PREVIEW_EOF'
pkg_name={1}
pkg=$(apt-cache show "$pkg_name" 2>/dev/null) || { echo "  Package not found"; exit 0; }

pkg_status="not installed"
hold_status=""
if dpkg -s "$pkg_name" 2>/dev/null | grep -q "^Status: install ok installed"; then
    pkg_status="installed"
    if dpkg -s "$pkg_name" 2>/dev/null | grep -q "^Hold:"; then
        hold_status=" [PINNED]"
    fi
fi
essential=$(echo "$pkg" | grep "^Essential:" | head -1 | cut -d" " -f2)
version=$(echo "$pkg" | grep "^Version:" | head -1 | sed "s/^Version: //")

printf "  \033[38;5;114m%s\033[0m%s  \033[38;5;59m(%s)\033[0m\n" "$pkg_name" "$hold_status" "$pkg_status"
printf "  \033[38;5;109mv%s\033[0m" "$version"
[ -n "$essential" ] && printf "  \033[38;5;180messential\033[0m"
printf "\n"

maintainer=$(echo "$pkg" | grep "^Maintainer:" | head -1 | sed "s/^Maintainer: //")
homepage=$(echo "$pkg" | grep "^Homepage:" | head -1 | sed "s/^Homepage: //")
[ -n "$maintainer" ] && printf "\n  \033[38;5;59mBy:\033[0m %s\n" "$(echo "$maintainer" | cut -c1-48)"
[ -n "$homepage" ] && printf "  \033[38;5;59mWeb:\033[0m %s\n" "$(echo "$homepage" | cut -c1-48)"

dl_size=$(echo "$pkg" | grep "^Size:" | head -1 | cut -d" " -f2)
inst_size=$(echo "$pkg" | grep "^Installed-Size:" | head -1 | sed "s/^Installed-Size: //")
printf "\n  \033[38;5;59mDownload:\033[0m "
if [ -n "$dl_size" ]; then
    if command -v numfmt >/dev/null 2>&1; then
        printf "%s" "$dl_size" | numfmt --to=iec --suffix=B 2>/dev/null || printf "%s B" "$dl_size"
    else
        printf "%s B" "$dl_size"
    fi
else
    printf "unknown"
fi
if [ -n "$inst_size" ]; then
    printf "  \033[38;5;59mInstalled:\033[0m "
    if command -v numfmt >/dev/null 2>&1; then
        printf "%s" "$((inst_size * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || printf "%s KiB" "$inst_size"
    else
        printf "%s KiB" "$inst_size"
    fi
fi
printf "\n"

printf "\n--- DEPENDENCIES ---\n"
deps=$(echo "$pkg" | grep "^Depends:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | sed 's/|.*//' | sed 's/ *(.*//' | sort -u | head -n 6)
dep_count=$(echo "$deps" | grep -c . 2>/dev/null)
if [ -z "$deps" ]; then
    echo "  None."
else
    echo "$deps" | while read -r d; do printf "  %s\n" "$d"; done
    total_deps=$(echo "$pkg" | grep "^Depends:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | wc -l | tr -d " ")
    [ "$dep_count" -lt "$total_deps" ] && printf "  \033[38;5;59m...and %d more\033[0m\n" "$((total_deps - dep_count))"
fi

recs=$(echo "$pkg" | grep "^Recommends:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | sed 's/|.*//' | sed 's/ *(.*//' | sort -u | head -n 3)
sugs=$(echo "$pkg" | grep "^Suggests:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | sed 's/|.*//' | sed 's/ *(.*//' | sort -u | head -n 3)
if [ -n "$recs" ]; then
    printf "\n--- RECOMMENDS ---\n"
    echo "$recs" | while read -r r; do printf "  %s\n" "$r"; done
fi
if [ -n "$sugs" ]; then
    printf "\n--- SUGGESTS ---\n"
    echo "$sugs" | while read -r s; do printf "  %s\n" "$s"; done
fi

conflicts=$(echo "$pkg" | grep "^Conflicts:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | sed 's/ *(.*//' | sort -u | head -n 3)
replaces=$(echo "$pkg" | grep "^Replaces:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | sed 's/ *(.*//' | sort -u | head -n 3)
if [ -n "$conflicts" ]; then
    printf "\n--- CONFLICTS ---\n"
    echo "$conflicts" | while read -r c; do printf "  %s\n" "$c"; done
fi
if [ -n "$replaces" ]; then
    printf "\n--- REPLACES ---\n"
    echo "$replaces" | while read -r r; do printf "  %s\n" "$r"; done
fi

printf "\n--- REVERSE DEPS ---\n"
rdeps_full=$(apt-cache rdepends "$pkg_name" 2>/dev/null | tail -n +3 | grep -v "^$")
rdeps=$(echo "$rdeps_full" | head -n 6)
if [ -z "$rdeps" ]; then
    echo "  Nothing depends on this."
else
    echo "$rdeps" | while read -r r; do printf "  %s\n" "$r"; done
    rdep_total=$(echo "$rdeps_full" | wc -l | tr -d ' ')
    shown=$(echo "$rdeps" | wc -l | tr -d ' ')
    [ "$shown" -lt "$rdep_total" ] && printf "  \033[38;5;59m...and %d more\033[0m\n" "$((rdep_total - shown))"
fi

if dpkg -s "$pkg_name" 2>/dev/null | grep -q "^Status: install ok installed"; then
    pkg_files=$(dpkg -L "$pkg_name" 2>/dev/null | grep "^/")
    file_count=$(echo "$pkg_files" | grep -c "^/" 2>/dev/null)
    printf "\n--- INSTALLED FILES (%s) ---\n" "$file_count"
    echo "$pkg_files" | grep -v "^/\\." | grep -v "^/etc/" | tail -n 12 | while read -r f; do printf "  %s\n" "$f"; done
    [ "$file_count" -gt 12 ] && printf "  \033[38;5;59m...%d more files\033[0m\n" "$((file_count - 12))"
fi

printf "\n--- DESCRIPTION ---\n"
echo "$pkg" | sed -n "/^Description:/ { s/^Description: //p; :a; n; /^ / { s/^ //p; ba }; }" | head -8
PREVIEW_EOF
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

    local query="$*"

    _pkgs_load_state
    _pkgs_rotate_history

    trap '_pkgs_invalidate_cache; _pkgs_cleanup' EXIT INT TERM HUP

    while true; do
        local -a FZF_ARGS
        local PREVIEW_LAYOUT=$(_pkgs_detect_layout)
        local status_msg=""
        case "$_PKGS_FILTER" in
            installed) status_msg="Showing: installed only" ;;
            available) status_msg="Showing: available only" ;;
            recent) status_msg="Showing: installed today" ;;
        esac
        [[ "$_PKGS_SORT" == "size" ]] && status_msg="${status_msg:+$status_msg | }Sorted by: size"
        _pkgs_build_fzf_args "$query" "$status_msg"

        _pkgs_get_cached_list > /dev/null 2>&1
        local output
        output=$(cat "$_PKGS_CACHE_FILE" | fzf "${FZF_ARGS[@]}")
        local ret=$?

        [[ $ret -ne 0 && -z "$output" ]] && { clear; break; }
        [[ -z "$output" ]] && continue

        output=$(_pkgs_strip_ansi "$output")
        local -a lines=("${(@f)output}")
        [[ ${#lines[@]} -lt 1 ]] && continue

        local query="${lines[1]}"
        query="$(_pkgs_trim "$query")"

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
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            continue
        fi

        if [[ "$query" == /installed ]]; then
            _PKGS_FILTER="installed"
            _pkgs_invalidate_cache
            _pkgs_save_state
            query=""
            continue
        fi

        if [[ "$query" == /available ]]; then
            _PKGS_FILTER="available"
            _pkgs_invalidate_cache
            _pkgs_save_state
            query=""
            continue
        fi

        if [[ "$query" == /all ]]; then
            _PKGS_FILTER="all"
            _pkgs_invalidate_cache
            _pkgs_save_state
            query=""
            continue
        fi

        if [[ "$query" == /recent ]]; then
            _PKGS_FILTER="recent"
            _pkgs_invalidate_cache
            _pkgs_save_state
            query=""
            continue
        fi

        if [[ "$query" == /usage* && "$query" != /usage-top* ]]; then
            if [[ "$query" != "/usage" ]]; then
                local usage_pkg="${query#* }"
                usage_pkg="$(_pkgs_trim "$usage_pkg")"
                if [[ -z "$usage_pkg" ]]; then
                    printf "${C_MSG_WARN}Usage: /usage <pkg>${C_RESET}\n"
                    sleep 1
                    query=""
                    continue
                fi
                if ! _pkgs_validate_name "$usage_pkg"; then
                    printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$usage_pkg"
                    sleep 1
                    query=""
                    continue
                fi
                clear
                if ! dpkg -s -- "$usage_pkg" 2>/dev/null | grep -q '^Status: install ok installed'; then
                    printf "${C_MSG_REMOVE}Package not installed: %s${C_RESET}\n" "$usage_pkg"
                else
                    local usage_size
                    usage_size=$(dpkg-query -W -f='${Installed-Size}' -- "$usage_pkg" 2>/dev/null)
                    local usage_display
                    usage_display=$(_pkgs_format_size "$usage_size")
                    printf "\n  ${C_GREEN}── Files installed by %s (%s) ──${C_RESET}\n\n" "$usage_pkg" "$usage_display"
                    local usage_count=0
                    local usage_line
                    while IFS= read -r usage_line; do
                        [[ -z "$usage_line" ]] && continue
                        ((usage_count++))
                        printf "  ${C_DIM}%s${C_RESET}\n" "$usage_line"
                    done < <(dpkg -L -- "$usage_pkg" 2>/dev/null | grep "^/")
                    printf "\n  ${C_DIM}Total files: %d${C_RESET}\n" "$usage_count"
                fi
            else
                clear
                printf "\n  ${C_GREEN}── Disk Usage by Section ──${C_RESET}\n\n"
                local total_size=0
                local -A section_sizes
                local -A _pkgs_sec_cache
                local _sec_key _sec_val _sec_pkg=""
                while IFS=: read -r _sec_key _sec_val; do
                    _sec_key="${_sec_key## }" _sec_val="${_sec_val## }"
                    [[ "$_sec_key" == "Package" ]] && _sec_pkg="$_sec_val"
                    [[ "$_sec_key" == "Section" && -n "$_sec_pkg" ]] && {
                        _pkgs_sec_cache[$_sec_pkg]="${_sec_val%%/*}"
                        _sec_pkg=""
                    }
                done < <(apt-cache dump 2>/dev/null)
                while read -r line; do
                    local pkg_name="${line%% *}"
                    local rest="${line#* }"
                    local inst_size="${rest%% *}"
                    [[ -z "$inst_size" || "$inst_size" == "?" ]] && continue
                    local section="${_pkgs_sec_cache[$pkg_name]:-other}"
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
                    display_size=$(_pkgs_format_size "$ssize")
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
                total_display=$(_pkgs_format_size "$total_size")
                printf "\n  ${C_GREEN}Total:${C_RESET} %s across %d sections\n" "$total_display" "${#section_sizes[@]}"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /deps* && "$query" != /depends* ]]; then
            local deps_pkg; deps_pkg=$(_pkgs_parse_pkg_arg "deps" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! apt-cache show -- "$deps_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$deps_pkg"
            else
                printf "\n${C_MSG_INFO}--- Dependencies of %s ---${C_RESET}\n\n" "$deps_pkg"
                local deps_out
                deps_out=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$deps_pkg" 2>/dev/null | grep "^\w" | sort -u)
                if [[ -z "$deps_out" ]]; then
                    printf "${C_DIM}No dependencies.${C_RESET}\n"
                else
                    printf "%s\n" "$deps_out"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /tree* ]]; then
            local tree_pkg; tree_pkg=$(_pkgs_parse_pkg_arg "tree" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! apt-cache show -- "$tree_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$tree_pkg"
            else
                printf "\n${C_MSG_INFO}--- Dependency tree for %s ---${C_RESET}\n\n" "$tree_pkg"
                local tree_output
                tree_output=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$tree_pkg" 2>/dev/null)
                print -r -- "$tree_output" | head -50
                local total_deps
                total_deps=$(print -r -- "$tree_output" | grep "^\w" | sort -u | wc -l | tr -d ' ')
                printf "\n  ${C_DIM}Total unique dependencies: %s${C_RESET}\n" "$total_deps"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
                orphans_count=$(echo "$orphans_out" | wc -l | tr -d ' ')
                printf "\n  ${C_DIM}Total orphaned: %s${C_RESET}\n" "$orphans_count"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /top* ]]; then
            local top_n=10
                if [[ "$query" != "/top" ]]; then
                    local top_arg="${query#* }"
                    top_arg="$(_pkgs_trim "$top_arg")"
                    if [[ -z "$top_arg" || ! "$top_arg" =~ ^[0-9]+$ ]]; then
                        printf "${C_MSG_REMOVE}Invalid number: %s${C_RESET}\n" "$top_arg"
                        sleep 1
                        query=""
                        continue
                    fi
                    if (( top_arg > 0 && top_arg <= 100 )); then
                        top_n="$top_arg"
                    fi
            fi
            clear
            printf "\n${C_MSG_INFO}── Top %d Largest Installed Packages ──${C_RESET}\n\n" "$top_n"
            printf "  ${C_DIM}%-4s %-24s %-10s${C_RESET}\n" "#" "Package" "Size"
            printf "  ${C_DIM}%-4s %-24s %-10s${C_RESET}\n" "---" "-------" "----"
            local shown=0
            while read -r line; do
                [[ $shown -ge $top_n ]] && break
                local pkg_name="${line%% *}"
                local rest="${line#* }"
                local pkg_size="${rest%% *}"
                [[ -z "$pkg_size" || "$pkg_size" == "?" ]] && continue
                ((shown++))
                local display_size
                display_size=$(_pkgs_format_size "$pkg_size")
                printf "  ${C_WHITE}%-4s${C_RESET} ${C_TEAL}%-24s${C_RESET} ${C_AMBER}%-10s${C_RESET}\n" "$shown" "$pkg_name" "$display_size"
            done < <(dpkg-query -W -f='${Package} ${Installed-Size}\n' 2>/dev/null | sort -k2 -rn)
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
            total_pkgs=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | wc -l | tr -d ' ')
            local display_total
            display_total=$(_pkgs_format_size "$total_size_kb")
            printf "  ${C_WHITE}Total packages:${C_RESET}    %s\n" "$total_pkgs"
            printf "  ${C_WHITE}Total size:${C_RESET}        %s\n" "$display_total"
            local avg_kb=0
            (( total_pkgs > 0 )) && avg_kb=$(( total_size_kb / total_pkgs ))
            local avg_display
            avg_display=$(_pkgs_format_size "$avg_kb")
            printf "  ${C_WHITE}Average per package:${C_RESET} %s\n" "$avg_display"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /count ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Package Counts ---${C_RESET}\n\n"
            local count_installed count_available count_total
            count_installed=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | wc -l | tr -d ' ')
            count_total=$(apt-cache search ".*" 2>/dev/null | wc -l | tr -d ' ')
            count_available=$(( count_total - count_installed ))
            printf "  ${C_WHITE}Installed:${C_RESET}   %s\n" "$count_installed"
            printf "  ${C_WHITE}Available:${C_RESET}   %s\n" "$count_available"
            printf "  ${C_WHITE}Total:${C_RESET}       %s\n" "$count_total"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
                local -a all_pkgs
                all_pkgs=(${(@f)$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)})
                if (( ${#all_pkgs[@]} == 0 )); then
                    printf "echo 'No packages installed'\n"
                else
                    printf "${PKG_MGR} install \\\\\n"
                    local i
                    for i in {1..${#all_pkgs[@]}}; do
                        if (( i < ${#all_pkgs[@]} )); then
                            printf "    %s \\\\\n" "${all_pkgs[$i]}"
                        else
                            printf "    %s\n" "${all_pkgs[$i]}"
                        fi
                    done
                fi
            } > "$export_all_file"
            chmod +x "$export_all_file" 2>/dev/null
            printf "\n${C_MSG_DONE}Exported %s packages to: %s${C_RESET}\n" "${#all_pkgs[@]}" "$export_all_file"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
                note_pkg="$(_pkgs_trim "$note_pkg")"
                note_text="$(_pkgs_trim "$note_text")"
                if [[ -z "$note_pkg" || -z "$note_text" ]]; then
                    printf "${C_MSG_WARN}Usage: /note <pkg> <text>${C_RESET}\n"
                    sleep 1
                    query=""
                    continue
                fi
                if ! _pkgs_validate_name "$note_pkg"; then
                    printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$note_pkg"
                    sleep 1
                    query=""
                    continue
                fi
                mkdir -p "$(dirname "$_PKGS_NOTES_FILE")" 2>/dev/null
                if [[ -f "$_PKGS_NOTES_FILE" ]] && grep -qF "${note_pkg}|" "$_PKGS_NOTES_FILE" 2>/dev/null; then
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
                local note_pkg="$(_pkgs_trim "$note_action")"
                if [[ -z "$note_pkg" ]]; then
                    printf "${C_MSG_WARN}Usage: /note <pkg> <text> or /note <pkg>${C_RESET}\n"
                    sleep 1
                    query=""
                    continue
                fi
                if ! _pkgs_validate_name "$note_pkg"; then
                    printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$note_pkg"
                    sleep 1
                    query=""
                    continue
                fi
                if [[ -f "$_PKGS_NOTES_FILE" ]] && grep -qF "${note_pkg}|" "$_PKGS_NOTES_FILE" 2>/dev/null; then
                    local existing
                    existing=$(grep -m1F "${note_pkg}|" "$_PKGS_NOTES_FILE" | cut -d'|' -f2-)
                    printf "  ${C_WHITE}%-24s${C_RESET} %s\n" "$note_pkg" "$existing"
                else
                    printf "${C_DIM}No note for %s${C_RESET}\n" "$note_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
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
            info1=$(apt-cache show -- "$cmp_p1" 2>/dev/null)
            info2=$(apt-cache show -- "$cmp_p2" 2>/dev/null)
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
            v1=$(_pkgs_apt_field "$info1" Version)
            s1=$(_pkgs_apt_field "$info1" Section)
            d1=$(_pkgs_apt_field "$info1" Description)
            sz1=$(_pkgs_apt_field "$info1" Installed-Size)
            local v2 s2 d2 sz2
            v2=$(_pkgs_apt_field "$info2" Version)
            s2=$(_pkgs_apt_field "$info2" Section)
            d2=$(_pkgs_apt_field "$info2" Description)
            sz2=$(_pkgs_apt_field "$info2" Installed-Size)
            printf "  ${C_DIM}%-16s${C_RESET} ${C_WHITE}%-20s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "" "$cmp_p1" "$cmp_p2"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Version" "${v1:-?}" "${v2:-?}"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Section" "${s1:-?}" "${s2:-?}"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Size" "${sz1:-?} KiB" "${sz2:-?} KiB"
            local inst1="no" inst2="no"
            dpkg -s -- "$cmp_p1" 2>/dev/null | grep -q '^Status: install ok installed' && inst1="yes"
            dpkg -s -- "$cmp_p2" 2>/dev/null | grep -q '^Status: install ok installed' && inst2="yes"
            printf "  ${C_DIM}%-16s${C_RESET} ${C_TEAL}%-20s${C_RESET} ${C_TEAL}%s${C_RESET}\n" "Installed" "$inst1" "$inst2"
            printf "\n  ${C_WHITE}Description:${C_RESET}\n"
            local d1 trunc1="${d1:0:36}" d2 trunc2="${d2:0:36}"
            (( ${#d1} > 36 )) && trunc1="${trunc1}..."
            (( ${#d2} > 36 )) && trunc2="${trunc2}..."
            printf "  ${C_WHITE}%-20s${C_RESET} %s\n" "$cmp_p1" "${trunc1:-?}"
            printf "  ${C_WHITE}%-20s${C_RESET} %s\n" "$cmp_p2" "${trunc2:-?}"
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
                pkg_count=$(wc -l < "$backup_file" | tr -d ' ')
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
            restore_file="$(_pkgs_trim "$restore_file")"
            if [[ ! -f "$restore_file" ]]; then
                printf "${C_MSG_REMOVE}File not found: %s${C_RESET}\n" "$restore_file"
                sleep 1
                query=""
                continue
            fi
            if ! _pkgs_validate_export_path "$restore_file"; then
                printf "${C_MSG_REMOVE}Invalid or unsafe file path${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            clear
            local -a restore_pkgs=()
            while IFS= read -r rline; do
                rline="${rline##[[:space:]]}"
                rline="${rline%%[[:space:]]}"
                rline="${rline%%\\}"
                rline="${rline##[[:space:]]}"
                [[ -z "$rline" ]] && continue
                [[ "$rline" == "#"* ]] && continue
                [[ "$rline" == "#!"* ]] && continue
                [[ "$rline" == *"install"* ]] && continue
                _pkgs_validate_name "$rline" || continue
                apt-cache show -- "$rline" >/dev/null 2>&1 && restore_pkgs+=("$rline")
            done < "$restore_file"
            if [[ ${#restore_pkgs[@]} -eq 0 ]]; then
                printf "${C_MSG_REMOVE}No valid packages found in file${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local -a to_install_r=()
            for rp in "${restore_pkgs[@]}"; do
                dpkg -s -- "$rp" 2>/dev/null | grep -q '^Status: install ok installed' || to_install_r+=("$rp")
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
                sort_arg="$(_pkgs_trim "$sort_arg")"
            fi
            if [[ "$sort_arg" == "name" || "$sort_arg" == "size" ]]; then
                _PKGS_SORT="$sort_arg"
                _pkgs_invalidate_cache
                _pkgs_save_state
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
            case "$laction" in
                INSTALL|REMOVE) ;;
                *)
                    printf "\n  ${C_MSG_REMOVE}Last action (%s) cannot be undone.${C_RESET}\n" "$laction"
                    printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                    read -r
                    clear
                    continue
                    ;;
            esac
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
            local info_pkg; info_pkg=$(_pkgs_parse_pkg_arg "info" "$query") || { sleep 1; query=""; continue; }
            _pkgs_show_info "$info_pkg"
            query=""
            continue
        fi

        if [[ "$query" == /clean ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Cleaning apt cache and unused dependencies ---${C_RESET}\n\n"
            printf "${C_MSG_WARN}Run autoremove + clean? (y/N) ${C_RESET}"
            read -q confirm; read -r
            if [[ "$confirm" == "y" ]]; then
                "${PKG_MGR}" clean 2>/dev/null
                printf "${C_MSG_DONE}Cache cleaned.${C_RESET}\n"
                local autoremove_out
                if ! autoremove_out=$("${PKG_MGR}" autoremove --dry-run 2>&1); then
                    printf "${C_MSG_WARN}Could not check dependencies: %s${C_RESET}\n" "$autoremove_out"
                elif echo "$autoremove_out" | grep -qE "^0 upgraded, 0 newly installed, 0 to remove"; then
                    printf "${C_MSG_DONE}Nothing to remove.${C_RESET}\n"
                else
                    "${PKG_MGR}" autoremove -y 2>/dev/null
                    printf "${C_MSG_DONE}Unused dependencies removed.${C_RESET}\n"
                fi
                _pkgs_log_history "CLEAN" "autoremove+cache"
            else
                printf "${DIM}Cancelled.${C_RESET}\n"
            fi
            _pkgs_invalidate_cache
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /purge* ]]; then
            local purge_pkg; purge_pkg=$(_pkgs_parse_pkg_arg "purge" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! dpkg -s -- "$purge_pkg" 2>/dev/null | grep -q '^Status: install ok installed'; then
                printf "${C_MSG_REMOVE}Package not installed: %s${C_RESET}\n" "$purge_pkg"
            else
                printf "\n${C_MSG_REMOVE}Purging %s (removes config files)...${C_RESET}\n\n" "$purge_pkg"
                printf "${C_MSG_WARN}Purge %s? (y/N) ${C_RESET}" "$purge_pkg"
                read -q purge_confirm; read -r
                printf "\n"
                if [[ "$purge_confirm" == "y" ]]; then
                    if "${PKG_MGR}" purge -- "$purge_pkg" 2>/dev/null; then
                        _pkgs_log_history "PURGE" "$purge_pkg"
                        printf "${C_MSG_DONE}Purged %s${C_RESET}\n" "$purge_pkg"
                    else
                        printf "${C_MSG_REMOVE}Failed to purge %s${C_RESET}\n" "$purge_pkg"
                    fi
                    _pkgs_invalidate_cache
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

        if [[ "$query" == /hold* ]]; then
            local hold_pkg; hold_pkg=$(_pkgs_parse_pkg_arg "hold" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! dpkg -s -- "$hold_pkg" 2>/dev/null | grep -q '^Status: install ok installed'; then
                printf "${C_MSG_REMOVE}Package not installed: %s${C_RESET}\n" "$hold_pkg"
            else
                if "${PKG_MGR}" hold -- "$hold_pkg" 2>/dev/null; then
                    _pkgs_log_history "HOLD" "$hold_pkg"
                    printf "${C_MSG_DONE}Pinned %s (will not be upgraded)${C_RESET}\n" "$hold_pkg"
                else
                    printf "${C_MSG_REMOVE}Failed to pin %s${C_RESET}\n" "$hold_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /unhold* ]]; then
            local unhold_pkg; unhold_pkg=$(_pkgs_parse_pkg_arg "unhold" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! dpkg -s -- "$unhold_pkg" 2>/dev/null | grep -q '^Status: install ok installed'; then
                printf "${C_MSG_REMOVE}Package not installed: %s${C_RESET}\n" "$unhold_pkg"
            else
                if "${PKG_MGR}" unhold -- "$unhold_pkg" 2>/dev/null; then
                    _pkgs_log_history "UNHOLD" "$unhold_pkg"
                    printf "${C_MSG_DONE}Unpinned %s (upgrades enabled)${C_RESET}\n" "$unhold_pkg"
                else
                    printf "${C_MSG_REMOVE}Failed to unpin %s${C_RESET}\n" "$unhold_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /depends-on* ]]; then
            local depson_pkg; depson_pkg=$(_pkgs_parse_pkg_arg "depends-on" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! apt-cache show -- "$depson_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$depson_pkg"
            else
                printf "\n${C_MSG_INFO}--- Installed packages that depend on %s ---${C_RESET}\n\n" "$depson_pkg"
                local depson_out
                depson_out=$(apt-cache rdepends -- "$depson_pkg" 2>/dev/null | tail -n +3)
                if [[ -z "$depson_out" ]]; then
                    printf "${C_DIM}Nothing depends on %s.${C_RESET}\n" "$depson_pkg"
                else
                    local depson_count=0
                    local depson_line
                    while IFS= read -r depson_line; do
                        [[ -z "$depson_line" ]] && continue
                        dpkg -s -- "$depson_line" 2>/dev/null | grep -q '^Status: install ok installed' || continue
                        printf "  ${C_GREEN}%s${C_RESET}\n" "$depson_line"
                        ((depson_count++))
                    done <<< "$depson_out"
                    printf "\n  ${C_DIM}Total installed dependents: %d${C_RESET}\n" "$depson_count"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /outdated ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Outdated Packages (updates available) ---${C_RESET}\n\n"
            local outdated_count=0
            while read -r pkg_line; do
                [[ -z "$pkg_line" ]] && continue
                local opkg="${pkg_line%% *}"
                local orest="${pkg_line#* }"
                local oinst_ver="${orest%% *}"
                local ocand_ver="${orest#* }"
                [[ "$oinst_ver" == "$ocand_ver" ]] && continue
                printf "  ${C_WHITE}%-28s${C_RESET} ${C_DIM}%-16s${C_RESET} ${C_GREEN}%s${C_RESET}\n" "$opkg" "$oinst_ver" "$ocand_ver"
                ((outdated_count++))
            done < <(
                dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | while read -r pname pver; do
                    cver=$(apt-cache policy -- "$pname" 2>/dev/null | grep 'Candidate:' | head -1 | sed 's/^.*Candidate: //')
                    [[ -n "$cver" && "$pver" != "$cver" ]] && printf "%s %s %s\n" "$pname" "$pver" "$cver"
                done
            )
            if (( outdated_count == 0 )); then
                printf "  ${C_MSG_DONE}All packages are up to date.${C_RESET}\n"
            else
                printf "\n  ${C_DIM}Total outdated: %d${C_RESET}\n" "$outdated_count"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /orphans-safe ]]; then
            clear
            printf "\n${C_MSG_INFO}--- Orphaned Packages (safe to remove) ---${C_RESET}\n\n"
            local osafe_out
            osafe_out=$(apt-cache showpkg 2>/dev/null | awk '/^Package:/{pkg=$2} /^ReverseDependencies:/{if(NF==1) print pkg}' | sort -u | while read -r opkg; do
                [[ -z "$opkg" ]] && continue
                local opriority
                opriority=$(apt-cache show -- "$opkg" 2>/dev/null | grep '^Priority:' | head -1 | sed 's/^Priority: //')
                case "$opriority" in
                    required|important) continue ;;
                esac
                dpkg -s -- "$opkg" 2>/dev/null | grep -q '^Status: install ok installed' || continue
                printf "%s\n" "$opkg"
            done)
            if [[ -z "$osafe_out" ]]; then
                printf "${C_DIM}No safe orphans found.${C_RESET}\n"
            else
                printf "%s\n" "$osafe_out"
                local osafe_count
                osafe_count=$(print -r -- "$osafe_out" | wc -l | tr -d ' ')
                printf "\n  ${C_DIM}Total safe orphans: %s${C_RESET}\n" "$osafe_count"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /review ]]; then
            clear
            printf "\n  ${C_GREEN}── Review ($(date +%Y-%m-%d)) ──${C_RESET}\n\n"
            if [[ ! -f "$_PKGS_HISTORY_FILE" ]]; then
                printf "  ${C_DIM}No activity today.${C_RESET}\n"
            else
                local rv_install=0 rv_remove=0 rv_upgrade=0 rv_other=0
                local hline
                while IFS= read -r hline; do
                    [[ -z "$hline" ]] && continue
                    local rest="${hline#* }"
                    local haction="${rest%% *}"
                    case "$haction" in
                        INSTALL|UNDO-INSTALL) ((rv_install++)) ;;
                        REMOVE|UNDO-REMOVE) ((rv_remove++)) ;;
                        UPGRADE) ((rv_upgrade++)) ;;
                        *) ((rv_other++)) ;;
                    esac
                done < "$_PKGS_HISTORY_FILE"
                printf "  ${C_GREEN}Installs:${C_RESET}  %d\n" "$rv_install"
                printf "  ${C_RED}Removes:${C_RESET}   %d\n" "$rv_remove"
                printf "  ${C_AMBER}Upgrades:${C_RESET}  %d\n" "$rv_upgrade"
                (( rv_other > 0 )) && printf "  ${C_DIM}Other:${C_RESET}     %d\n" "$rv_other"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /stats ]]; then
            clear
            printf "\n  ${C_GREEN}── Stats ($(date +%Y-%m-%d)) ──${C_RESET}\n\n"
            local st_install=0 st_remove=0 st_upgrade=0 st_total=0
            if [[ -f "$_PKGS_HISTORY_FILE" ]]; then
                local hline
                while IFS= read -r hline; do
                    [[ -z "$hline" ]] && continue
                    local rest="${hline#* }"
                    local haction="${rest%% *}"
                    ((st_total++))
                    case "$haction" in
                        INSTALL|UNDO-INSTALL) ((st_install++)) ;;
                        REMOVE|UNDO-REMOVE) ((st_remove++)) ;;
                        UPGRADE) ((st_upgrade++)) ;;
                    esac
                done < "$_PKGS_HISTORY_FILE"
            fi
            printf "  ${C_DIM}Total operations:${C_RESET}  %d\n" "$st_total"
            printf "  ${C_GREEN}Installs:${C_RESET}          %d\n" "$st_install"
            printf "  ${C_RED}Removes:${C_RESET}           %d\n" "$st_remove"
            printf "  ${C_AMBER}Upgrades:${C_RESET}          %d\n" "$st_upgrade"
            local st_pkgs_installed
            st_pkgs_installed=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | wc -l | tr -d ' ')
            printf "\n  ${C_WHITE}Installed packages:${C_RESET} %s\n" "$st_pkgs_installed"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /history ]]; then
            clear
            printf "\n  ${C_GREEN}── Command History (last 7 days) ──${C_RESET}\n\n"
            local hist_found=0
            local hist_day
            for i in {0..6}; do
                hist_day=$(date -d "${i} days ago" +%Y-%m-%d 2>/dev/null || date -v-"${i}"d +%Y-%m-%d 2>/dev/null)
                [[ -z "$hist_day" ]] && continue
                local hist_file="${_PKGS_HISTORY_DIR}/${hist_day}.log"
                [[ -f "$hist_file" ]] || continue
                hist_found=1
                printf "  ${C_TEAL}%s${C_RESET}\n" "$hist_day"
                local hline
                while IFS= read -r hline; do
                    [[ -z "$hline" ]] && continue
                    local htime="${hline%% *}"
                    local hrest="${hline#* }"
                    local haction="${hrest%% *}"
                    local hpkg="${hrest#* }"
                    local hcolor="$C_DIM"
                    case "$haction" in
                        INSTALL) hcolor="$C_GREEN" ;;
                        REMOVE|PURGE) hcolor="$C_RED" ;;
                        UPGRADE) hcolor="$C_AMBER" ;;
                    esac
                    printf "    ${C_DIM}%s${C_RESET} ${hcolor}%-14s${C_RESET} %s\n" "$htime" "$haction" "$hpkg"
                done < "$hist_file"
                printf "\n"
            done
            if (( hist_found == 0 )); then
                printf "  ${C_DIM}No history found.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /changelog* ]]; then
            local cl_pkg; cl_pkg=$(_pkgs_parse_pkg_arg "changelog" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! apt-cache show -- "$cl_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$cl_pkg"
            else
                printf "\n${C_MSG_INFO}── Changelog for %s ──${C_RESET}\n\n" "$cl_pkg"
                local cl_file="/data/data/com.termux/files/usr/share/doc/${cl_pkg}/changelog.gz"
                local cl_file2="/data/data/com.termux/files/usr/share/doc/${cl_pkg}/changelog"
                if [[ -f "$cl_file" ]]; then
                    zcat "$cl_file" 2>/dev/null | head -60
                elif [[ -f "$cl_file2" ]]; then
                    head -60 "$cl_file2"
                else
                    local cl_ver
                    cl_ver=$(_pkgs_apt_field "$(apt-cache show -- "$cl_pkg" 2>/dev/null)" Version)
                    printf "  ${C_DIM}Version: %s${C_RESET}\n" "${cl_ver:-unknown}"
                    printf "  ${C_DIM}No changelog file found for this package.${C_RESET}\n"
                    printf "  ${C_DIM}Check: https://packages.termux.dev/${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /orphans-remove ]]; then
            clear
            printf "\n${C_MSG_INFO}── Removing Orphaned Packages ──${C_RESET}\n\n"
            local or_df_out
            or_df_out=$(apt-get -s autoremove 2>/dev/null | grep "^Remv" | awk '{print $2}')
            if [[ -z "$or_df_out" ]]; then
                printf "${C_MSG_DONE}No orphaned packages to remove.${C_RESET}\n"
            else
                local or_count
                or_count=$(echo "$or_df_out" | wc -l | tr -d ' ')
                printf "${C_MSG_WARN}Found %s orphaned packages:${C_RESET}\n\n" "$or_count"
                printf "%s\n" "$or_df_out" | head -30
                (( or_count > 30 )) && printf "  ${C_DIM}...and %d more${C_RESET}\n" "$((or_count - 30))"
                printf "\n${C_MSG_WARN}Remove all orphans? (y/N) ${C_RESET}"
                read -q or_confirm; read -r
                if [[ "$or_confirm" == "y" ]]; then
                    printf "\n${C_MSG_INFO}Removing orphans...${C_RESET}\n"
                    if "${PKG_MGR}" autoremove -y 2>/dev/null; then
                        _pkgs_log_history "CLEAN" "autoremove"
                        _pkgs_invalidate_cache
                        printf "${C_MSG_DONE}Done.${C_RESET}\n"
                    else
                        printf "${C_MSG_REMOVE}Failed.${C_RESET}\n"
                    fi
                else
                    printf "${C_DIM}Cancelled.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /version ]]; then
            clear
            printf "\n  ${C_GREEN}── System Info ──${C_RESET}\n\n"
            printf "  ${C_WHITE}pkgs:${C_RESET}          1.2.0\n"
            printf "  ${C_WHITE}Termux:${C_RESET}        %s\n" "$(termux-info 2>/dev/null | grep 'Termux version' | cut -d: -f2 | xargs || echo 'unknown')"
            printf "  ${C_WHITE}fzf:${C_RESET}           %s\n" "$(fzf --version 2>/dev/null | awk '{print $1}' || echo 'unknown')"
            printf "  ${C_WHITE}zsh:${C_RESET}           %s\n" "${ZSH_VERSION:-$(zsh --version 2>/dev/null | awk '{print $2}' || echo 'unknown')}"
            printf "  ${C_WHITE}dpkg:${C_RESET}          %s\n" "$(dpkg --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'unknown')"
            printf "  ${C_WHITE}apt:${C_RESET}           %s\n" "$(apt-cache --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'unknown')"
            printf "  ${C_WHITE}arch:${C_RESET}          %s\n" "$(uname -m)"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /reinstall* ]]; then
            local ri_pkg; ri_pkg=$(_pkgs_parse_pkg_arg "reinstall" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! dpkg -s -- "$ri_pkg" 2>/dev/null | grep -q '^Status: install ok installed'; then
                printf "${C_MSG_REMOVE}Package not installed: %s${C_RESET}\n" "$ri_pkg"
            else
                printf "\n${C_MSG_WARN}Reinstall %s? (y/N) ${C_RESET}" "$ri_pkg"
                read -q ri_confirm; read -r
                if [[ "$ri_confirm" == "y" ]]; then
                    printf "\n${C_MSG_INFO}Reinstalling %s...${C_RESET}\n" "$ri_pkg"
                    if "${PKG_MGR}" reinstall -- "$ri_pkg" 2>/dev/null; then
                        _pkgs_log_history "REINSTALL" "$ri_pkg"
                        printf "${C_MSG_DONE}Reinstalled %s${C_RESET}\n" "$ri_pkg"
                    else
                        printf "${C_MSG_REMOVE}Failed to reinstall %s${C_RESET}\n" "$ri_pkg"
                    fi
                    _pkgs_invalidate_cache
                else
                    printf "${C_DIM}Cancelled.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /search-file* ]]; then
            local sf_text="${query#* }"
            sf_text="$(_pkgs_trim "$sf_text")"
            if [[ -z "$sf_text" ]]; then
                printf "${C_MSG_WARN}Usage: /search-file <text>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            clear
            printf "\n${C_MSG_INFO}── Searching installed files for \"%s\"... ──${C_RESET}\n\n" "$sf_text"
            local sf_count=0
            local sf_line
            while IFS= read -r sf_line; do
                [[ -z "$sf_line" ]] && continue
                ((sf_count++))
                printf "  ${C_DIM}%s${C_RESET}\n" "$sf_line"
                if (( sf_count >= 40 )); then
                    printf "  ${C_DIM}... (showing first 40)${C_RESET}\n"
                    break
                fi
            done < <(dpkg -S "*${sf_text}*" 2>/dev/null | grep -v "no path found" | head -40)
            if (( sf_count == 0 )); then
                printf "  ${C_DIM}No installed files match \"%s\".${C_RESET}\n" "$sf_text"
            else
                printf "\n  ${C_DIM}Found %d matches${C_RESET}\n" "$sf_count"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /download-size* ]]; then
            local ds_pkg; ds_pkg=$(_pkgs_parse_pkg_arg "download-size" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! apt-cache show -- "$ds_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$ds_pkg"
            else
                local ds_info ds_dl ds_inst ds_ver
                ds_info=$(apt-cache show -- "$ds_pkg" 2>/dev/null)
                ds_dl=$(_pkgs_apt_field "$ds_info" Size)
                ds_inst=$(_pkgs_apt_field "$ds_info" Installed-Size)
                ds_ver=$(_pkgs_apt_field "$ds_info" Version)
                printf "\n  ${C_GREEN}── Download Size: %s ──${C_RESET}\n\n" "$ds_pkg"
                printf "  ${C_WHITE}Version:${C_RESET}      %s\n" "${ds_ver:-unknown}"
                if (( _HAS_NUMFMT )); then
                    printf "  ${C_WHITE}Download:${C_RESET}     %s\n" "$(printf "%s" "$((ds_dl * 1))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${ds_dl} B")"
                    printf "  ${C_WHITE}Installed:${C_RESET}    %s\n" "$(printf "%s" "$((ds_inst * 1024))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${ds_inst} KiB")"
                else
                    printf "  ${C_WHITE}Download:${C_RESET}     %s bytes\n" "${ds_dl:-unknown}"
                    printf "  ${C_WHITE}Installed:${C_RESET}    %s KiB\n" "${ds_inst:-unknown}"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /check ]]; then
            clear
            printf "\n${C_MSG_INFO}── Checking installed packages... ──${C_RESET}\n\n"
            local ck_ok=0 ck_bad=0
            local ck_line
            while IFS= read -r ck_line; do
                [[ -z "$ck_line" ]] && continue
                local ck_pkg="${ck_line%% *}"
                local ck_status="${ck_line#* }"
                if [[ "$ck_status" == *"half-installed"* || "$ck_status" == *"config-files"* || "$ck_status" == *"not-installed"* ]]; then
                    printf "  ${C_RED}✗ %-28s${C_RESET} %s\n" "$ck_pkg" "$ck_status"
                    ((ck_bad++))
                else
                    ((ck_ok++))
                fi
            done < <(dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null)
            printf "\n  ${C_GREEN}OK:${C_RESET} %d    ${C_RED}Broken:${C_RESET} %d\n" "$ck_ok" "$ck_bad"
            if (( ck_bad > 0 )); then
                printf "\n  ${C_MSG_WARN}Run ${C_TEAL}${PKG_MGR} --fix-broken install${C_MSG_WARN} to repair${C_RESET}\n"
            else
                printf "\n  ${C_MSG_DONE}All packages are OK.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /group ]]; then
            clear
            printf "\n${C_MSG_INFO}── Packages by Section ──${C_RESET}\n\n"
            local -A group_sections
            local -A _pkgs_grp_cache
            local _grp_key _grp_val _grp_pkg=""
            while IFS=: read -r _grp_key _grp_val; do
                _grp_key="${_grp_key## }" _grp_val="${_grp_val## }"
                [[ "$_grp_key" == "Package" ]] && _grp_pkg="$_grp_val"
                [[ "$_grp_key" == "Section" && -n "$_grp_pkg" ]] && {
                    _pkgs_grp_cache[$_grp_pkg]="${_grp_val%%/*}"
                    _grp_pkg=""
                }
            done < <(apt-cache dump 2>/dev/null)
            local grp_line
            while IFS= read -r grp_line; do
                [[ -z "$grp_line" ]] && continue
                local grp_pkg="${grp_line%% *}"
                local grp_rest="${grp_line#* }"
                local grp_size="${grp_rest%% *}"
                local grp_section="${_pkgs_grp_cache[$grp_pkg]:-other}"
                [[ -z "$grp_section" ]] && grp_section="other"
                group_sections[$grp_section]="${group_sections[$grp_section]:+${group_sections[$grp_section]} }${grp_pkg}"
            done < <(dpkg-query -W -f='${Package} ${Installed-Size}\n' 2>/dev/null)
            local -a sorted_groups=()
            for grp_sec in "${(k)group_sections[@]}"; do
                local grp_count
                grp_count=$(echo "${group_sections[$grp_sec]}" | wc -w | tr -d ' ')
                sorted_groups+=("${grp_count} ${grp_sec}")
            done
            sorted_groups=("${(@o)sorted_groups}")
            for entry in "${sorted_groups[@]}"; do
                local gcount="${entry%% *}"
                local gname="${entry#* }"
                printf "  ${C_TEAL}%-20s${C_RESET} ${C_DIM}(%s packages)${C_RESET}\n" "$gname" "$gcount"
            done
            printf "\n  ${C_DIM}Total sections: %d${C_RESET}\n" "${#group_sections[@]}"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /outdated-top* ]]; then
            local ot_n=10
            if [[ "$query" != "/outdated-top" ]]; then
                local ot_arg="${query#* }"
                ot_arg="$(_pkgs_trim "$ot_arg")"
                if [[ -z "$ot_arg" || ! "$ot_arg" =~ ^[0-9]+$ ]]; then
                    printf "${C_MSG_REMOVE}Invalid number: %s${C_RESET}\n" "$ot_arg"
                    sleep 1
                    query=""
                    continue
                fi
                if (( ot_arg > 0 && ot_arg <= 100 )); then
                    ot_n="$ot_arg"
                fi
            fi
            clear
            printf "\n${C_MSG_INFO}── Top %d Outdated Packages ──${C_RESET}\n\n" "$ot_n"
            local ot_count=0
            while read -r ot_line; do
                [[ -z "$ot_line" ]] && continue
                [[ $ot_count -ge $ot_n ]] && break
                local opkg="${ot_line%% *}"
                local orest="${ot_line#* }"
                local oinst_ver="${orest%% *}"
                local ocand_ver="${orest#* }"
                [[ "$oinst_ver" == "$ocand_ver" ]] && continue
                ((ot_count++))
                printf "  ${C_WHITE}%-4s${C_RESET} ${C_TEAL}%-24s${C_RESET} ${C_DIM}%-16s${C_RESET} ${C_GREEN}%s${C_RESET}\n" \
                    "$ot_count" "$opkg" "$oinst_ver" "$ocand_ver"
            done < <(
                dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | while read -r pname pver; do
                    cver=$(apt-cache policy -- "$pname" 2>/dev/null | grep 'Candidate:' | head -1 | sed 's/^.*Candidate: //')
                    [[ -n "$cver" && "$pver" != "$cver" ]] && printf "%s %s %s\n" "$pname" "$pver" "$cver"
                done
            )
            if (( ot_count == 0 )); then
                printf "  ${C_MSG_DONE}All packages are up to date.${C_RESET}\n"
            else
                printf "\n  ${C_DIM}Showing %d of outdated packages${C_RESET}\n" "$ot_count"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /usage-top* ]]; then
            local ut_n=15
            if [[ "$query" != "/usage-top" ]]; then
                local ut_arg="${query#* }"
                ut_arg="$(_pkgs_trim "$ut_arg")"
                if [[ -z "$ut_arg" || ! "$ut_arg" =~ ^[0-9]+$ ]]; then
                    printf "${C_MSG_REMOVE}Invalid number: %s${C_RESET}\n" "$ut_arg"
                    sleep 1
                    query=""
                    continue
                fi
                if (( ut_arg > 0 && ut_arg <= 100 )); then
                    ut_n="$ut_arg"
                fi
            fi
            clear
            printf "\n${C_MSG_INFO}── Top %d Packages by Disk Usage ──${C_RESET}\n\n" "$ut_n"
            local ut_shown=0
            local ut_max_size=0
            local -a ut_sizes=()
            local -a ut_names=()
            while read -r ut_line; do
                [[ $ut_shown -ge $ut_n ]] && break
                local ut_pkg="${ut_line%% *}"
                local ut_rest="${ut_line#* }"
                local ut_size="${ut_rest%% *}"
                [[ -z "$ut_size" || "$ut_size" == "?" ]] && continue
                ((ut_shown++))
                ut_sizes+=("$ut_size")
                ut_names+=("$ut_pkg")
                (( ut_size > ut_max_size )) && ut_max_size="$ut_size"
            done < <(dpkg-query -W -f='${Package} ${Installed-Size}\n' 2>/dev/null | sort -k2 -rn)
            local ut_max_bar=30
            local ut_i
            for ut_i in {1..${#ut_names[@]}}; do
                local ut_sz="${ut_sizes[$ut_i]}"
                local ut_nm="${ut_names[$ut_i]}"
                local ut_bar_len=0
                (( ut_max_size > 0 )) && ut_bar_len=$(( ut_sz * ut_max_bar / ut_max_size ))
                (( ut_bar_len < 1 )) && ut_bar_len=1
                local ut_bar=""
                local ut_j
                for ut_j in {1..$ut_bar_len}; do
                    ut_bar="${ut_bar}█"
                done
                local ut_display
                ut_display=$(_pkgs_format_size "$ut_sz")
                printf "  ${C_WHITE}%-24s${C_RESET} ${C_TEAL}%-10s${C_RESET} ${C_GREEN}%s${C_RESET}\n" "$ut_nm" "$ut_display" "$ut_bar"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
            search_text="$(_pkgs_trim "$search_text")"
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
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /rdeps* ]]; then
            local rdeps_pkg; rdeps_pkg=$(_pkgs_parse_pkg_arg "rdeps" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! apt-cache show -- "$rdeps_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$rdeps_pkg"
            else
                printf "\n${C_MSG_INFO}--- Reverse dependencies of %s ---${C_RESET}\n\n" "$rdeps_pkg"
                local rdeps_out
                rdeps_out=$(apt-cache rdepends -- "$rdeps_pkg" 2>/dev/null | tail -n +3)
                if [[ -z "$rdeps_out" ]]; then
                    printf "${C_DIM}Nothing depends on %s.${C_RESET}\n" "$rdeps_pkg"
                else
                    printf "%s\n" "$rdeps_out"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
            search_term="$(_pkgs_trim "$search_term")"
            if [[ -z "$search_term" ]]; then
                printf "${C_MSG_WARN}Usage: /%s <search>${C_RESET}\n" "$cmd"
                sleep 1
                query=""
                continue
            fi

            local -a match_pkgs=()
            while IFS= read -r line; do
                [[ "$line" == [WE]:* || "$line" == " "* ]] && continue
                local name="${line%% *}"
                [[ -z "$name" || "$name" == -* ]] && continue
                _pkgs_validate_name "$name" || continue
                apt-cache show -- "$name" >/dev/null 2>&1 && match_pkgs+=("$name")
            done < <(apt-cache search -n "$search_term" 2>/dev/null)

            if [[ ${#match_pkgs[@]} -eq 0 ]]; then
                printf "\n${C_MSG_REMOVE}--- No packages matching \"%s\" ---${C_RESET}\n\n" "$search_term"
                continue
            fi

            case "$cmd" in
                install|remove)
                    clear
                    printf "\n  ${C_MSG_INFO}── %s: %d package(s) matched ──${C_RESET}\n" "${cmd:u}" "${#match_pkgs[@]}"
                    local _i
                    for _i in {1..${#match_pkgs[@]}}; do
                        printf "    ${C_WHITE}%s${C_RESET}\n" "${match_pkgs[$_i]}"
                    done
                    printf "\n  ${C_MSG_INFO}Proceed with %s? ${C_DIM}(y=dry-run, d=process, e=export, Enter=cancel)${C_RESET} " "${cmd}"
                    local batch_choice
                    read -q batch_choice; read -r
                    if [[ "$batch_choice" == "y" ]]; then
                        printf "\n${C_MSG_INFO}--- Dry run: ${cmd} ---${C_RESET}\n"
                        for pkg in "${match_pkgs[@]}"; do
                            if [[ "$cmd" == "install" ]]; then
                                local dep_count
                                dep_count=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$pkg" 2>/dev/null | grep -c '^  ' || true)
                                printf "  ${C_DIM}+ %s (%s deps)${C_RESET}\n" "$pkg" "$dep_count"
                            else
                                local rdep_count
                                rdep_count=$(apt-cache rdepends --installed "$pkg" 2>/dev/null | tail -n +2 | grep -cv '^$' || true)
                                printf "  ${C_DIM}- %s (%s rev-deps)${C_RESET}\n" "$pkg" "$rdep_count"
                            fi
                        done
                        printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                        read -r
                        clear
                        query=""
                        continue
                    elif [[ "$batch_choice" == "e" ]]; then
                        local export_file="pkg-install-$(date +%Y%m%d-%H%M%S).sh"
                        printf "${C_MSG_INFO}Export file path [${C_RESET}%s${C_MSG_INFO}]: ${C_RESET}" "$export_file"
                        local user_path
                        read -r user_path
                        [[ -n "$user_path" ]] && export_file="$user_path"
                        if _pkgs_validate_export_path "$export_file"; then
                            {
                                printf "#!/data/data/com.termux/files/usr/bin/sh\n"
                                printf "%s install \\\\\n" "$PKG_MGR"
                                local _ei
                                for _ei in {1..${#match_pkgs[@]}}; do
                                    if (( _ei < ${#match_pkgs[@]} )); then
                                        printf "    %s \\\\\n" "${match_pkgs[$_ei]}"
                                    else
                                        printf "    %s\n" "${match_pkgs[$_ei]}"
                                    fi
                                done
                            } > "$export_file"
                            chmod +x "$export_file" 2>/dev/null
                            printf "\n${C_MSG_DONE}Exported %d packages to: %s${C_RESET}\n" "${#match_pkgs[@]}" "$export_file"
                        else
                            printf "${C_MSG_REMOVE}--- Invalid or unsafe file path ---${C_RESET}\n"
                        fi
                        printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                        read -r
                        clear
                        query=""
                        continue
                    elif [[ "$batch_choice" != "d" ]]; then
                        clear
                        query=""
                        continue
                    fi
                    local ok=0 fail=0
                    local total=${#match_pkgs[@]}
                    for pkg in "${match_pkgs[@]}"; do
                        printf "${C_MSG_INFO}  [%d/${total}] %s %s...${C_RESET}" "$((ok+fail+1))" "$cmd" "$pkg"
                        if "${PKG_MGR}" "$cmd" -- "$pkg"; then
                            _pkgs_log_history "${cmd:u}" "$pkg"
                            printf "\r${C_MSG_DONE}  ✓ %s${C_RESET}\n" "$pkg"
                            ((ok++))
                        else
                            printf "\r${C_MSG_REMOVE}  ✗ %s failed${C_RESET}\n" "$pkg"
                            ((fail++))
                        fi
                    done
                    _pkgs_invalidate_cache
                    printf "\n  ${C_MSG_INFO}Done:${C_RESET} %d ok, %d failed\n" "$ok" "$fail"
                    printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                    read -r
                    clear
                    query=""
                    continue
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
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
            if dpkg -s -- "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
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
                    dry_deps=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$rp" 2>/dev/null | grep "^\w" | sort -u | wc -l | tr -d ' ')
                    printf "    ${C_GREEN}+ %-20s${C_RESET} ${C_DIM}%s deps${C_RESET}\n" "$rp" "${dry_deps:-0}"
                done
                printf "\n"
            fi
            if (( ${#to_remove[@]} > 0 )); then
                printf "  ${C_MSG_REMOVE}Would remove:${C_RESET}\n"
                for rp in "${to_remove[@]}"; do
                    local dry_rdeps
                    dry_rdeps=$(apt-cache rdepends -- "$rp" 2>/dev/null | tail -n +3 | wc -l | tr -d ' ')
                    printf "    ${C_RED}- %-20s${C_RESET} ${C_DIM}%s depend on it${C_RESET}\n" "$rp" "${dry_rdeps:-0}"
                done
                printf "\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
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
            if ! apt-cache show -- "$pkg_name" >/dev/null 2>&1; then
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
  /purge <pkg>          Remove package + config files
  /hold <pkg>           Pin package (prevent upgrades)
  /unhold <pkg>         Unpin package
  /export <pkg>         Export install script to .sh file
  /export-all           Export all installed packages
  /info <pkg>           Show full package details
  /search <text>        Search package descriptions
  /rdeps <pkg>          Show reverse dependencies
  /depends-on <pkg>     Show installed packages depending on this
  /deps <pkg>           Show dependencies
  /tree <pkg>           Show dependency tree
  /compare <a> <b>      Compare two packages side by side
  /note <pkg> <text>    Add/view package note
  /orphans              Show orphaned packages
  /orphans-safe         Show safe orphans (exclude essential)
  /orphans-remove       Remove all orphaned packages
  /outdated             Show installed packages with updates
  /top                  Top 10 largest packages
  /top <n>              Top N largest packages
  /size                 Total installed size
  /count                Count installed/available packages
  /update               Update apt cache
  /clean                Remove orphaned packages and cache
  /installed            Filter: show only installed
  /available            Filter: show only available
  /recent               Filter: show installed today
  /usage                Disk usage by section
  /usage <pkg>          Per-package file list
  /changelog <pkg>      Show package changelog
  /reinstall <pkg>      Reinstall package
  /search-file <text>   Search inside installed files
  /download-size <pkg>  Show download + installed size
  /check                Verify all installed packages
  /group                Group packages by section
  /outdated-top <n>     Top N outdated packages
  /usage-top <n>        Disk usage bar chart (top N)
  /version              System version info
  /all                  Reset filter: show everything
  /sort name or /sort size  Sort by name or size
  /history              View last 7 days of commands
  /review               Today's activity summary
  /stats                Today's install/remove counts
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
    [[ "$ZSH_EVAL_CONTEXT" == toplevel ]] && exit 0 || return 0
fi
if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    _pkgs_version
    [[ "$ZSH_EVAL_CONTEXT" == toplevel ]] && exit 0 || return 0
fi

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && pkgs "$@"
