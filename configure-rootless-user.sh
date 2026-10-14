#!/usr/bin/env bash
# Allocate non-overlapping subordinate IDs to one existing NSS-resolvable user.
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
user="$(printf '%s' "$entry" | cut -d: -f1)"
uid="$(printf '%s' "$entry" | cut -d: -f3)"
if ! [[ "$uid" =~ ^[0-9]+$ ]] || ((uid <= 0 || uid >= 4294967295)); then
  echo 'Expected an existing non-root account with a valid numeric UID.' >&2; exit 1
fi
# A directory-managed subid provider must be configured through that provider.
provider="$(awk '$1 == "subid:" {print $2}' /etc/nsswitch.conf)"
if [[ -n "$provider" && "$provider" != files ]]; then
  echo "Subordinate IDs are managed by '$provider'; configure them through your identity administrator." >&2
  exit 1
fi
# Keep new ranges above visible host IDs as well as existing subordinate ranges.
# Some directories disable enumeration; administrators must reserve ranges centrally.
host_end="$( { getent passwd; getent group; printf '%s\n' "$entry"; } |
  awk -F: 'BEGIN {end=100000} $3+1>end {end=$3+1} END {printf "%.0f", end}')"
gid="$(printf '%s' "$entry" | cut -d: -f4)"
((host_end > gid)) || host_end=$((gid + 1))
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
  start="$(awk -F: -v floor="$host_end" 'BEGIN {end=floor} $2+$3>end {end=$2+$3} END {printf "%.0f", end}' /etc/subuid /etc/subgid)"
  end=$((start + 65535))
  ((end < 4294967295)) || { echo 'No subordinate ID range available.' >&2; exit 1; }
  # usermod requires /etc/passwd membership and rejects SSSD/AD users.
  # File-backed subids can use the canonical NSS username for either account type.
  printf '%s:%s:65536\n' "$user" "$start" >> "/etc/$kind"
done
echo "Mappings ready for $user. Log out/in, then run podman info as that user."
echo 'For an existing Podman setup, stop containers and run podman system migrate as that user.'
