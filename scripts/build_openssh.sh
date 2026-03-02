#!/bin/bash
source scripts/common.sh

OPENSSH_VERSION="9.9p2"
OPENSSH_TAR="openssh-${OPENSSH_VERSION}.tar.gz"
OPENSSH_URL="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/${OPENSSH_TAR}"
OPENSSH_SRC="$SRC_DIR/openssh-${OPENSSH_VERSION}"
OPENSSH_OUT="$BUILD_DIR/openssh"

mkdir -p "$SRC_DIR" "$OPENSSH_OUT/sbin" "$OPENSSH_OUT/bin" "$OPENSSH_OUT/libexec"

[ ! -f "$SRC_DIR/$OPENSSH_TAR" ] && \
    log_info "Downloading OpenSSH ${OPENSSH_VERSION}..." && \
    wget -q --show-progress "$OPENSSH_URL" -O "$SRC_DIR/$OPENSSH_TAR"

[ ! -d "$OPENSSH_SRC" ] && \
    log_info "Extracting OpenSSH..." && \
    tar -xf "$SRC_DIR/$OPENSSH_TAR" -C "$SRC_DIR"

cd "$OPENSSH_SRC"

log_info "Configuring OpenSSH..."
./configure \
    --prefix="$OPENSSH_OUT" \
    --sbindir="$OPENSSH_OUT/sbin" \
    --bindir="$OPENSSH_OUT/bin" \
    --sysconfdir=/etc/ssh \
    --with-ssl-dir=/usr \
    --with-zlib=/usr \
    --without-pam \
    --without-kerberos5 \
    --without-selinux \
    --without-libedit \
    --libexecdir=/usr/lib/openssh \
    CFLAGS="-Os" 2>&1 | tail -5

log_info "Building OpenSSH (sshd + ssh-keygen)..."
make -j$(nproc) 2>&1 | tail -5

cp sshd          "$OPENSSH_OUT/sbin/sshd"
cp ssh-keygen    "$OPENSSH_OUT/bin/ssh-keygen"
cp sshd-session  "$OPENSSH_OUT/libexec/sshd-session"
strip "$OPENSSH_OUT/sbin/sshd" "$OPENSSH_OUT/bin/ssh-keygen" "$OPENSSH_OUT/libexec/sshd-session" 2>/dev/null

log_info "Collecting shared library dependencies..."
mkdir -p "$OPENSSH_OUT/libs"
for bin in "$OPENSSH_OUT/sbin/sshd" "$OPENSSH_OUT/bin/ssh-keygen" "$OPENSSH_OUT/libexec/sshd-session"; do
    ldd "$bin" 2>/dev/null | awk '/=>/ {print $3}' | grep -v '^$' | while read lib; do
        [ -f "$lib" ] && cp -n "$lib" "$OPENSSH_OUT/libs/" && echo "  + $(basename $lib)"
    done
    ldd "$bin" 2>/dev/null | grep 'ld-linux' | awk '{print $1}' | while read lib; do
        [ -f "$lib" ] && cp -n "$lib" "$OPENSSH_OUT/libs/" && echo "  + $(basename $lib)"
    done
done
# NSS libs for user/passwd lookups
for nss in \
    /lib/x86_64-linux-gnu/libnss_files.so.2 \
    /lib/x86_64-linux-gnu/libnss_compat.so.2 \
    /lib/x86_64-linux-gnu/libresolv.so.2; do
    [ -f "$nss" ] && cp -n "$nss" "$OPENSSH_OUT/libs/" && echo "  + $(basename $nss)"
done

log_info "OpenSSH build complete:"
ls -lh "$OPENSSH_OUT/sbin/sshd" "$OPENSSH_OUT/bin/ssh-keygen" "$OPENSSH_OUT/libexec/sshd-session"
log_info "Bundled libs: $(ls $OPENSSH_OUT/libs/ | wc -l) files"
