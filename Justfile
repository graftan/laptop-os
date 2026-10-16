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
    @echo "Now: add cosign.key as the SIGNING_SECRET repo secret, commit cosign.pub, then delete or vault cosign.key"

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
