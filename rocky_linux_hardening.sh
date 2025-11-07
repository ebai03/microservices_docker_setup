#!/bin/bash

################################################################################
# Hardening Script for Rocky Linux 9.3 based on CIS Benchmark 2.0
# This script automates security recommendations from the report "Operating System Hardening (Server).md"
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
LOG_FILE="/var/log/hardening-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/root/hardening-backup-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be executed as root"
        exit 1
    fi
}


check_rocky_linux() {
    if ! grep -q "Rocky Linux" /etc/rocky-release; then
        log_error "This script is designed for Rocky Linux"
        exit 1
    fi
    log_success "Operating system verified: $(cat /etc/rocky-release)"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp -p "$file" "${BACKUP_DIR}$(dirname $file)/"
        log_info "Backup created: $file"
    fi
}

################################################################################
# Phase 1: Preparation
################################################################################

phase_preparation() {
    log_info "=== PHASE 1: PREPARATION ==="
    
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory created: $BACKUP_DIR"
    
    # Create backup structure
    mkdir -p "${BACKUP_DIR}/etc/ssh"
    mkdir -p "${BACKUP_DIR}/etc/dnf"
    mkdir -p "${BACKUP_DIR}/etc/selinux"
    mkdir -p "${BACKUP_DIR}/etc/fail2ban"
    
    log_success "Preparation phase completed"
}

