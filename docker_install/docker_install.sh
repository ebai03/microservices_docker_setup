#!/bin/bash

CURRENT_USER="${SUDO_USER:-$(whoami)}"

# Logging functions
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Append to LOG_FILE and print it on screen
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_warning() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }

check_root () {
    if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
    fi

    log_success "Verified UID (root)"
}

check_docker_is_not_active() {
    if systemctl is-active --quiet docker; then
        log_error "Docker daemon is active."
        exit 1
    else
        log_success "Docker daemon is not active."
    fi
}

log_info "Installing upgrades that provide security patches or bugfixes"
# Make any necessary upgrades
dnf upgrade-minimal

echo ""
log_warning "Installing docker"
# Install docker https://docs.docker.com/engine/install/rhel/
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log_warning "Verifying that docker is not active"


check_docker_is_not_active

# Configure IP range BEFORE initializing docker
sudo mkdir -p /etc/docker