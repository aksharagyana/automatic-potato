#!/usr/bin/env bash
# Install shared development tools on a registered RHEL 8 host.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: sudo bash setup.sh [--skip-code] [--docker-compat]
       bash setup.sh --help

Installs system-wide Podman, Buildah, Skopeo, Git, GitLab CLI, AWS CLI v2,
network diagnostics, and the latest stable VS Code from Microsoft's RPM repo.
  --skip-code      Skip the desktop editor on headless servers.
  --docker-compat  Install podman-docker (Docker-compatible command, not Docker Engine).
Run again to update installed tools. No user credentials are configured.
HELP
}

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
download() {
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 3 --connect-timeout 30 --max-time 600 "$@"
}

main() {
  local skip_code=0 docker_compat=0
  while (($#)); do
    case "$1" in
      --help|-h) usage; return 0 ;;
      --skip-code) skip_code=1 ;;
      --docker-compat) docker_compat=1 ;;
      *) fail "Unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  [[ "$(uname -s)" == Linux ]] || fail 'Run this on RHEL 8, not your Mac.'
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "$ID" == rhel && "${VERSION_ID%%.*}" == 8 ]] || fail 'This installer requires RHEL 8.'
  [[ $EUID -eq 0 ]] || fail 'Run with sudo: sudo bash setup.sh'
  local aws_arch glab_arch
  case "$(uname -m)" in
    x86_64) aws_arch=x86_64; glab_arch=amd64 ;;
    aarch64) aws_arch=aarch64; glab_arch=arm64 ;;
    *) fail 'Supported architectures: x86_64 and aarch64.' ;;
  esac
  umask 022
  export PATH="/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
  command -v dnf >/dev/null || fail 'dnf is required.'
  echo 'Install/update packages from enabled RHEL repositories (BaseOS and AppStream required).'
  dnf -y --refresh install ca-certificates curl unzip tar gzip jq git openssh-clients \
    shadow-utils slirp4netns fuse-overlayfs \
    bind-utils iproute iputils nmap-ncat net-tools traceroute mtr tcpdump nmap socat openssl telnet
  # Respect the administrator's enabled container-tools stream; do not reset it.
  dnf -y module install container-tools
  dnf -y upgrade podman buildah skopeo git
  if ((docker_compat)); then
    dnf -y install podman-docker
  fi

  # Shared directory is traversable by every user, even under a restrictive sudo umask.
  install -d -m 0755 /usr/local/bin
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT

  echo 'Install/update AWS CLI v2 for all users.'
  download "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "$workdir/aws.zip"
  unzip -q "$workdir/aws.zip" -d "$workdir"
  "$workdir/aws/install" --update --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
  chmod -R a+rX /usr/local/aws-cli

  echo 'Install/update GitLab CLI from the official release, with checksum verification.'
  local api='https://gitlab.com/api/v4/projects/gitlab-org%2Fcli'
  download "$api/releases/permalink/latest" -o "$workdir/release.json"
  local version asset asset_url checksum_url expected
  version="$(jq -er '.tag_name' "$workdir/release.json")"
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Unexpected GitLab CLI version: $version"
  asset="glab_${version#v}_linux_${glab_arch}.tar.gz"
  asset_url="$(jq -er --arg name "$asset" '.assets.links[] | select(.name == $name) | .url' "$workdir/release.json")"
  checksum_url="$(jq -er '.assets.links[] | select(.name == "checksums.txt") | .url' "$workdir/release.json")"
  # Only use assets served by the official GitLab domain.
  [[ "$asset_url" == https://gitlab.com/* && "$checksum_url" == https://gitlab.com/* ]] || fail 'Unexpected release asset host.'
  download "$asset_url" -o "$workdir/$asset"
  download "$checksum_url" -o "$workdir/checksums.txt"
  expected="$(awk -v name="$asset" '$2 == name || $2 == "*" name {print $1}' "$workdir/checksums.txt")"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'Missing or ambiguous release checksum.'
  (cd "$workdir" && printf '%s  %s\n' "$expected" "$asset" | sha256sum --check -)
  tar -xzf "$workdir/$asset" -C "$workdir" bin/glab
  install -o root -g root -m 0755 "$workdir/bin/glab" /usr/local/bin/glab

  if ((!skip_code)); then
    echo 'Install/update the latest stable VS Code from Microsoft.'
    rpm --import https://packages.microsoft.com/keys/microsoft.asc
    cat > /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
    chmod 0644 /etc/yum.repos.d/vscode.repo
    dnf -y --refresh install code
    dnf -y upgrade code
    rpm -q code
  fi
  # Login shells for all users can find vendor tools installed under /usr/local/bin.
  cat > /etc/profile.d/rhel8-devops-path.sh <<'PROFILE'
case ":${PATH}:" in
  *:/usr/local/bin:*) ;;
  *) export PATH="/usr/local/bin:${PATH}" ;;
esac
PROFILE
  chmod 0644 /etc/profile.d/rhel8-devops-path.sh
  podman --version
  git --version
  /usr/local/bin/aws --version
  /usr/local/bin/glab version
  echo 'Installation complete. See README.md for per-user rootless Podman and login setup.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
