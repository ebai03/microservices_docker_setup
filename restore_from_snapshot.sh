#!/bin/bash

#---------------RESTORE-FROM-SNAPSHOT-SCRIPT--------------------
# Restores a bunch of files and folders from a previously generated
# snapshot. The snapshot path must be provided


# -e: Exit if any command has a non-zero exit status
# -u: All variables have to be defined (otherwise an error is thrown)
# -o pipefail: If any command in the pipeline fails, return it's exit code
set -euo pipefail

BACKUP_FOLDER="/mnt/backups"

SNAPSHOT_PATH="$1"

LOG_FILE="/var/log/restore_snapshot.log"

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

    # Verificar que existe directorio
    if [[ -z $1 ]]; then
        log_error "Snapshot not found"
        exit 1
    fi
}

log_info "Using snapshot: $SNAPSHOT_PATH"

log_warning "All changes done after the snapshot was taken will be reverted"

echo ""
read -p "Continue with restoration? (Write Y to confirm): " confirm

if [[ "$confirm" != "Y" ]] then
    log_info "Retoration cancelled"
    exit 0
fi

# Restore the system from the tarball

