# laptop-os: Zirconium (niri + DankMaterialShell) with NVIDIA, plus a thin personal layer.
# CI builds this daily, signs it with cosign and pushes it to GHCR (see .github/workflows/build.yml).

# Build context: scripts and files are bind-mounted into the build, never copied into the image.
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY cosign.pub /cosign.pub

# Base image: GTX 16xx / RTX NVIDIA build of Zirconium (open kernel modules, CUDA, container toolkit).
FROM ghcr.io/zirconium-dev/zirconium-nvidia:latest

# Set by CI from the GitHub repo (lowercased). Used to trust your own signing key.
ARG IMAGE_REGISTRY="ghcr.io/CHANGEME"
ARG IMAGE_NAME="laptop-os"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Fail the build if the result is not a valid bootc image.
RUN bootc container lint
