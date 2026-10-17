# laptop-os

A thin personal layer on top of [Zirconium](https://github.com/zirconium-dev/zirconium) (Fedora bootc + niri + DankMaterialShell), NVIDIA flavour. GitHub Actions rebuilds it daily, signs it with cosign and publishes it to `ghcr.io/<you>/laptop-os`. The laptop tracks that tag with `bootc`, so updates are atomic and every change is a commit.

## What this layer adds

| Area | Change | Why |
| --- | --- | --- |
| Packages | `gh`, `mise`, `claude-code`, `podman-docker`, `nvtop`, `powertop` | Git's HTTPS credential helper at a stable path, tool manager, coding agent (signed Anthropic repo, stable channel), `docker` CLI on rootless podman, GPU and power monitors |
| Claude Code policy | `/etc/claude-code/managed-settings.json` | On this machine Claude Code always runs sandboxed, can't read credential folders and can't skip permissions; autonomous work goes in devcontainers |
| Kernel args | `nvidia.NVreg_DynamicPowerManagement=0x02` | Lets the GTX 1650 power down when idle (Turing needs it set) |
| udev | `80-nvidia-pm.rules` | Enables PCIe runtime PM on the dGPU |
| Services | `tailscaled` on, `nvidia-persistenced` off | VPN at boot; no daemon keeping the GPU awake |
| Trust | Your cosign key in the containers policy | `bootc` refuses unsigned or foreign images for this repo |

Everything else (tailscale, podman, distrobox, chezmoi, just, gcc, brew, bubblewrap, socat, NVIDIA driver, CUDA, container toolkit) already comes from Zirconium.

## Layout

```
Containerfile                  FROM zirconium-nvidia, runs build.sh, then bootc lint
build_files/build.sh           packages, repos, services, signing policy
system_files/                  copied onto / (kargs.d, udev rules, Claude Code policy)
cosign.pub                     your public signing key (placeholder until setup step 3)
.github/workflows/build.yml    build and push on every run; sign from main only, daily at 05:17 UTC
Justfile                       keygen, release-env, verify, switch, status, rollback, lint
```

## One-time setup

Run these in this folder with `gh` logged in (`gh auth login`, HTTPS).

1. **Commit and create the repo** (public, named `laptop-os`, or change `image` in the Justfile):
   `git init -b main && git add -A && git commit -m "laptop-os: initial scaffold"`, then `gh repo create laptop-os --public --source=. --remote=origin`.
2. **Signing key:** `just keygen` (cosign in a container, no password), then `git add cosign.pub && git commit -m "Add signing public key"`.
3. **Protected signing:** `just release-env` creates a `release` environment that only `main` can deploy to and stores `cosign.key` in it as `SIGNING_SECRET`. A workflow pushed on any other branch can't read it. Then move `cosign.key` into your password vault and `shred -u cosign.key`.
4. **Build:** `git push -u origin main`, then `gh run watch`. The first build takes 10–20 minutes.
5. **Make the package public:** github.com/users/&lt;you&gt;/packages/container/laptop-os/settings → Change visibility → Public, so `bootc` can pull without credentials. `just verify` passing confirms it is public and signed.

## Switching the laptop to it

```bash
just switch-first     # sudo bootc switch ghcr.io/<you>/laptop-os:latest
systemctl reboot
just switch           # same, now enforcing your signature policy
systemctl reboot
just status           # the booted image should read ostree-image-signed:docker://ghcr.io/<you>/laptop-os:latest
```

The first switch runs under Zirconium's policy, which doesn't know your key yet. The second runs under yours and proves the signing chain end to end.

## Day-2

- **Updates:** Zirconium's `uupd.timer` stages a new image daily at 04:00 (skipped on low battery). It applies on the next reboot. `just upgrade` stages one now.
- **Rollback:** `just rollback`, then reboot. Or pick the previous entry in the boot menu.
- **Pin a known-good build:** `sudo bootc switch --enforce-container-sigpolicy ghcr.io/<you>/laptop-os:YYYYMMDD`.
- **Add a system package:** add it to the `dnf5 -y install` list in `build_files/build.sh`, commit, push. CI builds, the laptop picks it up overnight.
- **Try a package without a build:** `sudo bootc usroverlay` gives a writable `/usr` until the next reboot.
- **Loosen the Claude Code policy** (for example, allow a domain for every project): edit `system_files/etc/claude-code/managed-settings.json` and push. Users can add rules but can't override it.

## Security notes

- **What protects the image:** `main` is the only branch that can sign, and the laptop only accepts signed images. What it can't stop is someone holding your GitHub token pushing to `main`. So coding agents never get your token: the host sandbox blocks the keyring and `~/.config/gh`, and devcontainers get their own scoped token.
- **Secure Boot:** off for now. Zirconium's NVIDIA module is unsigned. Signing it with your own MOK in this build is a later project.
- **Fedora version:** you follow Zirconium. When it moves to Fedora 45, so does this image, with no reinstall.
- **Lint locally:** `just lint` (needs `shellcheck` and `actionlint`, both in the dotfiles' mise config).

Workflow adapted from [ublue-os/image-template](https://github.com/ublue-os/image-template) (Apache-2.0).
