#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# shellcheck disable=SC1090,SC1091,SC2034,SC2154
# Validation Functions Module - Centralized Parameter and Environment Validation
# This module consolidates all validation logic from script_helpers.sh into standardized,
# reusable functions with proper error handling and logging integration

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
# VALIDATION CONFIGURATION
# =============================================================================

# Required environment variables for different validation contexts
declare -a CORE_ENV_VARS=(
    "SAP_AUTOMATION_REPO_PATH"
    "CONFIG_REPO_PATH"
    "ARM_SUBSCRIPTION_ID"
)

declare -a WEBAPP_ENV_VARS=(
    "TF_VAR_app_registration_app_id"
    "TF_VAR_webapp_client_secret"
)

declare -a AUTH_ENV_VARS=(
    "ARM_CLIENT_ID"
    "ARM_CLIENT_SECRET"
    "ARM_TENANT_ID"
)

# Required tools for system validation
declare -a REQUIRED_TOOLS=(
    "terraform"
    "az"
    "jq"
)

# =============================================================================
# ENVIRONMENT VALIDATION FUNCTIONS
# =============================================================================

################################################################################
# Enhanced environment variable validation with detailed reporting             #
# This replaces validate_exports() with improved error handling and logging    #
# Arguments:                                                                   #
#   $1 - Validation context (core, webapp, auth) - default: core               #
#   $2 - Strict mode (true/false) - default: true                              #
# Returns:                                                                     #
#   SUCCESS if all required variables are set, ENV_ERROR otherwise             #
# Usage:                                                                       #
#   validate_environment "core"                                                #
#   validate_environment "webapp" "false"                                      #
################################################################################
function validate_environment() {
    local context="${1:-core}"
    local strict_mode="${2:-true}"

    log_info "Starting environment validation for context: $context"
    log_debug "Strict mode: $strict_mode"

    local -a required_vars
    local validation_errors=0
    local missing_vars=()

    # Determine which variables to validate based on context
    case "$context" in
        core)
            required_vars=("${CORE_ENV_VARS[@]}")
            ;;
        webapp)
            required_vars=("${WEBAPP_ENV_VARS[@]}")
            ;;
        auth)
            required_vars=("${AUTH_ENV_VARS[@]}")
            ;;
        all)
            required_vars=("${CORE_ENV_VARS[@]}" "${WEBAPP_ENV_VARS[@]}" "${AUTH_ENV_VARS[@]}")
            ;;
        *)
            log_error "Invalid validation context: $context"
            return $PARAM_ERROR
            ;;
    esac

    log_debug "Validating ${#required_vars[@]} environment variables"

    # Validate each required variable
    for var in "${required_vars[@]}"; do
        if ! _validate_single_env_var "$var" "$strict_mode"; then
            missing_vars+=("$var")
            ((validation_errors++))
        fi
    done

    # Report results
    if [[ $validation_errors -eq 0 ]]; then
        log_info "Environment validation passed: all required variables are set"
        return $SUCCESS
    else
        log_error "Environment validation failed: $validation_errors missing variables"
        log_error "Missing variables: ${missing_vars[*]}"

        if [[ "$strict_mode" == "true" ]]; then
            _display_env_error_help "${missing_vars[@]}"
            return $ENV_ERROR
        else
            log_warn "Environment validation failed but continuing due to non-strict mode"
            return $SUCCESS
        fi
    fi
}

################################################################################
# Internal single environment variable validation                              #
# Arguments:                                                                   #
#   $1 - Variable name                                                         #
#   $2 - Strict mode                                                           #
# Returns:                                                                     #
#   SUCCESS if variable is set and valid, GENERAL_ERROR otherwise              #
################################################################################
function _validate_single_env_var() {
    local var_name="$1"
    local strict_mode="$2"

    log_debug "Validating environment variable: $var_name"

    # Check if variable is set
    if [[ -z "${!var_name:-}" ]]; then
        log_error "Environment variable not set: $var_name"
        return $GENERAL_ERROR
    fi

    # Additional validation for specific variables
    case "$var_name" in
        "ARM_SUBSCRIPTION_ID"|"TF_VAR_app_registration_app_id")
            if ! _is_valid_guid "${!var_name}"; then
                log_error "Invalid GUID format for $var_name: ${!var_name}"
                return $GENERAL_ERROR
            fi
            ;;
        "SAP_AUTOMATION_REPO_PATH"|"CONFIG_REPO_PATH")
            if [[ ! -d "${!var_name}" ]]; then
                log_error "Directory does not exist for $var_name: ${!var_name}"
                if [[ "$strict_mode" == "true" ]]; then
                    return $GENERAL_ERROR
                else
                    log_warn "Directory missing but continuing in non-strict mode"
                fi
            fi
            ;;
    esac

    log_debug "Environment variable validated: $var_name=${!var_name}"
    return $SUCCESS
}

################################################################################
# Display helpful error information for missing environment variables          #
# Arguments:                                                                   #
#   $@ - Array of missing variable names                                       #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _display_env_error_help() {
    local -a missing_vars=("$@")

    echo ""
    echo "#################################################################################"
    echo "#                                                                               #"
    echo "#                    ENVIRONMENT VALIDATION FAILED                             #"
    echo "#                                                                               #"
    echo "#################################################################################"
    echo ""
    echo "The following required environment variables are missing or invalid:"
    echo ""

    for var in "${missing_vars[@]}"; do
        echo "  ❌ $var"
        _get_env_var_help "$var"
    done

    echo ""
    echo "Please set these variables and try again."
    echo ""

    return $SUCCESS
}

################################################################################
# Get help text for specific environment variables                             #
# Arguments:                                                                   #
#   $1 - Environment variable name                                             #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _get_env_var_help() {
    local var_name="$1"

    case "$var_name" in
        "SAP_AUTOMATION_REPO_PATH")
            echo "     Path to the SAP automation repository"
            echo "     Example: export SAP_AUTOMATION_REPO_PATH=/opt/terraform/sap_deployment_automation"
            ;;
        "CONFIG_REPO_PATH")
            echo "     Path to the configuration repository"
            echo "     Example: export CONFIG_REPO_PATH=/opt/terraform/sap_config"
            ;;
        "ARM_SUBSCRIPTION_ID")
            echo "     Azure subscription ID (GUID format)"
            echo "     Example: export ARM_SUBSCRIPTION_ID=12345678-1234-1234-1234-123456789012"
            ;;
        "ARM_CLIENT_ID")
            echo "     Azure service principal client ID"
            echo "     Example: export ARM_CLIENT_ID=12345678-1234-1234-1234-123456789012"
            ;;
        "ARM_CLIENT_SECRET")
            echo "     Azure service principal client secret"
            echo "     Example: export ARM_CLIENT_SECRET=your-client-secret"
            ;;
        "ARM_TENANT_ID")
            echo "     Azure tenant ID (GUID format)"
            echo "     Example: export ARM_TENANT_ID=12345678-1234-1234-1234-123456789012"
            ;;
        *)
            echo "     Please refer to documentation for this variable"
            ;;
    esac
    echo ""
}

# =============================================================================
# PARAMETER FILE VALIDATION FUNCTIONS
# =============================================================================

################################################################################
# Enhanced parameter file validation with content analysis                     #
# This replaces validate_key_parameters() with improved error handling         #
# Arguments:                                                                   #
#   $1 - Parameter file path                                                   #
#   $2 - Required parameters (optional, space-separated list)                  #
# Returns:                                                                     #
#   SUCCESS if file is valid, PARAM_ERROR otherwise                            #
# Usage:                                                                       #
#   validate_parameter_file "/path/to/params.tfvars"                           #
#   validate_parameter_file "/path/to/params.tfvars" "environment location"    #
################################################################################
function validate_parameter_file() {
    if ! validate_function_params "validate_parameter_file" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local param_file="${1:-}"
    local required_params="${2:-}"

    log_info "Validating parameter file: $param_file"

    # Basic file existence and readability checks
    if ! _validate_file_access "$param_file"; then
        return $FILE_ERROR
    fi

    # Extract and validate key parameters
    local environment location management_network_logical_name network_logical_name

    if ! _extract_parameter_values "$param_file"; then
        log_error "Failed to extract parameters from file: $param_file"
        return $PARAM_ERROR
    fi

    # Validate required parameters if specified
    if [[ -n "$required_params" ]]; then
        local -a required_list
        IFS=' ' read -ra required_list <<< "$required_params"

        for param in "${required_list[@]}"; do
            if ! _validate_extracted_parameter "$param"; then
                log_error "Required parameter missing or invalid: $param"
                return $PARAM_ERROR
            fi
        done
    fi

    log_info "Parameter file validation completed successfully"
    return $SUCCESS
}

################################################################################
# Internal file access validation                                              #
# Arguments:                                                                   #
#   $1 - File path                                                             #
# Returns:                                                                     #
#   SUCCESS if file is accessible, FILE_ERROR otherwise                        #
################################################################################
function _validate_file_access() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        log_error "Parameter file does not exist: $file_path"
        return $FILE_ERROR
    fi

    if [[ ! -r "$file_path" ]]; then
        log_error "Parameter file is not readable: $file_path"
        return $FILE_ERROR
    fi

    log_debug "File access validation passed: $file_path"
    return $SUCCESS
}

################################################################################
# Extract parameter values from Terraform variable file                        #
# Arguments:                                                                   #
#   $1 - Parameter file path                                                   #
# Returns:                                                                     #
#   SUCCESS if extraction successful, PARAM_ERROR otherwise                    #
# Side Effects:                                                                #
#   Sets global variables: environment, location,                              #
#                          management_network_logical_name, etc.               #
################################################################################
function _extract_parameter_values() {
    local param_file="$1"

    log_debug "Extracting parameters from: $param_file"

    # Extract parameters using safe parsing
    environment=$(grep -E "^environment[[:space:]]*=" "$param_file" 2>/dev/null | \
                 sed 's/environment[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/' | \
                 head -1)

    location=$(grep -E "^location[[:space:]]*=" "$param_file" 2>/dev/null | \
              sed 's/location[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/' | \
              head -1)

    management_network_logical_name=$(grep -E "^management_network_logical_name[[:space:]]*=" "$param_file" 2>/dev/null | \
                                     sed 's/management_network_logical_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/' | \
                                     head -1)

    network_logical_name=$(grep -E "^network_logical_name[[:space:]]*=" "$param_file" 2>/dev/null | \
                          sed 's/network_logical_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/' | \
                          head -1)

    # Export for use by calling scripts (maintaining backward compatibility)
    export environment location management_network_logical_name network_logical_name

    log_debug "Extracted parameters - Environment: $environment, Location: $location"

    return $SUCCESS
}

################################################################################
# Validate extracted parameter value                                           #
# Arguments:                                                                   #
#   $1 - Parameter name                                                        #
# Returns:                                                                     #
#   SUCCESS if parameter is valid, PARAM_ERROR otherwise                       #
################################################################################
function _validate_extracted_parameter() {
    local param_name="$1"
    local param_value="${!param_name}"

    if [[ -z "$param_value" ]]; then
        log_error "Required parameter '$param_name' is missing or empty"
        return $PARAM_ERROR
    fi

    # Additional validation based on parameter type
    case "$param_name" in
        location)
            if ! _validate_azure_location "$param_value"; then
                log_error "Invalid Azure location: $param_value"
                return $PARAM_ERROR
            fi
            ;;
        environment)
            if ! _validate_environment_name "$param_value"; then
                log_error "Invalid environment name: $param_value"
                return $PARAM_ERROR
            fi
            ;;
    esac

    log_debug "Parameter validation passed: $param_name=$param_value"
    return $SUCCESS
}

# =============================================================================
# SYSTEM DEPENDENCY VALIDATION FUNCTIONS
# =============================================================================

################################################################################
# Enhanced system dependency validation with version checking                  #
# This replaces validate_dependencies() with improved functionality            #
# Arguments:                                                                   #
#   $1 - Check versions (true/false) - default: false                          #
#   $2 - Required tools list (optional, space-separated)                       #
# Returns:                                                                     #
#   SUCCESS if all dependencies are available, DEPENDENCY_ERROR otherwise      #
# Usage:                                                                       #
#   validate_system_dependencies                                               #
#   validate_system_dependencies "true" "terraform az jq"                      #
################################################################################
# shellcheck disable=SC2120
function validate_system_dependencies() {
    local check_versions="${1:-false}"
    local custom_tools="${2:-}"

    log_info "Starting system dependency validation"
    log_debug "Version checking: $check_versions"

    local -a tools_to_check
    if [[ -n "$custom_tools" ]]; then
        IFS=' ' read -ra tools_to_check <<< "$custom_tools"
    else
        tools_to_check=("${REQUIRED_TOOLS[@]}")
    fi

    local missing_tools=()
    local validation_errors=0

    # Check each required tool
    for tool in "${tools_to_check[@]}"; do
        log_debug "Checking availability of tool: $tool"

        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
            ((validation_errors++))
            log_error "Required tool not found: $tool"
        else
            log_debug "Tool found: $tool"

            if [[ "$check_versions" == "true" ]]; then
                _validate_tool_version "$tool"
            fi
        fi
    done

    # Check for Cloud Shell environment
    _detect_cloud_shell_environment

    # Report results
    if [[ $validation_errors -eq 0 ]]; then
        log_info "System dependency validation passed: all required tools are available"
        return $SUCCESS
    else
        log_error "System dependency validation failed: $validation_errors missing tools"
        log_error "Missing tools: ${missing_tools[*]}"
        _display_dependency_error_help "${missing_tools[@]}"
        return $DEPENDENCY_ERROR
    fi
}

################################################################################
# Validate tool version requirements                                           #
# Arguments:                                                                   #
#   $1 - Tool name                                                             #
# Returns:                                                                     #
#   SUCCESS if version is acceptable, GENERAL_ERROR otherwise                  #
################################################################################
function _validate_tool_version() {
    local tool="$1"

    case "$tool" in
        terraform)
            local tf_version
            tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null)
            if [[ -n "$tf_version" ]]; then
                log_info "Terraform version: $tf_version"
                # Add specific version requirements here if needed
            else
                log_warn "Could not determine Terraform version"
            fi
            ;;
        az)
            local az_version
            az_version=$(az version --output json 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null)
            if [[ -n "$az_version" ]]; then
                log_info "Azure CLI version: $az_version"
            else
                log_warn "Could not determine Azure CLI version"
            fi
            ;;
        jq)
            local jq_version
            jq_version=$(jq --version 2>/dev/null)
            if [[ -n "$jq_version" ]]; then
                log_info "jq version: $jq_version"
            else
                log_warn "Could not determine jq version"
            fi
            ;;
    esac

    return $SUCCESS
}

################################################################################
# Detect Cloud Shell environment and set appropriate configurations            #
# Arguments: None                                                              #
# Returns: Always SUCCESS                                                      #
# Side Effects: May modify PATH and other environment variables                #
################################################################################
function _detect_cloud_shell_environment() {
    if [[ -n "${AZURE_HTTP_USER_AGENT:-}" ]] || [[ -n "${POWERSHELL_DISTRIBUTION_CHANNEL:-}" ]]; then
        log_info "Azure Cloud Shell environment detected"

        # Set up Terraform path for Cloud Shell if needed
        if [[ -f "/opt/terraform/bin/terraform" ]] && ! command -v terraform >/dev/null 2>&1; then
            export PATH="/opt/terraform/bin:$PATH"
            log_info "Added Terraform to PATH for Cloud Shell"
        fi

        # Create necessary directories
        local tf_cache_dir="${HOME}/.terraform.d"
        if [[ ! -d "$tf_cache_dir" ]]; then
            mkdir -p "$tf_cache_dir"
            log_debug "Created Terraform cache directory: $tf_cache_dir"
        fi
    else
        log_debug "Local environment detected (not Cloud Shell)"
    fi

    return $SUCCESS
}

# =============================================================================
# AZURE RESOURCE VALIDATION FUNCTIONS
# =============================================================================

################################################################################
# Validate Azure Key Vault access and permissions                              #
# This replaces validate_key_vault() with enhanced functionality               #
# Arguments:                                                                   #
#   $1 - Key vault name                                                        #
#   $2 - Subscription ID (optional)                                            #
#   $3 - Max retry attempts (optional, default: 3)                             #
# Returns:                                                                     #
#   SUCCESS if key vault is accessible, AZURE_ERROR otherwise                  #
# Usage:                                                                       #
#   validate_azure_keyvault "my-keyvault"                                      #
#   validate_azure_keyvault "my-keyvault" "subscription-id" 5                  #
################################################################################
function validate_azure_keyvault() {
    if ! validate_function_params "validate_azure_keyvault" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local keyvault_name="${1:-}"
    local subscription_id="${2:-}"
    local max_retries="${3:-3}"

    log_info "Validating Azure Key Vault access: $keyvault_name"

    # Set subscription context if provided
    if [[ -n "$subscription_id" ]]; then
        log_debug "Setting subscription context: $subscription_id"
        if ! az account set --subscription "$subscription_id" >/dev/null 2>&1; then
            log_error "Failed to set subscription context: $subscription_id"
            return $AZURE_ERROR
        fi
    fi

    # Retry logic for Key Vault validation
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        log_debug "Key Vault validation attempt $attempt of $max_retries"

        if _test_keyvault_access "$keyvault_name"; then
            log_info "Key Vault validation successful: $keyvault_name"
            return $SUCCESS
        fi

        if [[ $attempt -lt $max_retries ]]; then
            log_warn "Key Vault validation failed, retrying in 30 seconds..."
            sleep 30
        fi

        ((attempt++))
    done

    log_error "Key Vault validation failed after $max_retries attempts: $keyvault_name"
    return $AZURE_ERROR
}

################################################################################
# Internal Key Vault access test                                               #
# Arguments:                                                                   #
#   $1 - Key vault name                                                        #
# Returns:                                                                     #
#   SUCCESS if accessible, GENERAL_ERROR otherwise                             #
################################################################################
function _test_keyvault_access() {
    local keyvault_name="$1"

    # Test basic Key Vault access
    if ! az keyvault show --name "$keyvault_name" --output none 2>/dev/null; then
        log_debug "Key Vault not accessible or does not exist: $keyvault_name"
        return $GENERAL_ERROR
    fi

    # Test secret listing permissions
    if ! az keyvault secret list --vault-name "$keyvault_name" --output none 2>/dev/null; then
        log_debug "Insufficient permissions for Key Vault: $keyvault_name"
        return $GENERAL_ERROR
    fi

    log_debug "Key Vault access test passed: $keyvault_name"
    return $SUCCESS
}

# =============================================================================
# UTILITY VALIDATION FUNCTIONS
# =============================================================================

################################################################################
# Validate GUID format                                                         #
# Arguments:                                                                   #
#   $1 - String to validate as GUID                                            #
# Returns:                                                                     #
#   SUCCESS if valid GUID format, PARAM_ERROR otherwise                        #
# Usage:                                                                       #
#   if _is_valid_guid "$subscription_id"; then                                 #
################################################################################
function _is_valid_guid() {
    local guid="${1:-}"
    local guid_pattern="^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

    if [[ "$guid" =~ $guid_pattern ]]; then
        return $SUCCESS
    else
        return $PARAM_ERROR
    fi
}

################################################################################
# Validate Azure location                                                      #
# Arguments:                                                                   #
#   $1 - Location string to validate                                           #
# Returns:                                                                     #
#   SUCCESS if valid location, PARAM_ERROR otherwise                           #
################################################################################
function _validate_azure_location() {
    local location="${1:-}"

    # Basic validation - Azure locations are lowercase, no spaces, may contain hyphens
    if [[ "$location" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]; then
        return $SUCCESS
    else
        return $PARAM_ERROR
    fi
}

################################################################################
# Validate environment name                                                    #
# Arguments:                                                                   #
#   $1 - Environment name to validate                                          #
# Returns:                                                                     #
#   SUCCESS if valid environment name, PARAM_ERROR otherwise                   #
################################################################################
function _validate_environment_name() {
    local env_name="${1:-}"

    # Environment names should be alphanumeric with optional hyphens/underscores
    if [[ "$env_name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9_-]*[a-zA-Z0-9])?$ ]] && [[ ${#env_name} -le 20 ]]; then
        return $SUCCESS
    else
        return $PARAM_ERROR
    fi
}

# =============================================================================
# BACKWARD COMPATIBILITY FUNCTIONS
# =============================================================================

################################################################################
# Legacy validate_exports function for backward compatibility                  #
################################################################################
function validate_exports() {
    deprecation_warning "validate_exports" "validate_environment"
    validate_environment "core"
    return $?
}

################################################################################
# Legacy validate_dependencies function for backward compatibility             #
################################################################################
function validate_dependencies() {
    deprecation_warning "validate_dependencies" "validate_system_dependencies"
    validate_system_dependencies
    return $?
}

################################################################################
# Legacy validate_key_parameters function for backward compatibility           #
################################################################################
function validate_key_parameters() {
    deprecation_warning "validate_key_parameters" "validate_parameter_file"
    validate_parameter_file "$@"
    return $?
}

################################################################################
# Legacy validate_key_vault function for backward compatibility                #
################################################################################
function validate_key_vault() {
    deprecation_warning "validate_key_vault" "validate_azure_keyvault"
    validate_azure_keyvault "$@"
    return $?
}

# =============================================================================
# ERROR HELP DISPLAY FUNCTIONS
# =============================================================================

################################################################################
# Display helpful error information for missing dependencies                   #
# Arguments:                                                                   #
#   $@ - Array of missing tool names                                           #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _display_dependency_error_help() {
    local -a missing_tools=("$@")

    echo ""
    echo "#################################################################################"
    echo "#                                                                               #"
    echo "#                    DEPENDENCY VALIDATION FAILED                              #"
    echo "#                                                                               #"
    echo "#################################################################################"
    echo ""
    echo "The following required tools are missing:"
    echo ""

    for tool in "${missing_tools[@]}"; do
        echo "  ❌ $tool"
        _get_tool_installation_help "$tool"
    done

    echo ""
    echo "Please install these tools and try again."
    echo ""

    return $SUCCESS
}

################################################################################
# Get installation help for specific tools                                     #
# Arguments:                                                                   #
#   $1 - Tool name                                                             #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _get_tool_installation_help() {
    local tool_name="$1"

    case "$tool_name" in
        terraform)
            echo "     Install from: https://www.terraform.io/downloads.html"
            echo "     Or use package manager: apt install terraform"
            ;;
        az)
            echo "     Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            echo "     Or use package manager: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
            ;;
        jq)
            echo "     Install from: https://stedolan.github.io/jq/download/"
            echo "     Or use package manager: apt install jq"
            ;;
        *)
            echo "     Please refer to the tool's official documentation"
            ;;
    esac
    echo ""
}

# Additional functions for deploy/scripts/helpers/refactored/validation_functions.sh

#==============================================================================
# Pipeline-Specific Configuration File Validation
#==============================================================================

function validate_pipeline_configuration_files() {
    local deployer_file="$1"
    local library_file="$2"

    display_banner "File Validation" "Validating configuration files" "info"
    send_pipeline_event "progress" "Validating configuration files" "30"

    local validation_errors=0

    # Validate deployer configuration file
    if ! validate_deployer_configuration_file "$deployer_file"; then
        ((validation_errors++))
    fi

    # Validate library configuration file
    if ! validate_library_configuration_file "$library_file"; then
        ((validation_errors++))
    fi

    # Convert files to Unix format for compatibility
    if ! convert_files_to_unix_format "$deployer_file" "$library_file"; then
        ((validation_errors++))
    fi

    if [[ $validation_errors -gt 0 ]]; then
        display_error "File Validation" "Configuration file validation failed" "$FILE_ERROR"
        send_pipeline_event "error" "Configuration file validation failed"
        return $FILE_ERROR
    fi

    display_success "File Validation" "All configuration files validated successfully"
    send_pipeline_event "progress" "Configuration files validated" "40"
    return $SUCCESS
}

function validate_deployer_configuration_file() {
    local file="$1"

    log_info "Validating deployer configuration file: $file"

    if [[ ! -f "$file" ]]; then
        display_error "Missing File" "Deployer configuration file not found: $file" "$FILE_ERROR"
        echo "##vso[task.logissue type=error]File DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME was not found."
        return $FILE_ERROR
    fi

    # Validate file is readable
    if [[ ! -r "$file" ]]; then
        display_error "File Access" "Deployer configuration file not readable: $file" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Validate file content structure (basic check)
    if ! validate_terraform_configuration_structure "$file"; then
        display_error "File Content" "Deployer configuration file structure invalid: $file" "$VALIDATION_ERROR"
        return $VALIDATION_ERROR
    fi

    log_info "Deployer configuration file validated successfully"
    return $SUCCESS
}

function validate_library_configuration_file() {
    local file="$1"

    log_info "Validating library configuration file: $file"

    if [[ ! -f "$file" ]]; then
        display_error "Missing File" "Library configuration file not found: $file" "$FILE_ERROR"
        echo "##vso[task.logissue type=error]File LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME was not found."
        return $FILE_ERROR
    fi

    # Validate file is readable
    if [[ ! -r "$file" ]]; then
        display_error "File Access" "Library configuration file not readable: $file" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Validate file content structure (basic check)
    if ! validate_terraform_configuration_structure "$file"; then
        display_error "File Content" "Library configuration file structure invalid: $file" "$VALIDATION_ERROR"
        return $VALIDATION_ERROR
    fi

    log_info "Library configuration file validated successfully"
    return $SUCCESS
}

function convert_files_to_unix_format() {
    local deployer_file="$1"
    local library_file="$2"

    log_info "Converting configuration files to Unix format"

    # Convert deployer file
    if ! dos2unix -q "$deployer_file" 2>/dev/null; then
        log_warn "Failed to convert deployer file to Unix format: $deployer_file"
    fi

    # Convert library file
    if ! dos2unix -q "$library_file" 2>/dev/null; then
        log_warn "Failed to convert library file to Unix format: $library_file"
    fi

    log_info "File format conversion completed"
    return $SUCCESS
}

function validate_terraform_configuration_structure() {
    local config_file="$1"

    log_debug "Validating Terraform configuration structure: $config_file"

    # Basic structure validation - check for common Terraform patterns
    if ! grep -q "=" "$config_file" 2>/dev/null; then
        log_warn "Configuration file appears to be empty or malformed: $config_file"
        return $VALIDATION_WARNING
    fi

    # Check for suspicious content that might indicate corruption
    if grep -q "^Binary file" "$config_file" 2>/dev/null; then
        log_error "Configuration file appears to be binary: $config_file"
        return $VALIDATION_ERROR
    fi

    log_debug "Terraform configuration structure validation passed"
    return $SUCCESS
}
# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

log_info "Validation functions module loaded successfully"
log_debug "Backward compatibility functions available for legacy scripts"
