#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# shellcheck disable=SC1090,SC1091,SC2034,SC2154

# Pipeline Standards Module - Centralized Constants, Utilities, and Azure DevOps Integration

#==============================================================================
# Pipeline Error Codes and Constants
#==============================================================================

# Pipeline-specific error codes
declare -gr PIPELINE_ERROR=100
declare -gr DEVOPS_ERROR=101
declare -gr GIT_ERROR=102
declare -gr DEPLOYMENT_ERROR=103
declare -gr SKIP_DEPLOYMENT=200

# Pipeline step constants
declare -gr PIPELINE_STEP_PREPARE=0
declare -gr PIPELINE_STEP_DEPLOY=1
declare -gr PIPELINE_STEP_COMPLETE=2

# Pipeline timeout and retry constants
declare -gr PIPELINE_TIMEOUT=7200        # 2 hours
declare -gr MAX_PIPELINE_RETRIES=3
declare -gr PIPELINE_RETRY_DELAY=30

# Azure DevOps logging constants
declare -gr ADO_SECTION="##[section]"
declare -gr ADO_WARNING="##vso[task.logissue type=warning]"
declare -gr ADO_ERROR="##vso[task.logissue type=error]"
declare -gr ADO_PROGRESS="##vso[task.setprogress value="
declare -gr ADO_SUMMARY="##vso[task.uploadsummary]"

#==============================================================================
# Pipeline Detection and Context Functions
#==============================================================================

function is_pipeline_environment() {
    # Detect if running in Azure DevOps pipeline
    [[ -n "${SYSTEM_COLLECTIONURI:-}" ]] && [[ -n "${SYSTEM_TEAMPROJECT:-}" ]]
}

function is_deployer_environment() {
    # Detect if running on a deployer VM
    [[ -f /etc/profile.d/deploy_server.sh ]]
}

function get_pipeline_agent_info() {
    if is_pipeline_environment; then
        echo "Azure DevOps Agent: ${AGENT_NAME:-unknown}"
        echo "Build ID: ${BUILD_BUILDID:-unknown}"
        echo "Build Number: ${BUILD_BUILDNUMBER:-unknown}"
    else
        echo "Local Environment: $(hostname)"
    fi
}

#==============================================================================
# Pipeline Environment Setup and Validation
#==============================================================================

function setup_pipeline_environment() {
    local deployer_folder="$1"
    local library_folder="$2"

    display_banner "Pipeline Configuration" "Setting up Azure DevOps build environment" "info"
    send_pipeline_event "progress" "Setting up pipeline environment" "10"

    # Extract and validate deployment context
    if ! extract_deployment_context "$deployer_folder" "$library_folder"; then
        send_pipeline_event "error" "Failed to extract deployment context"
        return $PIPELINE_ERROR
    fi

    # Validate build environment
    if ! validate_pipeline_prerequisites; then
        send_pipeline_event "error" "Pipeline environment validation failed"
        return $ENV_ERROR
    fi

    # Create automation directory if needed
    mkdir -p "$CONFIG_REPO_PATH/.sap_deployment_automation"

    log_info "Pipeline environment configured successfully"
    send_pipeline_event "progress" "Pipeline environment configured" "20"
    return $SUCCESS
}

function extract_deployment_context() {
    local deployer_folder="$1"
    local library_folder="$2"

    log_info "Extracting deployment context from folder names"

    # Extract environment and location from deployer folder name
    export ENVIRONMENT=$(echo "$deployer_folder" | awk -F'-' '{print $1}' | xargs)
    export LOCATION=$(echo "$deployer_folder" | awk -F'-' '{print $2}' | xargs)

    # Validate extracted values
    if [[ -z "$ENVIRONMENT" ]] || [[ -z "$LOCATION" ]]; then
        display_error "Deployment Context" "Failed to extract environment and location from: $deployer_folder" "$PIPELINE_ERROR"
        return $PIPELINE_ERROR
    fi

    echo "Configuration file:                  $CONFIG_REPO_PATH/.sap_deployment_automation/${ENVIRONMENT}${LOCATION}"
    echo "Environment:                         $ENVIRONMENT"
    echo "Location:                            $LOCATION"

    log_info "Deployment context - Environment: $ENVIRONMENT, Location: $LOCATION"
    return $SUCCESS
}

function validate_pipeline_prerequisites() {
    local validation_errors=0

    log_info "Validating pipeline environment variables"

    # Required environment variables
    local required_vars=(
        "BUILD_SOURCEBRANCHNAME"
        "SYSTEM_COLLECTIONURI"
        "SYSTEM_TEAMPROJECT"
        "VARIABLE_GROUP"
        "ARM_SUBSCRIPTION_ID"
        "DEPLOYER_FOLDERNAME"
        "LIBRARY_FOLDERNAME"
        "DEPLOYER_TFVARS_FILENAME"
        "LIBRARY_TFVARS_FILENAME"
        "CONFIG_REPO_PATH"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            display_error "Environment Variable" "Required variable not set: $var" "$ENV_ERROR"
            ((validation_errors++))
        fi
    done

    if [[ $validation_errors -gt 0 ]]; then
        display_error "Environment Validation" "Pipeline environment validation failed" "$ENV_ERROR"
        return $ENV_ERROR
    fi

    log_info "Pipeline environment validation successful"
    return $SUCCESS
}

#==============================================================================
# Azure DevOps Integration Functions
#==============================================================================

function configure_azure_devops_pipeline() {
    local variable_group="$1"

    display_banner "Azure DevOps Integration" "Configuring DevOps CLI and variable groups" "info"
    send_pipeline_event "progress" "Configuring Azure DevOps integration" "50"

    # Configure Azure DevOps CLI with error recovery
    if ! setup_azure_devops_cli; then
        send_pipeline_event "error" "Azure DevOps CLI configuration failed"
        return $DEVOPS_ERROR
    fi

    # Validate and manage variable groups
    if ! manage_variable_groups "$variable_group"; then
        send_pipeline_event "error" "Variable group management failed"
        return $DEVOPS_ERROR
    fi

    # Setup pipeline-specific configuration
    if ! configure_pipeline_parameters; then
        send_pipeline_event "error" "Pipeline parameter configuration failed"
        return $CONFIG_ERROR
    fi

    display_success "Azure DevOps Integration" "DevOps environment configured successfully"
    send_pipeline_event "progress" "Azure DevOps integration configured" "60"
    return $SUCCESS
}

function setup_azure_devops_cli() {
    log_info "Configuring Azure DevOps CLI extensions"

    # Configure Azure CLI with dynamic extension installation
    if ! az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors; then
        display_error "Azure CLI Config" "Failed to configure Azure CLI extensions" "$DEVOPS_ERROR"
        return $DEVOPS_ERROR
    fi

    # Add Azure DevOps extension with retry logic
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if az extension add --name azure-devops --output none --only-show-errors; then
            break
        fi

        log_warn "Azure DevOps extension installation failed, attempt $attempt/$max_attempts"
        ((attempt++))

        if [[ $attempt -le $max_attempts ]]; then
            sleep 5
        fi
    done

    if [[ $attempt -gt $max_attempts ]]; then
        display_error "DevOps Extension" "Failed to install Azure DevOps extension after $max_attempts attempts" "$DEVOPS_ERROR"
        return $DEVOPS_ERROR
    fi

    # Configure DevOps defaults
    if ! az devops configure --defaults organization="$SYSTEM_COLLECTIONURI" project="$SYSTEM_TEAMPROJECT" --output none --only-show-errors; then
        display_error "DevOps Configuration" "Failed to configure Azure DevOps defaults" "$DEVOPS_ERROR"
        return $DEVOPS_ERROR
    fi

    log_info "Azure DevOps CLI configuration completed successfully"
    return $SUCCESS
}

function manage_variable_groups() {
    local variable_group="$1"

    log_info "Managing Azure DevOps variable group: $variable_group"

    # Get variable group ID
    local variable_group_id
    variable_group_id=$(az pipelines variable-group list --query "[?name=='$variable_group'].id | [0]" 2>/dev/null)

    if [[ -z "$variable_group_id" ]] || [[ "$variable_group_id" == "null" ]]; then
        display_error "Variable Group" "Variable group '$variable_group' could not be found" "$DEVOPS_ERROR"
        echo "##vso[task.logissue type=error]Variable group $variable_group could not be found."
        return $DEVOPS_ERROR
    fi

    export VARIABLE_GROUP_ID="$variable_group_id"

    # Display variable group information
    printf -v tempval '%s id:' "$variable_group"
    printf -v val '%-20s' "${tempval}"
    echo "$val                 $VARIABLE_GROUP_ID"

    log_info "Variable group management completed successfully"
    return $SUCCESS
}

function configure_pipeline_parameters() {
    log_info "Configuring pipeline-specific parameters"

    # Setup agent information
    echo ""
    echo "Agent:                               ${THIS_AGENT:-$(hostname)}"
    echo "Organization:                        $SYSTEM_COLLECTIONURI"
    echo "Project:                             $SYSTEM_TEAMPROJECT"

    # Configure PAT token if available
    if [[ -n "${TF_VAR_agent_pat:-}" ]]; then
        echo "Deployer Agent PAT:                  IsDefined"
    fi

    # Configure agent pool if specified
    if [[ -n "${POOL:-}" ]]; then
        echo "Deployer Agent Pool:                 $POOL"
    fi

    log_info "Pipeline parameters configured successfully"
    return $SUCCESS
}

#==============================================================================
# Deployment Parameters and Execution
#==============================================================================

function build_deployment_parameters() {
    local deployer_file="$1"
    local library_file="$2"
    local subscription="$3"
    local -n params_ref="$4"

    log_info "Building deployment parameters"

    # Base parameters
    local base_params=(
        "--deployer_parameter_file" "$deployer_file"
        "--library_parameter_file" "$library_file"
        "--subscription" "$subscription"
        "--auto-approve"
        "--ado"
        "--only_deployer"
    )

    # Add authentication parameters based on mode
    if [[ "${USE_MSI:-false}" == "true" ]]; then
        base_params+=("--msi")
        log_info "Using MSI authentication for deployment"
    else
        base_params+=(
            "--spn_id" "$ARM_CLIENT_ID"
            "--spn_secret" "$ARM_CLIENT_SECRET"
            "--tenant_id" "$ARM_TENANT_ID"
        )
        log_info "Using Service Principal authentication for deployment"
    fi

    params_ref=("${base_params[@]}")
    log_info "Deployment parameters built successfully"
    return $SUCCESS
}

function execute_control_plane_deployment_with_monitoring() {
    local -a params=("$@")

    log_info "Executing control plane deployment with monitoring"

    # Setup deployment monitoring
    local deployment_start_time
    deployment_start_time=$(date +%s)

    # Execute deployment script with proper error handling
    local deployment_script="$SAP_AUTOMATION_REPO_PATH/deploy/scripts/deploy_controlplane.sh"

    if [[ ! -f "$deployment_script" ]]; then
        display_error "Deployment Script" "Deployment script not found: $deployment_script" "$FILE_ERROR"
        return $FILE_ERROR
    fi

    log_info "Executing: $deployment_script ${params[*]}"

    # Disable strict error handling for deployment script execution
    set +eu

    # Execute with timeout and capture return code
    local return_code=0
    if timeout "$PIPELINE_TIMEOUT" "$deployment_script" "${params[@]}"; then
        return_code=$?
    else
        return_code=$?
    fi

    # Re-enable strict error handling
    set -eu

    # Calculate deployment duration
    local deployment_end_time
    deployment_end_time=$(date +%s)
    local deployment_duration=$((deployment_end_time - deployment_start_time))

    echo ""
    echo "Deploy_controlplane returned:        $return_code"
    echo ""

    # Process deployment result
    if [[ $return_code -eq 0 ]]; then
        log_info "Deployment completed successfully in ${deployment_duration}s"
        send_metric "pipeline.control_plane_deployment_duration" "$deployment_duration" "histogram"
    else
        display_error "Deployment Execution" "Control plane deployment failed with code: $return_code" "$DEPLOYMENT_ERROR"
        send_metric "pipeline.control_plane_deployment_failures" "1" "counter"
    fi

    # Store return code for further processing
    export DEPLOYMENT_RETURN_CODE="$return_code"

    return $return_code
}

#==============================================================================
# Pipeline Event Management and Monitoring
#==============================================================================

function send_pipeline_event() {
    local event_type="$1"
    local event_message="$2"
    local event_data="$3"

    # Azure DevOps logging
    case "$event_type" in
        "start")
            echo "##[section]🚀 $event_message"
            ;;
        "success")
            echo "##[section]✅ $event_message"
            ;;
        "warning")
            echo "##vso[task.logissue type=warning]⚠️ $event_message"
            ;;
        "error")
            echo "##vso[task.logissue type=error]❌ $event_message"
            ;;
        "progress")
            if [[ -n "$event_data" ]]; then
                echo "##vso[task.setprogress value=$event_data]$event_message"
            fi
            ;;
    esac

    # Structured logging for monitoring
    log_structured_event "$event_type" "$event_message" "$event_data"

    # Send to monitoring system if enabled
    if [[ "${PIPELINE_MONITORING_ENABLED:-false}" == "true" ]]; then
        send_monitoring_event "pipeline.$event_type" "$event_message" "$event_data"
    fi
}

function log_structured_event() {
    local event_type="$1"
    local event_message="$2"
    local event_data="$3"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    case "$event_type" in
        "start"|"success")
            log_info "[$timestamp] Pipeline Event: $event_type - $event_message"
            ;;
        "warning")
            log_warn "[$timestamp] Pipeline Event: $event_type - $event_message"
            ;;
        "error")
            log_error "[$timestamp] Pipeline Event: $event_type - $event_message"
            ;;
        "progress")
            log_debug "[$timestamp] Pipeline Event: $event_type - $event_message ($event_data%)"
            ;;
    esac
}

function send_monitoring_event() {
    local event_type="$1"
    local event_message="$2"
    local event_data="$3"

    # Only send if monitoring is enabled
    if [[ "${PIPELINE_MONITORING_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    # Send to monitoring system (placeholder for integration)
    log_debug "Monitoring Event: $event_type - $event_message ($event_data)"

    # Future: Integration with monitoring systems like Application Insights, etc.
}

function send_metric() {
    local metric_name="$1"
    local metric_value="$2"
    local metric_type="$3"
    local metric_tags="$4"

    # Only send if monitoring is enabled
    if [[ "${PIPELINE_MONITORING_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    log_debug "Metric: $metric_name=$metric_value ($metric_type) [$metric_tags]"

    # Future: Integration with metrics systems
}
