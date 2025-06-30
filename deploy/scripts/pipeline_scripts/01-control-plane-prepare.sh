#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#==============================================================================
# SAP Control Plane Prepare Script - Refactored Version (Lean Orchestrator)
#
# This script orchestrates SAP control plane deployment preparation within
# Azure DevOps pipelines using modular framework components.
#
# File Path: deploy/scripts/pipeline_scripts/01-control-plane-prepare.sh
# Version: 2.0 (Refactored - Lean Orchestrator)
# Backward Compatibility: 100% maintained
#==============================================================================

# Pipeline build number update for Azure DevOps
echo "##vso[build.updatebuildnumber]Deploying the control plane defined in $DEPLOYER_FOLDERNAME $LIBRARY_FOLDERNAME"

# Script initialization and framework loading
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
SCRIPT_NAME="$(basename "$0")"

# Load enhanced framework (replaces legacy helper.sh)
source "${script_directory}/helper.sh"
source "${script_directory}/../helpers/script_helpers_v2.sh"

# Script constants
declare -gr SCRIPT_VERSION="2.0"
declare -gr DEPLOYMENT_TYPE="control_plane"

# Initialize logging and display
log_info "Starting pipeline script: $SCRIPT_NAME v$SCRIPT_VERSION (Lean Orchestrator)"
send_pipeline_event "start" "Control Plane Preparation Started" ""

#==============================================================================
# Script-Specific Configuration
#==============================================================================

function initialize_script_environment() {
    log_info "Initializing script-specific environment"

    # Setup debug mode based on environment
    export DEBUG=false
    if [[ "${SYSTEM_DEBUG:-false}" == "True" ]]; then
        set -x
        export DEBUG=true
        log_info "Debug mode enabled"
        echo "##[section]Environment variables:"
        printenv | sort
    fi

    # Set error handling for main script
    set -eu

    # Validate essential pipeline prerequisites
    if ! validate_pipeline_prerequisites; then
        send_pipeline_event "error" "Pipeline prerequisites validation failed"
        return $PIPELINE_ERROR
    fi

    log_info "Script environment initialized successfully"
    return $SUCCESS
}

function setup_script_configuration_paths() {
    log_info "Setting up script-specific configuration paths"

    # Validate CONFIG_REPO_PATH is set
    if [[ -z "${CONFIG_REPO_PATH:-}" ]]; then
        display_error "Configuration Path" "CONFIG_REPO_PATH environment variable not set" "$ENV_ERROR"
        return $ENV_ERROR
    fi

    # Change to configuration repository directory
    if ! cd "$CONFIG_REPO_PATH"; then
        display_error "Configuration Path" "Failed to change to CONFIG_REPO_PATH: $CONFIG_REPO_PATH" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    # Setup script-specific paths
    export deployer_environment_file_name="$CONFIG_REPO_PATH/.sap_deployment_automation/${ENVIRONMENT}${LOCATION}"
    export deployer_tfvars_file_name="${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME"
    export library_tfvars_file_name="${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME"

    # Setup state file keys
    export file_deployer_tfstate_key="$DEPLOYER_FOLDERNAME.tfstate"
    export deployer_tfstate_key="$DEPLOYER_FOLDERNAME.terraform.tfstate"

    log_info "Script configuration paths setup completed"
    return $SUCCESS
}

function check_deployment_readiness() {
    log_info "Checking if deployment should proceed"

    # Check current step from environment file
    local current_step=0

    if [[ -f "$deployer_environment_file_name" ]]; then
        current_step=$(extract_deployment_info_from_file "$deployer_environment_file_name" "step" "0")
    fi

    echo "Step:                                $current_step"

    # If step is not 0, deployment has already been prepared
    if [[ $current_step -ne $PIPELINE_STEP_PREPARE ]]; then
        echo "##vso[task.logissue type=warning]Already prepared"
        send_pipeline_event "warning" "Deployment already prepared, skipping"
        return $SKIP_DEPLOYMENT
    fi

    return $SUCCESS
}

function configure_deployment_environment() {
    log_info "Configuring deployment-specific environment"

    # Setup Terraform logging
    export TF_LOG_PATH="$CONFIG_REPO_PATH/.sap_deployment_automation/terraform.log"

    # Configure Ansible version if not set
    if [[ -z "${TF_VAR_ansible_core_version:-}" ]]; then
        export TF_VAR_ansible_core_version=2.16
    fi

    # Setup PAT token for Terraform if available
    if [[ -n "${SYSTEM_ACCESSTOKEN:-}" ]]; then
        export TF_VAR_PAT="$SYSTEM_ACCESSTOKEN"
    fi

    # Configure web app deployment setting
    if [[ "${USE_WEBAPP:-false}" == "true" ]]; then
        export TF_VAR_use_webapp=true
        echo "Deploy Web App:                      true"
    else
        export TF_VAR_use_webapp=false
        echo "Deploy Web App:                      false"
    fi

    log_info "Deployment environment configured successfully"
    return $SUCCESS
}

function execute_deployment_orchestration() {
    local deployer_file="$1"
    local library_file="$2"
    local subscription="$3"

    display_banner "Deployment Orchestration" "Executing control plane deployment" "info"
    send_pipeline_event "progress" "Starting control plane deployment" "90"

    # Handle state file decompression if needed
    if ! handle_encrypted_state_files; then
        send_pipeline_event "error" "State file handling failed"
        return $DEPLOYMENT_ERROR
    fi

    # Build and execute deployment
    local deployment_params
    if ! build_deployment_parameters "$deployer_file" "$library_file" "$subscription" "deployment_params"; then
        send_pipeline_event "error" "Deployment parameter setup failed"
        return $DEPLOYMENT_ERROR
    fi

    # Execute deployment with monitoring and timeout
    if ! execute_control_plane_deployment_with_monitoring "${deployment_params[@]}"; then
        send_pipeline_event "error" "Control plane deployment failed"
        return $DEPLOYMENT_ERROR
    fi

    # Process results and update variable groups
    if ! process_deployment_results_and_variables; then
        send_pipeline_event "error" "Deployment result processing failed"
        return $DEPLOYMENT_ERROR
    fi

    display_success "Deployment Orchestration" "Control plane deployment completed successfully"
    send_pipeline_event "success" "Control plane deployment completed successfully" ""
    return $SUCCESS
}

function handle_encrypted_state_files() {
    log_info "Handling encrypted state file decompression if needed"

    local state_zip_file="${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip"

    if [[ -f "$state_zip_file" ]]; then
        log_info "State zip file found, decompressing"

        # Extract using collection ID as password
        local password="${SYSTEM_COLLECTIONID//-/}"

        if unzip -qq -o -P "$password" "$state_zip_file" -d "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME"; then
            log_info "State zip file decompressed successfully"
        else
            log_warn "Failed to decompress state zip file"
            return $TOOL_ERROR
        fi
    else
        log_info "No encrypted state file found, proceeding with fresh deployment"
    fi

    return $SUCCESS
}

function process_deployment_results_and_variables() {
    log_info "Processing deployment results and updating variables"

    # Re-enable strict error handling
    set -eu

    # Extract deployment information from environment file
    if [[ -f "$deployer_environment_file_name" ]]; then
        extract_and_display_deployment_info
    fi

    # Update variable groups with deployment information
    if [[ "${DEPLOYMENT_RETURN_CODE:-1}" -eq 0 ]]; then
        if ! update_pipeline_variable_groups; then
            return $DEVOPS_ERROR
        fi
    fi

    # Persist deployment state to repository
    if ! execute_git_state_persistence_with_retry; then
        return $GIT_ERROR
    fi

    # Upload deployment summary if available
    if [[ -f "$CONFIG_REPO_PATH/.sap_deployment_automation/${ENVIRONMENT}${LOCATION}.md" ]]; then
        echo "##vso[task.uploadsummary]$CONFIG_REPO_PATH/.sap_deployment_automation/${ENVIRONMENT}${LOCATION}.md"
    fi

    log_info "Deployment results processed successfully"
    return $SUCCESS
}

function extract_and_display_deployment_info() {
    log_info "Extracting and displaying deployment information"

    # Extract key deployment information
    local file_key_vault
    local file_remote_state_sa
    local file_remote_state_rg

    file_key_vault=$(extract_deployment_info_from_file "$deployer_environment_file_name" "keyvault" "")
    file_remote_state_sa=$(extract_deployment_info_from_file "$deployer_environment_file_name" "REMOTE_STATE_SA" "")
    file_remote_state_rg=$(extract_deployment_info_from_file "$deployer_environment_file_name" "REMOTE_STATE_RG" "")

    # Display extracted information
    echo "Deployer Key Vault:                  $file_key_vault"
    echo "Deployer State File:                 $deployer_tfstate_key"

    if [[ -n "$file_remote_state_sa" ]]; then
        echo "Terraform Remote State Account:       $file_remote_state_sa"
    fi

    if [[ -n "$file_remote_state_rg" ]]; then
        echo "Terraform Remote State RG Name:       $file_remote_state_rg"
    fi

    # Export for variable group updates
    export file_key_vault file_remote_state_sa file_remote_state_rg
}

function update_pipeline_variable_groups() {
    log_info "Updating Azure DevOps variable groups with deployment results"

    # Update Key Vault variable
    if [[ -n "${file_key_vault:-}" ]]; then
        if saveVariableInVariableGroup "$VARIABLE_GROUP_ID" "DEPLOYER_KEYVAULT" "$file_key_vault"; then
            echo "Variable DEPLOYER_KEYVAULT updated successfully"
        else
            echo "##vso[task.logissue type=error]Failed to update DEPLOYER_KEYVAULT variable"
            return $DEVOPS_ERROR
        fi
    fi

    # Update environment and location variables
    if ! saveVariableInVariableGroup "$VARIABLE_GROUP_ID" "ControlPlaneEnvironment" "$ENVIRONMENT"; then
        echo "##vso[task.logissue type=error]Failed to update ControlPlaneEnvironment variable"
        return $DEVOPS_ERROR
    fi

    if ! saveVariableInVariableGroup "$VARIABLE_GROUP_ID" "ControlPlaneLocation" "$LOCATION"; then
        echo "##vso[task.logissue type=error]Failed to update ControlPlaneLocation variable"
        return $DEVOPS_ERROR
    fi

    log_info "Variable groups updated successfully"
    return $SUCCESS
}

#==============================================================================
# Main Execution Function (Lean Orchestrator)
#==============================================================================

function main() {
    local return_code=0

    # Initialize script environment
    if ! initialize_script_environment; then
        exit $PIPELINE_ERROR
    fi

    # Setup pipeline environment using framework functions
    if ! setup_pipeline_environment "$DEPLOYER_FOLDERNAME" "$LIBRARY_FOLDERNAME"; then
        send_pipeline_event "error" "Pipeline environment setup failed"
        exit $PIPELINE_ERROR
    fi

    # Setup script-specific configuration paths
    if ! setup_script_configuration_paths; then
        send_pipeline_event "error" "Configuration paths setup failed"
        exit $CONFIG_ERROR
    fi

    # Check if deployment should proceed
    local readiness_result
    check_deployment_readiness
    readiness_result=$?

    if [[ $readiness_result -eq $SKIP_DEPLOYMENT ]]; then
        log_info "Deployment already prepared, exiting successfully"
        return $SUCCESS
    elif [[ $readiness_result -ne $SUCCESS ]]; then
        send_pipeline_event "error" "Deployment readiness check failed"
        exit $PIPELINE_ERROR
    fi

    # Validate configuration files using framework
    if ! validate_pipeline_configuration_files "$deployer_tfvars_file_name" "$library_tfvars_file_name"; then
        send_pipeline_event "error" "Configuration file validation failed"
        exit $FILE_ERROR
    fi

    # Configure Azure DevOps integration using framework
    if ! configure_azure_devops_pipeline "$VARIABLE_GROUP"; then
        send_pipeline_event "error" "Azure DevOps integration failed"
        exit $DEVOPS_ERROR
    fi

    # Setup Azure integration using framework
    if ! setup_azure_pipeline_integration "$ARM_SUBSCRIPTION_ID" "${USE_MSI:-false}"; then
        send_pipeline_event "error" "Azure integration failed"
        exit $AZURE_ERROR
    fi

    # Execute git operations using framework
    if ! execute_pipeline_git_operations "$BUILD_SOURCEBRANCHNAME" "$BUILD_REQUESTEDFOR" "$BUILD_REQUESTEDFOREMAIL"; then
        send_pipeline_event "error" "Git operations failed"
        exit $GIT_ERROR
    fi

    # Configure deployment environment
    if ! configure_deployment_environment; then
        send_pipeline_event "error" "Deployment environment configuration failed"
        exit $CONFIG_ERROR
    fi

    # Execute deployment orchestration
    if ! execute_deployment_orchestration "$deployer_tfvars_file_name" "$library_tfvars_file_name" "$ARM_SUBSCRIPTION_ID"; then
        return_code="${DEPLOYMENT_RETURN_CODE:-$DEPLOYMENT_ERROR}"
    fi

    # Final success display
    if [[ $return_code -eq 0 ]]; then
        display_banner "Pipeline Complete" "Control plane preparation completed successfully" "success"
        send_pipeline_event "success" "Pipeline execution completed successfully" ""
    fi

    log_info "Script completed with return code: $return_code"
    return $return_code
}

#==============================================================================
# Script Entry Point
#==============================================================================

# Trap cleanup for graceful exit
trap 'cleanup_on_exit' EXIT

# shellcheck disable=SC2317
function cleanup_on_exit() {
    local exit_code=$?

    # Clean up temporary files
    [[ -f "terraform.log" ]] && rm -f terraform.log

    # Cleanup git credentials
    cleanup_git_credentials

    log_info "Cleanup completed"

    if [[ $exit_code -eq 0 ]]; then
        echo "Exiting: ${SCRIPT_NAME} - Success"
    else
        echo "Exiting: ${SCRIPT_NAME} - Error (Code: $exit_code)"
    fi
}

# Execute main function
main
exit_code=$?

# Exit with the deployment return code
exit $exit_code
