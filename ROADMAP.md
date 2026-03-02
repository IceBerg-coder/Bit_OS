# BitOS Development Roadmap

## Current Baseline (v1.5)

- 21MB ISO, Linux 6.6.15 (kernel build #5), BusyBox 1.36.1, OpenSSH 9.9p2
- RAM-only root FS, 20 packages, bpm v1.5 with dep-aware install + RSA-signed repository
- HTTPS (socat + openssl), iptables firewall (xt_recent/limit/hashlimit), web dashboard, bash shell
- Boot splash `[  OK  ]` / `[FAIL]` per service, GRUB2 EFI hybrid ISO, boot log CGI
- S05-hostname, S00-restore, S02-netconf persistent network config

---

## Phase 1 — Foundation Hardening `v1.x` ✅ *COMPLETE*

> Make what exists production-quality before expanding.

### 1.1 — Persistent Root FS ✅
- `switch_root` into a real ext4 partition at boot instead of staying in initramfs RAM
- Root on `/dev/sda1`, `/home` as separate partition
- `overlayfs`: read-only squashfs base + writable upper layer (Alpine live-mode style)
- Packages installed via `bpm` survive reboots

### 1.2 — Boot Polish ✅
- `[  OK  ]` / `[FAIL]` splash per service during `rcS.d`
- GRUB2 EFI hybrid ISO (BIOS + UEFI on one image)
- Boot log CGI accessible in the web dashboard

### 1.3 — netconf Boot Hook ✅
- `S00-restore` restores `/etc` from persistent disk on boot
- `S02-netconf` applies saved `/etc/network/*.conf` on every boot
- `S05-hostname` sets hostname before httpd starts

### 1.4 — bpm Dependency Declarations ✅
- `packages.list` updated to 5-field format: `name version sha256 deps description`
- `bpm install bit-ssl` auto-installs `bit-net` before installing `bit-ssl`
- `bpm remove` blocked with a message if another installed package depends on the target
- Repository list signed with RSA-2048; verified with `/etc/bpm_pubkey.pem` on every fetch
- New `bpm info <pkg>` subcommand — version, deps, installed status, description

**Milestone: v1.2** ✅ — Persistent root + netconf boot hook + GRUB EFI *(shipped)*
**Milestone: v1.5** ✅ — Dep-aware bpm + RSA-signed repo + boot splash + bpm info *(shipped)*

---

## Phase 2 — Real Userspace `v2.0` *(1–3 months)*

> The biggest single leap — move from BusyBox-only to a proper software stack.

### 2.1 — musl libc Base
- Replace uClibc-ng (BusyBox internal) with **musl libc** as the system libc
- Enables compiling real software natively inside BitOS
- Chosen over glibc for size (~640KB), MIT license, clean ABI — same as Alpine Linux

### 2.2 — Native C Toolchain
- Cross-compile `gcc` + `binutils` + `make` targeting musl
- Bundle as optional `dev-tools` meta-package (~30MB)
- Allows building any software from source inside BitOS

### 2.3 — Package Count Sprint to 100

| Category | Target Packages |
|---|---|
| Editors | `vim`, `nano`, `sed`, `awk` (real GNU versions) |
| Network | `curl`, `wget`, `nmap`, `tcpdump`, `netcat` |
| Scripting | `Python 3` (musl static), `Lua` |
| Crypto/TLS | `ca-certificates`, `gnupg` |
| Filesystem | `rsync`, `lsof`, `strace`, `file` |
| Compression | `xz`, `bzip2`, `zstd`, `unzip` |
| Dev | `git`, `patch`, `diffutils` |

### 2.4 — Package Signing (GPG)
- Generate a BitOS repo signing key
- Sign `packages.list` → `packages.list.sig`
- `bpm install` verifies GPG sig before SHA256 content check

**Milestone: v2.0** — musl libc + 100 packages + gcc toolchain

---

## Phase 3 — Init & Service Architecture `v2.x` *(2–4 months)*

> Replace flat `rcS` with a proper supervision tree.

### 3.1 — s6 Init (PID 1 Replacement)
- `s6` by skarnet — tiny (~100KB), reliable, POSIX
- Supervised services: auto-restart on crash, per-service logging built-in
- `s6-rc` for dependency ordering between services
- Replaces: `rcS.d/*` scripts + BusyBox init + `svc()` shell function

### 3.2 — eudev (udev Replacement)
- Replace `mdev` with `eudev` for proper hotplug, persistent device names, firmware loading
- Required for USB, PCIe hotplug, WiFi adapters

### 3.3 — Structured Logging
- `syslog-ng` or `metalog` with log levels, log rotation, remote syslog (RFC 5424)
- `bit-log` updated to read structured logs

**Milestone: v2.5** — s6 init + eudev + structured logging

---

## Phase 4 — Security Layer `v3.0` *(3–6 months)*

> Match Ubuntu/Debian security baseline.

### 4.1 — PAM (Pluggable Authentication Modules)
- Required for `sudo`, `su`, SSH keyboard-interactive, account locking
- Build `Linux-PAM` against musl, minimal modules: `pam_unix`, `pam_limits`, `pam_env`

### 4.2 — sudo
- Build `sudo` against musl + PAM
- `/etc/sudoers` with `visudo`

### 4.3 — Hardened Kernel Config
- Enable: `CONFIG_SECURITY`, `CONFIG_SECCOMP`, `CONFIG_SECCOMP_FILTER`
- Enable: `CONFIG_STACKPROTECTOR_STRONG`, `CONFIG_RANDOMIZE_BASE` (ASLR)
- Enable: `CONFIG_FORTIFY_SOURCE`
- Disable: `/proc/kcore`, `kexec`, `CONFIG_MAGIC_SYSRQ` in production profile

### 4.4 — AppArmor / Landlock
- AppArmor profiles for `sshd`, `httpd`, `crond`, `bpm`
- Landlock (built into 6.6.15) as simpler sandboxing for bpm package installs

### 4.5 — Secure Boot
- Sign kernel + GRUB with MOK key
- `shim` for UEFI Secure Boot compatibility

**Milestone: v3.0** — PAM + sudo + hardened kernel + AppArmor

---

## Phase 5 — Desktop Track `v3.x` *(6–12 months, optional)*

> Only if targeting workstation / desktop use cases.

### 5.1 — Wayland (primary)
- `Sway` (Wayland compositor, i3-compatible) + `foot` terminal
- Smaller footprint than full X11 stack

### 5.2 — X11 Fallback
- `xorg-server` + `xinit`, VESA framebuffer driver
- `dwm` or `openbox` as WM (~5MB)

### 5.3 — Display Manager
- `greetd` (~100KB, Rust) + `tuigreet` for minimal TUI login screen

**Milestone: v3.5** — Wayland desktop + display manager (optional track)

---

## Phase 6 — Distribution Infrastructure `v4.0` *(ongoing)*

> What turns a project into a real distro.

### 6.1 — Build System
- Replace hand-written `build_*.sh` scripts with a proper per-package build framework
- Options: `Buildroot` (proven, generates complete root FS) or custom `make`-based with `PKGBUILD`-style recipes per package

### 6.2 — Package Repository Server
- GitHub Releases as package CDN (current approach, already working)
- `packages.list` → proper repo metadata: categories, arch, installed size, deps
- Automatic checksum + sig regeneration on push via GitHub Actions CI

### 6.3 — CI/CD Pipeline (GitHub Actions)

```yaml
on: push to main
  jobs:
    build:   build kernel + busybox + initramfs → produce bitos.iso
    test:    boot ISO in QEMU headless → verify SSH on :22, HTTP on :80
    release: on tag push → attach ISO to GitHub Release
```

### 6.4 — Release Cadence
- Track LTS kernels: 6.6.x (supported until Dec 2026), then 6.12.x
- BitOS feature release every 3 months
- LTS release every 6 months with 1-year support window
- `CHANGELOG.md` maintained per release, ISO attached to every GitHub Release tag

**Milestone: v4.0** — CI/CD pipeline + automated ISO releases + wiki/docs site

---

## Milestone Summary

| Version | Goal | Status |
|---------|------|--------|
| **v1.2** | Persistent root FS + netconf boot hook + GRUB EFI | ✅ Done |
| **v1.5** | Dep-aware bpm + RSA-signed repo + boot splash + `bpm info` | ✅ Done |
| **v2.0** | musl libc + 100 packages + gcc toolchain | 3 months |
| **v2.5** | s6 init + eudev + structured logging | 5 months |
| **v3.0** | PAM + sudo + hardened kernel + AppArmor | 8 months |
| **v3.5** | Wayland desktop + display manager *(optional)* | 12 months |
| **v4.0** | CI/CD + automated releases + docs site | 15 months |

---

## Comparison with Established Distros

| Feature | BitOS v1.5 | Alpine Linux | Debian/Ubuntu |
|---|---|---|---|
| ISO size | 21MB | 50MB | 500MB+ |
| Packages | 20 | 10,000+ | 59,000+ |
| libc | uClibc-ng (BusyBox) | musl | glibc |
| Init | BusyBox init | OpenRC | systemd |
| Root FS | RAM only | overlayfs / disk | disk |
| SSH | ✅ OpenSSH 9.9p2 | ✅ | ✅ |
| HTTPS at boot | ✅ unique | ❌ | ❌ |
| Web dashboard | ✅ unique | ❌ | ❌ |
| Signed pkg repo | ✅ RSA-SHA256 | ✅ | ✅ |
| Dep-aware bpm | ✅ auto-install | ✅ | ✅ |
| PAM | ❌ | ✅ | ✅ |
| sudo | ❌ | ✅ | ✅ |
| AppArmor | ❌ | ❌ | ✅ |
| EFI boot | ✅ GRUB hybrid | ✅ | ✅ |
| Desktop | ❌ *(v3.5 target)* | optional | ✅ |

---

*Phase 1 is complete. The highest-leverage next move is **v2.0 — musl libc**. Everything else (native package installs, a real compiler, 100+ packages) becomes possible once the system has a proper libc.*
