#!/data/data/com.termux/files/usr/bin/zsh
emulate -L zsh
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
    local _PKGS_VERSION="1.5.0"

    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                _pkgs_usage
                return 0
                ;;
            -v|--version)
                echo "pkgs v${_PKGS_VERSION}"
                return 0
                ;;
            --konami)
                printf "\n  \033[38;5;46m↑\033[38;5;226m↑\033[38;5;202m↓\033[38;5;202m↓\033[38;5;129m←\033[38;5;214m→\033[38;5;129m←\033[38;5;214m→\033[38;5;46m B A \033[38;5;226mStart!\033[0m\n\n"
                printf "  \033[38;5;226mYou found the secret code!\033[0m\n"
                printf "  \033[38;5;59m(No extra lives were awarded. Sorry.)\033[0m\n\n"
                return 0
                ;;
            -vv)
                echo "pkgs v${_PKGS_VERSION} (you asked nicely, so here's the extended version)"
                echo "  Built with: questionable life choices, fzf, and zsh"
                echo "  Total slash commands: probably too many"
                echo "  Author's remaining hair: classified"
                return 0
                ;;
        esac
    done
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

    local C_INST_PREFIX="${C_GREEN}✓${C_RESET}"
    local C_NOT_INST_PREFIX="${C_DIM}○${C_RESET}"
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
    local _PKGS_THEME=""
    local _PKGS_FAVORITES_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/favorites"
    local _PKGS_SELF_URL="https://raw.githubusercontent.com/Mark44928/Termux-TUI-Package-Store/refs/heads/main/pkgs_core.zsh"

    _pkgs_validate_name() {
        [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9._+\-~]*$ ]]
    }

    _pkgs_resolve_path() {
        local path="$1"
        local resolved
        resolved=$(readlink -f "$path" 2>/dev/null) \
            || resolved=$(realpath "$path" 2>/dev/null) \
            || { local dir; dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P); resolved="${dir:+${dir}/$(basename "$path")}"; }
        print -r -- "$resolved"
    }

    _pkgs_date_ago() {
        local days="$1" fmt="${2:-%Y-%m-%d}"
        local ts=$(( $(date +%s) - days * 86400 ))
        date -d "@$ts" +"$fmt" 2>/dev/null \
            || TZ=UTC date -r "$ts" +"$fmt" 2>/dev/null \
            || printf "%s" "$(date +"$fmt")"
    }

    _pkgs_validate_export_path() {
        local path="$1"
        [[ -z "$path" ]] && return 1
        [[ "$path" =~ ^[[:space:]] ]] && return 1
        local dir
        dir=$(dirname "$path" 2>/dev/null)
        [[ -z "$dir" || ! -d "$dir" ]] && return 1
        local resolved
        resolved=$(_pkgs_resolve_path "$path") || return 1
        local prefix_dir
        prefix_dir=$(readlink -f "${PREFIX}" 2>/dev/null || echo "${PREFIX}")
        [[ -z "$prefix_dir" ]] && return 1
        [[ "$resolved" == "$prefix_dir/bin/pkgs" ]] && return 1
        # Block sensitive directories (both as direct paths and as substrings in the path)
        [[ "$resolved" == *"/.ssh"* || "$resolved" == *"/.gnupg"* || "$resolved" == "/etc/"* || "$resolved" == "/proc/"* || "$resolved" == "/sys/"* || "$resolved" == "/dev/"* ]] && return 1
        [[ "$resolved" != "$HOME"/* && "$resolved" != "$HOME" ]] && return 1
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

    # FZF package picker — extracts package name from cache selection
    _pkgs_fzf_pick_pkg() {
        local prompt="$1" height="${2:-50%}"
        _pkgs_get_cached_list > /dev/null 2>&1
        local fzf_tmp
        fzf_tmp=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_fzf.XXXXXX") || { _PKGS_FZF_PICKED=""; return 1; }
        chmod 600 "$fzf_tmp" 2>/dev/null
        _PKGS_TMP_FILES+=("$fzf_tmp")
        fzf < "$_PKGS_CACHE_FILE" --prompt=" $prompt> " --height="$height" --reverse > "$fzf_tmp" 2>/dev/null
        if [[ ! -s "$fzf_tmp" ]]; then
            rm -f "$fzf_tmp" 2>/dev/null
            _PKGS_FZF_PICKED=""
            return 1
        fi
        local raw; read -r raw < "$fzf_tmp"
        rm -f "$fzf_tmp" 2>/dev/null
        _PKGS_FZF_PICKED="${raw%%|*}"
    }

    # Bulk apt-cache policy — returns "pkg installed_ver candidate_ver" for all given packages
    # Accepts package names as arguments or reads from stdin (one per line)
    _pkgs_bulk_apt_policy() {
        local -a pkgs=()
        if (( $# > 0 )); then
            pkgs=("$@")
        else
            while IFS= read -r line; do
                [[ -n "$line" ]] && pkgs+=("$line")
            done
        fi
        (( ${#pkgs[@]} == 0 )) && return
        # apt-cache policy accepts multiple packages in one call
        apt-cache policy -- "${pkgs[@]}" 2>/dev/null | awk '
            /^Package:/ { pkg = $2 }
            /^\s+Installed:/ { installed = $NF }
            /^\s+Candidate:/ { candidate = $NF }
            /^$/ { if (pkg != "" && installed != "(none)" && installed != candidate) print pkg, installed, candidate; pkg=""; installed=""; candidate="" }
            END { if (pkg != "" && installed != "(none)" && installed != candidate) print pkg, installed, candidate }
        '
    }

    # Bulk dpkg-query size — returns "pkg size_kb" for all given packages
    _pkgs_bulk_dpkg_size() {
        local -a pkgs=("$@")
        (( ${#pkgs[@]} == 0 )) && return
        dpkg-query -W -f='${Package} ${Installed-Size}\n' -- "${pkgs[@]}" 2>/dev/null
    }

    # Profile storage
    _PKGS_PROFILES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/profiles"

    _pkgs_profile_list() {
        mkdir -p "$_PKGS_PROFILES_DIR" 2>/dev/null
        ls -1 "$_PKGS_PROFILES_DIR"/*.pkgslist(N) 2>/dev/null | while read -r f; do
            local name="${f:t}"
            name="${name%.pkgslist}"
            local count
            count=$(wc -l < "$f" 2>/dev/null || echo 0)
            local mtime
            mtime=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo 0)
            printf "%s\t%d\t%s\n" "$name" "$count" "$mtime"
        done
    }

    # Snapshot storage
    _PKGS_SNAPSHOTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/snapshots"

    # Get termux-api notification helper (soft dependency)
    _pkgs_notify() {
        local title="$1" msg="$2"
        command -v termux-notification >/dev/null 2>&1 && termux-notification --title "$title" --content "$msg" 2>/dev/null
    }

    _pkgs_parse_pkg_arg() {
        local cmd="$1" full_query="$2"
        if [[ "$full_query" == "/$cmd" || "$full_query" == "/$cmd " ]]; then
            printf "${C_MSG_WARN}Usage: /%s <pkg>${C_RESET}\n" "$cmd" >&2
            return 1
        fi
        local pkg="${full_query#* }"
        pkg="$(_pkgs_trim "$pkg")"
        if [[ -z "$pkg" ]]; then
            printf "${C_MSG_WARN}Usage: /%s <pkg>${C_RESET}\n" "$cmd" >&2
            return 1
        fi
        if ! _pkgs_validate_name "$pkg"; then
            printf "${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$pkg" >&2
            return 1
        fi
        echo "$pkg"
    }

    _pkgs_save_state() {
        mkdir -p "$_PKGS_CONFIG_DIR" 2>/dev/null
        chmod 700 "$_PKGS_CONFIG_DIR" 2>/dev/null
        local tmp_config
        tmp_config=$(mktemp "${_PKGS_CONFIG_DIR}/config.XXXXXX") || return 1
        chmod 600 "$tmp_config" 2>/dev/null
        {
            printf "FILTER=%s\n" "$_PKGS_FILTER"
            printf "SORT=%s\n" "$_PKGS_SORT"
            printf "THEME=%s\n" "$_PKGS_THEME"
            printf "COMPACT=%s\n" "${_PKGS_COMPACT:-off}"
            printf "HISTORY_DAYS=%s\n" "$_PKGS_HISTORY_KEEP_DAYS"
        } > "$tmp_config" 2>/dev/null
        mv "$tmp_config" "$_PKGS_CONFIG_FILE" 2>/dev/null
    }

    _pkgs_load_state() {
        if [[ -f "$_PKGS_CONFIG_FILE" ]]; then
            local line
            while IFS='=' read -r key val; do
                case "$key" in
                    FILTER) _PKGS_FILTER="$val" ;;
                    SORT) _PKGS_SORT="$val" ;;
                    THEME) _PKGS_THEME="$val" ;;
                    COMPACT) _PKGS_COMPACT="$val" ;;
                    HISTORY_DAYS) [[ "$val" =~ ^[0-9]+$ ]] && _PKGS_HISTORY_KEEP_DAYS="$val" ;;
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
            case "$_PKGS_THEME" in
                dark|light|minimal|neon|dracula|monokai|solarized|"") ;;
                *) _PKGS_THEME="" ;;
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
        C_INST_PREFIX="${C_GREEN}✓${C_RESET}"
        C_NOT_INST_PREFIX="${C_DIM}○${C_RESET}"
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
        cutoff_date=$(_pkgs_date_ago "$_PKGS_HISTORY_KEEP_DAYS") || return
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

    _pkgs_spinner() {
        local pid=$1 msg=$2
        [[ -n "$pid" ]] || return 1
        local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠏)
        local i=0
        while kill -0 "$pid" 2>/dev/null; do
            printf "\r  ${C_TEAL}%s${C_RESET} %s" "${frames[$((i % ${#frames[@]} + 1))]}" "$msg"
            sleep 0.1
            ((i++))
        done
        wait "$pid" 2>/dev/null
        return $?
    }

    _pkgs_check_network() {
        local host="${1:-packages.termux.dev}"
        if ! ping -c1 "$host" &>/dev/null; then
            printf "\n  ${C_MSG_REMOVE}No network connection (cannot reach %s).${C_RESET}\n" "$host"
            printf "  ${C_DIM}Check your wifi/mobile data and try again.${C_RESET}\n"
            return 1
        fi
        return 0
    }

    # Package queue (persistent)
    _PKGS_QUEUE_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/queue"

    _pkgs_queue_load() {
        local -a q=()
        if [[ -f "$_PKGS_QUEUE_FILE" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && q+=("$line")
            done < "$_PKGS_QUEUE_FILE"
        fi
        _PKGS_QUEUE=("${q[@]}")
    }

    _pkgs_queue_save() {
        mkdir -p "$(dirname "$_PKGS_QUEUE_FILE")" 2>/dev/null
        local tmp_q
        tmp_q=$(mktemp "${_PKGS_QUEUE_FILE}.XXXXXX") 2>/dev/null || return 1
        printf "%s\n" "${_PKGS_QUEUE[@]}" > "$tmp_q" 2>/dev/null
        mv "$tmp_q" "$_PKGS_QUEUE_FILE" 2>/dev/null
    }

    _pkgs_config_editor() {
        clear
        printf "\n  ${C_WHITE}─── Settings ───${C_RESET}\n\n"
        local -a settings_items=(
            "theme|Color theme|${_PKGS_THEME:-dark}"
            "filter|Package filter|${_PKGS_FILTER}"
            "sort|Sort mode|${_PKGS_SORT}"
            "compact|Compact mode|${_PKGS_COMPACT:-off}"
            "history_days|History retention|${_PKGS_HISTORY_KEEP_DAYS} days"
        )
        local idx=1
        for item in "${settings_items[@]}"; do
            local key="${item%%|*}"
            local rest="${item#*|}"
            local label="${rest%%|*}"
            local val="${rest#*|}"
            printf "  ${C_DIM}%d)${C_RESET} ${C_TEAL}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "$idx" "$label" "$val"
            ((idx++))
        done
        printf "\n  ${C_DIM}Enter number to edit, or Enter to return:${C_RESET} "
        local choice
        read -r choice
        [[ -z "$choice" ]] && return
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#settings_items[@]} )); then
            printf "  ${C_MSG_REMOVE}Invalid choice.${C_RESET}\n"
            sleep 1
            return
        fi
        local selected="${settings_items[$choice]}"
        local key="${selected%%|*}"
        case "$key" in
            theme)
                printf "\n  ${C_DIM}Available: dark, light, minimal, neon, dracula, monokai, solarized${C_RESET}\n"
                printf "  ${C_DIM}Current: ${C_WHITE}%s${C_RESET}\n" "${_PKGS_THEME:-dark}"
                printf "  Enter new theme: "
                local new_theme
                read -r new_theme
                [[ -z "$new_theme" ]] && return
                case "$new_theme" in
                    dark|light|minimal|neon|dracula|monokai|solarized)
                        _pkgs_apply_theme "$new_theme"
                        _PKGS_THEME="$new_theme"
                        _pkgs_save_state
                        printf "\n  ${C_MSG_DONE}Theme changed to: %s${C_RESET}\n" "$new_theme"
                        ;;
                    *)
                        printf "\n  ${C_MSG_REMOVE}Invalid theme: %s${C_RESET}\n" "$new_theme"
                        ;;
                esac
                ;;
            filter)
                printf "\n  ${C_DIM}Available: all, installed, available, recent${C_RESET}\n"
                printf "  ${C_DIM}Current: ${C_WHITE}%s${C_RESET}\n" "$_PKGS_FILTER"
                printf "  Enter new filter: "
                local new_filter
                read -r new_filter
                [[ -z "$new_filter" ]] && return
                case "$new_filter" in
                    all|installed|available|recent)
                        _PKGS_FILTER="$new_filter"
                        _pkgs_invalidate_cache
                        _pkgs_save_state
                        printf "\n  ${C_MSG_DONE}Filter changed to: %s${C_RESET}\n" "$new_filter"
                        ;;
                    *)
                        printf "\n  ${C_MSG_REMOVE}Invalid filter: %s${C_RESET}\n" "$new_filter"
                        ;;
                esac
                ;;
            sort)
                printf "\n  ${C_DIM}Available: name, size${C_RESET}\n"
                printf "  ${C_DIM}Current: ${C_WHITE}%s${C_RESET}\n" "$_PKGS_SORT"
                printf "  Enter new sort: "
                local new_sort
                read -r new_sort
                [[ -z "$new_sort" ]] && return
                case "$new_sort" in
                    name|size)
                        _PKGS_SORT="$new_sort"
                        _pkgs_invalidate_cache
                        _pkgs_save_state
                        printf "\n  ${C_MSG_DONE}Sort changed to: %s${C_RESET}\n" "$new_sort"
                        ;;
                    *)
                        printf "\n  ${C_MSG_REMOVE}Invalid sort: %s${C_RESET}\n" "$new_sort"
                        ;;
                esac
                ;;
            compact)
                if [[ "${_PKGS_COMPACT:-off}" == "on" ]]; then
                    _PKGS_COMPACT="off"
                else
                    _PKGS_COMPACT="on"
                fi
                _pkgs_save_state
                printf "\n  ${C_MSG_DONE}Compact mode: %s${C_RESET}\n" "$_PKGS_COMPACT"
                ;;
            history_days)
                printf "\n  ${C_DIM}Current: ${C_WHITE}%s${C_RESET} days\n" "$_PKGS_HISTORY_KEEP_DAYS"
                printf "  Enter new value (1-365): "
                local new_days
                read -r new_days
                [[ -z "$new_days" ]] && return
                if [[ "$new_days" =~ ^[0-9]+$ ]] && (( new_days >= 1 && new_days <= 365 )); then
                    _PKGS_HISTORY_KEEP_DAYS="$new_days"
                    _pkgs_save_state
                    printf "\n  ${C_MSG_DONE}History retention: %d days${C_RESET}\n" "$new_days"
                else
                    printf "\n  ${C_MSG_REMOVE}Invalid value.${C_RESET}\n"
                fi
                ;;
        esac
        printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
        read -r
    }

    _pkgs_log_history() {
        local action="$1" pkg_name="$2"
        mkdir -p "$_PKGS_HISTORY_DIR" 2>/dev/null
        chmod 700 "$_PKGS_HISTORY_DIR" 2>/dev/null
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
        desc=$(print -r -- "$info" | sed -n '/^Description:/{ s/^Description: //p; :a; n; /^ /{ s/^ //p; ba }; }')
        printf "  ${C_WHITE}Description:${C_RESET}\n"
        printf "  ${C_DIM}%s${C_RESET}\n" "$(print -r -- "$desc" | head -6)"
        printf "\n  ${C_MSG_INFO}Press Enter to return, b to go back: ${C_RESET}"
        read -r _info_choice
        if [[ "$_info_choice" == "b" ]]; then
            _PKGS_BACK_ACTION=1
        fi
    }

    _pkgs_help_print_cols() {
        local tw=$1 nc=$2
        shift 2
        local i=0 row=""
        if (( nc <= 1 )); then
            for item in "$@"; do
                local cmd="${item%%|*}" desc="${item#*|}"
                printf "    ${C_TEAL}%-28s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$cmd" "$desc"
            done
            return
        fi
        local sep_w=3 total=$#
        local cw=$(( (tw - sep_w * (nc - 1) - 2 * nc) / nc ))
        for item in "$@"; do
            ((i++))
            local cmd="${item%%|*}" desc="${item#*|}"
            local pad="" gap=2
            local cmdw=${#cmd} descw=${#desc}
            pad=$(( cw - cmdw - descw ))
            (( pad < gap )) && pad=$gap
            printf -v pad '%*s' "$pad" ''
            row+="  ${C_TEAL}${cmd}${C_RESET}${pad}${C_DIM}${desc}${C_RESET}"
            if (( i % nc == 0 )); then
                printf "%s\n" "$row"
                row=""
            elif (( i < total )); then
                row+="${C_DIM} │ ${C_RESET}"
            fi
        done
        [[ -n "$row" ]] && printf "%s\n" "$row"
    }

    _pkgs_show_help() {
        clear
        local tw
        tw=$(tput cols 2>/dev/null || echo 80)
        if (( tw < 40 )); then
            printf "\n  ${C_MSG_WARN}Terminal too small (${tw} cols). Need >= 40 columns.${C_RESET}\n"
            printf "  ${C_MSG_WARN}Resize your terminal or rotate your device.${C_RESET}\n\n"
            printf "  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            return
        fi
        local nc=1 shock=""
        (( tw >= 100 )) && nc=2
        (( tw >= 150 )) && nc=3
        (( tw >= 200 )) && nc=4
        (( tw >= 250 )) && nc=5
        (( tw >= 300 )) && nc=6

        if (( tw >= 300 )); then
            shock="${C_MSG_WARN}WH... WHY IS YOUR TERMINAL ${tw} COLUMNS WIDE?!${C_RESET}"
        elif (( tw >= 250 )); then
            shock="${C_MSG_WARN}Your terminal is ABSURDLY wide (${tw} cols). Impressive.${C_RESET}"
        elif (( tw >= 200 )); then
            shock="${C_MSG_WARN}Okay that's a THICC terminal (${tw} cols). Fine, 4 columns it is.${C_RESET}"
        elif (( tw >= 150 )); then
            shock="${C_DIM}Ooh, spacious! ${tw} cols. Here, have ${nc} columns.${C_RESET}"
        fi

        printf "\n  ${C_WHITE}Package Manager - Help${C_RESET}"
        printf "  ${C_DIM}(${tw} cols, ${nc}-column mode)${C_RESET}"
        if [[ -n "$shock" ]]; then
            printf "\n  ${shock}"
        fi
        printf "\n"

        local -a cmds=(
            "/upgrade|Upgrade all packages" "/export-all|Export all installed"
            "/install <pkg>|Install by name" "/info <pkg>|Full package info"
            "/remove <pkg>|Remove by name" "/search <text>|Search packages"
            "/purge <pkg>|Remove + config files" "/rdeps <pkg>|Reverse dependencies"
            "/hold <pkg>|Pin (no upgrade)" "/depends-on <pkg>|Installed dependents"
            "/unhold <pkg>|Unpin package" "/deps <pkg>|Show dependencies"
            "/export <pkg>|Export install script" "/tree <pkg>|Dependency tree"
            "/compare <a> <b>|Compare packages" "/note <pkg> <text>|Add/view note"
            "/orphans|Show orphaned packages" "/orphans-safe|Safe orphans"
            "/orphans-remove|Remove all orphans" "/outdated|Packages with updates"
            "/top|Top 10 largest pkgs" "/top <n>|Top N largest pkgs"
            "/size|Total installed size" "/count|Count packages"
            "/update|Update apt cache" "/clean|Clean orphans + cache"
            "/installed|Show only installed" "/available|Show only available"
            "/recent|Show installed today" "/usage|Disk usage by section"
            "/usage <pkg>|Per-package file list" "/changelog <pkg>|Show changelog"
            "/reinstall <pkg>|Reinstall package" "/search-file <text>|Search files"
            "/download-size <pkg>|Download size" "/check|Verify packages"
            "/group|Packages by section" "/outdated-top <n>|Top N outdated"
            "/usage-top <n>|Disk usage bar chart" "/version|System version info"
            "/all|Reset filter: show all" "/sort name|size|Sort by name/size"
            "/history|View last 7 days" "/review|Today's activity"
            "/stats|Today's counts" "/backup|Export package list"
            "/restore <file>|Install from list" "/undo|Reverse last op"
            "/mirror|Switch apt mirror" "/fav <pkg>|Toggle favorite"
            "/fav-list|Show all favorites" "/fav-remove|Remove a favorite"
            "/import <file>|Install from list" "/why <pkg>|Why installed"
            "/suggest <pkg>|Recommended packages" "/nuke|Storage cleanup"
            "/whatsnew|Recent changelogs" "/tips|Termux tips"
            "/self-update|Update from GitHub" "/search-size <min> <max>|Find by size"
            "/pkg-history <pkg>|Per-pkg history" "/depends-chain <a> <b>|Dep chain"
            "/broken|Find broken packages" "/conflicts-with <pkg>|Show conflicts"
            "/provides <pkg>|Virtual packages" "/manually-installed|Manual only"
            "/auto-installed|Auto installs" "/upgrade-plan|Simulated upgrade"
            "/pkg-ages|Package age view" "/unused-libs|Orphaned libraries"
            "/maintainer <name>|Search by maintainer" "/log-search <text>|Search dpkg logs"
            "/mirror-backup|Backup/restore mirrors" "/size-histogram|Size distribution"
            "/deptree <pkg>|Visual dep tree" "/reverse-tree <pkg>|Reverse dep tree"
            "/upgrade-size|Total upgrade dl size" "/download <pkg>|Download w/o install"
            "/verify <pkg>|Verify checksums" "/mirror-latency|Ping-test mirrors"
            "/mirror-bandwidth|Bandwidth-test mirrors" "/pkg-changes|Last apt upgrade diff"
            "/pkg-recommendations <pkg>|Who recommends" "/pkg-suggests <pkg>|Who suggests"
            "/pkg-breaks <pkg>|What breaks" "/pkg-replaces <pkg>|What this replaces"
            "/owner <file>|File owner (dpkg -S)" "/removed|Removed last upgrade"
            "/new-pkgs|Installed this week" "/same-size|Same-size packages"
            "/depends-on-list <pkgs>|Shared deps" "/upgradable|Upgradable with diff"
            "/whatprovides <file>|Find binary provider" "/snap-install <file>|Install local .deb"
            "/simulate-remove <pkg>|Simulate removal" "/repo-stats|Packages per repo"
            "/download-est <pkg>|Download+install est." "/diff <pkg>|Changelog diff"
            "/snapshot|Save snapshot" "/snapshot-list|List snapshots"
            "/snapshot-restore|Restore snapshot" "/plan <cmd>|Dry-run preview"
            "/missing|Missing dependencies" "/compact|Toggle compact mode"
            "/search-history <txt>|Search history" "/quick|Popular package sets"
            "/fuzzy-dep|Dependency explorer" "/size-filter <min> <max>|Filter by size"
            "/security|Outdated pkg check" "/duplicate|Duplicate/virtual pkgs"
            "/config|Edit settings" "/queue|View package queue"
            "/queue-add <pkg>|Add to queue" "/queue-remove <pkg>|Remove from queue"
            "/queue-clear|Clear queue"
        )
        printf "\n  ${C_AMBER}Slash Commands${C_RESET}\n"
        _pkgs_help_print_cols "$tw" "$nc" "${cmds[@]}"

        local -a cmds2=(
            "/profile|Save/restore profiles" "/check-deps|Scan missing tools"
            "/shell-hook|Shell aliases from pkgs" "/storage-report|Android storage"
            "/health|System health score" "/auto-clean|Scheduled cleanup (cronie)"
            "/footprint <pkg>|Total size+transitive" "/unused|Never invoked packages"
            "/timeline|Activity map" "/schedule|Update reminders (cronie)"
            "/search-providers|Find pkgs for command" "/diff-snapshots|Diff snapshots"
            "/audit|SUID/SGID scan" "/repo-check|Untrusted repo check"
            "/popular|Popular packages list" "/boot-time|Benchmark startup"
            "/disk-pressure|Storage pressure" "/pkg-impact <pkg>|Pre-install analysis"
            "/export-versions|Export with versions" "/theme-preview|Preview colors"
            "/keys|Fzf keybinding ref" "/cache-stats|Cache dashboard"
            "/dep-graph <pkg>|Visual dep tree" "/batch-upgrade|Batch upgrade picker"
            "/activity-log [days]|Package activity" "/compare <pkg1 pkg2>|Compare packages"
            "/theme|Switch color scheme" "/help|Show this help"
        )
        printf "\n  ${C_AMBER}Extended Commands${C_RESET}\n"
        _pkgs_help_print_cols "$tw" "$nc" "${cmds2[@]}"

        local -a kbs=("?:Toggle preview" "Tab:Multi-select" "Ctrl-A:Select all visible" "Ctrl-D:Deselect all" "Enter:Confirm selection" "Esc:Exit")
        printf "\n  ${C_AMBER}Keybindings${C_RESET}\n"
        _pkgs_help_print_cols "$tw" "$nc" "${kbs[@]}"

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
            local dpkg_log="${PREFIX}/var/log/dpkg.log"
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
                local size="${pkg_sizes[$pkg]:-999999999}"
                printf "%010d|%s\n" "$size" "$line"
            done <<< "$list_output" | sort -t'|' -k1,1 -rn | cut -d'|' -f2-
        else
            print -r -- "$list_output" | sort -t'|' -k1,1
        fi
    }

    _pkgs_get_cached_list() {
        if (( _PKGS_CACHE_VALID )) && [[ -n "$_PKGS_CACHE_FILE" && -f "$_PKGS_CACHE_FILE" ]]; then
            cat "$_PKGS_CACHE_FILE"
        else
            _PKGS_CACHE_FILE=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_cache.XXXXXX")
            chmod 600 "$_PKGS_CACHE_FILE" 2>/dev/null
            _pkgs_generate_list > "$_PKGS_CACHE_FILE"
            _PKGS_CACHE_VALID=1
            cat "$_PKGS_CACHE_FILE"
        fi
    }

    _pkgs_preview_command() {
        cat <<'PREVIEW_EOF'
pkg_name={1}
pkg_name="${pkg_name%%[[:space:]]*}"
pkg=$(apt-cache show "$pkg_name" 2>/dev/null) || { echo "  Package not found"; exit 0; }

pkg_status="not installed"
hold_status=""
if dpkg -s -- "$pkg_name" 2>/dev/null | grep -q "^Status: install ok installed"; then
    pkg_status="installed"
    if dpkg -s -- "$pkg_name" 2>/dev/null | grep -q "^Status: hold"; then
        hold_status=" [PINNED]"
    fi
fi
essential=$(echo "$pkg" | grep "^Essential:" | head -1 | cut -d" " -f2)
version=$(echo "$pkg" | grep "^Version:" | head -1 | sed 's/^Version: //')

printf "  \033[38;5;114m%s\033[0m%s  \033[38;5;59m(%s)\033[0m\n" "$pkg_name" "$hold_status" "$pkg_status"
printf "  \033[38;5;109mv%s\033[0m" "$version"
[ -n "$essential" ] && printf "  \033[38;5;180messential\033[0m"
printf "\n"

maintainer=$(echo "$pkg" | grep "^Maintainer:" | head -1 | sed 's/^Maintainer: //')
homepage=$(echo "$pkg" | grep "^Homepage:" | head -1 | sed 's/^Homepage: //')
[ -n "$maintainer" ] && printf "\n  \033[38;5;59mPackage Maintainer:\033[0m %s\n" "$(echo "$maintainer" | cut -c1-48)"
[ -n "$homepage" ] && printf "  \033[38;5;59mWeb:\033[0m %s\n" "$(echo "$homepage" | cut -c1-48)"

dl_size=$(echo "$pkg" | grep "^Size:" | head -1 | cut -d" " -f2)
inst_size=$(echo "$pkg" | grep "^Installed-Size:" | head -1 | sed 's/^Installed-Size: //')
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

printf "\n  \033[38;5;180m─── Dependencies ───\033[0m\n"
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
    printf "\n  \033[38;5;114m─── Recommends ───\033[0m\n"
    echo "$recs" | while read -r r; do printf "  %s\n" "$r"; done
fi
if [ -n "$sugs" ]; then
    printf "\n  \033[38;5;139m─── Suggests ───\033[0m\n"
    echo "$sugs" | while read -r s; do printf "  %s\n" "$s"; done
fi

conflicts=$(echo "$pkg" | grep "^Conflicts:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | sed 's/ *(.*//' | sort -u | head -n 3)
replaces=$(echo "$pkg" | grep "^Replaces:" | cut -d":" -f2 | sed "s/^ //" | tr ',' '\n' | sed 's/ *(.*//' | sort -u | head -n 3)
if [ -n "$conflicts" ]; then
    printf "\n  \033[38;5;203m─── Conflicts ───\033[0m\n"
    echo "$conflicts" | while read -r c; do printf "  %s\n" "$c"; done
fi
if [ -n "$replaces" ]; then
    printf "\n  \033[38;5;109m─── Replaces ───\033[0m\n"
    echo "$replaces" | while read -r r; do printf "  %s\n" "$r"; done
fi

printf "\n  \033[38;5;180m─── Reverse Deps ───\033[0m\n"
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

if dpkg -s -- "$pkg_name" 2>/dev/null | grep -q "^Status: install ok installed"; then
    pkg_files=$(dpkg -L -- "$pkg_name" 2>/dev/null | grep "^/")
    file_count=$(echo "$pkg_files" | grep -c "^/" 2>/dev/null)
    printf "\n  \033[38;5;114m─── Installed Files (%s) ───\033[0m\n" "$file_count"
    echo "$pkg_files" | grep -v "^/\\." | grep -v "^/etc/" | tail -n 12 | while read -r f; do printf "  %s\n" "$f"; done
    [ "$file_count" -gt 12 ] && printf "  \033[38;5;59m...%d more files\033[0m\n" "$((file_count - 12))"
fi

printf "\n  \033[38;5;223m─── Description ───\033[0m\n"
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
        local height_arg=()
        [[ "$_PKGS_COMPACT" == "on" ]] && height_arg=(--height=60% --reverse)
        FZF_ARGS=(
            --ansi
            --query "$query"
            --layout=reverse
            --border="$BORDER_STYLE"
            --border-label="  Packages${info_label} "
            --preview-label="  Details "
            --prompt="  > "
            --pointer="➜"
            --info=inline
            --multi
            --print-query
            --color='fg:223,bg:-1,hl:107,fg+:223,bg+:236,hl+:114,info:109,prompt:180,pointer:203,marker:114,spinner:139,header:59,border:59,separator:59'
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
            "${height_arg[@]}"
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
    local -a _PKGS_QUEUE=()
    local _PKGS_COMPACT="off"

    _pkgs_load_state
    _pkgs_apply_theme "$_PKGS_THEME"
    _pkgs_rotate_history
    _pkgs_queue_load

    trap '_pkgs_invalidate_cache; _pkgs_cleanup' EXIT INT TERM HUP QUIT

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
        local fzf_tmp
        fzf_tmp=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_fzf.XXXXXX") || { continue; }
        chmod 600 "$fzf_tmp" 2>/dev/null
        _PKGS_TMP_FILES+=("$fzf_tmp")
        fzf < "$_PKGS_CACHE_FILE" "${FZF_ARGS[@]}" > "$fzf_tmp" 2>/dev/null
        local ret=$?

        if [[ ! -s "$fzf_tmp" ]]; then
            rm -f "$fzf_tmp" 2>/dev/null
            [[ $ret -ne 0 ]] && { clear; break; }
            continue
        fi
        local output=""
        while IFS= read -r line; do output+="$line"$'\n'; done < "$fzf_tmp"
        output="${output%$'\n'}"
        rm -f "$fzf_tmp" 2>/dev/null
 
        output="${output//$'\033'\[[0-9;]*[a-zA-Z]/}"
        local -a lines=("${(@f)output}")
        [[ ${#lines[@]} -lt 1 ]] && continue

        local query="${lines[1]}"
        query="$(_pkgs_trim "$query")"

        if [[ "$query" == -* ]]; then
            query=""
            continue
        fi

        if [[ "$query" == /help ]]; then
            _pkgs_show_help
            continue
        fi

        # ── Easter eggs ──
        if [[ "$query" == /42 ]]; then
            printf "\n  \033[38;5;226mThe Answer to the Ultimate Question of Life, the Universe, and Everything.\033[0m\n"
            printf "  \033[38;5;59m(Still no idea what the question was though.)\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /coffee ]]; then
            local _cup=$'    ( (\n    ) )\n  .______.\n  |      |]\n  \\      /\n   \\`----\''
            printf "\n  \033[38;5;130m%s\033[0m\n" "$_cup"
            printf "  \033[38;5;130mCoffee installed. Wait, this isn't a real package manager... or is it?\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /matrix ]]; then
            printf "\n"
            local _m _i _m_line
            for _m in 1 2 3 4 5; do
                _m_line=""
                for _i in $(seq 1 $(( (RANDOM % 40) + 20 ))); do
                    printf -v _m_char '%b' "\\$(printf '%03o' $(( RANDOM % 94 + 33 )))"
                    _m_line+="$_m_char"
                done
                printf "  \033[38;5;46m%s\033[0m\n" "$_m_line"
            done
            printf "\n  \033[38;5;46mWake up, Neo...\033[0m\n"
            printf "  \033[38;5;59m(The apt repository has you.)\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /potato ]]; then
            printf "\n  \033[38;5;136m"
            printf "       ___\n"
            printf "      /   \\\n"
            printf "     / o o \\\n"
            printf "    (   >   )\n"
            printf "     \\  =  /\n"
            printf "      \\___/\n"
            printf "        |\n"
            printf "       /|\\\n"
            printf "      / | \\\n"
            printf "\033[0m"
            printf "  \033[38;5;136mThis is not a potato. This is a random thingie. Ignore it and go back to installing packages.\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /ping ]]; then
            local _pings=("Pong!" "Pang!" "Pung!" "Ping!" "Poing!" "Piiiing!")
            printf "\n  \033[38;5;117m%s\033[0m\n" "${_pings[$((RANDOM % ${#_pings[@]} + 1))]}"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /beer ]]; then
            printf "\n  \033[38;5;214m"
            printf "          . .\n"
            printf "       .. . *.\n"
            printf " - -_ _-__-0oOo\n"
            printf " _-_ -__ -||||)\n"
            printf "    ______||||______\n"
            printf "~~~~~~~~~~\`\"'<\n"
            printf "\033[0m"
            printf "  \033[38;5;214mHere's a cold one. You've earned it.\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == "/rm -rf /" ]]; then
            printf "\n  \033[38;5;196mNice try. This is a package manager, not a thermonuclear device.\033[0m\n"
            printf "  \033[38;5;59mAlso, even if it were, we'd never.\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /hello || "$query" == /hi ]]; then
            local _greetings=("Hey there!" "Yo!" "Sup!" "Howdy!" "Bonjour!" "Konnichiwa!" "Ahoy!" "Greetings, human.")
            printf "\n  \033[38;5;123m%s\033[0m\n" "${_greetings[$((RANDOM % ${#_greetings[@]} + 1))]}"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /uptime ]]; then
            local _up
            _up=$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up/up/')
            printf "\n  \033[38;5;109m%s\033[0m\n" "$_up"
            printf "  \033[38;5;59m(But really, have you tried turning it off and on again?)\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi
        if [[ "$query" == /sudo ]]; then
            printf "\n  \033[38;5;196mThis is not the sudo you're looking for.\033[0m\n"
            printf "  \033[38;5;59m(There is no sudo in Termux. There is no spoon either.)\033[0m\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        if [[ "$query" == /theme || "$query" == /theme\ * ]]; then
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
                chosen_theme=$(printf '%s\n' "${theme_list[@]}" | fzf --prompt=" Theme> " --preview='echo "Preview: {}"' --height=50% --reverse | sed 's/\o033\[[0-9;]*m//g')
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
            _pkgs_check_network || { query=""; continue; }
            printf "\n${C_MSG_WARN}Upgrade all installed packages? (y/N) ${C_RESET}"
            read -q upgrade_confirm; read -r
            if [[ "$upgrade_confirm" != "y" ]]; then
                printf "${C_DIM}Cancelled.${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                clear
                continue
            fi
            printf "\n${C_MSG_INFO}─── Upgrading all packages... ───${C_RESET}\n\n"
            local _up_log
            _up_log=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_up.XXXXXX") 2>/dev/null
            "${PKG_MGR}" upgrade -- &>"$_up_log" &
            local _up_pid=$!
            _pkgs_spinner "$_up_pid" "Upgrading packages..."
            wait "$_up_pid" 2>/dev/null
            local _up_rc=$?
            rm -f "$_up_log" 2>/dev/null
            if (( _up_rc == 0 )); then
                _pkgs_log_history "UPGRADE" "all"
                printf "\n${C_MSG_DONE}─── Upgrade completed successfully ───${C_RESET}\n"
            else
                printf "\n${C_MSG_REMOVE}─── Upgrade encountered errors ───${C_RESET}\n"
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
                    printf "\n  ${C_GREEN}Files installed by %s (%s)${C_RESET}\n\n" "$usage_pkg" "$usage_display"
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
                printf "\n  ${C_GREEN}Disk Usage by Section${C_RESET}\n\n"
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
                printf "\n${C_MSG_INFO}─── Dependencies of %s ───${C_RESET}\n\n" "$deps_pkg"
                local deps_out
                deps_out=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$deps_pkg" 2>/dev/null | grep "Depends:" | sed 's/.*Depends: //' | tr -d '<>' | awk '{print $1}' | sort -u)
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
                printf "\n${C_MSG_INFO}─── Dependency tree for %s ───${C_RESET}\n\n" "$tree_pkg"
                local tree_output
                tree_output=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$tree_pkg" 2>/dev/null)
                print -r -- "$tree_output" | head -50
                local total_deps
                total_deps=$(print -r -- "$tree_output" | grep "Depends:" | sed 's/.*Depends: //' | tr -d '<>' | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
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
            printf "\n${C_MSG_INFO}─── Orphaned Packages (auto-installed, no dependents) ───${C_RESET}\n\n"
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
            printf "\n${C_MSG_INFO}Top %d Largest Installed Packages${C_RESET}\n\n" "$top_n"
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
            printf "\n${C_MSG_INFO}─── Total Installed Size ───${C_RESET}\n\n"
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
            printf "\n${C_MSG_INFO}─── Package Counts ───${C_RESET}\n\n"
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
            _pkgs_check_network || { query=""; continue; }
            printf "\n${C_MSG_INFO}─── Updating package cache... ───${C_RESET}\n\n"
            local _upd_log
            _upd_log=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_upd.XXXXXX") 2>/dev/null
            "${PKG_MGR}" update &>"$_upd_log" &
            local _upd_pid=$!
            _pkgs_spinner "$_upd_pid" "Updating package cache..."
            wait "$_upd_pid" 2>/dev/null
            local _upd_rc=$?
            rm -f "$_upd_log" 2>/dev/null
            if (( _upd_rc == 0 )); then
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
            local export_all_file="pkg-export-all-$(date +%Y%m%d-%H%M%S%N).sh"
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
                    printf "%s install \\\\\n" "$PKG_MGR"
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
            chmod 700 "$export_all_file" 2>/dev/null
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
                    printf "\n  ${C_GREEN}Package Notes${C_RESET}\n\n"
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
                note_text="${note_text//$'\n'/ }"
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
                    tmp_notes=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_notes.XXXXXX") 2>/dev/null
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

        if [[ "$query" == /backup ]]; then
            clear
            local backup_file="pkg-backup-$(date +%Y%m%d-%H%M%S%N).txt"
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
                rline="${${rline#"${rline%%[![:space:]]*}"}%"${rline##*[![:space:]]}"}"
                rline="${rline%%\\}"
                rline="${${rline#"${rline%%[![:space:]]*}"}%"${rline##*[![:space:]]}"}"
                [[ -z "$rline" ]] && continue
                [[ "$rline" == \#* ]] && continue
                [[ "$rline" == "install "* || "$rline" == "pkg install "* ]] && continue
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
            printf "\n  ${C_GREEN}Restore from ${C_WHITE}%s${C_GREEN}${C_RESET}\n\n" "$restore_file"
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
            _pkgs_validate_name "$lpkg" || { printf "\n  ${C_MSG_REMOVE}Invalid package in history.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
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
            if [[ "${_PKGS_BACK_ACTION:-0}" == "1" ]]; then
                _PKGS_BACK_ACTION=0
                query="$info_pkg"
            else
                query=""
            fi
            continue
        fi

        if [[ "$query" == /clean ]]; then
            clear
            printf "\n${C_MSG_INFO}─── Cleaning apt cache and unused dependencies ───${C_RESET}\n\n"
            printf "${C_MSG_WARN}Run autoremove + clean? (y/N) ${C_RESET}"
            read -q confirm; read -r
            if [[ "$confirm" == "y" ]]; then
                "${PKG_MGR}" clean 2>/dev/null
                printf "${C_MSG_DONE}Cache cleaned.${C_RESET}\n"
                local autoremove_out
                if ! autoremove_out=$(apt-get autoremove --dry-run 2>&1); then
                    printf "${C_MSG_WARN}Could not check dependencies: %s${C_RESET}\n" "$autoremove_out"
                elif LANG=C echo "$autoremove_out" | grep -qE "^0 upgraded, 0 newly installed, 0 to remove"; then
                    printf "${C_MSG_DONE}Nothing to remove.${C_RESET}\n"
                else
                    apt-get autoremove -y 2>/dev/null
                    printf "${C_MSG_DONE}Unused dependencies removed.${C_RESET}\n"
                fi
                _pkgs_log_history "CLEAN" "autoremove+cache"
            else
                printf "${C_DIM}Cancelled.${C_RESET}\n"
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
                    if apt-get purge -- "$purge_pkg" 2>/dev/null; then
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
                if apt-mark hold "$hold_pkg" 2>/dev/null; then
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
                if apt-mark unhold "$unhold_pkg" 2>/dev/null; then
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

        if [[ "$query" == /depends-on* && "$query" != /depends-on-list* && "$query" != /depends-chain* ]]; then
            local depson_pkg; depson_pkg=$(_pkgs_parse_pkg_arg "depends-on" "$query") || { sleep 1; query=""; continue; }
            clear
            if ! apt-cache show -- "$depson_pkg" >/dev/null 2>&1; then
                printf "${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$depson_pkg"
            else
                printf "\n${C_MSG_INFO}─── Installed packages that depend on %s ───${C_RESET}\n\n" "$depson_pkg"
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
            printf "\n${C_MSG_INFO}─── Outdated Packages (updates available) ───${C_RESET}\n\n"
            local outdated_count=0
            # Bulk: get all installed packages, then batch apt-cache policy
            local -a all_pkgs=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && all_pkgs+=("$line")
            done < <(dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null)
            # Single apt-cache policy call for all packages
            local bulk_out
            bulk_out=$(_pkgs_bulk_apt_policy "${all_pkgs[@]}" 2>/dev/null)
            while read -r opkg oinst_ver ocand_ver; do
                [[ -z "$opkg" ]] && continue
                printf "  ${C_WHITE}%-28s${C_RESET} ${C_DIM}%-16s${C_RESET} ${C_GREEN}%s${C_RESET}\n" "$opkg" "$oinst_ver" "$ocand_ver"
                ((outdated_count++))
            done <<< "$bulk_out"
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
            printf "\n${C_MSG_INFO}─── Orphaned Packages (safe to remove) ───${C_RESET}\n\n"
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
            printf "\n  ${C_GREEN}Review ($(date +%Y-%m-%d))${C_RESET}\n\n"
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
            printf "\n  ${C_GREEN}Stats ($(date +%Y-%m-%d))${C_RESET}\n\n"
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
            local hist_days="${_PKGS_HISTORY_KEEP_DAYS:-7}"
            (( hist_days < 7 )) && hist_days=7
            printf "\n  ${C_GREEN}Command History (last %d days)${C_RESET}\n\n" "$hist_days"
            local hist_found=0
            local hist_day
            for i in $(seq 0 $((hist_days - 1))); do
                hist_day=$(_pkgs_date_ago "$i")
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
                printf "\n${C_MSG_INFO}Changelog for %s${C_RESET}\n\n" "$cl_pkg"
                local cl_file="${PREFIX}/share/doc/${cl_pkg}/changelog.gz"
                local cl_file2="${PREFIX}/share/doc/${cl_pkg}/changelog"
                if [[ -f "$cl_file" ]] && command -v zcat &>/dev/null; then
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
            printf "\n${C_MSG_INFO}Removing Orphaned Packages${C_RESET}\n\n"
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
                    if apt-get autoremove -y 2>/dev/null; then
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
            printf "\n  ${C_GREEN}System Info${C_RESET}\n\n"
            printf "  ${C_WHITE}pkgs:${C_RESET}          %s\n" "$_PKGS_VERSION"
            printf "  ${C_WHITE}Termux:${C_RESET}        %s\n" "${TERMUX_VERSION:-unknown}"
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
                clear
                query=""
                continue
            fi
            clear
            printf "\n${C_MSG_INFO}Searching installed files for \"%s\"...${C_RESET}\n\n" "$sf_text"
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
                printf "\n  ${C_GREEN}Download Size: %s${C_RESET}\n\n" "$ds_pkg"
                printf "  ${C_WHITE}Version:${C_RESET}      %s\n" "${ds_ver:-unknown}"
                if (( _HAS_NUMFMT )); then
                    printf "  ${C_WHITE}Download:${C_RESET}     %s\n" "$(printf "%s" "$(( ${ds_dl:-0} * 1 ))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${ds_dl:-0} B")"
                    printf "  ${C_WHITE}Installed:${C_RESET}    %s\n" "$(printf "%s" "$(( ${ds_inst:-0} * 1024 ))" | numfmt --to=iec --suffix=B 2>/dev/null || echo "${ds_inst:-0} KiB")"
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
            printf "\n${C_MSG_INFO}Checking installed packages...${C_RESET}\n\n"
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
                printf "\n  ${C_MSG_WARN}Run ${C_TEAL}%s --fix-broken install${C_MSG_WARN} to repair${C_RESET}\n" "$PKG_MGR"
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
            printf "\n${C_MSG_INFO}Packages by Section${C_RESET}\n\n"
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
            printf "\n${C_MSG_INFO}Top %d Outdated Packages (by installed size)${C_RESET}\n\n" "$ot_n"
            local ot_tmp ot_count=0
            ot_tmp=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_ot.XXXXXX") 2>/dev/null
            if [[ -n "$ot_tmp" ]]; then
                dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' 2>/dev/null | while IFS=$'\t' read -r pname pver psiz; do
                    [[ -z "$pname" || -z "$psiz" || "$psiz" == "*" ]] && continue
                    cver=$(apt-cache policy -- "$pname" 2>/dev/null | grep 'Candidate:' | head -1 | sed 's/^.*Candidate: //')
                    [[ -n "$cver" && "$pver" != "$cver" ]] && printf "%s\t%s\t%s\t%s\n" "$pname" "$pver" "$cver" "$psiz"
                done | sort -t$'\t' -k4 -rn > "$ot_tmp"
                while IFS=$'\t' read -r opkg oinst_ver ocand_ver _osiz; do
                    [[ -z "$opkg" ]] && continue
                    [[ $ot_count -ge $ot_n ]] && break
                    ((ot_count++))
                    printf "  ${C_WHITE}%-4s${C_RESET} ${C_TEAL}%-24s${C_RESET} ${C_DIM}%-16s${C_RESET} ${C_GREEN}%s${C_RESET}\n" \
                        "$ot_count" "$opkg" "$oinst_ver" "$ocand_ver"
                done < "$ot_tmp"
                rm -f "$ot_tmp" 2>/dev/null
            fi
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
            printf "\n${C_MSG_INFO}Top %d Packages by Disk Usage${C_RESET}\n\n" "$ut_n"
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
            local ut_cols
            ut_cols=$(tput cols 2>/dev/null) || ut_cols=80
            local ut_overhead=38
            local ut_max_bar=$(( ut_cols - ut_overhead ))
            (( ut_max_bar < 5 )) && ut_max_bar=5
            (( ut_max_bar > 50 )) && ut_max_bar=50
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

        if [[ "$query" == /search* && "$query" != /search-file* && "$query" != /search-size* && "$query" != /search-providers* && "$query" != /search-history* ]]; then
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
            printf "\n${C_MSG_INFO}─── Searching descriptions for \"%s\"... ───${C_RESET}\n\n" "$search_text"
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
                printf "\n${C_MSG_INFO}─── Reverse dependencies of %s ───${C_RESET}\n\n" "$rdeps_pkg"
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

        if [[ "$query" == /install* || "$query" == /remove* || "$query" == /export || "$query" == /export\ * ]]; then
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
                printf "\n${C_MSG_REMOVE}─── No packages matching \"%s\" ───${C_RESET}\n\n" "$search_term"
                continue
            fi

            case "$cmd" in
                install|remove)
                    clear
                    printf "\n  ${C_MSG_INFO}%s: %d package(s) matched${C_RESET}\n" "${cmd:u}" "${#match_pkgs[@]}"
                    local _i
                    for _i in {1..${#match_pkgs[@]}}; do
                        printf "    ${C_WHITE}%s${C_RESET}\n" "${match_pkgs[$_i]}"
                    done
                    printf "\n  ${C_DIM}Estimating download size...${C_RESET}\n"
                    local _est_total_dl=0 _est_total_inst=0 _est_p
                    for _est_p in "${match_pkgs[@]}"; do
                        local _est_info _est_dl _est_ins
                        _est_info=$(apt-cache show -- "$_est_p" 2>/dev/null)
                        _est_dl=$(_pkgs_apt_field "$_est_info" Size)
                        _est_ins=$(_pkgs_apt_field "$_est_info" Installed-Size)
                        [[ "$_est_dl" =~ ^[0-9]+$ ]] && (( _est_total_dl += _est_dl ))
                        [[ "$_est_ins" =~ ^[0-9]+$ ]] && (( _est_total_inst += _est_ins ))
                    done
                    if (( _est_total_dl > 0 || _est_total_inst > 0 )); then
                        printf "  ${C_DIM}Download: %s  Install: %s  Total: ~%s${C_RESET}\n" \
                            "$(_pkgs_format_size $(( _est_total_dl / 1024 )))" \
                            "$(_pkgs_format_size $(( _est_total_inst )))" \
                            "$(_pkgs_format_size $(( (_est_total_dl / 1024) + _est_total_inst )))"
                    fi
                    printf "\n  ${C_MSG_INFO}Proceed with %s? ${C_DIM}(y=dry-run, d=process, e=export, Enter=cancel)${C_RESET} " "${cmd}"
                    local batch_choice
                    read -q batch_choice; read -r
                    if [[ "$batch_choice" == "y" ]]; then
                        printf "\n${C_MSG_INFO}─── Dry run: ${cmd} ───${C_RESET}\n"
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
                            chmod 700 "$export_file" 2>/dev/null
                            printf "\n${C_MSG_DONE}Exported %d packages to: %s${C_RESET}\n" "${#match_pkgs[@]}" "$export_file"
                        else
                            printf "${C_MSG_REMOVE}─── Invalid or unsafe file path ───${C_RESET}\n"
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
                                printf "%s install \\\\\n" "$PKG_MGR"
                                local i
                                for i in {1..${#match_pkgs[@]}}; do
                                    if (( i < ${#match_pkgs[@]} )); then
                                        printf "    %s \\\\\n" "${match_pkgs[$i]}"
                                    else
                                        printf "    %s\n" "${match_pkgs[$i]}"
                                    fi
                                done
                            } > "$export_file"
                            chmod 700 "$export_file" 2>/dev/null
                            if [[ -f "$export_file" ]]; then
                                printf "\n${C_MSG_INFO}─── Saved: ${C_RESET}%s${C_MSG_INFO} ───${C_RESET}\n" "$export_file"
                            else
                                printf "${C_MSG_REMOVE}─── Failed to create export file ───${C_RESET}\n"
                            fi
                        else
                            printf "${C_MSG_REMOVE}─── Invalid file path ───${C_RESET}\n"
                        fi
                    else
                        printf "${C_MSG_REMOVE}─── Invalid or unsafe file path ───${C_RESET}\n"
                    fi
                    printf "\n"
                    ;;
            esac
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            continue
        fi

        # ─── /mirror ───
        if [[ "$query" == /mirror ]]; then
            clear
            local mirror_base="${PREFIX}/etc/termux/mirrors"
            if [[ ! -d "$mirror_base" ]]; then
                printf "\n  ${C_MSG_REMOVE}Mirror directory not found.${C_RESET}\n"
                printf "  ${C_MSG_WARN}Install termux-tools: pkg install termux-tools${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                continue
            fi
            local -a mirror_files=()
            local -a mirror_display=()
            local -A mirror_desc_map
            local -A mirror_region_map
            local region_dir
            for region_dir in "$mirror_base"/*/; do
                [[ ! -d "$region_dir" ]] && continue
                local region_name
                region_name=$(basename "$region_dir")
                local mf
                for mf in "$region_dir"/*; do
                    [[ ! -f "$mf" ]] && continue
                    [[ "$mf" == *.dpkg-old || "$mf" == *.dpkg-new || "$mf" == *~ ]] && continue
                    local murl mdesc
                    murl=$(basename "$mf")
                    mdesc=$(sed -n '2s/^# *//p' "$mf" 2>/dev/null)
                    [[ -z "$mdesc" ]] && mdesc="$murl"
                    local display_line="${mdesc} [${region_name}] (${murl})"
                    mirror_files+=("$mf")
                    mirror_display+=("$display_line")
                    mirror_desc_map["$display_line"]="$mf"
                    mirror_region_map["$display_line"]="$region_name"
                done
            done
            if [[ ${#mirror_files[@]} -eq 0 ]]; then
                printf "\n  ${C_MSG_REMOVE}No mirror definitions found.${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                continue
            fi
            local current_target
            current_target=$(readlink -f "$mirror_base/../chosen_mirrors" 2>/dev/null || echo "")
            local chosen
            chosen=$(printf '%s\n' "${mirror_display[@]}" | fzf --prompt=" Mirror> " --height=80% --reverse | sed 's/\o033\[[0-9;]*m//g')
            if [[ -z "$chosen" ]]; then
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                continue
            fi
            local selected_file="${mirror_desc_map[$chosen]}"
            local selected_region="${mirror_region_map[$chosen]}"
            printf "\n  ${C_WHITE}Selected:${C_RESET} %s\n" "$chosen"
            printf "\n  ${C_MSG_WARN}Apply this mirror? (y/N) ${C_RESET}"
            read -q confirm; read -r
            if [[ "$confirm" == "y" ]]; then
                if ln -sf "$selected_file" "${PREFIX}/etc/termux/chosen_mirrors" 2>/dev/null; then
                    printf "\n  ${C_MSG_DONE}Mirror set to: %s${C_RESET}\n" "$(basename "$selected_file")"
                    _pkgs_log_history "MIRROR" "$(basename "$selected_file")"
                else
                    printf "\n  ${C_MSG_REMOVE}Failed to update mirror symlink.${C_RESET}\n"
                    printf "  ${C_MSG_WARN}Run: termux-change-repo${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /fav ───
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
                    chosen_fav=$(cat "$_PKGS_FAVORITES_FILE" | fzf --prompt=" Remove favorite> " --height=50% --reverse | sed 's/\o033\[[0-9;]*m//g')
                    [[ -n "$chosen_fav" ]] && fav_rm_pkg="$chosen_fav"
                fi
            else
                _pkgs_validate_name "$fav_rm_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$fav_rm_pkg" ]]; then
                mkdir -p "$(dirname "$_PKGS_FAVORITES_FILE")" 2>/dev/null
                if grep -Fqx "$fav_rm_pkg" "$_PKGS_FAVORITES_FILE" 2>/dev/null; then
                    local fav_tmp
                    fav_tmp=$(mktemp "${_PKGS_FAVORITES_FILE}.XXXXXX") 2>/dev/null
                    if [[ -n "$fav_tmp" ]]; then
                        grep -vxF "$fav_rm_pkg" "$_PKGS_FAVORITES_FILE" > "$fav_tmp" && mv "$fav_tmp" "$_PKGS_FAVORITES_FILE"
                    fi
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
                _pkgs_fzf_pick_pkg "Add favorite"; fav_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$fav_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$fav_pkg" ]]; then
                mkdir -p "$(dirname "$_PKGS_FAVORITES_FILE")" 2>/dev/null
                touch "$_PKGS_FAVORITES_FILE"
                if grep -Fqx "$fav_pkg" "$_PKGS_FAVORITES_FILE" 2>/dev/null; then
                    local fav_toggle_tmp
                    fav_toggle_tmp=$(mktemp "${_PKGS_FAVORITES_FILE}.XXXXXX") 2>/dev/null
                    if [[ -n "$fav_toggle_tmp" ]]; then
                        grep -vxF "$fav_pkg" "$_PKGS_FAVORITES_FILE" > "$fav_toggle_tmp" && mv "$fav_toggle_tmp" "$_PKGS_FAVORITES_FILE"
                    fi
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

        # ─── /import ───
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
                    line="${line##[[:space:]]}"
                    line="${line%%[[:space:]]}"
                    [[ -z "$line" ]] && continue
                    _pkgs_validate_name "$line" || continue
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

        # ─── /why ───
        if [[ "$query" == /why* ]]; then
            local why_pkg="${query#/why }"
            [[ "$why_pkg" == "/why" ]] && why_pkg=""
            clear
            if [[ -z "$why_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Why installed"; why_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$why_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
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

        # ─── /nuke ───
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
            if [[ -d "$HOME/.cache/termux" ]]; then
                cache_size=$(du -sk "$HOME/.cache/termux" 2>/dev/null | awk '{print $1}')
                if (( cache_size > 0 )); then
                    printf "  ${C_TEAL}[C]${C_RESET} ~/.cache/termux:         %s\n" "$(_pkgs_format_size "$cache_size")"
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
                [[ "$ps" =~ ^[0-9]+$ ]] && orphan_size=$((orphan_size + ps))
                orphans+=("$pkg")
            done < <(apt-get autoremove --dry-run 2>&1 | sed -n 's/.*[^a-zA-Z0-9.+-]\([a-z][a-z0-9.+-]*\).*/\1/p' | sort -u)
            if (( orphan_size > 0 )); then
                printf "  ${C_TEAL}[E]${C_RESET} orphaned packages:     %s (%d pkgs)\n" "$(_pkgs_format_size "$orphan_size")" "${#orphans[@]}"
                nuke_items+=("orphans:$orphan_size")
            fi
            local pyc_size=0
            local pyc_count=0
            if [[ -d "$HOME" ]]; then
                local pyc_stats
                pyc_stats=$(find "$HOME" -maxdepth 6 -name "*.pyc" -type f -exec du -sk {} + 2>/dev/null | awk '{s+=$1;c++}END{print c+0" "s+0}')
                pyc_count=${pyc_stats%% *}
                pyc_size=${pyc_stats##* }
                if (( pyc_count > 0 )); then
                    printf "  ${C_TEAL}[F]${C_RESET} .pyc files:             %s (%d files)\n" "$(_pkgs_format_size "$pyc_size")" "$pyc_count"
                    nuke_items+=("pyc:$pyc_size")
                fi
            fi
            local o_size=0
            local o_count=0
            if [[ -d "$HOME" ]]; then
                local o_stats
                o_stats=$(find "$HOME" -maxdepth 6 -name "*.o" -type f -exec du -sk {} + 2>/dev/null | awk '{s+=$1;c++}END{print c+0" "s+0}')
                o_count=${o_stats%% *}
                o_size=${o_stats##* }
                if (( o_count > 0 )); then
                    printf "  ${C_TEAL}[G]${C_RESET} .o files:               %s (%d files)\n" "$(_pkgs_format_size "$o_size")" "$o_count"
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
                printf "\n  ${C_MSG_WARN}This will scan \$HOME (maxdepth 6) for .pyc and .o files.${C_RESET}\n"
                printf "  ${C_MSG_WARN}Clean all? (y/N) ${C_RESET}"
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
                                [[ -n "$PREFIX" ]] && rm -rf "${PREFIX}/tmp"/* 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ tmp cleaned${C_RESET}\n"
                                ;;
                            cache)
                                rm -rf "$HOME/.cache/termux" 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ ~/.cache/termux cleaned${C_RESET}\n"
                                ;;
                            history)
                                find "$_PKGS_HISTORY_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ old history logs removed${C_RESET}\n"
                                ;;
                            orphans)
                                apt-get autoremove -y 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ orphans removed${C_RESET}\n"
                                ;;
                            pyc)
                                find "$HOME" -maxdepth 6 -name "*.pyc" -type f -delete 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ .pyc files removed${C_RESET}\n"
                                ;;
                            obj)
                                find "$HOME" -maxdepth 6 -name "*.o" -type f -delete 2>/dev/null
                                printf "  ${C_MSG_DONE}✓ .o files removed${C_RESET}\n"
                                ;;
                            trash)
                                if [[ -d "$HOME/.Trash" ]]; then
                                    rm -rf "$HOME/.Trash"/* 2>/dev/null
                                fi
                                printf "  ${C_MSG_DONE}✓ ~/.Trash contents removed${C_RESET}\n"
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

        # ─── /whatsnew ───
        if [[ "$query" == /whatsnew ]]; then
            clear
            printf "\n  ${C_WHITE}Recently Upgraded Packages${C_RESET}\n\n"
            local -a recent_upgraded=()
            if [[ -f "$_PKGS_HISTORY_FILE" ]]; then
                while IFS=' ' read -r ts action pkg; do
                    [[ "$action" == "UPGRADE" ]] && recent_upgraded+=("$pkg")
                done < "$_PKGS_HISTORY_FILE"
            fi
            while IFS= read -r hist_file; do
                [[ -n "$hist_file" ]] || continue
                while IFS=' ' read -r ts action pkg; do
                    [[ "$action" == "UPGRADE" ]] && recent_upgraded+=("$pkg")
                done < "$hist_file"
            done < <(find "$_PKGS_HISTORY_DIR" -name "*.log" -mtime -7 2>/dev/null | sort -r | head -7)
            local -A seen_pkgs
            local -a unique_pkgs=()
            for p in "${recent_upgraded[@]}"; do
                [[ -z "${seen_pkgs[$p]}" ]] && { seen_pkgs[$p]=1; unique_pkgs+=("$p"); }
            done
            if (( ${#unique_pkgs[@]} == 0 )); then
                printf "  ${C_DIM}No recent upgrades found in history.${C_RESET}\n"
            else
                for cl_pkg in "${unique_pkgs[@]}"; do
                    printf "  ${C_WHITE}%s${C_RESET}\n" "$cl_pkg"
                    _pkgs_validate_name "$cl_pkg" || continue
                    local cl_file="${PREFIX}/share/doc/${cl_pkg}/changelog"
                    local cl_gz="${cl_file}.gz"
                    if [[ -f "$cl_gz" ]] && command -v gunzip &>/dev/null; then
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

        # ─── /tips ───
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

        # ─── /self-update ───
        if [[ "$query" == /self-update ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Checking for updates...${C_RESET}\n"
            local current_ver="$_PKGS_VERSION"
            local latest_ver
            latest_ver=$(curl -sL "$_PKGS_SELF_URL" 2>/dev/null | sed -n 's/.*pkgs \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
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
                    local tmp_file
                    tmp_file=$(mktemp "${target}.XXXXXX") || { printf "\n  ${C_MSG_REMOVE}Failed to create temp file.${C_RESET}\n"; query=""; continue; }
                    if curl -fsSL "$_PKGS_SELF_URL" -o "$tmp_file" 2>/dev/null && head -1 "$tmp_file" | grep -q '^#!/'; then
                        chmod +x "$tmp_file"
                        local bak_file="${target}.bak"
                        [[ -f "$bak_file" ]] && rm -f "$bak_file" 2>/dev/null
                        mv "$target" "$bak_file" 2>/dev/null
                        mv "$tmp_file" "$target"
                        printf "\n  ${C_MSG_DONE}Updated to v%s! Restart pkgs to use.${C_RESET}\n" "$latest_ver"
                    else
                        rm -f "$tmp_file" 2>/dev/null
                        printf "\n  ${C_MSG_REMOVE}Download failed or file invalid.${C_RESET}\n"
                    fi
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /search-size ───
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
            while IFS=$'\t' read -r pkg size; do
                [[ -z "$size" || "$size" == "*" ]] && continue
                if (( size >= ss_min && size <= ss_max )); then
                    local status="${C_GREEN}installed${C_RESET}"
                    local sz_display
                    sz_display=$(_pkgs_format_size "$size")
                    printf "  %-30s %-12s %s\n" "$pkg" "$sz_display" "$status"
                    ((ss_count++))
                fi
            done < <(dpkg-query -W -f='${Package}\t${Installed-Size}\n' 2>/dev/null)
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /pkg-history ───
        if [[ "$query" == /pkg-history* ]]; then
            local ph_pkg="${query#/pkg-history }"
            [[ "$ph_pkg" == "/pkg-history" ]] && ph_pkg=""
            clear
            if [[ -z "$ph_pkg" ]]; then
                _pkgs_fzf_pick_pkg "History for"; ph_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$ph_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$ph_pkg" ]]; then
                printf "\n  ${C_WHITE}History for %s:${C_RESET}\n\n" "$ph_pkg"
                local found=0
                while IFS= read -r hist_file; do
                    [[ -n "$hist_file" ]] || continue
                    while IFS=' ' read -r ts action pkg; do
                        if [[ "$pkg" == "$ph_pkg" ]]; then
                            printf "  ${C_DIM}%s${C_RESET}  %s%s%s\n" "$ts" "$C_MSG_DONE" "$action" "$C_RESET"
                            ((found++))
                        fi
                    done < "$hist_file"
                done < <(find "$_PKGS_HISTORY_DIR" -name "*.log" 2>/dev/null | sort -r)
                if (( found == 0 )); then
                    printf "  ${C_DIM}No history entries found for %s.${C_RESET}\n" "$ph_pkg"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /depends-chain ───
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
                _pkgs_fzf_pick_pkg "Package A"; dc_a=$_PKGS_FZF_PICKED
                if [[ -z "$dc_a" ]]; then
                    printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                    read -r
                    continue
                fi
                printf "\n  ${C_MSG_INFO}Select second package:${C_RESET}\n"
                _pkgs_fzf_pick_pkg "Package B"; dc_b=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$dc_a" || { printf "  ${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$dc_a"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
                _pkgs_validate_name "$dc_b" || { printf "  ${C_MSG_REMOVE}Invalid package name: %s${C_RESET}\n" "$dc_b"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$dc_a" && -n "$dc_b" ]]; then
                printf "\n  ${C_WHITE}Dependency chain: %s -> %s${C_RESET}\n\n" "$dc_a" "$dc_b"
                if apt-cache depends "$dc_a" 2>/dev/null | grep -qF -- "$dc_b"; then
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
                        for d in ${(f)deps}; do
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

        # ─── /broken ───
        if [[ "$query" == /broken ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Checking for broken packages...${C_RESET}\n\n"
            local broken_count=0
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                printf "  ${C_RED}✗ %s${C_RESET}\n" "$line"
                ((broken_count++))
            done < <(dpkg --audit 2>/dev/null)
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

        # ─── /conflicts-with ───
        if [[ "$query" == /conflicts-with* ]]; then
            local cw_pkg="${query#/conflicts-with }"
            [[ "$cw_pkg" == "/conflicts-with" ]] && cw_pkg=""
            clear
            if [[ -z "$cw_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Conflicts for"; cw_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$cw_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
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

        # ─── /provides ───
        if [[ "$query" == /provides* ]]; then
            local pv_pkg="${query#/provides }"
            [[ "$pv_pkg" == "/provides" ]] && pv_pkg=""
            clear
            if [[ -z "$pv_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Provides for"; pv_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$pv_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
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

        # ─── /manually-installed ───
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
            # Bulk: single dpkg-query for all sizes
            local -A size_map=()
            local bulk_sizes
            bulk_sizes=$(_pkgs_bulk_dpkg_size "${manual_pkgs[@]}" 2>/dev/null)
            while read -r spkg ssize; do
                [[ -n "$spkg" ]] && size_map["$spkg"]="$ssize"
            done <<< "$bulk_sizes"
            # Bulk: single apt-cache show for all sections
            local -A section_map=()
            local bulk_sections
            bulk_sections=$(apt-cache show -- "${manual_pkgs[@]}" 2>/dev/null | awk '
                /^Package:/ { pkg = $2 }
                /^Section:/ { if (pkg != "") section[pkg] = $2 }
                END { for (p in section) print p, section[p] }
            ')
            while read -r spkg ssec; do
                [[ -n "$spkg" ]] && section_map["$spkg"]="$ssec"
            done <<< "$bulk_sections"
            for pkg in "${manual_pkgs[@]}"; do
                printf "  ${C_GREEN}%-30s${C_RESET} %-12s %s\n" "$pkg" "$(_pkgs_format_size "${size_map[$pkg]:-0}")" "${section_map[$pkg]:---}"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /auto-installed ───
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
            # Bulk: single dpkg-query for all sizes
            local -A auto_size_map=()
            local bulk_sizes
            bulk_sizes=$(_pkgs_bulk_dpkg_size "${auto_pkgs[@]}" 2>/dev/null)
            while read -r spkg ssize; do
                [[ -n "$spkg" ]] && auto_size_map["$spkg"]="$ssize"
            done <<< "$bulk_sizes"
            # Bulk: single apt-cache rdepends for all packages
            local -A auto_parent_map=()
            local bulk_rdeps
            bulk_rdeps=$(apt-cache rdepends --installed -- "${auto_pkgs[@]}" 2>/dev/null | awk '
                /^Package:/ { pkg = $2; next }
                /^[^ ]/ { next }
                { if (pkg != "" && parent == "") { parent = $1 } }
                /^$/ { if (pkg != "") { print pkg, parent; pkg=""; parent="" } }
                END { if (pkg != "") print pkg, parent }
            ')
            while read -r spkg sparent; do
                [[ -n "$spkg" ]] && auto_parent_map["$spkg"]="$sparent"
            done <<< "$bulk_rdeps"
            local shown=0
            for pkg in "${auto_pkgs[@]}"; do
                ((shown++))
                (( shown > 100 )) && { printf "\n  ${C_DIM}... and %d more${C_RESET}\n" "$((${#auto_pkgs[@]} - 100))"; break; }
                printf "  %-30s %-12s ${C_DIM}%s${C_RESET}\n" "$pkg" "$(_pkgs_format_size "${auto_size_map[$pkg]:-0}")" "${auto_parent_map[$pkg]:---}"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /upgrade-plan ───
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

        # ─── /pkg-ages ───
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

        # ─── /unused-libs ───
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

        # ─── /maintainer ───
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
                apt-cache dump 2>/dev/null | awk -v query="$mt_query" '
                    /^Package:/ { pkg=$2 }
                    /^Maintainer:/ {
                        maint=substr($0, index($0,$2))
                        if (index(maint, query) > 0) {
                            printf "  %-30s %s\n", pkg, substr(maint,1,50)
                            count++
                            if (count >= 100) exit
                        }
                    }
                '
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /log-search ───
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
                    grep -B1 -A1 -i -F -- "$ls_query" "$apt_log" 2>/dev/null | head -80 | sed 's/^/  /'
                else
                    printf "  ${C_DIM}No apt history log found.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /mirror-backup ───
        if [[ "$query" == /mirror-backup ]]; then
            clear
            local src_list="${PREFIX}/etc/apt/sources.list"
            local backup_dir="${_PKGS_CONFIG_DIR}/mirror-backups"
            mkdir -p "$backup_dir" 2>/dev/null
            local -a mb_choices=("backup" "restore" "list")
            local mb_choice
            mb_choice=$(printf '%s\n' "${mb_choices[@]}" | fzf --prompt=" Mirror backup> " --height=30% --reverse | sed 's/\o033\[[0-9;]*m//g')
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
                    local -a backups=()
                    for f in "${backup_dir}"/sources.list.*(N); do [[ -f "$f" ]] && backups+=("$f"); done
                    backups=(${backups[@]:o})
                    if (( ${#backups[@]} == 0 )); then
                        printf "\n  ${C_MSG_WARN}No backups found.${C_RESET}\n"
                    else
                        local chosen_bak
                        chosen_bak=$(printf '%s\n' "${backups[@]}" | fzf --prompt=" Restore> " --height=50% --reverse | sed 's/\o033\[[0-9;]*m//g')
                        if [[ -n "$chosen_bak" ]]; then
                            cp "$chosen_bak" "$src_list"
                            printf "\n  ${C_MSG_DONE}Restored from: %s${C_RESET}\n" "$(basename "$chosen_bak")"
                        fi
                    fi
                    ;;
                list)
                    local -a backups=()
                    for f in "${backup_dir}"/sources.list.*(N); do [[ -f "$f" ]] && backups+=("$f"); done
                    backups=(${backups[@]:o})
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

        # ─── /size-histogram ───
        if [[ "$query" == /size-histogram ]]; then
            clear
            printf "\n  ${C_WHITE}Package Size Distribution${C_RESET}\n\n"
            local -a buckets=(0 0 0 0 0 0 0 0 0 0)
            local -a labels=("0-10K" "10-50K" "50-100K" "100-500K" "500K-1M" "1-5M" "5-10M" "10-50M" "50-100M" "100M+")
            while IFS= read -r size; do
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
            done < <(dpkg-query -W -f='${Installed-Size}\n' 2>/dev/null)
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
                printf "  ${C_DIM}%-10s${C_RESET} ${C_GREEN}%-40s${C_RESET} %d\n" "${labels[$i]}" "$bar" "$count"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /deptree ───
        if [[ "$query" == /deptree* ]]; then
            local dt_pkg="${query#/deptree }"
            [[ "$dt_pkg" == "/deptree" ]] && dt_pkg=""
            clear
            if [[ -z "$dt_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Dep tree for"; dt_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$dt_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$dt_pkg" ]]; then
                printf "\n  ${C_WHITE}Dependency tree: %s${C_RESET}\n\n" "$dt_pkg"
                local -A _pkgs_tree_seen=()
                _pkgs_tree_draw() {
                    local pkg="$1" prefix="$2" depth="$3"
                    (( depth > 8 )) && { printf "%s${C_DIM}... (max depth)${C_RESET}\n" "$prefix"; return; }
                    [[ -n "${_pkgs_tree_seen[$pkg]+x}" ]] && { printf "%s${C_DIM}... (cycle: %s)${C_RESET}\n" "$prefix" "$pkg"; return; }
                    _pkgs_tree_seen[$pkg]=1
                    local deps
                    deps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$pkg" 2>/dev/null | grep "Depends:" | sed 's/.*Depends: //' | tr -d '<>' | awk '{print $1}')
                    local first=1
                    for d in ${(f)deps}; do
                        if (( first )); then
                            printf "%s└── ${C_TEAL}%s${C_RESET}\n" "$prefix" "$d"
                            first=0
                        else
                            printf "%s├── ${C_TEAL}%s${C_RESET}\n" "$prefix" "$d"
                        fi
                        _pkgs_tree_draw "$d" "${prefix}│   " $((depth+1))
                    done
                }
                printf "  ${C_GREEN}%s${C_RESET}\n" "$dt_pkg"
                _pkgs_tree_draw "$dt_pkg" "  " 0
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return, b to go back: ${C_RESET}"
            read -r _dt_choice
            if [[ "$_dt_choice" == "b" ]]; then
                query="$dt_pkg"
            else
                query=""
            fi
            continue
        fi

        # ─── /reverse-tree ───
        if [[ "$query" == /reverse-tree* ]]; then
            local rt_pkg="${query#/reverse-tree }"
            [[ "$rt_pkg" == "/reverse-tree" ]] && rt_pkg=""
            clear
            if [[ -z "$rt_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Reverse tree for"; rt_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$rt_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$rt_pkg" ]]; then
                printf "\n  ${C_WHITE}Reverse dependency tree: %s${C_RESET}\n\n" "$rt_pkg"
                local -A _pkgs_rev_seen=()
                _pkgs_rev_tree_draw() {
                    local pkg="$1" prefix="$2" depth="$3"
                    (( depth > 8 )) && { printf "%s${C_DIM}... (max depth)${C_RESET}\n" "$prefix"; return; }
                    [[ -n "${_pkgs_rev_seen[$pkg]+x}" ]] && { printf "%s${C_DIM}... (cycle: %s)${C_RESET}\n" "$prefix" "$pkg"; return; }
                    _pkgs_rev_seen[$pkg]=1
                    local rdeps
                    rdeps=$(apt-cache rdepends --installed "$pkg" 2>/dev/null | tail -n +2 | grep -v "^$")
                    local first=1
                    for d in ${(f)rdeps}; do
                        [[ -z "$d" ]] && continue
                        local marker=""
                        dpkg -s -- "$d" 2>/dev/null | grep -q '^Status: install ok installed' && marker="${C_GREEN}*" || marker="${C_DIM}-"
                        printf "%s├── %s ${C_TEAL}%s${C_RESET}\n" "$prefix" "$marker" "$d"
                        _pkgs_rev_tree_draw "$d" "${prefix}│   " $((depth+1))
                    done
                }
                printf "  ${C_GREEN}%s${C_RESET} ${C_DIM}(*=installed)${C_RESET}\n" "$rt_pkg"
                _pkgs_rev_tree_draw "$rt_pkg" "  " 0
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /upgrade-size ───
        if [[ "$query" == /upgrade-size ]]; then
            clear
            printf "\n  ${C_MSG_INFO}Calculating upgrade download size...${C_RESET}\n\n"
            local us_out
            us_out=$("${PKG_MGR}" upgrade --dry-run 2>&1)
            local us_total
            us_total=$(echo "$us_out" | sed -n 's/.*Need to get \([0-9.]*[KMGT]*B\).*/\1/p' | head -1)
            local us_new us_upgrade us_remove
            us_new=$(echo "$us_out" | sed -n 's/.*\([0-9][0-9]*\) newly installed.*/\1/p')
            us_upgrade=$(echo "$us_out" | sed -n 's/.*\([0-9][0-9]*\) upgraded.*/\1/p')
            us_remove=$(echo "$us_out" | sed -n 's/.*\([0-9][0-9]*\) to remove.*/\1/p')
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

        # ─── /download ───
        if [[ "$query" == /download* && "$query" != /download-size* && "$query" != /download-est* ]]; then
            local dl_pkg="${query#/download }"
            [[ "$dl_pkg" == "/download" ]] && dl_pkg=""
            clear
            if [[ -z "$dl_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Download"; dl_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$dl_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$dl_pkg" ]]; then
                printf "\n  ${C_MSG_INFO}Downloading %s...${C_RESET}\n\n" "$dl_pkg"
                local dl_dir="${PREFIX}/tmp/pkgs-dl"
                mkdir -p "$dl_dir" 2>/dev/null
                (cd "$dl_dir" 2>/dev/null && apt-get download -- "$dl_pkg" 2>&1) | sed 's/^/  /'
                if ls "$dl_dir"/"$dl_pkg"*.deb 2>/dev/null | head -1 > /dev/null; then
                    printf "\n  ${C_MSG_DONE}Downloaded to:${C_RESET} %s\n" "$dl_dir"
                    ls -lh "$dl_dir"/"$dl_pkg"*.deb 2>/dev/null | sed 's/^/  /'
                else
                    printf "\n  ${C_MSG_REMOVE}Download failed.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /verify ───
        if [[ "$query" == /verify* ]]; then
            local vr_pkg="${query#/verify }"
            [[ "$vr_pkg" == "/verify" ]] && vr_pkg=""
            clear
            if [[ -z "$vr_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Verify"; vr_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$vr_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$vr_pkg" ]]; then
                printf "\n  ${C_MSG_INFO}Verifying %s...${C_RESET}\n\n" "$vr_pkg"
                local vr_ok=0 vr_fail=0
                local vr_verify_out
                vr_verify_out=$(dpkg --verify "$vr_pkg" 2>/dev/null)
                while IFS= read -r f; do
                    [[ -z "$f" ]] && continue
                    if echo "$vr_verify_out" | grep -q -- "$f"; then
                        printf "  ${C_RED}✗ %s${C_RESET}\n" "$f"
                        ((vr_fail++))
                    else
                        printf "  ${C_GREEN}✓ %s${C_RESET}\n" "$f"
                        ((vr_ok++))
                    fi
                done < <(dpkg -L -- "$vr_pkg" 2>/dev/null | grep -E "^/" | head -50)
                printf "\n  ${C_MSG_DONE}%d OK, %d failed${C_RESET}\n" "$vr_ok" "$vr_fail"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /mirror-latency ───
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

        # ─── /mirror-bandwidth ───
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
                local tmp_bw
                tmp_bw=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_bw.XXXXXX") 2>/dev/null
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

        # ─── /pkg-changes ───
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

        # ─── /pkg-recommendations ───
        if [[ "$query" == /pkg-recommendations* ]]; then
            local pr_pkg="${query#/pkg-recommendations }"
            [[ "$pr_pkg" == "/pkg-recommendations" ]] && pr_pkg=""
            clear
            if [[ -z "$pr_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Who recommends"; pr_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$pr_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$pr_pkg" ]]; then
                printf "\n  ${C_WHITE}Packages that recommend %s:${C_RESET}\n\n" "$pr_pkg"
                apt-cache rdepends "$pr_pkg" 2>/dev/null | tail -n +2 | while IFS= read -r rdep; do
                    [[ -z "$rdep" ]] && continue
                    local recommends
                    recommends=$(apt-cache depends "$rdep" 2>/dev/null | grep "Recommends:" | grep -F -- "$pr_pkg")
                    if [[ -n "$recommends" ]]; then
                        printf "  ${C_GREEN}%s${C_RESET}\n" "$rdep"
                    fi
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /pkg-suggests ───
        if [[ "$query" == /pkg-suggests* ]]; then
            local ps_pkg="${query#/pkg-suggests }"
            [[ "$ps_pkg" == "/pkg-suggests" ]] && ps_pkg=""
            clear
            if [[ -z "$ps_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Who suggests"; ps_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$ps_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$ps_pkg" ]]; then
                printf "\n  ${C_WHITE}Packages that suggest %s:${C_RESET}\n\n" "$ps_pkg"
                apt-cache rdepends "$ps_pkg" 2>/dev/null | tail -n +2 | while IFS= read -r rdep; do
                    [[ -z "$rdep" ]] && continue
                    local suggests
                    suggests=$(apt-cache depends "$rdep" 2>/dev/null | grep "Suggests:" | grep -F -- "$ps_pkg")
                    if [[ -n "$suggests" ]]; then
                        printf "  ${C_AMBER}%s${C_RESET}\n" "$rdep"
                    fi
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /pkg-breaks ───
        if [[ "$query" == /pkg-breaks* ]]; then
            local pb_pkg="${query#/pkg-breaks }"
            [[ "$pb_pkg" == "/pkg-breaks" ]] && pb_pkg=""
            clear
            if [[ -z "$pb_pkg" ]]; then
                _pkgs_fzf_pick_pkg "What breaks"; pb_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$pb_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
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

        # ─── /pkg-replaces ───
        if [[ "$query" == /pkg-replaces* ]]; then
            local prr_pkg="${query#/pkg-replaces }"
            [[ "$prr_pkg" == "/pkg-replaces" ]] && prr_pkg=""
            clear
            if [[ -z "$prr_pkg" ]]; then
                _pkgs_fzf_pick_pkg "What replaces"; prr_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$prr_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
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

        # ─── /owner ───
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
                ow_result=$(dpkg -S -- "$ow_file" 2>&1)
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

        # ─── /removed ───
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
                done < <(tail -r "$apt_log" 2>/dev/null || tail -$(($(wc -l < "$apt_log" 2>/dev/null || echo 0) + 1)) "$apt_log" 2>/dev/null | head -500)
                (( found_removed == 0 )) && printf "  ${C_DIM}No packages removed recently.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /new-pkgs ───
        if [[ "$query" == /new-pkgs ]]; then
            clear
            printf "\n  ${C_WHITE}Packages installed this week:${C_RESET}\n\n"
            local week_ago
            week_ago=$(_pkgs_date_ago 7)
            local dpkg_log="${PREFIX}/var/log/dpkg.log"
            if [[ -f "$dpkg_log" ]]; then
                local found_new=0
                while IFS= read -r line; do
                    local ndate npkg
                    ndate=$(echo "$line" | awk '{print $1}')
                    npkg=$(echo "$line" | awk '{print $3}')
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

        # ─── /same-size ───
        if [[ "$query" == /same-size ]]; then
            clear
            printf "\n  ${C_WHITE}Packages with identical installed size (possible duplicates):${C_RESET}\n\n"
            dpkg-query -W -f='${Package}\t${Installed-Size}\n' 2>/dev/null | sort -t$'\t' -k2 -n | awk -F'\t' -v dim="$C_DIM" -v reset="$C_RESET" '
                $2 != "" && $2 != "*" {
                    if ($2 == prev_size && $2 != 0) {
                        if (first == 1) printf "  %s[%s KiB]%s %s\n", dim, prev_size, reset, prev_pkg
                        printf "  %s[%s KiB]%s %s\n", dim, $2, reset, $1
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

        # ─── /depends-on-list ───
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
                for p in ${(w)dol_list}; do
                    _pkgs_validate_name "$p" || continue
                    local pdeps
                    pdeps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$p" 2>/dev/null | grep "Depends:" | sed 's/.*Depends: //' | tr -d '<>' | awk '{print $1}')
                    if [[ -z "$all_deps" ]]; then
                        all_deps="$pdeps"
                    else
                        all_deps=$(printf '%s\n' "${all_deps}" "${pdeps}" | sort | uniq -d)
                    fi
                done
                if [[ -n "$all_deps" ]]; then
                    while IFS= read -r d; do
                        [[ -z "$d" ]] && continue
                        local installed_mark=""
                        dpkg -s -- "$d" 2>/dev/null | grep -q '^Status: install ok installed' && installed_mark=" ${C_GREEN}(installed)${C_RESET}"
                        printf "  ${C_TEAL}%s${C_RESET}%s\n" "$d" "$installed_mark"
                    done <<< "$all_deps"
                else
                    printf "  ${C_DIM}No shared dependencies.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /upgradable ───
        if [[ "$query" == /upgradable ]]; then
            clear
            printf "\n  ${C_WHITE}Upgradable packages with version diff:${C_RESET}\n\n"
            printf "  ${C_DIM}%-30s %-16s %-16s %s${C_RESET}\n" "PACKAGE" "CURRENT" "AVAILABLE" "SIZE"
            printf "  ${C_DIM}%-30s %-16s %-16s %s${C_RESET}\n" "------------------------------" "----------------" "----------------" "------"
            # Get list of upgradable packages
            local -a upg_pkgs=()
            while IFS= read -r line; do
                local upkg
                upkg=$(echo "$line" | awk -F'/' '{print $1}')
                [[ -n "$upkg" ]] && upg_pkgs+=("$upkg")
            done < <(apt list --upgradable 2>/dev/null | tail -n +2)
            (( ${#upg_pkgs[@]} == 0 )) && { printf "  ${C_MSG_DONE}All packages are up to date.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; continue; }
            # Bulk: single apt-cache policy call for all upgradable packages
            local bulk_out
            bulk_out=$(_pkgs_bulk_apt_policy "${upg_pkgs[@]}" 2>/dev/null)
            # Bulk: single apt-cache show for all sizes
            local -A upg_size_map=()
            local bulk_sizes
            bulk_sizes=$(apt-cache show -- "${upg_pkgs[@]}" 2>/dev/null | awk '/^Package:/ { pkg=$2 } /^Size:/ { if(pkg!="") { print pkg, $2; pkg="" } }')
            while read -r spkg ssize; do
                [[ -n "$spkg" ]] && upg_size_map["$spkg"]="$ssize"
            done <<< "$bulk_sizes"
            while read -r upkg ucur uavail; do
                [[ -z "$upkg" ]] && continue
                local usize="${upg_size_map[$upkg]:-}"
                local usize_h="?"
                if [[ -n "$usize" && "$usize" =~ ^[0-9]+$ ]]; then
                    if (( usize > 1048576 )); then
                        usize_h="$((usize/1048576))MB"
                    elif (( usize > 1024 )); then
                        usize_h="$((usize/1024))KB"
                    else
                        usize_h="${usize}B"
                    fi
                fi
                printf "  %-30s ${C_DIM}%-16s${C_RESET} ${C_GREEN}%-16s${C_RESET} %s\n" "$upkg" "$ucur" "$uavail" "$usize_h"
            done <<< "$bulk_out"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /whatprovides ───
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
                wp_result=$(apt-file search "$wp_file" 2>/dev/null || dpkg -S -- "$wp_file" 2>/dev/null)
                if [[ -n "$wp_result" ]]; then
                    echo "$wp_result" | head -30 | while IFS= read -r line; do
                        local wpkg wpath
                        wpkg=$(echo "$line" | awk -F':' '{print $1}')
                        wpath=$(echo "$line" | awk -F': ' '{print $2}')
                        local winstalled=""
                        dpkg -s -- "$wpkg" 2>/dev/null | grep -q '^Status: install ok installed' && winstalled=" ${C_GREEN}(installed)${C_RESET}"
                        printf "  ${C_TEAL}%s${C_RESET} -> %s%s\n" "$wpkg" "$wpath" "$winstalled"
                    done
                else
                    printf "  ${C_DIM}No packages provide this file.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /snap-install ───
        if [[ "$query" == /snap-install* ]]; then
            local si_file="${query#/snap-install }"
            [[ "$si_file" == "/snap-install" ]] && si_file=""
            clear
            if [[ -z "$si_file" ]]; then
                printf "  ${C_MSG_INFO}Enter path to .deb file:${C_RESET} "
                read -r si_file
            fi
            if [[ -n "$si_file" && -f "$si_file" ]]; then
                if [[ "${si_file##*.}" != "deb" ]]; then
                    printf "\n  ${C_MSG_WARN}File does not have .deb extension.${C_RESET}\n"
                else
                    # Validate the original path (not just resolved) to prevent symlink attacks
                    local real_si
                    real_si=$(realpath "$si_file" 2>/dev/null || _pkgs_resolve_path "$si_file")
                    if [[ "$si_file" != "$HOME"/* && "$si_file" != "$PREFIX"/* && "$si_file" != "${TMPDIR:-${PREFIX}/tmp}"/* ]]; then
                        printf "\n  ${C_MSG_WARN}File must be in \$HOME, \$PREFIX, or \$TMPDIR.${C_RESET}\n"
                    elif [[ "$real_si" != "$HOME"/* && "$real_si" != "$PREFIX"/* && "$real_si" != "${TMPDIR:-${PREFIX}/tmp}"/* ]]; then
                        printf "\n  ${C_MSG_WARN}Symlink target must be in \$HOME, \$PREFIX, or \$TMPDIR.${C_RESET}\n"
                    else
                        printf "\n  ${C_MSG_INFO}Installing from: %s${C_RESET}\n\n" "$si_file"
                        dpkg -i -- "$real_si" 2>&1 | sed 's/^/  /'
                        local si_status=${pipestatus[1]}
                        if (( si_status == 0 )); then
                            printf "\n  ${C_MSG_DONE}Installation successful.${C_RESET}\n"
                        else
                            printf "\n  ${C_MSG_REMOVE}Installation had errors. Running %s --fix-broken install...${C_RESET}\n" "$PKG_MGR"
                            "${PKG_MGR}" --fix-broken install -y 2>&1 | sed 's/^/  /'
                        fi
                    fi
                fi
            elif [[ -n "$si_file" ]]; then
                printf "  ${C_MSG_REMOVE}File not found: %s${C_RESET}\n" "$si_file"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /simulate-remove ───
        if [[ "$query" == /simulate-remove* ]]; then
            local sr_pkg="${query#/simulate-remove }"
            [[ "$sr_pkg" == "/simulate-remove" ]] && sr_pkg=""
            clear
            if [[ -z "$sr_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Simulate remove"; sr_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$sr_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$sr_pkg" ]]; then
                printf "\n  ${C_WHITE}Simulating removal of %s...${C_RESET}\n\n" "$sr_pkg"
                local sr_out
                sr_out=$(apt-get remove --dry-run "$sr_pkg" 2>&1)
                printf "  ${C_MSG_DONE}Would be removed:${C_RESET}\n"
                echo "$sr_out" | grep "^  " | head -30 | sed 's/^/  /'
                local sr_free
                sr_free=$(echo "$sr_out" | sed -n 's/.*After this operation, \([0-9.]*[KMGT]*B\).*/\1/p')
                if [[ -n "$sr_free" ]]; then
                    printf "\n  ${C_GREEN}Freed space: %s${C_RESET}\n" "$sr_free"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /repo-stats ───
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
                local rs_cols
                rs_cols=$(tput cols 2>/dev/null) || rs_cols=80
                local rs_max_bar=$(( rs_cols - 34 ))
                (( rs_max_bar < 5 )) && rs_max_bar=5
                local bar=""
                local bcount=0
                (( total > 0 )) && bcount=$(( cnt * rs_max_bar / total ))
                (( bcount < 1 )) && bcount=1
                for ((i=0; i<bcount; i++)); do bar="${bar}█"; done
                printf "  ${C_TEAL}%-25s${C_RESET} ${C_GREEN}%-4s${C_RESET} %s\n" "$sec" "$cnt" "$bar"
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            continue
        fi

        # ─── /download-est ───
        if [[ "$query" == /download-est* ]]; then
            local de_pkg="${query#/download-est }"
            [[ "$de_pkg" == "/download-est" ]] && de_pkg=""
            clear
            if [[ -z "$de_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Download est"; de_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$de_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
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

        # ─── /diff ───
        if [[ "$query" == /diff* ]]; then
            local df_pkg="${query#/diff }"
            [[ "$df_pkg" == "/diff" ]] && df_pkg=""
            clear
            if [[ -z "$df_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Changelog diff"; df_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$df_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$df_pkg" ]]; then
                printf "\n  ${C_WHITE}Changelog diff: %s${C_RESET}\n\n" "$df_pkg"
                local cl_file="${PREFIX}/share/doc/${df_pkg}/changelog.Debian"
                if [[ -f "$cl_file" ]]; then
                    local cl_cur cl_prev
                    cl_cur=$(apt-cache policy "$df_pkg" 2>/dev/null | grep "Installed:" | awk '{print $2}')
                    cl_prev=$(dpkg -s -- "$df_pkg" 2>/dev/null | grep "^Version:" | awk '{print $2}')
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

        # === NEW FEATURES (18) ===

        # ─── /profile ───
        if [[ "$query" == /profile* ]]; then
            local prof_action="${query#/profile }"
            [[ "$prof_action" == "/profile" ]] && prof_action=""
            clear
            mkdir -p "$_PKGS_PROFILES_DIR" 2>/dev/null
            if [[ -z "$prof_action" || "$prof_action" == "list" ]]; then
                printf "\n  ${C_WHITE}Saved Profiles:${C_RESET}\n\n"
                local prof_count=0
                for f in "$_PKGS_PROFILES_DIR"/*.pkgslist(N); do
                    local pname="${f:t}"; pname="${pname%.pkgslist}"
                    local pcount; pcount=$(wc -l < "$f" 2>/dev/null || echo 0)
                    printf "  ${C_TEAL}%-20s${C_RESET} %s packages\n" "$pname" "$pcount"
                    ((prof_count++))
                done
                (( prof_count == 0 )) && printf "  ${C_DIM}No profiles saved yet.${C_RESET}\n"
                printf "\n  ${C_DIM}Usage: /profile save <name> | /profile restore <name> | /profile delete <name>${C_RESET}\n"
            elif [[ "$prof_action" == save* ]]; then
                local pname="${prof_action#save }"
                [[ "$pname" == "save" ]] && pname=""
                if [[ -z "$pname" ]]; then
                    printf "  ${C_MSG_WARN}Usage: /profile save <name>${C_RESET}\n"
                elif ! _pkgs_validate_name "$pname"; then
                    printf "  ${C_MSG_REMOVE}Invalid profile name: %s${C_RESET}\n" "$pname"
                else
                    dpkg-query -W -f='${Package}\n' 2>/dev/null | sort > "$_PKGS_PROFILES_DIR/${pname}.pkgslist"
                    local pcount; pcount=$(wc -l < "$_PKGS_PROFILES_DIR/${pname}.pkgslist" | tr -d ' ')
                    printf "  ${C_MSG_DONE}Profile '%s' saved:${C_RESET} %s packages\n" "$pname" "$pcount"
                fi
            elif [[ "$prof_action" == restore* ]]; then
                local pname="${prof_action#restore }"
                [[ "$pname" == "restore" ]] && pname=""
                if [[ -n "$pname" ]] && ! _pkgs_validate_name "$pname"; then
                    printf "  ${C_MSG_REMOVE}Invalid profile name: %s${C_RESET}\n" "$pname"
                    pname=""
                fi
                if [[ -z "$pname" ]]; then
                    local prof_list
                    prof_list=$(ls -1 "$_PKGS_PROFILES_DIR"/*.pkgslist(N) 2>/dev/null | while read -r f; do echo "${f:t:.pkgslist}"; done)
                    pname=$(echo "$prof_list" | fzf --prompt=" Restore profile> " --height=40% --reverse)
                fi
                if [[ -n "$pname" && -f "$_PKGS_PROFILES_DIR/${pname}.pkgslist" ]]; then
                    printf "\n  ${C_MSG_INFO}Restoring profile '%s'...${C_RESET}\n\n" "$pname"
                    local not_found=0
                    while IFS= read -r pkg; do
                        [[ -z "$pkg" ]] && continue
                        if dpkg -s -- "$pkg" >/dev/null 2>&1; then
                            printf "  ${C_DIM}  %s (already installed)${C_RESET}\n" "$pkg"
                        else
                            printf "  ${C_MSG_INFO}  Installing %s...${C_RESET}" "$pkg"
                            if "${PKG_MGR}" install -y -- "$pkg" 2>/dev/null; then
                                printf "\r  ${C_MSG_DONE}  Installed %s${C_RESET}\n" "$pkg"
                            else
                                printf "\r  ${C_MSG_REMOVE}  Failed %s${C_RESET}\n" "$pkg"
                                ((not_found++))
                            fi
                        fi
                    done < "$_PKGS_PROFILES_DIR/${pname}.pkgslist"
                    printf "\n  ${C_MSG_DONE}Profile '%s' restored.${C_RESET}\n" "$pname"
                elif [[ -n "$pname" ]]; then
                    printf "  ${C_MSG_REMOVE}Profile not found: %s${C_RESET}\n" "$pname"
                fi
            elif [[ "$prof_action" == delete* ]]; then
                local pname="${prof_action#delete }"
                [[ "$pname" == "delete" ]] && pname=""
                if [[ -z "$pname" ]]; then
                    printf "  ${C_MSG_WARN}Usage: /profile delete <name>${C_RESET}\n"
                elif ! _pkgs_validate_name "$pname"; then
                    printf "  ${C_MSG_REMOVE}Invalid profile name: %s${C_RESET}\n" "$pname"
                elif [[ -f "$_PKGS_PROFILES_DIR/${pname}.pkgslist" ]]; then
                    rm -f "$_PKGS_PROFILES_DIR/${pname}.pkgslist"
                    printf "  ${C_MSG_DONE}Profile '%s' deleted.${C_RESET}\n" "$pname"
                else
                    printf "  ${C_MSG_REMOVE}Profile not found: %s${C_RESET}\n" "$pname"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /check-deps ───
        if [[ "$query" == /check-deps* ]]; then
            local cd_path="${query#/check-deps }"
            [[ "$cd_path" == "/check-deps" ]] && cd_path=""
            clear
            if [[ -z "$cd_path" ]]; then
                printf "  ${C_MSG_INFO}Enter project path (or . for current dir):${C_RESET} "
                read -r cd_path
                [[ -z "$cd_path" ]] && cd_path="."
            fi
            if [[ -d "$cd_path" ]]; then
                printf "\n  ${C_WHITE}Checking dependencies for: %s${C_RESET}\n\n" "$(cd "$cd_path" && pwd)"
                local -A needed=()
                # Check common project files
                [[ -f "$cd_path/requirements.txt" ]] && while IFS= read -r line; do
                    [[ -z "$line" || "$line" == \#* ]] && continue
                    local pkg="${line%%[>=<]*}"; pkg="${pkg%%\[*}"; pkg="${pkg// /}"
                    [[ -n "$pkg" ]] && needed["python-$pkg"]=1
                done < "$cd_path/requirements.txt"
                [[ -f "$cd_path/package.json" ]] && needed[nodejs]=1 && needed[npm]=1
                [[ -f "$cd_path/Makefile" ]] && needed[make]=1
                [[ -f "$cd_path/Cargo.toml" ]] && needed[rust]=1
                [[ -f "$cd_path/go.mod" ]] && needed[go]=1
                [[ -f "$cd_path/CMakeLists.txt" ]] && needed[cmake]=1
                # Check shebangs
                while IFS= read -r -d '' f; do
                    local shebang
                    shebang=$(head -1 "$f" 2>/dev/null)
                    case "$shebang" in
                        *python3*) needed[python]=1 ;;
                        *node*) needed[nodejs]=1 ;;
                        *bash*) ;; # always available
                        *zsh*) needed[zsh]=1 ;;
                    esac
                done < <(find "$cd_path" -maxdepth 3 -type f -executable 2>/dev/null -print0 | head -z -50)
                local missing_count=0
                for cmd in "${(k)needed}"; do
                    if ! dpkg -s -- "$cmd" >/dev/null 2>&1; then
                        printf "  ${C_MSG_REMOVE}✗ Missing:${C_RESET} %s\n" "$cmd"
                        ((missing_count++))
                    else
                        printf "  ${C_MSG_DONE}✓ Installed:${C_RESET} %s\n" "$cmd"
                    fi
                done
                (( missing_count > 0 )) && printf "\n  ${C_MSG_WARN}Install missing with:${C_RESET} pkg install ${(j: :)${(k)needed}}\n"
                (( missing_count == 0 && ${#needed[@]} > 0 )) && printf "\n  ${C_MSG_DONE}All dependencies satisfied!${C_RESET}\n"
                (( ${#needed[@]} == 0 )) && printf "  ${C_DIM}No dependency files found.${C_RESET}\n"
            else
                printf "  ${C_MSG_REMOVE}Not a directory: %s${C_RESET}\n" "$cd_path"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /shell-hook ───
        if [[ "$query" == /shell-hook ]]; then
            clear
            printf "\n  ${C_WHITE}Generating shell hooks from installed packages...${C_RESET}\n\n"
            local hook_file="${HOME}/.pkgs_aliases.zsh"
            {
                printf "# Auto-generated by pkgs — $(date)\n"
                printf "# Source this in .zshrc: source ~/.pkgs_aliases.zsh\n\n"
                dpkg-query -W -f='${Package}\n' 2>/dev/null | while IFS= read -r pkg; do
                    case "$pkg" in
                        git) printf "alias g='git'\nalias gs='git status'\nalias gp='git push'\nalias gl='git log --oneline -10'\nalias gd='git diff'\n" ;;
                        python|python3) printf "alias py='python3'\nalias ipy='ipython'\n" ;;
                        nodejs) printf "alias ni='npm install'\nalias nr='npm run'\nalias nrs='npm start'\n" ;;
                        vim|neovim) printf "alias v='vim'\nalias vi='vim'\n" ;;
                        nano) printf "alias n='nano'\n" ;;
                        tmux) printf "alias t='tmux'\nalias ta='tmux attach'\nalias tl='tmux ls'\n" ;;
                        fzf) printf "alias fz='fzf'\n" ;;
                        ripgrep) printf "alias rg='rg --hidden'\n" ;;
                        fd) printf "alias fdf='fd --hidden'\n" ;;
                        bat) printf "alias cat='bat --paging=never'\n" ;;
                        exa|eza) printf "alias ls='exa'\nalias ll='exa -la'\n" ;;
                        lsd) printf "alias ls='lsd'\nalias ll='lsd -la'\n" ;;
                        lazygit) printf "alias lg='lazygit'\n" ;;
                        tig) printf "alias tg='tig'\n" ;;
                    esac
                done
            } > "$hook_file"
            printf "  ${C_MSG_DONE}Generated:${C_RESET} %s\n" "$hook_file"
            printf "  ${C_DIM}Add to .zshrc: source ~/.pkgs_aliases.zsh${C_RESET}\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /storage-report ───
        if [[ "$query" == /storage-report ]]; then
            clear
            printf "\n  ${C_WHITE}Storage Report:${C_RESET}\n\n"
            printf "  ${C_DIM}%-25s %s${C_RESET}\n" "LOCATION" "SIZE"
            printf "  ${C_DIM}%-25s %s${C_RESET}\n" "-------------------------" "---------"
            local total=0
            for dir_pair in "\$HOME:$HOME" "\$PREFIX:$PREFIX" "Cache:\$HOME/.cache" "Shared:\$HOME/storage/shared"; do
                local label="${dir_pair%%:*}"
                local dpath="${dir_pair#*:}"
                if [[ -d "$dpath" ]]; then
                    local dsize
                    dsize=$(timeout 5 du -sk "$dpath" 2>/dev/null | awk '{print $1}')
                    [[ -z "$dsize" ]] && dsize=0
                    printf "  %-25s %s\n" "$label" "$(_pkgs_format_size "${dsize:-0}")"
                    total=$((total + ${dsize:-0}))
                else
                    printf "  %-25s ${C_DIM}N/A${C_RESET}\n" "$label"
                fi
            done
            printf "  ${C_DIM}%-25s %s${C_RESET}\n" "-------------------------" "---------"
            printf "  ${C_WHITE}%-25s %s${C_RESET}\n" "Total (Termux)" "$(_pkgs_format_size "$total")"
            # Show Android storage
            local avail_kb
            avail_kb=$(df "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
            if [[ -n "$avail_kb" ]]; then
                printf "\n  ${C_TEAL}System available:${C_RESET} %s\n" "$(_pkgs_format_size "$avail_kb")"
                # Estimate Android per-app quota (heuristic: 1-8 GB)
                local est_limit_kb=$((4 * 1024 * 1024))  # 4GB typical
                local pct=$((total * 100 / est_limit_kb))
                if (( pct > 80 )); then
                    printf "  ${C_MSG_WARN}⚠ Approaching storage limit (~%d%% of estimated quota)${C_RESET}\n" "$pct"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /health ───
        if [[ "$query" == /health ]]; then
            clear
            printf "\n  ${C_WHITE}Termux Health Check${C_RESET}\n\n"
            local health_score=100
            local -a issues=()
            # Check broken packages
            local broken_count
            broken_count=$(dpkg --audit 2>&1 | grep -c "^Broken" || echo 0)
            if (( broken_count > 0 )); then
                issues+=("$broken_count broken packages (-15)")
                ((health_score -= 15))
            fi
            # Check disk pressure
            local avail_kb
            avail_kb=$(df "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
            if [[ -n "$avail_kb" ]] && (( avail_kb < 200000 )); then
                issues+=("Low disk space: $(_pkgs_format_size "$avail_kb") remaining (-20)")
                ((health_score -= 20))
            fi
            # Check held packages
            local held_count
            held_count=$(apt-mark showhold 2>/dev/null | wc -l | tr -d ' ')
            if (( held_count > 0 )); then
                issues+=("$held_count held packages (-5)")
                ((health_score -= 5))
            fi
            # Check outdated
            local outdated_count
            local _hp_all_pkgs
            _hp_all_pkgs=(${(@f)"$(dpkg-query -W -f='${Package}\n' 2>/dev/null)"})
            outdated_count=$(_pkgs_bulk_apt_policy "${_hp_all_pkgs[@]}" 2>/dev/null | wc -l | tr -d ' ')
            if (( outdated_count > 10 )); then
                issues+=("$outdated_count outdated packages (-10)")
                ((health_score -= 10))
            fi
            # Check orphans
            local orphans_count
            orphans_count=$(apt-mark showmanual 2>/dev/null | while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                deps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$pkg" 2>/dev/null | grep "Depends:" | awk '{print $2}')
                if [[ -z "$deps" ]]; then echo "$pkg"; fi
            done | wc -l | tr -d ' ')
            if (( orphans_count > 5 )); then
                issues+=("$orphans_count potential orphans (-5)")
                ((health_score -= 5))
            fi
            # Check apt cache size
            local cache_size
            cache_size=$(du -sk "$PREFIX/var/cache/apt/archives" 2>/dev/null | awk '{print $1}')
            if [[ -n "$cache_size" ]] && (( cache_size > 100000 )); then
                issues+=("Large apt cache: $(_pkgs_format_size "$cache_size") (-5)")
                ((health_score -= 5))
            fi
            # Clamp score
            (( health_score < 0 )) && health_score=0
            # Display
            if (( health_score >= 80 )); then
                printf "  ${C_MSG_DONE}Health Score: %d/100 ✓${C_RESET}\n\n" "$health_score"
            elif (( health_score >= 50 )); then
                printf "  ${C_MSG_WARN}Health Score: %d/100 ⚠${C_RESET}\n\n" "$health_score"
            else
                printf "  ${C_MSG_REMOVE}Health Score: %d/100 ✗${C_RESET}\n\n" "$health_score"
            fi
            if (( ${#issues[@]} > 0 )); then
                printf "  ${C_WHITE}Issues found:${C_RESET}\n"
                for issue in "${issues[@]}"; do
                    printf "  ${C_MSG_WARN}  • %s${C_RESET}\n" "$issue"
                done
            else
                printf "  ${C_MSG_DONE}No issues detected!${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /auto-clean ───
        if [[ "$query" == /auto-clean ]]; then
            clear
            printf "\n  ${C_WHITE}Auto-Clean Setup${C_RESET}\n\n"
            local cronie_file="$HOME/.config/pkgs/autoclean.cron"
            mkdir -p "$(dirname "$cronie_file")" 2>/dev/null
            if [[ -f "$cronie_file" ]]; then
                printf "  ${C_MSG_DONE}Current schedule:${C_RESET}\n"
                cat "$cronie_file" | sed 's/^/  /'
                printf "\n  ${C_TEAL}[d]${C_RESET} Disable  ${C_TEAL}[e]${C_RESET} Edit  ${C_TEAL}[r]${C_RESET} Remove\n"
                printf "  ${C_MSG_INFO}Choice: ${C_RESET}"
                local ac_choice; read -q ac_choice; read -r
                case "$ac_choice" in
                    d) rm -f "$cronie_file"; printf "\n  ${C_MSG_DONE}Auto-clean disabled.${C_RESET}\n" ;;
                    r) rm -f "$cronie_file"; printf "\n  ${C_MSG_DONE}Auto-clean removed.${C_RESET}\n" ;;
                    e) ${EDITOR:-vi} "$cronie_file" 2>/dev/null ;;
                    *) ;;
                esac
            else
                printf "  ${C_DIM}No auto-clean schedule configured.${C_RESET}\n\n"
                printf "  ${C_TEAL}[1]${C_RESET} Daily cleanup (3:00 AM)\n"
                printf "  ${C_TEAL}[2]${C_RESET} Weekly cleanup (Sundays 3:00 AM)\n"
                printf "  ${C_MSG_INFO}Choice (1-2, or Enter to skip): ${C_RESET}"
                local ac_choice; read -q ac_choice; read -r
                case "$ac_choice" in
                    1) echo "0 3 * * * pkg autoremove -y && apt-get clean" > "$cronie_file"
                       printf "\n  ${C_MSG_DONE}Daily auto-clean enabled.${C_RESET}\n" ;;
                    2) echo "0 3 * * 0 pkg autoremove -y && apt-get clean" > "$cronie_file"
                       printf "\n  ${C_MSG_DONE}Weekly auto-clean enabled.${C_RESET}\n" ;;
                    *) printf "\n  ${C_DIM}Cancelled.${C_RESET}\n" ;;
                esac
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /footprint ───
        if [[ "$query" == /footprint* ]]; then
            local fp_pkg="${query#/footprint }"
            [[ "$fp_pkg" == "/footprint" ]] && fp_pkg=""
            clear
            if [[ -z "$fp_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Footprint"; fp_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$fp_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$fp_pkg" ]]; then
                printf "\n  ${C_WHITE}Footprint analysis: %s${C_RESET}\n\n" "$fp_pkg"
                # Get direct dependencies recursively
                local -A all_deps=()
                local -a queue=("$fp_pkg")
                local iter_count=0
                while (( ${#queue[@]} > 0 && iter_count < 1000 )); do
                    local cur="${queue[1]}"
                    queue=("${queue[@]:1}")
                    [[ -n "${all_deps[$cur]}" ]] && continue
                    all_deps["$cur"]=1
                    ((iter_count++))
                    local deps
                    deps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$cur" 2>/dev/null | grep "Depends:" | awk '{print $2}')
                    while IFS= read -r dep; do
                        [[ -n "$dep" && -z "${all_deps[$dep]}" ]] && queue+=("$dep")
                    done <<< "$deps"
                done
                # Get sizes
                local total_new=0 total_installed=0
                local -a new_pkgs=()
                for dep in "${(k)all_deps}"; do
                    local size
                    size=$(dpkg-query -W -f='${Installed-Size}' -- "$dep" 2>/dev/null)
                    size="${size:-0}"
                    if dpkg -s -- "$dep" >/dev/null 2>&1; then
                        total_installed=$((total_installed + size))
                    else
                        total_new=$((total_new + size))
                        new_pkgs+=("$dep")
                    fi
                done
                printf "  ${C_DIM}%-30s %s${C_RESET}\n" "Package" "Size"
                printf "  ${C_DIM}%-30s %s${C_RESET}\n" "------------------------------" "---------"
                printf "  ${C_WHITE}%-30s${C_RESET} %s\n" "$fp_pkg (itself)" "$(_pkgs_format_size "$(dpkg-query -W -f='${Installed-Size}' -- "$fp_pkg" 2>/dev/null || echo 0)")"
                printf "  ${C_MSG_DONE}%-30s${C_RESET} %s\n" "Already installed deps" "$(_pkgs_format_size "$total_installed")"
                if (( ${#new_pkgs[@]} > 0 )); then
                    printf "  ${C_MSG_WARN}%-30s${C_RESET} %s\n" "NEW deps to download" "$(_pkgs_format_size "$total_new")"
                    printf "\n  ${C_DIM}New packages:${C_RESET}\n"
                    for np in "${new_pkgs[@]}"; do
                        local nsize; nsize=$(dpkg-query -W -f='${Installed-Size}' -- "$np" 2>/dev/null || echo 0)
                        printf "    ${C_AMBER}+ %-28s${C_RESET} %s\n" "$np" "$(_pkgs_format_size "$nsize")"
                    done
                fi
                printf "\n  ${C_WHITE}Total new disk cost: %s${C_RESET}\n" "$(_pkgs_format_size "$total_new")"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /unused ───
        if [[ "$query" == /unused ]]; then
            clear
            printf "\n  ${C_WHITE}Checking for unused packages...${C_RESET}\n\n"
            # Get commands from history
            local -A used_cmds=()
            local hist_cmds
            hist_cmds=$(fc -l1 2>/dev/null | awk '{print $2}' | awk '{print $1}' | sed 's|.*/||' | sort -u)
            if [[ -n "$hist_cmds" ]]; then
                while IFS= read -r cmd; do
                    [[ -z "$cmd" ]] && continue
                    [[ -n "$cmd" ]] && used_cmds["$cmd"]=1
                done <<< "$hist_cmds"
            fi
            # Check manually installed packages
            local unused_count=0
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                # Get primary binary from package
                local binaries
                binaries=$(dpkg -L -- "$pkg" 2>/dev/null | grep '/bin/' | while read -r f; do echo "${f##*/}"; done)
                local is_used=0
                while IFS= read -r bin; do
                    [[ -n "${used_cmds[$bin]}" ]] && { is_used=1; break; }
                done <<< "$binaries"
                if (( is_used == 0 && -n "$binaries" )); then
                    local bcount; bcount=$(echo "$binaries" | wc -l | tr -d ' ')
                    printf "  ${C_MSG_WARN}%-30s${C_RESET} ${C_DIM}(%s binaries, none in history)${C_RESET}\n" "$pkg" "$bcount"
                    ((unused_count++))
                fi
            done < <(apt-mark showmanual 2>/dev/null)
            if (( unused_count == 0 )); then
                printf "  ${C_MSG_DONE}All manually installed packages appear to be in use.${C_RESET}\n"
            else
                printf "\n  ${C_DIM}%d potentially unused packages found${C_RESET}\n" "$unused_count"
                printf "  ${C_DIM}Review with: /why <pkg> to check before removing${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /timeline ───
        if [[ "$query" == /timeline ]]; then
            clear
            printf "\n  ${C_WHITE}Package Activity Timeline${C_RESET}\n\n"
            local hist_dir="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/history"
            if [[ -d "$hist_dir" ]]; then
                printf "  ${C_DIM}%-12s %s${C_RESET}\n" "DATE" "ACTIVITY"
                printf "  ${C_DIM}%-12s %s${C_RESET}\n" "------------" "--------------------"
                for f in "$hist_dir"/*.log(N-om[1,30]); do
                    local fdate="${f:t}"; fdate="${fdate%.log}"
                    local installs removes
                    installs=$(grep -c "INSTALL" "$f" 2>/dev/null || echo 0)
                    removes=$(grep -c "REMOVE" "$f" 2>/dev/null || echo 0)
                    local bar=""
                    local i
                    for (( i=0; i<installs && i<20; i++ )); do bar="${bar}${C_GREEN}█${C_RESET}"; done
                    for (( i=0; i<removes && i<20; i++ )); do bar="${bar}${C_RED}█${C_RESET}"; done
                    [[ -z "$bar" ]] && bar="${C_DIM}·${C_RESET}"
                    printf "  ${C_TEAL}%-12s${C_RESET} %s ${C_DIM}(+%s/-%s)${C_RESET}\n" "$fdate" "$bar" "$installs" "$removes"
                done
            else
                printf "  ${C_DIM}No history data yet.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /schedule ───
        if [[ "$query" == /schedule ]]; then
            clear
            printf "\n  ${C_WHITE}Update Reminder Setup${C_RESET}\n\n"
            printf "  ${C_DIM}Requires cronie to auto-trigger reminders.${C_RESET}\n"
            if ! command -v termux-notification >/dev/null 2>&1; then
                printf "  ${C_MSG_WARN}termux-api package required for notifications.${C_RESET}\n"
                printf "  ${C_DIM}Install with: pkg install termux-api${C_RESET}\n"
            else
                local sched_file="$HOME/.config/pkgs/schedule.conf"
                mkdir -p "$(dirname "$sched_file")" 2>/dev/null
                if [[ -f "$sched_file" ]]; then
                    printf "  ${C_MSG_DONE}Current schedule:${C_RESET}\n"
                    cat "$sched_file" | sed 's/^/  /'
                    printf "\n  ${C_TEAL}[d]${C_RESET} Disable  ${C_TEAL}[e]${C_RESET} Edit\n"
                    printf "  ${C_MSG_INFO}Choice: ${C_RESET}"
                    local sch_choice; read -q sch_choice; read -r
                    case "$sch_choice" in
                        d) rm -f "$sched_file"; printf "\n  ${C_MSG_DONE}Reminders disabled.${C_RESET}\n" ;;
                        e) ${EDITOR:-vi} "$sched_file" 2>/dev/null ;;
                    esac
                else
                    printf "  ${C_TEAL}[1]${C_RESET} Daily reminder (9:00 AM)\n"
                    printf "  ${C_TEAL}[2]${C_RESET} Weekly reminder (Mondays 9:00 AM)\n"
                    printf "  ${C_MSG_INFO}Choice (1-2, or Enter to skip): ${C_RESET}"
                    local sch_choice; read -q sch_choice; read -r
                    case "$sch_choice" in
                        1) echo "frequency=daily\ntime=09:00" > "$sched_file"
                           printf "\n  ${C_MSG_DONE}Daily reminders enabled.${C_RESET}\n" ;;
                        2) echo "frequency=weekly\ntime=09:00" > "$sched_file"
                           printf "\n  ${C_MSG_DONE}Weekly reminders enabled.${C_RESET}\n" ;;
                        *) printf "\n  ${C_DIM}Cancelled.${C_RESET}\n" ;;
                    esac
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /search-providers ───
        if [[ "$query" == /search-providers* ]]; then
            local sp_query="${query#/search-providers }"
            [[ "$sp_query" == "/search-providers" ]] && sp_query=""
            clear
            if [[ -z "$sp_query" ]]; then
                printf "  ${C_MSG_INFO}Enter command/binary name:${C_RESET} "
                read -r sp_query
            fi
            if [[ -n "$sp_query" ]]; then
                printf "\n  ${C_WHITE}Packages providing '%s':${C_RESET}\n\n" "$sp_query"
                local sp_results
                sp_results=$(apt-cache search -- "$sp_query" 2>/dev/null | head -20)
                if [[ -n "$sp_results" ]]; then
                    printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "PACKAGE" "SIZE" "DESCRIPTION"
                    printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "------------------------------" "------------" "--------------------"
                    echo "$sp_results" | while IFS= read -r line; do
                        local spkg sdesc
                        spkg=$(echo "$line" | awk '{print $1}')
                        sdesc=$(echo "$line" | cut -d' ' -f2-)
                        local ssize
                        ssize=$(apt-cache show -- "$spkg" 2>/dev/null | grep "^Installed-Size:" | head -1 | awk '{print $2}')
                        printf "  ${C_TEAL}%-30s${C_RESET} %-12s ${C_DIM}%s${C_RESET}\n" "$spkg" "$(_pkgs_format_size "${ssize:-0}")" "${sdesc:0:40}"
                    done
                else
                    printf "  ${C_DIM}No packages found.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /diff-snapshots ───
        if [[ "$query" == /diff-snapshots ]]; then
            clear
            local snap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/snapshots"
            local -a snaps=()
            for f in "$snap_dir"/*.txt(N); do
                snaps+=("$f")
            done
            if (( ${#snaps[@]} < 2 )); then
                printf "  ${C_MSG_WARN}Need at least 2 snapshots. Use /snapshot to create them.${C_RESET}\n"
            else
                printf "\n  ${C_WHITE}Select first snapshot:${C_RESET}\n"
                local snap1
                snap1=$(printf '%s\n' "${snaps[@]##*/}" | fzf --prompt=" Snapshot A> " --height=40% --reverse)
                printf "\n  ${C_WHITE}Select second snapshot:${C_RESET}\n"
                local snap2
                snap2=$(printf '%s\n' "${snaps[@]##*/}" | fzf --prompt=" Snapshot B> " --height=40% --reverse)
                if [[ -n "$snap1" && -n "$snap2" && "$snap1" != "$snap2" ]]; then
                    local f1="$snap_dir/$snap1" f2="$snap_dir/$snap2"
                    printf "\n  ${C_WHITE}Diff: %s → %s${C_RESET}\n\n" "$snap1" "$snap2"
                    # Extract package names
                    local -a pkgs1=() pkgs2=()
                    while IFS=$'\t' read -r p v; do [[ -n "$p" ]] && pkgs1+=("$p"); done < "$f1"
                    while IFS=$'\t' read -r p v; do [[ -n "$p" ]] && pkgs2+=("$p"); done < "$f2"
                    # Find added, removed, changed
                    local added=0 removed=0 changed=0
                    # Packages in snap2 but not snap1 (added)
                    for p in "${pkgs2[@]}"; do
                        if ! printf '%s\n' "${pkgs1[@]}" | grep -qx "$p"; then
                            printf "  ${C_GREEN}+ %-30s${C_RESET}\n" "$p"
                            ((added++))
                        fi
                    done
                    # Packages in snap1 but not snap2 (removed)
                    for p in "${pkgs1[@]}"; do
                        if ! printf '%s\n' "${pkgs2[@]}" | grep -qx "$p"; then
                            printf "  ${C_RED}- %-30s${C_RESET}\n" "$p"
                            ((removed++))
                        fi
                    done
                    printf "\n  ${C_DIM}Summary: +%d added, -%d removed${C_RESET}\n" "$added" "$removed"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /audit ───
        if [[ "$query" == /audit ]]; then
            clear
            printf "\n  ${C_WHITE}Security Audit:${C_RESET}\n\n"
            local audit_count=0
            # SUID/SGID files
            printf "  ${C_TEAL}SUID/SGID files in \$PREFIX:${C_RESET}\n"
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                local owner
                owner=$(dpkg -S -- "$f" 2>/dev/null | head -1 | awk -F: '{print $1}')
                printf "  ${C_MSG_WARN}  ⚠ %s${C_RESET} ${C_DIM}(owned by: %s)${C_RESET}\n" "$f" "${owner:-unknown}"
                ((audit_count++))
            done < <(find "$PREFIX/bin" "$PREFIX/lib" -maxdepth 3 \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null)
            # World-writable files
            printf "\n  ${C_TEAL}World-writable files in \$PREFIX:${C_RESET}\n"
            local ww_count=0
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                printf "  ${C_MSG_WARN}  ⚠ %s${C_RESET}\n" "$f"
                ((ww_count++))
                ((audit_count++))
            done < <(find "$PREFIX" -maxdepth 4 -perm -0002 -type f 2>/dev/null | head -20)
            (( ww_count == 0 )) && printf "  ${C_MSG_DONE}  None found${C_RESET}\n"
            if (( audit_count == 0 )); then
                printf "\n  ${C_MSG_DONE}No security issues found.${C_RESET}\n"
            else
                printf "\n  ${C_DIM}%d potential issues found${C_RESET}\n" "$audit_count"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /repo-check ───
        if [[ "$query" == /repo-check ]]; then
            clear
            printf "\n  ${C_WHITE}Repository Trust Check:${C_RESET}\n\n"
            # Build list of trusted origins from sources.list
            local -A trusted_origins=()
            local sources_file="$PREFIX/etc/apt/sources.list"
            [[ -f "$sources_file" ]] && while IFS= read -r line; do
                [[ "$line" == \#* || -z "$line" ]] && continue
                local origin
                origin=$(echo "$line" | awk '{print $1}')
                [[ -n "$origin" ]] && trusted_origins["$origin"]=1
            done < "$sources_file"
            # Also check sources.list.d
            for sf in "$PREFIX/etc/apt/sources.list.d/"*.list(N); do
                while IFS= read -r line; do
                    [[ "$line" == \#* || -z "$line" ]] && continue
                    local origin
                    origin=$(echo "$line" | awk '{print $1}')
                    [[ -n "$origin" ]] && trusted_origins["$origin"]=1
                done < "$sf"
            done
            local unknown_count=0
            printf "  ${C_DIM}%-30s %s${C_RESET}\n" "PACKAGE" "ORIGIN"
            printf "  ${C_DIM}%-30s %s${C_RESET}\n" "------------------------------" "--------------------"
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                local origin
                origin=$(apt-cache show -- "$pkg" 2>/dev/null | grep "^Origin:" | head -1 | awk '{print $2}')
                if [[ -n "$origin" && -z "${trusted_origins[$origin]}" ]]; then
                    printf "  ${C_MSG_WARN}%-30s${C_RESET} %s\n" "$pkg" "$origin"
                    ((unknown_count++))
                fi
            done < <(dpkg-query -W -f='${Package}\n' 2>/dev/null | head -200)
            if (( unknown_count == 0 )); then
                printf "  ${C_MSG_DONE}All checked packages from trusted origins.${C_RESET}\n"
            else
                printf "\n  ${C_MSG_WARN}%d packages from untrusted origins${C_RESET}\n" "$unknown_count"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /popular ───
        if [[ "$query" == /popular ]]; then
            clear
            printf "\n  ${C_WHITE}Popular Termux Packages${C_RESET}\n\n"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "PACKAGE" "SIZE" "DESCRIPTION"
            printf "  ${C_DIM}%-30s %-12s %s${C_RESET}\n" "------------------------------" "------------" "--------------------"
            local -a popular_pkgs=(git vim tmux python nodejs nano jq curl wget htop tree ripgrep fd bat fzf lazygit tig neovim go rust openssh nmap ranger nnn lf micro)
            for pkg in "${popular_pkgs[@]}"; do
                if apt-cache show -- "$pkg" >/dev/null 2>&1; then
                    local desc ssize
                    desc=$(apt-cache show -- "$pkg" 2>/dev/null | grep "^Description:" | head -1 | sed 's/^Description: //' | cut -c1-35)
                    ssize=$(apt-cache show -- "$pkg" 2>/dev/null | grep "^Installed-Size:" | head -1 | awk '{print $2}')
                    local installed_tag=""
                    dpkg -s -- "$pkg" >/dev/null 2>&1 && installed_tag=" ${C_MSG_DONE}[installed]${C_RESET}"
                    printf "  ${C_TEAL}%-30s${C_RESET} %-12s ${C_DIM}%s${C_RESET}%s\n" "$pkg" "$(_pkgs_format_size "${ssize:-0}")" "${desc:-...}" "$installed_tag"
                fi
            done
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /boot-time ───
        if [[ "$query" == /boot-time ]]; then
            clear
            printf "\n  ${C_WHITE}Termux Startup Benchmark${C_RESET}\n\n"
            printf "  ${C_DIM}Measuring cold-start time (3 runs)...${C_RESET}\n\n"
            local -a times=()
            local i
            for (( i=1; i<=3; i++ )); do
                local elapsed
                elapsed=$( { time zsh -i -c exit; } 2>&1 | grep real | sed 's/.*0m//;s/s$//' )
                local ms
                ms=$(echo "$elapsed" | awk -F'.' '{printf "%d", $1*1000 + $2*100}')
                times+=("$ms")
                printf "  ${C_DIM}  Run %d: %dms${C_RESET}\n" "$i" "$ms"
            done
            # Average
            local sum=0
            for t in "${times[@]}"; do sum=$((sum + t)); done
            local avg=$((sum / ${#times[@]}))
            printf "\n  ${C_WHITE}Average startup: %dms${C_RESET}\n" "$avg"
            # Recommendations
            printf "\n  ${C_TEAL}Optimization tips:${C_RESET}\n"
            local zshrc_size
            zshrc_size=$(wc -c < "$HOME/.zshrc" 2>/dev/null || echo 0)
            if (( zshrc_size > 5000 )); then
                printf "  ${C_MSG_WARN}  • .zshrc is %d bytes — consider lazy-loading plugins${C_RESET}\n" "$zshrc_size"
            fi
            local pkg_count
            pkg_count=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | wc -l | tr -d ' ')
            if (( pkg_count > 500 )); then
                printf "  ${C_MSG_WARN}  • %d packages installed — PATH scanning may be slow${C_RESET}\n" "$pkg_count"
            fi
            printf "  ${C_DIM}  • Use 'compinit -C' to skip security checks${C_RESET}\n"
            printf "  ${C_DIM}  • Use 'autoload -Uz compinit && compinit' instead of eager compinit${C_RESET}\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /disk-pressure ───
        if [[ "$query" == /disk-pressure ]]; then
            clear
            printf "\n  ${C_WHITE}Disk Pressure Monitor${C_RESET}\n\n"
            local avail_kb
            avail_kb=$(df "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
            local used_kb
            used_kb=$(df "$HOME" 2>/dev/null | awk 'NR==2{print $3}')
            if [[ -n "$avail_kb" && -n "$used_kb" ]]; then
                local total_kb=$((used_kb + avail_kb))
                local pct=$((used_kb * 100 / total_kb))
                printf "  ${C_DIM}%-20s %s${C_RESET}\n" "Used:" "$(_pkgs_format_size "$used_kb")"
                printf "  ${C_DIM}%-20s %s${C_RESET}\n" "Available:" "$(_pkgs_format_size "$avail_kb")"
                printf "  ${C_DIM}%-20s %d%%${C_RESET}\n" "Usage:" "$pct"
                # Simple bar
                local bar_len=40
                local filled=$((pct * bar_len / 100))
                local empty=$((bar_len - filled))
                printf "\n  ["
                local j
                for (( j=0; j<filled; j++ )); do printf "${C_GREEN}█${C_RESET}"; done
                for (( j=0; j<empty; j++ )); do printf "${C_DIM}░${C_RESET}"; done
                printf "]\n"
                # Estimate days until full
                local hist_dir="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/history"
                if [[ -d "$hist_dir" ]]; then
                    local total_installs=0 total_days=0
                    for f in "$hist_dir"/*.log(N); do
                        local cnt; cnt=$(grep -c "INSTALL" "$f" 2>/dev/null || echo 0)
                        total_installs=$((total_installs + cnt))
                        ((total_days++))
                    done
                    if (( total_days > 0 && total_installs > 0 )); then
                        local avg_installs_per_day=$((total_installs / total_days))
                        local est_days="unknown"
                        # Rough estimate: ~2MB per install average
                        local daily_growth_kb=$((avg_installs_per_day * 2048))
                        if (( daily_growth_kb > 0 )); then
                            est_days=$((avail_kb / daily_growth_kb))
                        fi
                        printf "\n  ${C_DIM}Estimated days at current install rate: ~%s days${C_RESET}\n" "$est_days"
                    fi
                fi
                if (( pct > 90 )); then
                    printf "\n  ${C_MSG_REMOVE}⚠ CRITICAL: Storage nearly full! Run /nuke or /clean.${C_RESET}\n"
                elif (( pct > 75 )); then
                    printf "\n  ${C_MSG_WARN}⚠ Warning: Storage getting full. Consider /clean.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /pkg-impact ───
        if [[ "$query" == /pkg-impact* ]]; then
            local pi_pkg="${query#/pkg-impact }"
            [[ "$pi_pkg" == "/pkg-impact" ]] && pi_pkg=""
            clear
            if [[ -z "$pi_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Impact analysis"; pi_pkg=$_PKGS_FZF_PICKED
            else
                _pkgs_validate_name "$pi_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}\n"; read -r; continue; }
            fi
            if [[ -n "$pi_pkg" ]]; then
                if ! apt-cache show -- "$pi_pkg" >/dev/null 2>&1; then
                    printf "  ${C_MSG_REMOVE}Package not found: %s${C_RESET}\n" "$pi_pkg"
                else
                    printf "\n  ${C_WHITE}Impact Analysis: %s${C_RESET}\n\n" "$pi_pkg"
                    # Download size
                    local dl_size
                    dl_size=$(apt-cache show -- "$pi_pkg" 2>/dev/null | grep "^Size:" | head -1 | awk '{print $2}')
                    printf "  ${C_DIM}Download size:${C_RESET}      %s\n" "$(_pkgs_format_size "$(( ${dl_size:-0} / 1024 ))")"
                    # Installed size
                    local inst_size
                    inst_size=$(apt-cache show -- "$pi_pkg" 2>/dev/null | grep "^Installed-Size:" | head -1 | awk '{print $2}')
                    printf "  ${C_DIM}Installed size:${C_RESET}     %s\n" "$(_pkgs_format_size "${inst_size:-0}")"
                    # Dependencies
                    local -A pi_deps=()
                    local -a pi_queue=("$pi_pkg")
                    local pi_iter=0
                    while (( ${#pi_queue[@]} > 0 && pi_iter < 1000 )); do
                        local cur="${pi_queue[1]}"
                        pi_queue=("${pi_queue[@]:1}")
                        [[ -n "${pi_deps[$cur]}" ]] && continue
                        pi_deps["$cur"]=1
                        ((pi_iter++))
                        local deps
                        deps=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances -- "$cur" 2>/dev/null | grep "Depends:" | awk '{print $2}')
                        while IFS= read -r dep; do
                            [[ -n "$dep" && -z "${pi_deps[$dep]}" ]] && pi_queue+=("$dep")
                        done <<< "$deps"
                    done
                    # Count new vs existing
                    local new_count=0 existing_count=0 new_total_kb=0
                    for dep in "${(k)pi_deps}"; do
                        local dsize; dsize=$(dpkg-query -W -f='${Installed-Size}' -- "$dep" 2>/dev/null || echo 0)
                        if dpkg -s -- "$dep" >/dev/null 2>&1; then
                            ((existing_count++))
                        else
                            ((new_count++))
                            new_total_kb=$((new_total_kb + dsize))
                        fi
                    done
                    printf "  ${C_DIM}Total dependencies:${C_RESET}  %d\n" "$((${#pi_deps[@]} - 1))"
                    printf "  ${C_MSG_DONE}Already installed:${C_RESET}   %d\n" "$existing_count"
                    printf "  ${C_MSG_WARN}NEW to install:${C_RESET}      %d\n" "$new_count"
                    printf "  ${C_WHITE}Total system increase:${C_RESET} %s\n" "$(_pkgs_format_size "$new_total_kb")"
                    if (( new_total_kb > 100000 )); then
                        printf "\n  ${C_MSG_WARN}⚠ This will add over 100MB to your system.${C_RESET}\n"
                    fi
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /export-versions ───
        if [[ "$query" == /export-versions ]]; then
            clear
            printf "\n  ${C_WHITE}Export installed packages with versions${C_RESET}\n\n"
            local export_file="pkgs-versions-$(date +%Y%m%d-%H%M%S).txt"
            printf "  ${C_MSG_INFO}Export path [${C_RESET}%s${C_MSG_INFO}]: ${C_RESET}" "$export_file"
            local user_path
            read -r user_path
            [[ -n "$user_path" ]] && export_file="$user_path"
            if _pkgs_validate_export_path "$export_file"; then
                {
                    printf "# Installed packages — exported on %s\n" "$(date)"
                    printf "# Total: %s\n\n" "$(dpkg --get-selections 2>/dev/null | grep -c '\sinstall$' || echo 0)"
                    dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' 2>/dev/null \
                        | sort -t$'\t' -k3 -rn \
                        | while IFS=$'\t' read -r p v s; do
                            printf "%-30s %-20s %s\n" "$p" "$v" "$(_pkgs_format_size "${s:-0}")"
                        done
                } > "$export_file"
                if [[ -f "$export_file" ]]; then
                    local line_count
                    line_count=$(wc -l < "$export_file")
                    printf "\n  ${C_MSG_DONE}Saved: ${C_RESET}%s  ${C_DIM}(%d packages)${C_RESET}\n" "$export_file" "$((line_count - 2))"
                else
                    printf "\n  ${C_MSG_REMOVE}Failed to create export file${C_RESET}\n"
                fi
            else
                printf "\n  ${C_MSG_REMOVE}Invalid file path${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /theme-preview ───
        if [[ "$query" == /theme-preview ]]; then
            clear
            printf "\n  ${C_WHITE}Color Scheme Preview${C_RESET}\n\n"
            printf "  ${C_GREEN}■ ${C_RESET}C_GREEN   ${C_TEAL}■ ${C_RESET}C_TEAL    ${C_AMBER}■ ${C_RESET}C_AMBER  ${C_RED}■ ${C_RESET}C_RED   ${C_WHITE}■ ${C_RESET}C_WHITE  ${C_DIM}■ ${C_RESET}C_DIM\n"
            printf "\n"
            printf "  ${C_GREEN}✓${C_RESET} ${C_GREEN}pkgs-installed${C_RESET}     ${C_INST_PREFIX} via C_INST_PREFIX\n"
            printf "  ${C_DIM}○${C_RESET} ${C_DIM}pkgs-not-installed${C_RESET}   ${C_NOT_INST_PREFIX} via C_NOT_INST_PREFIX\n"
            printf "\n"
            printf "  ${C_PKG_NAME}package-name${C_RESET}       ${C_PKG_DESC}description text${C_RESET}\n"
            printf "  ${C_MSG_INSTALL}Install text${C_RESET}     ${C_MSG_REMOVE}Remove text${C_RESET}   ${C_MSG_INFO}Info text${C_RESET}   ${C_MSG_DONE}Done text${C_RESET}\n"
            printf "\n"
            local -a sample_cmds=(/search /upgrade /info /clean /snapshot /audit /export-versions /theme-preview /keys)
            printf "  ${C_WHITE}Sample command display:${C_RESET}\n"
            local col=0
            for cmd in "${sample_cmds[@]}"; do
                printf "  ${C_TEAL}%s${C_RESET}" "$cmd"
                ((col++))
                ((col % 4 == 0)) && printf "\n"
            done
            ((col % 4 != 0)) && printf "\n"
            printf "\n  ${C_DIM}Terminal: ${TERM:-unknown}  Colors: ${COLORTERM:-16}  ${C_RESET}"
            local colors
            colors=$(tput colors 2>/dev/null || echo 16)
            printf "${C_DIM}(%d-color mode)${C_RESET}\n" "$colors"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /keys ───
        if [[ "$query" == /keys ]]; then
            clear
            printf "\n  ${C_WHITE}Fzf Keybinding Reference${C_RESET}\n\n"
            printf "  ${C_TEAL}General:${C_RESET}\n"
            printf "    ${C_DIM}Enter${C_RESET}       Confirm / select highlighted item\n"
            printf "    ${C_DIM}Esc${C_RESET}         Cancel / close fzf\n"
            printf "    ${C_DIM}Ctrl-C${C_RESET}      Cancel / close fzf\n"
            printf "    ${C_DIM}Tab${C_RESET}         Multi-select toggle\n"
            printf "    ${C_DIM}Shift-Tab${C_RESET}   Multi-select reverse toggle\n"
            printf "\n"
            printf "  ${C_TEAL}Navigation:${C_RESET}\n"
            printf "    ${C_DIM}↑/↓${C_RESET}        Move cursor up/down\n"
            printf "    ${C_DIM}PgUp/PgDn${C_RESET}   Scroll page up/down\n"
            printf "    ${C_DIM}Home/End${C_RESET}    Go to first/last item\n"
            printf "\n"
            printf "  ${C_TEAL}Search/Filter:${C_RESET}\n"
            printf "    ${C_DIM}Ctrl-R${C_RESET}      Toggle fuzzy / regex search mode\n"
            printf "    ${C_DIM}Ctrl-A${C_RESET}      Select all (multi-select mode)\n"
            printf "    ${C_DIM}Ctrl-D${C_RESET}      Deselect all\n"
            printf "    ${C_DIM}Alt-Bksp${C_RESET}    Delete word backward\n"
            printf "\n"
            printf "  ${C_TEAL}In pkgs TUI:${C_RESET}\n"
            printf "    ${C_DIM}Type any query${C_RESET}  Filter package list in real time\n"
            printf "    ${C_DIM}/command${C_RESET}        Enter a slash command instead\n"
            printf "    ${C_DIM}Tab-select${C_RESET}      Pick multiple packages then process\n"
            printf "\n"
            printf "  ${C_DIM}For full reference: https://github.com/junegunn/fzf#key-bindings${C_RESET}\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /cache-stats ───
        if [[ "$query" == /cache-stats ]]; then
            clear
            printf "\n  ${C_WHITE}Cache & Stats Dashboard${C_RESET}\n\n"
            local cache_valid=0
            [[ "$_PKGS_CACHE_VALID" == "1" ]] && cache_valid=1
            printf "  ${C_TEAL}Cache state:${C_RESET}          %s\n" "$([[ $cache_valid -eq 1 ]] && printf "${C_MSG_DONE}VALID${C_RESET}" || printf "${C_MSG_WARN}STALE${C_RESET}")"
            [[ -n "$_PKGS_CACHE_FILE" ]] && printf "  ${C_DIM}Cache file:${C_RESET}         %s\n" "$_PKGS_CACHE_FILE"
            local cache_lines=0
            [[ -n "$_PKGS_CACHE_FILE" && -f "$_PKGS_CACHE_FILE" ]] && cache_lines=$(wc -l < "$_PKGS_CACHE_FILE")
            printf "  ${C_DIM}Cached packages:${C_RESET}     %d\n" "$cache_lines"
            local total_avail
            total_avail=$(apt-cache stats 2>/dev/null | grep "^Total package names" | awk '{print $NF}' | tr -d ':' || echo 0)
            [[ -z "$total_avail" || "$total_avail" == ":" ]] && total_avail=0
            printf "  ${C_DIM}Available in apt:${C_RESET}     %d\n" "$total_avail"
            local installed_count
            installed_count=$(dpkg --get-selections 2>/dev/null | grep '\sinstall$' | wc -l)
            printf "  ${C_DIM}Installed:${C_RESET}            %d\n" "$installed_count"
            local upgradable
            upgradable=$("${PKG_MGR}" list --upgradable 2>/dev/null | tail -n +2 | wc -l)
            printf "  ${C_DIM}Upgradable:${C_RESET}           %d\n" "$upgradable"
            printf "\n"
            printf "  ${C_TEAL}History:${C_RESET}\n"
            local hist_days=0 hist_actions=0
            if [[ -d "$_PKGS_HISTORY_DIR" ]]; then
                hist_days=$(find "$_PKGS_HISTORY_DIR" -name "*.log" 2>/dev/null | wc -l)
                hist_actions=$(cat "$_PKGS_HISTORY_DIR"/*.log 2>/dev/null | wc -l || echo 0)
            fi
            printf "  ${C_DIM}History files:${C_RESET}        %d\n" "$hist_days"
            printf "  ${C_DIM}Total actions logged:${C_RESET}  %d\n" "$hist_actions"
            printf "\n"
            printf "  ${C_TEAL}Disk usage:${C_RESET}\n"
            local apt_cache_size=0 hist_dir_size=0
            apt_cache_size=$(du -sk "$PREFIX/var/cache/apt" 2>/dev/null | awk '{print $1}' || echo 0)
            printf "  ${C_DIM}apt cache:${C_RESET}             %s\n" "$(_pkgs_format_size "$apt_cache_size")"
            [[ -d "$_PKGS_HISTORY_DIR" ]] && hist_dir_size=$(du -sk "$_PKGS_HISTORY_DIR" 2>/dev/null | awk '{print $1}')
            printf "  ${C_DIM}History logs:${C_RESET}           %s\n" "$(_pkgs_format_size "$hist_dir_size")"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /suggest ───
        if [[ "$query" == /suggest* ]]; then
            local sug_pkg="${query#/suggest }"
            [[ "$sug_pkg" == "/suggest" ]] && sug_pkg=""
            clear
            if [[ -z "$sug_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Suggest alternatives for"
                sug_pkg="$_PKGS_FZF_PICKED"
                [[ -z "$sug_pkg" ]] && { printf "\n  ${C_DIM}Cancelled.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            fi
            _pkgs_validate_name "$sug_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            printf "\n  ${C_WHITE}Alternatives to ${C_TEAL}%s${C_RESET}\n\n" "$sug_pkg"
            local sug_count=0
            local -a suggests=()
            suggests=( $(apt-cache depends -- "$sug_pkg" 2>/dev/null \
                | grep -E '^\s*(Suggests|Recommends):' \
                | awk '{print $2}' \
                | sort -u) )
            if (( ${#suggests[@]} > 0 )); then
                printf "  ${C_TEAL}Suggested/recommended packages:${C_RESET}\n"
                for sp in "${suggests[@]}"; do
                    sp="${sp%|}" ; sp="${sp%>}" ; sp="${sp%<}"
                    local sp_stat=""
                    dpkg -s -- "$sp" >/dev/null 2>&1 && sp_stat="${C_MSG_DONE}  [installed]${C_RESET}" || sp_stat=""
                    printf "  ${C_DIM}  • ${C_RESET}${C_GREEN}%s${C_RESET}%s\n" "$sp" "$sp_stat"
                    ((sug_count++))
                done
            fi
            local -a depends_on=()
            depends_on=( $(apt-cache depends -- "$sug_pkg" 2>/dev/null \
                | grep -E '^\s*(Depends):' \
                | awk '{print $2}' \
                | sort -u) )
            if (( ${#depends_on[@]} > 0 )); then
                printf "  ${C_TEAL}Direct dependencies:${C_RESET}\n"
                for dp in "${depends_on[@]}"; do
                    dp="${dp%|}" ; dp="${dp%>}" ; dp="${dp%<}"
                    local dp_stat=""
                    dpkg -s -- "$dp" >/dev/null 2>&1 && dp_stat="${C_MSG_DONE}  [installed]${C_RESET}" || dp_stat=""
                    printf "  ${C_DIM}  • ${C_RESET}${C_TEAL}%s${C_RESET}%s\n" "$dp" "$dp_stat"
                    ((sug_count++))
                done
            fi
            local -a rdep=()
            rdep=( $(apt-cache rdepends -- "$sug_pkg" 2>/dev/null | tail -n +3 | head -15 | sort -u) )
            if (( ${#rdep[@]} > 0 )); then
                printf "  ${C_TEAL}Packages that depend on %s:${C_RESET}\n" "$sug_pkg"
                for rp in "${rdep[@]}"; do
                    local rp_stat=""
                    dpkg -s -- "$rp" >/dev/null 2>&1 && rp_stat="${C_MSG_DONE}  [installed]${C_RESET}" || rp_stat=""
                    printf "  ${C_DIM}  • ${C_RESET}${C_AMBER}%s${C_RESET}%s\n" "$rp" "$rp_stat"
                    ((sug_count++))
                done
                local rdep_total
                rdep_total=$(apt-cache rdepends -- "$sug_pkg" 2>/dev/null | tail -n +3 | wc -l)
                if (( rdep_total > 15 )); then
                    printf "  ${C_DIM}  ... and %d more${C_RESET}\n" "$((rdep_total - 15))"
                fi
            fi
            (( sug_count == 0 )) && printf "  ${C_DIM}No related packages found.${C_RESET}\n"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /dep-graph ───
        if [[ "$query" == /dep-graph* ]]; then
            local dg_pkg="${query#/dep-graph }"
            [[ "$dg_pkg" == "/dep-graph" ]] && dg_pkg=""
            clear
            if [[ -z "$dg_pkg" ]]; then
                _pkgs_fzf_pick_pkg "Dependency graph for"
                dg_pkg="$_PKGS_FZF_PICKED"
                [[ -z "$dg_pkg" ]] && { printf "\n  ${C_DIM}Cancelled.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            fi
            _pkgs_validate_name "$dg_pkg" || { printf "  ${C_MSG_REMOVE}Invalid package name.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            printf "\n  ${C_WHITE}Dependency tree for ${C_TEAL}%s${C_RESET}\n\n" "$dg_pkg"
            local -a visited=()
            _pkgs_dep_tree() {
                local pkg="$1" depth="$2"
                (( depth > 3 )) && return
                local indent=""
                local i
                for (( i=0; i<depth; i++ )); do indent+="  "; done
                if (( depth == 0 )); then
                    printf "  ${C_GREEN}%s${C_RESET}\n" "$pkg"
                else
                    local conn="├─"
                    printf "  ${C_DIM}%s${C_RESET}${C_TEAL}%s${C_RESET}\n" "$indent$conn " "$pkg"
                fi
                local deps
                deps=$(apt-cache depends -- "$pkg" 2>/dev/null \
                    | grep -E '^\s*(Depends):' \
                    | awk '{print $2}' \
                    | sed 's/[|><:]//g' \
                    | sort -u)
                for dep in ${(f)deps}; do
                    [[ -z "$dep" ]] && continue
                    local key="$dep"
                    if (( ${visited[(Ie)$key]} )); then
                        local indent2=""
                        for (( i=0; i<=depth; i++ )); do indent2+="  "; done
                        printf "  ${C_DIM}%s└─ ${C_AMBER}%s${C_DIM} (circ)${C_RESET}\n" "$indent2" "$dep"
                        continue
                    fi
                    visited+=("$key")
                    _pkgs_dep_tree "$dep" $((depth + 1))
                done
            }
            _pkgs_dep_tree "$dg_pkg" 0
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /batch-upgrade ───
        if [[ "$query" == /batch-upgrade ]]; then
            clear
            if ! _pkgs_check_network; then
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                clear
                query=""
                continue
            fi
            printf "\n  ${C_WHITE}Batch Upgrade Picker${C_RESET}\n\n"
            printf "  ${C_DIM}Fetching upgradable packages...${C_RESET}\n"
            local upg_list
            upg_list=$(apt list --upgradable 2>/dev/null | tail -n +2 | sed 's|/.*||' | sort -u)
            if [[ -z "$upg_list" ]]; then
                printf "\n  ${C_MSG_DONE}All packages are up-to-date.${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                clear
                query=""
                continue
            fi
            local upg_count
            upg_count=$(echo "$upg_list" | wc -l)
            printf "  ${C_DIM}Found %d upgradable packages. Launching selector...${C_RESET}\n\n" "$upg_count"
            local fzf_tmp
            fzf_tmp=$(mktemp "${TMPDIR:-${PREFIX}/tmp}/pkgs_fzf.XXXXXX") 2>/dev/null
            chmod 600 "$fzf_tmp" 2>/dev/null
            _PKGS_TMP_FILES+=("$fzf_tmp")
            echo "$upg_list" \
                | fzf --prompt=" Upgrade> " --multi --height=60% --reverse \
                    --bind="ctrl-a:select-all,ctrl-d:deselect-all" \
                    --header=" ⬆  Select packages to upgrade (Tab=multi, Ctrl+A=all, Ctrl+D=none, Enter=confirm)" \
                    > "$fzf_tmp" 2>/dev/null
            if [[ ! -s "$fzf_tmp" ]]; then
                rm -f "$fzf_tmp" 2>/dev/null
                printf "\n  ${C_DIM}Cancelled.${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                clear
                query=""
                continue
            fi
            local -a chosen=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && chosen+=("$line")
            done < "$fzf_tmp"
            rm -f "$fzf_tmp" 2>/dev/null
            printf "\n  ${C_WHITE}Upgrade ${C_TEAL}%d${C_WHITE} packages?${C_RESET}\n\n" "${#chosen[@]}"
            local pkg
            for pkg in "${chosen[@]}"; do
                printf "  ${C_GREEN}↑ %s${C_RESET}\n" "$pkg"
            done
            printf "\n  ${C_MSG_INFO}Proceed? (${C_WHITE}y${C_MSG_INFO}=yes / ${C_WHITE}Enter${C_MSG_INFO}=cancel) ${C_RESET}"
            read -q confirm; read -r
            printf "\n"
            if [[ "$confirm" == "y" ]]; then
                local ok=0 fail=0
                for pkg in "${chosen[@]}"; do
                    printf "  ${C_MSG_INFO}Upgrading %s...${C_RESET}" "$pkg"
                    if "${PKG_MGR}" install -- "$pkg" 2>/dev/null; then
                        _pkgs_log_history "UPGRADE" "$pkg"
                        printf "\r${C_MSG_DONE}  ✓ %s${C_RESET}\n" "$pkg"
                        ((ok++))
                    else
                        printf "\r${C_MSG_REMOVE}  ✗ %s failed${C_RESET}\n" "$pkg"
                        ((fail++))
                    fi
                done
                _pkgs_invalidate_cache
                printf "\n  ${C_MSG_DONE}Done: %d ok, %d failed${C_RESET}\n" "$ok" "$fail"
            else
                printf "  ${C_DIM}Cancelled.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /activity-log ───
        if [[ "$query" == /activity-log* ]]; then
            local al_days="${query#/activity-log }"
            [[ "$al_days" == "/activity-log" ]] && al_days="7"
            clear
            printf "\n  ${C_WHITE}Package Activity Log (last ${C_TEAL}%s${C_WHITE} days)${C_RESET}\n\n" "$al_days"
            if [[ ! -d "$_PKGS_HISTORY_DIR" ]]; then
                printf "  ${C_DIM}No activity log found.${C_RESET}\n"
                printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                read -r
                clear
                query=""
                continue
            fi
            local -A action_count=()
            local total_entries=0
            local cutoff
            cutoff=$(_pkgs_date_ago "$al_days" "%Y-%m-%d")
            local f
            for f in "$_PKGS_HISTORY_DIR"/*.log(N); do
                local fdate
                fdate=$(basename "$f" .log)
                [[ "$fdate" < "$cutoff" ]] && continue
                while IFS=' ' read -r ts action pkg; do
                    [[ -z "$action" || -z "$pkg" ]] && continue
                    ((action_count[$action]++))
                    ((total_entries++))
                done < "$f"
            done
            if (( total_entries == 0 )); then
                printf "  ${C_DIM}No activity in the last %s days.${C_RESET}\n" "$al_days"
            else
                printf "  ${C_DIM}Total entries: %d${C_RESET}\n\n" "$total_entries"
                local sort_order=(INSTALL REMOVE UPGRADE REINSTALL HOLD UNHOLD PURGE CLEAN RESTORE UNDO-INSTALL UNDO-REMOVE MIRROR NUKE)
                for act in "${sort_order[@]}"; do
                    local cnt=${action_count[$act]:-0}
                    (( cnt == 0 )) && continue
                    case "$act" in
                        INSTALL)     printf "  ${C_GREEN}%-20s %3d${C_RESET}\n" "Installs:" "$cnt" ;;
                        REMOVE)      printf "  ${C_RED}%-20s %3d${C_RESET}\n" "Removals:" "$cnt" ;;
                        UPGRADE)     printf "  ${C_TEAL}%-20s %3d${C_RESET}\n" "Upgrades:" "$cnt" ;;
                        REINSTALL)   printf "  ${C_AMBER}%-20s %3d${C_RESET}\n" "Reinstalls:" "$cnt" ;;
                        HOLD)        printf "  ${C_MSG_WARN}%-20s %3d${C_RESET}\n" "Holds set:" "$cnt" ;;
                        UNHOLD)      printf "  ${C_MSG_INFO}%-20s %3d${C_RESET}\n" "Holds removed:" "$cnt" ;;
                        PURGE)       printf "  ${C_RED}%-20s %3d${C_RESET}\n" "Purges:" "$cnt" ;;
                        CLEAN)       printf "  ${C_DIM}%-20s %3d${C_RESET}\n" "Cleanups:" "$cnt" ;;
                        RESTORE)     printf "  ${C_MSG_DONE}%-20s %3d${C_RESET}\n" "Restores:" "$cnt" ;;
                        UNDO-INSTALL|UNDO-REMOVE) printf "  ${C_AMBER}%-20s %3d${C_RESET}\n" "Undoes:" "$cnt" ;;
                        MIRROR)      printf "  ${C_MSG_INFO}%-20s %3d${C_RESET}\n" "Mirror changes:" "$cnt" ;;
                        NUKE)        printf "  ${C_RED}%-20s %3d${C_RESET}\n" "Nukes:" "$cnt" ;;
                        *)           printf "  ${C_DIM}%-20s %3d${C_RESET}\n" "${act}:" "$cnt" ;;
                    esac
                done
                printf "\n  ${C_WHITE}Recent entries:${C_RESET}\n"
                local recent=0
                for f in "$_PKGS_HISTORY_DIR"/*.log(N); do
                    local fdate
                    fdate=$(basename "$f" .log)
                    [[ "$fdate" < "$cutoff" ]] && continue
                    tail -5 "$f" 2>/dev/null | while IFS=' ' read -r ts act pkg; do
                        [[ -z "$act" || -z "$pkg" ]] && continue
                        [[ "$act" == "CLEAN" ]] && continue
                        (( recent >= 10 )) && break
                        local act_color="$C_DIM"
                        case "$act" in
                            INSTALL) act_color="$C_GREEN" ;; REMOVE) act_color="$C_RED" ;;
                            UPGRADE) act_color="$C_TEAL" ;; HOLD|UNHOLD) act_color="$C_AMBER" ;;
                        esac
                        printf "  ${C_DIM}%s ${act_color}%-10s${C_RESET} %s\n" "${fdate}T${ts}" "$act" "$pkg"
                        ((recent++))
                    done
                    (( recent >= 10 )) && break
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /compare ───
        if [[ "$query" == /compare* ]]; then
            local cmp_args="${query#/compare }"
            [[ "$cmp_args" == "/compare" ]] && cmp_args=""
            clear
            local cmp_p1="" cmp_p2=""
            if [[ -n "$cmp_args" ]]; then
                cmp_p1=$(echo "$cmp_args" | awk '{print $1}')
                cmp_p2=$(echo "$cmp_args" | awk '{print $2}')
            fi
            if [[ -z "$cmp_p1" ]]; then
                _pkgs_fzf_pick_pkg "First package"
                cmp_p1="$_PKGS_FZF_PICKED"
                [[ -z "$cmp_p1" ]] && { printf "\n  ${C_DIM}Cancelled.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            fi
            if [[ -z "$cmp_p2" ]]; then
                _pkgs_fzf_pick_pkg "Second package"
                cmp_p2="$_PKGS_FZF_PICKED"
                [[ -z "$cmp_p2" ]] && { printf "\n  ${C_DIM}Cancelled.${C_RESET}\n"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            fi
            _pkgs_validate_name "$cmp_p1" || { printf "  ${C_MSG_REMOVE}Invalid: %s${C_RESET}\n" "$cmp_p1"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            _pkgs_validate_name "$cmp_p2" || { printf "  ${C_MSG_REMOVE}Invalid: %s${C_RESET}\n" "$cmp_p2"; printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"; read -r; clear; query=""; continue; }
            printf "\n  ${C_WHITE}Compare: ${C_TEAL}%s${C_WHITE} vs ${C_TEAL}%s${C_RESET}\n\n" "$cmp_p1" "$cmp_p2"
            local field_a field_b
            local -a fields=()
            local -a labels=()
            fields=(Version Installed-Size Depends Recommends Suggests Section Priority)
            labels=("Version" "Size" "Depends" "Recommends" "Suggests" "Section" "Priority")
            local fmax=${#fields[@]}
            local i
            for (( i=0; i<fmax; i++ )); do
                local f="${fields[$((i+1))]}"
                local lbl="${labels[$((i+1))]}"
                local v1 v2
                v1=$(apt-cache show -- "$cmp_p1" 2>/dev/null | grep "^${f}:" | head -1 | sed "s/^${f}: //")
                v2=$(apt-cache show -- "$cmp_p2" 2>/dev/null | grep "^${f}:" | head -1 | sed "s/^${f}: //")
                if [[ "$f" == "Installed-Size" ]]; then
                    v1=$(_pkgs_format_size "${v1:-0}")
                    v2=$(_pkgs_format_size "${v2:-0}")
                fi
                local same=""
                [[ "$v1" == "$v2" ]] && same="${C_DIM} (same)${C_RESET}"
                printf "  ${C_WHITE}%s:${C_RESET}\n" "$lbl"
                printf "    ${C_GREEN}%-30s${C_RESET}\n" "${v1:---}"
                printf "    ${C_RED}%-30s${C_RESET}%s\n" "${v2:---}" "$same"
            done
            printf "\n  ${C_TEAL}Dependencies:${C_RESET}\n"
            local -a deps1 deps2
            deps1=( $(apt-cache depends -- "$cmp_p1" 2>/dev/null | grep -E '^\s*(Depends):' | awk '{print $2}' | sed 's/[|><:]//g' | sort -u) )
            deps2=( $(apt-cache depends -- "$cmp_p2" 2>/dev/null | grep -E '^\s*(Depends):' | awk '{print $2}' | sed 's/[|><:]//g' | sort -u) )
            local common=0 only1=0 only2=0
            for d in "${deps1[@]}"; do
                if (( ${deps2[(Ie)$d]} )); then
                    ((common++))
                else
                    ((only1++))
                fi
            done
            for d in "${deps2[@]}"; do
                if (( ! ${deps1[(Ie)$d]} )); then
                    ((only2++))
                fi
            done
            printf "  ${C_DIM}Common deps: ${C_RESET}%d    " "$common"
            printf "${C_GREEN}Only in %s: ${C_RESET}%d    " "$cmp_p1" "$only1"
            printf "${C_RED}Only in %s: ${C_RESET}%d\n" "$cmp_p2" "$only2"
            if (( only1 > 0 )); then
                printf "  ${C_DIM}Unique to ${C_GREEN}%s${C_DIM}:${C_RESET} " "$cmp_p1"
                local first=1
                for d in "${deps1[@]}"; do
                    (( ! ${deps2[(Ie)$d]} )) || continue
                    (( first )) || printf ", "
                    printf "%s" "$d"
                    first=0
                done
                printf "\n"
            fi
            if (( only2 > 0 )); then
                printf "  ${C_DIM}Unique to ${C_RED}%s${C_DIM}:${C_RESET} " "$cmp_p2"
                local first=1
                for d in "${deps2[@]}"; do
                    (( ! ${deps1[(Ie)$d]} )) || continue
                    (( first )) || printf ", "
                    printf "%s" "$d"
                    first=0
                done
                printf "\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # === END NEW FEATURES ===

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
        printf "\n  ${C_GREEN}Selected Packages (${C_WHITE}%d${C_GREEN})${C_RESET}\n\n" "${#selected_names[@]}"
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
            printf "\n  ${C_GREEN}Dry Run${C_RESET}\n\n"
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
                        printf "%s install \\\\\n" "$PKG_MGR"
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
                        printf "%s remove \\\\\n" "$PKG_MGR"
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
                chmod 700 "$export_file" 2>/dev/null
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

        # ─── /snapshot ───
        if [[ "$query" == /snapshot ]]; then
            clear
            local snap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/snapshots"
            mkdir -p "$snap_dir" 2>/dev/null
            local snap_file="${snap_dir}/snap-$(date +%Y%m%d-%H%M%S).txt"
            dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | sort > "$snap_file"
            local snap_count
            snap_count=$(wc -l < "$snap_file" | tr -d ' ')
            printf "\n  ${C_MSG_DONE}Snapshot saved:${C_RESET} %s\n" "$snap_file"
            printf "  ${C_DIM}%s packages captured${C_RESET}\n" "$snap_count"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /snapshot-list ───
        if [[ "$query" == /snapshot-list ]]; then
            clear
            local snap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/snapshots"
            if [[ ! -d "$snap_dir" ]] || [[ -z "$(ls -A "$snap_dir"/*.txt 2>/dev/null)" ]]; then
                printf "\n  ${C_MSG_WARN}No snapshots found.${C_RESET}\n"
                printf "  ${C_DIM}Run /snapshot to create one.${C_RESET}\n"
            else
                printf "\n  ${C_WHITE}Saved Snapshots:${C_RESET}\n\n"
                local i=1
                for f in "${snap_dir}"/snap-*.txt(N-rt); do
                    local fname="${f:t}"
                    local fdate="${fname#snap-}"
                    fdate="${fdate%.txt}"
                    fdate="${fdate//-/ }"
                    local fcount
                    fcount=$(wc -l < "$f" | tr -d ' ')
                    printf "  ${C_TEAL}%d)${C_RESET} %s  ${C_DIM}(%s packages)${C_RESET}\n" "$i" "$fdate" "$fcount"
                    ((i++))
                done
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /snapshot-restore ───
        if [[ "$query" == /snapshot-restore ]]; then
            clear
            local snap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/pkgs/snapshots"
            if [[ ! -d "$snap_dir" ]] || [[ -z "$(ls -A "$snap_dir"/*.txt 2>/dev/null)" ]]; then
                printf "\n  ${C_MSG_WARN}No snapshots found.${C_RESET}\n"
            else
                local -a snap_files=()
                for f in "${snap_dir}"/snap-*.txt(N-rt); do
                    snap_files+=("$f")
                done
                if (( ${#snap_files[@]} == 0 )); then
                    printf "\n  ${C_MSG_WARN}No snapshots found.${C_RESET}\n"
                else
                    printf "\n  ${C_WHITE}Select a snapshot to restore:${C_RESET}\n\n"
                    local snap_choice
                    snap_choice=$(printf '%s\n' "${snap_files[@]##*/}" | fzf --prompt=" Restore> " --height=40% --reverse)
                    if [[ -n "$snap_choice" ]]; then
                        local snap_path="${snap_dir}/${snap_choice}"
                        local snap_pkgs
                        snap_pkgs=(${(@f)$(awk -F'\t' '{print $1}' "$snap_path" 2>/dev/null)})
                        local current_pkgs
                        current_pkgs=(${(@f)$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)})
                        local -a snap_missing=()
                        for sp in "${snap_pkgs[@]}"; do
                            [[ -z "$sp" ]] && continue
                            local found=0
                            for cp in "${current_pkgs[@]}"; do
                                [[ "$cp" == "$sp" ]] && { found=1; break; }
                            done
                            (( found == 0 )) && snap_missing+=("$sp")
                        done
                        if (( ${#snap_missing[@]} == 0 )); then
                            printf "\n  ${C_MSG_DONE}All snapshot packages are already installed.${C_RESET}\n"
                        else
                            printf "\n  ${C_MSG_INFO}Missing packages to install: %d${C_RESET}\n\n" "${#snap_missing[@]}"
                            printf "  ${C_MSG_WARN}Install missing packages? (y/N) ${C_RESET}"
                            read -q snap_confirm; read -r
                            if [[ "$snap_confirm" == "y" ]]; then
                                local snap_ok=0 snap_fail=0
                                for sp in "${snap_missing[@]}"; do
                                    printf "  ${C_MSG_INFO}Installing %s...${C_RESET}" "$sp"
                                    if "${PKG_MGR}" install -- "$sp" 2>/dev/null; then
                                        printf "\r  ${C_MSG_DONE}Installed %s${C_RESET}\n" "$sp"
                                        ((snap_ok++))
                                    else
                                        printf "\r  ${C_MSG_REMOVE}Failed %s${C_RESET}\n" "$sp"
                                        ((snap_fail++))
                                    fi
                                done
                                printf "\n  ${C_MSG_DONE}Done:${C_RESET} %d ok, %d failed\n" "$snap_ok" "$snap_fail"
                            else
                                printf "\n  ${C_DIM}Cancelled.${C_RESET}\n"
                            fi
                        fi
                    fi
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /plan ───
        if [[ "$query" == /plan* ]]; then
            local plan_cmd="${query#/plan }"
            [[ "$plan_cmd" == "/plan" ]] && plan_cmd=""
            clear
            if [[ -z "$plan_cmd" ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /plan install <pkg>, /plan remove <pkg>, /plan upgrade${C_RESET}\n"
            elif [[ "$plan_cmd" == upgrade* ]]; then
                printf "\n  ${C_WHITE}Upgrade Plan:${C_RESET}\n\n"
                local plan_out
                plan_out=$(LANG=C apt-get upgrade --dry-run 2>&1)
                echo "$plan_out" | grep -E "^(Inst|Conf|Remv)" | head -40 | while IFS= read -r line; do
                    local ptype="${line%% *}"
                    local pdata="${line#* }"
                    case "$ptype" in
                        Inst)  printf "  ${C_GREEN}+ %-40s${C_RESET} %s\n" "${pdata%% (*}" "${pdata##* }" ;;
                        Remv)  printf "  ${C_RED}- %-40s${C_RESET}\n" "$pdata" ;;
                        Conf)  printf "  ${C_AMBER}c %-40s${C_RESET}\n" "$pdata" ;;
                    esac
                done
                printf "\n  ${C_DIM}%s${C_RESET}\n" "$(echo "$plan_out" | tail -3)"
            else
                local plan_verb plan_pkgs
                if [[ "$plan_cmd" == install* ]]; then
                    plan_verb="install"
                    plan_pkgs="${plan_cmd#install }"
                elif [[ "$plan_cmd" == remove* ]]; then
                    plan_verb="remove"
                    plan_pkgs="${plan_cmd#remove }"
                else
                    printf "\n  ${C_MSG_WARN}Usage: /plan install <pkg> or /plan remove <pkg>${C_RESET}\n"
                    printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
                    read -r
                    clear
                    query=""
                    continue
                fi
                plan_pkgs="$(_pkgs_trim "$plan_pkgs")"
                if [[ -z "$plan_pkgs" ]]; then
                    printf "\n  ${C_MSG_WARN}Usage: /plan %s <pkg>${C_RESET}\n" "$plan_verb"
                else
                    printf "\n  ${C_WHITE}Plan: %s %s${C_RESET}\n\n" "$plan_verb" "$plan_pkgs"
                    LANG=C apt-get "$plan_verb" --dry-run -- "$plan_pkgs" 2>&1 | grep -E "^(Inst|Conf|Remv|Need)" | head -30 | while IFS= read -r line; do
                        local ptype="${line%% *}"
                        local pdata="${line#* }"
                        case "$ptype" in
                            Inst)  printf "  ${C_GREEN}+ %-40s${C_RESET} %s\n" "${pdata%% (*}" "${pdata##* }" ;;
                            Remv)  printf "  ${C_RED}- %-40s${C_RESET}\n" "$pdata" ;;
                            Conf)  printf "  ${C_AMBER}c %-40s${C_RESET}\n" "$pdata" ;;
                            Need)  printf "  ${C_TEAL}? %s${C_RESET}\n" "$pdata" ;;
                        esac
                    done
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /missing ───
        if [[ "$query" == /missing ]]; then
            clear
            printf "\n  ${C_WHITE}Checking for missing dependencies...${C_RESET}\n\n"
            local miss_count=0
            while IFS=$'\t' read -r pkg deps; do
                [[ -z "$deps" || "$deps" == "(none)" ]] && continue
                echo "$deps" | tr ',' '\n' | sed 's/|.*//;s/ (.*)//;s/^ *//' | while read -r dep; do
                    [[ -z "$dep" ]] && continue
                    if ! dpkg -s "$dep" >/dev/null 2>&1; then
                        printf "  ${C_RED}✗ ${pkg}${C_RESET} needs ${C_AMBER}%s${C_RESET} (missing)\n" "$dep"
                        ((miss_count++))
                    fi
                done
            done < <(dpkg-query -W -f='${Package}\t${Depends}\n' 2>/dev/null)
            if (( miss_count == 0 )); then
                printf "  ${C_MSG_DONE}No missing dependencies found.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /compact ───
        if [[ "$query" == /compact ]]; then
            clear
            local fzf_opts="$FZF_DEFAULT_OPTS"
            if [[ "$fzf_opts" == *"--height"* ]]; then
                fzf_opts="${fzf_opts//--height=[0-9]*%?(-reverse)/}"
                printf "\n  ${C_MSG_DONE}Compact mode OFF${C_RESET} — full screen\n"
            else
                fzf_opts="--height=60% --reverse ${fzf_opts}"
                printf "\n  ${C_MSG_DONE}Compact mode ON${C_RESET} — 60%% height\n"
            fi
            FZF_DEFAULT_OPTS="$fzf_opts"
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /search-history ───
        if [[ "$query" == /search-history* ]]; then
            local sh_text="${query#/search-history }"
            [[ "$sh_text" == "/search-history" ]] && sh_text=""
            clear
            if [[ -z "$sh_text" ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /search-history <text>${C_RESET}\n"
            else
                printf "\n  ${C_WHITE}History search: %s${C_RESET}\n\n" "$sh_text"
                local sh_found=0
                if [[ -d "$_PKGS_HISTORY_DIR" ]]; then
                    for f in "${_PKGS_HISTORY_DIR}"/*.log(N); do
                        local matches
                        matches=$(grep -Fi "$sh_text" "$f" 2>/dev/null)
                        if [[ -n "$matches" ]]; then
                            local fdate="${f:t}"
                            fdate="${fdate%.log}"
                            while IFS= read -r mline; do
                                printf "  ${C_DIM}[%s]${C_RESET} %s\n" "$fdate" "$mline"
                                ((sh_found++))
                            done <<< "$matches"
                        fi
                    done
                fi
                if (( sh_found == 0 )); then
                    printf "  ${C_DIM}No matches found.${C_RESET}\n"
                else
                    printf "\n  ${C_DIM}Found %d matches${C_RESET}\n" "$sh_found"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /config ]]; then
            _pkgs_config_editor
            query=""
            continue
        fi

        # ─── /queue ───
        if [[ "$query" == /queue ]]; then
            clear
            if (( ${#_PKGS_QUEUE[@]} == 0 )); then
                printf "\n  ${C_DIM}Queue is empty.${C_RESET}\n"
                printf "  ${C_DIM}Use /queue-add <pkg> to add packages.${C_RESET}\n"
            else
                printf "\n  ${C_WHITE}Package Queue (${C_TEAL}%d${C_WHITE})${C_RESET}\n\n" "${#_PKGS_QUEUE[@]}"
                local _qi
                for _qi in "${_PKGS_QUEUE[@]}"; do
                    local _qstatus="${C_DIM}○${C_RESET}"
                    dpkg -s -- "$_qi" 2>/dev/null | grep -q '^Status: install ok installed' && _qstatus="${C_GREEN}✓${C_RESET}"
                    printf "  %s ${C_WHITE}%s${C_RESET}\n" "$_qstatus" "$_qi"
                done
                printf "\n  ${C_MSG_INFO}y=process  r=remove all  d=dry-run  Enter=cancel${C_RESET} "
                local _qaction
                read -q _qaction; read -r
                if [[ "$_qaction" == "y" ]]; then
                    local _qok=0 _qfail=0
                    local _qp
                    for _qp in "${_PKGS_QUEUE[@]}"; do
                        if dpkg -s -- "$_qp" 2>/dev/null | grep -q '^Status: install ok installed'; then
                            continue
                        fi
                        printf "  ${C_MSG_INFO}Installing %s...${C_RESET}" "$_qp"
                        if "${PKG_MGR}" install -- "$_qp" 2>/dev/null; then
                            _pkgs_log_history "INSTALL" "$_qp"
                            printf "\r${C_MSG_DONE}  ✓ %s${C_RESET}\n" "$_qp"
                            ((_qok++))
                        else
                            printf "\r${C_MSG_REMOVE}  ✗ %s failed${C_RESET}\n" "$_qp"
                            ((_qfail++))
                        fi
                    done
                    _pkgs_invalidate_cache
                    _PKGS_QUEUE=()
                    _pkgs_queue_save
                    printf "\n  ${C_MSG_DONE}Done: %d ok, %d failed${C_RESET}\n" "$_qok" "$_qfail"
                elif [[ "$_qaction" == "d" ]]; then
                    printf "\n  ${C_DIM}Dry run:${C_RESET}\n"
                    local _qp
                    for _qp in "${_PKGS_QUEUE[@]}"; do
                        local _installed_status="not installed"
                        dpkg -s -- "$_qp" 2>/dev/null | grep -q '^Status: install ok installed' && _installed_status="installed"
                        printf "  ${C_DIM}+ %s (%s)${C_RESET}\n" "$_qp" "$_installed_status"
                    done
                elif [[ "$_qaction" == "r" ]]; then
                    _PKGS_QUEUE=()
                    _pkgs_queue_save
                    printf "\n  ${C_MSG_DONE}Queue cleared.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        if [[ "$query" == /queue-add* ]]; then
            local _qa_pkg="${query#* }"
            _qa_pkg="$(_pkgs_trim "$_qa_pkg")"
            if [[ -z "$_qa_pkg" ]]; then
                printf "${C_MSG_WARN}Usage: /queue-add <pkg>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            _pkgs_validate_name "$_qa_pkg" || { sleep 1; query=""; continue; }
            _PKGS_QUEUE+=("$_qa_pkg")
            _pkgs_queue_save
            printf "${C_MSG_DONE}Added %s to queue (${C_WHITE}%d${C_MSG_DONE} total)${C_RESET}\n" "$_qa_pkg" "${#_PKGS_QUEUE[@]}"
            sleep 1
            query=""
            continue
        fi

        if [[ "$query" == /queue-remove* ]]; then
            local _qr_pkg="${query#* }"
            _qr_pkg="$(_pkgs_trim "$_qr_pkg")"
            if [[ -z "$_qr_pkg" ]]; then
                printf "${C_MSG_WARN}Usage: /queue-remove <pkg>${C_RESET}\n"
                sleep 1
                query=""
                continue
            fi
            local -a _new_queue=()
            local _found=0
            for _qitem in "${_PKGS_QUEUE[@]}"; do
                if [[ "$_qitem" == "$_qr_pkg" && $_found -eq 0 ]]; then
                    _found=1
                    continue
                fi
                _new_queue+=("$_qitem")
            done
            if (( _found )); then
                _PKGS_QUEUE=("${_new_queue[@]}")
                _pkgs_queue_save
                printf "${C_MSG_DONE}Removed %s from queue.${C_RESET}\n" "$_qr_pkg"
            else
                printf "${C_MSG_REMOVE}%s not in queue.${C_RESET}\n" "$_qr_pkg"
            fi
            sleep 1
            query=""
            continue
        fi

        if [[ "$query" == /queue-clear ]]; then
            _PKGS_QUEUE=()
            _pkgs_queue_save
            printf "${C_MSG_DONE}Queue cleared.${C_RESET}\n"
            sleep 1
            query=""
            continue
        fi

        # ─── /quick ───
        if [[ "$query" == /quick ]]; then
            clear
            printf "\n  ${C_WHITE}Quick Install — Popular Packages${C_RESET}\n\n"
            printf "  ${C_TEAL}[1]${C_RESET} Python dev      ${C_DIM}python, pip, python-numpy${C_RESET}\n"
            printf "  ${C_TEAL}[2]${C_RESET} Node.js dev     ${C_DIM}nodejs, npm, yarn${C_RESET}\n"
            printf "  ${C_TEAL}[3]${C_RESET} Go dev          ${C_DIM}go${C_RESET}\n"
            printf "  ${C_TEAL}[4]${C_RESET} Rust dev        ${C_DIM}rust${C_RESET}\n"
            printf "  ${C_TEAL}[5]${C_RESET} Git + tools     ${C_DIM}git, tig, lazygit${C_RESET}\n"
            printf "  ${C_TEAL}[6]${C_RESET} Text editors    ${C_DIM}vim, nano, micro${C_RESET}\n"
            printf "  ${C_TEAL}[7]${C_RESET} Terminal tools  ${C_DIM}tmux, jq, tree, htop${C_RESET}\n"
            printf "  ${C_TEAL}[8]${C_RESET} Networking      ${C_DIM}openssh, nmap, curl, wget${C_RESET}\n"
            printf "  ${C_TEAL}[9]${C_RESET} File managers   ${C_DIM}ranger, nnn, lf${C_RESET}\n"
            printf "  ${C_TEAL}[0]${C_RESET} Everything above\n"
            printf "\n  ${C_MSG_INFO}Choose (0-9): ${C_RESET}"
            local qchoice
            read -q qchoice; read -r
            local -a qpkgs=()
            case "$qchoice" in
                1) qpkgs=(python python-numpy python-pip) ;;
                2) qpkgs=(nodejs npm yarn) ;;
                3) qpkgs=(go) ;;
                4) qpkgs=(rust) ;;
                5) qpkgs=(git tig lazygit) ;;
                6) qpkgs=(vim nano micro) ;;
                7) qpkgs=(tmux jq tree htop) ;;
                8) qpkgs=(openssh nmap curl wget) ;;
                9) qpkgs=(ranger nnn lf) ;;
                0) qpkgs=(python python-numpy python-pip nodejs npm yarn go rust git tig lazygit vim nano micro tmux jq tree htop openssh nmap curl wget ranger nnn lf) ;;
                *) printf "\n  ${C_MSG_REMOVE}Invalid choice.${C_RESET}\n" ;;
            esac
            if (( ${#qpkgs[@]} > 0 )); then
                printf "\n  ${C_MSG_INFO}Installing %d packages...${C_RESET}\n\n" "${#qpkgs[@]}"
                local qok=0 qfail=0
                for qp in "${qpkgs[@]}"; do
                    if dpkg -s "$qp" >/dev/null 2>&1; then
                        printf "  ${C_DIM}  %s (already installed)${C_RESET}\n" "$qp"
                    else
                        printf "  ${C_MSG_INFO}  Installing %s...${C_RESET}" "$qp"
                        if "${PKG_MGR}" install -y -- "$qp" 2>/dev/null; then
                            printf "\r  ${C_MSG_DONE}  Installed %s${C_RESET}\n" "$qp"
                            ((qok++))
                        else
                            printf "\r  ${C_MSG_REMOVE}  Failed %s${C_RESET}\n" "$qp"
                            ((qfail++))
                        fi
                    fi
                done
                printf "\n  ${C_MSG_DONE}Done:${C_RESET} %d installed, %d failed\n" "$qok" "$qfail"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /fuzzy-dep ───
        if [[ "$query" == /fuzzy-dep ]]; then
            clear
            _pkgs_get_cached_list > /dev/null 2>&1
            local fd_pkg
            _pkgs_fzf_pick_pkg "Fuzzy dep explorer" "60%"; fd_pkg=$_PKGS_FZF_PICKED
            if [[ -n "$fd_pkg" ]]; then
                printf "\n  ${C_WHITE}Dependencies of: %s${C_RESET}\n\n" "$fd_pkg"
                local fd_deps
                fd_deps=$(apt-cache depends -- "$fd_pkg" 2>/dev/null | grep -E "^\w" | awk '{print $2}')
                if [[ -n "$fd_deps" ]]; then
                    while IFS= read -r dep; do
                        local installed_tag=""
                        dpkg -s "$dep" >/dev/null 2>&1 && installed_tag=" ${C_GREEN}[installed]${C_RESET}" || installed_tag=" ${C_DIM}[available]${C_RESET}"
                        printf "  ${C_TEAL}→${C_RESET} %s%s\n" "$dep" "$installed_tag"
                    done <<< "$fd_deps"
                else
                    printf "  ${C_DIM}No dependencies.${C_RESET}\n"
                fi
                printf "\n  ${C_WHITE}Reverse dependencies (what depends on %s):${C_RESET}\n\n" "$fd_pkg"
                local fd_rdeps
                fd_rdeps=$(apt-cache rdepends --installed -- "$fd_pkg" 2>/dev/null | tail -n +2)
                if [[ -n "$fd_rdeps" ]]; then
                    while IFS= read -r rdep; do
                        printf "  ${C_AMBER}←${C_RESET} %s\n" "$rdep"
                    done <<< "$fd_rdeps"
                else
                    printf "  ${C_DIM}Nothing depends on this.${C_RESET}\n"
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /size-filter ───
        if [[ "$query" == /size-filter* ]]; then
            local sf_args="${query#/size-filter }"
            [[ "$sf_args" == "/size-filter" ]] && sf_args=""
            clear
            if [[ -z "$sf_args" ]]; then
                printf "\n  ${C_MSG_WARN}Usage: /size-filter <min_KB> <max_KB>${C_RESET}\n"
                printf "  ${C_DIM}Example: /size-filter 100 5000${C_RESET}\n"
            else
                local sf_min sf_max
                sf_min=$(echo "$sf_args" | awk '{print $1}')
                sf_max=$(echo "$sf_args" | awk '{print $2}')
                if [[ -z "$sf_min" || -z "$sf_max" || ! "$sf_min" =~ ^[0-9]+$ || ! "$sf_max" =~ ^[0-9]+$ ]]; then
                    printf "\n  ${C_MSG_REMOVE}Invalid size range. Use numbers in KiB.${C_RESET}\n"
                else
                    printf "\n  ${C_WHITE}Packages between %s KiB and %s KiB:${C_RESET}\n\n" "$sf_min" "$sf_max"
                    dpkg-query -W -f='${Installed-Size}\t${Package}\n' 2>/dev/null | awk -v min="$sf_min" -v max="$sf_max" '$1 >= min && $1 <= max {print $2 "\t" $1}' | sort -t$'\t' -k2 -rn | head -30 | while IFS=$'\t' read -r spkg ssize; do
                        local sh_size
                        if (( ssize > 1024 )); then
                            sh_size="$((ssize/1024)) MB"
                        else
                            sh_size="${ssize} KB"
                        fi
                        printf "  ${C_TEAL}%-30s${C_RESET} %s\n" "$spkg" "$sh_size"
                    done
                fi
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /security ───
        if [[ "$query" == /security ]]; then
            clear
            printf "\n  ${C_WHITE}Outdated Packages:${C_RESET}\n\n"
            printf "  ${C_DIM}Checking for packages with available updates...${C_RESET}\n\n"
            local sec_count=0
            # Bulk: single apt-cache policy call for all installed packages
            local -a all_pkgs=()
            while IFS=$'\t' read -r pkg ver; do
                [[ -n "$pkg" ]] && all_pkgs+=("$pkg")
            done < <(dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null)
            local bulk_out
            bulk_out=$(_pkgs_bulk_apt_policy "${all_pkgs[@]}" 2>/dev/null)
            while read -r pkg cand; do
                [[ -z "$pkg" ]] && continue
                printf "  ${C_AMBER}↻ ${C_WHITE}%-30s${C_RESET} → %s\n" "$pkg" "$cand"
                ((sec_count++))
            done <<< "$bulk_out"
            if (( sec_count == 0 )); then
                printf "  ${C_MSG_DONE}All packages are up to date.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
            continue
        fi

        # ─── /duplicate ───
        if [[ "$query" == /duplicate ]]; then
            clear
            printf "\n  ${C_WHITE}Checking for duplicate/conflicting packages...${C_RESET}\n\n"
            local dup_found=0
            while read -r pkg; do
                local provides
                provides=$(apt-cache show -- "$pkg" 2>/dev/null | grep "^Provides:" | sed 's/^Provides: //')
                if [[ -n "$provides" ]]; then
                    echo "$provides" | tr ',' '\n' | sed 's/^ *//' | while read -r virtual; do
                        [[ -z "$virtual" ]] && continue
                        local others
                        others=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep "^${virtual}$")
                        if [[ -n "$others" && "$others" != "$pkg" ]]; then
                            printf "  ${C_AMBER}⚡ ${C_WHITE}%s${C_RESET} provides ${C_TEAL}%s${C_RESET} (also: %s)\n" "$pkg" "$virtual" "$others"
                            ((dup_found++))
                        fi
                    done
                fi
            done < <(dpkg-query -W -f='${Package}\t${Status}\n' 2>/dev/null | awk -F'\t' '$2 ~ /install ok installed/ {print $1}' | sort)
            if (( dup_found == 0 )); then
                printf "  ${C_MSG_DONE}No duplicates found.${C_RESET}\n"
            fi
            printf "\n  ${C_MSG_INFO}Press Enter to return.${C_RESET}"
            read -r
            clear
            query=""
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
            local _inst_err
            _inst_err=$("${PKG_MGR}" install -- "$pkg_name" 2>&1) && {
                _pkgs_log_history "INSTALL" "$pkg_name"
                printf "\r${C_MSG_DONE}  [%d/${total}] ✓ %s${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((ok++))
            } || {
                printf "\r${C_MSG_REMOVE}  [%d/${total}] ✗ %s failed${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((fail++))
                [[ -n "$_inst_err" ]] && printf "  ${C_DIM}%s${C_RESET}\n" "$(print -r -- "$_inst_err" | tail -2)"
            }
        done

        for pkg_name in "${to_remove[@]}"; do
            printf "${C_MSG_INFO}  [%d/${total}] remove %s...${C_RESET}" "$((ok+fail+1))" "$pkg_name"
            local _rem_err
            _rem_err=$("${PKG_MGR}" remove -- "$pkg_name" 2>&1) && {
                _pkgs_log_history "REMOVE" "$pkg_name"
                printf "\r${C_MSG_DONE}  [%d/${total}] ✓ %s${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((ok++))
            } || {
                printf "\r${C_MSG_REMOVE}  [%d/${total}] ✗ %s failed${C_RESET}\n" "$((ok+fail+1))" "$pkg_name"
                ((fail++))
                [[ -n "$_rem_err" ]] && printf "  ${C_DIM}%s${C_RESET}\n" "$(print -r -- "$_rem_err" | tail -2)"
            }
        done

        if (( ${#to_remove[@]} > 0 )); then
            local auto_out
            if auto_out=$(apt-get autoremove --dry-run 2>&1) && ! LANG=C echo "$auto_out" | grep -qE "^0 upgraded, 0 newly installed, 0 to remove"; then
                printf "\n  ${C_MSG_WARN}Remove orphaned dependencies? (y/N) ${C_RESET}"
                read -q auto_confirm; read -r
                printf "\n"
                if [[ "$auto_confirm" == "y" ]]; then
                    printf "  ${C_MSG_INFO}Cleaning up...${C_RESET}\n"
                    apt-get autoremove -y 2>/dev/null
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
    local tw
    tw=$(tput cols 2>/dev/null || echo 80)
    local nc=1
    (( tw >= 100 )) && nc=2
    (( tw >= 150 )) && nc=3
    (( tw >= 200 )) && nc=4
    (( tw >= 250 )) && nc=5
    (( tw >= 300 )) && nc=6

    printf "Usage: pkgs [OPTIONS] [QUERY]\n"
    printf "Interactive TUI package manager for Termux.\n\n"
    printf "Options:\n"
    printf "  -h, --help       Show this help message\n"
    printf "  -v, --version    Show version\n\n"
    printf "Interactive Commands (type in search box):\n"

    local -a cmds=(
        "/upgrade|Upgrade all packages" "/export-all|Export all installed"
        "/install <pkg>|Install by name" "/info <pkg>|Full package info"
        "/remove <pkg>|Remove by name" "/search <text>|Search packages"
        "/purge <pkg>|Remove + config files" "/rdeps <pkg>|Reverse dependencies"
        "/hold <pkg>|Pin (no upgrade)" "/depends-on <pkg>|Installed dependents"
        "/unhold <pkg>|Unpin package" "/deps <pkg>|Show dependencies"
        "/export <pkg>|Export install script" "/tree <pkg>|Dependency tree"
        "/compare <a> <b>|Compare packages" "/note <pkg> <text>|Add/view note"
        "/orphans|Show orphaned packages" "/orphans-safe|Safe orphans"
        "/orphans-remove|Remove all orphans" "/outdated|Packages with updates"
        "/top|Top 10 largest pkgs" "/top <n>|Top N largest pkgs"
        "/size|Total installed size" "/count|Count packages"
        "/update|Update apt cache" "/clean|Clean orphans + cache"
        "/installed|Show only installed" "/available|Show only available"
        "/recent|Show installed today" "/usage|Disk usage by section"
        "/usage <pkg>|Per-package file list" "/changelog <pkg>|Show changelog"
        "/reinstall <pkg>|Reinstall package" "/search-file <text>|Search files"
        "/download-size <pkg>|Download size" "/check|Verify packages"
        "/group|Packages by section" "/outdated-top <n>|Top N outdated"
        "/usage-top <n>|Disk usage bar chart" "/version|System version info"
        "/all|Reset filter: show all" "/sort name|size|Sort by name/size"
        "/history|View last 7 days" "/review|Today's activity"
        "/stats|Today's counts" "/backup|Export package list"
        "/restore <file>|Install from list" "/undo|Reverse last op"
        "/mirror|Switch apt mirror" "/fav <pkg>|Toggle favorite"
        "/fav-list|Show all favorites" "/fav-remove|Remove a favorite"
        "/import <file>|Install from list" "/why <pkg>|Why installed"
        "/suggest <pkg>|Recommended packages" "/nuke|Storage cleanup"
        "/whatsnew|Recent changelogs" "/tips|Termux tips"
        "/self-update|Update from GitHub" "/search-size <min> <max>|Find by size"
        "/pkg-history <pkg>|Per-pkg history" "/depends-chain <a> <b>|Dep chain"
        "/broken|Find broken packages" "/conflicts-with <pkg>|Show conflicts"
        "/provides <pkg>|Virtual packages" "/manually-installed|Manual only"
        "/auto-installed|Auto installs" "/upgrade-plan|Simulated upgrade"
        "/pkg-ages|Package age view" "/unused-libs|Orphaned libraries"
        "/maintainer <name>|Search by maintainer" "/log-search <text>|Search dpkg logs"
        "/mirror-backup|Backup/restore mirrors" "/size-histogram|Size distribution"
        "/deptree <pkg>|Visual dep tree" "/reverse-tree <pkg>|Reverse dep tree"
        "/upgrade-size|Total upgrade dl size" "/download <pkg>|Download w/o install"
        "/verify <pkg>|Verify checksums" "/mirror-latency|Ping-test mirrors"
        "/mirror-bandwidth|Bandwidth-test mirrors" "/pkg-changes|Last apt upgrade diff"
        "/pkg-recommendations <pkg>|Who recommends" "/pkg-suggests <pkg>|Who suggests"
        "/pkg-breaks <pkg>|What breaks" "/pkg-replaces <pkg>|What this replaces"
        "/owner <file>|File owner (dpkg -S)" "/removed|Removed last upgrade"
        "/new-pkgs|Installed this week" "/same-size|Same-size packages"
        "/depends-on-list <pkgs>|Shared deps" "/upgradable|Upgradable with diff"
        "/whatprovides <file>|Find binary provider" "/snap-install <file>|Install local .deb"
        "/simulate-remove <pkg>|Simulate removal" "/repo-stats|Packages per repo"
        "/download-est <pkg>|Download+install est." "/diff <pkg>|Changelog diff"
        "/snapshot|Save snapshot" "/snapshot-list|List snapshots"
        "/snapshot-restore|Restore snapshot" "/plan <cmd>|Dry-run preview"
        "/missing|Missing dependencies" "/compact|Toggle compact mode"
        "/search-history <txt>|Search history" "/quick|Popular package sets"
        "/fuzzy-dep|Dependency explorer" "/size-filter <min> <max>|Filter by size"
        "/security|Outdated pkg check" "/duplicate|Duplicate/virtual pkgs"
        "/profile|Save/restore profiles" "/check-deps|Scan missing tools"
        "/shell-hook|Shell aliases from pkgs" "/storage-report|Android storage"
        "/health|System health score" "/auto-clean|Scheduled cleanup"
        "/footprint <pkg>|Total size+transitive" "/unused|Never invoked packages"
        "/timeline|Activity map" "/schedule|Update reminders"
        "/search-providers|Find pkgs for command" "/diff-snapshots|Diff snapshots"
        "/audit|SUID/SGID scan" "/repo-check|Untrusted repo check"
        "/popular|Popular packages list" "/boot-time|Benchmark startup"
        "/disk-pressure|Storage pressure" "/pkg-impact <pkg>|Pre-install analysis"
        "/export-versions|Export with versions" "/theme-preview|Preview colors"
        "/keys|Fzf keybinding ref" "/cache-stats|Cache dashboard"
        "/dep-graph <pkg>|Visual dep tree" "/batch-upgrade|Batch upgrade picker"
        "/activity-log [days]|Package activity" "/compare <pkg1 pkg2>|Compare packages"
        "/theme|Switch color scheme" "/help|Show this help"
    )

    local cw i row cmd desc pad cmdw descw gap=2
    if (( nc <= 1 )); then
        for item in "${cmds[@]}"; do
            cmd="${item%%|*}"; desc="${item#*|}"
            printf "    %-28s %s\n" "$cmd" "$desc"
        done
    else
        local sep_w=3 total=${#cmds[@]}
        cw=$(( (tw - sep_w * (nc - 1) - 2 * nc) / nc ))
        i=0; row=""
        for item in "${cmds[@]}"; do
            ((i++))
            cmd="${item%%|*}"; desc="${item#*|}"
            cmdw=${#cmd}; descw=${#desc}
            pad=$(( cw - cmdw - descw ))
            (( pad < gap )) && pad=$gap
            printf -v pad '%*s' "$pad" ''
            row+="  ${cmd}${pad}${desc}"
            if (( i % nc == 0 )); then
                printf "%s\n" "$row"
                row=""
            elif (( i < total )); then
                row+=" │ "
            fi
        done
        [[ -n "$row" ]] && printf "%s\n" "$row"
    fi

    printf "\nKeybindings:\n"
    printf "  ?       Toggle preview     Tab     Multi-select\n"
    printf "  Ctrl-A  Select all visible Ctrl-D  Deselect all\n"
    printf "  Enter   Confirm selection  Esc     Exit\n\n"
    printf "Examples:\n"
    printf "  pkgs              Launch with no filter\n"
    printf "  pkgs vim          Launch pre-filtered for 'vim'\n"
    printf "  pkgs -h           Show this help\n"
}

pkgs "$@"
