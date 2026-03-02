#!/bin/bash
source scripts/common.sh

log_info "Creating initramfs..."
mkdir -p "$BUILD_DIR/initramfs"
cd "$BUILD_DIR/initramfs"
log_info "Cleaning old initramfs..."
rm -rf -v *

log_info "Copying Busybox files..."
cp -rv "$SRC_DIR/busybox-$BUSYBOX_VERSION/_install/"* .

log_info "Creating standard Linux directory structure..."
mkdir -pv dev proc sys tmp etc home bin sbin usr/bin usr/sbin etc/init.d lib/modules/6.6.15
mkdir -pv var/log var/run var/spool/cron/crontabs etc/rcS.d var/www etc/ssh lib/x86_64-linux-gnu lib64 var/empty run usr/lib/openssh usr/lib/x86_64-linux-gnu/xtables etc/ssl/bitos var/containers

log_info "Pre-bundling musl dynamic linker..."
MUSL_LIBC_SRC="${MUSL_TOOLCHAIN_DIR:-$HOME/musl-cross}/x86_64-linux-musl/lib/libc.so"
if [ -f "$MUSL_LIBC_SRC" ]; then
    cp "$MUSL_LIBC_SRC" lib/ld-musl-x86_64.so.1
    chmod 755 lib/ld-musl-x86_64.so.1
    log_info "  + lib/ld-musl-x86_64.so.1 ($(du -sh lib/ld-musl-x86_64.so.1 | awk '{print $1}')) — musl runtime for bpm packages"
else
    log_info "  (musl toolchain not found — skipping; curl/jq will fail until bpm install musl-libc)"
fi

log_info "Bundling terminfo entries (xterm, xterm-256color, linux)..."
mkdir -p usr/share/terminfo/x usr/share/terminfo/l
for _ti in /usr/share/terminfo/x/xterm /usr/share/terminfo/x/xterm-256color; do
    [ -f "$_ti" ] && cp "$_ti" usr/share/terminfo/x/ && log_info "  + $(basename $_ti)"
done
for _ti in /usr/share/terminfo/l/linux; do
    [ -f "$_ti" ] && cp "$_ti" usr/share/terminfo/l/ && log_info "  + $(basename $_ti)"
done

log_info "Copying OpenSSH server..."
if [ -f "$BUILD_DIR/openssh/sbin/sshd" ]; then
    cp "$BUILD_DIR/openssh/sbin/sshd"        usr/sbin/sshd
    cp "$BUILD_DIR/openssh/bin/ssh-keygen"   usr/bin/ssh-keygen
    cp "$BUILD_DIR/openssh/libexec/sshd-session" usr/lib/openssh/sshd-session
    chmod +x usr/sbin/sshd usr/bin/ssh-keygen usr/lib/openssh/sshd-session
    log_info "Copying bundled shared libs..."
    cp -v "$BUILD_DIR/openssh/libs/"*.so*    lib/x86_64-linux-gnu/ 2>/dev/null || true
    # Copy dynamic linker to lib64
    if [ -f "$BUILD_DIR/openssh/libs/ld-linux-x86-64.so.2" ]; then
        cp "$BUILD_DIR/openssh/libs/ld-linux-x86-64.so.2" lib64/
    fi
    log_info "OpenSSH sshd installed: $(ls -lh usr/sbin/sshd)"
else
    log_err "OpenSSH not found! Run: bash scripts/build_openssh.sh first"
fi

log_info "Copying bash-static..."
if [ -f "/bin/bash-static" ]; then
    cp /bin/bash-static bin/bash
    chmod +x bin/bash
    log_info "bash-static installed: $(ls -lh bin/bash)"
else
    log_info "bash-static not found, skipping (ash remains default)"
fi

log_info "Copying socat + openssl for HTTPS..."
if [ -f "/usr/bin/socat1" ]; then
    cp /usr/bin/socat1 usr/bin/socat
    ln -sf /usr/bin/socat usr/bin/socat1
    chmod +x usr/bin/socat
    # Copy socat's shared lib dependencies
    for lib in libssl.so.3 libcrypto.so.3 libwrap.so.0 libz.so.1 libzstd.so.1; do
        src="/lib/x86_64-linux-gnu/$lib"
        [ ! -f "$src" ] && src="/usr/lib/x86_64-linux-gnu/$lib"
        [ -f "$src" ] && cp "$src" lib/x86_64-linux-gnu/ && echo "  + $lib"
    done
    log_info "socat installed: $(ls -lh usr/bin/socat)"
else
    log_info "socat not found — HTTPS will be skipped (run: sudo apt-get install socat)"
fi

log_info "Copying socat + openssl for HTTPS..."
if [ -f "/usr/bin/socat1" ]; then
    cp /usr/bin/socat1 usr/bin/socat
    ln -sf /usr/bin/socat usr/bin/socat1
    chmod +x usr/bin/socat
    # Copy socat's shared lib dependencies
    for lib in libssl.so.3 libcrypto.so.3 libwrap.so.0 libz.so.1 libzstd.so.1; do
        src="/lib/x86_64-linux-gnu/$lib"
        [ ! -f "$src" ] && src="/usr/lib/x86_64-linux-gnu/$lib"
        [ -f "$src" ] && cp "$src" lib/x86_64-linux-gnu/ && echo "  + $lib"
    done
    log_info "socat installed: $(ls -lh usr/bin/socat)"
else
    log_info "socat not found — HTTPS will be skipped (run: sudo apt-get install socat)"
fi

if [ -f "/usr/bin/openssl" ]; then
    cp /usr/bin/openssl usr/bin/openssl
    chmod +x usr/bin/openssl
    # openssl requires its config file to generate certs
    mkdir -p etc/ssl
    cp /etc/ssl/openssl.cnf etc/ssl/openssl.cnf 2>/dev/null || true
    # Also copy CA certs directory for SSL verification
    if [ -d /etc/ssl/certs ]; then
        mkdir -p etc/ssl/certs
        cp /etc/ssl/certs/ca-certificates.crt etc/ssl/certs/ 2>/dev/null || true
    fi
    log_info "openssl installed: $(ls -lh usr/bin/openssl)"
fi

log_info "Copying iptables (legacy)..."
IPTABLES_BIN="/usr/sbin/xtables-legacy-multi"
if [ -f "$IPTABLES_BIN" ]; then
    cp "$IPTABLES_BIN" usr/sbin/iptables
    chmod +x usr/sbin/iptables
    # Core iptables libs
    for lib in libxtables.so.12 libip4tc.so.2 libip6tc.so.2; do
        src="/usr/lib/x86_64-linux-gnu/$lib"
        [ -f "$src" ] && cp "$src" lib/x86_64-linux-gnu/ && echo "  + $lib"
    done
    # xtables match/target extensions (needed by the firewall rules)
    XTDIR="/usr/lib/x86_64-linux-gnu/xtables"
    for ext in libxt_standard.so libxt_conntrack.so libxt_tcp.so libipt_icmp.so libxt_REJECT.so libxt_LOG.so libxt_recent.so libxt_limit.so; do
        [ -f "$XTDIR/$ext" ] && cp "$XTDIR/$ext" usr/lib/x86_64-linux-gnu/xtables/ && echo "  + $ext"
    done
    # libxt_state.so is just a symlink to libxt_conntrack.so
    ln -sf libxt_conntrack.so usr/lib/x86_64-linux-gnu/xtables/libxt_state.so
    log_info "iptables installed: $(ls -lh usr/sbin/iptables)"
else
    log_err "xtables-legacy-multi not found! Run: sudo apt-get install iptables"
fi

log_info "Creating sshd_config..."
cat << 'SSHEOF' > etc/ssh/sshd_config
Port 22
PermitRootLogin yes
PermitEmptyPasswords yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
PrintMotd no
StrictModes no
PidFile /var/run/sshd.pid
MaxAuthTries 3
LoginGraceTime 30
Banner /etc/issue.net
SSHEOF

cat << 'EOF' > etc/issue.net
*******************************************
*   BitOS Professional Edition            *
*   Authorised access only.               *
*   All sessions are logged.              *
*******************************************
EOF

log_info "Creating etc/inittab..."
cat << 'EOF' > etc/inittab
::sysinit:/etc/init.d/rcS
::askfirst:-/bin/sh
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::restart:/sbin/init
EOF

log_info "Creating etc/fstab..."
cat << 'EOF' > etc/fstab
# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults        0       0
sysfs           /sys            sysfs   defaults        0       0
devtmpfs        /dev            devtmpfs defaults       0       0
tmpfs           /tmp            tmpfs   defaults,size=64M 0       0
# /dev/vda /home ext4 defaults 0 0  (mounted conditionally in rcS)
EOF

log_info "Creating DNS configuration..."
echo "BitOS" > etc/hostname

log_info "Creating DNS configuration..."
cat << 'EOF' > etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

log_info "Creating user accounts..."
# Passwords in /etc/shadow (x in passwd = shadow auth)
# Use /bin/bash as default login shell (bash-static is bundled)
echo "root:x:0:0:root:/home/root:/bin/bash" > etc/passwd
echo "kaung:x:1000:1000:kaung:/home/kaung:/bin/bash" >> etc/passwd
echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/sbin/nologin" >> etc/passwd
echo "root:x:0:" > etc/group
echo "kaung:x:1000:" >> etc/group
echo "sshd:x:74:" >> etc/group

# Shadow file: root has no password, kaung has no password
# Format: user:hash:lastchange:min:max:warn:inactive:expire
# Empty hash = no password required
cat << 'EOF' > etc/shadow
root::19787:0:99999:7:::
kaung::19787:0:99999:7:::
sshd:!:19787::::::
EOF
chmod 640 etc/shadow

# Create base home structure
mkdir -p home/root home/kaung

log_info "Updating etc/inittab for login..."
cat << 'EOF' > etc/inittab
::sysinit:/etc/init.d/rcS
::respawn:/sbin/getty -L ttyS0 115200 vt100
::respawn:/sbin/getty -L tty1 115200 linux
::ctrlaltdel:/sbin/reboot
::shutdown:/etc/init.d/shutdown.sh
::restart:/sbin/init
EOF

log_info "Creating etc/init.d/rcS..."
cat << 'RCSEOF' > etc/init.d/rcS
#!/bin/sh
log_msg() { echo -e "\e[1;32m[BitOS]\e[0m $1"; }

log_msg "Starting System V Initializer..."

# Mount critical filesystems
mount -a
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts -o gid=5,mode=620
mount -t tmpfs tmpfs /dev/shm

# Start hotplug event handler (mdev)
log_msg "Starting mdev (Device Hotplug Handler)..."
mdev -s
# Register mdev only if the kernel supports UEVENT_HELPER
[ -f /proc/sys/kernel/hotplug ] && echo /sbin/mdev > /proc/sys/kernel/hotplug
# Ensure ptmx exists for SSH PTY allocation
[ ! -e /dev/ptmx ] && mknod /dev/ptmx c 5 2 && chmod 666 /dev/ptmx

# Set networking (loopback)
ifconfig lo 127.0.0.1 up

    # Mount persistent storage EARLY — before rcS.d scripts so S00-restore can use it
    if [ -b /dev/vda ]; then
        log_msg "Mounting persistent storage /dev/vda -> /home..."
        mount -t ext4 /dev/vda /home 2>/dev/null \
            && log_msg "Persistent storage online" \
            || log_msg "Warning: /dev/vda mount failed, /home is tmpfs"
    else
        log_msg "No persistent disk (/dev/vda) found — /home is tmpfs"
    fi

    # Prepare /home directory structure
    mkdir -p /home/bin /home/root /home/kaung /home/.config/network
    chown -R 1000:1000 /home/kaung 2>/dev/null

    # Sentinel file: presence of /home/.persistent tells bpm and tools to use /home for storage
    if mountpoint -q /home 2>/dev/null; then
        touch /home/.persistent
        log_msg "Persistent mode: packages + config will survive reboots"
    fi

    # Run rcS.d startup scripts with coloured boot splash
    log_msg "Starting services..."
    for script in /etc/rcS.d/S*; do
        [ -f "$script" ] && [ -x "$script" ] || continue
        NAME=$(basename "$script")
        printf "  \e[1;34m[ .... ]\e[0m %s\r" "$NAME"
        if "$script" > /tmp/boot-${NAME}.log 2>&1; then
            printf "  \e[1;32m[  OK  ]\e[0m %s\n" "$NAME"
        else
            RC=$?
            printf "  \e[1;31m[ FAIL ]\e[0m %s  (exit $RC)\n" "$NAME"
            tail -1 /tmp/boot-${NAME}.log 2>/dev/null | sed 's/^/             /'
        fi
    done

    # Set hostname after S00-restore may have restored /etc/hostname
    hostname -F /etc/hostname 2>/dev/null || hostname bitos
RCSEOF
chmod +x etc/init.d/rcS

# Graceful shutdown script — called by inittab on halt/shutdown/SIGTERM to PID 1
log_info "Creating etc/init.d/shutdown.sh..."
cat << 'SHUTEOF' > etc/init.d/shutdown.sh
#!/bin/sh
# BitOS graceful shutdown — stops services in reverse order, syncs, unmounts
log_sh() { echo -e "\e[1;33m[shutdown]\e[0m $1"; }
log_sh "Graceful shutdown initiated..."

# Stop services in reverse order
for SVC in socat httpd sshd crond syslogd klogd telnetd; do
    if pidof "$SVC" >/dev/null 2>&1; then
        log_sh "Stopping $SVC..."
        killall -TERM "$SVC" 2>/dev/null
        sleep 1
        killall -KILL "$SVC" 2>/dev/null
    fi
done

# Flush filesystem write cache
log_sh "Syncing filesystems..."
sync; sync

# Unmount non-root filesystems
log_sh "Unmounting filesystems..."
umount -a -r 2>/dev/null

log_sh "Shutdown complete."
SHUTEOF
chmod +x etc/init.d/shutdown.sh

# Create initial startup scripts for rcS.d
log_info "Creating udhcpc default script (for DNS)..."
mkdir -p usr/share/udhcpc
cat << 'EOF' > usr/share/udhcpc/default.script
#!/bin/sh
# udhcpc script - configure IP, default route, and DNS
case "$1" in
  bound|renew)
    ifconfig "$interface" "$ip" ${subnet:+netmask "$subnet"}
    [ -n "$router" ] && route add default gw "$router" dev "$interface"
    : > /etc/resolv.conf
    if [ -n "$dns" ]; then
      for ns in $dns; do
        echo "nameserver $ns" >> /etc/resolv.conf
      done
    else
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    fi
    ;;
  deconfig)
    ifconfig "$interface" 0.0.0.0
    ;;
esac
exit 0
EOF
chmod +x usr/share/udhcpc/default.script

log_info "Creating rcS.d startup scripts..."
mkdir -p etc/rcS.d

# S00-restore: must run first — restores persisted /etc files from /home/.config/
cat << 'EOF' > etc/rcS.d/S00-restore
#!/bin/sh
PERSIST="/home/.config"
[ -d "$PERSIST" ] || exit 0
[ -f /home/.persistent ] || exit 0
echo "Restoring persistent config from $PERSIST ..."
for f in hostname passwd group resolv.conf bitos.configured; do
    [ -f "$PERSIST/$f" ] && cp "$PERSIST/$f" "/etc/$f" && echo "  + $f"
done
[ -f "$PERSIST/shadow" ] && cp "$PERSIST/shadow" /etc/shadow && chmod 640 /etc/shadow && echo "  + shadow"
[ -d "$PERSIST/network" ] && cp -r "$PERSIST/network/." /etc/network/ 2>/dev/null && echo "  + network/*.conf"
echo "Restore complete."
EOF
chmod +x etc/rcS.d/S00-restore

# S01-network: bring up eth0 — skips DHCP if static IP is configured (S02-netconf handles it)
cat << 'EOF' > etc/rcS.d/S01-network
#!/bin/sh
ifconfig eth0 up
# If a static IP config exists, skip DHCP — let S02-netconf apply it
if [ -f /etc/network/eth0.conf ]; then
    MODE=$(grep '^MODE=' /etc/network/eth0.conf 2>/dev/null | cut -d= -f2)
    if [ "$MODE" = "static" ]; then
        echo "Static IP configured for eth0 — skipping DHCP"
        exit 0
    fi
fi
echo "Requesting DHCP lease on eth0..."
udhcpc -i eth0 -p /var/run/udhcpc.eth0.pid -q -s /usr/share/udhcpc/default.script 2>/dev/null
[ -z "$(cat /etc/resolv.conf 2>/dev/null)" ] && echo "nameserver 8.8.8.8" > /etc/resolv.conf && echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "eth0: $(ifconfig eth0 2>/dev/null | awk '/inet /{print $2}')  DNS: $(head -1 /etc/resolv.conf 2>/dev/null)"
EOF
chmod +x etc/rcS.d/S01-network

# S02-netconf: apply static IP / gateway / DNS from /etc/network/*.conf
cat << 'EOF' > etc/rcS.d/S02-netconf
#!/bin/sh
APPLIED=0
for conf in /etc/network/*.conf; do
    [ -f "$conf" ] || continue
    IFACE=$(basename "$conf" .conf)
    MODE=$(grep '^MODE=' "$conf" 2>/dev/null | cut -d= -f2)
    [ "$MODE" != "static" ] && continue
    IP=$(grep '^IP=' "$conf" | cut -d= -f2)
    MASK=$(grep '^MASK=' "$conf" | cut -d= -f2)
    GW=$(grep '^GW=' "$conf" | cut -d= -f2)
    DNS=$(grep '^DNS=' "$conf" | cut -d= -f2-)
    [ -z "$IP" ] && continue
    ifconfig "$IFACE" "$IP" netmask "${MASK:-255.255.255.0}" up 2>/dev/null
    if [ -n "$GW" ]; then route del default 2>/dev/null; route add default gw "$GW" "$IFACE" 2>/dev/null; fi
    if [ -n "$DNS" ]; then
        printf "" > /etc/resolv.conf
        for ns in $DNS; do echo "nameserver $ns" >> /etc/resolv.conf; done
    fi
    echo "applied: $IFACE $IP gw=${GW:-none} dns=${DNS:-dhcp}"
    APPLIED=$((APPLIED+1))
done
[ "$APPLIED" -eq 0 ] && echo "No static IP configs — network via DHCP" && exit 0
EOF
chmod +x etc/rcS.d/S02-netconf

cat << 'EOF' > etc/rcS.d/S05-hostname
#!/bin/sh
# Set hostname early so services like httpd report the correct name
if [ -f /etc/hostname ]; then
    hostname -F /etc/hostname
    echo "Hostname set to: $(hostname)"
else
    hostname bitos
    echo "Hostname set to: bitos (default)"
fi
EOF
chmod +x etc/rcS.d/S05-hostname

cat << 'EOF' > etc/rcS.d/S10-depmod
#!/bin/sh
echo "Loading basic kernel modules..."
# virtio_net/blk/pci are built-in (=y) — modprobe returns 1 for built-ins, ignore it
modprobe -a virtio_net virtio_blk virtio_pci 2>/dev/null || true
EOF
chmod +x etc/rcS.d/S10-depmod

cat << 'EOF' > etc/rcS.d/S20-logging
#!/bin/sh
echo "Starting system and kernel loggers..."
mkdir -p /var/log
syslogd -S -b 7 -s 200 -O /var/log/messages
klogd
EOF
chmod +x etc/rcS.d/S20-logging

cat << 'EOF' > etc/rcS.d/S30-crond
#!/bin/sh
echo "Starting cron daemon..."
mkdir -p /var/spool/cron/crontabs
crond -b -l 8 -L /var/log/cron.log
EOF
chmod +x etc/rcS.d/S30-crond

# Create default root crontab
mkdir -p etc/crontabs
cat << 'EOF' > etc/crontabs/root
# BitOS root crontab
# min hour day month weekday command
*/5 * * * * sync
0 * * * * uptime >> /var/log/uptime.log
EOF
chmod 600 etc/crontabs/root

# Syslog config
cat << 'EOF' > etc/syslog.conf
kern.*      /var/log/kern.log
*.info      /var/log/messages
auth.*      /var/log/auth.log
EOF

# --- Networking Services ---

cat << 'EOF' > etc/rcS.d/S40-firewall
#!/bin/sh
echo "Applying firewall rules..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# SSH rate limiting: max 3 new connections per 60s, then DROP
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j LOG --log-prefix "SSH_BRUTE: " --log-level 6
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 23 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p icmp -m limit --limit 10/s -j ACCEPT
iptables -A INPUT -j DROP
echo "Firewall rules applied (SSH rate-limiting active)."
EOF
chmod +x etc/rcS.d/S40-firewall

cat << 'EOF' > etc/rcS.d/S50-sshd
#!/bin/sh
echo "Generating SSH host keys (if needed)..."
[ ! -d /etc/ssh ] && mkdir -p /etc/ssh
# Ensure /var/empty is owned by root with correct permissions (required by OpenSSH privsep)
mkdir -p /var/empty
chown root:root /var/empty
chmod 755 /var/empty
ssh-keygen -A -f / 2>&1
echo "Starting OpenSSH server on port 22..."
/usr/sbin/sshd
sleep 2
if [ -f /var/run/sshd.pid ]; then
    echo "SSH server started (PID $(cat /var/run/sshd.pid))"
else
    echo "WARNING: sshd may not have started - check console"
fi
EOF
chmod +x etc/rcS.d/S50-sshd

cat << 'EOF' > etc/rcS.d/S51-telnetd
#!/bin/sh
echo "Starting Telnet server on port 23..."
telnetd -b 0.0.0.0:23 -l /bin/login
echo "Telnet server started."
EOF
chmod +x etc/rcS.d/S51-telnetd

cat << 'EOF' > etc/rcS.d/S50-httpd
#!/bin/sh
mkdir -p /var/www
# Ensure CGI scripts are executable at runtime
chmod +x /var/www/*.cgi 2>/dev/null
# httpd.conf: map .cgi extension to /bin/sh interpreter
echo "*.cgi:/bin/sh" > /etc/httpd.conf
echo "Starting HTTP server on port 80..."
httpd -p 80 -h /var/www -c /etc/httpd.conf
echo "HTTP server started at http://$(hostname):80"
EOF
chmod +x etc/rcS.d/S50-httpd

cat << 'EOF' > etc/rcS.d/S55-https
#!/bin/sh
# Start HTTPS via socat if cert exists
CERT_DIR="/etc/ssl/bitos"
PEM="$CERT_DIR/bitos.pem"
LOG="/var/log/https-setup.log"

if ! command -v socat >/dev/null 2>&1; then
    echo "socat not found, skipping HTTPS"
    exit 0
fi
if [ ! -f "$PEM" ]; then
    echo "Generating self-signed TLS certificate..."
    mkdir -p "$CERT_DIR"
    CN=$(hostname)
    [ -z "$CN" ] && CN="bitos"
    # openssl.cnf must exist; fall back to /dev/null approach if missing
    if [ -f /etc/ssl/openssl.cnf ]; then
        OPENSSL_CONF=/etc/ssl/openssl.cnf \
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout "$CERT_DIR/bitos.key" \
            -out   "$CERT_DIR/bitos.crt" \
            -days 3650 \
            -subj "/CN=$CN/O=BitOS/C=US" > "$LOG" 2>&1
    else
        # Minimal config inline
        cat > /tmp/openssl-min.cnf << CNFEOF
[req]
distinguished_name=req
[san]
subjectAltName=DNS:$CN
CNFEOF
        OPENSSL_CONF=/tmp/openssl-min.cnf \
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout "$CERT_DIR/bitos.key" \
            -out   "$CERT_DIR/bitos.crt" \
            -days 3650 \
            -subj "/CN=$CN/O=BitOS/C=US" > "$LOG" 2>&1
    fi
    if [ $? -eq 0 ] && [ -s "$CERT_DIR/bitos.crt" ] && [ -s "$CERT_DIR/bitos.key" ]; then
        cat "$CERT_DIR/bitos.crt" "$CERT_DIR/bitos.key" > "$PEM"
        chmod 600 "$CERT_DIR/bitos.key" "$PEM"
        echo "Certificate generated: $PEM"
    else
        echo "[!] Certificate generation failed (see $LOG):"
        cat "$LOG" 2>/dev/null | head -5
        exit 1
    fi
fi
if [ -s "$PEM" ]; then
    socat OPENSSL-LISTEN:443,cert="$PEM",verify=0,reuseaddr,fork \
        TCP:127.0.0.1:80 >> "$LOG" 2>&1 &
    echo "HTTPS server started on port 443 (socat -> httpd:80)"
else
    echo "[!] PEM file missing or empty, HTTPS not started"
fi
EOF
chmod +x etc/rcS.d/S55-https

# Create default web root
mkdir -p var/www
cat << 'EOF' > var/www/index.html
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="refresh" content="0;url=/dashboard.cgi">
<title>BitOS Dashboard</title>
<style>
body{background:#111;color:#0f0;font-family:monospace;padding:40px;}
a{color:#0af;}
</style>
</head>
<body>
<p>Loading dashboard... <a href="/dashboard.cgi">Click here</a> if not redirected.</p>
</body>
</html>
EOF

cat << 'CGIEOF' > var/www/dashboard.cgi
#!/bin/sh
echo "Content-Type: text/html"
echo ""
UPTIME=$(uptime | sed 's/.*up //' | sed 's/,  .*//')
HOSTNAME=$(hostname 2>/dev/null || echo "bitos")
KERNEL=$(uname -r)
MEM_LINE=$(free -m | grep Mem)
MEM_TOTAL=$(echo $MEM_LINE | awk '{print $2}')
MEM_USED=$(echo $MEM_LINE  | awk '{print $3}')
MEM_FREE=$(echo $MEM_LINE  | awk '{print $4}')
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
PROC_COUNT=$(ps | wc -l)
DISK=$(df -h /home 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}')
[ -z "$DISK" ] && DISK=$(df -h /tmp 2>/dev/null | awk 'NR==2{print $3"/"$2" (tmpfs)"}')
[ -z "$DISK" ] && DISK="ramfs (no quota)"
ETH_IP=$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
[ -z "$ETH_IP" ] && ETH_IP="N/A"
PKG_COUNT=0
[ -s /etc/bpm.db ] && PKG_COUNT=$(wc -l < /etc/bpm.db)
SSH_STATUS="stopped"
[ -f /var/run/sshd.pid ] && kill -0 $(cat /var/run/sshd.pid) 2>/dev/null && SSH_STATUS="running"
HTTP_STATUS="running"
CRON_STATUS="stopped"
[ -f /var/run/crond.pid ] && kill -0 $(cat /var/run/crond.pid) 2>/dev/null && CRON_STATUS="running"

# Bar generator (filled/total -> ASCII bar)
bar() {
    USED=$1; TOTAL=$2; WIDTH=20
    [ "$TOTAL" -eq 0 ] && echo "[--------------------] N/A" && return
    FILLED=$(( USED * WIDTH / TOTAL ))
    EMPTY=$(( WIDTH - FILLED ))
    BAR="["
    i=0; while [ $i -lt $FILLED ]; do BAR="${BAR}#"; i=$((i+1)); done
    i=0; while [ $i -lt $EMPTY ];  do BAR="${BAR}-"; i=$((i+1)); done
    BAR="${BAR}] ${USED}/${TOTAL} MB"
    echo "$BAR"
}
MEM_BAR=$(bar $MEM_USED $MEM_TOTAL)

# Security / firewall card data
FW_RULES=$(iptables -L INPUT --line-numbers 2>/dev/null | grep -c '^[0-9]' || echo 0)
FW_POLICY=$(iptables -L INPUT 2>/dev/null | head -1 | awk '{print $4}' | tr -d ')')
[ -z "$FW_POLICY" ] && FW_POLICY="N/A"
HTTPS_STATUS="stopped"
pidof socat >/dev/null 2>&1 && HTTPS_STATUS="running"
CERT_EXPIRY="N/A"
[ -f /etc/ssl/bitos/bitos.crt ] && CERT_EXPIRY=$(openssl x509 -noout -enddate -in /etc/ssl/bitos/bitos.crt 2>/dev/null | cut -d= -f2 | awk '{print $1,$2,$4}')
FW_BLOCKED=$(awk 'NR>1{c++}END{print c+0}' /proc/net/xt_recent/SSH 2>/dev/null || echo 0)

cat << HTML
<!DOCTYPE html>
<html>
<head>
<title>BitOS Dashboard - $HOSTNAME</title>
<meta http-equiv="refresh" content="10">
<meta charset="utf-8">
<style>
  body { background: #0d1117; color: #c9d1d9; font-family: 'Courier New', monospace; margin: 0; padding: 0; }
  .header { background: #161b22; border-bottom: 1px solid #30363d; padding: 16px 32px; display: flex; align-items: center; gap: 16px; }
  .header h1 { color: #3fb950; margin: 0; font-size: 1.4em; }
  .header .sub { color: #8b949e; font-size: 0.85em; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; padding: 24px 32px; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; }
  .card h2 { color: #58a6ff; margin: 0 0 12px 0; font-size: 0.95em; text-transform: uppercase; letter-spacing: 1px; border-bottom: 1px solid #21262d; padding-bottom: 8px; }
  .row { display: flex; justify-content: space-between; padding: 4px 0; border-bottom: 1px solid #21262d; font-size: 0.9em; }
  .row:last-child { border-bottom: none; }
  .label { color: #8b949e; }
  .val { color: #c9d1d9; }
  .green { color: #3fb950; }
  .red { color: #f85149; }
  .bar { font-family: monospace; color: #3fb950; font-size: 0.85em; word-break: break-all; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
  .badge-green { background: #1a3a23; color: #3fb950; }
  .badge-red { background: #3a1a1a; color: #f85149; }
  .footer { text-align: center; color: #484f58; font-size: 0.8em; padding: 16px; }
  .logo { color: #3fb950; font-size: 1.2em; }
</style>
</head>
<body>
<div class="header">
  <span class="logo">&#9608;&#9608;</span>
  <h1>BitOS Professional Edition</h1>
  <span class="sub">Dashboard &mdash; auto-refresh every 10s</span>
  <a href="/boot-log.cgi" style="margin-left:auto;color:#58a6ff;text-decoration:none;font-size:0.85em;padding:6px 14px;border:1px solid #30363d;border-radius:4px;">Boot Log</a>
</div>
<div class="grid">

  <div class="card">
    <h2>System</h2>
    <div class="row"><span class="label">Hostname</span><span class="val green">$HOSTNAME</span></div>
    <div class="row"><span class="label">Kernel</span><span class="val">$KERNEL</span></div>
    <div class="row"><span class="label">Uptime</span><span class="val">$UPTIME</span></div>
    <div class="row"><span class="label">Load avg</span><span class="val">$LOAD</span></div>
    <div class="row"><span class="label">Processes</span><span class="val">$PROC_COUNT</span></div>
  </div>

  <div class="card">
    <h2>Memory</h2>
    <div class="row"><span class="label">Total</span><span class="val">${MEM_TOTAL} MB</span></div>
    <div class="row"><span class="label">Used</span><span class="val">${MEM_USED} MB</span></div>
    <div class="row"><span class="label">Free</span><span class="val green">${MEM_FREE} MB</span></div>
    <div class="row"><span class="label">Usage</span></div>
    <div class="bar">$MEM_BAR</div>
  </div>

  <div class="card">
    <h2>Storage &amp; Network</h2>
    <div class="row"><span class="label">Disk (/)</span><span class="val">$DISK</span></div>
    <div class="row"><span class="label">IP (eth0)</span><span class="val green">$ETH_IP</span></div>
    <div class="row"><span class="label">Packages</span><span class="val">$PKG_COUNT installed</span></div>
  </div>

  <div class="card">
    <h2>Services</h2>
    <div class="row">
      <span class="label">OpenSSH (sshd)</span>
      <span class="badge $([ "$SSH_STATUS" = "running" ] && echo badge-green || echo badge-red)">$SSH_STATUS</span>
    </div>
    <div class="row">
      <span class="label">Web (httpd)</span>
      <span class="badge badge-green">$HTTP_STATUS</span>
    </div>
    <div class="row">
      <span class="label">Cron (crond)</span>
      <span class="badge $([ "$CRON_STATUS" = "running" ] && echo badge-green || echo badge-red)">$CRON_STATUS</span>
    </div>
    <div class="row">
      <span class="label">HTTPS (socat)</span>
      <span class="badge $([ "$HTTPS_STATUS" = "running" ] && echo badge-green || echo badge-red)">$HTTPS_STATUS</span>
    </div>
  </div>

  <div class="card">
    <h2>Security</h2>
    <div class="row"><span class="label">Firewall</span><span class="badge badge-green">active</span></div>
    <div class="row"><span class="label">INPUT policy</span><span class="val red">$FW_POLICY</span></div>
    <div class="row"><span class="label">Rules loaded</span><span class="val">$FW_RULES</span></div>
    <div class="row"><span class="label">SSH tracked IPs</span><span class="val $([ "$FW_BLOCKED" -gt 0 ] 2>/dev/null && echo red || echo green)">$FW_BLOCKED</span></div>
    <div class="row"><span class="label">TLS cert expiry</span><span class="val">$CERT_EXPIRY</span></div>
  </div>

</div>
<div class="footer">BitOS &mdash; $(date '+%Y-%m-%d %H:%M:%S %Z')</div>
</body>
</html>
HTML
CGIEOF
chmod +x var/www/dashboard.cgi

# Boot log viewer — written via python to avoid heredoc nesting issues
python3 - << 'PYEOF'
content = r"""#!/bin/sh
echo "Content-Type: text/html"
echo ""
HOSTNAME=$(hostname 2>/dev/null || echo "bitos")
cat << BOOTHTML
<!DOCTYPE html>
<html>
<head>
<title>BitOS Boot Log - $HOSTNAME</title>
<meta charset="utf-8">
<style>
  body{background:#0d1117;color:#c9d1d9;font-family:'Courier New',monospace;margin:0;padding:0;}
  .header{background:#161b22;border-bottom:1px solid #30363d;padding:16px 32px;display:flex;align-items:center;gap:16px;}
  .header h1{color:#3fb950;margin:0;font-size:1.4em;}
  .nav{margin-left:auto;}
  .nav a{color:#58a6ff;text-decoration:none;font-size:.9em;padding:6px 14px;border:1px solid #30363d;border-radius:4px;}
  .toolbar{padding:12px 32px;display:flex;gap:12px;align-items:center;border-bottom:1px solid #21262d;}
  .btn{background:#238636;color:#fff;border:none;padding:7px 18px;border-radius:5px;cursor:pointer;font-family:monospace;font-size:.9em;}
  .btn:hover{background:#2ea043;}
  .btn-secondary{background:#21262d;border:1px solid #30363d;}
  .section{margin:0 32px 24px 32px;}
  .section-title{color:#58a6ff;font-size:.85em;text-transform:uppercase;letter-spacing:1px;border-bottom:1px solid #21262d;padding:16px 0 8px 0;}
  pre{background:#161b22;border:1px solid #30363d;border-radius:6px;padding:16px;margin:0;overflow-x:auto;font-size:.82em;line-height:1.5;white-space:pre-wrap;word-break:break-all;}
  .ok{color:#3fb950;} .fail{color:#f85149;}
  .footer{text-align:center;color:#484f58;font-size:.8em;padding:16px;}
  #copied{color:#3fb950;font-size:.85em;display:none;}
</style>
</head>
<body>
<div class="header">
  <span style="color:#3fb950;font-size:1.2em">&#9608;&#9608;</span>
  <h1>BitOS Boot Log</h1>
  <div class="nav"><a href="/dashboard.cgi">&larr; Dashboard</a></div>
</div>
<div class="toolbar">
  <button class="btn" onclick="copyLog()">&#128203; Copy All</button>
  <button class="btn btn-secondary" onclick="location.reload()">&#8635; Refresh</button>
  <span id="copied">&#10003; Copied!</span>
</div>
BOOTHTML
echo '<div class="section"><div class="section-title">Service Boot Logs</div><pre id="svc-log">'
for logfile in /tmp/boot-*.log; do
  [ -f "$logfile" ] || continue
  NAME=$(basename "$logfile" .log | sed 's/boot-//')
  printf '<span class="ok">### %s ###</span>\n' "$NAME"
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$logfile"
  echo
done
echo '</pre></div>'
echo '<div class="section"><div class="section-title">Kernel Ring Buffer (dmesg)</div><pre id="dmesg-log">'
dmesg 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
echo '</pre></div>'
TS=$(date '+%Y-%m-%d %H:%M:%S')
cat << BOOTHTML
<div class="footer">BitOS &mdash; $TS</div>
<script>
function copyLog(){
  var t='',s=document.getElementById('svc-log'),d=document.getElementById('dmesg-log');
  if(s) t+='=== SERVICE BOOT LOGS ===\n'+s.innerText+'\n';
  if(d) t+='=== KERNEL DMESG ===\n'+d.innerText;
  navigator.clipboard.writeText(t).then(function(){show()}).catch(function(){
    var a=document.createElement('textarea');a.value=t;document.body.appendChild(a);a.select();document.execCommand('copy');document.body.removeChild(a);show();
  });
}
function show(){var e=document.getElementById('copied');e.style.display='inline';setTimeout(function(){e.style.display='none'},2000);}
</script>
</body></html>
BOOTHTML
"""
with open("var/www/boot-log.cgi", "w") as f:
    f.write(content)
import os
os.chmod("var/www/boot-log.cgi", 0o755)
print("[INFO] boot-log.cgi written")
PYEOF

# Embed package repository signing public key
log_info "Embedding package signing public key..."
cat << 'EOF' > etc/bpm_pubkey.pem
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxcrK0K4KAC2OF6QQXJ5o
8mL2zlPlpO7I78dp2u7SVctvUg9SOx5ks+vRFVnF81lINWSJBMGH2Bzo1vse7ohb
6jpAbHPk8t+hMSxaaaPoJr5U5SbJQmG72vK0Kszudirgy1jsjz95gHJDWOreVtZM
KPo5EiaDSr85kvsKnGdEpKbZY/phlxkLod7qL4BLaux7diIBQHDuY5EWa0e5dE26
VwRXZtZgpt9ymaeIFqMLVgFCeHtBeWyUFNIuhIjFENgrdyPe3Jf21N9DKTxP0DhP
6uly8lh9cmAS3i3+xRujzLPFTAcOyI6M6otc5csaQ1pFC1FCYgs1RJ1V8jL4NtJI
cQIDAQAB
-----END PUBLIC KEY-----
EOF

log_info "Creating MOTD and profile..."
cat << 'EOF' > etc/motd
Welcome to BitOS Professional Edition
  bit_info             - system info
  bpm available        - browse 20 packages
  bpm install <pkg>    - install package (auto-resolves deps)
  bpm info <pkg>       - show package details and deps
  svc status           - service manager
  bit-firewall menu    - firewall TUI
  bit-users menu       - user manager TUI
  bit-netconf status   - network configurator
  bit-containers list  - container manager
  bit-watch -n2 cmd    - live terminal refresh (like watch)
Dashboard: http://localhost:80/dashboard.cgi
   HTTPS: https://localhost:443/dashboard.cgi
EOF

cat << 'EOF' > etc/profile
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/home/bin
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
export HISTFILE=$HOME/.sh_history
export HISTSIZE=1000
export TERM=xterm
alias ls='ls --color=auto'
alias ll='ls -al'
alias la='ls -A'
alias grep='grep --color=auto'
alias log='tail -f /var/log/messages'
alias klog='tail -f /var/log/kern.log'
alias crontab='crontab -u root'
alias netstat='netstat -tulpn'
alias myip='ip addr show eth0 | grep inet'
alias ports='netstat -tulpn'
alias weblog='tail -f /var/log/httpd.log'

# bit_info: Simple system info tool
bit_info() {
    echo -e "\e[1;32m   ____  _ _   ____   _____ \e[0m"
    echo -e "\e[1;32m  | __ )(_) |_/ __ \ / ___/ \e[0m"
    echo -e "\e[1;32m  |  _ \| | __/ / / / \__ \  \e[0m"
    echo -e "\e[1;32m  | |_) | | |_/ /_/ / ___/ / \e[0m"
    echo -e "\e[1;32m  |____/|_|\__\____/ /____/  \e[0m"
    echo ""
    echo -e "\e[1;34mOS:\e[0m BitOS (Professional Edition)"
    echo -e "\e[1;34mKernel:\e[0m $(uname -r)"
    echo -e "\e[1;34mUptime:\e[0m $(uptime | awk '{print $3,$4}' | sed 's/,//')"
    # Use shell evaluation to avoid awk escaping issues inside heredoc
    MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
    MEM_USED=$(free -h | grep Mem | awk '{print $3}')
    echo -e "\e[1;34mMemory:\e[0m ${MEM_USED}/${MEM_TOTAL}"
    echo -e "\e[1;34mHostname:\e[0m $(hostname)"
    echo ""
}

# _persist_etc: Copy /etc files to /home/.config/ for persistence across reboots
_persist_etc() {
    [ -f /home/.persistent ] || return 0
    mkdir -p /home/.config/network
    for f in "$@"; do
        [ -f "$f" ] || continue
        cp "$f" /home/.config/ && echo -e "\e[1;36m[~]\e[0m persisted $(basename $f)"
    done
    # Also persist network configs as a directory
    [ -d /etc/network ] && cp -r /etc/network/. /home/.config/network/ 2>/dev/null
}

# bpm internal helpers (called by bpm and each other)
_bpm_paths() {
    if [ -f /home/.persistent ]; then
        BPM_DB="/home/.config/bpm.db"; BPM_BIN="/home/bin"
    else
        BPM_DB="/etc/bpm.db"; BPM_BIN="/usr/bin"
    fi
}
_bpm_fetch_list() {
    local REPO="https://raw.githubusercontent.com/IceBerg-coder/Bit_OS/main/pkgs"
    wget -q --no-check-certificate "$REPO/packages.list" -O /tmp/bpm_pkglist 2>/dev/null || { echo "[!] Cannot reach repository" >&2; return 1; }
    wget -q --no-check-certificate "$REPO/packages.list.sig" -O /tmp/bpm_pkglist.sig 2>/dev/null
    if [ -f /etc/bpm_pubkey.pem ] && [ -f /tmp/bpm_pkglist.sig ]; then
        if openssl dgst -sha256 -verify /etc/bpm_pubkey.pem -signature /tmp/bpm_pkglist.sig /tmp/bpm_pkglist >/dev/null 2>&1; then
            echo -e "\e[1;32m[\u2713] packages.list signature verified\e[0m" >&2
        else
            echo -e "\e[1;31m[!] packages.list signature INVALID — aborting\e[0m" >&2; return 1
        fi
    fi
    cat /tmp/bpm_pkglist
}
_bpm_is_installed() { _bpm_paths; grep -q "^$1 " "$BPM_DB" 2>/dev/null; }
_bpm_install_one() {
    local PKG="$1" META="$2"
    _bpm_paths
    local VER SHA DEPS
    VER=$(echo  "$META" | awk -v p="$PKG" '$1==p{print $2}')
    SHA=$(echo  "$META" | awk -v p="$PKG" '$1==p{print $3}')
    DEPS=$(echo "$META" | awk -v p="$PKG" '$1==p{print $4}')
    [ -z "$VER" ] && echo -e "\e[1;31m[!] $PKG not found in repository\e[0m" && return 1
    [ -z "$DEPS" ] && DEPS="-"
    wget -q --no-check-certificate "https://raw.githubusercontent.com/IceBerg-coder/Bit_OS/main/pkgs/$PKG" -O "/tmp/bpm_dl_$PKG"
    if [ $? -ne 0 ] || [ ! -s "/tmp/bpm_dl_$PKG" ]; then rm -f "/tmp/bpm_dl_$PKG"; echo -e "\e[1;31m[!] Download failed: $PKG\e[0m"; return 1; fi
    if [ -n "$SHA" ]; then
        local ACTUAL; ACTUAL=$(sha256sum "/tmp/bpm_dl_$PKG" | awk '{print $1}')
        if [ "$ACTUAL" != "$SHA" ]; then rm -f "/tmp/bpm_dl_$PKG"; echo -e "\e[1;31m[!] SHA256 mismatch: $PKG\e[0m  expected: $SHA\n  got: $ACTUAL"; return 1; fi
        echo -e "\e[1;32m[\u2713] SHA256 verified: $PKG\e[0m"
    fi
    mv "/tmp/bpm_dl_$PKG" "$BPM_BIN/$PKG"; chmod +x "$BPM_BIN/$PKG"
    # musl-libc: also install the dynamic linker to /lib/ld-musl-x86_64.so.1
    if [ "$PKG" = "musl-libc" ]; then
        mkdir -p /lib
        cp "$BPM_BIN/musl-libc" /lib/ld-musl-x86_64.so.1
        chmod 755 /lib/ld-musl-x86_64.so.1
        echo -e "\e[1;32m[+] Dynamic linker installed: /lib/ld-musl-x86_64.so.1\e[0m"
    fi
    sed -i "/^$PKG /d" "$BPM_DB" 2>/dev/null
    echo "$PKG $VER (github) deps:$DEPS" >> "$BPM_DB"
    echo -e "\e[1;32m[+] Installed $PKG v$VER -> $BPM_BIN\e[0m"
}

# bpm: BitOS Package Manager (v1.5 - dep-aware, signed repo)
bpm() {
    _bpm_paths
    local PKG_DB="$BPM_DB" INSTALL_BIN="$BPM_BIN"
    local REPO_URL="https://raw.githubusercontent.com/IceBerg-coder/Bit_OS/main/pkgs"
    
    case "$1" in
        "install")
            [ -z "$2" ] && echo "Usage: bpm install <name>" && return 1
            echo -e "\e[1;34m[*] Fetching package repository...\e[0m"
            local META; META=$(_bpm_fetch_list) || return 1
            # Resolve dependencies first
            local DEPS; DEPS=$(echo "$META" | awk -v p="$2" '$1==p{print $4}')
            if [ -n "$DEPS" ] && [ "$DEPS" != "-" ]; then
                echo -e "\e[1;33m[~] $2 requires: $DEPS\e[0m"
                local DEP; for DEP in $(echo "$DEPS" | tr ',' ' '); do
                    if _bpm_is_installed "$DEP"; then
                        echo -e "  \e[1;32m[=]\e[0m $DEP already installed"
                    else
                        echo -e "  \e[1;34m[+]\e[0m Installing dependency: $DEP"
                        _bpm_install_one "$DEP" "$META" || { echo -e "\e[1;31m[!] Dep failed: $DEP\e[0m"; return 1; }
                    fi
                done
            fi
            echo -e "\e[1;34m[*] Installing $2...\e[0m"
            _bpm_install_one "$2" "$META"
            ;;
        "remove")
            [ -z "$2" ] && echo "Usage: bpm remove <name>" && return 1
            # Block removal if another installed package depends on $2
            local RDEPS; RDEPS=$(grep " deps:.*\b$2\b" "$PKG_DB" 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
            if [ -n "$RDEPS" ]; then
                echo -e "\e[1;31m[!] Cannot remove $2 — required by: ${RDEPS}\e[0m"
                echo "    Remove those packages first."
                return 1
            fi
            if [ -f "$INSTALL_BIN/$2" ] || [ -f "/usr/bin/$2" ]; then
                rm -f "$INSTALL_BIN/$2" "/usr/bin/$2" 2>/dev/null
                sed -i "/^$2 /d" "$PKG_DB" 2>/dev/null
                echo -e "\e[1;32m[-] Removed $2\e[0m"
            else
                echo -e "\e[1;31m[!] $2 is not installed\e[0m"
            fi
            ;;
        "list")
            echo -e "\e[1;34m--- Installed Packages ---\e[0m"
            if [ -s "$PKG_DB" ]; then
                printf "  \e[1;36m%-20s %-8s %-12s %s\e[0m\n" "NAME" "VERSION" "SOURCE" "DEPS"
                printf "  %-20s %-8s %-12s %s\n" "----" "-------" "------" "----"
                while IFS= read -r L; do
                    local N V S D
                    N=$(echo "$L" | awk '{print $1}')
                    V=$(echo "$L" | awk '{print $2}')
                    S=$(echo "$L" | awk '{print $3}')
                    D=$(echo "$L" | grep -o 'deps:[^ ]*' | sed 's/deps://')
                    [ -z "$D" ] && D="-"
                    printf "  \e[1;32m%-20s\e[0m \e[1;33m%-8s\e[0m %-12s \e[36m%s\e[0m\n" "$N" "$V" "$S" "$D"
                done < "$PKG_DB"
            else
                echo "(none)"
            fi
            ;;
        "available")
            echo -e "\e[1;34m--- Available Packages ---\e[0m"
            local RESULT; RESULT=$(_bpm_fetch_list) || return 1
            printf "  \e[1;36m%-20s %-8s %-16s %s\e[0m\n" "NAME" "VER" "DEPS" "DESCRIPTION"
            printf "  %-20s %-8s %-16s %s\n" "----" "---" "----" "-----------"
            echo "$RESULT" | grep '^bit-' | while IFS= read -r L; do
                local N V D DESC
                N=$(echo "$L"    | awk '{print $1}')
                V=$(echo "$L"    | awk '{print $2}')
                D=$(echo "$L"    | awk '{print $4}')
                DESC=$(echo "$L" | awk '{for(i=5;i<=NF;i++) printf "%s ",$i; print ""}')
                printf "  \e[1;32m%-20s\e[0m \e[1;33m%-8s\e[0m \e[36m%-16s\e[0m %s\n" "$N" "$V" "$D" "$DESC"
            done
            ;;
        "info")
            [ -z "$2" ] && echo "Usage: bpm info <name>" && return 1
            local META; META=$(_bpm_fetch_list) || return 1
            local LINE; LINE=$(echo "$META" | awk -v p="$2" '$1==p')
            [ -z "$LINE" ] && echo -e "\e[1;31m[!] $2 not found in repository\e[0m" && return 1
            local V D DESC INST
            V=$(echo "$LINE"    | awk '{print $2}')
            D=$(echo "$LINE"    | awk '{print $4}')
            DESC=$(echo "$LINE" | awk '{for(i=5;i<=NF;i++) printf "%s ",$i; print ""}')
            INST=$(grep -q "^$2 " "$PKG_DB" 2>/dev/null && echo "yes" || echo "no")
            echo -e "\e[1;34m┌─ $2 ─────────────────────\e[0m"
            echo -e "\e[1;34m│\e[0m Version:     \e[1;33m$V\e[0m"
            echo -e "\e[1;34m│\e[0m Depends:     \e[36m$D\e[0m"
            echo -e "\e[1;34m│\e[0m Installed:   $([ "$INST" = "yes" ] && echo '\e[1;32myes\e[0m' || echo '\e[1;31mno\e[0m')"
            echo -e "\e[1;34m│\e[0m Description: $DESC"
            echo -e "\e[1;34m└──────────────────────────────\e[0m"
            ;;
        "search")
            echo -e "\e[1;34m--- Matching Built-in Applets ---\e[0m"
            busybox --list | grep "${2:-.}"
            ;;
        "upgrade")
            echo -e "\e[1;34m[*] Checking for updates...\e[0m"
            if [ ! -s "$PKG_DB" ]; then echo "(no packages installed)"; return 0; fi
            local REMOTE_LIST; REMOTE_LIST=$(_bpm_fetch_list) || return 1
            local UPGRADED=0 SKIPPED=0 FAILED=0
            while IFS= read -r LINE; do
                local PKG INST_VER SRC REMOTE_VER PKG_DEPS EXP ACT
                PKG=$(echo "$LINE"      | awk '{print $1}')
                INST_VER=$(echo "$LINE" | awk '{print $2}')
                SRC=$(echo "$LINE"      | awk '{print $3}')
                [ "$SRC" != "(github)" ] && continue
                REMOTE_VER=$(echo "$REMOTE_LIST" | awk -v p="$PKG" '$1==p{print $2}')
                [ -z "$REMOTE_VER" ] && continue
                if [ "$INST_VER" = "$REMOTE_VER" ]; then
                    echo -e "[\e[1;32m=\e[0m] $PKG v$INST_VER is up-to-date"; SKIPPED=$((SKIPPED+1)); continue
                fi
                echo -e "\e[1;33m[~] Upgrading $PKG ($INST_VER -> $REMOTE_VER)...\e[0m"
                wget -q --no-check-certificate "$REPO_URL/$PKG" -O "/tmp/${PKG}.new"
                if [ $? -eq 0 ] && [ -s "/tmp/${PKG}.new" ]; then
                    EXP=$(echo "$REMOTE_LIST" | awk -v p="$PKG" '$1==p{print $3}')
                    PKG_DEPS=$(echo "$REMOTE_LIST" | awk -v p="$PKG" '$1==p{print $4}'); [ -z "$PKG_DEPS" ] && PKG_DEPS="-"
                    if [ -n "$EXP" ]; then
                        ACT=$(sha256sum "/tmp/${PKG}.new" | awk '{print $1}')
                        if [ "$ACT" != "$EXP" ]; then rm -f "/tmp/${PKG}.new"; echo -e "\e[1;31m[!] SHA256 mismatch: $PKG\e[0m"; FAILED=$((FAILED+1)); continue; fi
                    fi
                    mv "/tmp/${PKG}.new" "$INSTALL_BIN/$PKG"; chmod +x "$INSTALL_BIN/$PKG"
                    sed -i "/^$PKG /d" "$PKG_DB" 2>/dev/null
                    echo "$PKG $REMOTE_VER (github) deps:$PKG_DEPS" >> "$PKG_DB"
                    echo -e "\e[1;32m[+] $PKG upgraded to v$REMOTE_VER\e[0m"; UPGRADED=$((UPGRADED+1))
                else
                    rm -f "/tmp/${PKG}.new"; echo -e "\e[1;31m[!] Failed: $PKG\e[0m"; FAILED=$((FAILED+1))
                fi
            done < "$PKG_DB"
            echo -e "\e[1;34m[=] Upgraded: $UPGRADED  Up-to-date: $SKIPPED  Failed: $FAILED\e[0m"
            ;;
        *)
            echo "bpm - BitOS Package Manager v1.5 (dep-aware, signed repo)"
            echo "Usage: bpm [install|remove|list|available|info|search|upgrade] <pkg>"
            echo "  install <pkg>   Install package + auto-install all dependencies"
            echo "  remove  <pkg>   Remove (blocked if another package depends on it)"
            echo "  list            Show installed packages with versions and deps"
            echo "  available       List all packages in the signed repository"
            echo "  info <pkg>      Package details, version, deps, install status"
            echo "  search <term>   Search built-in BusyBox applets"
            echo "  upgrade         Upgrade all installed packages to latest version"
            ;;
    esac
}

# svc: Service Manager
svc() {
    _svc_pid() {
        local NAME="$1" PF="$2"
        if [ -n "$PF" ] && [ -f "$PF" ]; then cat "$PF" 2>/dev/null
        else pidof "$NAME" 2>/dev/null | awk '{print $1}'; fi
    }
    _svc_running() { local P; P=$(_svc_pid "$1" "$2"); [ -n "$P" ] && kill -0 "$P" 2>/dev/null; }
    _svc_do() {
        local NAME="$1" ACT="$2" PF START STOP
        case "$NAME" in
            sshd)    PF="/var/run/sshd.pid";  START="/usr/sbin/sshd";                               STOP="kill \$(cat $PF)" ;;
            httpd)   PF="";                    START="httpd -p 80 -h /var/www -c /etc/httpd.conf"; STOP="killall httpd" ;;
            crond)   PF="";                    START="crond -b -l 8 -L /var/log/cron.log";         STOP="killall crond" ;;
            telnetd) PF="";                    START="telnetd -l /bin/bash";                       STOP="killall telnetd" ;;
            syslogd) PF="";                    START="syslogd -S -b 7 -s 200 -O /var/log/messages"; STOP="killall syslogd" ;;
            *) echo "[!] Unknown service '$NAME'. Known: sshd httpd crond telnetd syslogd"; return 1 ;;
        esac
        case "$ACT" in
            start)
                if _svc_running "$NAME" "$PF"; then
                    echo -e "[\e[1;33m$NAME\e[0m] already running (pid: $(_svc_pid $NAME $PF))"
                else
                    eval "$START" && echo -e "[\e[1;32m$NAME\e[0m] started" || echo -e "[\e[1;31m$NAME\e[0m] failed to start"
                fi ;;
            stop)
                if _svc_running "$NAME" "$PF"; then
                    eval "$STOP" 2>/dev/null && echo -e "[\e[1;33m$NAME\e[0m] stopped" || echo -e "[\e[1;31m$NAME\e[0m] stop failed"
                else
                    echo -e "[\e[1;33m$NAME\e[0m] not running"
                fi ;;
            restart) _svc_do "$NAME" stop; sleep 1; _svc_do "$NAME" start ;;
            status)
                if _svc_running "$NAME" "$PF"; then
                    echo -e "  [\e[1;32m running \e[0m] $NAME  (pid: $(_svc_pid $NAME $PF))"
                else
                    echo -e "  [\e[1;31m stopped \e[0m] $NAME"
                fi ;;
        esac
    }
    local ACT="$1"; shift
    case "$ACT" in
        start|stop|restart|status)
            if [ -z "$1" ]; then
                [ "$ACT" = "status" ] && echo -e "\e[1;34m--- Service Status ---\e[0m"
                for S in sshd httpd crond telnetd syslogd; do _svc_do "$S" "$ACT"; done
            else
                for S in "$@"; do _svc_do "$S" "$ACT"; done
            fi ;;
        *)
            echo "Usage: svc [start|stop|restart|status] [service...]"
            echo "       svc status          - show all services"
            echo "       svc restart sshd    - restart specific service"
            echo "Services: sshd  httpd  crond  telnetd  syslogd" ;;
    esac
}

# Add a simple login tool for switching users
login_as() {
    exec su - "$1"
}

# adduser: Add a new user
adduser() {
    [ -z "$1" ] && echo "Usage: adduser <username> [uid]" && return 1
    USERNAME="$1"
    UID_NUM="${2:-$(awk -F: '{if($3>999 && $3<65534) print $3}' /etc/passwd | sort -n | tail -1 | xargs -I{} expr {} + 1 || echo 1000)}"
    grep -q "^$USERNAME:" /etc/passwd && echo "[!] User $USERNAME already exists" && return 1
    echo "${USERNAME}:x:${UID_NUM}:${UID_NUM}::/home/${USERNAME}:/bin/bash" >> /etc/passwd
    echo "${USERNAME}:x:${UID_NUM}:" >> /etc/group
    echo "${USERNAME}:!:19000:0:99999:7:::" >> /etc/shadow
    mkdir -p "/home/${USERNAME}"
    chmod 700 "/home/${USERNAME}"
    echo "[+] User $USERNAME created (uid=$UID_NUM). Set password: passwd $USERNAME"
    _persist_etc /etc/passwd /etc/shadow /etc/group
}

# deluser: Delete a user
deluser() {
    [ -z "$1" ] && echo "Usage: deluser <username>" && return 1
    USERNAME="$1"
    grep -q "^$USERNAME:" /etc/passwd || { echo "[!] User $USERNAME not found"; return 1; }
    sed -i "/^${USERNAME}:/d" /etc/passwd
    sed -i "/^${USERNAME}:/d" /etc/shadow
    sed -i "/^${USERNAME}:/d" /etc/group
    echo "[-] User $USERNAME removed."
    echo -n "Remove home directory /home/$USERNAME? (y/N): "
    read -r RMHOME
    [ "$RMHOME" = "y" ] && rm -rf "/home/$USERNAME" && echo "[-] /home/$USERNAME removed."
    _persist_etc /etc/passwd /etc/shadow /etc/group
}

# lsusers: List all non-system users
lsusers() {
    echo -e "\e[1;34m--- User Accounts ---\e[0m"
    awk -F: '$3 >= 1000 && $3 < 65534 {printf "  %-16s uid=%-6s home=%s\n", $1, $3, $6}' /etc/passwd
    echo ""
    echo -e "\e[1;34m--- System Accounts ---\e[0m"
    awk -F: '$3 < 1000 {printf "  %-16s uid=%-6s shell=%s\n", $1, $3, $7}' /etc/passwd
}

# chpasswd_user: Interactive password change for any user (root only)
chpasswd_user() {
    [ -z "$1" ] && echo "Usage: chpasswd_user <username>" && return 1
    passwd "$1"
}

# bit-install: Simple HDD Installer
bit_install() {
    TARGET_DEV="$1"
    [ -z "$TARGET_DEV" ] && echo "Usage: bit_install /dev/vdb" && return 1
    [ ! -b "$TARGET_DEV" ] && echo -e "\e[1;31m[!] $TARGET_DEV is not a block device\e[0m" && return 1

    echo -e "\e[1;31m!!! WARNING: ALL DATA ON $TARGET_DEV WILL BE ERASED !!!\e[0m"
    echo -e "Device info: $(fdisk -l $TARGET_DEV 2>/dev/null | head -3)"
    echo -n "Type 'yes' to confirm: "
    read -r CONFIRM
    [ "$CONFIRM" != "yes" ] && echo "Aborted." && return 1

    # --- Partition ---
    echo -e "\e[1;34m[1/5] Partitioning $TARGET_DEV...\e[0m"
    printf 'o\nn\np\n1\n\n\nw\n' | fdisk "$TARGET_DEV" >/dev/null 2>&1
    sleep 1
    # Determine partition name (vda->vda1, sda->sda1, nvme0n1->nvme0n1p1)
    if echo "$TARGET_DEV" | grep -q "nvme"; then
        PART="${TARGET_DEV}p1"
    else
        PART="${TARGET_DEV}1"
    fi

    # --- Format ---
    echo -e "\e[1;34m[2/5] Formatting $PART as ext4...\e[0m"
    mkfs.ext4 -L BitOS "$PART" >/dev/null 2>&1 || { echo -e "\e[1;31m[!] mkfs.ext4 failed\e[0m"; return 1; }

    # --- Mount ---
    echo -e "\e[1;34m[3/5] Mounting $PART...\e[0m"
    mkdir -p /mnt/bitos_install
    mount "$PART" /mnt/bitos_install || { echo -e "\e[1;31m[!] mount failed\e[0m"; return 1; }

    # --- Copy System ---
    echo -e "\e[1;34m[4/5] Copying system files...\e[0m"
    mkdir -p /mnt/bitos_install/boot
    # Kernel is at /boot/vmlinuz on ISO (ISOLINUX structure)
    KERN=$(find /boot /mnt /cdrom /media -name "vmlinuz" 2>/dev/null | head -1)
    INITRD=$(find /boot /mnt /cdrom /media -name "initramfs.cpio.gz" 2>/dev/null | head -1)
    [ -z "$KERN" ]  && KERN="/vmlinuz"
    [ -z "$INITRD" ] && INITRD="/initramfs.cpio.gz"
    cp "$KERN" /mnt/bitos_install/boot/vmlinuz 2>/dev/null || \
        { echo -e "\e[1;31m[!] Kernel not found at $KERN\e[0m"; umount /mnt/bitos_install; return 1; }
    cp "$INITRD" /mnt/bitos_install/boot/initramfs.cpio.gz 2>/dev/null || \
        { echo -e "\e[1;31m[!] Initrd not found at $INITRD\e[0m"; umount /mnt/bitos_install; return 1; }
    mkdir -p /mnt/bitos_install/home

    # --- Write boot config hint ---
    cat > /mnt/bitos_install/boot/boot.txt << BOOTEOF
BitOS Boot Parameters:
  kernel: /boot/vmlinuz
  initrd: /boot/initramfs.cpio.gz
  cmdline: console=ttyS0 root=/dev/$( basename $PART ) rw

To boot with QEMU:
  qemu-system-x86_64 -kernel /boot/vmlinuz -initrd /boot/initramfs.cpio.gz \
    -hda $TARGET_DEV -append "root=$PART rw console=ttyS0"
BOOTEOF

    umount /mnt/bitos_install
    echo -e "\e[1;32m[5/5] Installation complete!\e[0m"
    echo ""
    echo -e "  Kernel:  $KERN -> /boot/vmlinuz"
    echo -e "  Initrd:  $INITRD -> /boot/initramfs.cpio.gz"
    echo -e "  Boot:    cat /mnt/bitos_install/boot/boot.txt"
    echo -e "\e[1;33m  To boot without ISO, use kernel+initrd directly in QEMU.\e[0m"
}

# bit-setup: First-boot configuration wizard
bit_setup() {
    echo -e "\e[1;34m"
    echo "  ____  _ _    ___  ____    ____       _               "
    echo " | __ )(_) |_ / _ \/ ___|  / ___|  ___| |_ _   _ _ __  "
    echo " |  _ \| | __| | | \___ \  \___ \ / _ \ __| | | | '_ \ "
    echo " | |_) | | |_| |_| |___) |  ___) |  __/ |_| |_| | |_) |"
    echo " |____/|_|\__|\___/|____/  |____/ \___|\__|\__,_| .__/ "
    echo "                                                  |_|    "
    echo -e "\e[0m"
    echo -e "\e[1;33mFirst-Boot Setup Wizard\e[0m"
    echo "-------------------------------------------"

    # Hostname
    echo -n "Hostname [$( hostname )]: "
    read -r NEW_HOST
    if [ -n "$NEW_HOST" ]; then
        echo "$NEW_HOST" > /etc/hostname
        hostname "$NEW_HOST"
        echo -e "\e[1;32m[+] Hostname set to: $NEW_HOST\e[0m"
    fi

    # Root password
    echo -n "Set root password? (y/N): "
    read -r DO_PASS
    [ "$DO_PASS" = "y" ] && passwd root

    # Services
    echo ""
    echo -e "\e[1;34mEnable/disable services:\e[0m"
    for SVC in sshd telnetd crond; do
        echo -n "  Enable $SVC? (Y/n): "
        read -r EN
        if [ "$EN" = "n" ]; then
            svc stop "$SVC" 2>/dev/null
            echo -e "  \e[1;33m[-] $SVC disabled\e[0m"
        else
            svc start "$SVC" 2>/dev/null
            echo -e "  \e[1;32m[+] $SVC enabled\e[0m"
        fi
    done

    # Timezone
    echo ""
    echo -n "Timezone (e.g. UTC, Asia/Yangon) [UTC]: "
    read -r TZ_NAME
    if [ -n "$TZ_NAME" ] && [ -f "/usr/share/zoneinfo/$TZ_NAME" ]; then
        cp "/usr/share/zoneinfo/$TZ_NAME" /etc/localtime
        echo "$TZ_NAME" > /etc/timezone
        echo -e "\e[1;32m[+] Timezone set to $TZ_NAME\e[0m"
    else
        echo -e "\e[1;33m[=] Keeping UTC\e[0m"
    fi

    touch /etc/bitos.configured
    _persist_etc /etc/hostname /etc/passwd /etc/shadow /etc/group /etc/bitos.configured
    echo ""
    echo -e "\e[1;32m[!] Setup complete! Dashboard: http://$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1):80/dashboard.cgi\e[0m"
    echo ""
}

# Show system info on login
bit_info

# First-boot: prompt setup wizard if not yet configured
if [ ! -f /etc/bitos.configured ]; then
    echo -e "\e[1;33m[!] BitOS not yet configured. Run 'bit_setup' to configure.\e[0m"
fi
EOF

log_info "Creating legacy init symlink..."
ln -sf /sbin/init init

log_info "Updating module dependencies..."
# Use host depmod to create modules.dep for the target
depmod -b . "$KERNEL_VERSION"

log_info "Generating initramfs image..."
find . | cpio -H newc -o | gzip > "$OUTPUT_DIR/initramfs.cpio.gz"
log_info "Initramfs created at $OUTPUT_DIR/initramfs.cpio.gz"

log_info "Copying Kernel to output..."
cp "$SRC_DIR/linux-$KERNEL_VERSION/arch/x86/boot/bzImage" "$OUTPUT_DIR/vmlinuz"
log_info "Kernel copied to $OUTPUT_DIR/vmlinuz"
