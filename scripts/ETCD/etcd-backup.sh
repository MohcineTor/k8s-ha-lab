#!/bin/bash
set -Eeuo pipefail

# 1. Activation des alias pour ce script
shopt -s expand_aliases
source "$HOME/alias.sh"

# Configuration
BACKUP_DIR="/var/backups/etcd"
RECIPIENT_FILE="/etc/etcd-backup-recipient.txt"
S3_ENV="/etc/etcd-backup-s3.env"
S3_ENDPOINT="http://192.168.56.40:8333"
S3_BUCKET="etcd-backups"

# Préparation
umask 077
mkdir -p "$BACKUP_DIR"

source "$S3_ENV"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT="$BACKUP_DIR/etcd-${TIMESTAMP}.db"
ENCRYPTED="${SNAPSHOT}.age"

echo "[$(date)] Début de la sauvegarde etcd"

# 2. Création du snapshot via mon alias !
etcdctl-k8s snapshot save "$SNAPSHOT"

# Vérification du snapshot (ajout de sudo car le fichier appartient à root)
sudo /usr/local/bin/etcdutl snapshot status "$SNAPSHOT" --write-out=table

# Chiffrement (ajout de sudo pour lire le fichier original)
sudo age -R "$RECIPIENT_FILE" -o "$ENCRYPTED" "$SNAPSHOT"
sudo chmod 600 "$SNAPSHOT" "$ENCRYPTED"

# Envoi vers SeaweedFS
aws --no-cli-pager --endpoint-url "$S3_ENDPOINT" \
  s3 cp "$ENCRYPTED" "s3://${S3_BUCKET}/$(basename "$ENCRYPTED")"

# Vérification de la présence distante
aws --no-cli-pager --endpoint-url "$S3_ENDPOINT" \
  s3api head-object \
  --bucket "$S3_BUCKET" \
  --key "$(basename "$ENCRYPTED")" >/dev/null

# Nettoyage : conserver 7 jours de fichiers locaux (ajout de sudo)
sudo find "$BACKUP_DIR" -type f -name 'etcd-*.db' -mtime +7 -delete
sudo find "$BACKUP_DIR" -type f -name 'etcd-*.db.age' -mtime +7 -delete

echo "[$(date)] Sauvegarde terminée avec succès : $(basename "$ENCRYPTED")"