#!/usr/bin/env bash
# Runs once inside the image build (see Containerfile). Keep it boring:
# files, packages, services, trust. Anything per-user belongs in your dotfiles.
set -euxo pipefail

: "${IMAGE_REGISTRY:?build arg IMAGE_REGISTRY is missing}"
: "${IMAGE_NAME:?build arg IMAGE_NAME is missing}"
if [[ "${IMAGE_REGISTRY}" == *CHANGEME* ]]; then
    echo "IMAGE_REGISTRY is still the placeholder; build with 'just build' or in CI" >&2
    exit 1
fi

DNF="$(command -v dnf5 || command -v dnf)"
FEDORA_VERSION="$(rpm -E %fedora)"
REPOS_D=/etc/yum.repos.d
mkdir -p "${REPOS_D}"

### 1. Static files: kernel args and udev rules for NVIDIA runtime power management
cp -avf /ctx/system_files/. /

### 2. Packages from Fedora
# Zirconium already ships tailscale, podman, distrobox, chezmoi, just, gcc, brew,
# nvidia-container-toolkit and nvctk-cdi.service. Only add what is missing.
"${DNF}" -y install \
    nvtop \
    powertop

### 3. Packages from third-party repos, enabled for this build only
# mise (per-user tool manager): COPR jdxcode/mise
curl -fsSL --retry 3 -o "${REPOS_D}/jdxcode-mise.repo" \
    "https://copr.fedorainfracloud.org/coprs/jdxcode/mise/repo/fedora-${FEDORA_VERSION}/jdxcode-mise-fedora-${FEDORA_VERSION}.repo"

# Claude Code: Anthropic's signed rpm repo, stable channel. Check the key fingerprint
# published at https://code.claude.com/docs/en/setup before trusting it.
CLAUDE_KEY_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
curl -fsSL --retry 3 -o /tmp/claude-code.asc https://downloads.claude.ai/keys/claude-code.asc
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
fpr="$(gpg --show-keys --with-colons /tmp/claude-code.asc | awk -F: '$1 == "fpr" && !seen { print $10; seen = 1 }')"
if [[ "${fpr}" != "${CLAUDE_KEY_FPR}" ]]; then
    echo "Claude Code signing key fingerprint mismatch: got '${fpr}'" >&2
    exit 1
fi
rpm --import /tmp/claude-code.asc
cat > "${REPOS_D}/claude-code.repo" <<'EOF'
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=file:///tmp/claude-code.asc
EOF

"${DNF}" -y install mise claude-code
rm -f "${REPOS_D}/jdxcode-mise.repo" "${REPOS_D}/claude-code.repo"

### 4. Services
systemctl enable tailscaled.service
# A persistence daemon keeps the dGPU awake; a laptop wants it powered down when idle.
systemctl disable nvidia-persistenced.service 2>/dev/null || true

### 5. Trust your own signing key for this image
if ! grep -q 'BEGIN PUBLIC KEY' /ctx/cosign.pub; then
    echo "cosign.pub is still a placeholder: generate a key pair first (README, step 2)" >&2
    exit 1
fi
KEY_PATH="/usr/share/pki/containers/${IMAGE_NAME}.pub"
install -Dm0644 /ctx/cosign.pub "${KEY_PATH}"

# Zirconium keeps the real policy in /usr/share/factory and symlinks /etc/containers/*
# to it at boot (tmpfiles "L+"), so edit the factory copy. Plain Fedora bases use /etc.
FACTORY=/usr/share/factory/etc/containers
if [[ -f "${FACTORY}/policy.json" ]]; then
    POLICY="${FACTORY}/policy.json"
    REGISTRIES_D="${FACTORY}/registries.d"
else
    POLICY=/etc/containers/policy.json
    REGISTRIES_D=/etc/containers/registries.d
fi

jq --arg repo "${IMAGE_REGISTRY}/${IMAGE_NAME}" --arg key "${KEY_PATH}" \
    '.transports.docker[$repo] = [{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}]' \
    "${POLICY}" > /tmp/policy.json
install -m0644 /tmp/policy.json "${POLICY}"

mkdir -p "${REGISTRIES_D}"
cat > "${REGISTRIES_D}/${IMAGE_NAME}.yaml" <<EOF
docker:
  ${IMAGE_REGISTRY}/${IMAGE_NAME}:
    use-sigstore-attachments: true
EOF
if [[ "${REGISTRIES_D}" == "${FACTORY}/registries.d" ]]; then
    echo "L+ /etc/containers/registries.d/${IMAGE_NAME}.yaml" \
        > "/usr/lib/tmpfiles.d/50-${IMAGE_NAME}-registries.conf"
fi

### 6. Sanity checks: fail here rather than ship a broken image
jq -e --arg repo "${IMAGE_REGISTRY}/${IMAGE_NAME}" '.transports.docker[$repo]' "${POLICY}" > /dev/null
for bin in mise claude tailscale nvidia-smi nvidia-ctk nvtop powertop; do
    command -v "${bin}" > /dev/null || { echo "missing ${bin}" >&2; exit 1; }
done
