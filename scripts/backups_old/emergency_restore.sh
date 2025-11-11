#!/bin/bash

#-----------------EMERGENCY-RESTORATION-SCRIPT----------
# This script will be automatically executed to check
# network connectivity and restore it if necessary

# -e: Exit if any command has a non-zero exit status
# -u: All variables have to be defined (otherwise an error is thrown)
# -o pipefail: If any command in the pipeline fails, return it's exit code
set -euo pipefail

# TICK: Used as a timer to make the script run automatically
TICK_FILE="/var/run/system_snapshot.tick"
MAX_FAILED_TICKS=2        # Restore after MAX_FAILED consecutive ticks


BACKUP_FOLDER="/mnt/backups"

LOG_FILE="/var/log/emergency-restore.log"

log_emergency() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] EMERGENCY: $@" >> "$RESTORE_LOG"

    # Log using systemd journal
    logger -t emergency-restore -p user.crit "$@"
}

emergency_restore() {
    log_emergency "INICIANDO RESTAURACIÓN DE EMERGENCIA"
    
    # Encontrar el snapshot más reciente
    # Mismo patrón que en restore_from_snapshot.sh
    log_emergency "Restaurando desde: $(ls -tr $BACKUP_ROOT/pre_docker_snapshot_* 2>/dev/null | tail -1)"
    
    # Ejecutar el script de restauración
    # < <(echo "SI"): proporcionar automáticamente "SI" como entrada (simula confirmación)
    # >>: append al archivo de log
    bash /usr/local/bin/restore_from_snapshot.sh < <(echo "SI") >> "$RESTORE_LOG" 2>&1
}