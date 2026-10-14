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
SUDO_USER=testalice bash "$helper"
# Explicit target overrides the sudo caller.
SUDO_USER=testalice bash "$helper" testbob
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
for caller in '' root; do
  if SUDO_USER="$caller" bash "$helper"; then
    echo 'Ambiguous/root caller was unexpectedly accepted' >&2; exit 1
  fi
done
if bash "$helper" testalice testbob; then
  echo 'Extra arguments were unexpectedly accepted' >&2; exit 1
fi
[[ "$before" == "$(cat /etc/subuid /etc/subgid)" ]]
echo 'Rootless mapping, default sudo user, explicit override, and rejection checks passed.'

# Enterprise-sized UIDs must be accepted, without overlapping real host IDs.
useradd -m -u 1200000000 testhigh
sed -i '/^testhigh:/d' /etc/subuid /etc/subgid
SUDO_USER=testhigh bash "$helper"
for file in /etc/subuid /etc/subgid; do
  awk -F: '$1=="testhigh" {if ($2<=1200000000 || $3!=65536) exit 1; found=1} END {if (!found) exit 1}' "$file"
done
# Model a directory user visible through NSS but absent from /etc/passwd.
getent() {
  if [[ "${1:-}" == passwd && "${2:-}" == directoryuser ]]; then
    echo 'directoryuser:x:1300000000:1300000000:Directory User:/home/directoryuser:/bin/bash'
  else
    command getent "$@"
  fi
}
export -f getent
SUDO_USER=directoryuser bash "$helper"
before="$(cat /etc/subuid /etc/subgid)"
SUDO_USER=directoryuser bash "$helper"
[[ "$before" == "$(cat /etc/subuid /etc/subgid)" ]]
for file in /etc/subuid /etc/subgid; do
  awk -F: '$1=="directoryuser" {if ($2<=1300000000 || $3!=65536) exit 1; found=1} END {if (!found) exit 1}' "$file"
done
echo 'High-UID and directory-user regression checks passed.'

# Do not modify files when a central subordinate-ID provider is configured.
printf '\nsubid: sss\n' >> /etc/nsswitch.conf
if SUDO_USER=directoryuser bash "$helper"; then
  echo 'Central subid provider was unexpectedly bypassed' >&2; exit 1
fi
[[ "$before" == "$(cat /etc/subuid /etc/subgid)" ]]
