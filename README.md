# RHEL 8 DevOps setup

Install development tools once, system-wide, for all users of a RHEL 8 machine.
Supports x86_64 and aarch64. Requires working RHEL BaseOS and AppStream repositories
(subscription or an administrator-managed mirror), sudo/root, and outbound HTTPS.

## Install

```bash
git clone https://github.com/aksharagyana/automatic-potato.git
cd automatic-potato
bash setup.sh --help
sudo bash setup.sh
```

On a headless server, use `sudo bash setup.sh --skip-code`. To provide a `docker`
command backed by Podman, use `--docker-compat`. This is the RHEL `podman-docker`
compatibility package; it does not install Docker Engine or guarantee every Docker
API/Compose feature. The installer respects your enabled container-tools module
stream and never resets it or removes an existing container engine.

Rerun the installer to update AWS CLI, GitLab CLI, VS Code and the selected RHEL
tools. It does not perform a whole-system upgrade. A failed download/package
installation stops the script; successful previous steps remain installed.

## Installed tools

| Component | Installation and availability |
|---|---|
| Podman, Buildah, Skopeo | RHEL container-tools module; system commands |
| Git and OpenSSH client | RHEL packages; works with GitLab and other Git servers |
| GitLab CLI (`glab`) | Latest official Linux release, SHA-256 checked, `/usr/local/bin/glab` |
| AWS CLI v2 (`aws`) | Latest official bundled installer, `/usr/local/aws-cli`, links in `/usr/local/bin` |
| VS Code (`code`) | Latest stable package available in Microsoft's signed RPM repository |
| Networking | curl, dig/nslookup, ip/ss, ping, nc/ncat, netstat, traceroute, mtr, tcpdump, nmap, socat, OpenSSL, Telnet, jq |

AWS downloads use the official HTTPS endpoint; this installer does not additionally
verify AWS's detached PGP signature. GitLab checksums are obtained from its official
release. VS Code/RHEL packages retain RPM signature verification.

Root owns shared programs, with permissions allowing other users to run them.
`/usr/local/bin` is added for all login shells. Existing terminals can run
`export PATH="/usr/local/bin:$PATH"`; services/CI jobs should set PATH explicitly.
The script does not install software inside `/root` or share login tokens.

## Each user: Podman

Rootless Podman keeps each user's containers and images separate. It needs
subordinate UID/GID mappings. For each **existing local user**, an administrator runs:

```bash
sudo bash configure-rootless-user.sh alice
sudo bash configure-rootless-user.sh bob
```

The helper preserves existing mappings, allocates unused ranges when absent, and
serializes concurrent uses of this helper. Coordinate with LDAP/central identity
and other account provisioning tools before assigning ranges; those systems are
outside this helper's scope. It does not create accounts or grant sudo access.

Then, as each user in a fresh login session:

```bash
podman info
podman run --rm registry.access.redhat.com/ubi8/ubi echo hello
```

If mappings changed for an existing Podman setup, stop the user's containers and
run `podman system migrate` as that user. Home directories for rootless container
storage must be on a supported local filesystem, not NFS. Administrator policies
must permit user namespaces. No Docker group or shared privileged socket is needed.

## Each user: AWS and GitLab

Run these **without sudo**, so credentials belong to the correct user:

```bash
aws configure sso
aws sso login --profile my-profile
aws sts get-caller-identity --profile my-profile

glab auth login --hostname gitlab.com
# For work: replace gitlab.com with your organization's GitLab hostname.
glab auth status
glab repo clone group/project

git config --global user.name 'Your name'
git config --global user.email 'your-email@example.com'
```

AWS profiles live in `~/.aws`; GitLab credentials/settings live in the user's
keyring/configuration. Use `glab auth login` to select HTTPS or SSH. For SSH, create
and register each user's own key with GitLab. Do not copy administrator credentials
to other users. CI can inject `GITLAB_TOKEN`, `GITLAB_HOST`, and appropriate AWS
credentials/identity configuration at runtime.

## VS Code

Launch `code .` as a regular user in a graphical desktop session. Installation is
shared; extensions and settings are per-user. A headless RHEL server can instead be
accessed using VS Code Remote SSH from a desktop. No display server is installed.
The latest vendor release must still support RHEL 8's system libraries; package
resolution will fail rather than bypass dependency or signature checks.

## Verify as a regular user

```bash
podman --version
git --version
glab version
aws --version
command -v code  # unless --skip-code
command -v dig ss nc telnet tcpdump
```

Packet capture and some network probes may require elevated privileges. Installing
their binaries system-wide does not grant every user packet-capture privileges.

## Sources

- [RHEL 8 container tools and rootless containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/assembly_starting-with-containers_building-running-and-managing-containers)
- [VS Code Linux installation](https://code.visualstudio.com/docs/setup/linux)
- [AWS CLI installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [GitLab CLI](https://gitlab.com/gitlab-org/cli)
- [GitLab authentication](https://docs.gitlab.com/cli/authentication/)

## Validation

Run `shellcheck setup.sh configure-rootless-user.sh tests/rootless.sh` and
`docker build -f tests/Containerfile -t rhel8-rootless-tests .`. The container test
checks subordinate ID allocation, non-overlap, repeated execution, and rejection
of unknown accounts. It does not launch nested Podman containers.

Full installation requires registered RHEL repositories. Public UBI 8 repositories
do not include every diagnostic package (including traceroute, tcpdump, and telnet),
so a UBI-only full install is not supported. Validate GUI launch, rootless containers,
and cloud logins on your target RHEL host before using it as a standard image.
