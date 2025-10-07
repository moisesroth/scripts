#!/bin/bash

# usage:
#   save this script on /home/sailpoint/log/
#   cd /home/sailpoint/log/ && tail -n20 ccg.log > temp.log && ./isc_log_reader_v2.sh temp.log
#   similar to -f (but lose the purpose of the relative time feature)
#     cd /home/sailpoint/log && tail -F ccg.log | stdbuf -oL -eL ./isc_log_reader_v2.sh /dev/stdin
#     cd /home/sailpoint/log && ./isc_log_reader_v2.sh <(tail -F ccg.log)

#
# extras:
#   PRINT_STACK=all   -> print full stacktrace
#   PRINT_STACK=1     -> print only the 1st line (default)
#   PRINT_STACK=0     -> do not print stacktrace

set -euo pipefail

# ---- Config ----
PRINT_STACK_DEFAULT="${PRINT_STACK:-1}"   # 0 | 1 | all

# ---- Args / deps ----
if [ -z "${1:-}" ]; then
  echo "Usage: $0 <log_file>"
  exit 1
fi
LOG_FILE="$1"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: 'jq' is required but not installed."
  exit 1
fi

# ---- Helpers ----
print_block() {
  # $1 = formatted timestamp
  # $2 = time_ago
  # $3 = LEVEL (already uppercase)
  # $4 = possibly multi-line text
  local _ts="$1" _ago="$2" _lvl="$3" _text="$4"
  # print line by line, preserving prefix
  while IFS= read -r _line; do
    printf "[%s] [%s] [%-5s] %s\n" "$_ts" "$_ago" "$_lvl" "$_line"
  done <<< "$_text"
}

# ---- Now (UTC) ----
NOW_EPOCH=$(date -u +%s)

# ---- Loop ----
while IFS= read -r line; do
  # Skip lines that are not JSON
  if ! echo "$line" | jq -e . >/dev/null 2>&1; then
    continue
  fi

  RAW_TIMESTAMP=$(echo "$line" | jq -r '."@timestamp" // empty')
  [ -z "$RAW_TIMESTAMP" ] && continue

  LEVEL=$(echo "$line" | jq -r '.level // "UNKNOWN"' 2>/dev/null)
  LEVEL_UPPER=$(echo "$LEVEL" | tr '[:lower:]' '[:upper:]')

  MESSAGE=$(echo "$line" | jq -r '.message // "NO MESSAGE"' 2>/dev/null)

  # readable timestamp and "time ago"
  FORMATTED_TIMESTAMP=$(date -u -d "$RAW_TIMESTAMP" +"%Y-%m-%d %H:%M:%S,%3N" 2>/dev/null || echo "$RAW_TIMESTAMP")
  LOG_EPOCH=$(date -u -d "$RAW_TIMESTAMP" +%s 2>/dev/null || echo "")
  if [[ -n "$LOG_EPOCH" && "$LOG_EPOCH" =~ ^[0-9]+$ ]]; then
    DIFF_SEC=$((NOW_EPOCH - LOG_EPOCH))
    DAYS=$(( DIFF_SEC / 86400 ))
    HOURS=$(( (DIFF_SEC % 86400) / 3600 ))
    MINUTES=$(( (DIFF_SEC % 3600) / 60 ))
    SECONDS=$(( DIFF_SEC % 60 ))
    TIME_AGO=$(printf "+%02dd %02dh %02dm %02ds" "$DAYS" "$HOURS" "$MINUTES" "$SECONDS")
  else
    TIME_AGO="+??d ??h ??m ??s"
  fi

  # print the main message (with prefix on all lines)
  print_block "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "$MESSAGE"

  # ---- Exception (when exists) ----
  HAS_EXCEPTION=$(echo "$line" | jq -e 'has("exception") and (.exception != null)' >/dev/null 2>&1 && echo 1 || echo 0)
  if [ "$HAS_EXCEPTION" -eq 1 ]; then
    EXC_CLASS=$(echo "$line" | jq -r '.exception.exception_class // .exception.class // empty')
    EXC_MSG=$(echo "$line"   | jq -r '.exception.exception_message // .exception.message // empty')
    EXC_STACK=$(echo "$line" | jq -r '.exception.stacktrace // empty')

    # build a friendly line for the exception
    if [ -n "$EXC_CLASS" ] && [ -n "$EXC_MSG" ]; then
      print_block "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "Exception ($EXC_CLASS): $EXC_MSG"
    elif [ -n "$EXC_MSG" ]; then
      print_block "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "Exception: $EXC_MSG"
    elif [ -n "$EXC_CLASS" ]; then
      print_block "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "Exception ($EXC_CLASS)"
    else
      # fallback: print the entire exception object (compact)
      EXC_RAW=$(echo "$line" | jq -c '.exception' 2>/dev/null)
      [ -n "$EXC_RAW" ] && print_block "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "Exception: $EXC_RAW"
    fi

    # stacktrace: 1st line by default; full if PRINT_STACK=all; none if PRINT_STACK=0
    if [ -n "$EXC_STACK" ]; then
      case "$PRINT_STACK_DEFAULT" in
        all)
          print_block "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "$EXC_STACK"
          ;;
        1)
          print_block "$FORMATTED_TIMESTAMP" "$TIME_AGO" "$LEVEL_UPPER" "$(echo "$EXC_STACK" | head -n 1)"
          ;;
        0|*)
          : # do not print
          ;;
      esac
    fi
  fi

done < "$LOG_FILE"
