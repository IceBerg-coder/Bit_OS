#!/bin/bash
# Re-sign packages.list after any changes
# Usage: bash scripts/sign_packages.sh
set -e
source scripts/common.sh

KEY="pkgs/keys/signing_key.pem"
PUB="pkgs/keys/signing_pubkey.pem"
LIST="pkgs/packages.list"
SIG="pkgs/packages.list.sig"

[ ! -f "$KEY" ] && log_err "Private key not found: $KEY" && exit 1

log_info "Signing packages.list..."
openssl dgst -sha256 -sign "$KEY" -out "$SIG" "$LIST"

log_info "Verifying signature..."
openssl dgst -sha256 -verify "$PUB" -signature "$SIG" "$LIST"

log_info "Done. Commit $SIG to the repository."
