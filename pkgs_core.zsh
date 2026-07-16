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
    local _PKGS_FAVORITES_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/favorites"
    local _PKGS_THEME_FILE="${_PKGS_CONFIG_DIR}/theme"
    local _PKGS_SELF_URL="https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/refs/heads/main/pkgs_core.zsh"

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
            printf "THEME=%s\n" "$_PKGS_THEME"
        } > "$_PKGS_CONFIG_FILE" 2>/dev/null
    }

    _pkgs_load_state() {
        if [[ -f "$_PKGS_CONFIG_FILE" ]]; then
            local line
            while IFS='=' read -r key val; do
                case "$key" in
                    FILTER) _PKGS_FILTER="$val" ;;
                    SORT) _PKGS_SORT="$val" ;;
                    THEME) _PKGS_THEME="$val" ;;
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

    _pkgs_apply_theme() {
        local theme="$1"
        case "$theme" in
            dark)
                C_GREEN=$'\033[38;5;114m'; C_TEAL=$'\033[38;5;109m'; C_AMBER=$'\033[38;5;180m'
                C_RED=$'\033[38;5;203m'; C_WHITE=$'\033[38;5;223m'; C_DIM=$'\033[38;5;59m' ;;
            light)
                C_GREEN=$'\033[38;5;28m'; C_TEAL=$'\033[38;5;24m'; C_AMBER=$'\033[38;5;130m'
                C_RED=$'\033[38;5;124m'; C_WHITE=$'\033[38;5;234m'; C_DIM=$'\033[38;5;243m' ;;
            minimal)
                C_GREEN=$'\033[1m'; C_TEAL=$'\033[1m'; C_AMBER=$'\033[1m'
                C_RED=$'\033[1;31m'; C_WHITE=$'\033[1m'; C_DIM=$'\033[2m' ;;
            neon)
                C_GREEN=$'\033[38;5;46m'; C_TEAL=$'\033[38;5;51m'; C_AMBER=$'\033[38;5;226m'
                C_RED=$'\033[38;5;199m'; C_WHITE=$'\033[38;5;255m'; C_DIM=$'\033[38;5;240m' ;;
            dracula)
                C_GREEN=$'\033[38;5;84m'; C_TEAL=$'\033[38;5;141m'; C_AMBER=$'\033[38;5;212m'
                C_RED=$'\033[38;5;213m'; C_WHITE=$'\033[38;5;252m'; C_DIM=$'\033[38;5;61m' ;;
            monokai)
                C_GREEN=$'\033[38;5;148m'; C_TEAL=$'\033[38;5;81m'; C_AMBER=$'\033[38;5;173m'
                C_RED=$'\033[38;5;196m'; C_WHITE=$'\033[38;5;252m'; C_DIM=$'\033[38;5;59m' ;;
            solarized)
                C_GREEN=$'\033[38;5;64m'; C_TEAL=$'\033[38;5;37m'; C_AMBER=$'\033[38;5;136m'
                C_RED=$'\033[38;5;160m'; C_WHITE=$'\033[38;5;230m'; C_DIM=$'\033[38;5;243m' ;;
            *)
                C_GREEN=$'\033[38;5;114m'; C_TEAL=$'\033[38;5;109m'; C_AMBER=$'\033[38;5;180m'
                C_RED=$'\033[38;5;203m'; C_WHITE=$'\033[38;5;223m'; C_DIM=$'\033[38;5;59m' ;;
        esac
        C_INST_PREFIX="${C_GREEN}[✓]${C_RESET}"
        C_NOT_INST_PREFIX="${C_DIM}[ ]${C_RESET}"
        C_PKG_NAME="${C_GREEN}"
        C_PKG_DESC="${C_DIM}"
        C_MSG_INSTALL="${C_GREEN}"
        C_MSG_REMOVE="${C_RED}"
        C_MSG_INFO="${C_AMBER}"
        C_MSG_WARN="${C_AMBER}"
        C_MSG_DONE="${C_TEAL}"
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
        printf "\n  ${C_WHITE}%s${C_RESET}\n" "$pkg_name"
        printf "  ${C_DIM}Version:${C_RESET}      %s\n" "$(_pkgs_apt_field "$info" Version)"
        printf "  ${C_DIM}Section:${C_RESET}      %s\n" "$(_pkgs_apt_field "$info" Section)"
        printf "  ${C_DIM}Maintainer:${C_RESET}   %s\n" "$(print -r -- "$(_pkgs_apt_field "$info" Maintainer)" | cut -c1-32)"
        local size
        size=$(_pkgs_apt_field "$info" Installed-Size)
        if [[ -n "$size" && "$size" =~ ^[0-9]+$ ]]; then
            size=$(_pkgs_format_size "$size")
        else
            size="${size:-?} KiB"
        fi
        printf "  ${C_DIM}Size:${C_RESET}         %s\n" "$size"
        local status_str="not installed"
        if dpkg -s -- "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
            status_str="${C_GREEN}installed${C_RESET}"
        fi
        printf "  ${C_DIM}Status:${C_RESET}       %s\n" "$status_str"
        local desc
        desc=$(echo "$info" | sed -n '/^Description:/{ s/^Description: //p; :a; n; /^ /{ s/^ //p; ba }; }')
        printf "  ${C_WHITE}Description:${C_RESET}\n"
        printf "  ${C_DIM}%s${C_RESET}\n" "$(echo "$desc" | head -6)"
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
        printf "    ${C_TEAL}/mirror${C_RESET}           Switch apt mirror\n"
        printf "    ${C_TEAL}/fav <pkg>${C_RESET}        Toggle package favorite\n"
        printf "    ${C_TEAL}/fav-list${C_RESET}         Show all favorites\n"
        printf "    ${C_TEAL}/fav-remove${C_RESET}      Remove a favorite\n"
        printf "    ${C_TEAL}/import <file>${C_RESET}   Install from package list file\n"
        printf "    ${C_TEAL}/why <pkg>${C_RESET}       Show why a package is installed\n"
        printf "    ${C_TEAL}/suggest <pkg>${C_RESET}   Show recommended packages\n"
        printf "    ${C_TEAL}/nuke${C_RESET}            Interactive storage cleanup\n"
        printf "    ${C_TEAL}/whatsnew${C_RESET}        Show recent upgrade changelogs\n"
        printf "    ${C_TEAL}/tips${C_RESET}            Termux tips & tricks\n"
        printf "    ${C_TEAL}/self-update${C_RESET}     Update pkgs from GitHub\n"
        printf "    ${C_TEAL}/search-size <min> <max>${C_RESET} Find pkgs by size\n"
        printf "    ${C_TEAL}/pkg-history <pkg>${C_RESET}  Per-pkg history\n"
        printf "    ${C_TEAL}/depends-chain <a> <b>${C_RESET} Dep path finder\n"
        printf "    ${C_TEAL}/broken${C_RESET}           Find broken packages\n"
        printf "    ${C_TEAL}/conflicts-with <pkg>${C_RESET} Show conflicts\n"
        printf "    ${C_TEAL}/provides <pkg>${C_RESET}    Virtual packages\n"
        printf "    ${C_TEAL}/manually-installed${C_RESET} Manual installs only\n"
        printf "    ${C_TEAL}/auto-installed${C_RESET}    Auto installs only\n"
        printf "    ${C_TEAL}/upgrade-plan${C_RESET}      Simulated upgrade\n"
        printf "    ${C_TEAL}/pkg-ages${C_RESET}          Package age view\n"
        printf "    ${C_TEAL}/unused-libs${C_RESET}       Orphaned libraries\n"
        printf "    ${C_TEAL}/maintainer <name>${C_RESET} Search by maintainer\n"
        printf "    ${C_TEAL}/log-search <text>${C_RESET} Search dpkg logs\n"
        printf "    ${C_TEAL}/mirror-backup${C_RESET}     Backup/restore mirrors\n"
        printf "    ${C_TEAL}/size-histogram${C_RESET}    Size distribution\n"
        printf "    ${C_TEAL}/deptree <pkg>${C_RESET}    Visual dependency tree\n"
        printf "    ${C_TEAL}/reverse-tree <pkg>${C_RESET} Reverse dependency tree\n"
        printf "    ${C_TEAL}/upgrade-size${C_RESET}      Total upgrade download size\n"
        printf "    ${C_TEAL}/download <pkg>${C_RESET}    Download pkg without install\n"
        printf "    ${C_TEAL}/verify <pkg>${C_RESET}      Verify package checksums\n"
        printf "    ${C_TEAL}/mirror-latency${C_RESET}    Ping-test all mirrors\n"
        printf "    ${C_TEAL}/mirror-bandwidth${C_RESET}  Bandwidth-test mirrors\n"
        printf "    ${C_TEAL}/pkg-changes${C_RESET}       Last apt upgrade diff\n"
        printf "    ${C_TEAL}/pkg-recommendations${C_RESET} Who recommends this pkg\n"
        printf "    ${C_TEAL}/pkg-suggests <pkg>${C_RESET} Who suggests this pkg\n"
        printf "    ${C_TEAL}/pkg-breaks <pkg>${C_RESET}  What breaks if installed\n"
        printf "    ${C_TEAL}/pkg-replaces <pkg>${C_RESET} What does this replace\n"
        printf "    ${C_TEAL}/owner <file>${C_RESET}      Which pkg owns this file\n"
        printf "    ${C_TEAL}/removed${C_RESET}           Packages removed last upgrade\n"
        printf "    ${C_TEAL}/new-pkgs${C_RESET}          Installed this week\n"
        printf "    ${C_TEAL}/same-size${C_RESET}         Packages with identical size\n"
        printf "    ${C_TEAL}/depends-on-list${C_RESET}   Shared deps of multiple pkgs\n"
        printf "    ${C_TEAL}/upgradable${C_RESET}        Upgradable with version diff\n"
        printf "    ${C_TEAL}/whatprovides <file>${C_RESET} Find binary/file provider\n"
        printf "    ${C_TEAL}/snap-install <file>${C_RESET} Install from local .deb\n"
        printf "    ${C_TEAL}/simulate-remove <pkg>${C_RESET} Simulate removal\n"
        printf "    ${C_TEAL}/repo-stats${C_RESET}        Packages per repository\n"
        printf "    ${C_TEAL}/download-est <pkg>${C_RESET} Download + installed size\n"
        printf "    ${C_TEAL}/diff <pkg>${C_RESET}        Changelog diff of last upgrade\n"
        printf "    ${C_TEAL}/help${C_RESET}              Show this help\n"
        printf "    ${C_TEAL}/theme${C_RESET}            Switch color scheme\n"
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
    _pkgs_apply_theme "$_PKGS_THEME"
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

        if [[ "$query" == /theme* ]]; then
            local theme_arg="${query#/theme }"
            [[ "$theme_arg" == "/theme" ]] && theme_arg=""
            clear
            if [[ -n "$theme_arg" ]]; then
                case "$theme_arg" in
                    dark|light|minimal|neon|dracula|monokai|solarized)
                        _pkgs_apply_theme "$theme_arg"
                        _PKGS_THEME="$theme_arg"
                        _pkgs_save_state
                        printf "\n  ${C_MSG_DONE}Theme changed to: %s${C_RESET}\n" "$theme_arg"
                        ;;
                    *)
                        printf "\n  ${C_MSG_WARN}Unknown theme: %s${C_RESET}\n" "$theme_arg"
                        printf "  ${C_DIM}Available: dark, light, minimal, neon, dracula, monokai, solarized${C_RESET}\n"
                        ;;
                esac
            else
                printf "\n  ${C_WHITE}Color Themes${C_RESET}\n\n"
                local -a theme_list=("dark" "light" "minimal" "neon" "dracula" "monokai" "solarized")
                local chosen_theme
                chosen_theme=$(printf '%s\n' "${theme_list[@]}" | fzf --prompt=" Theme> " --preview='echo "Preview: {}"' --height=50% --reverse)
                if [[ -n "$chosen_theme" ]]; then
                    _pkgs_apply_theme "$chosen_theme"
                    _PKGS_THEME="$chosen_theme"
                    _pkgs_save_state
                    printf "\n  ${C_MSG_DONE}Theme changed to: %s${C_RESET}\n" "$chosen_theme"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
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

        # --- /mirror ---
        if [[ "$query" == /mirror ]]; then
            clear
            local -a mirrors=(
                "packages.termux.dev|Official (packages.termux.dev)|Default"
                "packages-cf.termux.dev|CloudFlare CDN|packages-cf.termux.dev"
                "mirrors.tuna.tsinghua.edu.cn|Tsinghua TUNA|China"
                "mirror.iscas.ac.cn|CAS ISC|China"
                "mirrors.ustc.edu.cn|USTC|China"
                "mirrors.aliyun.com|Alibaba|China"
                "mirrors.nju.edu.cn|Nanjing Univ|China"
                "mirrors.sjtu.edu.cn|SJTU|China"
                "mirrors.zju.edu.cn|Zhejiang Univ|China"
                "mirrors.hust.edu.cn|HUST|China"
                "mirror.sjtu.edu.cn|SJTU mirror|China"
                "linux.domainesia.com|DomaiNesia|Indonesia"
                "mirror.freedif.org|karibu|Singapore"
                "mirror.jeonnam.school|Jeonnam HS|South Korea"
                "mirror.meowsmp.net|MeowIce|Vietnam"
                "mirror.nag.albony.in|Albonycal|India"
                "mirror.nevacloud.com|Nevacloud|Indonesia"
                "mirror.rinarin.dev|Bombyeol|South Korea"
                "mirror.twds.com.tw|Taiwan DSC|Taiwan"
                "mirrors.cbrx.io|CyberRex0|Japan"
                "mirrors.in.sahilister.net|sahilister|India"
                "mirrors.krnk.org|KuronekoServer|Japan"
                "mirrors.nguyenhoang.cloud|Nguyen Hoang|Vietnam"
                "mirrors.ravidwivedi.in|Ravi|India"
                "mirrors.saswata.cc|Saswata|India"
                "termux.niranjan.co|Niranjan F|India"
                "tmx.xvx.my.id|MyDapitt|Indonesia"
                "ftp.agdsn.de|AG DSN|Germany"
                "ftp.fau.de|FAU|Germany"
                "ftp.icm.edu.pl|ICM Warsaw|Poland"
                "grimler.se|grimler|Finland"
                "is.mirror.flokinet.net|FlokiNET IS|Iceland"
                "md.mirrors.hacktegic.com|amocrenco|Moldova"
                "mirror.accum.se|ACCUM|Sweden"
                "mirror.autkin.net|Andriy Utkin|UK"
                "mirror.bouwhuis.network|bouwhuis|Netherlands"
                "mirror.cutie.dating|CutiesDomain|Germany"
                "mirror.leitecastro.com|T. Leite|Portugal"
                "mirror.sunred.org|SunRed|Germany"
                "mirrors.de.sahilister.net|sahilister DE|Germany"
                "mirrors.medzik.dev|M3DZIK|Germany"
                "nl.mirror.flokinet.net|FlokiNET NL|Netherlands"
                "ro.mirror.flokinet.net|FlokiNET RO|Romania"
                "termux.3san.dev|Exosunandnet|Spain"
                "termux.cdn.lumito.net|LumitoLuma|Germany"
                "termux.librehat.com|Librehat|Germany"
                "gnlug.org|GNLUG|USA"
                "mirror.csclub.uwaterloo.ca|UWaterloo|Canada"
                "mirror.fcix.net|FCIX|USA"
                "mirror.mwt.me|mwt|USA/CDN"
                "mirror.quantum5.ca|quantum5|Canada"
                "mirror.vern.cc|vern.cc|USA"
                "mirrors.utermux.dev|Utermux|USA"
                "plug-mirror.rcac.purdue.edu|Purdue PLUG|USA"
                "termux.danyael.xyz|Dan Yael|USA"
                "mirrors.middlendian.com|DiffieHellman|Australia"
                "mirror.mephi.ru|MEPhI|Russia"
                "repository.su|Dmitry|Russia"
            )
            local -a mirror_display=()
            local -A mirror_map
            for entry in "${mirrors[@]}"; do
                IFS='|' read -r url desc region <<< "$entry"
                mirror_display+=("${desc} [${region}] (${url})")
                mirror_map["${desc} [${region}] (${url})"]="$url"
            done
            local chosen
            chosen=$(printf '%s\n' "${mirror_display[@]}" | fzf --prompt=" Mirror> " --preview='echo "Mirror: {2}"' --height=80% --reverse)
            if [[ -z "$chosen" ]]; then
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                continue
            fi
            local new_url="${mirror_map[$chosen]}"
            printf "\n  ${C_MSG_INFO}Testing mirror speed...${C_RESET}\n"
            local start_ms end_ms elapsed_ms
            start_ms=$(($(date +%s%N)/1000000))
            if curl -sI --connect-timeout 5 "https://${new_url}/dists/stable/Release" >/dev/null 2>&1; then
                end_ms=$(($(date +%s%N)/1000000))
                elapsed_ms=$((end_ms - start_ms))
                printf "  ${C_MSG_DONE}Response: %dms${C_RESET}\n" "$elapsed_ms"
            else
                printf "  ${C_MSG_REMOVE}Mirror unreachable${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                continue
            fi
            printf "\n  ${C_MSG_WARN}Apply mirror to sources.list? (y/N) ${C_RESET}"
            read -q confirm; read -r
            if [[ "$confirm" == "y" ]]; then
                local src_list="${PREFIX}/etc/apt/sources.list"
                if [[ -f "$src_list" ]]; then
                    cp "$src_list" "${src_list}.bak" 2>/dev/null
                    sed -i "s|^deb https://[^ ]* /apt/termux-main |deb https://${new_url}/apt/termux-main |" "$src_list"
                    sed -i "s|^deb https://[^ ]* /termux-main |deb https://${new_url}/termux-main |" "$src_list"
                fi
                local x11_list="${PREFIX}/etc/apt/sources.list.d/x11.list"
                if [[ -f "$x11_list" ]]; then
                    cp "$x11_list" "${x11_list}.bak" 2>/dev/null
                    sed -i "s|^deb https://[^ ]* /apt/termux-x11 |deb https://${new_url}/apt/termux-x11 |" "$x11_list"
                    sed -i "s|^deb https://[^ ]* /termux-x11 |deb https://${new_url}/termux-x11 |" "$x11_list"
                fi
                local root_list="${PREFIX}/etc/apt/sources.list.d/root.list"
                if [[ -f "$root_list" ]]; then
                    cp "$root_list" "${root_list}.bak" 2>/dev/null
                    sed -i "s|^deb https://[^ ]* /apt/termux-root |deb https://${new_url}/apt/termux-root |" "$root_list"
                    sed -i "s|^deb https://[^ ]* /termux-root |deb https://${new_url}/termux-root |" "$root_list"
                fi
                printf "\n  ${C_MSG_DONE}Mirror applied. Run /update to refresh.${C_RESET}\n"
                _pkgs_log_history "MIRROR" "$new_url"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /fav ---
        if [[ "$query" == /fav-list ]]; then
            clear
            mkdir -p "$(dirname "$_PKGS_FAVORITES_FILE")" 2>/dev/null
            if [[ ! -s "$_PKGS_FAVORITES_FILE" ]]; then
                printf "\n  ${C_MSG_WARN}No favorites saved yet.${C_RESET}\n"
            else
                printf "\n  ${C_GREEN}Favorite Packages${C_RESET}\n\n"
                while IFS= read -r pkg; do
                    [[ -z "$pkg" ]] && continue
                    local f_status=""
                    dpkg -s -- "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' && f_status="${C_GREEN}[installed]${C_RESET}" || f_status="${C_DIM}[not installed]${C_RESET}"
                    printf "    ${C_TEAL}%s${C_RESET}  %s\n" "$pkg" "$f_status"
                done < "$_PKGS_FAVORITES_FILE"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        if [[ "$query" == /fav-remove* ]]; then
            local fav_rm_pkg="${query#/fav-remove }"
            [[ "$fav_rm_pkg" == "/fav-remove" ]] && fav_rm_pkg=""
            if [[ -z "$fav_rm_pkg" ]]; then
                clear
                mkdir -p "$(dirname "$_PKGS_FAVORITES_FILE")" 2>/dev/null
                if [[ ! -s "$_PKGS_FAVORITES_FILE" ]]; then
                    printf "\n  ${C_MSG_WARN}No favorites to remove.${C_RESET}\n"
                else
                    local chosen_fav
                    chosen_fav=$(cat "$_PKGS_FAVORITES_FILE" | fzf --prompt=" Remove favorite> " --height=50% --reverse)
                    [[ -n "$chosen_fav" ]] && fav_rm_pkg="$chosen_fav"
                fi
            fi
            if [[ -n "$fav_rm_pkg" ]]; then
                mkdir -p "$(dirname "$_PKGS_FAVORITES_FILE")" 2>/dev/null
                if grep -qx "$fav_rm_pkg" "$_PKGS_FAVORITES_FILE" 2>/dev/null; then
                    sed -i "/^${fav_rm_pkg}$/d" "$_PKGS_FAVORITES_FILE"
                    printf "\n  ${C_MSG_DONE}Removed %s from favorites.${C_RESET}\n" "$fav_rm_pkg"
                else
                    printf "\n  ${C_MSG_WARN}%s not in favorites.${C_RESET}\n" "$fav_rm_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        if [[ "$query" == /fav* && "$query" != /fav-list && "$query" != /fav-remove* ]]; then
            local fav_pkg="${query#/fav }"
            [[ "$fav_pkg" == "/fav" ]] && fav_pkg=""
            if [[ -z "$fav_pkg" ]]; then
                clear
                _pkgs_get_cached_list > /dev/null 2>&1
                fav_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Add favorite> " --height=50% --reverse)
                fav_pkg=$(echo "$fav_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$fav_pkg" ]]; then
                mkdir -p "$(dirname "$_PKGS_FAVORITES_FILE")" 2>/dev/null
                touch "$_PKGS_FAVORITES_FILE"
                if grep -qx "$fav_pkg" "$_PKGS_FAVORITES_FILE" 2>/dev/null; then
                    sed -i "/^${fav_pkg}$/d" "$_PKGS_FAVORITES_FILE"
                    printf "\n  ${C_MSG_DONE}Removed %s from favorites.${C_RESET}\n" "$fav_pkg"
                else
                    echo "$fav_pkg" >> "$_PKGS_FAVORITES_FILE"
                    printf "\n  ${C_MSG_DONE}Added %s to favorites.${C_RESET}\n" "$fav_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /import ---
        if [[ "$query" == /import* ]]; then
            local import_file="${query#/import }"
            [[ "$import_file" == "/import" ]] && import_file=""
            clear
            if [[ -z "$import_file" || ! -f "$import_file" ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /import <file>${C_RESET}\n"
                printf "  ${C_DIM}File should contain one package name per line.${C_RESET}\n"
            else
                local -a import_pkgs=()
                while IFS= read -r line; do
                    line="${line%%#*}"
                    line="${line// /}"
                    [[ -z "$line" ]] && continue
                    import_pkgs+=("$line")
                done < "$import_file"
                if (( ${#import_pkgs[@]} == 0 )); then
                    printf "\n  ${C_MSG_WARN}No packages found in file.${C_RESET}\n"
                else
                    printf "\n  ${C_MSG_INFO}Packages to install (%d):${C_RESET}\n" "${#import_pkgs[@]}"
                    for p in "${import_pkgs[@]}"; do
                        if dpkg -s -- "$p" 2>/dev/null | grep -q '^Status: install ok installed'; then
                            printf "    ${C_DIM}%s (already installed)${C_RESET}\n" "$p"
                        else
                            printf "    ${C_TEAL}%s${C_RESET}\n" "$p"
                        fi
                    done
                    printf "\n  ${C_MSG_WARN}Install all? (y/N) ${C_RESET}"
                    read -q confirm; read -r
                    if [[ "$confirm" == "y" ]]; then
                        local ok=0 fail=0
                        for p in "${import_pkgs[@]}"; do
                            printf "  ${C_MSG_INFO}[%d/%d] Installing %s...${C_RESET}" "$((ok+fail+1))" "${#import_pkgs[@]}" "$p"
                            if "${PKG_MGR}" install -y -- "$p" >/dev/null 2>&1; then
                                printf "\r${C_MSG_DONE}[%d/%d] ✓ %s${C_RESET}\n" "$((ok+fail+1))" "${#import_pkgs[@]}" "$p"
                                _pkgs_log_history "INSTALL" "$p"
                                ((ok++))
                            else
                                printf "\r${C_MSG_REMOVE}[%d/%d] ✗ %s failed${C_RESET}\n" "$((ok+fail+1))" "${#import_pkgs[@]}" "$p"
                                ((fail++))
                            fi
                        done
                        printf "\n  ${C_MSG_DONE}Done:${C_RESET} %d ok, %d failed\n" "$ok" "$fail"
                    fi
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /why ---
        if [[ "$query" == /why* ]]; then
            local why_pkg="${query#/why }"
            [[ "$why_pkg" == "/why" ]] && why_pkg=""
            clear
            if [[ -z "$why_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                why_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Why installed> " --height=50% --reverse)
                why_pkg=$(echo "$why_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$why_pkg" ]]; then
                printf "\n  ${C_WHITE}Why is %s installed?${C_RESET}\n\n" "$why_pkg"
                if dpkg -s -- "$why_pkg" 2>/dev/null | grep -q '^Status: install ok installed'; then
                    local inst_date
                    inst_date=$(dpkg-query -W -f='${db-fsys:Last-Modified}' -- "$why_pkg" 2>/dev/null || echo "unknown")
                    printf "  ${C_DIM}Installed since:${C_RESET}   %s\n" "$inst_date"
                    local priority
                    priority=$(apt-cache show "$why_pkg" 2>/dev/null | sed -n 's/^Priority: //p')
                    printf "  ${C_DIM}Priority:${C_RESET}          %s\n" "${priority:-unknown}"
                    local section
                    section=$(apt-cache show "$why_pkg" 2>/dev/null | sed -n 's/^Section: //p')
                    printf "  ${C_DIM}Section:${C_RESET}           %s\n" "${section:-unknown}"
                    local mark
                    mark=$(apt-mark showmanual 2>/dev/null | grep -x "$why_pkg")
                    if [[ -n "$mark" ]]; then
                        printf "  ${C_GREEN}Install type:${C_RESET}      manual (you installed this)\n"
                    else
                        printf "  ${C_MSG_INFO}Install type:${C_RESET}      auto (dependency)\n"
                        printf "\n  ${C_WHITE}Dependents (what depends on %s):${C_RESET}\n" "$why_pkg"
                        local -a rdeps=()
                        while IFS= read -r dep; do
                            [[ -z "$dep" ]] && continue
                            rdeps+=("$dep")
                        done < <(apt-cache rdepends --installed "$why_pkg" 2>/dev/null | tail -n +2 | grep -v "^$")
                        if (( ${#rdeps[@]} == 0 )); then
                            printf "  ${C_DIM}No installed dependents found${C_RESET}\n"
                        else
                            for dep in "${rdeps[@]}"; do
                                printf "    ${C_TEAL}%s${C_RESET}\n" "$dep"
                            done
                        fi
                    fi
                    printf "\n  ${C_WHITE}Reverse dependencies:${C_RESET}\n"
                    local -a revdeps=()
                    while IFS= read -r dep; do
                        [[ -z "$dep" ]] && continue
                        revdeps+=("$dep")
                    done < <(apt-cache rdepends "$why_pkg" 2>/dev/null | tail -n +2 | grep -v "^$" | head -20)
                    if (( ${#revdeps[@]} == 0 )); then
                        printf "  ${C_DIM}None${C_RESET}\n"
                    else
                        for dep in "${revdeps[@]}"; do
                            if dpkg -s -- "$dep" 2>/dev/null | grep -q '^Status: install ok installed'; then
                                printf "    ${C_GREEN}%s${C_RESET} ${C_DIM}(installed)${C_RESET}\n" "$dep"
                            else
                                printf "    ${C_DIM}%s${C_RESET}\n" "$dep"
                            fi
                        done
                    fi
                else
                    printf "  ${C_MSG_WARN}%s is not installed.${C_RESET}\n" "$why_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /suggest ---
        if [[ "$query" == /suggest* ]]; then
            local sug_pkg="${query#/suggest }"
            [[ "$sug_pkg" == "/suggest" ]] && sug_pkg=""
            clear
            if [[ -z "$sug_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                sug_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Suggest for> " --height=50% --reverse)
                sug_pkg=$(echo "$sug_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$sug_pkg" ]]; then
                printf "\n  ${C_WHITE}Suggested packages for %s:${C_RESET}\n\n" "$sug_pkg"
                local -a suggestions=()
                while IFS= read -r line; do
                    local pkg_name
                    pkg_name=$(echo "$line" | sed -n 's/.*: //p')
                    [[ -z "$pkg_name" ]] && continue
                    if ! dpkg -s -- "$pkg_name" 2>/dev/null | grep -q '^Status: install ok installed'; then
                        local pkg_desc
                        pkg_desc=$(apt-cache show "$pkg_name" 2>/dev/null | sed -n 's/^Description: //p' | head -1)
                        printf "    ${C_TEAL}%-30s${C_RESET} %s\n" "$pkg_name" "${pkg_desc:0:50}"
                        suggestions+=("$pkg_name")
                    fi
                done < <(apt-cache depends "$sug_pkg" 2>/dev/null | grep -E "^\s+(Recommends|Suggests):")
                if (( ${#suggestions[@]} == 0 )); then
                    printf "  ${C_DIM}No additional suggestions.${C_RESET}\n"
                else
                    printf "\n  ${C_MSG_WARN}Install suggested? (y/N) ${C_RESET}"
                    read -q sug_confirm; read -r
                    if [[ "$sug_confirm" == "y" ]]; then
                        local sug_ok=0 sug_fail=0
                        for sp in "${suggestions[@]}"; do
                            printf "  ${C_MSG_INFO}Installing %s...${C_RESET}" "$sp"
                            if "${PKG_MGR}" install -y -- "$sp" >/dev/null 2>&1; then
                                printf "\r${C_MSG_DONE}✓ %s${C_RESET}\n" "$sp"
                                _pkgs_log_history "INSTALL" "$sp"
                                ((sug_ok++))
                            else
                                printf "\r${C_MSG_REMOVE}✗ %s failed${C_RESET}\n" "$sp"
                                ((sug_fail++))
                            fi
                        done
                        printf "\n  ${C_MSG_DONE}Done:${C_RESET} %d ok, %d failed\n" "$sug_ok" "$sug_fail"
                    fi
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /nuke ---
        if [[ "$query" == /nuke ]]; then
            clear
            printf "\n  ${C_WHITE}Termux Storage Cleanup${C_RESET}\n\n"
            local total_saved=0
            local -a nuke_items=()
            local apt_size=0
            if [[ -d "${PREFIX}/var/cache/apt/archives" ]]; then
                apt_size=$(du -sk "${PREFIX}/var/cache/apt/archives" 2>/dev/null | awk '{print $1}')
                if (( apt_size > 0 )); then
                    printf "  ${C_TEAL}[A]${C_RESET} apt cache:              %s\n" "$(_pkgs_format_size "$apt_size")"
                    nuke_items+=("apt:$apt_size")
                fi
            fi
            local tmp_size=0
            if [[ -d "${PREFIX}/tmp" ]]; then
                tmp_size=$(du -sk "${PREFIX}/tmp" 2>/dev/null | awk '{print $1}')
                if (( tmp_size > 0 )); then
                    printf "  ${C_TEAL}[B]${C_RESET} tmp ($PREFIX/tmp):      %s\n" "$(_pkgs_format_size "$tmp_size")"
                    nuke_items+=("tmp:$tmp_size")
                fi
            fi
            local cache_size=0
            if [[ -d "$HOME/.cache" ]]; then
                cache_size=$(du -sk "$HOME/.cache" 2>/dev/null | awk '{print $1}')
                if (( cache_size > 0 )); then
                    printf "  ${C_TEAL}[C]${C_RESET} ~/.cache:               %s\n" "$(_pkgs_format_size "$cache_size")"
                    nuke_items+=("cache:$cache_size")
                fi
            fi
            local hist_size=0
            if [[ -d "$_PKGS_HISTORY_DIR" ]]; then
                hist_size=$(du -sk "$_PKGS_HISTORY_DIR" 2>/dev/null | awk '{print $1}')
                if (( hist_size > 0 )); then
                    printf "  ${C_TEAL}[D]${C_RESET} pkgs history logs:      %s\n" "$(_pkgs_format_size "$hist_size")"
                    nuke_items+=("history:$hist_size")
                fi
            fi
            local orphan_size=0
            local -a orphans=()
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                local ps
                ps=$(dpkg-query -W -f='${Installed-Size}' -- "$pkg" 2>/dev/null)
                [[ -n "$ps" ]] && orphan_size=$((orphan_size + ps))
                orphans+=("$pkg")
            done < <("${PKG_MGR}" autoremove --dry-run 2>&1 | grep -oP '(?<=\s)[a-z][a-z0-9.+\-]+' | sort -u)
            if (( orphan_size > 0 )); then
                printf "  ${C_TEAL}[E]${C_RESET} orphaned packages:     %s (%d pkgs)\n" "$(_pkgs_format_size "$orphan_size")" "${#orphans[@]}"
                nuke_items+=("orphans:$orphan_size")
            fi
            local pyc_size=0
            if [[ -d "$HOME" ]]; then
                pyc_size=$(find "$HOME" -name "*.pyc" -type f -exec du -sk {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
                if (( pyc_size > 0 )); then
                    printf "  ${C_TEAL}[F]${C_RESET} .pyc files:             %s\n" "$(_pkgs_format_size "$pyc_size")"
                    nuke_items+=("pyc:$pyc_size")
                fi
            fi
            local o_size=0
            if [[ -d "$HOME" ]]; then
                o_size=$(find "$HOME" -name "*.o" -type f -exec du -sk {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
                if (( o_size > 0 )); then
                    printf "  ${C_TEAL}[G]${C_RESET} .o files:               %s\n" "$(_pkgs_format_size "$o_size")"
                    nuke_items+=("obj:$o_size")
                fi
            fi
            local trash_size=0
            if [[ -d "$HOME/.Trash" ]]; then
                trash_size=$(du -sk "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
                if (( trash_size > 0 )); then
                    printf "  ${C_TEAL}[H]${C_RESET} ~/.Trash:               %s\n" "$(_pkgs_format_size "$trash_size")"
                    nuke_items+=("trash:$trash_size")
                fi
            fi
            if (( ${#nuke_items[@]} == 0 )); then
                printf "\n  ${C_MSG_DONE}Nothing to clean. Your Termux is lean.${C_RESET}\n"
            else
                printf "\n  ${C_MSG_WARN}Clean all? (y/N) ${C_RESET}"
                read -q nuke_confirm; read -r
                if [[ "$nuke_confirm" == "y" ]]; then
                    for item in "${nuke_items[@]}"; do
                        IFS=':' read -r type size <<< "$item"
                        case "$type" in
                            apt)
                                apt-get clean 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ apt cache cleaned${C_RESET}\n"
                                ;;
                            tmp)
                                rm -rf "${PREFIX}/tmp"/* 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ tmp cleaned${C_RESET}\n"
                                ;;
                            cache)
                                rm -rf "$HOME/.cache" 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ ~/.cache cleaned${C_RESET}\n"
                                ;;
                            history)
                                find "$_PKGS_HISTORY_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ old history logs removed${C_RESET}\n"
                                ;;
                            orphans)
                                "${PKG_MGR}" autoremove -y 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ orphans removed${C_RESET}\n"
                                ;;
                            pyc)
                                find "$HOME" -name "*.pyc" -type f -delete 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ .pyc files removed${C_RESET}\n"
                                ;;
                            obj)
                                find "$HOME" -name "*.o" -type f -delete 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ .o files removed${C_RESET}\n"
                                ;;
                            trash)
                                rm -rf "$HOME/.Trash" 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ ~/.Trash removed${C_RESET}\n"
                                ;;
                        esac
                        total_saved=$((total_saved + size))
                    done
                    printf "\n  ${C_MSG_DONE}Freed ~%s${C_RESET}\n" "$(_pkgs_format_size "$total_saved")"
                    _pkgs_log_history "NUKE" "cleanup"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /whatsnew ---
        if [[ "$query" == /whatsnew ]]; then
            clear
            printf "\n  ${C_WHITE}Recently Upgraded Packages${C_RESET}\n\n"
            local dpkg_log="/data/data/com.termux/files/usr/var/lib/dpkg/status"
            local -a recent_upgraded=()
            if [[ -f "$_PKGS_HISTORY_FILE" ]]; then
                while IFS='|' read -r ts action pkg; do
                    [[ "$action" == "UPGRADE" ]] && recent_upgraded+=("$pkg")
                done < "$_PKGS_HISTORY_FILE"
            fi
            local -a extra_logs
            extra_logs=($(ls -t /data/data/com.termux/files/usr/var/cache/apt/archives/.. 2>/dev/null))
            for hist_file in $(find "$_PKGS_HISTORY_DIR" -name "*.log" -mtime -7 2>/dev/null | sort -r | head -7); do
                while IFS='|' read -r ts action pkg; do
                    [[ "$action" == "UPGRADE" ]] && recent_upgraded+=("$pkg")
                done < "$hist_file"
            done
            local -A seen_pkgs
            local -a unique_pkgs=()
            for p in "${recent_upgraded[@]}"; do
                [[ -z "${seen_pkgs[$p]}" ]] && { seen_pkgs[$p]=1; unique_pkgs+=("$p"); }
            done
            if (( ${#unique_pkgs[@]} == 0 )); then
                printf "  ${C_DIM}No recent upgrades found in history.${C_RESET}\n"
            else
                for cl_pkg in "${unique_pkgs[@]}"; do
                    printf "  ${C_WHITE}── %s ──${C_RESET}\n" "$cl_pkg"
                    local cl_file="${PREFIX}/share/doc/${cl_pkg}/changelog"
                    local cl_gz="${cl_file}.gz"
                    if [[ -f "$cl_gz" ]]; then
                        gunzip -c "$cl_gz" 2>/dev/null | head -15 | sed 's/^/    /'
                    elif [[ -f "$cl_file" ]]; then
                        head -15 "$cl_file" 2>/dev/null | sed 's/^/    /'
                    else
                        printf "  ${C_DIM}    No changelog available.${C_RESET}\n"
                    fi
                    printf "\n"
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /tips ---
        if [[ "$query" == /tips ]]; then
            clear
            local -a tips=(
                "STORAGE|Termux cannot write to /sdcard directly. Run 'termux-setup-storage' first to create ~/storage symlinks to Android shared storage."
                "TMPDIR|Termux has no /tmp like Linux. Use \$PREFIX/tmp (which is \$TMPDIR). It is wiped on every app restart."
                "SHARED|~/storage/shared = /storage/emulated/0 (your phone's internal storage). Files there use fat/emulated fs — cannot run binaries from there (noexec)."
                "PREFIX|Always use \$PREFIX, never hardcoded /usr. Termux prefix is /data/data/com.termux/files/usr — it is compiled into binaries."
                "HOME|\$HOME = /data/data/com.termux/files/home. This is your workspace. Scripts, repos, configs all go here."
                "NO ROOT|Unrooted Termux has NO root access. No systemd, no service management. Use 'termux-wake-lock' to prevent CPU sleep."
                "MIRRORS|Run /mirror in pkgs to switch apt mirrors. Use a mirror near your region for faster downloads."
                "WAKELOCK|'termux-wake-lock' keeps Termux running in background. Remove with 'termux-wake-unlock'."
                "CRON|Install 'cronie' package for cron jobs. Run 'crond' to start the daemon."
                "API|Install 'termux-api' for Android APIs: termux-clipboard-get, termux-notification, termux-vibrate, termux-camera-photo, etc."
                "BOOT|'termux-boot' package runs scripts in ~/.termux/boot/ when phone boots. Needs Termux:Boot app from F-Droid."
                "SSH|'openssh' package for SSH. Run 'sshd' to start server on port 8022. Use 'ssh-keygen' to generate keys."
                "NOEXEC|Never store executables on ~/storage/shared (fat filesystem). Move them to \$HOME or \$PREFIX/bin first."
                "PKG VS APT|'pkg' is a wrapper around 'apt'. Both work. 'pkg' is Termux-specific, 'apt' is the upstream tool."
                "UNINSTALL|'pkg uninstall' removes packages. 'pkg purge' also removes config files. 'pkg autoremove' cleans orphaned deps."
                "F-DROID|Get Termux from F-Droid, NOT Google Play (deprecated). Install Termux:API, Termux:Boot, Termux:Widget from F-Droid too."
                "PERMISSION|Android 11+: may need 'Allow manage all files' in Termux app settings for storage access."
                "SELECTION|Use Tab in pkgs TUI to multi-select packages. Ctrl-A selects all visible. Ctrl-D deselects all."
                "THEMES|Run /theme in pkgs to switch color schemes. Dark, light, minimal, neon, dracula, monokai, solarized available."
                "FAVORITES|Run /fav <pkg> in pkgs to mark packages as favorites. /fav-list shows all favorites."
            )
            local tip_idx=0
            while (( tip_idx < ${#tips[@]} )); do
                clear
                IFS='|' read -r tip_key tip_text <<< "${tips[$tip_idx]}"
                printf "\n  ${C_WHITE}Termux Tips (${C_TEAL}%d/%d${C_WHITE})${C_RESET}\n\n" "$((tip_idx+1))" "${#tips[@]}"
                printf "  ${C_GREEN}%s${C_RESET}\n\n" "$tip_key"
                printf "  ${C_DIM}%s${C_RESET}\n\n" "$tip_text"
                printf "  ${C_DIM}[n]ext  [p]rev  [q]uit${C_RESET} "
                read -k1 tip_choice
                read -r
                case "$tip_choice" in
                    n) ((tip_idx++)) ;;
                    p) ((tip_idx--)); ((tip_idx < 0)) && tip_idx=0 ;;
                    q) break ;;
                    *) ((tip_idx++)) ;;
                esac
            done
            continue
        fi

        # --- /self-update ---
        if [[ "$query" == /self-update ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Checking for updates...${C_RESET}\n"
            local current_ver="1.2.0"
            local latest_ver
            latest_ver=$(curl -sL "$_PKGS_SELF_URL" 2>/dev/null | grep -oP 'pkgs \K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            if [[ -z "$latest_ver" ]]; then
                printf "\n  ${C_MSG_REMOVE}Failed to check for updates.${C_RESET}\n"
            elif [[ "$latest_ver" == "$current_ver" ]]; then
                printf "\n  ${C_MSG_DONE}Already up to date (v%s).${C_RESET}\n" "$current_ver"
            else
                printf "\n  ${C_MSG_INFO}Update available: v%s → v%s${C_RESET}\n" "$current_ver" "$latest_ver"
                printf "\n  ${C_MSG_WARN}Update pkgs? (y/N) ${C_RESET}"
                read -q update_confirm; read -r
                if [[ "$update_confirm" == "y" ]]; then
                    local target="${PREFIX}/bin/pkgs"
                    if curl -fsSL "$_PKGS_SELF_URL" -o "${target}.new" 2>/dev/null; then
                        if head -1 "${target}.new" | grep -q '^#!/'; then
                            chmod +x "${target}.new"
                            mv "${target}" "${target}.bak" 2>/dev/null
                            mv "${target}.new" "${target}"
                            printf "\n  ${C_MSG_DONE}Updated to v%s! Restart pkgs to use.${C_RESET}\n" "$latest_ver"
                        else
                            rm -f "${target}.new"
                            printf "\n  ${C_MSG_REMOVE}Downloaded file invalid. Aborting.${C_RESET}\n"
                        fi
                    else
                        rm -f "${target}.new" 2>/dev/null
                        printf "\n  ${C_MSG_REMOVE}Download failed.${C_RESET}\n"
                    fi
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /search-size ---
        if [[ "$query" == /search-size* ]]; then
            local ss_args="${query#/search-size }"
            [[ "$ss_args" == "/search-size" ]] && ss_args=""
            clear
            if [[ -z "$ss_args" ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /search-size <min_KiB> <max_KiB>${C_RESET}\n"
                printf "  ${C_DIM}Example: /search-size 100 5000${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                continue
            fi
            local ss_min ss_max
            ss_min=$(echo "$ss_args" | awk '{print $1}')
            ss_max=$(echo "$ss_args" | awk '{print $2}')
            if [[ -z "$ss_min" || -z "$ss_max" || ! "$ss_min" =~ ^[0-9]+$ || ! "$ss_max" =~ ^[0-9]+$ ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /search-size <min_KiB> <max_KiB>${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                continue
            fi
            printf "\n  ${C_MSG_INFO}Searching packages %s-%s KiB...${C_RESET}\n\n" "$ss_min" "$ss_max"
            local ss_count=0
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "PACKAGE" "SIZE" "STATUS"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "------------------------------" "------------" "------"
            dpkg-query -W -f='${Package}\t${Installed-Size}\n' 2>/dev/null | while IFS=$'\t' read -r pkg size; do
                [[ -z "$size" || "$size" == "*" ]] && continue
                if (( size >= ss_min && size <= ss_max )); then
                    local status="${C_GREEN}installed${C_RESET}"
                    local sz_display
                    sz_display=$(_pkgs_format_size "$size")
                    printf "  %-30s %-12b %b\n" "$pkg" "$sz_display" "$status"
                    ((ss_count++))
                fi
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /pkg-history ---
        if [[ "$query" == /pkg-history* ]]; then
            local ph_pkg="${query#/pkg-history }"
            [[ "$ph_pkg" == "/pkg-history" ]] && ph_pkg=""
            clear
            if [[ -z "$ph_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                ph_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" History for> " --height=50% --reverse)
                ph_pkg=$(echo "$ph_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$ph_pkg" ]]; then
                printf "\n  ${C_WHITE}History for %s:${C_RESET}\n\n" "$ph_pkg"
                local found=0
                for hist_file in $(find "$_PKGS_HISTORY_DIR" -name "*.log" 2>/dev/null | sort -r); do
                    while IFS='|' read -r ts action pkg; do
                        if [[ "$pkg" == "$ph_pkg" ]]; then
                            printf "  ${C_DIM}%s${C_RESET}  %b%s%b\n" "$ts" "$C_MSG_DONE" "$action" "$C_RESET"
                            ((found++))
                        fi
                    done < "$hist_file"
                done
                if (( found == 0 )); then
                    printf "  ${C_DIM}No history entries found for %s.${C_RESET}\n" "$ph_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /depends-chain ---
        if [[ "$query" == /depends-chain* ]]; then
            local dc_args="${query#/depends-chain }"
            [[ "$dc_args" == "/depends-chain" ]] && dc_args=""
            clear
            local dc_a dc_b
            dc_a=$(echo "$dc_args" | awk '{print $1}')
            dc_b=$(echo "$dc_args" | awk '{print $2}')
            if [[ -z "$dc_a" || -z "$dc_b" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                printf "\n  ${C_MSG_INFO}Select first package:${C_RESET}\n"
                dc_a=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Package A> " --height=50% --reverse)
                dc_a=$(echo "$dc_a" | awk -F'|' '{print $2}' | xargs)
                if [[ -z "$dc_a" ]]; then
                    printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                    read -r
                    continue
                fi
                printf "\n  ${C_MSG_INFO}Select second package:${C_RESET}\n"
                dc_b=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Package B> " --height=50% --reverse)
                dc_b=$(echo "$dc_b" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$dc_a" && -n "$dc_b" ]]; then
                printf "\n  ${C_WHITE}Dependency chain: %s -> %s${C_RESET}\n\n" "$dc_a" "$dc_b"
                if apt-cache depends "$dc_a" 2>/dev/null | grep -q "$dc_b"; then
                    printf "  ${C_GREEN}%s directly depends on %s${C_RESET}\n" "$dc_a" "$dc_b"
                else
                    local -a queue=("$dc_a")
                    local -A parent_map
                    local found_chain=0
                    parent_map["$dc_a"]=""
                    while (( ${#queue[@]} > 0 && found_chain == 0 )); do
                        local cur="${queue[1]}"
                        queue=("${queue[@]:1}")
                        local deps
                        deps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$cur" 2>/dev/null | grep "Depends:" | sed 's/.*Depends: //' | tr -d '<>' | awk '{print $1}')
                        for d in $deps; do
                            [[ -n "${parent_map[$d]}" ]] && continue
                            parent_map["$d"]="$cur"
                            if [[ "$d" == "$dc_b" ]]; then
                                found_chain=1
                                break
                            fi
                            queue+=("$d")
                        done
                    done
                    if (( found_chain )); then
                        printf "  ${C_GREEN}Chain found:${C_RESET}\n"
                        local chain_node="$dc_b"
                        local -a chain_rev=("$chain_node")
                        while [[ -n "${parent_map[$chain_node]}" ]]; do
                            chain_node="${parent_map[$chain_node]}"
                            chain_rev=("$chain_node" "${chain_rev[@]}")
                        done
                        printf "    ${C_TEAL}%s${C_RESET}" "${chain_rev[0]}"
                        for (( ci=1; ci<${#chain_rev[@]}; ci++ )); do
                            printf " -> ${C_TEAL}%s${C_RESET}" "${chain_rev[$ci]}"
                        done
                        printf "\n"
                    else
                        printf "  ${C_DIM}No dependency chain found between %s and %s.${C_RESET}\n" "$dc_a" "$dc_b"
                    fi
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /broken ---
        if [[ "$query" == /broken ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Checking for broken packages...${C_RESET}\n\n"
            local broken_count=0
            dpkg --audit 2>/dev/null | while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                printf "  ${C_RED}✗ %s${C_RESET}\n" "$line"
                ((broken_count++))
            done
            local -a held_pkgs
            held_pkgs=($(apt-mark showhold 2>/dev/null))
            if (( ${#held_pkgs[@]} > 0 )); then
                printf "\n  ${C_MSG_INFO}Held packages (%d):${C_RESET}\n" "${#held_pkgs[@]}"
                for hp in "${held_pkgs[@]}"; do
                    printf "    ${C_AMBER}HOLD %s${C_RESET}\n" "$hp"
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /conflicts-with ---
        if [[ "$query" == /conflicts-with* ]]; then
            local cw_pkg="${query#/conflicts-with }"
            [[ "$cw_pkg" == "/conflicts-with" ]] && cw_pkg=""
            clear
            if [[ -z "$cw_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                cw_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Conflicts for> " --height=50% --reverse)
                cw_pkg=$(echo "$cw_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$cw_pkg" ]]; then
                printf "\n  ${C_WHITE}Conflicts for %s:${C_RESET}\n\n" "$cw_pkg"
                local cw_found=0
                while IFS= read -r line; do
                    local cdep
                    cdep=$(echo "$line" | sed 's/.*Conflicts: //' | tr -d '<>' | awk '{print $1}')
                    [[ -z "$cdep" ]] && continue
                    if dpkg -s -- "$cdep" 2>/dev/null | grep -q '^Status: install ok installed'; then
                        printf "  ${C_RED}X %s${C_RESET} ${C_MSG_REMOVE}(INSTALLED - CONFLICT!)${C_RESET}\n" "$cdep"
                        ((cw_found++))
                    else
                        printf "  ${C_DIM}  %s${C_RESET}\n" "$cdep"
                    fi
                done < <(apt-cache depends "$cw_pkg" 2>/dev/null | grep -i "Conflicts")
                if (( cw_found > 0 )); then
                    printf "\n  ${C_MSG_REMOVE}WARNING: %d conflicting packages installed!${C_RESET}\n" "$cw_found"
                else
                    printf "\n  ${C_MSG_DONE}No active conflicts.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /provides ---
        if [[ "$query" == /provides* ]]; then
            local pv_pkg="${query#/provides }"
            [[ "$pv_pkg" == "/provides" ]] && pv_pkg=""
            clear
            if [[ -z "$pv_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                pv_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Provides for> " --height=50% --reverse)
                pv_pkg=$(echo "$pv_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$pv_pkg" ]]; then
                printf "\n  ${C_WHITE}Virtual packages provided by %s:${C_RESET}\n\n" "$pv_pkg"
                local pv_found=0
                while IFS= read -r line; do
                    local pv
                    pv=$(echo "$line" | sed 's/.*Provides: //' | tr -d '<>' | awk '{print $1}')
                    [[ -z "$pv" ]] && continue
                    printf "  ${C_GREEN}-> %s${C_RESET}\n" "$pv"
                    ((pv_found++))
                done < <(apt-cache depends "$pv_pkg" 2>/dev/null | grep -i "Provides")
                if (( pv_found == 0 )); then
                    printf "  ${C_DIM}No virtual packages provided.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /manually-installed ---
        if [[ "$query" == /manually-installed ]]; then
            clear
            printf "\n  ${C_WHITE}Manually Installed Packages${C_RESET}\n\n"
            local -a manual_pkgs=()
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                manual_pkgs+=("$pkg")
            done < <(apt-mark showmanual 2>/dev/null)
            printf "  ${C_MSG_DONE}%d packages installed manually${C_RESET}\n\n" "${#manual_pkgs[@]}"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "PACKAGE" "SIZE" "SECTION"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "------------------------------" "------------" "-------"
            for pkg in "${manual_pkgs[@]}"; do
                local size
                size=$(dpkg-query -W -f='${Installed-Size}' -- "$pkg" 2>/dev/null)
                local section
                section=$(apt-cache show "$pkg" 2>/dev/null | sed -n 's/^Section: //p' | head -1)
                printf "  ${C_GREEN}%-30s${C_RESET} %-12s %s\n" "$pkg" "$(_pkgs_format_size "${size:-0}")" "${section:---}"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /auto-installed ---
        if [[ "$query" == /auto-installed ]]; then
            clear
            printf "\n  ${C_WHITE}Auto-Installed Packages${C_RESET}\n\n"
            local -a auto_pkgs=()
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                auto_pkgs+=("$pkg")
            done < <(apt-mark showauto 2>/dev/null)
            printf "  ${C_MSG_DONE}%d packages auto-installed${C_RESET}\n\n" "${#auto_pkgs[@]}"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "PACKAGE" "SIZE" "PARENT"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "------------------------------" "------------" "------"
            local shown=0
            for pkg in "${auto_pkgs[@]}"; do
                ((shown++))
                (( shown > 100 )) && { printf "\n  ${C_DIM}... and %d more${C_RESET}\n" "$((${#auto_pkgs[@]} - 100))"; break; }
                local size
                size=$(dpkg-query -W -f='${Installed-Size}' -- "$pkg" 2>/dev/null)
                local parent
                parent=$(apt-cache rdepends --installed "$pkg" 2>/dev/null | tail -n +2 | head -1)
                printf "  %-30s %-12s ${C_DIM}%s${C_RESET}\n" "$pkg" "$(_pkgs_format_size "${size:-0}")" "${parent:---}"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /upgrade-plan ---
        if [[ "$query" == /upgrade-plan ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Simulating upgrade...${C_RESET}\n\n"
            local plan_out
            plan_out=$("${PKG_MGR}" upgrade --dry-run 2>&1)
            echo "$plan_out" | head -60
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /pkg-ages ---
        if [[ "$query" == /pkg-ages ]]; then
            clear
            printf "\n  ${C_WHITE}Package Ages${C_RESET}\n\n"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "PACKAGE" "SIZE" "AGE"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "------------------------------" "------------" "----------"
            dpkg-query -W -f='${Package}\t${Installed-Size}\t${db-fsys:Last-Modified}\n' 2>/dev/null | sort -t$'\t' -k3 -n | while IFS=$'\t' read -r pkg size ts; do
                [[ -z "$pkg" || -z "$ts" || "$ts" == "*" ]] && continue
                [[ ! "$ts" =~ ^[0-9]+$ ]] && continue
                local now_s days age_str
                now_s=$(date +%s)
                days=$(( (now_s - ts) / 86400 ))
                if (( days > 365 )); then
                    age_str="$((days / 365))y $((days % 365))d"
                elif (( days > 30 )); then
                    age_str="$((days / 30))mo $((days % 30))d"
                else
                    age_str="${days}d"
                fi
                printf "  %-30s %-12s ${C_DIM}%s${C_RESET}\n" "$pkg" "$(_pkgs_format_size "${size:-0}")" "$age_str"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /unused-libs ---
        if [[ "$query" == /unused-libs ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Scanning for orphaned libraries...${C_RESET}\n\n"
            local ul_count=0 ul_size=0
            while IFS= read -r libfile; do
                [[ -z "$libfile" ]] && continue
                if ! dpkg -S "$libfile" &>/dev/null; then
                    local lsize
                    lsize=$(du -k "$libfile" 2>/dev/null | awk '{print $1}')
                    ul_size=$((ul_size + lsize))
                    ((ul_count++))
                    (( ul_count > 50 )) && break
                    printf "  ${C_DIM}%-50s${C_RESET} %-12s ${C_RED}orphaned${C_RESET}\n" "${libfile:0:50}" "$(_pkgs_format_size "${lsize:-0}")"
                fi
            done < <(find "${PREFIX}/lib" -name "*.so" -o -name "*.so.*" 2>/dev/null | head -200)
            if (( ul_count == 0 )); then
                printf "  ${C_MSG_DONE}No orphaned libraries found.${C_RESET}\n"
            else
                printf "\n  ${C_MSG_WARN}%d orphaned libs, ~%s${C_RESET}\n" "$ul_count" "$(_pkgs_format_size "$ul_size")"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /maintainer ---
        if [[ "$query" == /maintainer* ]]; then
            local mt_query="${query#/maintainer }"
            [[ "$mt_query" == "/maintainer" ]] && mt_query=""
            clear
            if [[ -z "$mt_query" ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /maintainer <name or email>${C_RESET}\n"
            else
                printf "\n  ${C_MSG_INFO}Searching for maintainer: %s...${C_RESET}\n\n" "$mt_query"
                printf "  ${C_DIM}%-30s %s${C_RESET}\n" "PACKAGE" "MAINTAINER"
                printf "  ${C_DIM}%-30s %s${C_RESET}\n" "------------------------------" "----------------------------------------"
                apt-cache search "" 2>/dev/null | awk '{print $1}' | while read -r pkg; do
                    local maint
                    maint=$(apt-cache show "$pkg" 2>/dev/null | sed -n 's/^Maintainer: //p' | head -1)
                    if [[ "$maint" == *"$mt_query"* ]]; then
                        printf "  ${C_GREEN}%-30s${C_RESET} %s\n" "$pkg" "${maint:0:50}"
                    fi
                done | head -100
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /log-search ---
        if [[ "$query" == /log-search* ]]; then
            local ls_query="${query#/log-search }"
            [[ "$ls_query" == "/log-search" ]] && ls_query=""
            clear
            if [[ -z "$ls_query" ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /log-search <text>${C_RESET}\n"
            else
                printf "\n  ${C_MSG_INFO}Searching dpkg logs for: %s...${C_RESET}\n\n" "$ls_query"
                local apt_log="${PREFIX}/var/log/apt/history.log"
                if [[ -f "$apt_log" ]]; then
                    grep -B1 -A1 -i "$ls_query" "$apt_log" 2>/dev/null | head -80 | sed 's/^/  /'
                else
                    printf "  ${C_DIM}No apt history log found.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /mirror-backup ---
        if [[ "$query" == /mirror-backup ]]; then
            clear
            local src_list="${PREFIX}/etc/apt/sources.list"
            local backup_dir="${_PKGS_CONFIG_DIR}/mirror-backups"
            mkdir -p "$backup_dir" 2>/dev/null
            local -a mb_choices=("backup" "restore" "list")
            local mb_choice
            mb_choice=$(printf '%s\n' "${mb_choices[@]}" | fzf --prompt=" Mirror backup> " --height=30% --reverse)
            case "$mb_choice" in
                backup)
                    if [[ -f "$src_list" ]]; then
                        local ts
                        ts=$(date +%Y%m%d_%H%M%S)
                        cp "$src_list" "${backup_dir}/sources.list.${ts}"
                        printf "\n  ${C_MSG_DONE}Backup saved: sources.list.%s${C_RESET}\n" "$ts"
                    fi
                    ;;
                restore)
                    local -a backups=($(ls -t "${backup_dir}"/sources.list.* 2>/dev/null))
                    if (( ${#backups[@]} == 0 )); then
                        printf "\n  ${C_MSG_WARN}No backups found.${C_RESET}\n"
                    else
                        local chosen_bak
                        chosen_bak=$(printf '%s\n' "${backups[@]}" | fzf --prompt=" Restore> " --height=50% --reverse)
                        if [[ -n "$chosen_bak" ]]; then
                            cp "$chosen_bak" "$src_list"
                            printf "\n  ${C_MSG_DONE}Restored from: %s${C_RESET}\n" "$(basename "$chosen_bak")"
                        fi
                    fi
                    ;;
                list)
                    local -a backups=($(ls -t "${backup_dir}"/sources.list.* 2>/dev/null))
                    if (( ${#backups[@]} == 0 )); then
                        printf "\n  ${C_MSG_WARN}No backups found.${C_RESET}\n"
                    else
                        printf "\n  ${C_WHITE}Mirror backups:${C_RESET}\n\n"
                        for bak in "${backups[@]}"; do
                            printf "  ${C_DIM}%s${C_RESET}\n" "$(basename "$bak")"
                        done
                    fi
                    ;;
            esac
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /size-histogram ---
        if [[ "$query" == /size-histogram ]]; then
            clear
            printf "\n  ${C_WHITE}Package Size Distribution${C_RESET}\n\n"
            local -a buckets=(0 0 0 0 0 0 0 0 0 0)
            local -a labels=("0-10K" "10-50K" "50-100K" "100-500K" "500K-1M" "1-5M" "5-10M" "10-50M" "50-100M" "100M+")
            dpkg-query -W -f='${Installed-Size}\n' 2>/dev/null | while IFS= read -r size; do
                [[ -z "$size" || "$size" == "*" || ! "$size" =~ ^[0-9]+$ ]] && continue
                if (( size < 10 )); then ((buckets[1]++))
                elif (( size < 50 )); then ((buckets[2]++))
                elif (( size < 100 )); then ((buckets[3]++))
                elif (( size < 500 )); then ((buckets[4]++))
                elif (( size < 1024 )); then ((buckets[5]++))
                elif (( size < 5120 )); then ((buckets[6]++))
                elif (( size < 10240 )); then ((buckets[7]++))
                elif (( size < 51200 )); then ((buckets[8]++))
                elif (( size < 102400 )); then ((buckets[9]++))
                else ((buckets[10]++))
                fi
            done
            local max_bucket=0
            for b in "${buckets[@]}"; do
                (( b > max_bucket )) && max_bucket=$b
            done
            for i in {1..10}; do
                local count="${buckets[$i]}"
                local bar_len=0
                if (( max_bucket > 0 && count > 0 )); then
                    bar_len=$(( (count * 40) / max_bucket ))
                    (( bar_len < 1 )) && bar_len=1
                fi
                local bar=""
                for (( j=0; j<bar_len; j++ )); do bar="${bar}#"; done
                printf "  ${C_DIM}%-10s${C_RESET} ${C_GREEN}%-40s${C_RESET} %d\n" "${labels[$((i-1))]}" "$bar" "$count"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /deptree ---
        if [[ "$query" == /deptree* ]]; then
            local dt_pkg="${query#/deptree }"
            [[ "$dt_pkg" == "/deptree" ]] && dt_pkg=""
            clear
            if [[ -z "$dt_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                dt_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Dep tree for> " --height=50% --reverse)
                dt_pkg=$(echo "$dt_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$dt_pkg" ]]; then
                printf "\n  ${C_WHITE}Dependency tree: %s${C_RESET}\n\n" "$dt_pkg"
                _pkgs_draw_tree() {
                    local pkg="$1" prefix="$2" depth="$3"
                    (( depth > 8 )) && { printf "%s${C_DIM}... (max depth)${C_RESET}\n" "$prefix"; return; }
                    local deps
                    deps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$pkg" 2>/dev/null | grep "Depends:" | sed 's/.*Depends: //' | tr -d '<>' | awk '{print $1}')
                    local first=1
                    for d in $deps; do
                        if (( first )); then
                            printf "%s├── ${C_TEAL}%s${C_RESET}\n" "$prefix" "$d"
                            first=0
                        else
                            printf "%s├── ${C_TEAL}%s${C_RESET}\n" "$prefix" "$d"
                        fi
                        _pkgs_draw_tree "$d" "${prefix}│   " $((depth+1))
                    done
                }
                printf "  ${C_GREEN}%s${C_RESET}\n" "$dt_pkg"
                _pkgs_draw_tree "$dt_pkg" "  " 0
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /reverse-tree ---
        if [[ "$query" == /reverse-tree* ]]; then
            local rt_pkg="${query#/reverse-tree }"
            [[ "$rt_pkg" == "/reverse-tree" ]] && rt_pkg=""
            clear
            if [[ -z "$rt_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                rt_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Reverse tree for> " --height=50% --reverse)
                rt_pkg=$(echo "$rt_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$rt_pkg" ]]; then
                printf "\n  ${C_WHITE}Reverse dependency tree: %s${C_RESET}\n\n" "$rt_pkg"
                _pkgs_draw_rev_tree() {
                    local pkg="$1" prefix="$2" depth="$3"
                    (( depth > 8 )) && { printf "%s${C_DIM}... (max depth)${C_RESET}\n" "$prefix"; return; }
                    local rdeps
                    rdeps=$(apt-cache rdepends --installed "$pkg" 2>/dev/null | tail -n +2 | grep -v "^$")
                    local first=1
                    for d in $rdeps; do
                        [[ -z "$d" ]] && continue
                        local marker=""
                        dpkg -s -- "$d" 2>/dev/null | grep -q '^Status: install ok installed' && marker="${C_GREEN}*" || marker="${C_DIM}-"
                        printf "%s├── %b ${C_TEAL}%s${C_RESET}\n" "$prefix" "$marker" "$d"
                        _pkgs_draw_rev_tree "$d" "${prefix}│   " $((depth+1))
                    done
                }
                printf "  ${C_GREEN}%s${C_RESET} ${C_DIM}(*=installed)${C_RESET}\n" "$rt_pkg"
                _pkgs_draw_rev_tree "$rt_pkg" "  " 0
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /upgrade-size ---
        if [[ "$query" == /upgrade-size ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Calculating upgrade download size...${C_RESET}\n\n"
            local us_out
            us_out=$(apt-get upgrade --dry-run 2>&1)
            local us_total
            us_total=$(echo "$us_out" | grep -oP 'Need to get \K[0-9.]+[KMGT]?B' | head -1)
            local us_new us_upgrade us_remove
            us_new=$(echo "$us_out" | grep -oP '\d+ (?:newly installed)' | grep -oP '^\d+')
            us_upgrade=$(echo "$us_out" | grep -oP '\d+ upgraded' | grep -oP '^\d+')
            us_remove=$(echo "$us_out" | grep -oP '\d+ to remove' | grep -oP '^\d+')
            printf "  ${C_WHITE}Upgrade Summary:${C_RESET}\n\n"
            printf "  ${C_MSG_DONE}Download size:${C_RESET}   %s\n" "${us_total:-unknown}"
            printf "  ${C_GREEN}Upgrades:${C_RESET}       %s packages\n" "${us_upgrade:-0}"
            printf "  ${C_TEAL}New installs:${C_RESET}   %s packages\n" "${us_new:-0}"
            printf "  ${C_RED}Removals:${C_RESET}       %s packages\n" "${us_remove:-0}"
            printf "\n  ${C_DIM}Full output:${C_RESET}\n\n"
            echo "$us_out" | head -30 | sed 's/^/    /'
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /download ---
        if [[ "$query" == /download* ]]; then
            local dl_pkg="${query#/download }"
            [[ "$dl_pkg" == "/download" ]] && dl_pkg=""
            clear
            if [[ -z "$dl_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                dl_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Download> " --height=50% --reverse)
                dl_pkg=$(echo "$dl_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$dl_pkg" ]]; then
                printf "\n  ${C_MSG_INFO}Downloading %s...${C_RESET}\n\n" "$dl_pkg"
                local dl_dir="${PREFIX}/tmp/pkgs-dl"
                mkdir -p "$dl_dir" 2>/dev/null
                apt-get download --target-dir="$dl_dir" "$dl_pkg" 2>&1 | sed 's/^/  /'
                if ls "$dl_dir"/${dl_pkg}*.deb 2>/dev/null | head -1 > /dev/null; then
                    printf "\n  ${C_MSG_DONE}Downloaded to:${C_RESET} %s\n" "$dl_dir"
                    ls -lh "$dl_dir"/${dl_pkg}*.deb 2>/dev/null | sed 's/^/  /'
                else
                    printf "\n  ${C_MSG_REMOVE}Download failed.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /verify ---
        if [[ "$query" == /verify* ]]; then
            local vr_pkg="${query#/verify }"
            [[ "$vr_pkg" == "/verify" ]] && vr_pkg=""
            clear
            if [[ -z "$vr_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                vr_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Verify> " --height=50% --reverse)
                vr_pkg=$(echo "$vr_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$vr_pkg" ]]; then
                printf "\n  ${C_MSG_INFO}Verifying %s...${C_RESET}\n\n" "$vr_pkg"
                local vr_ok=0 vr_fail=0
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    if dpkg --verify "$vr_pkg" 2>/dev/null | grep -q "$f"; then
                        printf "  ${C_RED}✗ %s${C_RESET}\n" "$f"
                        ((vr_fail++))
                    else
                        printf "  ${C_GREEN}✓ %s${C_RESET}\n" "$f"
                        ((vr_ok++))
                    fi
                done < <(dpkg -L "$vr_pkg" 2>/dev/null | grep -E "^/" | head -50)
                printf "\n  ${C_MSG_DONE}%d OK, %d failed${C_RESET}\n" "$vr_ok" "$vr_fail"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /mirror-latency ---
        if [[ "$query" == /mirror-latency ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Testing mirror latency (top 10)...${C_RESET}\n\n"
            local -a mirrors_test=(
                "packages.termux.dev|Official"
                "mirrors.tuna.tsinghua.edu.cn|Tsinghua"
                "ftp.fau.de|FAU Germany"
                "mirror.fcix.net|FCIX USA"
                "mirror.freedif.org|karibu SG"
                "mirrors.cbrx.io|CyberRex JP"
                "mirror.meowsmp.net|MeowIce VN"
                "mirrors.medzik.dev|M3DZIK DE"
                "mirror.leitecastro.com|Leite PT"
                "mirror.accum.se|ACCUM SE"
            )
            printf "  ${C_DIM}%-35s %s${C_RESET}\n" "MIRROR" "LATENCY"
            printf "  ${C_DIM}%-35s %s${C_RESET}\n" "-----------------------------------" "--------"
            for entry in "${mirrors_test[@]}"; do
                IFS='|' read -r murl mname <<< "$entry"
                local start_ms end_ms elapsed
                start_ms=$(($(date +%s%N)/1000000))
                curl -sI --connect-timeout 3 "https://${murl}/dists/stable/Release" >/dev/null 2>&1
                end_ms=$(($(date +%s%N)/1000000))
                elapsed=$((end_ms - start_ms))
                if (( elapsed < 200 )); then
                    printf "  %-35s ${C_GREEN}%dms${C_RESET}\n" "$mname ($murl)" "$elapsed"
                elif (( elapsed < 1000 )); then
                    printf "  %-35s ${C_AMBER}%dms${C_RESET}\n" "$mname ($murl)" "$elapsed"
                else
                    printf "  %-35s ${C_RED}%dms${C_RESET}\n" "$mname ($murl)" "$elapsed"
                fi
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /mirror-bandwidth ---
        if [[ "$query" == /mirror-bandwidth ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Testing mirror bandwidth (downloading Release file)...${C_RESET}\n\n"
            local -a mirrors_bw=(
                "packages.termux.dev|Official"
                "mirrors.tuna.tsinghua.edu.cn|Tsinghua"
                "ftp.fau.de|FAU Germany"
                "mirror.fcix.net|FCIX USA"
                "mirror.freedif.org|karibu SG"
                "mirrors.cbrx.io|CyberRex JP"
                "mirror.medzik.dev|M3DZIK DE"
                "mirror.leitecastro.com|Leite PT"
            )
            printf "  ${C_DIM}%-25s %-12s %s${C_RESET}\n" "MIRROR" "SPEED" "TIME"
            printf "  ${C_DIM}%-25s %-12s %s${C_RESET}\n" "-------------------------" "------------" "------"
            for entry in "${mirrors_bw[@]}"; do
                IFS='|' read -r murl mname <<< "$entry"
                local tmp_bw="/tmp/pkgs_bw_$$"
                local start_t end_t elapsed_s speed_bps
                start_t=$(date +%s%N)
                curl -sL --connect-timeout 5 --max-time 10 "https://${murl}/dists/stable/Release" -o "$tmp_bw" 2>/dev/null
                end_t=$(date +%s%N)
                elapsed_s=$(( (end_t - start_t) / 1000000 ))
                if [[ -f "$tmp_bw" && -s "$tmp_bw" ]]; then
                    local fsize
                    fsize=$(wc -c < "$tmp_bw")
                    if (( elapsed_s > 0 )); then
                        speed_bps=$(( fsize * 1000 / elapsed_s ))
                        local speed_display
                        if (( speed_bps > 1048576 )); then
                            speed_display="$((speed_bps / 1048576)) MB/s"
                        elif (( speed_bps > 1024 )); then
                            speed_display="$((speed_bps / 1024)) KB/s"
                        else
                            speed_display="${speed_bps} B/s"
                        fi
                        if (( speed_bps > 1048576 )); then
                            printf "  %-25s ${C_GREEN}%-12s${C_RESET} %dms\n" "$mname" "$speed_display" "$elapsed_s"
                        elif (( speed_bps > 102400 )); then
                            printf "  %-25s ${C_AMBER}%-12s${C_RESET} %dms\n" "$mname" "$speed_display" "$elapsed_s"
                        else
                            printf "  %-25s ${C_RED}%-12s${C_RESET} %dms\n" "$mname" "$speed_display" "$elapsed_s"
                        fi
                    fi
                else
                    printf "  %-25s ${C_RED}%-12s${C_RESET}\n" "$mname" "FAILED"
                fi
                rm -f "$tmp_bw" 2>/dev/null
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /pkg-changes ---
        if [[ "$query" == /pkg-changes ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Last apt upgrade changes:${C_RESET}\n\n"
            local apt_log="${PREFIX}/var/log/apt/history.log"
            if [[ -f "$apt_log" ]]; then
                tail -200 "$apt_log" | grep -B5 -A5 "Upgraded:" | head -100 | sed 's/^/  /'
            else
                printf "  ${C_DIM}No apt history log found.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /pkg-recommendations ---
        if [[ "$query" == /pkg-recommendations* ]]; then
            local pr_pkg="${query#/pkg-recommendations }"
            [[ "$pr_pkg" == "/pkg-recommendations" ]] && pr_pkg=""
            clear
            if [[ -z "$pr_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                pr_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Who recommends> " --height=50% --reverse)
                pr_pkg=$(echo "$pr_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$pr_pkg" ]]; then
                printf "\n  ${C_WHITE}Packages that recommend %s:${C_RESET}\n\n" "$pr_pkg"
                local pr_found=0
                apt-cache rdepends "$pr_pkg" 2>/dev/null | tail -n +2 | while IFS= read -r rdep; do
                    [[ -z "$rdep" ]] && continue
                    local recommends
                    recommends=$(apt-cache depends "$rdep" 2>/dev/null | grep -A1 "Recommends:" | grep "$pr_pkg")
                    if [[ -n "$recommends" ]]; then
                        printf "  ${C_GREEN}%s${C_RESET}\n" "$rdep"
                        ((pr_found++))
                    fi
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /pkg-suggests ---
        if [[ "$query" == /pkg-suggests* ]]; then
            local ps_pkg="${query#/pkg-suggests }"
            [[ "$ps_pkg" == "/pkg-suggests" ]] && ps_pkg=""
            clear
            if [[ -z "$ps_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                ps_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Who suggests> " --height=50% --reverse)
                ps_pkg=$(echo "$ps_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$ps_pkg" ]]; then
                printf "\n  ${C_WHITE}Packages that suggest %s:${C_RESET}\n\n" "$ps_pkg"
                apt-cache rdepends "$ps_pkg" 2>/dev/null | tail -n +2 | while IFS= read -r rdep; do
                    [[ -z "$rdep" ]] && continue
                    local suggests
                    suggests=$(apt-cache depends "$rdep" 2>/dev/null | grep -A1 "Suggests:" | grep "$ps_pkg")
                    if [[ -n "$suggests" ]]; then
                        printf "  ${C_AMBER}%s${C_RESET}\n" "$rdep"
                    fi
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /pkg-breaks ---
        if [[ "$query" == /pkg-breaks* ]]; then
            local pb_pkg="${query#/pkg-breaks }"
            [[ "$pb_pkg" == "/pkg-breaks" ]] && pb_pkg=""
            clear
            if [[ -z "$pb_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                pb_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" What breaks> " --height=50% --reverse)
                pb_pkg=$(echo "$pb_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$pb_pkg" ]]; then
                printf "\n  ${C_WHITE}Packages that break with %s:${C_RESET}\n\n" "$pb_pkg"
                while IFS= read -r line; do
                    local bdep
                    bdep=$(echo "$line" | sed 's/.*Breaks: //' | tr -d '<>' | awk '{print $1}')
                    [[ -z "$bdep" ]] && continue
                    if dpkg -s -- "$bdep" 2>/dev/null | grep -q '^Status: install ok installed'; then
                        printf "  ${C_RED}X %s${C_RESET} ${C_MSG_REMOVE}(INSTALLED!)${C_RESET}\n" "$bdep"
                    else
                        printf "  ${C_DIM}  %s${C_RESET}\n" "$bdep"
                    fi
                done < <(apt-cache depends "$pb_pkg" 2>/dev/null | grep -i "Breaks")
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /pkg-replaces ---
        if [[ "$query" == /pkg-replaces* ]]; then
            local prr_pkg="${query#/pkg-replaces }"
            [[ "$prr_pkg" == "/pkg-replaces" ]] && prr_pkg=""
            clear
            if [[ -z "$prr_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                prr_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" What replaces> " --height=50% --reverse)
                prr_pkg=$(echo "$prr_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$prr_pkg" ]]; then
                printf "\n  ${C_WHITE}Packages that %s replaces:${C_RESET}\n\n" "$prr_pkg"
                while IFS= read -r line; do
                    local rdep
                    rdep=$(echo "$line" | sed 's/.*Replaces: //' | tr -d '<>' | awk '{print $1}')
                    [[ -z "$rdep" ]] && continue
                    if dpkg -s -- "$rdep" 2>/dev/null | grep -q '^Status: install ok installed'; then
                        printf "  ${C_GREEN}-> %s${C_RESET} ${C_MSG_DONE}(installed, will be replaced)${C_RESET}\n" "$rdep"
                    else
                        printf "  ${C_DIM}  %s${C_RESET}\n" "$rdep"
                    fi
                done < <(apt-cache depends "$prr_pkg" 2>/dev/null | grep -i "Replaces")
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /owner ---
        if [[ "$query" == /owner* ]]; then
            local ow_file="${query#/owner }"
            [[ "$ow_file" == "/owner" ]] && ow_file=""
            clear
            if [[ -z "$ow_file" ]]; then
                printf "  ${C_MSG_INFO}Enter file path to query:${C_RESET} "
                read -r ow_file
            fi
            if [[ -n "$ow_file" ]]; then
                printf "\n  ${C_WHITE}Who owns %s?${C_RESET}\n\n" "$ow_file"
                local ow_result
                ow_result=$(dpkg -S "$ow_file" 2>&1)
                if [[ $? -eq 0 ]]; then
                    echo "$ow_result" | while IFS=: read -r owner files; do
                        printf "  ${C_GREEN}%s${C_RESET}\n" "$owner"
                        echo "$files" | tr ',' '\n' | sed 's/^ *//' | while IFS= read -r f; do
                            printf "    ${C_DIM}%s${C_RESET}\n" "$f"
                        done
                    done
                else
                    printf "  ${C_MSG_REMOVE}No package owns this file.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /removed ---
        if [[ "$query" == /removed ]]; then
            clear
            printf "\n  ${C_WHITE}Packages removed in last upgrade:${C_RESET}\n\n"
            local apt_log="${PREFIX}/var/log/apt/history.log"
            if [[ -f "$apt_log" ]]; then
                local found_removed=0
                while IFS= read -r line; do
                    if echo "$line" | grep -q "remove "; then
                        local rpkg
                        rpkg=$(echo "$line" | sed 's/.*remove //' | awk '{print $1}')
                        printf "  ${C_RED}- %s${C_RESET}\n" "$rpkg"
                        found_removed=1
                    fi
                done < <(tac "$apt_log" | head -500)
                (( found_removed == 0 )) && printf "  ${C_DIM}No packages removed recently.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /new-pkgs ---
        if [[ "$query" == /new-pkgs ]]; then
            clear
            printf "\n  ${C_WHITE}Packages installed this week:${C_RESET}\n\n"
            local week_ago
            week_ago=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d 2>/dev/null)
            local dpkg_log="${PREFIX}/var/log/dpkg.log"
            if [[ -f "$dpkg_log" ]]; then
                local found_new=0
                while IFS= read -r line; do
                    local ndate npkg
                    ndate=$(echo "$line" | awk '{print $1}')
                    npkg=$(echo "$line" | awk '{print $4}')
                    if [[ "$ndate" > "$week_ago" || "$ndate" == "$week_ago" ]]; then
                        printf "  ${C_GREEN}+ %s${C_RESET} ${C_DIM}(%s)${C_RESET}\n" "$npkg" "$ndate"
                        found_new=1
                    fi
                done < <(grep " install " "$dpkg_log" 2>/dev/null)
                (( found_new == 0 )) && printf "  ${C_DIM}No new packages this week.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /same-size ---
        if [[ "$query" == /same-size ]]; then
            clear
            printf "\n  ${C_WHITE}Packages with identical installed size (possible duplicates):${C_RESET}\n\n"
            dpkg-query -W -f='${Package}\t${Installed-Size}\n' 2>/dev/null | sort -t$'\t' -k2 -n | awk -F'\t' '
                $2 != "" && $2 != "*" {
                    if ($2 == prev_size && $2 != 0) {
                        if (first == 1) printf "  ${C_DIM}[%s KiB]${C_RESET} %s\n", prev_size, prev_pkg
                        printf "  ${C_DIM}[%s KiB]${C_RESET} %s\n", $2, $1
                        first = 1
                    } else {
                        first = 0
                    }
                    prev_size = $2
                    prev_pkg = $1
                }
            '
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /depends-on-list ---
        if [[ "$query" == /depends-on-list* ]]; then
            local dol_list="${query#/depends-on-list }"
            [[ "$dol_list" == "/depends-on-list" ]] && dol_list=""
            clear
            if [[ -z "$dol_list" ]]; then
                printf "  ${C_MSG_INFO}Enter packages (space-separated):${C_RESET} "
                read -r dol_list
            fi
            if [[ -n "$dol_list" ]]; then
                printf "\n  ${C_WHITE}Shared dependencies of: %s${C_RESET}\n\n" "$dol_list"
                local all_deps=""
                for p in $dol_list; do
                    local pdeps
                    pdeps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$p" 2>/dev/null | grep "Depends:" | sed 's/.*Depends: //' | tr -d '<>' | awk '{print $1}')
                    if [[ -z "$all_deps" ]]; then
                        all_deps="$pdeps"
                    else
                        all_deps=$(echo -e "${all_deps}\n${pdeps}" | sort | uniq -d)
                    fi
                done
                if [[ -n "$all_deps" ]]; then
                    while IFS= read -r d; do
                        [[ -z "$d" ]] && continue
                        local installed_mark=""
                        dpkg -s -- "$d" 2>/dev/null | grep -q '^Status: install ok installed' && installed_mark=" ${C_GREEN}(installed)${C_RESET}"
                        printf "  ${C_TEAL}%s${C_RESET}%b\n" "$d" "$installed_mark"
                    done <<< "$all_deps"
                else
                    printf "  ${C_DIM}No shared dependencies.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /upgradable ---
        if [[ "$query" == /upgradable ]]; then
            clear
            printf "\n  ${C_WHITE}Upgradable packages with version diff:${C_RESET}\n\n"
            printf "  ${C_DIM}%-30s %-16s %-16s %s${C_RESET}\n" "PACKAGE" "CURRENT" "AVAILABLE" "SIZE"
            printf "  ${C_DIM}%-30s %-16s %-16s %s${C_RESET}\n" "------------------------------" "----------------" "----------------" "------"
            apt list --upgradable 2>/dev/null | tail -n +2 | while IFS= read -r line; do
                local upkg
                upkg=$(echo "$line" | awk -F'/' '{print $1}')
                local ucur uavail
                ucur=$(apt-cache policy "$upkg" 2>/dev/null | grep "Installed:" | awk '{print $2}')
                uavail=$(apt-cache policy "$upkg" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
                local usize
                usize=$(apt-cache show "$upkg" 2>/dev/null | grep "^Size:" | awk '{print $2}')
                local usize_h
                if [[ -n "$usize" ]]; then
                    if (( usize > 1048576 )); then
                        usize_h="$((usize/1048576))MB"
                    elif (( usize > 1024 )); then
                        usize_h="$((usize/1024))KB"
                    else
                        usize_h="${usize}B"
                    fi
                else
                    usize_h="?"
                fi
                printf "  %-30s ${C_DIM}%-16s${C_RESET} ${C_GREEN}%-16s${C_RESET} %s\n" "$upkg" "$ucur" "$uavail" "$usize_h"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /whatprovides ---
        if [[ "$query" == /whatprovides* ]]; then
            local wp_file="${query#/whatprovides }"
            [[ "$wp_file" == "/whatprovides" ]] && wp_file=""
            clear
            if [[ -z "$wp_file" ]]; then
                printf "  ${C_MSG_INFO}Enter binary/file to find provider:${C_RESET} "
                read -r wp_file
            fi
            if [[ -n "$wp_file" ]]; then
                printf "\n  ${C_WHITE}Packages providing '%s':${C_RESET}\n\n" "$wp_file"
                local wp_result
                wp_result=$(apt-file search "$wp_file" 2>/dev/null || dpkg -S "$wp_file" 2>/dev/null)
                if [[ -n "$wp_result" ]]; then
                    echo "$wp_result" | head -30 | while IFS= read -r line; do
                        local wpkg wpath
                        wpkg=$(echo "$line" | awk -F':' '{print $1}')
                        wpath=$(echo "$line" | awk -F': ' '{print $2}')
                        local winstalled=""
                        dpkg -s -- "$wpkg" 2>/dev/null | grep -q '^Status: install ok installed' && winstalled=" ${C_GREEN}(installed)${C_RESET}"
                        printf "  ${C_TEAL}%s${C_RESET} -> %s%b\n" "$wpkg" "$wpath" "$winstalled"
                    done
                else
                    printf "  ${C_DIM}No packages provide this file.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /snap-install ---
        if [[ "$query" == /snap-install* ]]; then
            local si_file="${query#/snap-install }"
            [[ "$si_file" == "/snap-install" ]] && si_file=""
            clear
            if [[ -z "$si_file" ]]; then
                printf "  ${C_MSG_INFO}Enter path to .deb file:${C_RESET} "
                read -r si_file
            fi
            if [[ -n "$si_file" && -f "$si_file" ]]; then
                printf "\n  ${C_MSG_INFO}Installing from: %s${C_RESET}\n\n" "$si_file"
                dpkg -i "$si_file" 2>&1 | sed 's/^/  /'
                local si_status=$?
                if (( si_status == 0 )); then
                    printf "\n  ${C_MSG_DONE}Installation successful.${C_RESET}\n"
                else
                    printf "\n  ${C_MSG_REMOVE}Installation had errors. Running apt -f install...${C_RESET}\n"
                    apt -f install -y 2>&1 | sed 's/^/  /'
                fi
            elif [[ -n "$si_file" ]]; then
                printf "  ${C_MSG_REMOVE}File not found: %s${C_RESET}\n" "$si_file"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /simulate-remove ---
        if [[ "$query" == /simulate-remove* ]]; then
            local sr_pkg="${query#/simulate-remove }"
            [[ "$sr_pkg" == "/simulate-remove" ]] && sr_pkg=""
            clear
            if [[ -z "$sr_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                sr_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Simulate remove> " --height=50% --reverse)
                sr_pkg=$(echo "$sr_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$sr_pkg" ]]; then
                printf "\n  ${C_WHITE}Simulating removal of %s...${C_RESET}\n\n" "$sr_pkg"
                local sr_out
                sr_out=$(apt-get remove --dry-run "$sr_pkg" 2>&1)
                printf "  ${C_MSG_DONE}Would be removed:${C_RESET}\n"
                echo "$sr_out" | grep "^  " | head -30 | sed 's/^/  /'
                local sr_free
                sr_free=$(echo "$sr_out" | grep -oP 'After this operation, \K[0-9.]+[KMGT]?B')
                if [[ -n "$sr_free" ]]; then
                    printf "\n  ${C_GREEN}Freed space: %s${C_RESET}\n" "$sr_free"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /repo-stats ---
        if [[ "$query" == /repo-stats ]]; then
            clear
            printf "\n  ${C_WHITE}Packages per repository:${C_RESET}\n\n"
            local rs_total=0
            dpkg-query -W -f='${Section}\t${Package}\n' 2>/dev/null | awk -F'\t' '
                {
                    section[$1]++
                    total++
                }
                END {
                    for (s in section) printf "%s\t%d", s, section[s]
                    printf "\t%d\n", total
                }
            ' | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r sec cnt total; do
                local bar=""
                local bcount=$((cnt / 5))
                (( bcount < 1 )) && bcount=1
                for ((i=0; i<bcount; i++)); do bar="${bar}█"; done
                printf "  ${C_TEAL}%-25s${C_RESET} ${C_GREEN}%-4s${C_RESET} %s\n" "$sec" "$cnt" "$bar"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /download-est ---
        if [[ "$query" == /download-est* ]]; then
            local de_pkg="${query#/download-est }"
            [[ "$de_pkg" == "/download-est" ]] && de_pkg=""
            clear
            if [[ -z "$de_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                de_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Download est> " --height=50% --reverse)
                de_pkg=$(echo "$de_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$de_pkg" ]]; then
                printf "\n  ${C_WHITE}Download estimate: %s${C_RESET}\n\n" "$de_pkg"
                local de_show
                de_show=$(apt-cache show "$de_pkg" 2>/dev/null)
                local de_dsize de_isize
                de_dsize=$(echo "$de_show" | grep "^Size:" | head -1 | awk '{print $2}')
                de_isize=$(echo "$de_show" | grep "^Installed-Size:" | head -1 | awk '{print $2}')
                local de_dh de_ih
                if [[ -n "$de_dsize" && "$de_dsize" -gt 0 ]] 2>/dev/null; then
                    if (( de_dsize > 1048576 )); then
                        de_dh="$((de_dsize/1048576)) MB"
                    elif (( de_dsize > 1024 )); then
                        de_dh="$((de_dsize/1024)) KB"
                    else
                        de_dh="${de_dsize} B"
                    fi
                else
                    de_dh="unknown"
                fi
                if [[ -n "$de_isize" && "$de_isize" -gt 0 ]] 2>/dev/null; then
                    de_ih="$((de_isize/1024)) KB"
                else
                    de_ih="unknown"
                fi
                printf "  ${C_MSG_DONE}Download size:${C_RESET}   %s\n" "$de_dh"
                printf "  ${C_MSG_DONE}Installed size:${C_RESET} %s\n" "$de_ih"
                local de_ratio="?"
                if [[ -n "$de_dsize" && -n "$de_isize" && "$de_dsize" -gt 0 && "$de_isize" -gt 0 ]] 2>/dev/null; then
                    de_ratio=$((de_isize * 100 / de_dsize))
                    printf "  ${C_DIM}Expansion ratio:          %d%%${C_RESET}\n" "$de_ratio"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # --- /diff ---
        if [[ "$query" == /diff* ]]; then
            local df_pkg="${query#/diff }"
            [[ "$df_pkg" == "/diff" ]] && df_pkg=""
            clear
            if [[ -z "$df_pkg" ]]; then
                _pkgs_get_cached_list > /dev/null 2>&1
                df_pkg=$(cat "$_PKGS_CACHE_FILE" | fzf --prompt=" Changelog diff> " --height=50% --reverse)
                df_pkg=$(echo "$df_pkg" | awk -F'|' '{print $2}' | xargs)
            fi
            if [[ -n "$df_pkg" ]]; then
                printf "\n  ${C_WHITE}Changelog diff: %s${C_RESET}\n\n" "$df_pkg"
                local cl_file="${PREFIX}/share/doc/${df_pkg}/changelog.Debian"
                if [[ -f "$cl_file" ]]; then
                    local cl_cur cl_prev
                    cl_cur=$(apt-cache policy "$df_pkg" 2>/dev/null | grep "Installed:" | awk '{print $2}')
                    cl_prev=$(dpkg -s "$df_pkg" 2>/dev/null | grep "^Version:" | awk '{print $2}')
                    if [[ -n "$cl_cur" && -n "$cl_prev" ]]; then
                        printf "  ${C_DIM}Comparing %s -> %s${C_RESET}\n\n" "$cl_prev" "$cl_cur"
                    fi
                    head -80 "$cl_file" | sed 's/^/  /'
                else
                    printf "  ${C_DIM}No changelog found for %s.${C_RESET}\n" "$df_pkg"
                    printf "  ${C_DIM}Try: /changelog %s${C_RESET}\n" "$df_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
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
  /mirror               Switch apt mirror
  /fav <pkg>            Toggle package favorite
  /fav-list             Show all favorites
  /fav-remove           Remove a favorite
  /import <file>        Install from package list file
  /why <pkg>            Show why a package is installed
  /suggest <pkg>        Show recommended packages
  /nuke                 Interactive storage cleanup
  /whatsnew             Show recent upgrade changelogs
  /tips                 Termux tips & tricks
  /self-update          Update pkgs from GitHub
  /search-size <min> <max>  Find packages by size (KiB)
  /pkg-history <pkg>    Per-package install/upgrade/remove history
  /depends-chain <a> <b> Show dependency chain between two packages
  /broken               Find broken/half-installed packages
  /conflicts-with <pkg> Show conflicting packages
  /provides <pkg>       Show virtual packages provided
  /manually-installed   Show only manually installed packages
  /auto-installed       Show only auto-installed packages
  /upgrade-plan         Simulate upgrade, show what would change
  /pkg-ages             Show age of each installed package
  /unused-libs          Find orphaned .so libraries
  /maintainer <name>    Search packages by maintainer
  /log-search <text>    Search dpkg/apt history logs
  /mirror-backup        Backup/restore sources.list snapshots
  /size-histogram       Visual package size distribution
  /deptree <pkg>        Visual dependency tree (ASCII art)
  /reverse-tree <pkg>   Reverse dependency tree
  /upgrade-size         Total download size before upgrading
  /download <pkg>       Download package without installing
  /verify <pkg>         Verify package checksums/integrity
  /mirror-latency       Ping-test all mirrors, rank by latency
  /mirror-bandwidth     Bandwidth-test mirrors, rank by speed
  /pkg-changes          Show what changed in last apt upgrade
  /pkg-recommendations <pkg>  Show who recommends this package
  /pkg-suggests <pkg>   Show who suggests this package
  /pkg-breaks <pkg>     Show what breaks if this is installed
  /pkg-replaces <pkg>   Show what this package replaces
  /owner <file>         Which package owns this file (dpkg -S)
  /removed              Packages removed in last upgrade
  /new-pkgs             Packages installed this week
  /same-size            Packages with identical installed size
  /depends-on-list <pkgs>  Shared dependencies of multiple pkgs
  /upgradable           Upgradable packages with version diff
  /whatprovides <file>  Find which package provides a binary
  /snap-install <file>  Install from local .deb file
  /simulate-remove <pkg>  Simulate removal, show consequences
  /repo-stats           Packages per repository breakdown
  /download-est <pkg>   Download size + installed size estimate
  /diff <pkg>           Changelog diff of last upgrade
  /theme                Switch color scheme
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
