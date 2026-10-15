#!/usr/bin/env bash
# Source this file from Bash to load every utils/**/*.sh into the current shell.
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf 'shell.sh requires Bash.\n' >&2
    # Executing under another shell needs exit when return is unavailable.
    # shellcheck disable=SC2317
    return 1 2>/dev/null || exit 1
fi
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'Use: source /path/to/automatic-potato/shell.sh\n' >&2
    exit 1
fi

_rhel8_load_utils() {
    local _rhel8_root _rhel8_file _rhel8_count=0
    local _rhel8_debug="${SHELL_UTILS_DEBUG:-0}"
    _rhel8_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    [[ -d "$_rhel8_root/utils" ]] || {
        printf 'Utilities directory not found: %s/utils\n' "$_rhel8_root" >&2
        return 1
    }
    if [[ "$_rhel8_debug" == 1 ]]; then
        printf '[shell-utils] Directory: %s/utils\n' "$_rhel8_root" >&2
    fi
    # GNU find/sort are included on RHEL 8. NUL delimiters handle spaces/newlines.
    # FD 3 keeps discovery separate from a utility's stdin. Do not follow symlinks.
    while IFS= read -r -d '' _rhel8_file <&3; do
        if [[ "$_rhel8_debug" == 1 ]]; then
            printf '[shell-utils] Sourcing: %s\n' "$_rhel8_file" >&2
        fi
        # shellcheck disable=SC1090
        if ! source "$_rhel8_file"; then
            printf 'Failed to source utility: %s\n' "$_rhel8_file" >&2
            return 1
        fi
        _rhel8_count=$((_rhel8_count + 1))
        if [[ "$_rhel8_debug" == 1 ]]; then
            printf '[shell-utils] Loaded: %s\n' "$_rhel8_file" >&2
        fi
    done 3< <(find "$_rhel8_root/utils" -type f -name '*.sh' -print0 | LC_ALL=C sort -z)
    if [[ "$_rhel8_count" == 0 ]]; then
        printf '[shell-utils] WARNING: No utility files loaded from %s/utils\n' "$_rhel8_root" >&2
    elif [[ "$_rhel8_debug" == 1 ]]; then
        printf '[shell-utils] Loaded %s utility file(s) into the current shell.\n' "$_rhel8_count" >&2
    fi
    return 0
}

if _rhel8_load_utils; then
    unset -f _rhel8_load_utils
else
    unset -f _rhel8_load_utils
    return 1
fi
