#!/bin/bash
set -euo pipefail

echo "Testing log_utils.sh sourcing..."
echo "Bash version: $BASH_VERSION"

export DISABLE_AUTO_LOG_INIT=true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_UTILS_PATH="${SCRIPT_DIR}/../log_utils.sh"

echo "Checking if file exists: $LOG_UTILS_PATH"
ls -la "$LOG_UTILS_PATH"

echo "Testing syntax..."
bash -n "$LOG_UTILS_PATH"

echo "Attempting to source..."
source "$LOG_UTILS_PATH"

echo "Success! log_utils.sh sourced without errors."
