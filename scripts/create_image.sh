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
mkdir -pv var/log var/run var/spool/cron/crontabs etc/rcS.d var/www etc/dropbear

log_info "Copying Dropbear SSH server..."
if [ -f "$BUILD_DIR/dropbear/sbin/dropbear" ]; then
    cp "$BUILD_DIR/dropbear/sbin/dropbear"    usr/sbin/dropbear
    cp "$BUILD_DIR/dropbear/bin/dropbearkey"  usr/bin/dropbearkey
    chmod +x usr/sbin/dropbear usr/bin/dropbearkey
    log_info "Dropbear installed: $(ls -lh usr/sbin/dropbear)"
else
    log_err "Dropbear not found! Run: bash scripts/build_dropbear.sh first"
fi

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
echo "root:x:0:" > etc/group
echo "kaung:x:1000:" >> etc/group

# Shadow file: root has no password, kaung has no password
# Format: user:hash:lastchange:min:max:warn:inactive:expire
# Empty hash = no password required
cat << 'EOF' > etc/shadow
root::19787:0:99999:7:::
kaung::19787:0:99999:7:::
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

# Start hotplug event handler (mdev)
log_msg "Starting mdev (Device Hotplug Handler)..."
mdev -s
# Register mdev only if the kernel supports UEVENT_HELPER
[ -f /proc/sys/kernel/hotplug ] && echo /sbin/mdev > /proc/sys/kernel/hotplug

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
echo "Applying basic firewall rules..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 23 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A INPUT -j DROP
echo "Firewall rules applied."
EOF
chmod +x etc/rcS.d/S40-firewall

cat << 'EOF' > etc/rcS.d/S50-sshd
#!/bin/sh
echo "Generating SSH host keys (if needed)..."
[ ! -f /etc/dropbear/dropbear_rsa_host_key ] && \
    dropbearkey -t rsa -s 2048 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ] && \
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
echo "Starting SSH server on port 22..."
dropbear -p 22 -R -B -P /var/run/dropbear.pid
echo "SSH server started. Connect: ssh root@<ip>"
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
<head><title>BitOS Web Server</title>
<style>body{background:#111;color:#0f0;font-family:monospace;padding:40px;}
h1{color:#0f0;} a{color:#0af;}</style>
</head>
<body>
<h1>&#9608;&#9608; BitOS Professional Edition</h1>
<p>This page is served by the built-in <b>BusyBox httpd</b> running on BitOS.</p>
<hr>
<p>Kernel: $(uname -r) &nbsp;|&nbsp; Host: $(hostname)</p>
</body>
</html>
EOF

log_info "Creating MOTD and profile..."
chmod +x etc/init.d/rcS

log_info "Creating MOTD and profile..."
cat << 'EOF' > etc/motd

   ____  _ _   ____   _____ 
  | __ )(_) |_/ __ \ / ___/ 
  |  _ \| | __/ / / / \__ \  
  | |_) | | |_/ /_/ / ___/ / 
  |____/|_|\__\____/ /____/  

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

# bit_pkg: Simple package manager (Applet manager)
bit_pkg() {
    # GitHub raw URL - packages live in pkgs/ directory of the repo
    REPO_URL="https://raw.githubusercontent.com/IceBerg-coder/Bit_OS/main/pkgs"
    PKG_DB="/etc/bit_pkg.db"
    PKG_LIST_URL="$REPO_URL/packages.list"
    
    case "$1" in
        "install")
            [ -z "$2" ] && echo "Usage: bit_pkg install <applet>" && return 1
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
                     echo -e "\e[1;31m[!] Error: $2 not found. Run: bit_pkg available\e[0m"
                fi
            fi
            ;;
        "remove")
            [ -z "$2" ] && echo "Usage: bit_pkg remove <applet>" && return 1
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
            echo "Fetching from: $PKG_LIST_URL"
            RESULT=$(wget -O- --no-check-certificate "$PKG_LIST_URL" 2>&1)
            if echo "$RESULT" | grep -q "^bit-\|^#"; then
                echo "$RESULT" | grep -v "^Connecting\|^HTTP\|^Length\|^Saving\|^\-\-"
            else
                echo "wget output: $RESULT"
                echo -e "\e[1;31mCould not reach GitHub. Check network.\e[0m"
                echo "DNS test: $(nslookup raw.githubusercontent.com 2>&1 | head -3)"
                echo "Route: $(route -n 2>/dev/null | grep UG | head -1)"
            fi
            ;;
        "search")
            echo -e "\e[1;34m--- Matching Built-in Applets ---\e[0m"
            busybox --list | grep "${2:-.}"
            ;;
        *)
            echo "Usage: bit_pkg [install|remove|list|available|search] <name>"
            ;;
    esac
}

# Add a simple login tool for switching users
login_as() {
    exec su - "$1"
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

[ -f /etc/motd ] && cat /etc/motd
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
