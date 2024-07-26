#!/bin/bash

# Load environment variables from .env file
set -o allexport
source /root/stream_image/.env
set -o allexport

# Current date
CURRENT_DATE=$(date +"%Y%m%d")

# Hostname
HOSTNAME=$(hostname)

# Volumes to back up
VOLUMES=(
  "${WEBSITE_LOG}:/www/wwwlogs"
  "${WEBSITE_VHOST}:/www/server/panel/vhost"
  "${WEBSITE_CRON}:/www/server/cron"
  "${WEBSITE_DATA}:/www/wwwroot"
)

# Backup directory
BACKUP_DIR="/root/stream_image/backup"
mkdir -p "${BACKUP_DIR}"

# Loop through each volume
for VOLUME in "${VOLUMES[@]}"; do
  # Extract volume name and path
  VOLUME_NAME=$(basename "${VOLUME%%:*}")
  VOLUME_PATH="${VOLUME##*:}"

  # Create backup file name
  BACKUP_FILE="${BACKUP_DIR}/backup_${CURRENT_DATE}_${HOSTNAME}_${VOLUME_NAME}.tar.gz"

  # Perform the backup
  docker run --rm \
    -v "${VOLUME%%:*}:${VOLUME_PATH}" \
    -v "${BACKUP_DIR}:/backup" \
    alpine sh -c "cd ${VOLUME_PATH} && tar -czf /backup/backup_${CURRENT_DATE}_${HOSTNAME}_${VOLUME_NAME}.tar.gz ."

  # Upload to S3
  aws s3 cp "${BACKUP_FILE}" "s3://stream_img01/backup_${CURRENT_DATE}_${HOSTNAME}_${VOLUME_NAME}.tar.gz" --profile=backup
done

# Backup MySQL database
MYSQL_BACKUP_NAME="backup_${CURRENT_DATE}_${HOSTNAME}_mysql.sql.gz"
docker exec $MYSQL_CONTAINER mysqldump -u $MYSQL_USER -p"$MYSQL_PASSWORD" --all-databases | gzip > "$BACKUP_DIR/$MYSQL_BACKUP_NAME"
aws s3 cp "$BACKUP_DIR/$MYSQL_BACKUP_NAME" s3://"$BUCKET_NAME"/"$MYSQL_BACKUP_NAME" --profile=backup
