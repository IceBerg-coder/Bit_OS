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
mkdir -pv var/log var/run var/spool/cron/crontabs etc/rcS.d var/www etc/ssh lib/x86_64-linux-gnu lib64 var/empty run usr/lib/openssh usr/lib/x86_64-linux-gnu/xtables

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
echo "root:x:0:0:root:/home/root:/bin/sh" > etc/passwd
echo "kaung:x:1000:1000:kaung:/home/kaung:/bin/sh" >> etc/passwd
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
::shutdown:/bin/umount -a -r
::restart:/sbin/init
EOF

log_info "Creating etc/init.d/rcS..."
cat << 'EOF' > etc/init.d/rcS
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

# Run level 1 startup scripts (Modular init)
mkdir -p /etc/rcS.d
for script in /etc/rcS.d/S*; do
    [ -f "$script" ] && [ -x "$script" ] && log_msg "Running $script..." && "$script"
done

# Conditionally mount persistent /home if /dev/vda exists
if [ -b /dev/vda ]; then
    log_msg "Mounting persistent storage /dev/vda -> /home..."
    mount -t ext4 /dev/vda /home 2>/dev/null || log_msg "Warning: Could not mount /dev/vda"
else
    log_msg "No persistent disk found, using tmpfs for /home"
fi

# Ensure home structure exists on disk
log_msg "Preparing user environments..."
mkdir -p /home/root /home/kaung /home/bin
chown -R 1000:1000 /home/kaung 2>/dev/null

# Set hostname
hostname -F /etc/hostname
EOF

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
cat << 'EOF' > etc/rcS.d/S01-network
#!/bin/sh
echo "Bringing up eth0..."
ifconfig eth0 up
sleep 1
echo "Attempting DHCP on eth0..."
udhcpc -i eth0 -p /var/run/udhcpc.eth0.pid -q
if [ -z "$(cat /etc/resolv.conf 2>/dev/null)" ]; then
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
  echo "nameserver 1.1.1.1" >> /etc/resolv.conf
fi
echo "Network: $(ifconfig eth0 | grep 'inet ' | awk '{print $2}') DNS: $(head -1 /etc/resolv.conf 2>/dev/null)"
EOF
chmod +x etc/rcS.d/S01-network

cat << 'EOF' > etc/rcS.d/S10-depmod
#!/bin/sh
echo "Loading basic kernel modules..."
modprobe -a virtio_net virtio_blk virtio_pci 2>/dev/null
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
echo "Starting HTTP server on port 80..."
httpd -p 80 -h /var/www
echo "HTTP server started at http://$(hostname):80"
EOF
chmod +x etc/rcS.d/S50-httpd

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
DISK=$(df -h / 2>/dev/null | tail -1 | awk '{print $3"/"$2" ("$5")"}')
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
  </div>

</div>
<div class="footer">BitOS &mdash; $(date '+%Y-%m-%d %H:%M:%S %Z')</div>
</body>
</html>
HTML
CGIEOF
chmod +x var/www/dashboard.cgi

log_info "Creating MOTD and profile..."
chmod +x etc/init.d/rcS

log_info "Creating MOTD and profile..."
cat << 'EOF' > etc/motd
Welcome to BitOS Professional Edition
Type 'bit_info' for system info, 'bpm available' for packages.
Type 'lsusers' to list accounts, 'adduser/deluser' to manage users.
Dashboard: http://localhost:8180/dashboard.cgi
EOF

cat << 'EOF' > etc/profile
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/home/bin
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
export HISTFILE=$HOME/.sh_history
export HISTSIZE=1000
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

# bpm: BitOS Package Manager
bpm() {
    # GitHub raw URL - packages live in pkgs/ directory of the repo
    REPO_URL="https://raw.githubusercontent.com/IceBerg-coder/Bit_OS/main/pkgs"
    PKG_DB="/etc/bpm.db"
    PKG_LIST_URL="$REPO_URL/packages.list"
    
    case "$1" in
        "install")
            [ -z "$2" ] && echo "Usage: bpm install <name>" && return 1
            echo -e "\e[1;34m[*] Searching for $2...\e[0m"
            if busybox --list | grep -qx "$2"; then
                echo -e "\e[1;32m[+] Installing built-in applet: $2\e[0m"
                ln -sf /bin/busybox "/usr/bin/$2"
                echo "$2 (builtin)" >> "$PKG_DB"
                echo -e "\e[1;32m[!] $2 is now available\e[0m"
            else
                echo -e "\e[1;33m[-] Checking GitHub repository...\e[0m"
                wget -q --no-check-certificate "$REPO_URL/$2" -O "/usr/bin/$2"
                if [ $? -eq 0 ] && [ -s "/usr/bin/$2" ]; then
                     chmod +x "/usr/bin/$2"
                     echo "$2 (github)" >> "$PKG_DB"
                     echo -e "\e[1;32m[+] Installed $2 from GitHub repository.\e[0m"
                     echo "Run: $2"
                else
                     rm -f "/usr/bin/$2"
                     echo -e "\e[1;31m[!] Error: $2 not found. Run: bpm available\e[0m"
                fi
            fi
            ;;
        "remove")
            [ -z "$2" ] && echo "Usage: bpm remove <name>" && return 1
            if [ -f "/usr/bin/$2" ]; then
                rm "/usr/bin/$2"
                sed -i "/^$2 /d" "$PKG_DB" 2>/dev/null
                echo -e "\e[1;32m[-] Removed $2\e[0m"
            else
                echo -e "\e[1;31m[!] $2 is not installed\e[0m"
            fi
            ;;
        "list")
            echo -e "\e[1;34m--- Installed Packages ---\e[0m"
            if [ -s "$PKG_DB" ]; then cat "$PKG_DB"; else echo "(none)"; fi
            ;;
        "available")
            echo -e "\e[1;34m--- Available Packages in GitHub Repository ---\e[0m"
            RESULT=$(wget -O- -q --no-check-certificate "$PKG_LIST_URL" 2>/dev/null)
            if echo "$RESULT" | grep -q "^bit-\|^#"; then
                echo "$RESULT"
            else
                echo -e "\e[1;31mCould not reach GitHub. Check network.\e[0m"
                echo "DNS test: $(nslookup raw.githubusercontent.com 2>&1 | head -3)"
                echo "Route: $(route -n 2>/dev/null | grep UG | head -1)"
            fi
            ;;
        "search")
            echo -e "\e[1;34m--- Matching Built-in Applets ---\e[0m"
            busybox --list | grep "${2:-.}"
            ;;
        "upgrade")
            echo -e "\e[1;34m[*] Upgrading all GitHub-installed packages...\e[0m"
            if [ ! -s "$PKG_DB" ]; then
                echo "(no packages installed)"
                return 0
            fi
            UPGRADED=0; FAILED=0
            while IFS= read -r LINE; do
                PKG=$(echo "$LINE" | awk '{print $1}')
                SRC=$(echo "$LINE" | awk '{print $2}')
                [ "$SRC" != "(github)" ] && continue
                echo -e "\e[1;33m[~] Upgrading $PKG...\e[0m"
                wget -q --no-check-certificate "$REPO_URL/$PKG" -O "/tmp/${PKG}.new"
                if [ $? -eq 0 ] && [ -s "/tmp/${PKG}.new" ]; then
                    mv "/tmp/${PKG}.new" "/usr/bin/$PKG"
                    chmod +x "/usr/bin/$PKG"
                    echo -e "\e[1;32m[+] $PKG upgraded\e[0m"
                    UPGRADED=$((UPGRADED+1))
                else
                    rm -f "/tmp/${PKG}.new"
                    echo -e "\e[1;31m[!] Failed to upgrade $PKG\e[0m"
                    FAILED=$((FAILED+1))
                fi
            done < "$PKG_DB"
            echo -e "\e[1;34m[=] Done. Upgraded: $UPGRADED  Failed: $FAILED\e[0m"
            ;;
        *)
            echo "Usage: bpm [install|remove|list|available|search|upgrade] <name>"
            ;;
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
    echo "${USERNAME}:x:${UID_NUM}:${UID_NUM}::/home/${USERNAME}:/bin/sh" >> /etc/passwd
    echo "${USERNAME}:x:${UID_NUM}:" >> /etc/group
    echo "${USERNAME}:!:19000:0:99999:7:::" >> /etc/shadow
    mkdir -p "/home/${USERNAME}"
    chmod 700 "/home/${USERNAME}"
    echo "[+] User $USERNAME created (uid=$UID_NUM). Set password: passwd $USERNAME"
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
    [ -z "$TARGET_DEV" ] && echo "Usage: bit_install /dev/vda (or /dev/sda)" && return 1
    
    echo -e "\e[1;31m!!! WARNING: THIS WILL WIPE ALL DATA ON $TARGET_DEV !!!\e[0m"
    echo -n "Are you sure you want to proceed? (y/N): "
    read -r CONFIRM
    [ "$CONFIRM" != "y" ] && echo "Aborted." && return 1

    echo -e "\e[1;34m[*] Partitioning $TARGET_DEV...\e[0m"
    # Create a single primary bootable partition
    echo -e "o\nn\np\n1\n\n\na\n1\nw" | fdisk "$TARGET_DEV" >/dev/null 2>&1
    
    echo -e "\e[1;34m[*] Formatting ${TARGET_DEV}1 as ext4...\e[0m"
    mkfs.ext4 "${TARGET_DEV}1" >/dev/null 2>&1
    
    echo -e "\e[1;34m[*] Mounting ${TARGET_DEV}1 to /mnt...\e[0m"
    mkdir -p /mnt
    mount "${TARGET_DEV}1" /mnt
    
    echo -e "\e[1;34m[*] Installing System Files (Kernel & Initrd)...\e[0m"
    mkdir -p /mnt/boot
    # These paths come from the ISO/CD structure
    cp /vmlinuz /mnt/boot/vmlinuz
    cp /initramfs.cpio.gz /mnt/boot/initramfs.cpio.gz
    
    echo -e "\e[1;34m[*] Preparing persistence directory...\e[0m"
    mkdir -p /mnt/home
    
    echo -e "\e[1;32m[+] Installation Complete!\e[0m"
    echo "Note: To boot from this disk, ensure your bootloader (QEMU/VM) points to $TARGET_DEV."
    umount /mnt
}

# Show system info on login
bit_info
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
