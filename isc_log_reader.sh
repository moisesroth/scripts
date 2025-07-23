#!/bin/bash

# Check if a file path was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <log_file>"
  exit 1
fi

LOG_FILE="$1"

# Check for jq and date
if ! command -v jq > /dev/null; then
  echo "Error: 'jq' is required but not installed."
  exit 1
fi

# Get current UTC time in epoch seconds
NOW_EPOCH=$(date -u +%s)

# Read and parse each line
while IFS= read -r line; do
  RAW_TIMESTAMP=$(echo "$line" | jq -r '."@timestamp"' 2> /dev/null)
  LEVEL=$(echo "$line" | jq -r '.level // "UNKNOWN"' 2> /dev/null)
  MESSAGE=$(echo "$line" | jq -r '.message // "NO MESSAGE"' 2> /dev/null)

  if [[ -z "$RAW_TIMESTAMP" ]]; then
    continue
  fi

  # Format readable timestamp
  FORMATTED_TIMESTAMP=$(date -u -d "$RAW_TIMESTAMP" +"%Y-%m-%d %H:%M:%S,%3N" 2> /dev/null)
  LOG_EPOCH=$(date -u -d "$RAW_TIMESTAMP" +%s 2> /dev/null)

  if [[ -n "$LOG_EPOCH" ]]; then
    DIFF_SEC=$((NOW_EPOCH - LOG_EPOCH))

    DAYS=$((DIFF_SEC / 86400))
    HOURS=$(( (DIFF_SEC % 86400) / 3600 ))
    MINUTES=$(( (DIFF_SEC % 3600) / 60 ))
    SECONDS=$((DIFF_SEC % 60))

    TIME_AGO=$(printf "+%02dd %02dh %02dm %02ds" "$DAYS" "$HOURS" "$MINUTES" "$SECONDS")
  else
    TIME_AGO="+??d ??h ??m ??s"
  fi

  LEVEL_UPPER=$(echo "$LEVEL" | tr '[:lower:]' '[:upper:]')

  # Final output
  printf "[%s] [%s] [%-5s] %s\n" "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "$MESSAGE"

done < "$LOG_FILE"
