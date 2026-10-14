#!/usr/bin/env bash
# Run only in a disposable container, as root; creates test accounts.
set -euo pipefail
helper="${1:-/setup/configure-rootless-user.sh}"
useradd -m testalice
useradd -m testbob
# Remove automatically created mappings to exercise the helper's allocator.
for name in testalice testbob; do
  sed -i "/^${name}:/d" /etc/subuid /etc/subgid
done
bash "$helper" testalice
bash "$helper" testbob
before="$(cat /etc/subuid /etc/subgid)"
bash "$helper" testalice
[[ "$before" == "$(cat /etc/subuid /etc/subgid)" ]]
# Every assigned interval is disjoint, and the size supports rootless containers.
awk -F: '
  $1 ~ /^test(alice|bob)$/ {
    if ($3 < 65536) exit 1
    for (i=0;i<n;i++) if ($2 < ends[i] && $2+$3 > starts[i]) exit 1
    starts[n]=$2; ends[n]=$2+$3; n++
  }
  END {if (n != 4) exit 1}
' /etc/subuid /etc/subgid
if bash "$helper" nonexistent_test_user; then
  echo 'Unknown account was unexpectedly accepted' >&2; exit 1
fi
echo 'Rootless mapping allocation, non-overlap, idempotence, and unknown-user checks passed.'
