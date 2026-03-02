# BitOS Professional Edition

> A minimal, bootable Linux OS built from scratch — Linux 6.6.15 kernel + BusyBox 1.36.1 + OpenSSH 9.9p2 — with a web dashboard, package manager, firewall, HTTPS, containers, and 19 downloadable packages.

[![GitHub](https://img.shields.io/badge/Source-GitHub-green)](https://github.com/IceBerg-coder/Bit_OS)

---

## Features

| Category | Details |
|---|---|
| **Kernel** | Linux 6.6.15, x86_64, with Netfilter (conntrack, rate-limiting, REJECT, LOG, recent, limit) |
| **Userspace** | BusyBox 1.36.1 statically linked — full POSIX shell, coreutils, networking |
| **Shell** | bash-static 5.2.37 + ash (BusyBox fallback) |
| **SSH** | OpenSSH 9.9p2, key gen on first boot, MaxAuthTries 3, rate-limited (4 conn/60s) |
| **HTTPS** | socat 1.8.0.3 + openssl, auto self-signed cert, port 443 → httpd:80 |
| **Web Dashboard** | GitHub-style dark CGI dashboard, auto-refresh 10s, shows system/memory/disk/services |
| **Firewall** | iptables-legacy, SSH rate-limit, ICMP limit, SYN flood protect, input policy DROP |
| **Package Manager** | `bpm` — 19 packages on GitHub, install/remove/upgrade with SHA256 verification |
| **Service Manager** | `svc start|stop|restart|status sshd httpd crond telnetd syslogd` |
| **User Manager** | `adduser / deluser / lsusers / chpasswd_user` + `bit-users` TUI |
| **Init System** | BusyBox init (PID 1), graceful SIGTERM/SIGINT shutdown, S* startup scripts |
| **Containers** | `bit-containers` — chroot jail manager (create/exec/start/stop/destroy) |
| **Disk** | Optional 128MB ext4 virtio image mounted as `/home` |
| **First-boot wizard** | `bit_setup` — hostname, root password, services, timezone |

---

## Repository Layout

```
BitOS/
├── scripts/
│   ├── build_kernel.sh      # Build Linux 6.6.15
│   ├── build_busybox.sh     # Build BusyBox 1.36.1
│   ├── create_image.sh      # Build initramfs + ISO  ← main file
│   ├── create_storage.sh    # Create 128MB ext4 storage image
│   ├── run.sh               # QEMU launcher
│   └── common.sh            # Shared variables
├── pkgs/
│   ├── packages.list        # Package registry (name version sha256 description)
│   └── bit-*                # 19 installable packages
├── src/
│   ├── busybox-1.36.1/      # BusyBox source
│   └── linux-6.6.15/        # Linux kernel source
└── output/
    ├── bitos.iso            # Bootable ISO (built artifact)
    └── vmlinuz              # Kernel binary
```

---

## Requirements

- **Host OS:** Linux (Debian/Ubuntu recommended)
- **Packages:** `build-essential`, `libncurses-dev`, `bison`, `flex`, `libssl-dev`, `bc`, `grub-pc-bin`, `grub-efi-amd64-bin`, `xorriso`, `qemu-system-x86`, `socat`, `openssl`, `openssh-server`
- **RAM:** 4 GB+ (for kernel build)
- **Disk:** 10 GB+ free

---

## Build

```bash
# 1. Build BusyBox (first time only)
bash scripts/build_busybox.sh

# 2. Build Linux kernel (first time only — takes ~10 min)
bash scripts/build_kernel.sh

# 3. Build ISO
bash scripts/create_image.sh

# 4. Create persistent storage (first time only)
bash scripts/create_storage.sh

# 5. Boot in QEMU
bash scripts/run.sh
```

---

## Port Map (QEMU)

| Host Port | Guest Port | Protocol | Service |
|-----------|------------|----------|---------|
| 2222 | 22 | TCP | OpenSSH |
| 2323 | 23 | TCP | Telnet |
| 8180 | 80 | TCP | HTTP Dashboard |
| 8443 | 443 | TCP | HTTPS Dashboard |

---

## Quick Access

```bash
# SSH into BitOS
ssh root@localhost -p 2222

# Web dashboard (HTTP)
open http://localhost:8180/dashboard.cgi

# HTTPS dashboard (accept self-signed cert)
open https://localhost:8443/dashboard.cgi
```

---

## Package Manager (bpm)

```bash
bpm available               # list all 19 packages
bpm install bit-sysinfo     # install a package (SHA256 verified)
bpm list                    # show installed packages and versions
bpm upgrade                 # upgrade all installed packages
bpm remove bit-sysinfo      # remove a package
```

### Package Registry (19 packages)

| Package | Version | Description |
|---------|---------|-------------|
| `bit-hello` | 1.1 | SDK example / hello world |
| `bit-sysinfo` | 1.1 | CPU, memory, disk, network info |
| `bit-netinfo` | 1.1 | Network diagnostics |
| `bit-monitor` | 1.2 | Live TUI system monitor (CPU/mem/disk/net/procs) |
| `bit-diskinfo` | 1.1 | Disk and filesystem usage with bars |
| `bit-update` | 1.1 | Update all installed packages at once |
| `bit-ps` | 1.1 | Process manager with kill support |
| `bit-log` | 1.1 | Log viewer/manager |
| `bit-bench` | 1.1 | CPU and memory benchmark |
| `bit-files` | 1.1 | File browser |
| `bit-editor` | 1.1 | Text editor with vi backend |
| `bit-net` | 1.1 | Network toolkit (get/dns/ping/scan/speed/trace) |
| `bit-backup` | 1.1 | Backup and restore /etc and /home |
| `bit-cron` | 1.1 | Cron job manager |
| `bit-firewall` | 1.0 | Firewall manager TUI |
| `bit-ssl` | 1.0 | TLS certificate generator |
| `bit-users` | 1.0 | User management TUI |
| `bit-containers` | 1.0 | Chroot container manager |
| `bit-netconf` | 1.0 | Static IP / gateway / DNS configurator |

---

## Service Manager (svc)

```bash
svc status                  # show all services
svc start sshd              # start a service
svc stop httpd              # stop a service
svc restart crond           # restart a service
```

Services: `sshd`, `httpd`, `crond`, `telnetd`, `syslogd`

---

## Network Configuration (bit-netconf)

```bash
bit-netconf status                          # show current config
bit-netconf dhcp eth0                       # use DHCP (default)
bit-netconf set-ip eth0 192.168.1.100/24    # set static IP
bit-netconf set-gw 192.168.1.1             # set gateway
bit-netconf set-dns 8.8.8.8 1.1.1.1       # set DNS servers
bit-netconf apply                           # apply all settings now
```

---

## Firewall (bit-firewall)

```bash
bit-firewall status     # show active rules
bit-firewall allow 8080 # open a port
bit-firewall block 8080 # close a port
bit-firewall reset      # reset to defaults
bit-firewall menu       # interactive TUI
```

---

## Init System

BitOS uses BusyBox `init` as PID 1 with `/etc/inittab`. Services start via ordered `S*` scripts in `/etc/rcS.d/`:

| Script | Service |
|--------|---------|
| `S20-logging` | syslogd + klogd |
| `S30-crond` | cron daemon |
| `S40-firewall` | iptables rules |
| `S50-sshd` | OpenSSH server |
| `S50-httpd` | BusyBox httpd + CGI |
| `S55-https` | socat HTTPS (443 → 80) |

Shutdown/reboot via `init 0` / `init 6` or `poweroff` / `reboot`. SIGTERM is caught and triggers a graceful shutdown sequence.

---

## Credentials

| User | Password | Notes |
|------|----------|-------|
| `root` | *(empty)* | Set on first boot via `bit_setup` |

---

## Security

- SSH: `MaxAuthTries 3`, `LoginGraceTime 30`, login banner
- Firewall: SSH rate-limit 4 conn/60s (xt_recent), ICMP limit 10/s, INPUT chain default DROP
- HTTPS: self-signed RSA-2048 cert, rotated on first boot
- Packages: SHA256 verified on install

---

## License

MIT — see [LICENSE](LICENSE) for details.
