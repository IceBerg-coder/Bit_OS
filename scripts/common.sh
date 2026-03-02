#!/bin/bash
set -e

# Common variables for Bit OS build system
WORKSPACE_ROOT="$(pwd)"
SRC_DIR="$WORKSPACE_ROOT/src"
BUILD_DIR="$WORKSPACE_ROOT/build"
OUTPUT_DIR="$WORKSPACE_ROOT/output"
ISO_DIR="$WORKSPACE_ROOT/iso"

# Versions (Latest stable at time of build recommended)
KERNEL_VERSION="6.6.15"
BUSYBOX_VERSION="1.36.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }
