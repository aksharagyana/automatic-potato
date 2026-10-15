#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/repo with spaces/utils/nested/deep" "$fixture/elsewhere"
cp "$repo/shell.sh" "$fixture/repo with spaces/shell.sh"
cat > "$fixture/repo with spaces/utils/01-first.sh" <<'UTIL'
loader_order=A
first_function() { printf first; }
UTIL
cat > "$fixture/repo with spaces/utils/nested/deep/02 second.sh" <<'UTIL'
loader_order+=B
nested_function() { printf nested; }
UTIL
printf 'return 99\n' > "$fixture/repo with spaces/utils/ignored.txt"
cd "$fixture/elsewhere"
before_pwd="$PWD"
loader_order=
# shellcheck disable=SC1091
source "$fixture/repo with spaces/shell.sh"
[[ "$PWD" == "$before_pwd" && "$loader_order" == AB ]]
[[ "$(first_function)" == first && "$(nested_function)" == nested ]]
# Repeat sourcing reloads functions and picks up newly added scripts.
printf 'new_function() { :; }\n' > "$fixture/repo with spaces/utils/nested/new.sh"
# shellcheck disable=SC1091
source "$fixture/repo with spaces/shell.sh"
declare -F new_function >/dev/null
[[ "$loader_order" == AB ]]
if bash "$fixture/repo with spaces/shell.sh"; then
    echo 'Executing loader should require sourcing.' >&2; exit 1
fi
printf 'return 7\n' > "$fixture/repo with spaces/utils/00-failure.sh"
# shellcheck disable=SC1091
if source "$fixture/repo with spaces/shell.sh"; then
    echo 'Loader failed to report utility error.' >&2; exit 1
fi
rm -rf "$fixture/repo with spaces/utils"
mkdir "$fixture/repo with spaces/utils"
# shellcheck disable=SC1091
source "$fixture/repo with spaces/shell.sh"
# Source actual utilities: definitions load without cloud calls or credentials.
# shellcheck disable=SC1091
source "$repo/shell.sh"
declare -F connect_eks >/dev/null
# Diagnostic logs expose filenames and counts, not environment values.
# shellcheck disable=SC1091
SHELL_UTILS_DEBUG=1 source "$repo/shell.sh" 2>"$fixture/debug.log"
grep -q '\[shell-utils\] Directory:' "$fixture/debug.log"
grep -q '\[shell-utils\] Sourcing: .*utils/eks.sh' "$fixture/debug.log"
grep -q '\[shell-utils\] Loaded [0-9][0-9]* utility file(s)' "$fixture/debug.log"
declare -F connect_eks >/dev/null
echo 'Recursive shell loader checks passed.'
