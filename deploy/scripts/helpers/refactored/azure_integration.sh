#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# shellcheck disable=SC1090,SC1091,SC2034,SC2154
# Azure Integration Module - Authentication and Resource Management
# This module provides centralized Azure authentication, resource validation,
# and configuration management for the SAP deployment automation framework

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
# AZURE CONFIGURATION
# =============================================================================

# Azure CLI configuration
declare -gr AZ_CLI_TIMEOUT="${AZ_CLI_TIMEOUT:-300}"
declare -gr AZ_LOGIN_TIMEOUT="${AZ_LOGIN_TIMEOUT:-180}"
declare -gr AZ_MAX_RETRIES="${AZ_MAX_RETRIES:-3}"

# Azure authentication methods
declare -gr AUTH_METHOD_SPN="service_principal"
declare -gr AUTH_METHOD_MSI="managed_identity"
declare -gr AUTH_METHOD_USER="user"

# Azure resource validation patterns
# shellcheck disable=SC2034
declare -gr AZURE_SUBSCRIPTION_PATTERN="^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
declare -gr AZURE_RESOURCE_ID_PATTERN="^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/"

# =============================================================================
# AZURE AUTHENTICATION FUNCTIONS
# =============================================================================

########################################################################################
# Enhanced Azure authentication with multiple authentication methods                   #
# This replaces LogonToAzure with improved functionality and error handling            #
# Arguments:                                                                           #
#   $1 - Authentication method (spn, msi, user) - default: auto-detect                 #
#   $2 - Subscription ID (optional)                                                    #
#   $3 - Tenant ID (optional, required for SPN)                                        #
#   $4 - Client ID (optional, required for SPN)                                        #
#   $5 - Client secret (optional, required for SPN)                                    #
# Returns:                                                                             #
#   SUCCESS if authentication successful, AUTH_ERROR on failure                        #
# Usage:                                                                               #
#   authenticate_azure "spn" "$subscription" "$tenant" "$client_id" "$client_secret"   #
#   authenticate_azure "msi" "$subscription"                                           #
#   authenticate_azure "auto"                                                          #
########################################################################################
function authenticate_azure() {
    local auth_method="${1:-auto}"
    local subscription_id="${2:-}"
    local tenant_id="${3:-}"
    local client_id="${4:-}"
    local client_secret="${5:-}"

    log_info "Starting Azure authentication"
    log_debug "Authentication method: $auth_method"

    # Auto-detect authentication method if requested
    if [[ "$auth_method" == "auto" ]]; then
        auth_method=$(_detect_authentication_method)
        log_info "Auto-detected authentication method: $auth_method"
    fi

    # Validate authentication method
    case "$auth_method" in
        "$AUTH_METHOD_SPN"|"spn")
            auth_method="$AUTH_METHOD_SPN"
            ;;
        "$AUTH_METHOD_MSI"|"msi")
            auth_method="$AUTH_METHOD_MSI"
            ;;
        "$AUTH_METHOD_USER"|"user")
            auth_method="$AUTH_METHOD_USER"
            ;;
        *)
            log_error "Invalid authentication method: $auth_method"
            return $PARAM_ERROR
            ;;
    esac

    # Perform authentication based on method
    local auth_result
    case "$auth_method" in
        "$AUTH_METHOD_SPN")
            auth_result=$(_authenticate_service_principal "$subscription_id" "$tenant_id" "$client_id" "$client_secret")
            ;;
        "$AUTH_METHOD_MSI")
            auth_result=$(_authenticate_managed_identity "$subscription_id")
            ;;
        "$AUTH_METHOD_USER")
            auth_result=$(_authenticate_user "$subscription_id")
            ;;
    esac

    if [[ $auth_result -eq $SUCCESS ]]; then
        log_info "Azure authentication successful using method: $auth_method"

        # Validate and set subscription context
        if [[ -n "$subscription_id" ]]; then
            if ! set_azure_subscription "$subscription_id"; then
                log_error "Failed to set subscription context"
                return $AUTH_ERROR
            fi
        fi

        # Store authentication context for future use
        _store_authentication_context "$auth_method" "$subscription_id"

        return $SUCCESS
    else
        log_error "Azure authentication failed"
        return $AUTH_ERROR
    fi
}

################################################################################
# Auto-detect the best authentication method based on environment              #
# Arguments: None                                                              #
# Returns: Outputs authentication method name                                  #
################################################################################
function _detect_authentication_method() {
    log_debug "Auto-detecting authentication method"

    # Check for service principal environment variables
    if [[ -n "${ARM_CLIENT_ID:-}" && -n "${ARM_CLIENT_SECRET:-}" && -n "${ARM_TENANT_ID:-}" ]]; then
        log_debug "Service principal credentials detected"
        echo "$AUTH_METHOD_SPN"
        return
    fi

    # Check for managed identity environment (Azure VM, Cloud Shell, etc.)
    if [[ -n "${MSI_ENDPOINT:-}" ]] || [[ -n "${AZURE_HTTP_USER_AGENT:-}" ]] || _is_azure_environment; then
        log_debug "Managed identity environment detected"
        echo "$AUTH_METHOD_MSI"
        return
    fi

    # Check if already logged in with user account
    if az account show >/dev/null 2>&1; then
        log_debug "Existing user authentication detected"
        echo "$AUTH_METHOD_USER"
        return
    fi

    # Default to managed identity as it's most common in automation scenarios
    log_debug "No specific authentication method detected, defaulting to MSI"
    echo "$AUTH_METHOD_MSI"
}

################################################################################
# Authenticate using service principal                                         #
# Arguments:                                                                   #
#   $1 - Subscription ID                                                       #
#   $2 - Tenant ID                                                             #
#   $3 - Client ID                                                             #
#   $4 - Client secret                                                         #
# Returns:                                                                     #
#   SUCCESS if authentication successful, AUTH_ERROR on failure                #
################################################################################
function _authenticate_service_principal() {
    local subscription_id="$1"
    local tenant_id="$2"
    local client_id="$3"
    local client_secret="$4"

    log_info "Authenticating with service principal"

    # Use environment variables if parameters not provided
    tenant_id="${tenant_id:-${ARM_TENANT_ID:-}}"
    client_id="${client_id:-${ARM_CLIENT_ID:-}}"
    client_secret="${client_secret:-${ARM_CLIENT_SECRET:-}}"

    # Validate required parameters
    if [[ -z "$tenant_id" || -z "$client_id" || -z "$client_secret" ]]; then
        log_error "Service principal authentication requires tenant_id, client_id, and client_secret"
        return $AUTH_ERROR
    fi

    # Validate GUID formats
    if ! _is_valid_guid "$tenant_id"; then
        log_error "Invalid tenant ID format: $tenant_id"
        return $AUTH_ERROR
    fi

    if ! _is_valid_guid "$client_id"; then
        log_error "Invalid client ID format: $client_id"
        return $AUTH_ERROR
    fi

    log_debug "Service principal credentials validated"

    # Perform authentication
    local login_output
    if login_output=$(timeout "$AZ_LOGIN_TIMEOUT" az login --service-principal \
        --username "$client_id" \
        --password "$client_secret" \
        --tenant "$tenant_id" \
        --output json 2>&1); then

        log_info "Service principal authentication successful"
        log_debug "Authenticated as: $client_id"

        # Set subscription context if provided
        if [[ -n "$subscription_id" ]]; then
            if ! az account set --subscription "$subscription_id" >/dev/null 2>&1; then
                log_error "Failed to set subscription context: $subscription_id"
                return $AUTH_ERROR
            fi
        fi

        return $SUCCESS
    else
        log_error "Service principal authentication failed"
        log_debug "Login error: $login_output"
        return $AUTH_ERROR
    fi
}

################################################################################
# Authenticate using managed identity                                          #
# Arguments:                                                                   #
#   $1 - Subscription ID (optional)                                            #
# Returns:                                                                     #
#   SUCCESS if authentication successful, AUTH_ERROR on failure                #
################################################################################
function _authenticate_managed_identity() {
    local subscription_id="$1"

    log_info "Authenticating with managed identity"

    # Check if we're in an environment that supports MSI
    if ! _is_azure_environment; then
        log_warn "Managed identity authentication may not be available in this environment"
    fi

    # Attempt MSI authentication
    local login_output
    if login_output=$(timeout "$AZ_LOGIN_TIMEOUT" az login --identity --output json 2>&1); then
        log_info "Managed identity authentication successful"

        # Extract MSI details for logging
        local msi_client_id
        msi_client_id=$(echo "$login_output" | jq -r '.[0].user.name // "unknown"' 2>/dev/null)
        log_debug "Authenticated with MSI client ID: $msi_client_id"

        # Set subscription context if provided
        if [[ -n "$subscription_id" ]]; then
            if ! az account set --subscription "$subscription_id" >/dev/null 2>&1; then
                log_error "Failed to set subscription context: $subscription_id"
                return $AUTH_ERROR
            fi
        fi

        return $SUCCESS
    else
        log_error "Managed identity authentication failed"
        log_debug "Login error: $login_output"
        return $AUTH_ERROR
    fi
}

################################################################################
# Authenticate using existing user session                                     #
# Arguments:                                                                   #
#   $1 - Subscription ID (optional)                                            #
# Returns:                                                                     #
#   SUCCESS if authentication successful, AUTH_ERROR on failure                #
################################################################################
function _authenticate_user() {
    local subscription_id="$1"

    log_info "Using existing user authentication"

    # Check if already authenticated
    local current_account
    if current_account=$(az account show --output json 2>/dev/null); then
        local current_user
        current_user=$(echo "$current_account" | jq -r '.user.name // "unknown"' 2>/dev/null)
        log_info "Using existing authentication for user: $current_user"

        # Set subscription context if provided
        if [[ -n "$subscription_id" ]]; then
            if ! az account set --subscription "$subscription_id" >/dev/null 2>&1; then
                log_error "Failed to set subscription context: $subscription_id"
                return $AUTH_ERROR
            fi
        fi

        return $SUCCESS
    else
        log_error "No existing user authentication found"
        log_info "Please run 'az login' to authenticate"
        return $AUTH_ERROR
    fi
}

# =============================================================================
# AZURE SUBSCRIPTION AND CONTEXT MANAGEMENT
# =============================================================================

################################################################################
# Set Azure subscription context with validation                               #
# Arguments:                                                                   #
#   $1 - Subscription ID                                                       #
# Returns:                                                                     #
#   SUCCESS if subscription set successfully, AZURE_ERROR on failure           #
# Usage:                                                                       #
#   set_azure_subscription "12345678-1234-1234-1234-123456789012"              #
################################################################################
function set_azure_subscription() {
    if ! validate_function_params "set_azure_subscription" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local subscription_id="${1:-}"

    log_info "Setting Azure subscription context: $subscription_id"

    # Validate subscription ID format
    if ! _is_valid_guid "$subscription_id"; then
        log_error "Invalid subscription ID format: $subscription_id"
        return $PARAM_ERROR
    fi

    # Set subscription context
    if az account set --subscription "$subscription_id" >/dev/null 2>&1; then
        log_info "Subscription context set successfully"

        # Verify the subscription was set correctly
        local current_subscription
        current_subscription=$(az account show --query id --output tsv 2>/dev/null)

        if [[ "$current_subscription" == "$subscription_id" ]]; then
            log_debug "Subscription context verified: $subscription_id"
            export ARM_SUBSCRIPTION_ID="$subscription_id"
            return $SUCCESS
        else
            log_error "Subscription context verification failed"
            return $AZURE_ERROR
        fi
    else
        log_error "Failed to set subscription context: $subscription_id"
        return $AZURE_ERROR
    fi
}

################################################################################
# Get current Azure subscription information                                   #
# Arguments: None                                                              #
# Returns:                                                                     #
#   SUCCESS and outputs subscription JSON, AZURE_ERROR on failure              #
# Usage:                                                                       #
#   subscription_info=$(get_azure_subscription_info)                           #
################################################################################
function get_azure_subscription_info() {
    log_debug "Getting current Azure subscription information"

    local subscription_info
    if subscription_info=$(az account show --output json 2>/dev/null); then
        echo "$subscription_info"
        return $SUCCESS
    else
        log_error "Failed to get subscription information - check authentication"
        return $AZURE_ERROR
    fi
}

##############################################################################################
# Validate Azure subscription access and permissions                                         #
# Arguments:                                                                                 #
#   $1 - Subscription ID                                                                     #
#   $2 - Required permissions (optional, space-separated list)                               #
# Returns:                                                                                   #
#   SUCCESS if subscription accessible, AZURE_ERROR on failure                               #
# Usage:                                                                                     #
#   validate_subscription_access "$subscription_id"                                          #
#   validate_subscription_access "$subscription_id" "Microsoft.Compute/virtualMachines/read" #
##############################################################################################
function validate_subscription_access() {
    if ! validate_function_params "validate_subscription_access" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local subscription_id="${1:-}"
    local required_permissions="${2:-}"

    log_info "Validating subscription access: $subscription_id"

    # Set subscription context
    if ! set_azure_subscription "$subscription_id"; then
        return $AZURE_ERROR
    fi

    # Test basic subscription access
    local subscription_info
    if ! subscription_info=$(get_azure_subscription_info); then
        log_error "Cannot access subscription: $subscription_id"
        return $AZURE_ERROR
    fi

    # Extract subscription details
    local subscription_name tenant_id
    subscription_name=$(echo "$subscription_info" | jq -r '.name // "unknown"' 2>/dev/null)
    tenant_id=$(echo "$subscription_info" | jq -r '.tenantId // "unknown"' 2>/dev/null)

    log_info "Subscription access validated: $subscription_name (tenant: $tenant_id)"

    # Validate specific permissions if provided
    if [[ -n "$required_permissions" ]]; then
        log_debug "Checking required permissions: $required_permissions"

        local -a permissions_list
        IFS=' ' read -ra permissions_list <<< "$required_permissions"

        for permission in "${permissions_list[@]}"; do
            if ! _check_azure_permission "$permission"; then
                log_error "Required permission not available: $permission"
                return $AZURE_ERROR
            fi
        done

        log_info "All required permissions validated"
    fi

    return $SUCCESS
}

# =============================================================================
# AZURE RESOURCE MANAGEMENT FUNCTIONS
# =============================================================================

################################################################################
# Validate Azure Key Vault with comprehensive access testing                   #
# Enhanced version with retry logic and detailed error reporting               #
# Arguments:                                                                   #
#   $1 - Key vault name                                                        #
#   $2 - Subscription ID (optional)                                            #
#   $3 - Required access types (optional: "read", "write", "both")             #
# Returns:                                                                     #
#   SUCCESS if key vault accessible, AZURE_ERROR on failure                    #
# Usage:                                                                       #
#   validate_keyvault_access "my-keyvault" "$subscription" "both"              #
################################################################################
function validate_keyvault_access() {
    if ! validate_function_params "validate_keyvault_access" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local keyvault_name="${1:-}"
    local subscription_id="${2:-}"
    local access_type="${3:-read}"

    log_info "Validating Key Vault access: $keyvault_name"
    log_debug "Access type: $access_type"

    # Set subscription context if provided
    if [[ -n "$subscription_id" ]]; then
        if ! set_azure_subscription "$subscription_id"; then
            return $AZURE_ERROR
        fi
    fi

    # Retry logic for Key Vault validation
    local attempt=1
    local max_attempts="$AZ_MAX_RETRIES"

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Key Vault validation attempt $attempt of $max_attempts"

        if _test_keyvault_comprehensive "$keyvault_name" "$access_type"; then
            log_info "Key Vault access validation successful: $keyvault_name"
            return $SUCCESS
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            local wait_time=$((attempt * 30))
            log_warn "Key Vault validation failed, retrying in $wait_time seconds..."
            sleep "$wait_time"
        fi

        ((attempt++))
    done

    log_error "Key Vault validation failed after $max_attempts attempts: $keyvault_name"
    return $AZURE_ERROR
}

################################################################################
# Comprehensive Key Vault access testing                                       #
# Arguments:                                                                   #
#   $1 - Key vault name                                                        #
#   $2 - Access type                                                           #
# Returns:                                                                     #
#   SUCCESS if all tests pass, AZURE_ERROR on failure                          #
################################################################################
function _test_keyvault_comprehensive() {
    local keyvault_name="$1"
    local access_type="$2"

    log_debug "Running comprehensive Key Vault tests"

    # Test 1: Key Vault existence and basic access
    local keyvault_info
    if ! keyvault_info=$(az keyvault show --name "$keyvault_name" --output json 2>/dev/null); then
        log_debug "Key Vault does not exist or is not accessible: $keyvault_name"
        return $AZURE_ERROR
    fi

    # Extract Key Vault details
    local keyvault_uri resource_group
    keyvault_uri=$(echo "$keyvault_info" | jq -r '.properties.vaultUri // "unknown"' 2>/dev/null)
    resource_group=$(echo "$keyvault_info" | jq -r '.resourceGroup // "unknown"' 2>/dev/null)

    log_debug "Key Vault found: $keyvault_uri (resource group: $resource_group)"

    # Test 2: Read access (list secrets)
    if [[ "$access_type" == "read" || "$access_type" == "both" ]]; then
        if ! az keyvault secret list --vault-name "$keyvault_name" --output none 2>/dev/null; then
            log_debug "Key Vault read access test failed: $keyvault_name"
            return $AZURE_ERROR
        fi
        log_debug "Key Vault read access confirmed"
    fi

    # Test 3: Write access (attempt to create a test secret)
    if [[ "$access_type" == "write" || "$access_type" == "both" ]]; then
        local test_secret_name
        test_secret_name="sdaf-access-test-$(date +%s)"

        if az keyvault secret set --vault-name "$keyvault_name" \
            --name "$test_secret_name" \
            --value "test" \
            --output none 2>/dev/null; then

            log_debug "Key Vault write access confirmed"

            # Clean up test secret
            az keyvault secret delete --vault-name "$keyvault_name" \
                --name "$test_secret_name" \
                --output none 2>/dev/null || true
        else
            log_debug "Key Vault write access test failed: $keyvault_name"
            return $AZURE_ERROR
        fi
    fi

    log_debug "All Key Vault access tests passed"
    return $SUCCESS
}

################################################################################
# Get or create Azure storage account for Terraform state                      #
# Arguments:                                                                   #
#   $1 - Storage account name                                                  #
#   $2 - Resource group name                                                   #
#   $3 - Location                                                              #
#   $4 - Subscription ID (optional)                                            #
# Returns:                                                                     #
#   SUCCESS if storage account ready, AZURE_ERROR on failure                   #
# Usage:                                                                       #
#   ensure_terraform_storage "mystorageacct" "my-rg" "eastus" "$subscription"  #
################################################################################
function ensure_terraform_storage() {
    if ! validate_function_params "ensure_terraform_storage" 3 "$#"; then
        return $PARAM_ERROR
    fi

    local storage_account="${1:-}"
    local resource_group="${2:-}"
    local location="${3:-}"
    local subscription_id="${4:-}"

    log_info "Ensuring Terraform storage account: $storage_account"

    # Set subscription context if provided
    if [[ -n "$subscription_id" ]]; then
        if ! set_azure_subscription "$subscription_id"; then
            return $AZURE_ERROR
        fi
    fi

    # Check if storage account exists
    if az storage account show --name "$storage_account" --resource-group "$resource_group" >/dev/null 2>&1; then
        log_info "Storage account already exists: $storage_account"

        # Validate storage account configuration
        if _validate_storage_account_config "$storage_account" "$resource_group"; then
            return $SUCCESS
        else
            log_error "Storage account configuration validation failed"
            return $AZURE_ERROR
        fi
    else
        log_info "Creating storage account: $storage_account"

        # Create storage account
        if _create_terraform_storage "$storage_account" "$resource_group" "$location"; then
            log_info "Storage account created successfully: $storage_account"
            return $SUCCESS
        else
            log_error "Failed to create storage account: $storage_account"
            return $AZURE_ERROR
        fi
    fi
}

# =============================================================================
# AZURE APP CONFIGURATION INTEGRATION
# =============================================================================

################################################################################
# Get variable from Azure App Configuration                                    #
# Arguments:                                                                   #
#   $1 - App Configuration resource ID                                         #
#   $2 - Variable name                                                         #
#   $3 - Default value (optional)                                              #
# Returns:                                                                     #
#   SUCCESS and outputs value, AZURE_ERROR on failure                          #
# Usage:                                                                       #
#   value=$(get_app_config_variable "$app_config_id" "KeyVaultName" "default") #
################################################################################
function get_app_config_variable() {
    if ! validate_function_params "get_app_config_variable" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local app_config_id="${1:-}"
    local variable_name="${2:-}"
    local default_value="${3:-}"

    log_debug "Getting App Configuration variable: $variable_name"

    # Validate App Configuration resource ID format
    if [[ ! "$app_config_id" =~ $AZURE_RESOURCE_ID_PATTERN ]]; then
        log_error "Invalid App Configuration resource ID format: $app_config_id"
        return $PARAM_ERROR
    fi

    # Extract App Configuration name and subscription
    local app_config_name subscription_id
    app_config_name=$(echo "$app_config_id" | cut -d'/' -f9)
    subscription_id=$(echo "$app_config_id" | cut -d'/' -f3)

    log_debug "App Configuration: $app_config_name (subscription: $subscription_id)"

    # Set subscription context
    if ! set_azure_subscription "$subscription_id"; then
        return $AZURE_ERROR
    fi

    # Get configuration value
    local config_value
    if config_value=$(az appconfig kv show --name "$app_config_name" --key "$variable_name" --query "value" --output tsv 2>/dev/null); then
        if [[ -n "$config_value" && "$config_value" != "null" ]]; then
            echo "$config_value"
            log_debug "Retrieved App Configuration value: $variable_name"
            return $SUCCESS
        fi
    fi

    # Return default value if variable not found
    if [[ -n "$default_value" ]]; then
        echo "$default_value"
        log_debug "Using default value for $variable_name: $default_value"
        return $SUCCESS
    else
        log_error "App Configuration variable not found and no default provided: $variable_name"
        return $AZURE_ERROR
    fi
}

# =============================================================================
# UTILITY AND HELPER FUNCTIONS
# =============================================================================

################################################################################
# Check if running in Azure environment                                        #
# Arguments: None                                                              #
# Returns: SUCCESS if in Azure environment, GENERAL_ERROR otherwise            #
################################################################################
function _is_azure_environment() {
    # Check for Azure metadata service
    if curl -s -m 5 -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null 2>&1; then
        return $SUCCESS
    fi

    # Check for Azure Cloud Shell indicators
    if [[ -n "${AZURE_HTTP_USER_AGENT:-}" ]] || [[ -n "${POWERSHELL_DISTRIBUTION_CHANNEL:-}" ]]; then
        return $SUCCESS
    fi

    # Check for Azure Arc indicators
    if [[ -d "/var/opt/azcmagent" ]] || command -v azcmagent >/dev/null 2>&1; then
        return $SUCCESS
    fi

    return $GENERAL_ERROR
}

################################################################################
# Check specific Azure permission                                              #
# Arguments:                                                                   #
#   $1 - Permission string                                                     #
# Returns:                                                                     #
#   SUCCESS if permission available, AZURE_ERROR otherwise                     #
################################################################################
function _check_azure_permission() {
    local permission="$1"

    log_debug "Checking Azure permission: $permission"

    # This is a simplified permission check
    # In a production environment, you might want to use more sophisticated permission checking
    # For now, we'll do a basic check by attempting to list resources

    if az provider show --namespace "$(echo "$permission" | cut -d'/' -f1)" --output none 2>/dev/null; then
        return $SUCCESS
    else
        return $AZURE_ERROR
    fi
}

################################################################################
# Store authentication context for reuse                                       #
# Arguments:                                                                   #
#   $1 - Authentication method                                                 #
#   $2 - Subscription ID                                                       #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _store_authentication_context() {
    local auth_method="$1"
    local subscription_id="$2"

    export AZURE_AUTH_METHOD="$auth_method"
    if [[ -n "$subscription_id" ]]; then
        export AZURE_CURRENT_SUBSCRIPTION="$subscription_id"
    fi

    log_debug "Authentication context stored: method=$auth_method, subscription=$subscription_id"
    return $SUCCESS
}

################################################################################
# Validate storage account configuration for Terraform                         #
# Arguments:                                                                   #
#   $1 - Storage account name                                                  #
#   $2 - Resource group name                                                   #
# Returns:                                                                     #
#   SUCCESS if configuration valid, AZURE_ERROR otherwise                      #
################################################################################
function _validate_storage_account_config() {
    local storage_account="$1"
    local resource_group="$2"

    log_debug "Validating storage account configuration"

    # Check if tfstate container exists
    if ! az storage container show --name "tfstate" --account-name "$storage_account" >/dev/null 2>&1; then
        log_warn "tfstate container does not exist, creating it"

        if ! az storage container create --name "tfstate" --account-name "$storage_account" >/dev/null 2>&1; then
            log_error "Failed to create tfstate container"
            return $AZURE_ERROR
        fi
    fi

    log_debug "Storage account configuration validated"
    return $SUCCESS
}

################################################################################
# Create Terraform storage account with proper configuration                   #
# Arguments:                                                                   #
#   $1 - Storage account name                                                  #
#   $2 - Resource group name                                                   #
#   $3 - Location                                                              #
# Returns:                                                                     #
#   SUCCESS if creation successful, AZURE_ERROR on failure                     #
################################################################################
function _create_terraform_storage() {
    local storage_account="$1"
    local resource_group="$2"
    local location="$3"

    log_info "Creating Terraform storage account with proper configuration"

    # Create storage account
    if ! az storage account create \
        --name "$storage_account" \
        --resource-group "$resource_group" \
        --location "$location" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --output none 2>/dev/null; then

        log_error "Failed to create storage account"
        return $AZURE_ERROR
    fi

    # Create tfstate container
    if ! az storage container create \
        --name "tfstate" \
        --account-name "$storage_account" \
        --output none 2>/dev/null; then

        log_error "Failed to create tfstate container"
        return $AZURE_ERROR
    fi

    log_info "Storage account created with proper Terraform configuration"
    return $SUCCESS
}

# =============================================================================
# BACKWARD COMPATIBILITY FUNCTIONS
# =============================================================================

################################################################################
# Legacy LogonToAzure function for backward compatibility                      #
################################################################################
function LogonToAzure() {
    deprecation_warning "LogonToAzure" "authenticate_azure"

    # Extract parameters from global variables (legacy behavior)
    local subscription_id="${ARM_SUBSCRIPTION_ID:-}"
    local tenant_id="${ARM_TENANT_ID:-}"
    local client_id="${ARM_CLIENT_ID:-}"
    local client_secret="${ARM_CLIENT_SECRET:-}"

    # Determine authentication method based on available credentials
    if [[ -n "$client_id" && -n "$client_secret" && -n "$tenant_id" ]]; then
        authenticate_azure "spn" "$subscription_id" "$tenant_id" "$client_id" "$client_secret"
    else
        authenticate_azure "msi" "$subscription_id"
    fi

    return $?
}

################################################################################
# Legacy getVariableFromApplicationConfiguration function                      #
################################################################################
function getVariableFromApplicationConfiguration() {
    deprecation_warning "getVariableFromApplicationConfiguration" "get_app_config_variable"
    get_app_config_variable "$@"
    return $?
}

# Additional functions for deploy/scripts/helpers/refactored/azure_integration.sh

#==============================================================================
# Pipeline Azure Integration Functions
#==============================================================================

function setup_azure_pipeline_integration() {
    local subscription="$1"
    local use_msi="$2"

    display_banner "Azure Integration" "Configuring Azure resources and authentication" "info"
    send_pipeline_event "progress" "Setting up Azure integration" "70"

    # Setup Azure subscription context
    if ! configure_azure_subscription_context "$subscription"; then
        send_pipeline_event "error" "Azure subscription configuration failed"
        return $AZURE_ERROR
    fi

    # Authenticate with Azure using appropriate method
    if ! authenticate_azure_pipeline_context "$use_msi"; then
        send_pipeline_event "error" "Azure authentication failed"
        return $AZURE_ERROR
    fi

    # Configure Key Vault integration
    if ! setup_key_vault_integration; then
        send_pipeline_event "error" "Key Vault integration failed"
        return $AZURE_ERROR
    fi

    # Handle force reset scenario
    if ! handle_force_reset_scenario; then
        send_pipeline_event "error" "Force reset handling failed"
        return $AZURE_ERROR
    fi

    display_success "Azure Integration" "Azure resources configured successfully"
    send_pipeline_event "progress" "Azure integration completed" "80"
    return $SUCCESS
}

function configure_azure_subscription_context() {
    local subscription="$1"

    log_info "Configuring Azure subscription context: $subscription"

    # Set subscription context
    if ! az account set --subscription "$subscription"; then
        display_error "Azure Subscription" "Failed to set subscription context: $subscription" "$AZURE_ERROR"
        return $AZURE_ERROR
    fi

    # Verify subscription access
    local current_subscription
    current_subscription=$(az account show --query id --output tsv 2>/dev/null)

    if [[ "$current_subscription" != "$subscription" ]]; then
        display_error "Azure Subscription" "Subscription verification failed: expected $subscription, got $current_subscription" "$AZURE_ERROR"
        return $AZURE_ERROR
    fi

    echo "Deployer subscription:               $subscription"
    log_info "Azure subscription context configured successfully"
    return $SUCCESS
}

function authenticate_azure_pipeline_context() {
    local use_msi="$1"

    log_info "Authenticating with Azure using appropriate method"

    # Detect authentication context (pipeline vs deployer)
    if is_deployer_environment; then
        log_info "Deployer environment detected, using existing authentication"
        # Use the enhanced authenticate_azure function instead of legacy LogonToAzure
        if ! authenticate_azure "auto"; then
            display_error "Azure Authentication" "Deployer authentication failed" "$AZURE_ERROR"
            return $AZURE_ERROR
        fi
    else
        log_info "Pipeline agent environment detected, configuring authentication"
        if ! configure_pipeline_authentication "$use_msi"; then
            display_error "Azure Authentication" "Pipeline authentication configuration failed" "$AZURE_ERROR"
            return $AZURE_ERROR
        fi
    fi

    log_info "Azure authentication completed successfully"
    return $SUCCESS
}

function configure_pipeline_authentication() {
    local use_msi="$1"

    log_info "Configuring pipeline authentication parameters"

    # Configure non-deployer environment
    if ! configureNonDeployer "${TF_VERSION:-latest}"; then
        display_error "Non-Deployer Config" "Failed to configure non-deployer environment" "$CONFIG_ERROR"
        return $CONFIG_ERROR
    fi

    if [[ "$use_msi" == "true" ]]; then
        log_info "Using Managed Service Identity for authentication"

        # Configure MSI authentication
        export ARM_USE_MSI=true
        export TF_VAR_use_spn=false
        unset ARM_CLIENT_SECRET
        unset ARM_OIDC_TOKEN

        # Verify MSI authentication
        if ! az account show &>/dev/null; then
            log_error "MSI authentication failed"
            return $AZURE_ERROR
        fi
    else
        log_info "Using Service Principal for authentication"

        # Setup authentication variables
        export ARM_CLIENT_ID="$servicePrincipalId"
        export TF_VAR_spn_id="$ARM_CLIENT_ID"

        # Configure OIDC or client secret authentication
        if [[ -n "${idToken:-}" ]]; then
            export ARM_OIDC_TOKEN="$idToken"
            export ARM_USE_OIDC=true
            unset ARM_CLIENT_SECRET
            log_info "Using OIDC authentication"
        else
            export ARM_CLIENT_SECRET="$servicePrincipalKey"
            unset ARM_OIDC_TOKEN
            log_info "Using client secret authentication"
        fi

        export ARM_TENANT_ID="$tenantId"
        export TF_VAR_use_spn=true
    fi

    export ARM_USE_AZUREAD=true

    log_info "Pipeline authentication configured successfully"
    return $SUCCESS
}

function configureNonDeployer() {
    local tf_version="$1"

    log_info "Configuring non-deployer environment with Terraform version: $tf_version"

    # This function configures the environment for non-deployer scenarios
    # Implementation depends on the specific requirements of the SAP automation framework

    # Set up Terraform if needed
    if [[ -n "$tf_version" ]] && [[ "$tf_version" != "latest" ]]; then
        export TF_VERSION="$tf_version"
    fi

    # Configure environment variables for non-deployer execution
    export NON_DEPLOYER_MODE=true

    log_info "Non-deployer environment configured successfully"
    return $SUCCESS
}

function setup_key_vault_integration() {
    log_info "Setting up Key Vault integration"

    # Get Key Vault name from variable group
    local key_vault
    key_vault=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "DEPLOYER_KEYVAULT" "${deployer_environment_file_name}" "keyvault")

    if [[ -z "$key_vault" ]]; then
        log_info "No Key Vault specified, skipping Key Vault integration"
        echo "Deployer Key Vault:                  undefined"
        return $SUCCESS
    fi

    echo "Deployer Key Vault:                  $key_vault"

    # Validate Key Vault existence and access
    if ! setup_keyvault_access "$key_vault"; then
        # Attempt Key Vault recovery if not found
        if ! attempt_keyvault_recovery "$key_vault"; then
            display_error "Key Vault Setup" "Key Vault setup failed: $key_vault" "$AZURE_ERROR"
            return $AZURE_ERROR
        fi
    fi

    log_info "Key Vault integration completed successfully"
    return $SUCCESS
}

function setup_keyvault_access() {
    local key_vault="$1"

    log_info "Setting up Key Vault access: $key_vault"

    # Get Key Vault resource ID
    local key_vault_id
    key_vault_id=$(az resource list --name "$key_vault" --resource-type Microsoft.KeyVault/vaults --query "[].id | [0]" --subscription "$ARM_SUBSCRIPTION_ID" --output tsv 2>/dev/null)

    if [[ -z "$key_vault_id" ]]; then
        log_warn "Key Vault not found: $key_vault"
        return $AZURE_ERROR
    fi

    export TF_VAR_deployer_kv_user_arm_id="$key_vault_id"

    # Configure network access for current IP
    if ! configure_keyvault_network_access "$key_vault"; then
        log_warn "Failed to configure Key Vault network access"
    fi

    log_info "Key Vault access configured successfully"
    return $SUCCESS
}

function attempt_keyvault_recovery() {
    local key_vault="$1"

    log_info "Attempting Key Vault recovery: $key_vault"

    # Check if Key Vault is in deleted state
    local deleted_vault
    deleted_vault=$(az keyvault list-deleted --query "[?name=='$key_vault'].name | [0]" --subscription "$ARM_SUBSCRIPTION_ID" --output tsv 2>/dev/null)

    if [[ -n "$deleted_vault" ]]; then
        echo "##vso[task.logissue type=warning]Key Vault $key_vault is deleted, attempting recovery"
        log_info "Key Vault is in deleted state, attempting recovery"

        if az keyvault recover --name "$key_vault" --subscription "$ARM_SUBSCRIPTION_ID" --output none; then
            log_info "Key Vault recovery successful"
            # Re-attempt setup after recovery
            if setup_keyvault_access "$key_vault"; then
                return $SUCCESS
            fi
        else
            log_error "Key Vault recovery failed"
        fi
    fi

    echo "##vso[task.logissue type=error]Key Vault $key_vault could not be found or recovered"
    return $AZURE_ERROR
}

function configure_keyvault_network_access() {
    local key_vault="$1"

    log_info "Configuring Key Vault network access: $key_vault"

    # Get current public IP
    local current_ip
    current_ip=$(curl -s ipinfo.io/ip 2>/dev/null || echo "")

    if [[ -n "$current_ip" ]]; then
        # Add current IP to Key Vault network rules
        if az keyvault network-rule add --name "$key_vault" --ip-address "$current_ip" --subscription "$ARM_SUBSCRIPTION_ID" --only-show-errors --output none; then
            log_info "Added IP $current_ip to Key Vault network rules"
        else
            log_warn "Failed to add IP to Key Vault network rules"
        fi
    else
        log_warn "Could not determine current IP address"
    fi

    return $SUCCESS
}

function handle_force_reset_scenario() {
    log_info "Handling force reset scenario"

    if [[ "${FORCE_RESET:-false}" == "True" ]]; then
        echo "##vso[task.logissue type=warning]Forcing a re-install"
        log_info "Force reset requested, resetting environment configuration"

        # Reset step counter in environment file
        if [[ -f "$deployer_environment_file_name" ]]; then
            sed -i 's/step=1/step=0/' "$deployer_environment_file_name"
            sed -i 's/step=2/step=0/' "$deployer_environment_file_name"
            sed -i 's/step=3/step=0/' "$deployer_environment_file_name"
        fi

        # Setup remote state storage for force reset
        if ! setup_remote_state_for_reset; then
            return $AZURE_ERROR
        fi
    fi

    return $SUCCESS
}

function setup_remote_state_for_reset() {
    log_info "Setting up remote state storage for force reset"

    # Get remote state configuration from variable group
    local remote_state_sa
    local remote_state_rg

    remote_state_sa=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "TERRAFORM_REMOTE_STORAGE_ACCOUNT_NAME" "${deployer_environment_file_name}" "REMOTE_STATE_SA")
    remote_state_rg=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "TERRAFORM_REMOTE_STORAGE_RESOURCE_GROUP_NAME" "${deployer_environment_file_name}" "REMOTE_STATE_RG")

    if [[ -n "$remote_state_sa" ]]; then
        echo "Terraform Remote State Account:       $remote_state_sa"
    fi

    if [[ -n "$remote_state_rg" ]]; then
        echo "Terraform Remote State RG Name:       $remote_state_rg"
    fi

    # Configure remote state access if both values are available
    if [[ -n "$remote_state_sa" ]] && [[ -n "$remote_state_rg" ]]; then
        if ! configure_remote_state_access "$remote_state_sa" "$remote_state_rg"; then
            return $AZURE_ERROR
        fi

        export REINSTALL_ACCOUNTNAME="$remote_state_sa"
        export REINSTALL_SUBSCRIPTION="$ARM_SUBSCRIPTION_ID"
        export REINSTALL_RESOURCE_GROUP="$remote_state_rg"
    fi

    return $SUCCESS
}

function configure_remote_state_access() {
    local storage_account="$1"
    local resource_group="$2"

    log_info "Configuring remote state storage access: $storage_account"

    # Get storage account resource ID
    local tfstate_resource_id
    tfstate_resource_id=$(az resource list --name "$storage_account" --subscription "$ARM_SUBSCRIPTION_ID" --resource-type Microsoft.Storage/storageAccounts --query "[].id | [0]" -o tsv 2>/dev/null)

    if [[ -n "$tfstate_resource_id" ]]; then
        # Configure network access for current IP
        local current_ip
        current_ip=$(curl -s ipinfo.io/ip 2>/dev/null || echo "")

        if [[ -n "$current_ip" ]]; then
            if az storage account network-rule add --account-name "$storage_account" --resource-group "$resource_group" --ip-address "$current_ip" --only-show-errors --output none; then
                log_info "Added IP $current_ip to storage account network rules"
            else
                log_warn "Failed to add IP to storage account network rules"
            fi
        fi
    else
        log_warn "Storage account resource ID not found: $storage_account"
    fi

    return $SUCCESS
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

log_info "Azure integration module loaded successfully"
log_debug "Backward compatibility functions available for legacy scripts"
log_debug "Azure timeouts - CLI: ${AZ_CLI_TIMEOUT}s, Login: ${AZ_LOGIN_TIMEOUT}s"
