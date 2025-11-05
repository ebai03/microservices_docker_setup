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

# Creates a backup of most system directories, excluding some
# that were deemed as not necessary to backup.
# Ref: https://serverfault.com/questions/74696/linux-what-directories-should-i-exclude-when-backing-up-a-server
create_backup() {
    log_info "Creating snapshot..."

    mkdir -p "$SNAPSHOT_PATH"

    local exclude_dirs=(
        '--exclude=/proc/*'
        '--exclude=/sys/*'
        '--exclude=/dev/*'
        '--exclude=/run/*'
        '--exclude=/tmp/*'
        '--exclude=/mnt/backups/*'
        '--exclude=/media/*'
        '--exclude=/lost+found'
        '--exclude=/var/log/*'
        '--exclude=/var/cache/*'
        '--exclude=/var/tmp/*'
        '--exclude=.snapshots'
        '--exclude=$RECYCLE.BIN'
    )

    log_info "Generating backup, standby..."

    # Creates the backup and logs any errors
    # ---------------------------------------------
    # 2>&1 replaces fd 2 (stderr) with fd 1 (stdout)
    # https://blog.tratif.com/2023/01/09/bash-tips-1-logging-in-shell-scripts/
    if sudo tar -czf "$SNAPSHOT_PATH/system_backup.tar.gz" \
        "${exclude_dirs[@]}" \
        -C / . 2>&1 | grep -v "tar:Removing" | tee -a "$LOG_FILE"; then
        log_success "Finished backing up"
    else
        log_error "Error while generating backup"
        return 1
    fi

}