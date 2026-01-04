#!/bin/bash

# 1. Check if the required argument is provided (the log directory)
if [ -z "$1" ]; then
  echo "Usage: $0 <directory_path>"
  exit 1
fi

# Set variables
LOG_DIR="$1"
ARCHIVE_FILE="archived_logs_$(date +%Y%m%d).tar.gz"

echo "Searching for logs in $LOG_DIR older than 30 days..."

# 2. Use find to locate files and xargs/tar to archive them directly
# -print0 and xargs -0 handle filenames with spaces or special characters safely.
find "$LOG_DIR" -type f -mtime +30 -print0 | xargs -0 tar -czvf "$ARCHIVE_FILE" 2>&1

# 3. Check the exit status for error handling
if [ $? -eq 0 ]; then
  echo "Success: Archive created at $ARCHIVE_FILE"
else
  echo "Failure: Error occurred during archiving." >&2
  exit 1
fi
