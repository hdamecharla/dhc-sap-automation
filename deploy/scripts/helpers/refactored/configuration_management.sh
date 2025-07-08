#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Configuration Management Module - Centralized Settings and Environment Management
# This module provides centralized configuration management for the SAP deployment
# automation framework, including environment-specific settings, feature flags,
# and configuration validation

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
# CONFIGURATION CONSTANTS
# =============================================================================

# Configuration file locations
declare -gr SDAF_CONFIG_DIR="${SDAF_CONFIG_DIR:-${HOME}/.sdaf}"
declare -gr SDAF_GLOBAL_CONFIG="${SDAF_CONFIG_DIR}/config.json"
declare -gr SDAF_USER_CONFIG="${SDAF_CONFIG_DIR}/user.json"
declare -gr SDAF_ENV_CONFIG_DIR="${SDAF_CONFIG_DIR}/environments"

# Configuration schema version
declare -gr CONFIG_SCHEMA_VERSION="2.0.0"

# Default configuration values
declare -gr DEFAULT_LOG_LEVEL="INFO"
declare -gr DEFAULT_TERRAFORM_PARALLELISM="10"
declare -gr DEFAULT_AZURE_TIMEOUT="300"
declare -gr DEFAULT_RETRY_ATTEMPTS="3"

# Configuration categories
# shellcheck disable=SC2034
declare -ga CONFIG_CATEGORIES=(
    "logging"
    "terraform"
    "azure"
    "performance"
    "security"
    "features"
)

# =============================================================================
# CONFIGURATION INITIALIZATION
# =============================================================================

############################################################################################
# Initialize configuration system                                                         #
# Arguments:                                                                              #
#   $1 - Force initialization (true/false) - default: false                             #
# Returns:                                                                                #
#   SUCCESS if initialization complete, FILE_ERROR on failure                           #
# Usage:                                                                                  #
#   initialize_configuration_system                                                      #
#   initialize_configuration_system "true"                                              #
############################################################################################
# shellcheck disable=SC2120
function initialize_configuration_system() {
    local force_init="${1:-false}"

    log_info "Initializing SDAF configuration system"

    # Create configuration directory structure
    if ! _create_config_directories; then
        log_error "Failed to create configuration directories"
        return $FILE_ERROR
    fi

    # Initialize global configuration if it doesn't exist or force is enabled
    if [[ "$force_init" == "true" || ! -f "$SDAF_GLOBAL_CONFIG" ]]; then
        if ! _create_default_global_config; then
            log_error "Failed to create default global configuration"
            return $FILE_ERROR
        fi
    fi

    # Initialize user configuration if it doesn't exist
    if [[ ! -f "$SDAF_USER_CONFIG" ]]; then
        if ! _create_default_user_config; then
            log_error "Failed to create default user configuration"
            return $FILE_ERROR
        fi
    fi

    # Validate configuration files
    if ! validate_configuration_files; then
        log_error "Configuration validation failed"
        return $GENERAL_ERROR
    fi

    log_info "Configuration system initialized successfully"
    return $SUCCESS
}

############################################################################################
# Create configuration directory structure                                                #
############################################################################################
function _create_config_directories() {
    local directories=(
        "$SDAF_CONFIG_DIR"
        "$SDAF_ENV_CONFIG_DIR"
        "${SDAF_CONFIG_DIR}/templates"
        "${SDAF_CONFIG_DIR}/backups"
        "${SDAF_CONFIG_DIR}/logs"
    )

    for dir in "${directories[@]}"; do
        if ! create_directory_safe "$dir" "700" "true"; then
            log_error "Failed to create directory: $dir"
            return $FILE_ERROR
        fi
    done

    return $SUCCESS
}

############################################################################################
# Create default global configuration                                                     #
############################################################################################
function _create_default_global_config() {
    log_debug "Creating default global configuration"

    local global_config
    global_config=$(jq -n \
        --arg schema_version "$CONFIG_SCHEMA_VERSION" \
        --arg created_date "$(date -Iseconds)" \
        --arg log_level "$DEFAULT_LOG_LEVEL" \
        --argjson terraform_parallelism "$DEFAULT_TERRAFORM_PARALLELISM" \
        --argjson azure_timeout "$DEFAULT_AZURE_TIMEOUT" \
        --argjson retry_attempts "$DEFAULT_RETRY_ATTEMPTS" \
        '{
            schema_version: $schema_version,
            created_date: $created_date,
            last_updated: $created_date,
            configuration: {
                logging: {
                    level: $log_level,
                    enable_file_logging: true,
                    enable_performance_logging: true,
                    log_rotation_size_mb: 100,
                    log_retention_days: 30
                },
                terraform: {
                    parallelism: $terraform_parallelism,
                    timeout_seconds: 1800,
                    enable_state_backup: true,
                    auto_retry_on_failure: true,
                    plan_timeout_seconds: 300
                },
                azure: {
                    timeout_seconds: $azure_timeout,
                    retry_attempts: $retry_attempts,
                    enable_msi_fallback: true,
                    validate_subscriptions: true,
                    cache_authentication: true
                },
                performance: {
                    enable_monitoring: true,
                    enable_caching: true,
                    cache_ttl_seconds: 300,
                    performance_threshold_warning: 5.0,
                    performance_threshold_critical: 10.0
                },
                security: {
                    enable_input_sanitization: true,
                    enable_parameter_validation: true,
                    require_secure_connections: true,
                    audit_function_calls: true
                },
                features: {
                    use_refactored_display: true,
                    use_refactored_validation: true,
                    use_refactored_utilities: true,
                    use_refactored_terraform: true,
                    use_refactored_azure: true,
                    enable_deprecation_warnings: true
                }
            }
        }')

    if echo "$global_config" > "$SDAF_GLOBAL_CONFIG"; then
        log_debug "Global configuration created: $SDAF_GLOBAL_CONFIG"
        return $SUCCESS
    else
        log_error "Failed to write global configuration file"
        return $FILE_ERROR
    fi
}

############################################################################################
# Create default user configuration                                                       #
############################################################################################
function _create_default_user_config() {
    log_debug "Creating default user configuration"

    local user_config
    user_config=$(jq -n \
        --arg schema_version "$CONFIG_SCHEMA_VERSION" \
        --arg created_date "$(date -Iseconds)" \
        --arg username "${USER:-unknown}" \
        '{
            schema_version: $schema_version,
            created_date: $created_date,
            last_updated: $created_date,
            user_info: {
                username: $username,
                default_environment: "dev",
                preferred_azure_region: "eastus",
                preferred_terraform_version: "latest"
            },
            user_preferences: {
                display: {
                    banner_width: 80,
                    color_output: true,
                    verbose_errors: true
                },
                automation: {
                    auto_approve_safe_operations: false,
                    enable_dry_run_by_default: true,
                    create_backups_automatically: true
                }
            },
            environments: {}
        }')

    if echo "$user_config" > "$SDAF_USER_CONFIG"; then
        log_debug "User configuration created: $SDAF_USER_CONFIG"
        return $SUCCESS
    else
        log_error "Failed to write user configuration file"
        return $FILE_ERROR
    fi
}

# =============================================================================
# CONFIGURATION ACCESS FUNCTIONS
# =============================================================================

############################################################################################
# Get configuration value                                                                 #
# Arguments:                                                                              #
#   $1 - Configuration path (dot notation, e.g., "terraform.parallelism")               #
#   $2 - Configuration scope (global, user, environment) - default: global              #
#   $3 - Environment name (required if scope is environment)                            #
#   $4 - Default value if not found                                                      #
# Returns:                                                                                #
#   SUCCESS and outputs value, PARAM_ERROR if not found and no default                 #
# Usage:                                                                                  #
#   parallelism=$(get_config_value "terraform.parallelism")                             #
#   region=$(get_config_value "azure.default_region" "user")                            #
############################################################################################
function get_config_value() {
    if ! validate_function_params "get_config_value" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local config_path="${1:-}"
    local scope="${2:-global}"
    local environment="${3:-}"
    local default_value="${4:-}"

    log_debug "Getting config value: $config_path (scope: $scope)"

    local config_file
    case "$scope" in
        global)
            config_file="$SDAF_GLOBAL_CONFIG"
            ;;
        user)
            config_file="$SDAF_USER_CONFIG"
            ;;
        environment)
            if [[ -z "$environment" ]]; then
                log_error "Environment name required for environment scope"
                return $PARAM_ERROR
            fi
            config_file="${SDAF_ENV_CONFIG_DIR}/${environment}.json"
            ;;
        *)
            log_error "Invalid configuration scope: $scope"
            return $PARAM_ERROR
            ;;
    esac

    # Check if configuration file exists
    if [[ ! -f "$config_file" ]]; then
        log_debug "Configuration file not found: $config_file"
        if [[ -n "$default_value" ]]; then
            echo "$default_value"
            return $SUCCESS
        else
            return $PARAM_ERROR
        fi
    fi

    # Extract value using jq
    local value
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required for configuration management"
        return $DEPENDENCY_ERROR
    fi

    value=$(jq -r ".configuration.${config_path} // empty" "$config_file" 2>/dev/null)

    if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$value"
        return $SUCCESS
    elif [[ -n "$default_value" ]]; then
        echo "$default_value"
        return $SUCCESS
    else
        log_debug "Configuration value not found: $config_path"
        return $PARAM_ERROR
    fi
}

############################################################################################
# Set configuration value                                                                 #
# Arguments:                                                                              #
#   $1 - Configuration path (dot notation)                                               #
#   $2 - Value to set                                                                    #
#   $3 - Configuration scope (global, user, environment) - default: user                #
#   $4 - Environment name (required if scope is environment)                            #
# Returns:                                                                                #
#   SUCCESS if value set, FILE_ERROR on failure                                         #
# Usage:                                                                                  #
#   set_config_value "terraform.parallelism" "20" "user"                                #
#   set_config_value "azure.subscription_id" "$sub_id" "environment" "prod"             #
############################################################################################
function set_config_value() {
    if ! validate_function_params "set_config_value" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local config_path="${1:-}"
    local value="${2:-}"
    local scope="${3:-user}"
    local environment="${4:-}"

    log_info "Setting config value: $config_path = $value (scope: $scope)"

    local config_file
    case "$scope" in
        global)
            config_file="$SDAF_GLOBAL_CONFIG"
            ;;
        user)
            config_file="$SDAF_USER_CONFIG"
            ;;
        environment)
            if [[ -z "$environment" ]]; then
                log_error "Environment name required for environment scope"
                return $PARAM_ERROR
            fi
            config_file="${SDAF_ENV_CONFIG_DIR}/${environment}.json"
            ;;
        *)
            log_error "Invalid configuration scope: $scope"
            return $PARAM_ERROR
            ;;
    esac

    # Create environment config if it doesn't exist
    if [[ "$scope" == "environment" && ! -f "$config_file" ]]; then
        if ! _create_environment_config "$environment"; then
            log_error "Failed to create environment configuration: $environment"
            return $FILE_ERROR
        fi
    fi

    # Create backup before modification
    if ! _backup_config_file "$config_file"; then
        log_warn "Failed to create configuration backup"
    fi

    # Update configuration using jq
    local temp_file="${config_file}.tmp"

    # Determine if value should be treated as a number, boolean, or string
    local jq_value
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        # Numeric value
        jq_value="$value"
    elif [[ "$value" == "true" || "$value" == "false" ]]; then
        # Boolean value
        jq_value="$value"
    else
        # String value
        jq_value="\"$value\""
    fi

    if jq ".configuration.${config_path} = $jq_value | .last_updated = \"$(date -Iseconds)\"" "$config_file" > "$temp_file"; then
        if mv "$temp_file" "$config_file"; then
            log_debug "Configuration updated successfully"
            return $SUCCESS
        else
            log_error "Failed to move temporary configuration file"
            rm -f "$temp_file"
            return $FILE_ERROR
        fi
    else
        log_error "Failed to update configuration with jq"
        rm -f "$temp_file"
        return $FILE_ERROR
    fi
}

# =============================================================================
# ENVIRONMENT MANAGEMENT FUNCTIONS
# =============================================================================

############################################################################################
# Create environment configuration                                                        #
# Arguments:                                                                              #
#   $1 - Environment name                                                                #
#   $2 - Template name (optional, default: "default")                                   #
# Returns:                                                                                #
#   SUCCESS if created, FILE_ERROR on failure                                           #
# Usage:                                                                                  #
#   create_environment_config "production" "azure-prod"                                 #
############################################################################################
function create_environment_config() {
    if ! validate_function_params "create_environment_config" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local env_name="${1:-}"
    local template="${2:-default}"

    log_info "Creating environment configuration: $env_name"

    # Validate environment name
    if ! _validate_environment_name "$env_name"; then
        log_error "Invalid environment name: $env_name"
        return $PARAM_ERROR
    fi

    local env_config_file="${SDAF_ENV_CONFIG_DIR}/${env_name}.json"

    # Check if environment already exists
    if [[ -f "$env_config_file" ]]; then
        log_warn "Environment configuration already exists: $env_name"
        return $SUCCESS
    fi

    # Create environment configuration from template
    if ! _create_environment_config "$env_name" "$template"; then
        log_error "Failed to create environment configuration"
        return $FILE_ERROR
    fi

    log_info "Environment configuration created: $env_name"
    return $SUCCESS
}

############################################################################################
# List available environments                                                             #
# Arguments:                                                                              #
#   $1 - Output format (text, json) - default: text                                     #
# Returns:                                                                                #
#   SUCCESS and outputs environment list                                                 #
# Usage:                                                                                  #
#   list_environments                                                                    #
#   list_environments "json"                                                             #
############################################################################################
function list_environments() {
    local output_format="${1:-text}"

    log_debug "Listing environments in format: $output_format"

    # Find all environment configuration files
    local env_files=()
    if [[ -d "$SDAF_ENV_CONFIG_DIR" ]]; then
        while IFS= read -r -d '' file; do
            env_files+=("$(basename "$file" .json)")
        done < <(find "$SDAF_ENV_CONFIG_DIR" -name "*.json" -type f -print0 2>/dev/null)
    fi

    case "$output_format" in
        text)
            if [[ ${#env_files[@]} -eq 0 ]]; then
                echo "No environments configured."
            else
                echo "Available environments:"
                for env in "${env_files[@]}"; do
                    echo "  - $env"
                done
            fi
            ;;
        json)
            printf '%s\n' "${env_files[@]}" | jq -R . | jq -s .
            ;;
        *)
            log_error "Invalid output format: $output_format"
            return $PARAM_ERROR
            ;;
    esac

    return $SUCCESS
}

############################################################################################
# Switch to environment configuration                                                     #
# Arguments:                                                                              #
#   $1 - Environment name                                                                #
# Returns:                                                                                #
#   SUCCESS if switched, PARAM_ERROR if environment not found                           #
# Usage:                                                                                  #
#   switch_environment "production"                                                      #
############################################################################################
function switch_environment() {
    if ! validate_function_params "switch_environment" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local env_name="${1:-}"

    log_info "Switching to environment: $env_name"

    local env_config_file="${SDAF_ENV_CONFIG_DIR}/${env_name}.json"

    # Check if environment exists
    if [[ ! -f "$env_config_file" ]]; then
        log_error "Environment configuration not found: $env_name"
        return $PARAM_ERROR
    fi

    # Set current environment in user configuration
    if set_config_value "user_info.current_environment" "$env_name" "user"; then
        # Export environment variables from configuration
        _export_environment_variables "$env_name"

        log_info "Switched to environment: $env_name"
        display_success "Environment Switch" "Successfully switched to environment: $env_name"
        return $SUCCESS
    else
        log_error "Failed to update current environment in user configuration"
        return $FILE_ERROR
    fi
}

# =============================================================================
# CONFIGURATION VALIDATION FUNCTIONS
# =============================================================================

############################################################################################
# Validate all configuration files                                                        #
# Arguments: None                                                                         #
# Returns:                                                                                #
#   SUCCESS if all valid, GENERAL_ERROR if validation fails                             #
# Usage:                                                                                  #
#   validate_configuration_files                                                         #
############################################################################################
function validate_configuration_files() {
    log_info "Validating configuration files"

    local validation_errors=0
    local files_validated=0

    # Validate global configuration
    if [[ -f "$SDAF_GLOBAL_CONFIG" ]]; then
        if _validate_config_file "$SDAF_GLOBAL_CONFIG" "global"; then
            log_debug "✅ Global configuration valid"
        else
            log_error "❌ Global configuration invalid"
            ((validation_errors++))
        fi
        ((files_validated++))
    fi

    # Validate user configuration
    if [[ -f "$SDAF_USER_CONFIG" ]]; then
        if _validate_config_file "$SDAF_USER_CONFIG" "user"; then
            log_debug "✅ User configuration valid"
        else
            log_error "❌ User configuration invalid"
            ((validation_errors++))
        fi
        ((files_validated++))
    fi

    # Validate environment configurations
    if [[ -d "$SDAF_ENV_CONFIG_DIR" ]]; then
        while IFS= read -r -d '' env_file; do
            local env_name
            env_name=$(basename "$env_file" .json)

            if _validate_config_file "$env_file" "environment"; then
                log_debug "✅ Environment configuration valid: $env_name"
            else
                log_error "❌ Environment configuration invalid: $env_name"
                ((validation_errors++))
            fi
            ((files_validated++))
        done < <(find "$SDAF_ENV_CONFIG_DIR" -name "*.json" -type f -print0 2>/dev/null)
    fi

    log_info "Configuration validation complete: $files_validated files, $validation_errors errors"

    if [[ $validation_errors -eq 0 ]]; then
        return $SUCCESS
    else
        return $GENERAL_ERROR
    fi
}

############################################################################################
# Apply configuration to current session                                                  #
# Arguments:                                                                              #
#   $1 - Environment name (optional, uses current environment if not specified)         #
# Returns:                                                                                #
#   SUCCESS if applied, PARAM_ERROR on failure                                          #
# Usage:                                                                                  #
#   apply_configuration "production"                                                     #
#   apply_configuration  # Uses current environment                                     #
############################################################################################
# shellcheck disable=SC2120
function apply_configuration() {
    local env_name="${1:-}"

    log_info "Applying configuration to current session"

    # Get current environment if not specified
    if [[ -z "$env_name" ]]; then
        env_name=$(get_config_value "user_info.current_environment" "user" "" "dev")
    fi

    log_debug "Applying configuration for environment: $env_name"

    # Apply global configuration
    _apply_global_config

    # Apply user configuration
    _apply_user_config

    # Apply environment configuration if it exists
    if [[ -f "${SDAF_ENV_CONFIG_DIR}/${env_name}.json" ]]; then
        _apply_environment_config "$env_name"
    fi

    log_info "Configuration applied successfully"
    return $SUCCESS
}

# =============================================================================
# INTERNAL HELPER FUNCTIONS
# =============================================================================

############################################################################################
# Create environment configuration from template                                          #
############################################################################################
function _create_environment_config() {
    local env_name="$1"
    local template="${2:-default}"

    local env_config_file="${SDAF_ENV_CONFIG_DIR}/${env_name}.json"

    local env_config
    env_config=$(jq -n \
        --arg schema_version "$CONFIG_SCHEMA_VERSION" \
        --arg created_date "$(date -Iseconds)" \
        --arg env_name "$env_name" \
        --arg template "$template" \
        '{
            schema_version: $schema_version,
            created_date: $created_date,
            last_updated: $created_date,
            environment_info: {
                name: $env_name,
                template: $template,
                description: "",
                azure_region: "eastus",
                deployment_mode: "incremental"
            },
            configuration: {
                logging: {
                    level: "INFO",
                    enable_debug: false
                },
                terraform: {
                    parallelism: 10,
                    workspace: $env_name
                },
                azure: {
                    subscription_id: "",
                    tenant_id: "",
                    default_resource_group: "",
                    default_location: "eastus"
                },
                security: {
                    require_confirmation: true,
                    enable_audit_logging: true
                }
            }
        }')

    if echo "$env_config" > "$env_config_file"; then
        return $SUCCESS
    else
        return $FILE_ERROR
    fi
}

############################################################################################
# Validate environment name format                                                        #
############################################################################################
function _validate_environment_name() {
    local env_name="$1"

    # Environment names should be alphanumeric with optional hyphens/underscores
    if [[ "$env_name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9_-]*[a-zA-Z0-9])?$ ]] && [[ ${#env_name} -le 30 ]]; then
        return $SUCCESS
    else
        return $PARAM_ERROR
    fi
}

############################################################################################
# Validate individual configuration file                                                  #
############################################################################################
function _validate_config_file() {
    local config_file="$1"
    local config_type="$2"

    # Check if file exists and is readable
    if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
        log_error "Configuration file not accessible: $config_file"
        return $GENERAL_ERROR
    fi

    # Validate JSON syntax
    if ! jq . "$config_file" >/dev/null 2>&1; then
        log_error "Invalid JSON syntax in configuration file: $config_file"
        return $GENERAL_ERROR
    fi

    # Validate schema version
    local schema_version
    schema_version=$(jq -r '.schema_version // "unknown"' "$config_file" 2>/dev/null)

    if [[ "$schema_version" != "$CONFIG_SCHEMA_VERSION" ]]; then
        log_warn "Configuration schema version mismatch: expected $CONFIG_SCHEMA_VERSION, found $schema_version"
    fi

    # Type-specific validation
    case "$config_type" in
        global)
            _validate_global_config_schema "$config_file"
            ;;
        user)
            _validate_user_config_schema "$config_file"
            ;;
        environment)
            _validate_environment_config_schema "$config_file"
            ;;
    esac

    return $?
}

############################################################################################
# Validate global configuration schema                                                    #
############################################################################################
function _validate_global_config_schema() {
    local config_file="$1"

    # Check required sections exist
    local required_sections=("logging" "terraform" "azure" "performance" "security" "features")

    for section in "${required_sections[@]}"; do
        if ! jq -e ".configuration.$section" "$config_file" >/dev/null 2>&1; then
            log_error "Missing required configuration section: $section"
            return $GENERAL_ERROR
        fi
    done

    return $SUCCESS
}

############################################################################################
# Validate user configuration schema                                                      #
############################################################################################
function _validate_user_config_schema() {
    local config_file="$1"

    # Check required sections exist
    if ! jq -e '.user_info' "$config_file" >/dev/null 2>&1; then
        log_error "Missing required section: user_info"
        return $GENERAL_ERROR
    fi

    if ! jq -e '.user_preferences' "$config_file" >/dev/null 2>&1; then
        log_error "Missing required section: user_preferences"
        return $GENERAL_ERROR
    fi

    return $SUCCESS
}

############################################################################################
# Validate environment configuration schema                                               #
############################################################################################
function _validate_environment_config_schema() {
    local config_file="$1"

    # Check required sections exist
    if ! jq -e '.environment_info' "$config_file" >/dev/null 2>&1; then
        log_error "Missing required section: environment_info"
        return $GENERAL_ERROR
    fi

    return $SUCCESS
}

############################################################################################
# Create backup of configuration file                                                     #
############################################################################################
function _backup_config_file() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        return $SUCCESS  # Nothing to backup
    fi

    local backup_dir="${SDAF_CONFIG_DIR}/backups"
    local filename
    filename=$(basename "$config_file")
    local backup_file
		backup_file="${backup_dir}/${filename}.backup.$(date +%Y%m%d_%H%M%S)"

    if cp "$config_file" "$backup_file" 2>/dev/null; then
        log_debug "Configuration backup created: $backup_file"
        return $SUCCESS
    else
        return $FILE_ERROR
    fi
}

############################################################################################
# Export environment variables from configuration                                         #
############################################################################################
function _export_environment_variables() {
    local env_name="$1"

    log_debug "Exporting environment variables for: $env_name"

    # Set SDAF environment variables
    export SDAF_CURRENT_ENVIRONMENT="$env_name"

    # Apply feature flags from configuration
    local use_refactored_display use_refactored_validation use_refactored_utilities
    local use_refactored_terraform use_refactored_azure enable_deprecation_warnings

    use_refactored_display=$(get_config_value "features.use_refactored_display" "global" "" "true")
    use_refactored_validation=$(get_config_value "features.use_refactored_validation" "global" "" "true")
    use_refactored_utilities=$(get_config_value "features.use_refactored_utilities" "global" "" "true")
    use_refactored_terraform=$(get_config_value "features.use_refactored_terraform" "global" "" "true")
    use_refactored_azure=$(get_config_value "features.use_refactored_azure" "global" "" "true")
    enable_deprecation_warnings=$(get_config_value "features.enable_deprecation_warnings" "global" "" "true")

    export USE_REFACTORED_DISPLAY="$use_refactored_display"
    export USE_REFACTORED_VALIDATION="$use_refactored_validation"
    export USE_REFACTORED_UTILITIES="$use_refactored_utilities"
    export USE_REFACTORED_TERRAFORM="$use_refactored_terraform"
    export USE_REFACTORED_AZURE="$use_refactored_azure"
    export ENABLE_DEPRECATION_WARNINGS="$enable_deprecation_warnings"

    # Apply performance settings
    local perf_monitoring perf_caching
    perf_monitoring=$(get_config_value "performance.enable_monitoring" "global" "" "true")
    perf_caching=$(get_config_value "performance.enable_caching" "global" "" "true")

    export PERF_MONITORING_ENABLED="$perf_monitoring"
    export ENABLE_FUNCTION_CACHING="$perf_caching"
}

############################################################################################
# Apply global configuration settings                                                     #
############################################################################################
function _apply_global_config() {
    log_debug "Applying global configuration"

    # Apply logging configuration
    local log_level
    log_level=$(get_config_value "logging.level" "global" "" "$DEFAULT_LOG_LEVEL")
    export SDAF_LOG_LEVEL="$log_level"

    # Apply Terraform configuration
    local terraform_parallelism
    terraform_parallelism=$(get_config_value "terraform.parallelism" "global" "" "$DEFAULT_TERRAFORM_PARALLELISM")
    export TF_PARALLELISM="$terraform_parallelism"

    # Apply Azure configuration
    local azure_timeout
    azure_timeout=$(get_config_value "azure.timeout_seconds" "global" "" "$DEFAULT_AZURE_TIMEOUT")
    export AZ_CLI_TIMEOUT="$azure_timeout"
}

############################################################################################
# Apply user configuration settings                                                       #
############################################################################################
function _apply_user_config() {
    log_debug "Applying user configuration"

    # Apply display preferences
    local banner_width color_output
    banner_width=$(get_config_value "user_preferences.display.banner_width" "user" "" "80")
    color_output=$(get_config_value "user_preferences.display.color_output" "user" "" "true")

    export SDAF_BANNER_WIDTH="$banner_width"
    export SDAF_COLOR_OUTPUT="$color_output"
}

############################################################################################
# Apply environment-specific configuration                                                #
############################################################################################
function _apply_environment_config() {
    local env_name="$1"

    log_debug "Applying environment configuration: $env_name"

    # Apply environment-specific Azure settings
    local subscription_id tenant_id default_location
    subscription_id=$(get_config_value "azure.subscription_id" "environment" "$env_name")
    tenant_id=$(get_config_value "azure.tenant_id" "environment" "$env_name")
    default_location=$(get_config_value "azure.default_location" "environment" "$env_name")

    if [[ -n "$subscription_id" ]]; then
        export ARM_SUBSCRIPTION_ID="$subscription_id"
    fi

    if [[ -n "$tenant_id" ]]; then
        export ARM_TENANT_ID="$tenant_id"
    fi

    if [[ -n "$default_location" ]]; then
        export SDAF_DEFAULT_LOCATION="$default_location"
    fi
}

#==============================================================================
# Azure DevOps Variable Group Management
#==============================================================================

function getVariableFromVariableGroup() {
    local variable_group_id="$1"
    local variable_name="$2"
    local environment_file_name="$3"
    local environment_variable_name="$4"
    local variable_value=""
    local sourced_from_file=0

    # Suppress debug output during variable retrieval
    local original_debug_state="$DEBUG"
    DEBUG=false

    # Validate input parameters
    if [[ -z "$variable_group_id" || -z "$variable_name" ]]; then
        log_error "getVariableFromVariableGroup: Missing required parameters"
        DEBUG="$original_debug_state"
        return $PARAM_ERROR
    fi

    # Attempt to get variable from Azure DevOps variable group
    log_debug "Getting variable '$variable_name' from variable group ID: $variable_group_id"

    # Use a more robust query that handles null values properly
    variable_value=$(az pipelines variable-group variable list \
        --group-id "${variable_group_id}" \
        --query "${variable_name}.value" \
        --output tsv 2>/dev/null | grep -v "^DEBUG:" | grep -v "^INFO:" | head -n 1 | xargs || true)

    # Check if variable was found and is not null/empty
    if [[ -z "$variable_value" || "$variable_value" == "null" ]]; then
        log_debug "Variable '$variable_name' not found in variable group or config file"

        # Fallback to environment file if available
        if [[ -n "$environment_file_name" && -f "$environment_file_name" && -n "$environment_variable_name" ]]; then
            log_debug "Attempting to read from environment file: $environment_file_name"
            variable_value=$(grep "^$environment_variable_name" "${environment_file_name}" 2>/dev/null | \
                awk -F'=' '{print $2}' | tr -d ' \t\n\r\f"' || true)

            if [[ -n "$variable_value" ]]; then
                sourced_from_file=1
                export sourced_from_file
                log_debug "Variable '$variable_name' found in environment file with value: $variable_value"
            fi
        fi
    else
        log_debug "Variable '$variable_name' found in variable group with value: $variable_value"
    fi

    # Restore debug state
    DEBUG="$original_debug_state"

    # Return the value (may be empty)
    echo "$variable_value"
    return 0
}

function saveVariableInVariableGroup() {
    local variable_group_id="$1"
    local variable_name="$2"
    local variable_value="$3"
    local return_code=0

    # Validate input parameters
    if [[ -z "$variable_group_id" || -z "$variable_name" ]]; then
        log_error "saveVariableInVariableGroup: Missing required parameters"
        return $PARAM_ERROR
    fi

    # Handle empty values appropriately
    if [[ -z "$variable_value" ]]; then
        log_warn "saveVariableInVariableGroup: Empty value provided for variable '$variable_name'"
        return 0  # Don't save empty values
    fi

    log_debug "Saving variable '$variable_name' to variable group ID: $variable_group_id"

    # Check if variable already exists
    local existing_value
    existing_value=$(az pipelines variable-group variable list \
        --group-id "${variable_group_id}" \
        --query "${variable_name}.value" \
        --output tsv 2>/dev/null || true)

    if [[ -n "$existing_value" && "$existing_value" != "null" ]]; then
        # Update existing variable
        log_debug "Updating existing variable '$variable_name'"
        if az pipelines variable-group variable update \
            --group-id "${variable_group_id}" \
            --name "${variable_name}" \
            --value "${variable_value}" \
            --output none \
            --only-show-errors 2>/dev/null; then
            log_info "Variable '$variable_name' updated successfully"
            return_code=0
        else
            log_error "Failed to update variable '$variable_name'"
            return_code=$AZURE_ERROR
        fi
    else
        # Create new variable
        log_debug "Creating new variable '$variable_name'"
        if az pipelines variable-group variable create \
            --group-id "${variable_group_id}" \
            --name "${variable_name}" \
            --value "${variable_value}" \
            --output none \
            --only-show-errors 2>/dev/null; then
            log_info "Variable '$variable_name' created successfully"
            return_code=0
        else
            log_error "Failed to create variable '$variable_name'"
            return_code=$AZURE_ERROR
        fi
    fi

    return $return_code
}

# Enhanced variable validation function
function validate_required_variables() {
    local variable_group_id="$1"
    local environment_file="$2"
    local -a missing_variables=()
    local -a required_vars=(
        "ARM_SUBSCRIPTION_ID"
        "ARM_CLIENT_ID"
        "ARM_TENANT_ID"
    )

    log_info "Validating required variables for deployment"

    for var in "${required_vars[@]}"; do
        local value
        value=$(getVariableFromVariableGroup "$variable_group_id" "$var" "$environment_file" "$var" || true)

        if [[ -z "$value" ]]; then
            missing_variables+=("$var")
        fi
    done

    if [[ ${#missing_variables[@]} -gt 0 ]]; then
        log_error "Missing required variables: ${missing_variables[*]}"
        return $VALIDATION_ERROR
    fi

    log_info "All required variables validated successfully"
    return 0
}

# Bootstrap-aware variable handling
function get_variable_with_bootstrap_fallback() {
    local variable_group_id="$1"
    local variable_name="$2"
    local environment_file="$3"
    local environment_variable_name="$4"
    local is_required_for_bootstrap="${5:-false}"

    local value
    value=$(getVariableFromVariableGroup "$variable_group_id" "$variable_name" "$environment_file" "$environment_variable_name" || true)

    # If bootstrap deployment and variable is not required for bootstrap, return empty
    if [[ "$IS_BOOTSTRAP_DEPLOYMENT" == "true" && "$is_required_for_bootstrap" != "true" ]]; then
        if [[ -z "$value" ]]; then
            log_debug "Bootstrap mode: '$variable_name' not required, returning empty"
            return 0
        fi
    fi

    # For non-bootstrap or required variables, validate presence
    if [[ -z "$value" && "$is_required_for_bootstrap" == "true" ]]; then
        log_error "Required variable '$variable_name' is missing"
        return $VALIDATION_ERROR
    fi

    echo "$value"
    return 0
}

#==============================================================================
# Deployment Information Extraction and Management
#==============================================================================

function extract_deployment_info_from_file() {
    local file="$1"
    local key="$2"
    local default_value="$3"

    if [[ -f "$file" ]]; then
        local value
        value=$(grep -m1 "^${key}=" "$file" | awk -F'=' '{print $2}' | xargs 2>/dev/null || echo "$default_value")
        echo "$value"
    else
        echo "$default_value"
    fi
}

function create_deployment_summary() {
    local summary_file="$1"
    local deployment_info="$2"

    log_info "Creating deployment summary: $summary_file"

    cat > "$summary_file" << EOF
# SAP Control Plane Deployment Summary

## Deployment Information
- Environment: ${ENVIRONMENT:-Unknown}
- Location: ${LOCATION:-Unknown}
- Deployment Time: $(date)
- Build Number: ${BUILD_BUILDNUMBER:-Unknown}

## Configuration Files
- Deployer Configuration: ${DEPLOYER_TFVARS_FILENAME:-Unknown}
- Library Configuration: ${LIBRARY_TFVARS_FILENAME:-Unknown}

## Deployment Status
$deployment_info

---
Generated by SAP Deployment Automation Framework
EOF

    log_info "Deployment summary created successfully"
    return $SUCCESS
}

#==============================================================================
# Configuration Path Management
#==============================================================================

function validate_configuration_repository() {
    local config_path="$1"

    log_info "Validating configuration repository: $config_path"

    # Check if directory exists
    if [[ ! -d "$config_path" ]]; then
        display_error "Configuration Repository" "Configuration repository not found: $config_path" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Check if it's a git repository
    if [[ ! -d "$config_path/.git" ]]; then
        display_error "Configuration Repository" "Configuration path is not a git repository: $config_path" "$GIT_ERROR"
        return $GIT_ERROR
    fi

    # Check read/write permissions
    if [[ ! -r "$config_path" ]] || [[ ! -w "$config_path" ]]; then
        display_error "Configuration Repository" "Insufficient permissions for configuration repository: $config_path" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    log_info "Configuration repository validation successful"
    return $SUCCESS
}

function setup_configuration_directory_structure() {
    local base_path="$1"

    log_info "Setting up configuration directory structure"

    # Create automation directory
    local automation_dir="$base_path/.sap_deployment_automation"
    if ! mkdir -p "$automation_dir"; then
        display_error "Directory Creation" "Failed to create automation directory: $automation_dir" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Set appropriate permissions
    chmod 755 "$automation_dir"

    # Create additional subdirectories if needed
    local subdirs=("logs" "state" "temp")
    for subdir in "${subdirs[@]}"; do
        local full_path="$automation_dir/$subdir"
        if ! mkdir -p "$full_path"; then
            log_warn "Failed to create subdirectory: $full_path"
        else
            chmod 755 "$full_path"
        fi
    done

    log_info "Configuration directory structure setup completed"
    return $SUCCESS
}

function normalize_configuration_paths() {
    local base_path="$1"

    log_info "Normalizing configuration paths"

    # Normalize path separators and resolve symlinks
    local normalized_path
    normalized_path=$(realpath "$base_path" 2>/dev/null)

    if [[ -z "$normalized_path" ]]; then
        log_error "Failed to normalize configuration path: $base_path"
        return $FILE_ERROR
    fi

    echo "$normalized_path"
    return $SUCCESS
}

#==============================================================================
# Configuration File Management
#==============================================================================

function backup_configuration_file() {
    local config_file="$1"
    local backup_suffix="${2:-$(date +%Y%m%d_%H%M%S)}"

    log_info "Creating backup of configuration file: $config_file"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Configuration file not found for backup: $config_file"
        return $FILE_WARNING
    fi

    local backup_file="${config_file}.backup_${backup_suffix}"

    if cp "$config_file" "$backup_file"; then
        log_info "Configuration backup created: $backup_file"
        return $SUCCESS
    else
        log_error "Failed to create configuration backup: $backup_file"
        return $FILE_ERROR
    fi
}

function restore_configuration_file() {
    local config_file="$1"
    local backup_file="$2"

    log_info "Restoring configuration file from backup"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return $FILE_ERROR
    fi

    if cp "$backup_file" "$config_file"; then
        log_info "Configuration file restored from backup: $backup_file"
        return $SUCCESS
    else
        log_error "Failed to restore configuration file from backup"
        return $FILE_ERROR
    fi
}

function validate_configuration_file_format() {
    local config_file="$1"
    local expected_format="$2"

    log_debug "Validating configuration file format: $config_file ($expected_format)"

    case "$expected_format" in
        "terraform"|"tfvars")
            # Basic Terraform variable file validation
            if ! grep -q "=" "$config_file" 2>/dev/null; then
                log_error "Configuration file does not contain valid Terraform variables: $config_file"
                return $VALIDATION_ERROR
            fi
            ;;
        "json")
            # JSON format validation
            if ! jq empty "$config_file" 2>/dev/null; then
                log_error "Configuration file is not valid JSON: $config_file"
                return $VALIDATION_ERROR
            fi
            ;;
        "yaml"|"yml")
            # YAML format validation (basic check)
            if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
                log_error "Configuration file is not valid YAML: $config_file"
                return $VALIDATION_ERROR
            fi
            ;;
        *)
            log_warn "Unknown configuration file format: $expected_format"
            return $VALIDATION_WARNING
            ;;
    esac

    log_debug "Configuration file format validation passed"
    return $SUCCESS
}

#==============================================================================
# Environment Configuration Management
#==============================================================================

function load_environment_configuration() {
    local env_file="$1"
    local env_name="${2:-development}"

    log_info "Loading environment configuration: $env_file ($env_name)"

    if [[ ! -f "$env_file" ]]; then
        log_warn "Environment configuration file not found: $env_file"
        return $FILE_WARNING
    fi

    # Source the configuration file
    if source "$env_file"; then
        log_info "Environment configuration loaded successfully"
        return $SUCCESS
    else
        log_error "Failed to load environment configuration: $env_file"
        return $CONFIG_ERROR
    fi
}

function save_environment_configuration() {
    local env_file="$1"
    local config_data="$2"

    log_info "Saving environment configuration: $env_file"

    # Create backup before saving
    if [[ -f "$env_file" ]]; then
        backup_configuration_file "$env_file"
    fi

    # Save new configuration
    if echo "$config_data" > "$env_file"; then
        log_info "Environment configuration saved successfully"
        return $SUCCESS
    else
        log_error "Failed to save environment configuration: $env_file"
        return $CONFIG_ERROR
    fi
}


# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Initialize configuration system if not already done
if [[ ! -f "$SDAF_GLOBAL_CONFIG" ]] && [[ "${SDAF_AUTO_INIT_CONFIG:-true}" == "true" ]]; then
    log_info "Auto-initializing configuration system"
    initialize_configuration_system
fi

# Apply configuration if available
if [[ -f "$SDAF_GLOBAL_CONFIG" ]] && [[ "${SDAF_AUTO_APPLY_CONFIG:-true}" == "true" ]]; then
    apply_configuration >/dev/null 2>&1
fi

log_info "Configuration management module loaded successfully"
log_debug "Configuration directory: $SDAF_CONFIG_DIR"
