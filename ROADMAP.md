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

## Phase 2 — Real Userspace `v2.0` ✅ *COMPLETE*

> Move from BusyBox-only to real statically-linked software built against musl libc.

### 2.1 — musl-cross-make Toolchain ✅
- `scripts/build_musl_toolchain.sh` — builds `musl-cross-make` → `x86_64-linux-musl-gcc` in `~/musl-cross/`
- GCC 13.3.0 + musl 1.2.5 + binutils 2.44
- Sysroot: static `zlib 1.3.1`, `openssl 3.3.2`, `ncurses 6.4`, `readline 8.2` built in `build/musl-sysroot/`

### 2.2 — Static Package Builder ✅
- `scripts/build_musl_packages.sh` — per-package build functions, strips + packages + updates `packages.list`
- Run: `bash scripts/build_musl_packages.sh [all|curl|nano|rsync|htop|jq]`
- Commit: `9f66e87e8` — v2.0a tag

### 2.3 — First Wave Packages (musl static)

| Package | Version | Sysroot deps | Linking | Status |
|---------|---------|-------------|---------|--------|
| `curl` | 8.9.1 | zlib + openssl | musl-dynamic | ✅ shipped |
| `nano` | 7.2 | ncurses | fully-static | ✅ shipped |
| `rsync` | 3.4.1 | — | fully-static | ✅ shipped |
| `htop` | 3.3.0 | ncurses | fully-static | ✅ shipped |
| `jq` | 1.7.1 | oniguruma (builtin) | musl-dynamic | ✅ shipped |
| `musl-libc` | 1.2.5 | — | n/a | ✅ shipped — pre-bundled in initramfs at `/lib/ld-musl-x86_64.so.1` |
| `nmap` | 7.95 | openssl + pcre | — | ⏳ planned |
| `Python 3` | 3.12 | openssl + zlib + readline | — | ⏳ planned |
| `git` | 2.44 | openssl + zlib + pcre | — | ⏳ planned |
| `vim` | 9.1 | ncurses | — | ⏳ planned |
| `strace` | 6.7 | — | — | ⏳ planned |

> **Note:** "musl-dynamic" means the binary links against musl's `libc.so` (the musl dynamic linker `/lib/ld-musl-x86_64.so.1`).
> `ld-musl-x86_64.so.1` is pre-bundled in the initramfs by `create_image.sh` — curl and jq work out-of-the-box after bpm install.
> `TERMINFO=/usr/share/terminfo` + `/etc/terminfo` symlink in initramfs — overrides hardcoded sysroot path compiled into ncurses static builds.

**QEMU validation (Mar 3 2026):** curl 8.9.1 ✅  jq 1.7.1 ✅  nano 7.2 ✅  htop 3.3.0 TUI ✅  rsync 3.4.1 ✅

**Milestone: v2.0** ✅ — musl toolchain + 6 real packages + QEMU validated *(shipped)*

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
| **v2.0** | musl toolchain + static pkgs (curl, nano, rsync, htop, jq) + 50+ packages | 🔄 In Progress |
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
| Static real pkgs | 🔄 curl/nano/rsync/htop/jq | ✅ | ✅ |
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
