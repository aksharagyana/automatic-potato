#!/usr/bin/env bash
# Allocate non-overlapping subordinate IDs to one existing local user.
set -euo pipefail
usage() {
  echo 'Usage: sudo bash configure-rootless-user.sh [USERNAME]'
  echo 'Defaults to the user who invoked sudo (SUDO_USER).'
  echo 'Preserves existing mappings; allocates a free 65536-ID range when absent.'
}
if [[ "${1:-}" == --help ]]; then usage; exit 0; fi
if (($# > 1)); then usage >&2; exit 1; fi
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
user="${1:-${SUDO_USER:-}}"
if [[ -z "$user" || "$user" == root ]]; then
  echo 'Cannot infer a non-root sudo user. Supply an explicit username.' >&2
  exit 1
fi
[[ "$user" != -* ]] || { echo 'Invalid username.' >&2; exit 1; }
entry="$(getent passwd "$user")" || { echo 'User does not exist.' >&2; exit 1; }
uid="$(printf '%s' "$entry" | cut -d: -f3)"
[[ "$uid" -ge 1000 && "$uid" -lt 60000 ]] || { echo 'Expected a regular local user (UID 1000–59999).' >&2; exit 1; }
# Serialize this helper; coordinate with other account provisioning separately.
exec 9>/run/lock/rhel8-devops-subids.lock
flock -x 9
touch /etc/subuid /etc/subgid
chmod 0644 /etc/subuid /etc/subgid
for kind in subuid subgid; do
  if awk -F: -v u="$user" -v id="$uid" '($1==u || $1==id) && $3>0 {found=1} END {exit !found}' "/etc/$kind"; then
    echo "Preserving existing $kind mappings for $user."
    continue
  fi
  # Search both mapping files so newly allocated UID/GID ranges never overlap.
  start="$(awk -F: 'BEGIN {end=100000} $2+$3>end {end=$2+$3} END {printf "%.0f", end}' /etc/subuid /etc/subgid)"
  end=$((start + 65535))
  ((end < 4294967295)) || { echo 'No subordinate ID range available.' >&2; exit 1; }
  usermod "--add-${kind}s" "$start-$end" "$user"
done
echo "Mappings ready for $user. Log out/in, then run podman info as that user."
echo 'For an existing Podman setup, stop containers and run podman system migrate as that user.'
