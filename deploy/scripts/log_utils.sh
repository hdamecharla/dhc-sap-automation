#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

################################################################################
# log_utils.sh - Comprehensive Logging Infrastructure for SAP Automation
#
# This script provides standardized logging capabilities across the SAP automation
# deployment framework. It supports multiple log levels, both console and file
# output, and maintains proper log directory structure.
#
# Dependencies: None (foundation layer)
# Author: SAP Automation Team
# Version: 2.0 (Refactored)
################################################################################

# Prevent multiple sourcing of this library
if [[ ${__LOG_UTILS_SOURCED:-} == "true" ]]; then
    return 0
fi
readonly __LOG_UTILS_SOURCED="true"

################################################################################
# CONSTANTS AND GLOBAL VARIABLES
################################################################################

# Log level definitions (numeric values for comparison)
declare -gA LOG_LEVELS=(
    [CRITICAL]=0
    [ERROR]=1
    [WARN]=2
    [INFO]=3
    [DEBUG]=4
    [VERBOSE]=5
)

# Default log level mappings for different loggers
declare -gA LOG_LEVEL_MAPPER

# Console color definitions (only set if terminal supports colors)
declare -g COLOR_NORMAL=""
declare -g COLOR_RED=""
declare -g COLOR_GREEN=""
declare -g COLOR_YELLOW=""
declare -g COLOR_MAGENTA=""
declare -g COLOR_CYAN=""
declare -g COLOR_WHITE=""

# Global logging configuration
declare -g LOG_CONFIG_INITIALIZED="false"
declare -g LOG_BASE_DIR=""
declare -g LOG_CONSOLE_ENABLED="true"
declare -g LOG_FILE_ENABLED="true"
declare -g LOG_TIMESTAMP_FORMAT="%Y-%m-%d:%H:%M:%S"
declare -g LOG_DEFAULT_LEVEL="INFO"

################################################################################
# INITIALIZATION FUNCTIONS
################################################################################

################################################################################
# Initialize the logging system with configuration and directory structure
# Arguments:
#   $1: Base log directory (optional, defaults to CONFIG_REPO_PATH/.sap_deployment_automation/logs)
#   $2: Default log level (optional, defaults to INFO)
# Returns:
#   0: Success
#   1: Configuration error
# Usage:
#   init_logging [base_dir] [default_level]
# Example:
#   init_logging "/opt/sap/logs" "DEBUG"
################################################################################
# shellcheck disable=SC2120
function init_logging() {
    local base_dir="${1:-}"
    local default_level="${2:-INFO}"

    # Allow re-initialization if base directory changes (for testing)
    # or if forcing re-initialization
    if [[ "${LOG_CONFIG_INITIALIZED}" == "true" ]]; then
        if [[ -n "$base_dir" && "$base_dir" != "$LOG_BASE_DIR" ]]; then
            # Different directory requested - allow re-initialization
            LOG_CONFIG_INITIALIZED="false"
        elif [[ "${FORCE_LOG_REINIT:-false}" == "true" ]]; then
            # Force flag set - allow re-initialization
            LOG_CONFIG_INITIALIZED="false"
        else
            # Same configuration - skip re-initialization
            return 0
        fi
    fi

    # Set default base directory if not provided
    if [[ -z "${base_dir}" ]]; then
        if [[ -n "${CONFIG_REPO_PATH:-}" ]]; then
            base_dir="${CONFIG_REPO_PATH}/.sap_deployment_automation/logs"
        else
            base_dir="/tmp/sap_automation_logs"
        fi
    fi

    # Validate and set default log level
    if [[ -z "${LOG_LEVELS[$default_level]:-}" ]]; then
        echo "WARNING: Invalid log level '$default_level', using INFO" >&2
        default_level="INFO"
    fi

    LOG_BASE_DIR="${base_dir}"
    LOG_DEFAULT_LEVEL="${default_level}"

    # Initialize colors if terminal supports them
    _init_colors

    # Create log directory structure
    if ! _create_log_directories; then
        echo "ERROR: Failed to create log directory structure" >&2
        return 1
    fi

    # Set default logger
    LOG_LEVEL_MAPPER["default"]="${LOG_LEVELS[$default_level]}"

    LOG_CONFIG_INITIALIZED="true"

    log_info "Logging system initialized successfully"
    log_info "Log base directory: ${LOG_BASE_DIR}"
    log_info "Default log level: ${LOG_DEFAULT_LEVEL}"

    return 0
}

################################################################################
# Initialize console colors based on terminal capabilities
# Arguments: None
# Returns: None (always succeeds)
# Usage: _init_colors (internal function)
################################################################################
function _init_colors() {
    # Only initialize colors if not already set as readonly
    if [[ -z "${COLOR_NORMAL:-}" ]]; then
        if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
            local colors
            colors=$(tput colors 2>/dev/null || echo 0)

            if [[ ${colors} -ge 8 ]]; then
                COLOR_NORMAL="\033[0m"
                COLOR_RED="\033[0;31m"
                COLOR_GREEN="\033[0;32m"
                COLOR_YELLOW="\033[0;33m"
                COLOR_MAGENTA="\033[0;35m"
                COLOR_CYAN="\033[0;36m"
                COLOR_WHITE="\033[0;37m"
            fi
        fi

        readonly COLOR_NORMAL COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_MAGENTA COLOR_CYAN COLOR_WHITE
    fi
}

################################################################################
# Create standardized log directory structure
# Arguments: None
# Returns:
#   0: Success
#   1: Directory creation failed
# Usage: _create_log_directories (internal function)
################################################################################
function _create_log_directories() {
    local dirs=(
        "${LOG_BASE_DIR}"
        "${LOG_BASE_DIR}/daily"
        "${LOG_BASE_DIR}/scripts"
        "${LOG_BASE_DIR}/archive"
    )

    for dir in "${dirs[@]}"; do
        if ! mkdir -p "${dir}" 2>/dev/null; then
            echo "ERROR: Failed to create directory: ${dir}" >&2
            return 1
        fi
    done

    return 0
}

################################################################################
# CONFIGURATION FUNCTIONS
################################################################################

################################################################################
# Set log level for a specific logger
# Arguments:
#   $1: Logger name (or "default" for global default)
#   $2: Log level (CRITICAL, ERROR, WARN, INFO, DEBUG, VERBOSE)
# Returns:
#   0: Success
#   1: Invalid log level
# Usage:
#   set_log_level "logger_name" "DEBUG"
# Example:
#   set_log_level "terraform" "VERBOSE"
################################################################################
function set_log_level() {
    local logger="${1:-default}"
    local level="${2:-}"

    if [[ -z "${level}" ]]; then
        echo "ERROR: Log level is required" >&2
        return 1
    fi

    if [[ -z "${LOG_LEVELS[$level]:-}" ]]; then
        echo "ERROR: Invalid log level '$level'. Valid levels: ${!LOG_LEVELS[*]}" >&2
        return 1
    fi

    LOG_LEVEL_MAPPER["$logger"]="${LOG_LEVELS[$level]}"

    return 0
}

################################################################################
# Enable or disable console logging
# Arguments:
#   $1: "true" to enable, "false" to disable
# Returns: None
# Usage:
#   set_console_logging "false"
################################################################################
function set_console_logging() {
    local enabled="${1:-true}"
    LOG_CONSOLE_ENABLED="${enabled}"
}

################################################################################
# Enable or disable file logging
# Arguments:
#   $1: "true" to enable, "false" to disable
# Returns: None
# Usage:
#   set_file_logging "false"
################################################################################
function set_file_logging() {
    local enabled="${1:-true}"
    LOG_FILE_ENABLED="${enabled}"
}

################################################################################
# CORE LOGGING FUNCTIONS
################################################################################

################################################################################
# Core logging function that handles both console and file output
# Arguments:
#   $1: Log level
#   $2: Logger name (optional, defaults to "default")
#   $3+: Log message components
# Returns:
#   0: Success
#   1: Invalid log level
# Usage:
#   _log "INFO" "default" "This is a log message"
# Note: This is an internal function, use the public log_* functions instead
################################################################################
function _log() {
    local level="$1"
    local logger="default"
    shift

    # Check if second argument is a logger name (starts with -l)
    if [[ "$1" == "-l" ]] && [[ -n "$2" ]]; then
        logger="$2"
        shift 2
    fi

    # Initialize logging if not already done
    if [[ "${LOG_CONFIG_INITIALIZED}" != "true" ]]; then
        init_logging
    fi

    # Validate log level
    local level_value="${LOG_LEVELS[$level]:-}"
    if [[ -z "${level_value}" ]]; then
        echo "ERROR: Invalid log level '$level'" >&2
        return 1
    fi

    # Check if this message should be logged for this logger
    local logger_level="${LOG_LEVEL_MAPPER[$logger]:-${LOG_LEVEL_MAPPER[default]}}"
    if [[ ${logger_level} -lt ${level_value} ]]; then
        return 0  # Message filtered out
    fi

    # Build log message components
    local timestamp
    timestamp=$(date +"${LOG_TIMESTAMP_FORMAT}")

    local caller_info
    caller_info=$(printf "+%s@%d:%s:" \
        "${BASH_SOURCE[3]##*/}" \
        "${BASH_LINENO[2]}" \
        "${FUNCNAME[3]:-main}")

    local log_message="$*"
    local formatted_message
    formatted_message=$(printf '%s %-7s %s %s' \
        "$timestamp" \
        "$level" \
        "$caller_info" \
        "$log_message")

    # Output to console if enabled
    if [[ "${LOG_CONSOLE_ENABLED}" == "true" ]]; then
        _log_to_console "$level" "$formatted_message"
    fi

    # Output to file if enabled
    if [[ "${LOG_FILE_ENABLED}" == "true" ]]; then
        _log_to_file "$level" "$logger" "$formatted_message"
    fi

    return 0
}

################################################################################
# Output log message to console with appropriate coloring
# Arguments:
#   $1: Log level
#   $2: Formatted log message
# Returns: None
# Usage: _log_to_console "ERROR" "formatted message" (internal function)
################################################################################
function _log_to_console() {
    local level="$1"
    local message="$2"
    local color=""

    case "$level" in
        CRITICAL|ERROR)
            color="${COLOR_RED}"
            ;;
        WARN)
            color="${COLOR_YELLOW}"
            ;;
        INFO)
            color="${COLOR_CYAN}"
            ;;
        DEBUG)
            color="${COLOR_MAGENTA}"
            ;;
        VERBOSE)
            color="${COLOR_WHITE}"
            ;;
    esac

    if [[ "${level}" == "CRITICAL" || "${level}" == "ERROR" ]]; then
        echo -e "${color}${message}${COLOR_NORMAL}" >&2
    else
        echo -e "${color}${message}${COLOR_NORMAL}"
    fi
}

################################################################################
# Output log message to appropriate log file
# Arguments:
#   $1: Log level
#   $2: Logger name
#   $3: Formatted log message
# Returns:
#   0: Success
#   1: File write error
# Usage: _log_to_file "INFO" "default" "formatted message" (internal function)
################################################################################
function _log_to_file() {
    local level="$1"
    local logger="$2"
    local message="$3"

    # Determine log file path
    local log_file
    log_file=$(_get_log_file_path "$level" "$logger")

    # Ensure log file directory exists
    local log_dir
    log_dir=$(dirname "$log_file")
    if ! mkdir -p "$log_dir" 2>/dev/null; then
        echo "ERROR: Cannot create log directory: $log_dir" >&2
        return 1
    fi

    # Write to log file
    if ! echo "$message" >> "$log_file" 2>/dev/null; then
        echo "ERROR: Cannot write to log file: $log_file" >&2
        return 1
    fi

    return 0
}

################################################################################
# Determine the appropriate log file path for a message
# Arguments:
#   $1: Log level
#   $2: Logger name
# Returns: Outputs log file path to stdout
# Usage: log_file=$(_get_log_file_path "INFO" "default")
################################################################################
function _get_log_file_path() {
    local level="$1"
    local logger="$2"
    local date_str
    date_str=$(date +"%Y%m%d")

    local script_name="${BASH_SOURCE[4]##*/}"
    script_name="${script_name%.sh}"

    # Create hierarchical log file structure
    if [[ "${logger}" == "default" ]]; then
        echo "${LOG_BASE_DIR}/daily/${script_name}_${date_str}.log"
    else
        echo "${LOG_BASE_DIR}/scripts/${logger}/${script_name}_${date_str}.log"
    fi
}

################################################################################
# PUBLIC LOGGING INTERFACE FUNCTIONS
################################################################################

################################################################################
# Log a critical message (highest priority)
# Arguments:
#   [-l logger_name]: Optional logger name
#   $*: Log message components
# Returns: Result of _log function
# Usage:
#   log_critical "System is in critical state"
#   log_critical -l "terraform" "Critical terraform error"
################################################################################
function log_critical() {
    _log "CRITICAL" "$@"
}

################################################################################
# Log an error message
# Arguments:
#   [-l logger_name]: Optional logger name
#   $*: Log message components
# Returns: Result of _log function
# Usage:
#   log_error "Operation failed"
#   log_error -l "azure" "Azure CLI command failed"
################################################################################
function log_error() {
    _log "ERROR" "$@"
}

################################################################################
# Log a warning message
# Arguments:
#   [-l logger_name]: Optional logger name
#   $*: Log message components
# Returns: Result of _log function
# Usage:
#   log_warn "Deprecated function used"
#   log_warn -l "validation" "Parameter validation warning"
################################################################################
function log_warn() {
    _log "WARN" "$@"
}

################################################################################
# Log an informational message
# Arguments:
#   [-l logger_name]: Optional logger name
#   $*: Log message components
# Returns: Result of _log function
# Usage:
#   log_info "Operation completed successfully"
#   log_info -l "deployment" "Deployment phase started"
################################################################################
function log_info() {
    _log "INFO" "$@"
}

################################################################################
# Log a debug message
# Arguments:
#   [-l logger_name]: Optional logger name
#   $*: Log message components
# Returns: Result of _log function
# Usage:
#   log_debug "Variable value: $var"
#   log_debug -l "terraform" "Terraform state: $state"
################################################################################
function log_debug() {
    _log "DEBUG" "$@"
}

################################################################################
# Log a verbose message (lowest priority)
# Arguments:
#   [-l logger_name]: Optional logger name
#   $*: Log message components
# Returns: Result of _log function
# Usage:
#   log_verbose "Detailed operation trace"
#   log_verbose -l "network" "Network configuration details"
################################################################################
function log_verbose() {
    _log "VERBOSE" "$@"
}

################################################################################
# CONVENIENCE FUNCTIONS FOR FUNCTION ENTRY/EXIT LOGGING
################################################################################

################################################################################
# Log function entry at INFO level
# Arguments: None (automatically detects calling function)
# Returns: Result of log_info
# Usage:
#   log_info_enter
################################################################################
function log_info_enter() {
    log_info "Entering function ${FUNCNAME[1]}"
}

################################################################################
# Log function exit at INFO level
# Arguments:
#   $1: Optional return code
# Returns: Result of log_info
# Usage:
#   log_info_exit [return_code]
################################################################################
function log_info_exit() {
    local return_code="${1:-0}"
    log_info "Exiting function ${FUNCNAME[1]} with return code: $return_code"
}

################################################################################
# Log function entry at DEBUG level
# Arguments: None (automatically detects calling function)
# Returns: Result of log_debug
# Usage:
#   log_debug_enter
################################################################################
function log_debug_enter() {
    log_debug "Entering function ${FUNCNAME[1]}"
}

################################################################################
# Log function exit at DEBUG level
# Arguments:
#   $1: Optional return code
# Returns: Result of log_debug
# Usage:
#   log_debug_exit [return_code]
################################################################################
function log_debug_exit() {
    local return_code="${1:-0}"
    log_debug "Exiting function ${FUNCNAME[1]} with return code: $return_code"
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

################################################################################
# List all available log levels
# Arguments: None
# Returns: None (outputs to stdout)
# Usage:
#   list_log_levels
################################################################################
function list_log_levels() {
    local level
    for level in "${!LOG_LEVELS[@]}"; do
        printf '%s\n' "$level"
    done | sort -k1,1n
}

################################################################################
# List all configured loggers and their levels
# Arguments: None
# Returns: None (outputs to stdout)
# Usage:
#   list_loggers
################################################################################
function list_loggers() {
    local logger
    for logger in "${!LOG_LEVEL_MAPPER[@]}"; do
        local level_num="${LOG_LEVEL_MAPPER[$logger]}"
        local level_name=""

        # Find level name by value
        for level in "${!LOG_LEVELS[@]}"; do
            if [[ "${LOG_LEVELS[$level]}" == "$level_num" ]]; then
                level_name="$level"
                break
            fi
        done

        printf '%-20s %s\n' "$logger" "$level_name"
    done | sort
}

################################################################################
# Clean up old log files (older than specified days)
# Arguments:
#   $1: Number of days to retain (default: 30)
# Returns:
#   0: Success
#   1: Cleanup failed
# Usage:
#   cleanup_logs [days_to_retain]
# Example:
#   cleanup_logs 7  # Keep only 7 days of logs
################################################################################
function cleanup_logs() {
    local days_to_retain="${1:-30}"

    if [[ ! "$days_to_retain" =~ ^[0-9]+$ ]]; then
        log_error "Invalid days_to_retain value: $days_to_retain"
        return 1
    fi

    if [[ ! -d "${LOG_BASE_DIR}" ]]; then
        log_warn "Log directory does not exist: ${LOG_BASE_DIR}"
        return 0
    fi

    log_info "Cleaning up log files older than $days_to_retain days"

    # Find and remove old log files
    local files_removed=0
    while IFS= read -r -d '' file; do
        if rm "$file" 2>/dev/null; then
            ((files_removed++))
            log_debug "Removed old log file: $file"
        else
            log_warn "Failed to remove log file: $file"
        fi
    done < <(find "${LOG_BASE_DIR}" -name "*.log" -type f -mtime "+$days_to_retain" -print0 2>/dev/null)

    log_info "Cleanup completed. Removed $files_removed log files"
    return 0
}

################################################################################
# BACKWARD COMPATIBILITY FUNCTIONS
################################################################################

# Maintain backward compatibility with existing function names
function log_info_file() { log_info "$@"; }
function log_debug_file() { log_debug "$@"; }
function log_verbose_file() { log_verbose "$@"; }
function log_info_leave() { log_info_exit "$@"; }
function log_debug_leave() { log_debug_exit "$@"; }
function log_verbose_enter() { log_verbose "Entering function ${FUNCNAME[1]}"; }
function log_verbose_leave() { log_verbose "Exiting function ${FUNCNAME[1]}"; }

# Legacy function aliases
function __list_log_levels() { list_log_levels; }
function __list_available_loggers() { list_loggers; }

################################################################################
# INITIALIZATION ON SOURCE
################################################################################

# Initialize logging system when script is sourced (unless disabled)
if [[ "${DISABLE_AUTO_LOG_INIT:-false}" != "true" ]]; then
    init_logging
fi

# Export public functions for use by other scripts
export -f log_critical log_error log_warn log_info log_debug log_verbose
export -f log_info_enter log_info_exit log_debug_enter log_debug_exit
export -f set_log_level set_console_logging set_file_logging
export -f init_logging cleanup_logs list_log_levels list_loggers

################################################################################
# END OF log_utils.sh
################################################################################
