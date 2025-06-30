#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Foundation Layer - Standardized Error Codes and Common Standards
# This module provides the foundation for all refactored script_helpers modules

# =============================================================================
# STANDARDIZED ERROR CODES
# =============================================================================
# These error codes provide consistent return values across all modules
# shellcheck disable=SC2034
declare -gr SUCCESS=0
declare -gr GENERAL_ERROR=1
declare -gr PARAM_ERROR=2
declare -gr HELP_REQUESTED=3
declare -gr DEPENDENCY_ERROR=10
declare -gr ENV_ERROR=11
declare -gr AUTH_ERROR=12
declare -gr VALIDATION_ERROR=13
declare -gr TERRAFORM_ERROR=20
declare -gr AZURE_ERROR=21
declare -gr FILE_ERROR=30
declare -gr NETWORK_ERROR=31
declare -gr NOT_FOUND=32

# =============================================================================
# MODULE METADATA
# =============================================================================
declare -gr SCRIPT_HELPERS_VERSION="2.0.0"
declare -gr REFACTORING_PHASE="1"

# =============================================================================
# LOGGING INTEGRATION
# =============================================================================
# Source log_utils if not already loaded
if [[ -z "${__isLibSourced:-}" ]]; then
    script_directory="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    if [[ -f "${script_directory}/../log_utils.sh" ]]; then
        # shellcheck source=../log_utils.sh
        source "${script_directory}/../log_utils.sh"
    else
        echo "ERROR: log_utils.sh not found. Logging will be limited." >&2
        # Fallback logging functions
        log_error() { echo "ERROR: $*" >&2; }
        log_warn() { echo "WARN: $*" >&2; }
        log_info() { echo "INFO: $*"; }
        log_debug() { echo "DEBUG: $*"; }
    fi
fi

# =============================================================================
# STANDARD FUNCTION TEMPLATE AND VALIDATION
# =============================================================================

################################################################################
# Standard function template validation helper                                 #
# This validates that functions follow the new standardized patterns           #
# Arguments:                                                                   #
#   $1 - Function name being validated                                         #
#   $2 - Expected parameter count                                              #
#   $3 - Actual parameter count received                                       #
# Returns:                                                                     #
#   SUCCESS on valid parameters, PARAM_ERROR on validation failure             #
# Usage:                                                                       #
#   validate_function_params "my_function" 2 $#                                #
################################################################################
function validate_function_params() {
    local function_name="${1:-unknown_function}"
    local expected_count="${2:-0}"
    local actual_count="${3:-0}"

    log_debug "Validating parameters for function: $function_name"
    log_debug "Expected: $expected_count, Actual: $actual_count"

    if [[ ! "$expected_count" =~ ^[0-9]+$ ]]; then
        log_error "Invalid expected parameter count: $expected_count"
        return $PARAM_ERROR
    fi

    if [[ ! "$actual_count" =~ ^[0-9]+$ ]]; then
        log_error "Invalid actual parameter count: $actual_count"
        return $PARAM_ERROR
    fi

    if [[ "$actual_count" -lt "$expected_count" ]]; then
        log_error "Function $function_name requires $expected_count parameters, got $actual_count"
        return $PARAM_ERROR
    fi

    return $SUCCESS
}

################################################################################
# Input sanitization helper                                                    #
# Sanitizes input parameters to prevent injection and ensure safe processing   #
# Arguments:                                                                   #
#   $1 - Input string to sanitize                                              #
#   $2 - Sanitization type (path, name, url, etc.) - optional,                 #
#                                                    defaults to 'general'     #
# Returns:                                                                     #
#   SUCCESS and outputs sanitized string, PARAM_ERROR on failure               #
# Usage:                                                                       #
#   sanitized=$(sanitize_input "$user_input" "path")                           #
################################################################################
function sanitize_input() {
    local input="${1:-}"
    local type="${2:-general}"

    if [[ -z "$input" ]]; then
        log_debug "Empty input provided to sanitize_input"
        echo ""
        return $SUCCESS
    fi

    log_debug "Sanitizing input of type: $type"

    case "$type" in
        path)
            # Remove dangerous path characters but allow valid path chars
            echo "$input" | sed 's/[^a-zA-Z0-9._/-]//g'
            ;;
        name)
            # Allow only alphanumeric, underscore, hyphen
            echo "$input" | sed 's/[^a-zA-Z0-9_-]//g'
            ;;
        url)
            # Basic URL character sanitization
            echo "$input" | sed 's/[^a-zA-Z0-9._:/?&=-]//g'
            ;;
        general|*)
            # Remove control characters and most special chars
            echo "$input" | sed 's/[^a-zA-Z0-9._@%/:-]//g'
            ;;
    esac

    return $SUCCESS
}

# =============================================================================
# BACKWARD COMPATIBILITY TRACKING
# =============================================================================

# Legacy function names that are being replaced
declare -ga DEPRECATED_FUNCTIONS=(
    "print_banner"
    "validate_exports"
    "validate_dependencies"
    "version_compare"
)

################################################################################
# Legacy function deprecation warning                                          #
# Issues warnings when deprecated functions are called                         #
# Arguments:                                                                   #
#   $1 - Name of the deprecated function                                       #
#   $2 - Replacement function name (optional)                                  #
# Returns:                                                                     #
#   Always returns SUCCESS                                                     #
# Usage:                                                                       #
#   deprecation_warning "old_function" "new_function"                          #
################################################################################
function deprecation_warning() {
    local deprecated_function="${1:-unknown}"
    local replacement_function="${2:-}"

    log_warn "DEPRECATED: Function '$deprecated_function' is deprecated"
    if [[ -n "$replacement_function" ]]; then
        log_warn "Please use '$replacement_function' instead"
    fi
    log_warn "This function will be removed in a future version"

    return $SUCCESS
}

# =============================================================================
# VERSION MANAGEMENT
# =============================================================================

################################################################################
# Get the current script helpers version                                       #
# Arguments:                                                                   #
#   None                                                                       #
# Returns:                                                                     #
#   Always returns SUCCESS and outputs version                                 #
# Usage:                                                                       #
#   version=$(get_script_helpers_version)                                      #
################################################################################
function get_script_helpers_version() {
    echo "$SCRIPT_HELPERS_VERSION"
    return $SUCCESS
}

################################################################################
# Check if refactoring is complete                                             #
# Arguments:                                                                   #
#   None                                                                       #
# Returns:                                                                     #
#   SUCCESS if refactoring complete, GENERAL_ERROR if still in progress        #
# Usage:                                                                       #
#   if is_refactoring_complete; then                                           #
################################################################################
function is_refactoring_complete() {
    # Currently in phase 1, refactoring not complete
    log_debug "Refactoring phase: $REFACTORING_PHASE"
    if [[ "$REFACTORING_PHASE" == "5" ]]; then
        return $SUCCESS
    else
        return $GENERAL_ERROR
    fi
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

log_info "Foundation standards module loaded (version $SCRIPT_HELPERS_VERSION)"
log_debug "Error codes standardized: SUCCESS=$SUCCESS, GENERAL_ERROR=$GENERAL_ERROR"
log_debug "Logging integration: $(type -t log_error 2>/dev/null || echo "fallback mode")"
