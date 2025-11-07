#!/bin/bash

CURRENT_USER="${SUDO_USER:-$(whoami)}"
LOG_FILE="/var/log/install_docker.log"

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

configure_docker_network() {
    log_info "Configuring Docker network range..."
    
    # Create docker config directory if it doesn't exist
    mkdir -p /etc/docker
    
    # Create daemon.json with custom network configuration
    # Using 10.10.0.0/16 to avoid conflicts with 172.24.x.x networks
    cat > /etc/docker/daemon.json <<'EOF'
{
  "bip": "10.10.0.1/16",
  "fixed-cidr": "10.10.0.0/16",
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Docker daemon.json created successfully"
        log_info "Docker network configuration:"
        log_info "  - Bridge IP (bip): 10.10.0.1/16"
        log_info "  - CIDR range: 10.10.0.0/16"
        log_info "  - Storage driver: overlay2"
        cat /etc/docker/daemon.json | tee -a "$LOG_FILE"
    else
        log_error "Failed to create /etc/docker/daemon.json"
        exit 1
    fi
}

verify_docker_config() {
    log_info "Verifying Docker configuration..."
    
    if [[ ! -f /etc/docker/daemon.json ]]; then
        log_error "Docker configuration file not found"
        exit 1
    fi
    
    # Validate JSON syntax
    if ! python3 -m json.tool /etc/docker/daemon.json > /dev/null 2>&1; then
        log_error "Invalid JSON in /etc/docker/daemon.json"
        exit 1
    fi
    
    log_success "Docker configuration is valid"
}

start_docker_service() {
    log_info "Starting Docker service..."
    
    systemctl daemon-reload
    systemctl start docker
    
    if systemctl is-active --quiet docker; then
        log_success "Docker service started successfully"
    else
        log_error "Failed to start Docker service"
        exit 1
    fi
}

enable_docker_service() {
    log_info "Enabling Docker service on boot..."
    
    systemctl enable docker
    
    if systemctl is-enabled --quiet docker; then
        log_success "Docker service enabled on boot"
    else
        log_error "Failed to enable Docker service"
        exit 1
    fi
}

verify_docker_network() {
    log_info "Verifying Docker network configuration..."
    
    sleep 2  # Give Docker time to initialize
    
    # Get the docker0 bridge IP
    DOCKER_IP=$(ip addr show docker0 2>/dev/null | grep "inet " | awk '{print $2}')
    
    if [[ -z "$DOCKER_IP" ]]; then
        log_warning "docker0 interface not found (might be normal if no containers are running)"
    else
        log_success "Docker bridge (docker0) configured with: $DOCKER_IP"
    fi
    
    # Show network inspection
    docker network inspect bridge > /tmp/docker_network.txt 2>&1
    if [[ $? -eq 0 ]]; then
        log_success "Docker network inspection successful"
        cat /tmp/docker_network.txt | tee -a "$LOG_FILE"
    else
        log_warning "Could not inspect Docker network"
    fi
}

# Main execution
main() {
    log_info "=========================================="
    log_info "Docker Upgrade Script Started"
    log_info "User: $CURRENT_USER"
    log_info "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "=========================================="
    
    check_root
    
    log_info "Installing upgrades that provide security patches or bugfixes"
    dnf upgrade-minimal -y
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to upgrade system packages"
        exit 1
    fi
    
    log_success "System upgrade completed"
    
    log_warning "Installing Docker packages"
    dnf -y install dnf-plugins-core
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to install dnf-plugins-core"
        exit 1
    fi
    
    log_info "Adding Docker CE repository..."
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to add Docker repository"
        exit 1
    fi
    
    log_info "Installing Docker CE, CLI, containerd, buildx and compose..."
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to install Docker packages"
        exit 1
    fi
    
    log_success "Docker packages installed successfully"
    echo ""
    
    log_warning "Verifying that docker daemon is not active"
    check_docker_is_not_active
    echo ""
    
    log_warning "Configuring Docker network BEFORE starting daemon"
    configure_docker_network
    echo ""
    
    verify_docker_config
    echo ""
    
    start_docker_service
    echo ""
    
    enable_docker_service
    echo ""
    
    verify_docker_network
    echo ""
    
}

# Execute main function
main