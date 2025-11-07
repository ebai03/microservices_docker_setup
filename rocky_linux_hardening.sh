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

################################################################################
# Phase 2: OpenSCAP and CIS Benchmark
################################################################################

phase_openscap() {
    log_info "=== PHASE 2: OPENSCAP INSTALLATION AND CONFIGURATION ==="
    
    # Install OpenSCAP
    log_info "Installing OpenSCAP and SCAP Security Guide..."
    if ! dnf install -y openscap-scanner scap-security-guide &>> "$LOG_FILE"; then
        log_error "Failed to install OpenSCAP"
        return 1
    fi
    log_success "OpenSCAP installed successfully"
    
    # Generate remediation script
    log_info "Generating CIS Server L1 profile remediation script..."
    local remediate_script="${BACKUP_DIR}/remediate-cis.sh"
    
    if ! oscap xccdf generate fix \
        --profile xccdf_org.ssgproject.content_profile_cis_server_l1 \
        /usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml > "$remediate_script" 2>> "$LOG_FILE"; then
        log_error "Failed to generate remediation script"
        return 1
    fi
    
    # Apply patches: Disable password expiration to avoid lockouts
    log_info "Applying patches to remediation script..."
    sed -i "s/var_accounts_maximum_age_login_defs='[0-9]*'/var_accounts_maximum_age_login_defs='-1'/g" "$remediate_script"
    
    chmod +x "$remediate_script"
    log_success "Remediation script generated at: $remediate_script"
    
    log_info "Running CIS remediation script..."
    if ! bash "$remediate_script" &>> "$LOG_FILE"; then
        log_warning "Some remediation script rules may have failed"
    fi
    
    log_success "OpenSCAP phase completed"
}

################################################################################
# Phase 3: /tmp Partition Configuration
################################################################################

phase_tmp_partition() {
    log_info "=== PHASE 3: /tmp PARTITION CONFIGURATION ==="
    
    # Backup fstab
    backup_file /etc/fstab
    
    log_info "Mounting /tmp as tmpfs with security options..."
    if ! mount -t tmpfs -o size=25%,defaults,rw,nosuid,nodev,noexec,relatime tmpfs /tmp 2>> "$LOG_FILE"; then
        log_error "Failed to mount /tmp"
        return 1
    fi
    log_success "/tmp mounted successfully"
    
    # Configure fstab for persistence
    log_info "Configuring /etc/fstab for persistence..."
    if ! grep -q "^tmpfs[[:space:]]*0[[:space:]]*\/tmp" /etc/fstab; then
        echo "tmpfs 0 /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=25% 0 0" >> /etc/fstab
        log_success "Entry added to /etc/fstab"
    else
        log_warning "/tmp is already configured in /etc/fstab"
    fi
    
    log_success "/tmp configuration phase completed"
}

################################################################################
# Phase 4: GRUB Configuration
################################################################################

phase_grub_password() {
    log_info "=== PHASE 4: GRUB PASSWORD CONFIGURATION ==="
    
    log_info "Setting password for GRUB..."
    # Note: grub2-setpassword is interactive, use with caution
    # To automate, grub2-mkpasswd-pbkdf2 can be used
    
    read -sp "Enter password for GRUB (or press Enter to use default password): " grub_pass
    echo
    
    if [[ -z "$grub_pass" ]]; then
        log_warning "GRUB password configuration skipped"
        return 0
    fi
    
    # Generate password hash
    local grub_hash=$(echo -e "$grub_pass\n$grub_pass" | grub2-mkpasswd-pbkdf2 | grep -oP 'grub.pbkdf2.sha512.10000.\K.*')
    
    backup_file /etc/grub.d/40_custom
    
    cat >> /etc/grub.d/40_custom << EOF
set superusers="root"
password_pbkdf2 root $grub_hash
EOF
    
    chmod 600 /etc/grub.d/40_custom
    
    log_info "Regenerating GRUB configuration..."
    grub2-mkconfig -o /boot/grub2/grub.cfg &>> "$LOG_FILE"
    
    log_success "GRUB password configured"
}

################################################################################
# Phase 5: SELinux Configuration
################################################################################

phase_selinux() {
    log_info "=== PHASE 5: SELINUX CONFIGURATION ==="
    
    backup_file /etc/selinux/config
    
    log_info "Installing libselinux..."
    if ! dnf install -y libselinux &>> "$LOG_FILE"; then
        log_warning "Failed to install libselinux"
    fi
    
    log_info "Configuring SELinux to enforcing mode..."
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    
    log_success "SELinux configured to enforcing mode"
    log_warning "SELinux will enter enforcing mode on next reboot"
}


################################################################################
# Help Functions
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [OPTION]

Options:
    -h, --help              Show this help message
    -f, --full              Run all phases (default)
    -p, --phase PHASE       Run only a specific phase
    -l, --list-phases       List all available phases
    -b, --backup-dir DIR    Specify backup directory
    
Available phases:
    1  - preparation        (Initial preparation)
    2  - openscap          (OpenSCAP installation and CIS Benchmark)
    3  - tmp-partition     (/tmp configuration)
    4  - grub              (GRUB password)
    5  - selinux           (SELinux configuration)
    6  - ssh               (SSH hardening)
    7  - fail2ban          (Fail2ban installation)
    8  - firewall          (Firewall configuration)
    9  - updates           (Automatic updates)
EOF
}

list_phases() {
    cat << EOF
Available hardening phases:

1.  Preparation: Create backup directories and validate system
2.  OpenSCAP: Install tools and apply CIS Server L1 profile
3.  /tmp: Configure separate partition with security options
4.  GRUB: Set password on bootloader
5.  SELinux: Configure to enforcing mode
6.  SSH: Hardening configuration and public key authentication
7.  Fail2ban: Protection against brute force attacks
8.  Firewall: firewalld configuration
9.  Updates: Configure automatic security patches
EOF
}

################################################################################
# Main Execution
################################################################################

main() {
    local phase_to_run="all"
    
    # Process arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--list-phases)
                list_phases
                exit 0
                ;;
            -f|--full)
                phase_to_run="all"
                shift
                ;;
            -p|--phase)
                phase_to_run="$2"
                shift 2
                ;;
            -b|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initial checks
    check_root
    check_rocky_linux
    
    log_info "Starting Rocky Linux 9.3 hardening script"
    log_info "Log file: $LOG_FILE"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Date and time: $(date)"
    
    # Run phases
    case $phase_to_run in
        all)
            phase_preparation
            phase_openscap
            phase_tmp_partition
            phase_grub_password
            phase_selinux
            phase_ssh_hardening
            phase_fail2ban
            phase_firewall
            phase_automatic_updates
            phase_verification
            ;;
        1|preparation)
            phase_preparation
            ;;
        2|openscap)
            phase_openscap
            ;;
        3|tmp-partition)
            phase_tmp_partition
            ;;
        4|grub)
            phase_grub_password
            ;;
        5|selinux)
            phase_selinux
            ;;
        6|ssh)
            phase_ssh_hardening
            ;;
        7|fail2ban)
            phase_fail2ban
            ;;
        8|firewall)
            phase_firewall
            ;;
        9|updates)
            phase_automatic_updates
            ;;
        *)
            log_error "Unknown phase: $phase_to_run"
            list_phases
            exit 1
            ;;
    esac
    
    log_success "Hardening script completed"
    log_info "Backups are located at: $BACKUP_DIR"
    log_info "Check the log at: $LOG_FILE"
    
    echo
    log_warning "IMPORTANT: It is recommended to reboot the system to apply all changes"
    log_warning "Especially SELinux which requires reboot to enter enforcing mode"
}
