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

# Log functions
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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
}