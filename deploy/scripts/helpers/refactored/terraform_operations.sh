#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Terraform Operations Module - Complex State Management and Error Recovery
# This module breaks down the monolithic ImportAndReRunApply function and other
# complex Terraform operations into smaller, testable, and maintainable functions

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
# TERRAFORM CONFIGURATION
# =============================================================================

# Terraform operation timeouts and retries
declare -gr TF_PLAN_TIMEOUT="${TF_PLAN_TIMEOUT:-300}"
declare -gr TF_APPLY_TIMEOUT="${TF_APPLY_TIMEOUT:-1800}"
declare -gr TF_IMPORT_TIMEOUT="${TF_IMPORT_TIMEOUT:-180}"
declare -gr TF_MAX_RETRIES="${TF_MAX_RETRIES:-3}"
declare -gr TF_DEFAULT_PARALLELISM="${TF_DEFAULT_PARALLELISM:-10}"

# Terraform error patterns for classification
declare -ga TF_IMPORT_ERROR_PATTERNS=(
    "A resource with the ID"
    "already exists"
    "already assigned"
)

declare -ga TF_PERMISSION_ERROR_PATTERNS=(
    "The role assignment already exists"
    "does not have authorization"
    "insufficient privileges"
)

declare -ga TF_TRANSIENT_ERROR_PATTERNS=(
    "timeout"
    "network error"
    "connection reset"
    "throttled"
)

# =============================================================================
# TERRAFORM PLAN ANALYSIS FUNCTIONS
# =============================================================================

####################################################################################
# Enhanced Terraform plan analysis with detailed resource impact assessment        #
# This replaces testIfResourceWouldBeRecreated with improved functionality         #
# Arguments:                                                                       #
#   $1 - Terraform module directory                                                #
#   $2 - Plan output file path                                                     #
#   $3 - Resource patterns to check (space-separated)                              #
# Returns:                                                                         #
#   SUCCESS if no destructive changes &, TERRAFORM_ERROR for destructive changes   #
# Usage:                                                                           #
#   analyze_terraform_plan "/path/to/module" "plan.out" "azurerm_virtual_machine.*"#
####################################################################################
function analyze_terraform_plan() {
    if ! validate_function_params "analyze_terraform_plan" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local terraform_dir="${1:-}"
    local plan_file="${2:-}"
    local resource_patterns="${3:-}"

    log_info "Analyzing Terraform plan for destructive changes"
    log_debug "Plan file: $plan_file, Patterns: $resource_patterns"

    # Validate inputs
    if [[ ! -d "$terraform_dir" ]]; then
        log_error "Terraform directory does not exist: $terraform_dir"
        return $PARAM_ERROR
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file does not exist: $plan_file"
        return $FILE_ERROR
    fi

    # Analyze plan for destructive changes
    local analysis_result
    analysis_result=$(_parse_plan_for_changes "$terraform_dir" "$plan_file" "$resource_patterns")
    local parse_result=$?

    if [[ $parse_result -ne $SUCCESS ]]; then
        log_error "Failed to parse Terraform plan"
        return $TERRAFORM_ERROR
    fi

    # Evaluate analysis results
    local destructive_changes
    destructive_changes=$(echo "$analysis_result" | jq -r '.destructive_changes // 0' 2>/dev/null)

    if [[ "$destructive_changes" -gt 0 ]]; then
        log_error "Destructive changes detected in Terraform plan"
        _display_destructive_changes "$analysis_result"
        return $TERRAFORM_ERROR
    else
        log_info "No destructive changes detected in Terraform plan"
        return $SUCCESS
    fi
}

################################################################################
# Internal plan parsing function                                               #
# Arguments:                                                                   #
#   $1 - Terraform directory                                                   #
#   $2 - Plan file                                                             #
#   $3 - Resource patterns                                                     #
# Returns:                                                                     #
#   SUCCESS and outputs JSON analysis, TERRAFORM_ERROR on failure              #
################################################################################
function _parse_plan_for_changes() {
    local terraform_dir="$1"
    local plan_file="$2"
    local resource_patterns="$3"

    log_debug "Parsing plan file for changes"

    # Convert plan to JSON if not already in JSON format
    local json_plan="/tmp/plan_analysis_$$.json"

    if ! terraform -chdir="$terraform_dir" show -json "$plan_file" > "$json_plan" 2>/dev/null; then
        log_error "Failed to convert plan to JSON format"
        rm -f "$json_plan"
        return $TERRAFORM_ERROR
    fi

    # Analyze JSON plan for destructive changes
    local analysis_output
    analysis_output=$(_analyze_json_plan "$json_plan" "$resource_patterns")
    local analysis_result=$?

    # Cleanup
    rm -f "$json_plan"

    if [[ $analysis_result -eq $SUCCESS ]]; then
        echo "$analysis_output"
        return $SUCCESS
    else
        return $TERRAFORM_ERROR
    fi
}

################################################################################
# Analyze JSON plan for specific change types                                  #
# Arguments:                                                                   #
#   $1 - JSON plan file                                                        #
#   $2 - Resource patterns to check                                            #
# Returns:                                                                     #
#   SUCCESS and outputs analysis JSON, TERRAFORM_ERROR on failure              #
################################################################################
function _analyze_json_plan() {
    local json_plan="$1"
    local resource_patterns="$2"

    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required for plan analysis"
        return $DEPENDENCY_ERROR
    fi

    # Extract resource changes that match patterns
    local destructive_changes=0
    local resources_to_recreate=()
    local resources_to_destroy=()

    # If no specific patterns provided, check all resources
    if [[ -z "$resource_patterns" ]]; then
        resource_patterns=".*"
    fi

    # Parse resource changes
    while IFS= read -r resource_change; do
        local resource_address
        local change_actions

        resource_address=$(echo "$resource_change" | jq -r '.address // "unknown"')
        change_actions=$(echo "$resource_change" | jq -r '.change.actions[]? // "none"' | tr '\n' ',' | sed 's/,$//')

        # Check if resource matches patterns
        if [[ "$resource_address" =~ $resource_patterns ]]; then
            case "$change_actions" in
                *"delete,create"*|*"create,delete"*)
                    resources_to_recreate+=("$resource_address")
                    ((destructive_changes++))
                    log_warn "Resource will be recreated: $resource_address"
                    ;;
                *"delete"*)
                    resources_to_destroy+=("$resource_address")
                    ((destructive_changes++))
                    log_warn "Resource will be destroyed: $resource_address"
                    ;;
            esac
        fi
    done < <(jq -c '.resource_changes[]? // empty' "$json_plan" 2>/dev/null)

    # Generate analysis report
    local analysis_report
    analysis_report=$(jq -n \
        --argjson destructive_changes "$destructive_changes" \
        --argjson resources_to_recreate "$(printf '%s\n' "${resources_to_recreate[@]}" | jq -R . | jq -s .)" \
        --argjson resources_to_destroy "$(printf '%s\n' "${resources_to_destroy[@]}" | jq -R . | jq -s .)" \
        '{
            destructive_changes: $destructive_changes,
            resources_to_recreate: $resources_to_recreate,
            resources_to_destroy: $resources_to_destroy,
            analysis_timestamp: now | todateiso8601
        }')

    echo "$analysis_report"
    return $SUCCESS
}

# =============================================================================
# TERRAFORM ERROR PROCESSING AND RECOVERY
# =============================================================================

#####################################################################################
# Enhanced Terraform error processing with structured error handling                #
# This breaks down the complex ImportAndReRunApply logic into manageable            #
# components                                                                        #
# Arguments:                                                                        #
#   $1 - Terraform error output file (JSON format)                                  #
#   $2 - Terraform module directory                                                 #
#   $3 - Import parameters                                                          #
#   $4 - Apply parameters                                                           #
#   $5 - Parallelism setting                                                        #
# Returns:                                                                          #
#   SUCCESS if errors resolved, TERRAFORM_ERROR if unrecoverable                    #
# Usage:                                                                            #
#   process_terraform_errors "apply_output.json" "/path/to/module" "$import_params" #
#####################################################################################
function process_terraform_errors() {
    if ! validate_function_params "process_terraform_errors" 4 "$#"; then
        return $PARAM_ERROR
    fi

    local error_file="${1:-}"
    local terraform_dir="${2:-}"
    local import_params="${3:-}"
    local apply_params="${4:-}"
    local parallelism="${5:-$TF_DEFAULT_PARALLELISM}"

    log_info "Processing Terraform errors from: $error_file"

    # Validate inputs
    if [[ ! -f "$error_file" ]]; then
        log_error "Error file does not exist: $error_file"
        return $FILE_ERROR
    fi

    if [[ ! -d "$terraform_dir" ]]; then
        log_error "Terraform directory does not exist: $terraform_dir"
        return $PARAM_ERROR
    fi

    # Analyze error file
    local error_analysis
    error_analysis=$(_analyze_terraform_errors "$error_file")
    local analysis_result=$?

    if [[ $analysis_result -ne $SUCCESS ]]; then
        log_error "Failed to analyze Terraform errors"
        return $TERRAFORM_ERROR
    fi

    # Extract error categories
    local import_errors permission_errors transient_errors other_errors
    import_errors=$(echo "$error_analysis" | jq -r '.import_errors // 0')
    permission_errors=$(echo "$error_analysis" | jq -r '.permission_errors // 0')
    transient_errors=$(echo "$error_analysis" | jq -r '.transient_errors // 0')
    other_errors=$(echo "$error_analysis" | jq -r '.other_errors // 0')

    log_info "Error analysis - Import: $import_errors, Permission: $permission_errors, Transient: $transient_errors, Other: $other_errors"

    # Process different error types
    local recovery_result=$SUCCESS

    # Handle import errors (resources that already exist)
    if [[ "$import_errors" -gt 0 ]]; then
        if ! _handle_import_errors "$error_file" "$terraform_dir" "$import_params"; then
            recovery_result=$TERRAFORM_ERROR
        fi
    fi

    # Handle permission errors (can usually be ignored for MSI scenarios)
    if [[ "$permission_errors" -gt 0 ]]; then
        _handle_permission_errors "$error_file"
    fi

    # Handle transient errors (retry logic)
    if [[ "$transient_errors" -gt 0 ]]; then
        if ! _handle_transient_errors "$terraform_dir" "$apply_params" "$parallelism"; then
            recovery_result=$TERRAFORM_ERROR
        fi
    fi

    # Report unhandled errors
    if [[ "$other_errors" -gt 0 ]]; then
        log_error "Unhandled errors detected: $other_errors"
        _display_unhandled_errors "$error_file"
        recovery_result=$TERRAFORM_ERROR
    fi

    return $recovery_result
}

################################################################################
# Analyze Terraform error output and categorize errors                         #
# Arguments:                                                                   #
#   $1 - Error file path                                                       #
# Returns:                                                                     #
#   SUCCESS and outputs JSON analysis, TERRAFORM_ERROR on failure              #
################################################################################
function _analyze_terraform_errors() {
    local error_file="$1"

    log_debug "Analyzing Terraform errors in: $error_file"

    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required for error analysis"
        return $DEPENDENCY_ERROR
    fi

    # Initialize counters
    local import_errors=0 permission_errors=0 transient_errors=0 other_errors=0
    local import_resources=() permission_messages=() transient_messages=() other_messages=()

    # Process each error message
    while IFS= read -r error_entry; do
        local error_message
        error_message=$(echo "$error_entry" | jq -r '.diagnostic.summary // .diagnostic.detail // "unknown error"' 2>/dev/null)

        if [[ -z "$error_message" || "$error_message" == "null" ]]; then
            continue
        fi

        # Categorize error
        local error_categorized=false

        # Check for import errors
        for pattern in "${TF_IMPORT_ERROR_PATTERNS[@]}"; do
            if [[ "$error_message" =~ $pattern ]]; then
                ((import_errors++))
                import_resources+=("$error_message")
                error_categorized=true
                break
            fi
        done

        # Check for permission errors
        if [[ "$error_categorized" == "false" ]]; then
            for pattern in "${TF_PERMISSION_ERROR_PATTERNS[@]}"; do
                if [[ "$error_message" =~ $pattern ]]; then
                    ((permission_errors++))
                    permission_messages+=("$error_message")
                    error_categorized=true
                    break
                fi
            done
        fi

        # Check for transient errors
        if [[ "$error_categorized" == "false" ]]; then
            for pattern in "${TF_TRANSIENT_ERROR_PATTERNS[@]}"; do
                if [[ "$error_message" =~ $pattern ]]; then
                    ((transient_errors++))
                    transient_messages+=("$error_message")
                    error_categorized=true
                    break
                fi
            done
        fi

        # Uncategorized errors
        if [[ "$error_categorized" == "false" ]]; then
            ((other_errors++))
            other_messages+=("$error_message")
        fi

    done < <(jq -c 'select(."@level" == "error") // empty' "$error_file" 2>/dev/null)

    # Generate analysis report
    local analysis_report
    analysis_report=$(jq -n \
        --argjson import_errors "$import_errors" \
        --argjson permission_errors "$permission_errors" \
        --argjson transient_errors "$transient_errors" \
        --argjson other_errors "$other_errors" \
        --argjson import_resources "$(printf '%s\n' "${import_resources[@]}" | jq -R . | jq -s .)" \
        --argjson permission_messages "$(printf '%s\n' "${permission_messages[@]}" | jq -R . | jq -s .)" \
        --argjson transient_messages "$(printf '%s\n' "${transient_messages[@]}" | jq -R . | jq -s .)" \
        --argjson other_messages "$(printf '%s\n' "${other_messages[@]}" | jq -R . | jq -s .)" \
        '{
            import_errors: $import_errors,
            permission_errors: $permission_errors,
            transient_errors: $transient_errors,
            other_errors: $other_errors,
            import_resources: $import_resources,
            permission_messages: $permission_messages,
            transient_messages: $transient_messages,
            other_messages: $other_messages,
            analysis_timestamp: now | todateiso8601
        }')

    echo "$analysis_report"
    return $SUCCESS
}

################################################################################
# Handle import errors by importing existing resources                         #
# Arguments:                                                                   #
#   $1 - Error file                                                            #
#   $2 - Terraform directory                                                   #
#   $3 - Import parameters                                                     #
# Returns:                                                                     #
#   SUCCESS if imports successful, TERRAFORM_ERROR on failure                  #
################################################################################
function _handle_import_errors() {
    local error_file="$1"
    local terraform_dir="$2"
    local import_params="$3"

    log_info "Handling import errors - importing existing resources"

    local import_success=0
    local import_failures=0

    # Extract resources that need importing
    while IFS= read -r error_entry; do
        local error_message error_address azure_resource_id

        error_message=$(echo "$error_entry" | jq -r '.diagnostic.summary // ""' 2>/dev/null)
        error_address=$(echo "$error_entry" | jq -r '.diagnostic.address // ""' 2>/dev/null)

        # Extract Azure resource ID from error message
        if [[ "$error_message" =~ \"([^\"]+)\" ]]; then
            azure_resource_id="${BASH_REMATCH[1]}"
        else
            log_warn "Could not extract resource ID from error: $error_message"
            continue
        fi

        if [[ -n "$error_address" && -n "$azure_resource_id" ]]; then
            log_info "Importing resource: $error_address -> $azure_resource_id"

            if _import_terraform_resource "$terraform_dir" "$error_address" "$azure_resource_id" "$import_params"; then
                ((import_success++))
            else
                ((import_failures++))
                log_error "Failed to import resource: $error_address"
            fi
        fi

    done < <(jq -c 'select(."@level" == "error" and (.diagnostic.summary | contains("A resource with the ID"))) // empty' "$error_file" 2>/dev/null)

    log_info "Import results - Success: $import_success, Failures: $import_failures"

    if [[ $import_failures -eq 0 ]]; then
        return $SUCCESS
    else
        return $TERRAFORM_ERROR
    fi
}

################################################################################
# Import a single Terraform resource                                           #
# Arguments:                                                                   #
#   $1 - Terraform directory                                                   #
#   $2 - Terraform resource address                                            #
#   $3 - Azure resource ID                                                     #
#   $4 - Import parameters                                                     #
# Returns:                                                                     #
#   SUCCESS if import successful, TERRAFORM_ERROR on failure                   #
################################################################################
function _import_terraform_resource() {
    local terraform_dir="$1"
    local resource_address="$2"
    local azure_resource_id="$3"
    local import_params="$4"

    log_debug "Importing Terraform resource: $resource_address"

    # Attempt import with timeout
    local import_output
    if import_output=$(timeout "$TF_IMPORT_TIMEOUT" terraform -chdir="$terraform_dir" import $import_params "$resource_address" "$azure_resource_id" 2>&1); then
        log_debug "Import successful: $resource_address"
        return $SUCCESS
    else
        local import_exit_code=$?
        log_warn "Import failed for $resource_address (exit code: $import_exit_code)"
        log_debug "Import output: $import_output"

        # Try to remove from state and import again
        if terraform -chdir="$terraform_dir" state rm "$resource_address" >/dev/null 2>&1; then
            log_debug "Removed resource from state, attempting import again"

            if timeout "$TF_IMPORT_TIMEOUT" terraform -chdir="$terraform_dir" import $import_params "$resource_address" "$azure_resource_id" >/dev/null 2>&1; then
                log_debug "Import successful after state removal: $resource_address"
                return $SUCCESS
            fi
        fi

        log_error "Failed to import resource after retry: $resource_address"
        return $TERRAFORM_ERROR
    fi
}

################################################################################
# Handle permission errors (typically safe to ignore in MSI scenarios)         #
# Arguments:                                                                   #
#   $1 - Error file                                                            #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _handle_permission_errors() {
    local error_file="$1"

    local permission_count
    permission_count=$(jq '[.[] | select(."@level" == "error" and (.diagnostic.summary | contains("The role assignment already exists")))] | length' "$error_file" 2>/dev/null || echo "0")

    if [[ "$permission_count" -gt 0 ]]; then
        log_info "Permission errors detected: $permission_count (can safely be ignored in MSI scenarios)"
        log_debug "These typically occur when role assignments already exist"
    fi

    return $SUCCESS
}

################################################################################
# Handle transient errors with retry logic                                     #
# Arguments:                                                                   #
#   $1 - Terraform directory                                                   #
#   $2 - Apply parameters                                                      #
#   $3 - Parallelism                                                           #
# Returns:                                                                     #
#   SUCCESS if retry successful, TERRAFORM_ERROR on continued failure          #
################################################################################
function _handle_transient_errors() {
    local terraform_dir="$1"
    local apply_params="$2"
    local parallelism="$3"

    log_info "Handling transient errors with retry logic"

    local retry_count=0
    local max_retries="$TF_MAX_RETRIES"

    while [[ $retry_count -lt $max_retries ]]; do
        ((retry_count++))
        log_info "Retry attempt $retry_count of $max_retries"

        # Wait before retry
        local wait_time=$((retry_count * 30))
        log_debug "Waiting $wait_time seconds before retry"
        sleep "$wait_time"

        # Retry apply
        if timeout "$TF_APPLY_TIMEOUT" terraform -chdir="$terraform_dir" apply -parallelism="$parallelism" $apply_params >/dev/null 2>&1; then
            log_info "Retry successful after $retry_count attempts"
            return $SUCCESS
        else
            log_warn "Retry $retry_count failed"
        fi
    done

    log_error "All retry attempts failed"
    return $TERRAFORM_ERROR
}

# =============================================================================
# TERRAFORM STATE MANAGEMENT
# =============================================================================

########################################################################################
# Enhanced resource replacement in state file                                          #
# This replaces ReplaceResourceInStateFile with improved functionality                 #
# Arguments:                                                                           #
#   $1 - Terraform directory                                                           #
#   $2 - Resource address to replace                                                   #
#   $3 - New resource ID                                                               #
#   $4 - Backup state file (optional)                                                  #
# Returns:                                                                             #
#   SUCCESS if replacement successful, TERRAFORM_ERROR on failure                      #
# Usage:                                                                               #
#   replace_terraform_resource "/path/to/module" "module.vm.azurerm_vm.main" "new-id"  #
########################################################################################
function replace_terraform_resource() {
    if ! validate_function_params "replace_terraform_resource" 3 "$#"; then
        return $PARAM_ERROR
    fi

    local terraform_dir="${1:-}"
    local resource_address="${2:-}"
    local new_resource_id="${3:-}"
    local backup_state="${4:-}"

    log_info "Replacing Terraform resource in state: $resource_address"
    log_debug "New resource ID: $new_resource_id"

    # Validate inputs
    if [[ ! -d "$terraform_dir" ]]; then
        log_error "Terraform directory does not exist: $terraform_dir"
        return $PARAM_ERROR
    fi

    # Create state backup if requested
    if [[ -n "$backup_state" ]]; then
        if ! _backup_terraform_state "$terraform_dir" "$backup_state"; then
            log_error "Failed to create state backup"
            return $TERRAFORM_ERROR
        fi
    fi

    # Remove existing resource from state
    log_debug "Removing resource from state: $resource_address"
    if ! terraform -chdir="$terraform_dir" state rm "$resource_address" >/dev/null 2>&1; then
        log_warn "Failed to remove resource from state (may not exist): $resource_address"
    fi

    # Import resource with new ID
    log_debug "Importing resource with new ID: $resource_address -> $new_resource_id"
    if terraform -chdir="$terraform_dir" import "$resource_address" "$new_resource_id" >/dev/null 2>&1; then
        log_info "Resource replacement successful: $resource_address"
        return $SUCCESS
    else
        log_error "Failed to import resource with new ID: $resource_address"

        # Restore from backup if available
        if [[ -n "$backup_state" && -f "$backup_state" ]]; then
            log_info "Attempting to restore from backup state"
            _restore_terraform_state "$terraform_dir" "$backup_state"
        fi

        return $TERRAFORM_ERROR
    fi
}

################################################################################
# Backup Terraform state                                                       #
# Arguments:                                                                   #
#   $1 - Terraform directory                                                   #
#   $2 - Backup file path                                                      #
# Returns:                                                                     #
#   SUCCESS if backup successful, TERRAFORM_ERROR on failure                   #
################################################################################
function _backup_terraform_state() {
    local terraform_dir="$1"
    local backup_file="$2"

    log_debug "Creating Terraform state backup: $backup_file"

    local state_file="${terraform_dir}/terraform.tfstate"

    if [[ -f "$state_file" ]]; then
        if cp "$state_file" "$backup_file" 2>/dev/null; then
            log_debug "State backup created successfully"
            return $SUCCESS
        else
            log_error "Failed to create state backup"
            return $TERRAFORM_ERROR
        fi
    else
        log_warn "No state file found to backup: $state_file"
        return $SUCCESS
    fi
}

################################################################################
# Restore Terraform state from backup                                          #
# Arguments:                                                                   #
#   $1 - Terraform directory                                                   #
#   $2 - Backup file path                                                      #
# Returns:                                                                     #
#   SUCCESS if restore successful, TERRAFORM_ERROR on failure                  #
################################################################################
function _restore_terraform_state() {
    local terraform_dir="$1"
    local backup_file="$2"

    log_info "Restoring Terraform state from backup: $backup_file"

    local state_file="${terraform_dir}/terraform.tfstate"

    if [[ -f "$backup_file" ]]; then
        if cp "$backup_file" "$state_file" 2>/dev/null; then
            log_info "State restored successfully from backup"
            return $SUCCESS
        else
            log_error "Failed to restore state from backup"
            return $TERRAFORM_ERROR
        fi
    else
        log_error "Backup file not found: $backup_file"
        return $TERRAFORM_ERROR
    fi
}

# =============================================================================
# HIGH-LEVEL TERRAFORM OPERATIONS
# =============================================================================

########################################################################################
# Comprehensive Terraform apply with error recovery                                    #
# This combines all the error handling and recovery logic into a single function       #
# Arguments:                                                                           #
#   $1 - Terraform directory                                                           #
#   $2 - Apply parameters                                                              #
#   $3 - Import parameters                                                             #
#   $4 - Parallelism (optional)                                                        #
#   $5 - Enable auto-recovery (true/false, default: true)                              #
# Returns:                                                                             #
#   SUCCESS if apply successful, TERRAFORM_ERROR on failure                            #
# Usage:                                                                               #
#   terraform_apply_with_recovery "/path/to/module" "$apply_params" "$import_params"   #
########################################################################################
function terraform_apply_with_recovery() {
    if ! validate_function_params "terraform_apply_with_recovery" 3 "$#"; then
        return $PARAM_ERROR
    fi

    local terraform_dir="${1:-}"
    local apply_params="${2:-}"
    local import_params="${3:-}"
    local parallelism="${4:-$TF_DEFAULT_PARALLELISM}"
    local auto_recovery="${5:-true}"

    log_info "Starting Terraform apply with error recovery"
    log_debug "Directory: $terraform_dir, Parallelism: $parallelism, Auto-recovery: $auto_recovery"

    # Validate inputs
    if [[ ! -d "$terraform_dir" ]]; then
        log_error "Terraform directory does not exist: $terraform_dir"
        return $PARAM_ERROR
    fi

    # Execute initial apply
    local apply_output="/tmp/tf_apply_output_$$.json"
    local apply_result

    log_info "Executing Terraform apply"

    # shellcheck disable=SC2086
    if timeout "$TF_APPLY_TIMEOUT" terraform -chdir="$terraform_dir" apply -parallelism="$parallelism" \
        $apply_params -no-color -compact-warnings -json -input=false --auto-approve > "$apply_output" 2>&1; then
        apply_result=$SUCCESS
        log_info "Terraform apply completed successfully"
    else
        apply_result=$TERRAFORM_ERROR
        log_warn "Terraform apply encountered errors"
    fi

    # Process errors if auto-recovery is enabled
    if [[ $apply_result -ne $SUCCESS && "$auto_recovery" == "true" ]]; then
        log_info "Attempting error recovery"

        if process_terraform_errors "$apply_output" "$terraform_dir" "$import_params" "$apply_params" "$parallelism"; then
            log_info "Error recovery successful"
            apply_result=$SUCCESS
        else
            log_error "Error recovery failed"
            apply_result=$TERRAFORM_ERROR
        fi
    fi

    # Cleanup
    rm -f "$apply_output"

    return $apply_result
}

# =============================================================================
# BACKWARD COMPATIBILITY FUNCTIONS
# =============================================================================

################################################################################
# Legacy ImportAndReRunApply function for backward compatibility               #
################################################################################
function ImportAndReRunApply() {
    deprecation_warning "ImportAndReRunApply" "process_terraform_errors"
    process_terraform_errors "$@"
    return $?
}

################################################################################
# Legacy testIfResourceWouldBeRecreated function for backward compatibility    #
################################################################################
function testIfResourceWouldBeRecreated() {
    deprecation_warning "testIfResourceWouldBeRecreated" "analyze_terraform_plan"

    local resource_pattern="$1"
    local plan_file="$2"
    local description="${3:-resource}"

    # Convert to new function parameters
    analyze_terraform_plan "." "$plan_file" "$resource_pattern"
    local result=$?

    if [[ $result -eq $SUCCESS ]]; then
        log_info "No destructive changes detected for $description"
        return 0  # Legacy return code
    else
        log_error "Destructive changes detected for $description"
        return 1  # Legacy return code
    fi
}

################################################################################
# Legacy ReplaceResourceInStateFile function for backward compatibility        #
################################################################################
function ReplaceResourceInStateFile() {
    deprecation_warning "ReplaceResourceInStateFile" "replace_terraform_resource"
    replace_terraform_resource "." "$@"
    return $?
}

# =============================================================================
# ERROR DISPLAY FUNCTIONS
# =============================================================================

################################################################################
# Display destructive changes from plan analysis                               #
# Arguments:                                                                   #
#   $1 - Analysis JSON                                                         #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _display_destructive_changes() {
    local analysis="$1"

    echo ""
    echo "#################################################################################"
    echo "#                                                                               #"
    echo "#                        ⚠️  DESTRUCTIVE CHANGES DETECTED  ⚠️                   #"
    echo "#                                                                               #"
    echo "#################################################################################"
    echo ""

    local resources_to_recreate resources_to_destroy
    resources_to_recreate=$(echo "$analysis" | jq -r '.resources_to_recreate[]? // empty' 2>/dev/null)
    resources_to_destroy=$(echo "$analysis" | jq -r '.resources_to_destroy[]? // empty' 2>/dev/null)

    if [[ -n "$resources_to_recreate" ]]; then
        echo "Resources that will be RECREATED (data loss risk):"
        echo "$resources_to_recreate" | while read -r resource; do
            echo "  🔄 $resource"
        done
        echo ""
    fi

    if [[ -n "$resources_to_destroy" ]]; then
        echo "Resources that will be DESTROYED:"
        echo "$resources_to_destroy" | while read -r resource; do
            echo "  🗑️  $resource"
        done
        echo ""
    fi

    echo "Please review these changes carefully before proceeding."
    echo ""
}

################################################################################
# Display unhandled errors                                                     #
# Arguments:                                                                   #
#   $1 - Error file                                                            #
# Returns:                                                                     #
#   Always SUCCESS                                                             #
################################################################################
function _display_unhandled_errors() {
    local error_file="$1"

    echo ""
    echo "#################################################################################"
    echo "#                                                                               #"
    echo "#                        UNHANDLED TERRAFORM ERRORS                            #"
    echo "#                                                                               #"
    echo "#################################################################################"
    echo ""

    jq -r 'select(."@level" == "error") | .diagnostic.summary // .diagnostic.detail // "Unknown error"' "$error_file" 2>/dev/null | \
    while read -r error_msg; do
        echo "  ❌ $error_msg"
    done

    echo ""
    echo "These errors require manual intervention."
    echo ""
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

log_info "Terraform operations module loaded successfully"
log_debug "Available functions: analyze_terraform_plan, process_terraform_errors, replace_terraform_resource, terraform_apply_with_recovery, validate_terraform_configuration_structure"
log_debug "Backward compatibility functions available for legacy scripts"
log_debug "Terraform timeouts - Plan: ${TF_PLAN_TIMEOUT}s, Apply: ${TF_APPLY_TIMEOUT}s, Import: ${TF_IMPORT_TIMEOUT}s"
