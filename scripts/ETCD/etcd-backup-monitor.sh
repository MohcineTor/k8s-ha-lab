#!/bin/bash
set -u

BACKUP_SCRIPT="/usr/local/bin/etcd-backup.sh"
STATE_DIR="/var/lib/etcd-backup-monitor"
STATE_FILE="${STATE_DIR}/state"
METRICS_DIR="/var/lib/prometheus/node-exporter"
METRICS_FILE="${METRICS_DIR}/etcd_backup.prom"

umask 077
mkdir -p "$STATE_DIR"

START=$(date +%s)
ATTEMPT=$(date +%s)

LAST_SUCCESS=0

if [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE"
fi

STATUS=0
UPLOAD_STATUS=0

echo "Début de la tentative de sauvegarde etcd"

if "$BACKUP_SCRIPT"; then
    STATUS=1
    UPLOAD_STATUS=1
    LAST_SUCCESS=$(date +%s)
    echo "Sauvegarde réussie"
else
    echo "ÉCHEC de la sauvegarde etcd"
fi

END=$(date +%s)
DURATION=$((END - START))

TMP_STATE=$(mktemp "${STATE_DIR}/state.XXXXXX")

cat > "$TMP_STATE" <<EOF
LAST_SUCCESS=$LAST_SUCCESS
LAST_ATTEMPT=$ATTEMPT
LAST_STATUS=$STATUS
LAST_UPLOAD_STATUS=$UPLOAD_STATUS
LAST_DURATION=$DURATION
EOF

chmod 600 "$TMP_STATE"
mv "$TMP_STATE" "$STATE_FILE"

TMP_METRICS=$(mktemp "${METRICS_DIR}/etcd_backup.XXXXXX")

cat > "$TMP_METRICS" <<EOF
# HELP etcd_backup_last_status Status of the latest etcd backup attempt
# TYPE etcd_backup_last_status gauge
etcd_backup_last_status $STATUS
# HELP etcd_backup_last_success_timestamp Unix timestamp of the last successful backup
# TYPE etcd_backup_last_success_timestamp gauge
etcd_backup_last_success_timestamp $LAST_SUCCESS
# HELP etcd_backup_last_attempt_timestamp Unix timestamp of the last backup attempt
# TYPE etcd_backup_last_attempt_timestamp gauge
etcd_backup_last_attempt_timestamp $ATTEMPT
# HELP etcd_backup_duration_seconds Duration of the latest backup attempt
# TYPE etcd_backup_duration_seconds gauge
etcd_backup_duration_seconds $DURATION
# HELP etcd_backup_upload_status Status of the latest backup upload
# TYPE etcd_backup_upload_status gauge
etcd_backup_upload_status $UPLOAD_STATUS
EOF

chmod 644 "$TMP_METRICS"
mv "$TMP_METRICS" "$METRICS_FILE"

exit "$((1 - STATUS))"