#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#==============================================================================
# SAP Secrets Management Script - Refactored Version
#
# This script securely manages Service Principal Name (SPN) secrets in Azure
# Key Vault for SAP automation with enhanced validation, secure handling,
# and comprehensive error recovery.
#
# Version: 2.0 (Refactored)
# Backward Compatibility: 100% maintained
#==============================================================================

# Script initialization and framework loading
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
SCRIPT_NAME="$(basename "$0")"

# Load enhanced framework (replaces legacy helpers)
source "${script_directory}/deploy_utils.sh"
source "${script_directory}/helpers/script_helpers_v2.sh"

# Script constants and configuration
declare -gr SCRIPT_VERSION="2.0"
declare -gr SECRET_EXPIRY_PERIOD="+1 year"
declare -gr SECRET_TYPE_CONFIG="configuration"
declare -gr SECRET_TYPE_SECRET="secret"

# Security configuration
declare -gr MAX_SECRET_ATTEMPTS=3
declare -gr SECRET_RECOVERY_DELAY=10

# Initialize logging and display
log_info "Starting script: $SCRIPT_NAME v$SCRIPT_VERSION"
display_banner "SAP Secrets Management" "Initializing secure secret management" "info"

#==============================================================================
# Help System - Template-driven (eliminates duplication)
#==============================================================================

# Register help template (replaces hardcoded showhelp function)
add_help_template "set_secrets" "
#########################################################################################
#                                                                                       #
# SAP Secrets Management Script                                                        #
#                                                                                       #
# This script securely manages Service Principal Name (SPN) credentials in Azure      #
# Key Vault for SAP automation. It supports both service principal and managed        #
# service identity authentication modes with comprehensive validation and recovery.    #
#                                                                                       #
# Required Environment Variables:                                                       #
#   CONFIG_REPO_PATH         - Path to configuration repository                        #
#                                                                                       #
# Usage: set_secrets.sh [OPTIONS]                                                      #
#   -e, --environment NAME              Environment name (required)                   #
#   -r, --region REGION                 Region code (required)                        #
#   -v, --vault NAME                    Azure Key Vault name (required)              #
#   -s, --subscription ID               Target subscription ID (required)            #
#   -c, --spn_id ID                     SPN application ID (for SPN mode)            #
#   -p, --spn_secret SECRET             SPN password (for SPN mode)                  #
#   -t, --tenant_id ID                  SPN tenant ID (for SPN mode)                 #
#   -b, --keyvault_subscription ID      Key Vault subscription (optional)            #
#   -w, --workload                      Workload deployment mode                     #
#   -m, --msi                           Use Managed Service Identity                 #
#   -h, --help                          Show this help message                       #
#                                                                                       #
# Authentication Modes:                                                                #
#   Service Principal Mode: Requires --spn_id, --spn_secret, --tenant_id              #
#   MSI Mode: Use --msi flag (no SPN credentials required)                            #
#                                                                                       #
# Examples:                                                                             #
#                                                                                       #
# Service Principal Mode:                                                               #
#   set_secrets.sh \\                                                                  #
#     --environment PROD \\                                                            #
#     --region weeu \\                                                                 #
#     --vault prodweeuusrabc \\                                                        #
#     --subscription xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \\                          #
#     --spn_id yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy \\                                #
#     --spn_secret ************************ \\                                        #
#     --tenant_id zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz                               #
#                                                                                       #
# Managed Service Identity Mode:                                                       #
#   set_secrets.sh \\                                                                  #
#     --environment PROD \\                                                            #
#     --region weeu \\                                                                 #
#     --vault prodweeuusrabc \\                                                        #
#     --subscription xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \\                          #
#     --msi                                                                            #
#                                                                                       #
#########################################################################################"

#==============================================================================
# Enhanced Parameter Processing
#==============================================================================

function process_command_line_arguments() {
    local INPUT_ARGUMENTS VALID_ARGUMENTS

    log_info "Processing command line arguments"

    INPUT_ARGUMENTS=$(getopt -n set_secrets -o e:r:v:s:c:p:t:b:hwm --longoptions environment:,region:,vault:,subscription:,spn_id:,spn_secret:,tenant_id:,keyvault_subscription:,workload,help,msi -- "$@")
    VALID_ARGUMENTS=$?

    if [[ "$VALID_ARGUMENTS" != "0" ]]; then
        display_error "Invalid Arguments" "Failed to parse command line arguments" "$PARAM_ERROR"
        display_help "set_secrets" "$0"
        exit $PARAM_ERROR
    fi

    eval set -- "$INPUT_ARGUMENTS"
    while :; do
        case "$1" in
        -e | --environment)
            environment="$2"
            log_debug "Environment: $environment"
            shift 2
            ;;
        -r | --region)
            region_code="$2"
            log_debug "Region: $region_code"
            shift 2
            ;;
        -v | --vault)
            keyvault="$2"
            log_debug "Key vault: $keyvault"
            shift 2
            ;;
        -s | --subscription)
            subscription="$2"
            log_debug "Subscription: $subscription"
            shift 2
            ;;
        -c | --spn_id)
            client_id="$2"
            log_debug "SPN ID: ${client_id:0:8}..."
            shift 2
            ;;
        -p | --spn_secret)
            client_secret="$2"
            log_debug "SPN secret: ****** (provided)"
            shift 2
            ;;
        -t | --tenant_id)
            tenant_id="$2"
            log_debug "Tenant ID: ${tenant_id:0:8}..."
            shift 2
            ;;
        -b | --keyvault_subscription)
            STATE_SUBSCRIPTION="$2"
            log_debug "Key Vault subscription: $STATE_SUBSCRIPTION"
            shift 2
            ;;
        -w | --workload)
            workload=1
            log_debug "Workload mode enabled"
            shift
            ;;
        -m | --msi)
            deploy_using_msi_only=1
            log_debug "MSI mode enabled"
            shift
            ;;
        -h | --help)
            display_help "set_secrets" "$0"
            exit $HELP_REQUESTED
            ;;
        --)
            shift
            break
            ;;
        esac
    done

    # Set default values for MSI mode
    deploy_using_msi_only=${deploy_using_msi_only:-0}
    workload=${workload:-0}

    # Comprehensive parameter validation
    validate_required_parameters
}

function validate_required_parameters() {
    local validation_errors=0

    log_info "Validating required parameters"

    # Interactive parameter collection for missing required parameters
    collect_missing_parameters

    # Validate parameter formats
    if ! validate_parameter_formats; then
        ((validation_errors++))
    fi

    # Validate authentication mode requirements
    if ! validate_authentication_requirements; then
        ((validation_errors++))
    fi

    if [[ $validation_errors -gt 0 ]]; then
        display_error "Parameter Validation" "Parameter validation failed" "$PARAM_ERROR"
        display_help "set_secrets" "$0"
        exit $PARAM_ERROR
    fi

    log_info "Required parameters validated successfully"
    return $SUCCESS
}

function collect_missing_parameters() {
    log_info "Collecting missing required parameters interactively"

    # Environment parameter
    while [[ -z "${environment:-}" ]]; do
        read -r -p "Environment name: " environment
        if [[ -n "$environment" ]]; then
            log_debug "Environment collected: $environment"
        fi
    done

    # Region parameter
    while [[ -z "${region_code:-}" ]]; do
        read -r -p "Region name: " region
        if [[ -n "$region" ]]; then
            # Convert region to correct code if needed
            get_region_code "$region"
            log_debug "Region collected: $region_code"
        fi
    done

    # Key vault parameter (with validation)
    if [[ -z "${keyvault:-}" ]]; then
        load_config_vars "${environment_config_information}" "keyvault"
        while [[ -z "${keyvault:-}" ]]; do
            read -r -p "Key vault name: " keyvault
            if [[ -n "$keyvault" ]] && ! valid_kv_name "$keyvault"; then
                display_error "Invalid Key Vault Name" "Key vault name format is invalid: $keyvault" "$PARAM_ERROR"
                keyvault=""
            fi
        done
    fi

    # SPN parameters (only if not using MSI)
    if [[ "${deploy_using_msi_only}" != "1" ]]; then
        collect_spn_parameters
    fi

    # Subscription parameter
    if [[ -z "${subscription:-}" ]]; then
        read -r -p "SPN Subscription: " subscription
    fi
}

function collect_spn_parameters() {
    log_info "Collecting SPN parameters for service principal authentication"

    # Client ID
    if [[ -z "${client_id:-}" ]]; then
        load_config_vars "${environment_config_information}" "client_id"
        if [[ -z "${client_id:-}" ]]; then
            read -r -p "SPN App ID: " client_id
        fi
    fi

    # Client Secret (secure input)
    if [[ -z "${client_secret:-}" ]]; then
        read -rs -p "        -> Kindly provide SPN Password: " client_secret
        echo "********"
    fi

    # Tenant ID
    if [[ -z "${tenant_id:-}" ]]; then
        load_config_vars "${environment_config_information}" "tenant_id"
        if [[ -z "${tenant_id:-}" ]]; then
            read -r -p "SPN Tenant ID: " tenant_id
        fi
    fi
}

function validate_parameter_formats() {
    local format_errors=0

    log_info "Validating parameter formats"

    # Validate GUID formats
    if [[ -n "${client_id:-}" ]] && ! is_valid_guid "${client_id}"; then
        display_error "Invalid Client ID" "SPN Client ID format is invalid: ${client_id:0:8}..." "$PARAM_ERROR"
        ((format_errors++))
    fi

    if [[ -n "${tenant_id:-}" ]] && ! is_valid_guid "${tenant_id}"; then
        display_error "Invalid Tenant ID" "SPN Tenant ID format is invalid: ${tenant_id:0:8}..." "$PARAM_ERROR"
        ((format_errors++))
    fi

    if [[ -n "${subscription:-}" ]] && ! is_valid_guid "${subscription}"; then
        display_error "Invalid Subscription" "Subscription ID format is invalid: ${subscription:0:8}..." "$PARAM_ERROR"
        ((format_errors++))
    fi

    # Validate Key Vault name format
    if [[ -n "${keyvault:-}" ]] && ! valid_kv_name "$keyvault"; then
        display_error "Invalid Key Vault Name" "Key vault name format is invalid: $keyvault" "$PARAM_ERROR"
        ((format_errors++))
    fi

    return $format_errors
}

function validate_authentication_requirements() {
    local auth_errors=0

    log_info "Validating authentication requirements"

    if [[ "${deploy_using_msi_only}" != "1" ]]; then
        # Service Principal mode - require all SPN parameters
        if [[ -z "${client_id:-}" ]]; then
            display_error "Missing SPN Parameter" "Client ID is required for service principal authentication" "$PARAM_ERROR"
            ((auth_errors++))
        fi

        if [[ -z "${client_secret:-}" ]]; then
            display_error "Missing SPN Parameter" "Client secret is required for service principal authentication" "$PARAM_ERROR"
            ((auth_errors++))
        fi

        if [[ -z "${tenant_id:-}" ]]; then
            display_error "Missing SPN Parameter" "Tenant ID is required for service principal authentication" "$PARAM_ERROR"
            ((auth_errors++))
        fi
    fi

    # Common requirements
    if [[ -z "${subscription:-}" ]]; then
        display_error "Missing Parameter" "Subscription ID is required" "$PARAM_ERROR"
        ((auth_errors++))
    fi

    if [[ -z "${keyvault:-}" ]]; then
        display_error "Missing Parameter" "Key vault name is required" "$PARAM_ERROR"
        ((auth_errors++))
    fi

    return $auth_errors
}

#==============================================================================
# Comprehensive Validation Framework
#==============================================================================

function validate_secrets_deployment_prerequisites() {
    local environment="$1"
    local region_code="$2"
    local keyvault="$3"
    local subscription="$4"

    display_banner "Validation" "Validating secrets deployment prerequisites" "info"

    # Validate environment configuration
    if ! setup_environment_configuration "$environment" "$region_code"; then
        return $?
    fi

    # Validate Azure Key Vault access
    if ! validate_keyvault_access_comprehensive "$keyvault" "${STATE_SUBSCRIPTION:-$subscription}"; then
        return $?
    fi

    # Validate Azure CLI and authentication
    if ! validate_azure_authentication "$subscription"; then
        return $?
    fi

    # Validate system dependencies
    if ! validate_system_dependencies "true" "az jq"; then
        display_error "Dependencies Missing" "Required system dependencies are not available" "$DEPENDENCY_ERROR"
        return $DEPENDENCY_ERROR
    fi

    display_success "Validation Complete" "All prerequisites validated successfully"
    return $SUCCESS
}

function setup_environment_configuration() {
    local environment="$1"
    local region_code="$2"

    log_info "Setting up environment configuration"

    # Setup configuration directory structure
    local automation_config_directory="$CONFIG_REPO_PATH/.sap_deployment_automation"
    export environment_config_information="${automation_config_directory}/${environment}${region_code}"

    # Create configuration directory if needed
    if [[ ! -d "$automation_config_directory" ]]; then
        mkdir -p "$automation_config_directory"
        log_info "Created configuration directory: $automation_config_directory"
    fi

    # Ensure environment configuration file exists
    touch "$environment_config_information"

    # Load existing configuration
    load_configuration_values

    log_info "Environment configuration setup completed"
    return $SUCCESS
}

function load_configuration_values() {
    log_info "Loading configuration values from previous deployments"

    # Load subscription information
    if [[ -z "${subscription:-}" ]]; then
        load_config_vars "$environment_config_information" "subscription"
    fi

    # Load state subscription for workload deployments
    if [[ "$workload" != 1 ]]; then
        load_config_vars "$environment_config_information" "STATE_SUBSCRIPTION"
        if [[ -n "${STATE_SUBSCRIPTION:-}" ]]; then
            subscription="${STATE_SUBSCRIPTION}"
        fi
    fi

    # Load SPN configuration if not in MSI mode
    if [[ "${deploy_using_msi_only}" != "1" ]]; then
        load_config_vars "$environment_config_information" "client_id"
        load_config_vars "$environment_config_information" "tenant_id"
    fi
}

function validate_keyvault_access_comprehensive() {
    local keyvault_name="$1"
    local kv_subscription="$2"

    log_info "Performing comprehensive Key Vault access validation"

    # Validate Key Vault exists
    local kv_resource_id
    kv_resource_id=$(az resource list --name "$keyvault_name" --subscription "$kv_subscription" \
                     --resource-type Microsoft.KeyVault/vaults --query "[].id | [0]" -o tsv 2>/dev/null)

    if [[ -z "$kv_resource_id" ]]; then
        display_error "Key Vault Not Found" "Key vault does not exist: $keyvault_name" "$AZURE_ERROR"
        return $AZURE_ERROR
    fi

    # Validate Key Vault access permissions
    local access_test
    access_test=$(az keyvault secret list --vault-name "$keyvault_name" --subscription "$kv_subscription" \
                  --only-show-errors 2>&1 | grep "The user, group or application" || true)

    if [[ -n "$access_test" ]]; then
        local current_user
        current_user=$(az account show --query user.name -o tsv)
        display_error "Key Vault Access Denied" "User $current_user does not have access to Key Vault: $keyvault_name" "$AZURE_ERROR"
        return $AZURE_ERROR
    fi

    log_info "Key Vault access validation successful"
    return $SUCCESS
}

function validate_azure_authentication() {
    local subscription="$1"

    log_info "Validating Azure authentication and subscription access"

    # Check if logged into Azure
    if ! az account show &>/dev/null; then
        display_error "Azure Authentication" "Not logged into Azure CLI" "$AZURE_ERROR"
        return $AZURE_ERROR
    fi

    # Validate subscription access
    local sub_access
    sub_access=$(az account show --subscription "$subscription" --query id -o tsv 2>/dev/null || true)

    if [[ -z "$sub_access" ]]; then
        display_error "Subscription Access" "Cannot access subscription: $subscription" "$AZURE_ERROR"
        return $AZURE_ERROR
    fi

    log_info "Azure authentication validation successful"
    return $SUCCESS
}

#==============================================================================
# Enhanced Secret Management
#==============================================================================

function execute_secrets_deployment() {
    local environment="$1"
    local keyvault="$2"
    local subscription="$3"
    local kv_subscription="${STATE_SUBSCRIPTION:-$subscription}"

    display_banner "Secrets Deployment" "Deploying SPN secrets to Key Vault" "info"

    # Initialize error tracking
    local deployment_errors=0

    # Remove any existing error files
    [[ -f secret.err ]] && rm secret.err

    # Deploy subscription ID secret (always required)
    if ! deploy_subscription_secret "$environment" "$keyvault" "$kv_subscription" "$subscription"; then
        ((deployment_errors++))
    fi

    # Deploy SPN secrets (only if not using MSI)
    if [[ "${deploy_using_msi_only}" != "1" ]]; then
        if ! deploy_spn_secrets "$environment" "$keyvault" "$kv_subscription"; then
            ((deployment_errors++))
        fi
    else
        log_info "MSI mode enabled - skipping SPN secret deployment"
    fi

    # Save configuration
    save_deployment_configuration

    if [[ $deployment_errors -eq 0 ]]; then
        display_success "Secrets Deployment" "All secrets deployed successfully"
        return $SUCCESS
    else
        display_error "Secrets Deployment" "Failed to deploy some secrets" "$SECRET_ERROR"
        return $SECRET_ERROR
    fi
}

function deploy_subscription_secret() {
    local environment="$1"
    local keyvault="$2"
    local kv_subscription="$3"
    local target_subscription="$4"

    local secret_name="${environment}-subscription-id"

    log_info "Deploying subscription secret: $secret_name"

    if set_secret_with_recovery "$keyvault" "$kv_subscription" "$secret_name" "$target_subscription" "$SECRET_TYPE_CONFIG"; then
        display_success "Secret Deployed" "Secret $secret_name set in Key Vault $keyvault"
        return $SUCCESS
    else
        display_error "Secret Deployment Failed" "Failed to set secret $secret_name in Key Vault $keyvault" "$SECRET_ERROR"
        echo "Failed to set secret $secret_name in Key Vault $keyvault" > secret.err
        return $SECRET_ERROR
    fi
}

function deploy_spn_secrets() {
    local environment="$1"
    local keyvault="$2"
    local kv_subscription="$3"

    log_info "Deploying SPN secrets for service principal authentication"

    local secrets_failed=0

    # Deploy client ID secret
    local client_id_secret="${environment}-client-id"
    if set_secret_with_recovery "$keyvault" "$kv_subscription" "$client_id_secret" "$client_id" "$SECRET_TYPE_CONFIG"; then
        display_success "Secret Deployed" "Secret $client_id_secret set in Key Vault $keyvault"
    else
        display_error "Secret Deployment Failed" "Failed to set secret $client_id_secret" "$SECRET_ERROR"
        echo "Failed to set secret $client_id_secret in Key Vault $keyvault" >> secret.err
        ((secrets_failed++))
    fi

    # Deploy tenant ID secret
    local tenant_id_secret="${environment}-tenant-id"
    if set_secret_with_recovery "$keyvault" "$kv_subscription" "$tenant_id_secret" "$tenant_id" "$SECRET_TYPE_CONFIG"; then
        display_success "Secret Deployed" "Secret $tenant_id_secret set in Key Vault $keyvault"
    else
        display_error "Secret Deployment Failed" "Failed to set secret $tenant_id_secret" "$SECRET_ERROR"
        echo "Failed to set secret $tenant_id_secret in Key Vault $keyvault" >> secret.err
        ((secrets_failed++))
    fi

    # Deploy client secret (most sensitive)
    local client_secret_secret="${environment}-client-secret"
    if set_secret_with_recovery "$keyvault" "$kv_subscription" "$client_secret_secret" "$client_secret" "$SECRET_TYPE_SECRET"; then
        display_success "Secret Deployed" "Secret $client_secret_secret set in Key Vault $keyvault"
    else
        display_error "Secret Deployment Failed" "Failed to set secret $client_secret_secret" "$SECRET_ERROR"
        echo "Failed to set secret $client_secret_secret in Key Vault $keyvault" >> secret.err
        ((secrets_failed++))
    fi

    return $secrets_failed
}

function set_secret_with_recovery() {
    local keyvault="$1"
    local subscription="$2"
    local secret_name="$3"
    local value="$4"
    local content_type="$5"

    local attempt=1
    local max_attempts="$MAX_SECRET_ATTEMPTS"

    log_info "Setting secret $secret_name with intelligent recovery (max attempts: $max_attempts)"

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Setting secret attempt $attempt/$max_attempts"

        # Calculate expiration date
        local expiry_date
        expiry_date=$(date -d "$SECRET_EXPIRY_PERIOD" -u +%Y-%m-%dT%H:%M:%SZ)

        # Attempt to set secret
        if az keyvault secret set \
           --name "$secret_name" \
           --vault-name "$keyvault" \
           --subscription "$subscription" \
           --value "$value" \
           --expires "$expiry_date" \
           --output none \
           --content-type "$content_type" 2>/dev/null; then
            log_info "Secret $secret_name set successfully on attempt $attempt"
            return $SUCCESS
        else
            local return_code=$?
            log_warn "Secret setting failed on attempt $attempt (return code: $return_code)"

            # Handle specific error cases
            if [[ $return_code -eq 1 ]]; then
                log_info "Attempting secret recovery for $secret_name"

                if az keyvault secret recover \
                   --name "$secret_name" \
                   --vault-name "$keyvault" \
                   --subscription "$subscription" 2>/dev/null; then
                    log_info "Secret recovery successful, waiting ${SECRET_RECOVERY_DELAY}s before retry"
                    sleep "$SECRET_RECOVERY_DELAY"

                    # Retry setting after recovery
                    if az keyvault secret set \
                       --name "$secret_name" \
                       --vault-name "$keyvault" \
                       --subscription "$subscription" \
                       --value "$value" \
                       --expires "$expiry_date" \
                       --output none \
                       --content-type "$content_type" 2>/dev/null; then
                        log_info "Secret $secret_name set successfully after recovery"
                        return $SUCCESS
                    fi
                fi
            fi

            ((attempt++))
            if [[ $attempt -le $max_attempts ]]; then
                log_info "Retrying secret setting in 5 seconds..."
                sleep 5
            fi
        fi
    done

    log_error "Failed to set secret $secret_name after $max_attempts attempts"
    return $SECRET_ERROR
}

function save_deployment_configuration() {
    log_info "Saving deployment configuration"

    # Save configuration variables
    save_config_vars "$environment_config_information" \
        keyvault \
        environment \
        subscription \
        client_id \
        tenant_id \
        STATE_SUBSCRIPTION

    log_info "Configuration saved successfully"
}

#==============================================================================
# Main Execution Function
#==============================================================================

function main() {
    local return_code=0

    # Enable debug mode if requested
    if [[ "${DEBUG:-false}" == "true" ]] || [[ "${SYSTEM_DEBUG:-false}" == "True" ]]; then
        set -x
        log_info "Debug mode enabled"
    fi

    # Process command line arguments
    process_command_line_arguments "$@"

    # Validate deployment prerequisites
    if ! validate_secrets_deployment_prerequisites "$environment" "$region_code" "$keyvault" "$subscription"; then
        display_error "Prerequisites Failed" "Secrets deployment prerequisites validation failed" "$VALIDATION_ERROR"
        exit $VALIDATION_ERROR
    fi

    # Display deployment summary
    display_deployment_summary

    # Execute secrets deployment
    if ! execute_secrets_deployment "$environment" "$keyvault" "$subscription"; then
        display_error "Deployment Failed" "Secrets deployment execution failed" "$SECRET_ERROR"
        exit $SECRET_ERROR
    fi

    # Final success display
    display_banner "Deployment Complete" "SPN secrets deployed successfully to Key Vault" "success"

    log_info "Script completed successfully: $SCRIPT_NAME"
    return $return_code
}

function display_deployment_summary() {
    display_banner "Deployment Summary" "Configuration summary" "info"

    echo "Environment:                         $environment"
    echo "Region:                              $region_code"
    echo "Key Vault:                           $keyvault"
    echo "Target Subscription:                 $subscription"
    echo "Key Vault Subscription:              ${STATE_SUBSCRIPTION:-$subscription}"

    if [[ "${deploy_using_msi_only}" == "1" ]]; then
        echo "Authentication Mode:                 Managed Service Identity"
    else
        echo "Authentication Mode:                 Service Principal"
        echo "SPN Client ID:                       ${client_id:0:8}..."
        echo "SPN Tenant ID:                       ${tenant_id:0:8}..."
    fi

    if [[ "$workload" == "1" ]]; then
        echo "Deployment Type:                     Workload"
    else
        echo "Deployment Type:                     Control Plane"
    fi

    echo ""
}

#==============================================================================
# Script Entry Point
#==============================================================================

# Trap cleanup for graceful exit
trap 'cleanup_on_exit' EXIT

function cleanup_on_exit() {
    local exit_code=$?

    # Clean up temporary files
    [[ -f "secret.err" ]] && rm -f secret.err

    # Clear sensitive variables
    unset client_secret

    log_info "Cleanup completed"

    if [[ $exit_code -eq 0 ]]; then
        echo "Exiting: ${SCRIPT_NAME} - Success"
    else
        echo "Exiting: ${SCRIPT_NAME} - Error (Code: $exit_code)"
    fi
}

# Execute main function with all arguments
main "$@"
