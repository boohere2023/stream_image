#!/bin/bash

# Load environment variables from .env file
set -o allexport
source /root/stream_image/.env
set -o allexport

# Current date
CURRENT_DATE=$(date +"%Y%m%d")

# Hostname
HOSTNAME=$(hostname)

# Restore Docker image from Docker Hub
DOCKER_IMAGE="sclbo/$HOSTNAME:$CURRENT_DATE"
docker pull "$DOCKER_IMAGE"

# Remove existing container if it exists
if [ "$(docker ps -aq -f name=aapanel)" ]; then
  docker rm -f aapanel
fi

# Run the restored Docker image
docker run -d --name aapanel \
  -p "${AAPANEL_PORT}:7800" \
  -p "${WEBSERVER_HOST_PORT}:80" \
  -p "${WEBSERVER_SECURE_HOST_PORT}:443" \
  -p "${PHPMYADMIN_PORT}:888" \
  -p "${REDIS_PORT}:6379" \
  -p "${MYSQL_PORT}:3306" \
  -v "${WEBSITE_LOG}:/www/wwwlogs" \
  -v "${WEBSITE_VHOST}:/www/server/panel/vhost" \
  -v "${WEBSITE_CRON}:/www/server/cron" \
  -v "${WEBSITE_DATA}:/www/wwwroot" \
  -e TZ=Asia/Singapore \
  "$DOCKER_IMAGE"

# Volumes to restore
VOLUMES=(
  "${WEBSITE_LOG}:/www/wwwlogs"
  "${WEBSITE_VHOST}:/www/server/panel/vhost"
  "${WEBSITE_CRON}:/www/server/cron"
  "${WEBSITE_DATA}:/www/wwwroot"
)

# Backup directory
BACKUP_DIR="/root/stream_image/backup"
mkdir -p "${BACKUP_DIR}"

# Get aapanel container ID
AAPANEL_CONTAINER=$(docker container ls | grep 'aapanel' | awk '{print $1}')

# Loop through each volume
for VOLUME in "${VOLUMES[@]}"; do
  # Extract volume name and path
  VOLUME_NAME=$(basename "${VOLUME%%:*}")
  VOLUME_PATH="${VOLUME##*:}"

  # Create backup file name
  BACKUP_FILE="${BACKUP_DIR}/backup_${CURRENT_DATE}_${HOSTNAME}_${VOLUME_NAME}.tar.gz"

  # Download backup file from S3
  s3cmd get "s3://stream_img01/backup_${CURRENT_DATE}_${HOSTNAME}_${VOLUME_NAME}.tar.gz" "${BACKUP_FILE}" || {
    echo "Failed to download ${BACKUP_FILE} from S3. Skipping volume restore."
    continue
  }

  # Check if the backup file exists
  if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Backup file ${BACKUP_FILE} does not exist. Skipping volume restore."
    continue
  fi
   # Restore from the tar.gz file
  docker run --rm \
    -v "${VOLUME%%:*}:${VOLUME_PATH}" \
    -v "${BACKUP_DIR}:/backup" \
    alpine sh -c "tar -xzf /backup/$(basename ${BACKUP_FILE}) -C ${VOLUME_PATH}" || {
    echo "Failed to restore volume ${VOLUME_NAME} from ${BACKUP_FILE}."
  }

  # Clean up the downloaded backup file
  rm "${BACKUP_FILE}"
done

# Restore MySQL database
MYSQL_BACKUP_NAME="backup_${CURRENT_DATE}_${HOSTNAME}_mysql.sql.gz"
MYSQL_BACKUP_FILE="${BACKUP_DIR}/${MYSQL_BACKUP_NAME}"
echo "Restoring MySQL database"

# Download the MySQL backup file from S3
s3cmd get "s3://stream_img01/${MYSQL_BACKUP_NAME}" "${MYSQL_BACKUP_FILE}" || {
  echo "Failed to download ${MYSQL_BACKUP_FILE} from S3. Skipping MySQL restore."
  exit 1
}

# Check if the MySQL backup file exists
if [ ! -f "${MYSQL_BACKUP_FILE}" ]; then
  echo "MySQL backup file ${MYSQL_BACKUP_FILE} does not exist. Skipping MySQL restore."
  exit 1
fi

# Restore the MySQL database
gunzip < "${MYSQL_BACKUP_FILE}" | docker exec -i "${MYSQL_CONTAINER}" mysql -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" || {
  echo "Failed to restore MySQL database from ${MYSQL_BACKUP_FILE}."
}

# Clean up the downloaded MySQL backup file
rm "${MYSQL_BACKUP_FILE}"

# Restart MySQL, Redis, and Nginx services inside the aapanel container
docker exec $AAPANEL_CONTAINER bash /etc/init.d/mysqld restart
docker exec $AAPANEL_CONTAINER bash /etc/init.d/redis restart
docker exec $AAPANEL_CONTAINER bash /etc/init.d/nginx restart


