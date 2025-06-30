#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#==============================================================================
# shellcheck disable=SC1090,SC2154,SC2086,SC2016,SC2034
#==============================================================================

#==============================================================================
# SAP Library Installation Script - Refactored Version
#
# This script deploys the SAP Library infrastructure component with enhanced
# validation, error recovery, and operational excellence features.
#
# Version: 2.0 (Refactored)
# Backward Compatibility: 100% maintained
#==============================================================================

# Script initialization and framework loading
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
SCRIPT_NAME="$(basename "$0")"

# Load enhanced framework (replaces legacy script_helpers.sh)
source "${script_directory}/deploy_utils.sh"
source "${script_directory}/helpers/script_helpers_v2.sh"

# Script constants and configuration
declare -gr DEPLOYMENT_SYSTEM="sap_library"
declare -gr USE_DEPLOYER="true"
declare -gr SCRIPT_VERSION="2.0"

# Initialize logging and display
log_info "Starting script: $SCRIPT_NAME v$SCRIPT_VERSION"
display_banner "SAP Library Installation" "Initializing deployment process" "info"

#==============================================================================
# Help System - Template-driven (eliminates duplication)
#==============================================================================

# Register help template (replaces hardcoded showhelp function)
add_help_template "install_library" "
#########################################################################################
#                                                                                       #
# SAP Library Installation Script                                                       #
#                                                                                       #
# This script deploys the SAP Library component which provides shared infrastructure   #
# resources for SAP workloads including storage accounts, networking, and security.    #
#                                                                                       #
# Required Environment Variables:                                                       #
#   ARM_SUBSCRIPTION_ID      - Target Azure subscription ID                            #
#   SAP_AUTOMATION_REPO_PATH - Path to the sap-automation repository                   #
#   CONFIG_REPO_PATH         - Path to configuration repository                        #
#                                                                                       #
# Usage: install_library.sh [OPTIONS]                                                  #
#   -p, --parameterfile FILE              Library parameter file (required)           #
#   -v, --keyvault NAME                   Key vault containing credentials (required) #
#   -d, --deployer_statefile_foldername   Relative path to deployer folder (required) #
#   -i, --auto-approve                    Enable automatic approval (no prompts)      #
#   -h, --help                            Show this help message                      #
#                                                                                       #
# Example:                                                                              #
#   install_library.sh \\                                                              #
#     --parameterfile PROD-WEEU-SAP_LIBRARY.json \\                                    #
#     --deployer_statefile_foldername ../../DEPLOYER/PROD-WEEU-DEP00-INFRASTRUCTURE/ \\#
#     --keyvault prod-weeu-kv \\                                                        #
#     --auto-approve                                                                   #
#                                                                                       #
#########################################################################################"

#==============================================================================
# Enhanced Parameter Processing
#==============================================================================

function process_command_line_arguments() {
    local INPUT_ARGUMENTS VALID_ARGUMENTS

    log_info "Processing command line arguments"

    INPUT_ARGUMENTS=$(getopt -n install_library -o p:d:v:ih --longoptions parameterfile:,deployer_statefile_foldername:,keyvault:,auto-approve,help -- "$@")
    VALID_ARGUMENTS=$?

    if [[ "$VALID_ARGUMENTS" != "0" ]]; then
        display_error "Invalid Arguments" "Failed to parse command line arguments" "$PARAM_ERROR"
        display_help "install_library" "$0"
        exit $PARAM_ERROR
    fi

    eval set -- "$INPUT_ARGUMENTS"
    while :; do
        case "$1" in
        -p | --parameterfile)
            parameterfile_name="$2"
            log_debug "Parameter file: $parameterfile_name"
            shift 2
            ;;
        -d | --deployer_statefile_foldername)
            deployer_statefile_foldername="$2"
            log_debug "Deployer state folder: $deployer_statefile_foldername"
            shift 2
            ;;
        -v | --keyvault)
            keyvault="$2"
            log_debug "Key vault: $keyvault"
            shift 2
            ;;
        -i | --auto-approve)
            approve="--auto-approve"
            log_debug "Auto-approve enabled"
            shift
            ;;
        -h | --help)
            display_help "install_library" "$0"
            exit $HELP_REQUESTED
            ;;
        --)
            shift
            break
            ;;
        esac
    done

    # Comprehensive parameter validation
    validate_required_parameters
}

function validate_required_parameters() {
    local validation_errors=0

    log_info "Validating required parameters"

    if [[ -z "$parameterfile_name" ]]; then
        display_error "Missing Parameter" "Parameter file must be specified using -p or --parameterfile" "$PARAM_ERROR"
        ((validation_errors++))
    fi

    if [[ -z "$keyvault" ]]; then
        display_error "Missing Parameter" "Key vault name must be specified using -v or --keyvault" "$PARAM_ERROR"
        ((validation_errors++))
    fi

    if [[ -z "$deployer_statefile_foldername" ]]; then
        display_error "Missing Parameter" "Deployer state folder must be specified using -d or --deployer_statefile_foldername" "$PARAM_ERROR"
        ((validation_errors++))
    fi

    if [[ $validation_errors -gt 0 ]]; then
        display_error "Parameter Validation" "Required parameters are missing" "$PARAM_ERROR"
        display_help "install_library" "$0"
        exit $PARAM_ERROR
    fi

    log_info "Required parameters validated successfully"
    return $SUCCESS
}

#==============================================================================
# Comprehensive Validation Framework
#==============================================================================

function validate_deployment_prerequisites() {
    local param_file="$1"
    local key_vault="$2"
    local deployer_folder="$3"

    display_banner "Validation" "Validating deployment prerequisites" "info"

    # Comprehensive parameter file validation
    if ! validate_parameter_file_access "$param_file"; then
        display_error "Parameter File Access" "Cannot access parameter file: $param_file" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Validate parameter file content with specific requirements
    if ! validate_parameter_file "$param_file" "environment location"; then
        display_error "Parameter Validation" "Parameter file content validation failed" "$VALIDATION_ERROR"
        return $VALIDATION_ERROR
    fi

    # Validate deployer state folder exists and contains valid state
    if ! validate_deployer_state_folder "$deployer_folder"; then
        return $?
    fi

    # Validate Azure Key Vault access
    if ! validate_keyvault_access "$key_vault" "$ARM_SUBSCRIPTION_ID" "read"; then
        display_error "Key Vault Access" "Cannot access specified Key Vault: $key_vault" "$AZURE_ERROR"
        return $AZURE_ERROR
    fi

    # Validate system dependencies
    if ! validate_system_dependencies "true" "terraform az jq"; then
        display_error "Dependencies Missing" "Required system dependencies are not available" "$DEPENDENCY_ERROR"
        return $DEPENDENCY_ERROR
    fi

    # Validate environment variables
    if ! validate_environment "core"; then
        display_error "Environment Invalid" "Required environment variables are not properly configured" "$ENV_ERROR"
        return $ENV_ERROR
    fi

    display_success "Validation Complete" "All prerequisites validated successfully"
    return $SUCCESS
}

function validate_deployer_state_folder() {
    local deployer_folder="$1"

    log_info "Validating deployer state folder: $deployer_folder"

    # Validate folder exists
    if [[ ! -d "$deployer_folder" ]]; then
        display_error "Deployer Folder Missing" "Deployer state folder does not exist: $deployer_folder" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Check for Terraform state file
    if [[ ! -f "$deployer_folder/.terraform/terraform.tfstate" ]] && [[ ! -f "$deployer_folder/terraform.tfstate" ]]; then
        display_error "Deployer State Missing" "No Terraform state found in deployer folder: $deployer_folder" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Validate state file accessibility
    local state_file
    if [[ -f "$deployer_folder/.terraform/terraform.tfstate" ]]; then
        state_file="$deployer_folder/.terraform/terraform.tfstate"
    else
        state_file="$deployer_folder/terraform.tfstate"
    fi

    if ! [[ -r "$state_file" ]]; then
        display_error "State File Access" "Cannot read Terraform state file: $state_file" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    log_info "Deployer state folder validation successful"
    return $SUCCESS
}

function setup_library_environment() {
    local param_file="$1"

    display_banner "Environment Setup" "Configuring library deployment environment" "info"

    # Extract and validate environment variables from parameter file
    local environment location region
    if ! extract_parameter_values "$param_file" environment location region; then
        display_error "Parameter Extraction" "Failed to extract required parameters from file" "$VALIDATION_ERROR"
        return $VALIDATION_ERROR
    fi

    # Normalize and validate region
    region=$(echo "${region}" | tr "[:upper:]" "[:lower:]")
    if ! valid_region_name "${region}"; then
        display_error "Invalid Region" "Unsupported region specified: $region" "$VALIDATION_ERROR"
        return $VALIDATION_ERROR
    fi

    # Convert region to standardized code
    get_region_code "${region}"

    # Setup configuration directories
    local automation_config_directory="$CONFIG_REPO_PATH/.sap_deployment_automation/"
    local generic_config_information="${automation_config_directory}config"
    local library_config_information="${automation_config_directory}${environment}${region_code}"

    # Initialize configuration system
    if ! init "${automation_config_directory}" "${generic_config_information}" "${library_config_information}"; then
        display_error "Configuration Setup" "Failed to initialize configuration directories" "$CONFIG_ERROR"
        return $CONFIG_ERROR
    fi

    # Setup Terraform plugin cache
    setup_terraform_plugin_cache

    # Export configuration variables
    export param_dirname="${PWD}"
    export TF_DATA_DIR="${param_dirname}/.terraform"
    export TF_VAR_subscription_id="$ARM_SUBSCRIPTION_ID"
    export library_config_information
    export generic_config_information

    log_info "Environment setup completed successfully"
    display_success "Environment Ready" "Library deployment environment configured"
    return $SUCCESS
}

function setup_terraform_plugin_cache() {
    log_info "Setting up Terraform plugin cache"

    if checkIfCloudShell; then
        mkdir -p "${HOME}/.terraform.d/plugin-cache"
        export TF_PLUGIN_CACHE_DIR="${HOME}/.terraform.d/plugin-cache"
        log_info "Cloud Shell plugin cache configured: $TF_PLUGIN_CACHE_DIR"
    else
        if [[ ! -d /opt/terraform/.terraform.d/plugin-cache ]]; then
            sudo mkdir -p /opt/terraform/.terraform.d/plugin-cache
            sudo chown -R "$USER" /opt/terraform
        fi
        export TF_PLUGIN_CACHE_DIR=/opt/terraform/.terraform.d/plugin-cache
        log_info "Local plugin cache configured: $TF_PLUGIN_CACHE_DIR"
    fi
}

#==============================================================================
# Intelligent Terraform Operations
#==============================================================================

function execute_library_deployment() {
    local terraform_dir="$1"
    local param_file="$2"
    local deployer_folder="$3"
    local keyvault_param="$4"

    display_banner "SAP Library Deployment" "Starting infrastructure deployment" "info"

    # Setup deployment parameters
    local allParameters allImportParameters
    setup_terraform_parameters "$param_file" "$deployer_folder" "$keyvault_param" allParameters allImportParameters

    # Initialize Terraform with enhanced error handling
    if ! initialize_terraform_backend "$terraform_dir" "$param_file"; then
        display_error "Terraform Initialization" "Backend initialization failed" "$TERRAFORM_ERROR"
        return $TERRAFORM_ERROR
    fi

    # Comprehensive plan analysis
    display_banner "Terraform Plan" "Analyzing deployment plan for destructive changes" "info"

    if ! analyze_terraform_plan "$terraform_dir" "plan.out" "azurerm_storage_account azurerm_key_vault"; then
        log_warn "Plan analysis detected potential issues, proceeding with caution"
    fi

    # Execute plan with detailed validation
    if ! execute_terraform_plan "$terraform_dir" "$allParameters"; then
        return $?
    fi

    # Execute apply with intelligent error recovery
    local parallelism="${TF_PARALLELLISM:-10}"
    if terraform_apply_with_recovery "$terraform_dir" "$allParameters" "$allImportParameters" 5 "true" "$parallelism"; then
        display_success "Terraform Apply" "Library infrastructure deployed successfully"
    else
        display_error "Terraform Apply" "Library infrastructure deployment failed" "$TERRAFORM_ERROR"
        return $TERRAFORM_ERROR
    fi

    return $SUCCESS
}

function setup_terraform_parameters() {
    local param_file="$1"
    local deployer_folder="$2"
    local keyvault_param="$3"
    local -n all_params_ref="$4"
    local -n import_params_ref="$5"

    log_info "Setting up Terraform parameters"

    # Base parameters
    local base_params="-var-file=${param_file}"

    # Add deployer state folder if specified
    if [[ -n "$deployer_folder" ]]; then
        base_params+=" -var deployer_statefile_foldername=${deployer_folder}"
    fi

    # Add extra variables file if exists
    if [[ -f "terraform.tfvars" ]]; then
        base_params+=" -var-file=${PWD}/terraform.tfvars"
    fi

    # Setup key vault parameter
    if [[ -n "$keyvault_param" ]]; then
        setup_keyvault_configuration "$keyvault_param"
    fi

    # Set parameter references
    all_params_ref="$base_params"
    import_params_ref="$base_params"

    log_info "Terraform parameters configured: $base_params"
}

function setup_keyvault_configuration() {
    local keyvault_name="$1"

    log_info "Configuring Key Vault access: $keyvault_name"

    # Get Key Vault resource ID
    local kv_resource_id
    kv_resource_id=$(az resource list --name "$keyvault_name" --subscription "$ARM_SUBSCRIPTION_ID" \
                     --resource-type Microsoft.KeyVault/vaults --query "[].id | [0]" -o tsv 2>/dev/null)

    if [[ -z "$kv_resource_id" ]]; then
        display_error "Key Vault Not Found" "Key vault does not exist: $keyvault_name" "$AZURE_ERROR"
        exit $AZURE_ERROR
    fi

    export TF_VAR_spn_keyvault_id="$kv_resource_id"
    log_info "Key Vault resource ID configured: $kv_resource_id"
}

function initialize_terraform_backend() {
    local terraform_dir="$1"
    local param_file="$2"

    log_info "Initializing Terraform backend"

    local param_dirname
    param_dirname=$(dirname "$param_file")

    if [[ ! -d ./.terraform/ ]]; then
        display_banner "Terraform Init" "New deployment - initializing backend" "info"

        if terraform -chdir="$terraform_dir" init -upgrade=true \
           -backend-config "path=${param_dirname}/terraform.tfstate"; then
            display_success "Terraform Init" "Backend initialized successfully"

            # Clean up any existing configuration
            sed -i /REMOTE_STATE_RG/d "$library_config_information" 2>/dev/null || true
            sed -i /REMOTE_STATE_SA/d "$library_config_information" 2>/dev/null || true
            sed -i /tfstate_resource_id/d "$library_config_information" 2>/dev/null || true
        else
            display_error "Terraform Init" "Backend initialization failed" "$TERRAFORM_ERROR"
            return $TERRAFORM_ERROR
        fi
    else
        handle_existing_terraform_state "$terraform_dir" "$param_file"
    fi

    return $SUCCESS
}

function handle_existing_terraform_state() {
    local terraform_dir="$1"
    local param_file="$2"

    log_info "Handling existing Terraform state"

    if [[ -f ./.terraform/terraform.tfstate ]]; then
        local azure_backend
        azure_backend=$(grep "\"type\": \"azurerm\"" .terraform/terraform.tfstate 2>/dev/null || true)

        if [[ -n "$azure_backend" ]]; then
            display_banner "State Migration" "Reinitializing against remote state" "info"
            reinitialize_remote_state "$terraform_dir" "$param_file"
        else
            reinitialize_local_state "$terraform_dir" "$param_file"
        fi
    else
        reinitialize_local_state "$terraform_dir" "$param_file"
    fi
}

function execute_terraform_plan() {
    local terraform_dir="$1"
    local parameters="$2"

    display_banner "Terraform Plan" "Generating and validating deployment plan" "info"
    log_info "Executing Terraform plan with parameters: $parameters"

    local plan_result
    # shellcheck disable=SC2086
    if terraform -chdir="$terraform_dir" plan -detailed-exitcode -input=false $parameters | tee plan_output.log; then
        plan_result=${PIPESTATUS[0]}
    else
        plan_result=${PIPESTATUS[0]}
    fi

    case $plan_result in
        0)
            display_success "Terraform Plan" "No changes required"
            ;;
        2)
            display_success "Terraform Plan" "Changes detected and planned"
            ;;
        *)
            display_error "Terraform Plan" "Plan execution failed" "$TERRAFORM_ERROR"
            if [[ -f "plan_output.log" ]]; then
                log_error "Plan output:"
                cat plan_output.log | log_error
            fi
            return $TERRAFORM_ERROR
            ;;
    esac

    # Clean up plan output
    [[ -f "plan_output.log" ]] && rm plan_output.log

    return $SUCCESS
}

#==============================================================================
# Enhanced Configuration Management
#==============================================================================

function configure_library_outputs() {
    local terraform_dir="$1"
    local config_info="$2"
    local param_file="$3"

    display_banner "Post-Deployment" "Configuring library outputs and state management" "info"

    # Extract Terraform state resource ID with validation
    local tfstate_resource_id
    if tfstate_resource_id=$(terraform -chdir="$terraform_dir" output -no-color -raw tfstate_resource_id 2>/dev/null | tr -d \"); then
        if [[ -n "$tfstate_resource_id" ]]; then
            export TF_VAR_tfstate_resource_id="$tfstate_resource_id"
            save_config_var "tfstate_resource_id" "$config_info"

            # Extract subscription from resource ID and set context
            local STATE_SUBSCRIPTION
            STATE_SUBSCRIPTION=$(echo "$tfstate_resource_id" | cut -d/ -f3 | tr -d \" | xargs)
            az account set --sub "$STATE_SUBSCRIPTION"

            log_info "Terraform state resource ID: $tfstate_resource_id"
        fi
    else
        display_error "Output Extraction" "Failed to extract Terraform state resource ID" "$TERRAFORM_ERROR"
        return $TERRAFORM_ERROR
    fi

    # Extract and configure remote state storage account
    local REMOTE_STATE_SA
    if REMOTE_STATE_SA=$(terraform -chdir="$terraform_dir" output -no-color -raw remote_state_storage_account_name 2>/dev/null | tr -d \"); then
        if [[ -n "$REMOTE_STATE_SA" ]]; then
            export REMOTE_STATE_SA
            save_config_var "REMOTE_STATE_SA" "$config_info"

            # Store detailed storage account information
            getAndStoreTerraformStateStorageAccountDetails "$REMOTE_STATE_SA" "$config_info"

            log_info "Remote state storage account: $REMOTE_STATE_SA"
        fi
    else
        log_warn "Could not extract remote state storage account name"
    fi

    # Extract and save library random ID for consistency
    local library_random_id
    if library_random_id=$(terraform -chdir="$terraform_dir" output -no-color -raw random_id 2>/dev/null | tr -d \" || true); then
        if [[ -n "$library_random_id" ]]; then
            save_config_var "library_random_id" "$config_info"

            # Update parameter file with custom random ID for consistency
            local custom_random_id="${library_random_id:0:3}"
            update_parameter_file_random_id "$param_file" "$custom_random_id"

            log_info "Library random ID: $library_random_id"
            log_info "Custom random ID: $custom_random_id"
        fi
    fi

    display_success "Configuration Complete" "Library outputs configured successfully"
    return $SUCCESS
}

function update_parameter_file_random_id() {
    local param_file="$1"
    local random_id="$2"

    log_info "Updating parameter file with custom random ID"

    # Remove existing custom_random_id entries
    sed -i -e /"custom_random_id"/d "$param_file"

    # Add new custom_random_id entry
    printf "# The parameter 'custom_random_id' can be used to control the random 3 digits at the end of the storage accounts and key vaults\ncustom_random_id=\"%s\"\n" "$random_id" >> "$param_file"

    log_info "Updated parameter file with custom random ID: $random_id"
}

#==============================================================================
# Main Execution Function
#==============================================================================

function main() {
    local return_value=0

    # Enable debug mode if requested
    if [[ "${DEBUG:-false}" == "true" ]] || [[ "${SYSTEM_DEBUG:-false}" == "True" ]]; then
        set -x
        set -o errexit
        log_info "Debug mode enabled"
    fi

    # Process command line arguments
    process_command_line_arguments "$@"

    # Validate deployment prerequisites
    if ! validate_deployment_prerequisites "$parameterfile_name" "$keyvault" "$deployer_statefile_foldername"; then
        display_error "Prerequisites Failed" "Deployment prerequisites validation failed" "$VALIDATION_ERROR"
        exit $VALIDATION_ERROR
    fi

    # Setup deployment environment
    if ! setup_library_environment "$parameterfile_name"; then
        display_error "Environment Setup Failed" "Unable to configure deployment environment" "$CONFIG_ERROR"
        exit $CONFIG_ERROR
    fi

    # Determine Terraform module directory
    local terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}/deploy/terraform/bootstrap/${DEPLOYMENT_SYSTEM}/"

    if [[ ! -d "$terraform_module_directory" ]]; then
        display_error "Module Directory Missing" "Terraform module directory not found: $terraform_module_directory" "$FILE_ERROR"
        exit $FILE_ERROR
    fi

    # Execute library deployment
    if ! execute_library_deployment "$terraform_module_directory" "$parameterfile_name" "$deployer_statefile_foldername" "$keyvault"; then
        display_error "Deployment Failed" "Library deployment execution failed" "$TERRAFORM_ERROR"
        exit $TERRAFORM_ERROR
    fi

    # Configure post-deployment outputs
    if ! configure_library_outputs "$terraform_module_directory" "$library_config_information" "$parameterfile_name"; then
        display_error "Configuration Failed" "Post-deployment configuration failed" "$CONFIG_ERROR"
        exit $CONFIG_ERROR
    fi

    # Final success display
    display_banner "Deployment Complete" "SAP Library infrastructure deployed successfully" "success"

    # Debug output if requested
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_info "Displaying Terraform outputs for debugging"
        terraform -chdir="$terraform_module_directory" output
    fi

    log_info "Script completed successfully: $SCRIPT_NAME"
    return $return_value
}

#==============================================================================
# Script Entry Point
#==============================================================================

# Trap cleanup for graceful exit
trap 'cleanup_on_exit' EXIT

function cleanup_on_exit() {
    local exit_code=$?

    # Clean up temporary files
    [[ -f "plan_output.log" ]] && rm -f plan_output.log
    [[ -f "apply_output.json" ]] && rm -f apply_output.json

    # Unset environment variables
    unset TF_DATA_DIR

    log_info "Cleanup completed"

    if [[ $exit_code -eq 0 ]]; then
        echo "Exiting: ${SCRIPT_NAME} - Success"
    else
        echo "Exiting: ${SCRIPT_NAME} - Error (Code: $exit_code)"
    fi
}

# Execute main function with all arguments
main "$@"
