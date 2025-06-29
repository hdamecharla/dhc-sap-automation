#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#########################################################################################
# SAP Deployer Installation Script - Refactored Version                                #
# This script deploys the SAP deployer infrastructure using the modular framework      #
#########################################################################################

# Script setup and initialization
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
SCRIPT_NAME="$(basename "$0")"

# Load the refactored framework (replaces legacy script_helpers.sh)
source "${script_directory}/log_utils.sh"
source "${script_directory}/deploy_utils.sh"
source "${script_directory}/helpers/script_helpers_v2.sh"

# Initialize logging and display entry banner
log_info "Starting script: $SCRIPT_NAME"
display_banner "SAP Deployer Installation" "Initializing deployment process" "info"

#########################################################################################
# CONFIGURATION AND CONSTANTS                                                          #
#########################################################################################

declare -gr DEPLOYMENT_SYSTEM="sap_deployer"
declare -gr DEFAULT_PARALLELISM=10
declare -gr NETWORK_RULE_DELAY=30

# Initialize script variables
declare -g parameterfile=""
declare -g approve=""
# shellcheck disable=SC2034
declare -g return_value=0

#########################################################################################
# HELP SYSTEM - Using Template-Driven Approach                                        #
#########################################################################################

# Register help template for this script (replaces hardcoded showhelp function)
add_help_template "install_deployer" "
#########################################################################################
#                                                                                       #
# SAP Deployer Installation Script                                                     #
#                                                                                       #
# This script deploys the SAP deployer infrastructure component using Terraform.       #
# The deployer provides the foundation for SAP automation operations.                  #
#                                                                                       #
# Required Environment Variables:                                                       #
#   ARM_SUBSCRIPTION_ID     - Target Azure subscription ID                             #
#   SAP_AUTOMATION_REPO_PATH - Path to the sap-automation repository                   #
#   CONFIG_REPO_PATH        - Path to configuration repository                         #
#                                                                                       #
# Configuration Persistence:                                                           #
#   Configuration data is stored in: [CONFIG_REPO_PATH]/.sap_deployment_automation/   #
#                                                                                       #
# Usage: install_deployer.sh [OPTIONS]                                                 #
#   -p, --parameterfile FILE    Deployer parameter file (required)                    #
#   -i, --auto-approve          Enable automatic approval (no prompts)                #
#   -h, --help                  Show this help message                                #
#                                                                                       #
# Example:                                                                              #
#   install_deployer.sh \\                                                             #
#     --parameterfile PROD-WEEU-DEP00-INFRASTRUCTURE.json \\                          #
#     --auto-approve                                                                   #
#                                                                                       #
#########################################################################################"

#########################################################################################
# PARAMETER PROCESSING - Enhanced with Validation                                      #
#########################################################################################

function process_command_line_arguments() {
    local INPUT_ARGUMENTS
    local VALID_ARGUMENTS

    INPUT_ARGUMENTS=$(getopt -n install_deployer -o p:ih --longoptions parameterfile:,auto-approve,help -- "$@")
    VALID_ARGUMENTS=$?

    if [[ "$VALID_ARGUMENTS" != "0" ]]; then
        display_error "Invalid Arguments" "Failed to parse command line arguments" "$PARAM_ERROR"
        display_help "install_deployer" "$0"
        exit $PARAM_ERROR
    fi

    eval set -- "$INPUT_ARGUMENTS"
    while :; do
        case "$1" in
        -p | --parameterfile)
            parameterfile="$2"
            shift 2
            ;;
        -i | --auto-approve)
            approve="--auto-approve"
            shift
            ;;
        -h | --help)
            display_help "install_deployer" "$0"
            exit $HELP_REQUESTED
            ;;
        --)
            shift
            break
            ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$parameterfile" ]]; then
        display_error "Parameter Required" "Parameter file must be specified using -p or --parameterfile" "$PARAM_ERROR"
        display_help "install_deployer" "$0"
        exit $PARAM_ERROR
    fi

    log_info "Command line processing completed successfully"
    log_debug "Parameter file: $parameterfile, Auto-approve: ${approve:-false}"
}

#########################################################################################
# VALIDATION FUNCTIONS - Using Refactored Framework                                    #
#########################################################################################

function validate_parameter_file_access() {
    local param_file="$1"
    local param_dirname

    log_info "Validating parameter file access and location"

    # Validate parameter file exists
    if [[ ! -f "$param_file" ]]; then
        display_error "File Not Found" "Parameter file does not exist: $param_file" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Validate parameter file is in current directory (legacy requirement)
    param_dirname=$(dirname "$param_file")
    if [[ "$param_dirname" != '.' ]]; then
        display_error "Invalid Location" "Please run this command from the folder containing the parameter file" "$PARAM_ERROR"
        log_error "Current directory: $(pwd), Parameter file directory: $param_dirname"
        return $PARAM_ERROR
    fi

    # Validate parameter file content using refactored validation
    if ! validate_parameter_file "$param_file" "environment location"; then
        display_error "Invalid Parameter File" "Parameter file validation failed" "$VALIDATION_ERROR"
        return $VALIDATION_ERROR
    fi

    log_info "Parameter file validation completed successfully"
    return $SUCCESS
}

function setup_deployment_environment() {
    local param_file="$1"

    log_info "Setting up deployment environment"

    # Extract and validate parameters using refactored functions
    validate_key_parameters "$param_file"
    local validation_result=$?
    if [[ $validation_result -ne $SUCCESS ]]; then
        display_error "Parameter Validation Failed" "Key parameters could not be validated" "$validation_result"
        return $validation_result
    fi

    # Normalize region and get region code
    region=$(echo "${region}" | tr "[:upper:]" "[:lower:]")
    get_region_code "$region"

    # Setup configuration directories
    local key automation_config_directory generic_config_information deployer_config_information
    key=$(echo "$param_file" | cut -d. -f1)
    automation_config_directory="$CONFIG_REPO_PATH/.sap_deployment_automation/"
    generic_config_information="${automation_config_directory}config"
    deployer_config_information="${automation_config_directory}${environment}${region_code}"

    # Initialize configuration system
    init "$automation_config_directory" "$generic_config_information" "$deployer_config_information"

    # Validate required environment variables
    if ! validate_environment "core"; then
        display_error "Environment Validation Failed" "Required environment variables are not properly configured" "$ENV_ERROR"
        return $ENV_ERROR
    fi

    # Setup Terraform environment
    local param_dirname
    param_dirname=$(pwd)
    export TF_DATA_DIR="${param_dirname}/.terraform"

    # Get and set agent IP
    local this_ip
    this_ip=$(curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
    export TF_VAR_Agent_IP="$this_ip"

    log_info "Deployment environment setup completed"
    log_info "Configuration file: $param_file"
    log_info "Deployment region: $region"
    log_info "Deployment region code: $region_code"
    log_info "Agent IP: $this_ip"

    return $SUCCESS
}

#########################################################################################
# TERRAFORM OPERATIONS - Using Enhanced Framework Functions                           #
#########################################################################################

function initialize_terraform_backend() {
    local terraform_dir="$1"
    local param_dirname="$2"
    local var_file="$3"

    log_info "Initializing Terraform backend"

    if [[ ! -d ".terraform/" ]]; then
        display_banner "Terraform Initialization" "New deployment - initializing local backend" "info"
        terraform -chdir="$terraform_dir" init -upgrade=true -backend-config "path=${param_dirname}/terraform.tfstate"
        return $?
    fi

    # Handle existing Terraform state
    if [[ ! -f ".terraform/terraform.tfstate" ]]; then
        display_banner "Terraform Initialization" "No existing state - initializing as new deployment" "info"
        terraform -chdir="$terraform_dir" init -upgrade=true -backend-config "path=${param_dirname}/terraform.tfstate"
        return $?
    fi

    # Check for Azure backend migration
    local azure_backend
    azure_backend=$(grep "\"type\": \"azurerm\"" .terraform/terraform.tfstate 2>/dev/null || true)

    if [[ -n "$azure_backend" ]]; then
        handle_azure_backend_reinit "$terraform_dir" "$var_file"
    else
        display_banner "Terraform Initialization" "Initializing with local backend" "info"
        terraform -chdir="$terraform_dir" init -upgrade=true -backend-config "path=${param_dirname}/terraform.tfstate"
    fi

    return $?
}

function handle_azure_backend_reinit() {
    local terraform_dir="$1"
    local var_file="$2"

    log_info "Handling Azure backend reinitialization"
    display_banner "Azure Backend" "State is already migrated to Azure - reinitializing" "info"

    # Extract backend configuration from existing state
    local REINSTALL_SUBSCRIPTION REINSTALL_ACCOUNTNAME REINSTALL_RESOURCE_GROUP
    REINSTALL_SUBSCRIPTION=$(grep -m1 "subscription_id" "${param_dirname}/.terraform/terraform.tfstate" | cut -d ':' -f2 | tr -d '", \r' | xargs 2>/dev/null || true)
    REINSTALL_ACCOUNTNAME=$(grep -m1 "storage_account_name" "${param_dirname}/.terraform/terraform.tfstate" | cut -d ':' -f2 | tr -d ' ",\r' | xargs 2>/dev/null || true)
    REINSTALL_RESOURCE_GROUP=$(grep -m1 "resource_group_name" "${param_dirname}/.terraform/terraform.tfstate" | cut -d ':' -f2 | tr -d ' ",\r' | xargs 2>/dev/null || true)

    # Validate storage account exists
    local tfstate_resource_id
    tfstate_resource_id=$(az resource list --name "$REINSTALL_ACCOUNTNAME" --subscription "$REINSTALL_SUBSCRIPTION" --resource-type Microsoft.Storage/storageAccounts --query "[].id | [0]" -o tsv 2>/dev/null || true)

    if [[ -n "$tfstate_resource_id" ]]; then
        handle_remote_backend_init "$terraform_dir" "$var_file" "$REINSTALL_SUBSCRIPTION" "$REINSTALL_RESOURCE_GROUP" "$REINSTALL_ACCOUNTNAME" "$tfstate_resource_id"
    else
        log_warn "Storage account not found, falling back to local backend"
        terraform -chdir="$terraform_dir" init -upgrade=true -reconfigure --backend-config "path=${param_dirname}/terraform.tfstate"
    fi
}

function handle_remote_backend_init() {
    local terraform_dir="$1"
    local var_file="$2"
    local subscription="$3"
    local resource_group="$4"
    local storage_account="$5"
    local tfstate_resource_id="$6"

    log_info "Initializing remote Azure backend"

    # Configure network access for current IP
    local this_ip
    this_ip=$(curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")

    if [[ "$this_ip" != "unknown" ]]; then
        log_info "Adding current IP to storage account network rules: $this_ip"
        az storage account network-rule add \
            --account-name "$storage_account" \
            --resource-group "$resource_group" \
            --ip-address "$this_ip" \
            --only-show-errors --output none

        display_banner "Network Configuration" "Waiting for network rule to take effect" "info"
        sleep $NETWORK_RULE_DELAY
    fi

    # Set up environment for remote backend
    export TF_VAR_tfstate_resource_id="$tfstate_resource_id"
    local remote_terraform_dir="${SAP_AUTOMATION_REPO_PATH}/deploy/terraform/run/sap_deployer"

    # Initialize with remote backend
    if terraform -chdir="$remote_terraform_dir" init -upgrade=true \
        --backend-config "subscription_id=$subscription" \
        --backend-config "resource_group_name=$resource_group" \
        --backend-config "storage_account_name=$storage_account" \
        --backend-config "container_name=tfstate" \
        --backend-config "key=${key}.terraform.tfstate"; then

        display_success "Terraform Backend" "Remote backend initialization successful"

        # Refresh state and handle key vault access
        terraform -chdir="$remote_terraform_dir" refresh -var-file="$var_file"
        handle_keyvault_access "$remote_terraform_dir"

        export TF_VAR_recover=true
    else
        display_error "Terraform Backend" "Remote backend initialization failed" "$TERRAFORM_ERROR"
        return $TERRAFORM_ERROR
    fi
}

function handle_keyvault_access() {
    local terraform_dir="$1"

    log_info "Configuring Key Vault access"

    # Extract Key Vault information from Terraform output
    local keyvault_id keyvault keyvault_resource_group keyvault_subscription
    keyvault_id=$(terraform -chdir="$terraform_dir" output deployer_kv_user_arm_id 2>/dev/null | tr -d \" || true)

    if [[ -n "$keyvault_id" ]]; then
        keyvault=$(echo "$keyvault_id" | cut -d / -f9)
        keyvault_resource_group=$(echo "$keyvault_id" | cut -d / -f5)
        keyvault_subscription=$(echo "$keyvault_id" | cut -d / -f3)

        log_info "Enabling Key Vault public network access: $keyvault"
        az keyvault update \
            --name "$keyvault" \
            --resource-group "$keyvault_resource_group" \
            --subscription "$keyvault_subscription" \
            --public-network-access Enabled \
            --only-show-errors --output none

        display_banner "Key Vault Access" "Waiting for network configuration to take effect" "info"
        sleep $NETWORK_RULE_DELAY
    fi
}

#########################################################################################
# DEPLOYMENT EXECUTION - Using Enhanced Error Handling                                 #
#########################################################################################

function execute_terraform_deployment() {
    local terraform_dir="$1"
    local var_file="$2"

    display_banner "Terraform Deployment" "Starting infrastructure deployment" "info"

    # Setup parameters
    local extra_vars=""
    if [[ -f "terraform.tfvars" ]]; then
        extra_vars=" -var-file=${param_dirname}/terraform.tfvars "
    fi

    local allParameters allImportParameters
    allParameters=$(printf " -var-file=%s %s" "$var_file" "$extra_vars")
    allImportParameters=$(printf " -var-file=%s %s " "$var_file" "$extra_vars")

    log_info "Terraform parameters: $allParameters"

    # Validate dependencies before deployment
    if ! validate_system_dependencies "true" "terraform az jq"; then
        display_error "Dependencies Missing" "Required system dependencies are not available" "$DEPENDENCY_ERROR"
        return $DEPENDENCY_ERROR
    fi

    # Execute Terraform plan
    display_banner "Terraform Plan" "Analyzing deployment plan" "info"

    # Use refactored terraform operations for plan analysis
    if ! analyze_terraform_plan "$terraform_dir" "plan.out"; then
        log_warn "Plan analysis detected potential issues, proceeding with caution"
    fi

    local plan_result
    if terraform -chdir="$terraform_dir" plan -detailed-exitcode -input=false $allParameters | tee plan_output.log; then
        plan_result=${PIPESTATUS[0]}
    else
        plan_result=${PIPESTATUS[0]}
    fi

    log_info "Terraform plan return code: $plan_result"

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
                cat plan_output.log
                rm plan_output.log
            fi
            return $TERRAFORM_ERROR
            ;;
    esac

    # Clean up plan output
    [[ -f "plan_output.log" ]] && rm plan_output.log

    # Execute Terraform apply with enhanced error recovery
    execute_terraform_apply "$terraform_dir" "$allParameters" "$allImportParameters"
}

function execute_terraform_apply() {
    local terraform_dir="$1"
    local allParameters="$2"
    local allImportParameters="$3"

    display_banner "Terraform Apply" "Deploying infrastructure changes" "info"

    # Configure parallelism
    local parallelism="${TF_PARALLELLISM:-$DEFAULT_PARALLELISM}"
    log_info "Using Terraform parallelism: $parallelism"

    # Clean up any existing apply output
    [[ -f "apply_output.json" ]] && rm apply_output.json

    local apply_result
    if [[ -n "$approve" ]]; then
        # Auto-approve mode with JSON output for error processing
        if terraform -chdir="$terraform_dir" apply -parallelism="$parallelism" \
            $allParameters -no-color -compact-warnings -json -input=false --auto-approve | tee apply_output.json; then
            apply_result=${PIPESTATUS[0]}
        else
            apply_result=${PIPESTATUS[0]}
        fi

        # Use refactored error handling instead of multiple ImportAndReRunApply calls
        if [[ $apply_result -ne $SUCCESS ]] && [[ -f "apply_output.json" ]]; then
            display_banner "Error Recovery" "Attempting automatic error recovery" "warning"

            # Use the new terraform_apply_with_recovery function
            if terraform_apply_with_recovery "$terraform_dir" "$allParameters" "$allImportParameters" 5 "true"; then
                display_success "Error Recovery" "Automatic recovery successful"
                apply_result=$SUCCESS
            else
                display_error "Error Recovery" "Automatic recovery failed" "$TERRAFORM_ERROR"
                apply_result=$TERRAFORM_ERROR
            fi
        fi
    else
        # Interactive mode
        if terraform -chdir="$terraform_dir" apply -parallelism="$parallelism" $allParameters; then
            apply_result=${PIPESTATUS[0]}
        else
            apply_result=${PIPESTATUS[0]}
        fi
    fi

    # Report apply results
    case $apply_result in
        0)
            display_success "Terraform Apply" "Infrastructure deployment completed successfully"
            ;;
        *)
            display_error "Terraform Apply" "Infrastructure deployment failed" "$apply_result"
            return $apply_result
            ;;
    esac

    return $apply_result
}

#########################################################################################
# POST-DEPLOYMENT CONFIGURATION                                                        #
#########################################################################################

function configure_deployment_outputs() {
    local terraform_dir="$1"
    local deployer_config_info="$2"

    display_banner "Post-Deployment" "Configuring deployment outputs" "info"

    # Extract and save Key Vault information
    local keyvault
    if keyvault=$(terraform -chdir="$terraform_dir" output deployer_kv_user_name 2>/dev/null | tr -d \"); then
        display_success "Key Vault Configuration" "Key Vault for SPN details: $keyvault"

        save_config_var "keyvault" "$deployer_config_info"

        # Set Key Vault ARM ID for future operations
        local TF_VAR_deployer_kv_user_arm_id
        TF_VAR_deployer_kv_user_arm_id=$(az resource list --name "$keyvault" --subscription "$ARM_SUBSCRIPTION_ID" --resource-type Microsoft.KeyVault/vaults --query "[].id | [0]" -o tsv)
        export TF_VAR_deployer_kv_user_arm_id

        log_info "Key Vault ARM ID: $TF_VAR_deployer_kv_user_arm_id"
    else
        display_error "Key Vault Configuration" "Failed to retrieve Key Vault information" "$TERRAFORM_ERROR"
        return $TERRAFORM_ERROR
    fi

    # Extract and save SSH secret information
    local sshsecret
    sshsecret=$(terraform -chdir="$terraform_dir" output -no-color -raw deployer_sshkey_secret_name 2>/dev/null | tr -d \" || true)
    if [[ -n "$sshsecret" ]]; then
        save_config_var "sshsecret" "$deployer_config_info"
        log_info "SSH secret name: $sshsecret"
    fi

    # Extract and save public IP address
    local deployer_public_ip_address
    deployer_public_ip_address=$(terraform -chdir="$terraform_dir" output -no-color -raw deployer_public_ip_address 2>/dev/null | tr -d \" || true)
    if [[ -n "$deployer_public_ip_address" ]]; then
        save_config_var "deployer_public_ip_address" "$deployer_config_info"
        log_info "Deployer public IP: $deployer_public_ip_address"
    fi

    # Extract and save random ID for consistency
    local deployer_random_id
    deployer_random_id=$(terraform -chdir="$terraform_dir" output -no-color -raw random_id 2>/dev/null | tr -d \" || true)
    if [[ -n "$deployer_random_id" ]]; then
        save_config_var "deployer_random_id" "$deployer_config_info"

        # Update parameter file with custom random ID
        local custom_random_id="${deployer_random_id:0:3}"
        sed -i -e /"custom_random_id"/d "$var_file"
        printf "# The parameter 'custom_random_id' can be used to control the random 3 digits at the end of the storage accounts and key vaults\ncustom_random_id=\"%s\"\n" "$custom_random_id" >> "$var_file"

        log_info "Custom random ID: $custom_random_id"
    fi

    return $SUCCESS
}

#########################################################################################
# MAIN EXECUTION FLOW                                                                  #
#########################################################################################

function main() {
    local terraform_module_directory param_dirname var_file
    local automation_config_directory deployer_config_information

    # Enable debug mode if requested
    if [[ "$DEBUG" == "True" ]]; then
        set -x
        set -o errexit
        log_info "Debug mode enabled"
    fi

    # Process command line arguments
    process_command_line_arguments "$@"

    # Validate parameter file and setup environment
    if ! validate_parameter_file_access "$parameterfile"; then
        exit $?
    fi

    if ! setup_deployment_environment "$parameterfile"; then
        exit $?
    fi

    # Setup paths and directories
    terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}/deploy/terraform/bootstrap/${DEPLOYMENT_SYSTEM}/"
    param_dirname=$(pwd)
    var_file="${param_dirname}/${parameterfile}"
    automation_config_directory="$CONFIG_REPO_PATH/.sap_deployment_automation/"
    deployer_config_information="${automation_config_directory}${environment}${region_code}"

    # Initialize Terraform backend
    if ! initialize_terraform_backend "$terraform_module_directory" "$param_dirname" "$var_file"; then
        display_error "Terraform Initialization" "Backend initialization failed" "$TERRAFORM_ERROR"
        exit $TERRAFORM_ERROR
    fi

    # Execute deployment
    if ! execute_terraform_deployment "$terraform_module_directory" "$var_file"; then
        display_error "Deployment Failed" "Infrastructure deployment encountered errors" "$TERRAFORM_ERROR"
        exit $TERRAFORM_ERROR
    fi

    # Configure post-deployment settings
    if ! configure_deployment_outputs "$terraform_module_directory" "$deployer_config_information"; then
        display_error "Post-Deployment Configuration" "Failed to configure deployment outputs" "$TERRAFORM_ERROR"
        exit $TERRAFORM_ERROR
    fi

    # Clean up and exit
    unset TF_DATA_DIR
    display_success "Deployment Complete" "SAP Deployer has been successfully deployed"
    log_info "Exiting script: $SCRIPT_NAME"

    return $SUCCESS
}

#########################################################################################
# SCRIPT EXECUTION                                                                     #
#########################################################################################

# Execute main function with all arguments
main "$@"
exit $?
