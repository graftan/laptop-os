# laptop-os

A thin personal layer on top of [Zirconium](https://github.com/zirconium-dev/zirconium) (Fedora bootc + niri + DankMaterialShell), NVIDIA flavour. GitHub Actions rebuilds it daily, signs it with cosign and publishes it to `ghcr.io/<you>/laptop-os`. The laptop tracks that tag with `bootc`, so updates are atomic and every change is a commit.

## What this layer adds

| Area | Change | Why |
| --- | --- | --- |
| Packages | `mise`, `claude-code`, `nvtop`, `powertop` | Tool manager, coding agent (signed Anthropic repo, stable channel), GPU and power monitors |
| Kernel args | `nvidia.NVreg_DynamicPowerManagement=0x02` | Lets the GTX 1650 power down when idle (Turing needs it set) |
| udev | `80-nvidia-pm.rules` | Enables PCIe runtime PM on the dGPU |
| Services | `tailscaled` on, `nvidia-persistenced` off | VPN at boot; no daemon keeping the GPU awake |
| Trust | Your cosign key in the containers policy | `bootc` refuses unsigned or foreign images for this repo |

Everything else (tailscale, podman, distrobox, chezmoi, just, gcc, brew, NVIDIA driver, CUDA, container toolkit) already comes from Zirconium.

## Layout

```
Containerfile                  FROM zirconium-nvidia, runs build.sh, then bootc lint
build_files/build.sh           packages, repos, services, signing policy
system_files/                  copied onto / (kargs.d, udev rules)
cosign.pub                     your public signing key (placeholder until step 2)
.github/workflows/build.yml    build, push, sign; daily at 05:17 UTC
Justfile                       keygen, verify, switch, status, rollback, lint
```

## One-time setup

1. **Create the repo** on GitHub as **public** (named `laptop-os`, or change `image` in the Justfile), then push this folder to `main`.
2. **Signing key.** In the repo folder run `just keygen` (cosign in a container, no password). Add the contents of `cosign.key` as the Actions secret `SIGNING_SECRET` (Settings → Secrets and variables → Actions), commit `cosign.pub`, then move `cosign.key` into your password vault and delete it from disk.
3. **Build.** Push to `main` (or Actions → Build image → Run workflow). The first build takes 10–20 minutes.
4. **Make the package public.** Open the package from the repo's sidebar → Package settings → Change visibility → Public, so `bootc` can pull without credentials.

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

## Notes

- **Secure Boot:** off for now. Zirconium's NVIDIA module is unsigned. Signing it with your own MOK in this build is a later project.
- **Fedora version:** you follow Zirconium. When it moves to Fedora 45, so does this image, with no reinstall.
- **Lint locally:** `just lint` (needs `shellcheck` and `actionlint`, both in the dotfiles' mise config).

Workflow adapted from [ublue-os/image-template](https://github.com/ublue-os/image-template) (Apache-2.0).
