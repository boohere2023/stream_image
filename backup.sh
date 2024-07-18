#!/bin/bash

# Load environment variables from the .env file
ENV_FILE="./stream_image/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env file not found at $ENV_FILE"
  exit 1
fi
source "$ENV_FILE"

# Variables
VOLUMES=("$WEBSITE_LOG" "$WEBSITE_VHOST" "$WEBSITE_MYSQL" "$WEBSITE_DATA")
HOSTNAME=$(hostname)
DATE=$(date +%Y%m%d)
BACKUP_DIR="./stream_image/backup" # Replace with your backup directory
BUCKET_NAME="stream-data" # Replace with your UpCloud Object Storage bucket name

# Create a backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

for VOLUME in "${VOLUMES[@]}"; do
  BACKUP_NAME="backup_${DATE}_${HOSTNAME}_$(basename $VOLUME).tar.gz"

  # Check if the volume is set
  if [ -z "$VOLUME" ]; then
    echo "Error: Volume name is empty"
    continue
  fi

  # Backup the Docker volume
  docker run --rm -v "$VOLUME":/volume -v "$BACKUP_DIR":/backup alpine \
    sh -c "tar czf /backup/$BACKUP_NAME -C /volume ."

  # Upload the backup to UpCloud Object Storage
  s3cmd put "$BACKUP_DIR/$BACKUP_NAME" s3://"$BUCKET_NAME"/"$BACKUP_NAME"
done
