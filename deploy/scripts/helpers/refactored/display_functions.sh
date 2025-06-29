#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Display Functions Module - Refactored Banner and Help System
# This module replaces the duplicated banner and help functions from script_helpers.sh
# with a clean, template-driven approach

# Source foundation standards
script_directory="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
if [[ -f "${script_directory}/foundation_standards.sh" ]]; then
    # shellcheck source=./foundation_standards.sh
    source "${script_directory}/foundation_standards.sh"
else
    echo "ERROR: foundation_standards.sh not found" >&2
    exit 1
fi

# =============================================================================
# DISPLAY CONFIGURATION
# =============================================================================
declare -gr DEFAULT_BANNER_WIDTH=80
declare -gr MIN_BANNER_WIDTH=60
declare -gr MAX_BANNER_WIDTH=120

# Color definitions - centralized and consistent
declare -gr COLOR_RESET="\e[0m"
declare -gr COLOR_BOLD_RED="\e[1;31m"
declare -gr COLOR_CYAN="\e[1;36m"
declare -gr COLOR_GREEN="\e[1;32m"
declare -gr COLOR_YELLOW="\e[0;33m"

# =============================================================================
# BANNER SYSTEM - Template-driven approach
# =============================================================================

################################################################################
# Enhanced banner display with template support and logging integration        #
# This replaces the original print_banner function with improved functionality #
# Arguments:                                                                   #
#   $1 - Banner title                                                          #
#   $2 - Primary message                                                       #
#   $3 - Message type (error, success, warning, info) - default: info          #
#   $4 - Secondary message (optional)                                          #
#   $5 - Banner width (optional) - default: 80                                 #
# Returns:                                                                     #
#   SUCCESS on successful display, PARAM_ERROR on invalid parameters           #
# Usage:                                                                       #
#   display_banner "Title" "Message" "info" "Secondary message"                #
#   display_banner "Error" "Failed operation" "error"                          #
################################################################################
function display_banner() {
    log_debug "Entering display_banner function"

    # Parameter validation
    if ! validate_function_params "display_banner" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local title="${1:-}"
    local message="${2:-}"
    local type="${3:-info}"
    local secondary_message="${4:-}"
    local width="${5:-$DEFAULT_BANNER_WIDTH}"

    # Input sanitization
    title=$(sanitize_input "$title" "general")
    message=$(sanitize_input "$message" "general")
    secondary_message=$(sanitize_input "$secondary_message" "general")

    # Validate width parameter
    if [[ ! "$width" =~ ^[0-9]+$ ]] || [[ "$width" -lt $MIN_BANNER_WIDTH ]] || [[ "$width" -gt $MAX_BANNER_WIDTH ]]; then
        log_warn "Invalid banner width: $width, using default: $DEFAULT_BANNER_WIDTH"
        width=$DEFAULT_BANNER_WIDTH
    fi

    # Log the banner display for audit trail
    log_info "Displaying banner - Title: $title, Type: $type"
    log_debug "Banner details - Message: $message, Width: $width"

    # Determine color based on message type
    local color
    case "$type" in
        error)
            color="$COLOR_BOLD_RED"
            log_error "Banner Error: $title - $message"
            ;;
        success)
            color="$COLOR_GREEN"
            log_info "Banner Success: $title - $message"
            ;;
        warning)
            color="$COLOR_YELLOW"
            log_warn "Banner Warning: $title - $message"
            ;;
        info|*)
            color="$COLOR_CYAN"
            log_info "Banner Info: $title - $message"
            ;;
    esac

    # Generate banner using helper function
    _generate_banner_output "$title" "$message" "$secondary_message" "$color" "$width"

    log_debug "Banner display completed successfully"
    return $SUCCESS
}

################################################################################
# Internal banner generation helper                                            #
# Generates the actual banner output with proper formatting                    #
# Arguments:                                                                   #
#   $1 - Title text                                                            #
#   $2 - Message text                                                          #
#   $3 - Secondary message text                                                #
#   $4 - Color code                                                            #
#   $5 - Banner width                                                          #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _generate_banner_output() {
    local title="$1"
    local message="$2"
    local secondary_message="$3"
    local color="$4"
    local width="$5"

    # Ensure odd-length strings for proper centering
    local length=${#title}
    if ((length % 2 == 0)); then
        title="$title "
    fi

    length=${#message}
    if ((length % 2 == 0)); then
        message="$message "
    fi

    length=${#secondary_message}
    if ((length % 2 == 0 && length > 0)); then
        secondary_message="$secondary_message "
    fi

    # Calculate padding for centering
    local padding_title=$(((width - ${#title}) / 2))
    local padding_message=$(((width - ${#message}) / 2))
    local padding_secondary_message=$(((width - ${#secondary_message}) / 2))

    # Generate centered text
    local centered_title
    local centered_message
    local centered_secondary_message

    centered_title=$(printf "%*s%s%*s" $padding_title "" "$title" $padding_title "")
    centered_message=$(printf "%*s%s%*s" $padding_message "" "$message" $padding_message "")

    if [[ -n "$secondary_message" ]]; then
        centered_secondary_message=$(printf "%*s%s%*s" $padding_secondary_message "" "$secondary_message" $padding_secondary_message "")
    fi

    # Generate border line
    local border_line
    border_line=$(printf "%*s" $width | tr ' ' '#')

    # Output the banner
    echo ""
    echo -e "${color}"
    echo "$border_line"
		# shellcheck disable=SC2183
    echo "#$(printf "%*s" $((width-2)) | tr ' ' ' ')#"
    echo -e "#${color}${centered_title}${COLOR_RESET}#"
		# shellcheck disable=SC2183
    echo "#$(printf "%*s" $((width-2)) | tr ' ' ' ')#"
    echo -e "#${color}${centered_message}${COLOR_RESET}#"
		# shellcheck disable=SC2183
    echo "#$(printf "%*s" $((width-2)) | tr ' ' ' ')#"

    if [[ -n "$secondary_message" ]]; then
        echo -e "#${color}${centered_secondary_message}${COLOR_RESET}#"
				# shellcheck disable=SC2183
        echo "#$(printf "%*s" $((width-2)) | tr ' ' ' ')#"
    fi

    echo "$border_line"
    echo -e "${COLOR_RESET}"
    echo ""
}

# =============================================================================
# HELP SYSTEM - Template-driven approach
# =============================================================================

# Help templates to eliminate code duplication
declare -A HELP_TEMPLATES

HELP_TEMPLATES[installer]='
#                                                                                       #
# This script is used to install the SAP Deployment Automation Framework deployer     #
#                                                                                       #
# Usage:                                                                                #
#   %s --parameterfile <parameter_file>                                                #
#                                                                                       #
# Options:                                                                              #
#   -p, --parameterfile    Parameter file path                                         #
#   -i, --auto-approve     Automatic approval of changes                               #
#   -h, --help             Show this help message                                      #
#                                                                                       #
'

HELP_TEMPLATES[remover]='
#                                                                                       #
# This script is used to remove SAP Deployment Automation Framework resources         #
#                                                                                       #
# Usage:                                                                                #
#   %s --parameterfile <parameter_file> [options]                                     #
#                                                                                       #
# Options:                                                                              #
#   -p, --parameterfile    Parameter file path                                         #
#   -t, --type             Deployment type                                             #
#   -i, --auto-approve     Automatic approval of changes                               #
#   -f, --force            Force removal without confirmation                          #
#   -h, --help             Show this help message                                      #
#                                                                                       #
'

HELP_TEMPLATES[control_plane]='
#                                                                                       #
# This script deploys the SAP Deployment Automation Framework control plane           #
#                                                                                       #
# Usage:                                                                                #
#   %s --control_plane_name <name> [options]                                          #
#                                                                                       #
# Options:                                                                              #
#   -c, --control_plane_name    Control plane name                                     #
#   -d, --deployer_parameter_file    Deployer parameter file                           #
#   -l, --library_parameter_file     Library parameter file                            #
#   -s, --subscription          Azure subscription ID                                  #
#   -i, --auto-approve          Automatic approval of changes                          #
#   -h, --help                  Show this help message                                 #
#                                                                                       #
'

################################################################################
# Enhanced help display using templates                                        #
# Replaces multiple duplicated help functions with a single template-driven    #
# approach                                                                     #
# Arguments:                                                                   #
#   $1 - Help type (installer, remover, control_plane, etc.)                   #
#   $2 - Script name for usage examples                                        #
#   $3 - Additional help content (optional)                                    #
# Returns:                                                                     #
#   SUCCESS on successful display, PARAM_ERROR on invalid parameters           #
# Usage:                                                                       #
#   display_help "installer" "$0"                                              #
#   display_help "control_plane" "deploy_control_plane.sh"                     #
################################################################################
function display_help() {
    log_debug "Entering display_help function"

    if ! validate_function_params "display_help" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local help_type="${1:-general}"
    local script_name="${2:-script}"
    local additional_content="${3:-}"

    # Sanitize inputs
    help_type=$(sanitize_input "$help_type" "name")
    script_name=$(sanitize_input "$script_name" "path")

    log_info "Displaying help for type: $help_type"

    # Get template or use generic template
    local template="${HELP_TEMPLATES[$help_type]}"
    if [[ -z "$template" ]]; then
        log_warn "No specific help template found for: $help_type, using generic template"
        template='
#                                                                                       #
# SAP Deployment Automation Framework Script                                           #
#                                                                                       #
# Usage:                                                                                #
#   %s [options]                                                                       #
#                                                                                       #
# Options:                                                                              #
#   -h, --help             Show this help message                                      #
#                                                                                       #
'
    fi

    # Display help banner and content
    display_banner "Help" "Usage Information" "info"

    echo "#################################################################################"
    printf "$template" "$script_name"

    if [[ -n "$additional_content" ]]; then
        echo "#                                                                               #"
        echo "# Additional Information:                                                       #"
        echo "#   $additional_content"
        echo "#                                                                               #"
    fi

    echo "#################################################################################"
    echo ""

    log_debug "Help display completed"
    return $SUCCESS
}

################################################################################
# Add or update help template                                                  #
# Allows dynamic addition of help templates for extensibility                  #
# Arguments:                                                                   #
#   $1 - Template name                                                         #
#   $2 - Template content                                                      #
# Returns:                                                                     #
#   SUCCESS on successful addition, PARAM_ERROR on invalid parameters          #
# Usage:                                                                       #
#   add_help_template "custom_script" "Custom help content..."                 #
################################################################################
function add_help_template() {
    if ! validate_function_params "add_help_template" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local template_name="${1:-}"
    local template_content="${2:-}"

    template_name=$(sanitize_input "$template_name" "name")

    if [[ -z "$template_name" ]] || [[ -z "$template_content" ]]; then
        log_error "Template name and content cannot be empty"
        return $PARAM_ERROR
    fi

    HELP_TEMPLATES["$template_name"]="$template_content"
    log_info "Added help template: $template_name"

    return $SUCCESS
}

# =============================================================================
# BACKWARD COMPATIBILITY FUNCTIONS
# =============================================================================

################################################################################
# Legacy print_banner function for backward compatibility                      #
# Wrapper around the new display_banner function                               #
# Arguments: Same as original print_banner                                     #
# Returns: SUCCESS                                                             #
################################################################################
function print_banner() {
    deprecation_warning "print_banner" "display_banner"
    display_banner "$@"
    return $SUCCESS
}

# =============================================================================
# ERROR DISPLAY FUNCTIONS
# =============================================================================

################################################################################
# Standardized error message display                                           #
# Consistent error reporting with logging integration                          #
# Arguments:                                                                   #
#   $1 - Error title                                                           #
#   $2 - Error message                                                         #
#   $3 - Error code (optional)                                                 #
#   $4 - Additional context (optional)                                         #
# Returns:                                                                     #
#   The provided error code or GENERAL_ERROR                                   #
# Usage:                                                                       #
#   display_error "Configuration Error" "Parameter file not found" $PARAM_ERROR#
################################################################################
function display_error() {
    local error_title="${1:-Error}"
    local error_message="${2:-Unknown error occurred}"
    local error_code="${3:-$GENERAL_ERROR}"
    local additional_context="${4:-}"

    # Display error banner
    display_banner "$error_title" "$error_message" "error" "$additional_context"

    # Log the error with context
    log_error "Error Code: $error_code - $error_title: $error_message"
    if [[ -n "$additional_context" ]]; then
        log_error "Additional Context: $additional_context"
    fi

    return "$error_code"
}

################################################################################
# Success message display                                                      #
# Consistent success reporting with logging integration                        #
# Arguments:                                                                   #
#   $1 - Success title                                                         #
#   $2 - Success message                                                       #
#   $3 - Additional details (optional)                                         #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
# Usage:                                                                       #
#   display_success "Deployment Complete" "All resources created successfully" #
################################################################################
function display_success() {
    local success_title="${1:-Success}"
    local success_message="${2:-Operation completed successfully}"
    local additional_details="${3:-}"

    display_banner "$success_title" "$success_message" "success" "$additional_details"
    log_info "Success: $success_title - $success_message"

    return $SUCCESS
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

log_info "Display functions module loaded successfully"
log_debug "Available functions: display_banner, display_help, display_error, display_success"
log_debug "Backward compatibility: print_banner (deprecated)"
log_debug "Help templates loaded: ${!HELP_TEMPLATES[*]}"
