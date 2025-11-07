#---------------SNAPSHOT-CREATION-SCRIPT--------------------
# Stores a backup of the system config usig tar, useful for
# sys admins that may be changing critical configurations within Linux 


# -e: Exit if any command has a non-zero exit status
# -u: All variables have to be defined (otherwise an error is thrown)
# -o pipefail: If any command in the pipeline fails, return it's exit code
set -euo pipefail

BACKUP_FOLDER="/mnt/backups"
SNAPSHOT_NAME="snapshot"
SNAPSHOT_PATH="$BACKUP_FOLDER/$SNAPSHOT_NAME"

RESTORE_SCRIPT="/usr/local/bin/restore_from_snapshot.sh"
RESTORE_SYSTEMD_SERVICE="/etc/systemd/system/emergency-restore.service"
RESTORE_EMERGENCY_TIMER="/etc/systemd/system/emergency-restore.timer"
EMERGENCY_RESTORE_SCRIPT="/usr/lib/systemd/scripts/emergency-restore.sh"

# TICK: Used as a timer to make the script run automatically
TICK_FILE="/var/run/system_snapshot.tick"
TICK_CHECK_INTERVAL=300  # 300 = 5 minutes
MAX_FAILED_TICKS=2        # Restore after MAX_FAILED consecutive ticks


CURRENT_USER="${SUDO_USER:-$(whoami)}"
LOG_FILE="/var/log/create_snapshot.log"


# Creates a list of dirs that will be included in the snapshot

create_include_list() {
    local includes_file="$SNAPSHOT_PATH/includes.txt"
    
    # Will store the list of included dirs in
    # $SNAPSHOT_PATH/includes.txt
    cat > "$includes_file" << 'INCLUDES'
# ============================================================================
# FILES AND DIRS TO INCLUDE IN THE SNAPSHOT
# ============================================================================
# SYS CONFIG
etc/
home/
root/

# ADDITIONALLY INSTALLED APPS
opt/
usr/local/

# variable data, which includes spool directories and files
var/spool/
var/lib/docker/

# NETWORK CONFIG
etc/sysconfig/
etc/NetworkManager/
etc/hostname
etc/resolv.conf

# SSH
root/.ssh/
INCLUDES
}

# Log functions
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

check_prerequisites () {
    if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
    fi

    log_success "Verified UID (root)"
}

# Creates a backup of some directories and files
create_selective_backup() {
    log_info "Creating selective snapshot..."

    mkdir -p "$SNAPSHOT_PATH"

    create_include_list

    log_info "You can check progress with:"
    log_info "  watch -n 5 'du -sh $SNAPSHOT_PATH'"
    echo ""

    if tar -cf - \
        --files-from="$SNAPSHOT_PATH/includes.txt" \
        -C / 2>/dev/null | \
        pigz > "$SNAPSHOT_PATH/system_backup.tar.gz" 2>&1; then
        log_success "Backup completed"
    else
        log_error "While backing up"
    fi

    # Result info
    local size=$(du -h "$SNAPSHOT_PATH/system_backup.tar.gz" | cut -f1)
    log_info "Snapshot size: $size"

}

# Captures network configuration
create_network_snapshot() {
    log_info "Capturing network config"

    sudo ip ad show > "$SNAPSHOT_PATH/network_interfaces.txt"

    sudo ip r show > "$SNAPSHOT_PATH/network_routes.txt"

    sudo ip rule show > "$SNAPSHOT_PATH/network_rules.txt" 2>/dev/null || true

    log_success "Network info captured"
}

# Verify prerequisites
check_prerequisites


# Generate backup
create_selective_backup
create_network_snapshot

# Show results

echo  ""
echo  "      _____________________________"
echo  "    ( Backup generated succesfully!)"
echo  "      ----------------   ----------"
echo  "                 (__) \/     "
echo  "          \------(oo)"
echo  "           ||    (__)"
echo  "           ||w--||     \|/"
echo  " \|/"
echo  "-------------------------------------"
echo  "PATH:"
echo "  $SNAPSHOT_PATH"
echo  "-------------------------------------"
echo  "SIZE:"
du -sh "$SNAPSHOT_PATH"
echo  "-------------------------------------"