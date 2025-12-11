#!/bin/bash

################################################################################
# Hardening Script for Ubuntu 24.04 LTS based on the CIS v1.0.0 Benchmark
# This script automates security recommendations from the report "OS_hardening.md"
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
ROOT_DIR="/home/${SUDO_USER:-$(whoami)}/hardening-$(date +%Y%m%d)"
LOG_FILE="$ROOT_DIR/log"
BACKUP_DIR="$ROOT_DIR/backup"
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


check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script is designed for Ubuntu"
        exit 1
    fi
    
    local version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log_success "Operating system verified: Ubuntu $version"
    
    if [[ "$version" != "24.04" ]]; then
        log_warning "This script is optimized for Ubuntu 24.04 LTS, detected:  $version"
        read -p "Do you want to continue?  (y/n): " -n 1 -r
        echo
        if [[ !  $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

backup_dir_structure() {
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory created: $BACKUP_DIR"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_path="${BACKUP_DIR}$(dirname "$file")"
        mkdir -p "$backup_path"
        cp -p "$file" "$backup_path/"
        log_info "Backup created: $file"
    fi
}

################################################################################
# Phase 1: Preparation
################################################################################

phase_preparation() {
    log_info "=== PHASE 1: PREPARATION ==="

    backup_dir_structure

    log_info "Updating system packages..."
    apt update
    apt -y upgrade

    if [[ $? -ne 0 ]]; then
        log_error "Failed to upgrade system packages"
        exit 1
    fi
    
    log_success "System upgrade completed"
    log_success "Preparation phase completed"
}

################################################################################
# Phase 2: OpenSCAP and CIS Benchmark
################################################################################

phase_openscap() {
    log_info "=== PHASE 2: OPENSCAP INSTALLATION AND CONFIGURATION ==="
    
    # Install OpenSCAP
    log_info "Installing OpenSCAP and SCAP Security Guide..."
    if ! apt install -y openscap-scanner libopenscap25t64 ssg-base ssg-debderived ssg-debian ssg-nondebian ssg-applications &>> "$LOG_FILE"; then
        log_error "Failed to install OpenSCAP"
        return 1
    fi
    log_success "OpenSCAP installed successfully"
    
    # Download and install Ubuntu 24.04 specific content
    log_info "Downloading Ubuntu 24.04 SCAP content..."
    local scap_version="0.1.79"
    local scap_url="https://github.com/ComplianceAsCode/content/releases/download/v${scap_version}/scap-security-guide-${scap_version}.tar.gz"
    local scap_download_dir="${BACKUP_DIR}/scap-download"

    mkdir -p "$scap_download_dir"

    if wget -q -O "${scap_download_dir}/scap-security-guide-${scap_version}.tar.gz" "$scap_url"; then
        log_success "Downloaded SCAP Security Guide"
    else
        log_error "Failed to download SCAP Security Guide from $scap_url"
        return 1
    fi

    log_info "Extracting SCAP content..."
    tar -xzf "${scap_download_dir}/scap-security-guide-${scap_version}.tar.gz" -C "$scap_download_dir"
    
    # Copy Ubuntu content
    local scap_extract_dir="${scap_download_dir}/scap-security-guide-${scap_version}"
    local scap_content_dir="/usr/share/xml/scap/ssg/content"
    
    mkdir -p "$scap_content_dir"
    if ! cp "${scap_extract_dir}"/ssg-ubuntu2404-ds.xml "$scap_content_dir/"; then
        log_error "Failed to copy SCAP content"
        return 1
    fi
    log_success "Ubuntu 24.04 SCAP content installed"

    # Generate remediation script
    log_info "Generating CIS Server L1 profile remediation script..."
    local remediate_script="${BACKUP_DIR}/remediate-cis.sh"
    
    if ! oscap xccdf generate fix \
        --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
        /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml > "$remediate_script" 2>> "$LOG_FILE"; then
        log_warning "Failed to generate remediation script, this is normal if profile is not complete yet"
    else
        chmod +x "$remediate_script"
        log_success "Remediation script generated at: $remediate_script"
        
        log_info "Running CIS remediation script..."
        if !  bash "$remediate_script" &>> "$LOG_FILE"; then
            log_warning "Some remediation script rules may have failed"
        fi
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
    
    log_info "Checking current /tmp mount..."
    if mount | grep -q "on /tmp type tmpfs"; then
        log_info "/tmp is already mounted as tmpfs, reconfiguring..."
        umount /tmp || true
    fi
    
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

    # Install grub-common if not present
    apt install -y grub-common &>> "$LOG_FILE"
    
    # Generate password hash
    log_info "Generating password hash..."
    local grub_hash=$(echo -e "$grub_pass\n$grub_pass" | grub-mkpasswd-pbkdf2 | grep -oP 'grub.pbkdf2.sha512.\K.*')
    
    if [[ -z "$grub_hash" ]]; then
        log_error "Failed to generate GRUB password hash"
        return 1
    fi

    mkdir -p "${BACKUP_DIR}/etc/grub.d"

    backup_file /etc/grub.d/40_custom
    
    cat >> /etc/grub.d/40_custom << EOF
# GRUB Password Protection
set superusers="root"
password_pbkdf2 root grub.pbkdf2.sha512.$grub_hash
EOF
    
    chmod 755 /etc/grub.d/40_custom
    
    log_info "Regenerating GRUB configuration..."
    update-grub &>> "$LOG_FILE"
    
    log_success "GRUB password configured"
}

################################################################################
# Phase 5: AppArmor Configuration
################################################################################

phase_apparmor() {
    log_info "=== PHASE 5: APPARMOR CONFIGURATION ==="
    
    log_info "Installing AppArmor utilities..."
    if ! apt install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra &>> "$LOG_FILE"; then
        log_warning "Failed to install some AppArmor packages"
    fi
    
    log_info "Enabling AppArmor..."
    systemctl enable apparmor
    systemctl start apparmor
    
    log_info "Checking AppArmor status..."
    if aa-enabled &>> "$LOG_FILE"; then
        log_success "AppArmor is enabled"
    else
        log_warning "AppArmor is not enabled"
    fi
    
    log_info "AppArmor profiles status:"
    aa-status | tee -a "$LOG_FILE"
    
    log_success "AppArmor configured successfully"
    log_info "You can manage profiles with: aa-enforce, aa-complain, aa-disable"
}


################################################################################
# Phase 6: System Banner Hardening
################################################################################

phase_banner_hardening() {
    log_info "=== PHASE 6: SYSTEM BANNER HARDENING ==="
    
    backup_dir_structure

    mkdir -p "${BACKUP_DIR}/etc"

    backup_file /etc/issue
    backup_file /etc/issue.net
    backup_file /etc/motd
    
    # Remove OS information from banners
    log_info "Configuring /etc/issue banner..."
    cat > /etc/issue << 'EOF'
Authorized access only.  All activity may be monitored and reported.
EOF
    # Same content for network banner
    cp /etc/issue /etc/issue.net

    # Remove dynamic MOTD generators that reveal OS info
    log_info "Disabling OS information in MOTD..."
    if [ -d /etc/update-motd. d ]; then
        chmod -x /etc/update-motd.d/10-help-text 2>/dev/null || true
        chmod -x /etc/update-motd.d/50-landscape-sysinfo 2>/dev/null || true
        chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true
    fi
    
    # Customize MOTD (Message of the Day)
    log_info "Customizing MOTD..."
   cat > /etc/motd << 'EOF'

                      /^--^\     /^--^\     /^--^\
                      \____/     \____/     \____/
                     /      \   /      \   /      \
                    |        | |        | |        |
                     \__  __/   \__  __/   \__  __/
|^|^|^|^|^|^|^|^|^|^|^|^\ \^|^|^|^/ /^|^|^|^|^\ \^|^|^|^|^|^|^|^|^|^|^|^|
| | | | | | | | | | | | |\ \| | |/ /| | | | | | \ \ | | | | | | | | | | |
########################/ /######\ \###########/ /#######################
| | | | | | | | | | | | \/| | | | \/| | | | | |\/ | | | | | | | | | | | |
|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|
EOF

    # Remove OS info from SSH banner if exists
    if [[ -f /etc/ssh/sshd_banner ]]; then
        backup_file /etc/ssh/sshd_banner
        cp /etc/issue /etc/ssh/sshd_banner
    fi
    
    # Set proper permissions
    chmod 644 /etc/issue
    chmod 644 /etc/issue.net
    chmod 644 /etc/motd
    
    log_success "System banners configured according to security policy"
}


################################################################################
# Phase 7: SSH Hardening Configuration
################################################################################

phase_ssh_hardening() {
    log_info "=== PHASE 7: SSH HARDENING CONFIGURATION ==="
    
    backup_file /etc/ssh/sshd_config
    
    log_info "Applying SSH security configurations..."
    
    # Create a hardened sshd_config
    cat > /etc/ssh/sshd_config.d/99-cis-hardening.conf << 'EOF'
# CIS Ubuntu 24.04 SSH Hardening Configuration

# Authentication
PermitRootLogin no
PermitEmptyPasswords no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
HostbasedAuthentication no
IgnoreRhosts yes

# Security Settings
MaxAuthTries 4
MaxSessions 10
MaxStartups 10:30:60

# Timeouts
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Additional Security
Banner /etc/issue.net
UsePAM yes
PrintLastLog yes
EOF
    
    log_success "SSH hardening configuration created"
    
    # Validate sshd_config syntax
    if sshd -t &>> "$LOG_FILE"; then
        log_success "SSH configuration validated"
        systemctl restart ssh || systemctl restart sshd
        log_success "SSH service restarted"
    else
        log_error "SSH configuration error - reverting changes"
        rm -f /etc/ssh/sshd_config.d/99-cis-hardening.conf
        return 1
    fi
    
    log_success "SSH hardening phase completed"
    log_warning "Make sure you have SSH key authentication configured before logging out!"
}

################################################################################
# Phase 8: Fail2ban Installation and Configuration
################################################################################

phase_fail2ban() {
    log_info "=== PHASE 8: FAIL2BAN INSTALLATION AND CONFIGURATION ==="
    
    # Install Fail2ban
    log_info "Installing Fail2ban..."
    if ! apt install -y fail2ban &>> "$LOG_FILE"; then
        log_error "Failed to install Fail2ban"
        return 1
    fi
    
    backup_file /etc/fail2ban/jail.conf
    
    # Create local configuration
    log_info "Configuring Fail2ban..."
    
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 4w

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd
maxretry = 3
bantime = 1d
EOF
    
    log_success "Fail2ban configuration created"
    
    # Enable and start service
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_success "Fail2ban enabled and started"
    
    # Show status
    log_info "Fail2ban status:"
    fail2ban-client status sshd | tee -a "$LOG_FILE" || true
}

################################################################################
# Phase 9: Firewall Configuration (UFW)
################################################################################

phase_firewall() {
    log_info "=== PHASE 9: FIREWALL CONFIGURATION ==="
    
    log_info "Installing UFW..."
    if ! apt install -y ufw &>> "$LOG_FILE"; then
        log_error "Failed to install UFW"
        return 1
    fi
    
    log_info "Configuring UFW rules..."
    
    # Reset UFW to default
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny routed
    
    # Allow SSH (important to do before enabling!)
    ufw allow ssh comment 'SSH access'
    
    # Configure logging
    ufw logging medium
    
    log_info "Enabling UFW..."
    ufw --force enable
    
    log_success "UFW configured and enabled"
    
    # Show status
    log_info "UFW status:"
    ufw status verbose | tee -a "$LOG_FILE"
    
    log_warning "Remember to allow other required ports with: ufw allow <port>/tcp"
}

################################################################################
# Phase 10: Automatic Updates Configuration
################################################################################

phase_automatic_updates() {
    log_info "=== PHASE 10: AUTOMATIC UPDATES CONFIGURATION ==="
    
    log_info "Installing unattended-upgrades..."
    if ! apt install -y unattended-upgrades apt-listchanges &>> "$LOG_FILE"; then
        log_error "Failed to install unattended-upgrades"
        return 1
    fi
    
    backup_file /etc/apt/apt. conf.d/50unattended-upgrades
    backup_file /etc/apt/apt.conf.d/20auto-upgrades
    
    # Configure automatic security updates
    log_info "Configuring automatic security updates..."
    
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade:: Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade:: DevRelease "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade:: Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF
    
    cat > /etc/apt/apt. conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT:: Periodic::AutocleanInterval "7";
APT::Periodic:: Unattended-Upgrade "1";
EOF
    
    # Enable and start service
    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades
    
    log_success "Automatic security updates configured"
    
    # Test configuration
    log_info "Testing unattended-upgrades configuration..."
    unattended-upgrades --dry-run --debug 2>&1 | tail -20 | tee -a "$LOG_FILE"
}

################################################################################
# Phase 11: Verification and Reports
################################################################################

phase_verification() {    
    log_info "=== PHASE 11: VERIFICATION AND REPORTS ==="
    
    local report_file="${BACKUP_DIR}/cis-verification-report.html"
    local scap_content="/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml"
    
    if [ !  -f "$scap_content" ]; then
        log_warning "SCAP content not found, skipping verification"
        return 0
    fi
    
    log_info "Generating CIS verification report..."
    
    if oscap xccdf eval \
        --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
        --report "$report_file" \
        "$scap_content" &>> "$LOG_FILE"; then
        log_success "Verification report generated:  $report_file"
    else
        log_warning "Some checks may have failed, but report was generated"
        log_info "Report location: $report_file"
    fi
    
    # Additional system checks
    log_info "Performing additional security checks..."
    
    echo "=== System Security Status ===" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    echo "AppArmor Status:" | tee -a "$LOG_FILE"
    aa-status 2>&1 | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    echo "UFW Status:" | tee -a "$LOG_FILE"
    ufw status numbered | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    echo "Fail2ban Status:" | tee -a "$LOG_FILE"
    fail2ban-client status 2>&1 | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    echo "SSH Configuration:" | tee -a "$LOG_FILE"
    sshd -T | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    log_success "Verification phase completed"
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
    5  - apparmor          (AppArmor configuration)
    6  - banner            (System banner hardening)
    7  - ssh               (SSH hardening)
    8  - fail2ban          (Fail2ban installation)
    9  - firewall          (UFW firewall configuration)
    10 - updates           (Automatic updates)
    11 - verification      (Final verification)

Examples:
    $0                              # Run all phases
    $0 --phase 6                    # Only configure SSH
    $0 --full                       # Run all phases explicitly

EOF
}

list_phases() {
    cat << EOF
Available hardening phases:

1.  Preparation:  Create backup directories and validate system
2.  OpenSCAP: Install tools and apply CIS Level 1 Server profile
3.  /tmp:  Configure separate partition with security options
4.  GRUB:  Set password on bootloader
5.  AppArmor: Configure mandatory access control (Ubuntu's alternative to SELinux)
6.  Banner: System banner hardening
7.  SSH: Hardening configuration and public key authentication
8.  Fail2ban: Protection against brute force attacks
9.  Firewall: UFW (Uncomplicated Firewall) configuration
10. Updates: Configure automatic security patches with unattended-upgrades
11. Verification: Generate final CIS compliance report

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

    mkdir -p "$ROOT_DIR"
    log_info "Created root directory $ROOT_DIR"

    # Initial checks
    check_root
    check_ubuntu
    
    log_info "Starting Ubuntu 24.04 LTS hardening script"
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
            phase_apparmor
            phase_banner_hardening
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
        5|apparmor)
            phase_apparmor
            ;;
        6|banner)
            phase_banner_hardening
            ;;
        7|ssh)
            phase_ssh_hardening
            ;;
        8|fail2ban)
            phase_fail2ban
            ;;
        9|firewall)
            phase_firewall
            ;;
        10|updates)
            phase_automatic_updates
            ;;
        11|verification)
            phase_verification
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
}

main "$@"
