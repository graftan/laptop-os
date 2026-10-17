# Local helpers for laptop-os. CI does the real builds; these are for testing and day-2 ops.

image := "laptop-os"
owner := `git config --get remote.origin.url 2>/dev/null | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#/.*$##' | tr '[:upper:]' '[:lower:]'`
registry := "ghcr.io/" + owner
ref := registry + "/" + image + ":latest"
cosign := "ghcr.io/sigstore/cosign/cosign:v3.1.2"

[private]
default:
    @just --list

# Build the image locally with podman (needs ~20 GB free)
build:
    podman build --pull=newer \
      --build-arg IMAGE_REGISTRY={{ registry }} \
      --build-arg IMAGE_NAME={{ image }} \
      --tag localhost/{{ image }}:latest .

# Lint the build script and the workflow (tools come from mise)
lint:
    shellcheck build_files/*.sh
    actionlint .github/workflows/*.yml
    just --unstable --fmt --check

# Generate the cosign key pair in this folder (cosign.key must never be committed)
keygen:
    podman run --rm --user 0 -e COSIGN_PASSWORD= -v "$PWD":/w:Z -w /w {{ cosign }} generate-key-pair
    @echo "Now: commit cosign.pub, run 'just release-env', then vault and delete cosign.key"

# Create the 'release' environment (main branch only) and store cosign.key in it
release-env:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f cosign.key || { echo "cosign.key not found: run 'just keygen' first" >&2; exit 1; }
    printf '%s' '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
      | gh api -X PUT "repos/{owner}/{repo}/environments/release" --input - > /dev/null
    if ! gh api "repos/{owner}/{repo}/environments/release/deployment-branch-policies" \
        --jq '.branch_policies[].name' | grep -qx main; then
      gh api -X POST "repos/{owner}/{repo}/environments/release/deployment-branch-policies" \
        -f name=main -f type=branch > /dev/null
    fi
    gh secret set SIGNING_SECRET --env release < cosign.key
    echo "release environment ready: deployable from main only, SIGNING_SECRET stored"

# Check the published image's signature against cosign.pub
verify:
    podman run --rm -v "$PWD/cosign.pub":/cosign.pub:ro,Z {{ cosign }} \
      verify --new-bundle-format=false --key /cosign.pub {{ ref }}

# Show booted, staged and rollback deployments
status:
    sudo bootc status

# Move this machine to your image, verifying signatures from now on
switch:
    sudo bootc switch --enforce-container-sigpolicy {{ ref }}

# First move from stock Zirconium (your policy only exists once you boot your image)
switch-first:
    sudo bootc switch {{ ref }}

# Stage the latest image now instead of waiting for the nightly updater
upgrade:
    sudo bootc upgrade

# Boot the previous deployment next time
rollback:
    sudo bootc rollback
