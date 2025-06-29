#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Migration Utilities Module - Tools for Legacy to Refactored Transition
# This module provides utilities to help migrate from the legacy script_helpers.sh
# to the refactored modular architecture, including compatibility checking,
# usage analysis, and automated migration assistance

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
# MIGRATION CONFIGURATION
# =============================================================================

# Migration tracking
declare -g MIGRATION_LOG_FILE="${MIGRATION_LOG_FILE:-/tmp/sdaf_migration.log}"
declare -g MIGRATION_ANALYSIS_FILE="${MIGRATION_ANALYSIS_FILE:-/tmp/sdaf_analysis.json}"
declare -g MIGRATION_BACKUP_DIR="${MIGRATION_BACKUP_DIR:-/tmp/sdaf_backup}"

# Legacy function tracking
declare -A LEGACY_FUNCTION_USAGE
declare -A REFACTORED_FUNCTION_MAPPING
# shellcheck disable=SC2034
declare -A MIGRATION_STATUS

# Initialize function mappings
REFACTORED_FUNCTION_MAPPING=(
    ["print_banner"]="display_banner"
    ["validate_exports"]="validate_environment"
    ["validate_dependencies"]="validate_system_dependencies"
    ["validate_key_parameters"]="validate_parameter_file"
    ["validate_key_vault"]="validate_keyvault_access"
    ["version_compare"]="compare_semantic_versions"
    ["get_escaped_string"]="escape_string"
    ["LogonToAzure"]="authenticate_azure"
    ["getVariableFromApplicationConfiguration"]="get_app_config_variable"
    ["ImportAndReRunApply"]="process_terraform_errors"
    ["testIfResourceWouldBeRecreated"]="analyze_terraform_plan"
    ["ReplaceResourceInStateFile"]="replace_terraform_resource"
)

# =============================================================================
# COMPATIBILITY ANALYSIS FUNCTIONS
# =============================================================================

############################################################################################
# Analyze script files for legacy function usage                                          #
# Arguments:                                                                              #
#   $1 - Directory to analyze                                                            #
#   $2 - File pattern (optional, default: "*.sh")                                       #
#   $3 - Output format (json, text) - default: json                                     #
# Returns:                                                                                #
#   SUCCESS if analysis complete, FILE_ERROR if directory invalid                       #
# Usage:                                                                                  #
#   analyze_legacy_usage "/path/to/scripts" "*.sh" "json"                               #
############################################################################################
function analyze_legacy_usage() {
    if ! validate_function_params "analyze_legacy_usage" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local target_dir="${1:-}"
    local file_pattern="${2:-*.sh}"
    local output_format="${3:-json}"

    log_info "Analyzing legacy function usage in: $target_dir"
    log_debug "File pattern: $file_pattern, Output format: $output_format"

    # Validate target directory
    if [[ ! -d "$target_dir" ]]; then
        log_error "Target directory does not exist: $target_dir"
        return $FILE_ERROR
    fi

    # Initialize usage tracking
    LEGACY_FUNCTION_USAGE=()

    # Analyze files
    local total_files=0
    local files_with_legacy=0

    while IFS= read -r -d '' file; do
        ((total_files++))
        if _analyze_file_usage "$file"; then
            ((files_with_legacy++))
        fi
    done < <(find "$target_dir" -name "$file_pattern" -type f -print0)

    log_info "Analysis complete: $total_files files analyzed, $files_with_legacy contain legacy functions"

    # Generate output
    case "$output_format" in
        json)
            _generate_usage_analysis_json "$total_files" "$files_with_legacy"
            ;;
        text)
            _generate_usage_analysis_text "$total_files" "$files_with_legacy"
            ;;
        *)
            log_error "Invalid output format: $output_format"
            return $PARAM_ERROR
            ;;
    esac

    return $SUCCESS
}

############################################################################################
# Analyze individual file for legacy function usage                                       #
# Arguments:                                                                              #
#   $1 - File path                                                                       #
# Returns:                                                                                #
#   SUCCESS if legacy functions found, GENERAL_ERROR if none found                      #
############################################################################################
function _analyze_file_usage() {
    local file_path="$1"
    local found_legacy=false

    log_debug "Analyzing file: $file_path"

    # Check for each legacy function
    for legacy_func in "${!REFACTORED_FUNCTION_MAPPING[@]}"; do
        local usage_count
        usage_count=$(grep -c "\b${legacy_func}\b" "$file_path" 2>/dev/null || echo "0")

        if [[ "$usage_count" -gt 0 ]]; then
            LEGACY_FUNCTION_USAGE["${file_path}:${legacy_func}"]="$usage_count"
            found_legacy=true
            log_debug "Found $usage_count usages of $legacy_func in $file_path"
        fi
    done

    if [[ "$found_legacy" == "true" ]]; then
        return $SUCCESS
    else
        return $GENERAL_ERROR
    fi
}

############################################################################################
# Generate compatibility report                                                           #
# Arguments:                                                                              #
#   $1 - Target directory for analysis                                                   #
#   $2 - Report output file (optional)                                                   #
# Returns:                                                                                #
#   SUCCESS if report generated, FILE_ERROR on failure                                  #
# Usage:                                                                                  #
#   generate_compatibility_report "/path/to/scripts" "/tmp/compatibility_report.html"   #
############################################################################################
function generate_compatibility_report() {
    if ! validate_function_params "generate_compatibility_report" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local target_dir="${1:-}"
    local report_file="${2:-${MIGRATION_ANALYSIS_FILE%.*}.html}"

    log_info "Generating compatibility report for: $target_dir"

    # Perform analysis
    if ! analyze_legacy_usage "$target_dir" "*.sh" "json"; then
        log_error "Failed to analyze legacy usage"
        return $FILE_ERROR
    fi

    # Generate HTML report
    _generate_html_report "$report_file"

    log_info "Compatibility report generated: $report_file"
    return $SUCCESS
}

# =============================================================================
# MIGRATION PLANNING FUNCTIONS
# =============================================================================

############################################################################################
# Create migration plan for scripts                                                       #
# Arguments:                                                                              #
#   $1 - Analysis file (JSON format)                                                     #
#   $2 - Migration plan output file                                                      #
#   $3 - Migration strategy (conservative, moderate, aggressive)                         #
# Returns:                                                                                #
#   SUCCESS if plan created, FILE_ERROR on failure                                      #
# Usage:                                                                                  #
#   create_migration_plan "$analysis_file" "$plan_file" "moderate"                      #
############################################################################################
function create_migration_plan() {
    if ! validate_function_params "create_migration_plan" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local analysis_file="${1:-}"
    local plan_file="${2:-}"
    local strategy="${3:-moderate}"

    log_info "Creating migration plan with strategy: $strategy"

    # Validate analysis file
    if [[ ! -f "$analysis_file" ]]; then
        log_error "Analysis file does not exist: $analysis_file"
        return $FILE_ERROR
    fi

    # Generate migration plan based on strategy
    {
        echo "# SAP Deployment Automation Framework - Migration Plan"
        echo "# Generated: $(date)"
        echo "# Strategy: $strategy"
        echo ""

        _generate_strategy_overview "$strategy"
        _generate_migration_phases "$analysis_file" "$strategy"
        _generate_risk_assessment "$strategy"
        _generate_rollback_plan

    } > "$plan_file"

    log_info "Migration plan created: $plan_file"
    return $SUCCESS
}

############################################################################################
# Validate migration readiness                                                            #
# Arguments:                                                                              #
#   $1 - Target environment (dev, test, prod)                                           #
# Returns:                                                                                #
#   SUCCESS if ready for migration, GENERAL_ERROR if not ready                          #
# Usage:                                                                                  #
#   validate_migration_readiness "prod"                                                 #
############################################################################################
function validate_migration_readiness() {
    local environment="${1:-dev}"

    log_info "Validating migration readiness for environment: $environment"

    local readiness_score=0
    local max_score=0
    local issues=()

    # Check 1: Module availability
    ((max_score++))
    if check_refactoring_status >/dev/null 2>&1; then
        ((readiness_score++))
        log_debug "✅ All modules are available"
    else
        issues+=("❌ Some modules are not properly loaded")
    fi

    # Check 2: Testing status
    ((max_score++))
    if run_all_tests "unit" >/dev/null 2>&1; then
        ((readiness_score++))
        log_debug "✅ Unit tests are passing"
    else
        issues+=("❌ Unit tests are failing")
    fi

    # Check 3: Backup capability
    ((max_score++))
    if [[ -d "$MIGRATION_BACKUP_DIR" ]] || mkdir -p "$MIGRATION_BACKUP_DIR" 2>/dev/null; then
        ((readiness_score++))
        log_debug "✅ Backup directory is available"
    else
        issues+=("❌ Cannot create backup directory: $MIGRATION_BACKUP_DIR")
    fi

    # Check 4: Environment-specific checks
    case "$environment" in
        prod)
            ((max_score++))
            if [[ -n "${SDAF_PRODUCTION_VALIDATION:-}" ]]; then
                ((readiness_score++))
                log_debug "✅ Production validation flag is set"
            else
                issues+=("❌ Production validation flag not set")
            fi
            ;;
        test)
            ((max_score++))
            if command -v terraform >/dev/null 2>&1 && command -v az >/dev/null 2>&1; then
                ((readiness_score++))
                log_debug "✅ Required tools are available"
            else
                issues+=("❌ Required tools (terraform, az) not available")
            fi
            ;;
        dev)
            ((readiness_score++))
            log_debug "✅ Development environment - no additional checks"
            ;;
    esac

    # Calculate readiness percentage
    local readiness_percentage
    readiness_percentage=$(( max_score > 0 ? (readiness_score * 100) / max_score : 0 ))

    log_info "Migration readiness: $readiness_percentage% ($readiness_score/$max_score)"

    # Display issues if any
    if [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        echo "🚨 Migration Readiness Issues:"
        for issue in "${issues[@]}"; do
            echo "   $issue"
        done
        echo ""
    fi

    # Determine readiness based on environment
    local required_percentage
    case "$environment" in
        prod) required_percentage=100 ;;
        test) required_percentage=80 ;;
        dev) required_percentage=60 ;;
        *) required_percentage=80 ;;
    esac

    if [[ $readiness_percentage -ge $required_percentage ]]; then
        display_success "Migration Ready" "Environment $environment is ready for migration ($readiness_percentage%)"
        return $SUCCESS
    else
        display_error "Migration Not Ready" "Environment $environment requires $required_percentage% readiness, current: $readiness_percentage%"
        return $GENERAL_ERROR
    fi
}

# =============================================================================
# AUTOMATED MIGRATION FUNCTIONS
# =============================================================================

############################################################################################
# Perform automatic migration of script files                                             #
# Arguments:                                                                              #
#   $1 - Source directory                                                                #
#   $2 - Backup directory                                                                #
#   $3 - Dry run (true/false) - default: true                                           #
# Returns:                                                                                #
#   SUCCESS if migration complete, FILE_ERROR on failure                                #
# Usage:                                                                                  #
#   migrate_scripts_automatically "/path/to/scripts" "/path/to/backup" "false"          #
############################################################################################
function migrate_scripts_automatically() {
    if ! validate_function_params "migrate_scripts_automatically" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local source_dir="${1:-}"
    local backup_dir="${2:-}"
    local dry_run="${3:-true}"

    log_info "Starting automatic migration: source=$source_dir, backup=$backup_dir, dry_run=$dry_run"

    # Validate directories
    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory does not exist: $source_dir"
        return $FILE_ERROR
    fi

    # Create backup directory
    if ! create_directory_safe "$backup_dir" "755" "true"; then
        log_error "Failed to create backup directory: $backup_dir"
        return $FILE_ERROR
    fi

    # Find shell scripts to migrate
    local scripts_to_migrate=()
    while IFS= read -r -d '' script; do
        if _script_needs_migration "$script"; then
            scripts_to_migrate+=("$script")
        fi
    done < <(find "$source_dir" -name "*.sh" -type f -print0)

    log_info "Found ${#scripts_to_migrate[@]} scripts that need migration"

    # Process each script
    local migrated_count=0
    local failed_count=0

    for script in "${scripts_to_migrate[@]}"; do
        log_info "Processing script: $script"

        if _migrate_single_script "$script" "$backup_dir" "$dry_run"; then
            ((migrated_count++))
        else
            ((failed_count++))
        fi
    done

    # Report results
    log_info "Migration complete: $migrated_count successful, $failed_count failed"

    if [[ $failed_count -eq 0 ]]; then
        display_success "Migration Complete" "$migrated_count scripts migrated successfully"
        return $SUCCESS
    else
        display_error "Migration Partial" "$failed_count scripts failed to migrate"
        return $GENERAL_ERROR
    fi
}

############################################################################################
# Check if script needs migration                                                         #
# Arguments:                                                                              #
#   $1 - Script file path                                                                #
# Returns:                                                                                #
#   SUCCESS if migration needed, GENERAL_ERROR otherwise                                #
############################################################################################
function _script_needs_migration() {
    local script_file="$1"

    # Check for legacy function usage
    for legacy_func in "${!REFACTORED_FUNCTION_MAPPING[@]}"; do
        if grep -q "\b${legacy_func}\b" "$script_file" 2>/dev/null; then
            return $SUCCESS
        fi
    done

    return $GENERAL_ERROR
}

############################################################################################
# Migrate a single script file                                                            #
# Arguments:                                                                              #
#   $1 - Script file path                                                                #
#   $2 - Backup directory                                                                #
#   $3 - Dry run flag                                                                    #
# Returns:                                                                                #
#   SUCCESS if migration successful, FILE_ERROR on failure                              #
############################################################################################
function _migrate_single_script() {
    local script_file="$1"
    local backup_dir="$2"
    local dry_run="$3"

    local script_name
    script_name=$(basename "$script_file")
    local backup_file
		backup_file="${backup_dir}/${script_name}.backup.$(date +%Y%m%d_%H%M%S)"

    log_debug "Migrating script: $script_file"

    # Create backup
    if [[ "$dry_run" == "false" ]]; then
        if ! cp "$script_file" "$backup_file"; then
            log_error "Failed to create backup: $backup_file"
            return $FILE_ERROR
        fi
        log_debug "Backup created: $backup_file"
    fi

    # Apply migrations
    local temp_file="${script_file}.tmp"
    local migration_applied=false

    # Copy original to temp file
    if [[ "$dry_run" == "false" ]]; then
        cp "$script_file" "$temp_file"
    else
        temp_file="$script_file"  # For dry run, just reference original
    fi

    # Apply function replacements
    for legacy_func in "${!REFACTORED_FUNCTION_MAPPING[@]}"; do
        local refactored_func="${REFACTORED_FUNCTION_MAPPING[$legacy_func]}"

        if grep -q "\b${legacy_func}\b" "$temp_file" 2>/dev/null; then
            log_debug "Replacing $legacy_func with $refactored_func"

            if [[ "$dry_run" == "false" ]]; then
                sed -i "s/\b${legacy_func}\b/${refactored_func}/g" "$temp_file"
            fi

            migration_applied=true
        fi
    done

    # Apply file modifications if not dry run
    if [[ "$dry_run" == "false" && "$migration_applied" == "true" ]]; then
        if mv "$temp_file" "$script_file"; then
            log_info "✅ Migrated: $script_file"
            return $SUCCESS
        else
            log_error "❌ Failed to apply migration: $script_file"
            return $FILE_ERROR
        fi
    elif [[ "$dry_run" == "true" && "$migration_applied" == "true" ]]; then
        log_info "🔍 Would migrate: $script_file"
        return $SUCCESS
    else
        log_debug "No migration needed: $script_file"
        return $SUCCESS
    fi
}

# =============================================================================
# ROLLBACK FUNCTIONS
# =============================================================================

############################################################################################
# Rollback migration changes                                                              #
# Arguments:                                                                              #
#   $1 - Backup directory                                                                #
#   $2 - Target directory                                                                #
# Returns:                                                                                #
#   SUCCESS if rollback complete, FILE_ERROR on failure                                 #
# Usage:                                                                                  #
#   rollback_migration "/path/to/backup" "/path/to/scripts"                             #
############################################################################################
function rollback_migration() {
    if ! validate_function_params "rollback_migration" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local backup_dir="${1:-}"
    local target_dir="${2:-}"

    log_info "Starting migration rollback: backup=$backup_dir, target=$target_dir"

    # Validate directories
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory does not exist: $backup_dir"
        return $FILE_ERROR
    fi

    if [[ ! -d "$target_dir" ]]; then
        log_error "Target directory does not exist: $target_dir"
        return $FILE_ERROR
    fi

    # Find backup files
    local backup_files=()
    while IFS= read -r -d '' backup_file; do
        backup_files+=("$backup_file")
    done < <(find "$backup_dir" -name "*.backup.*" -type f -print0)

    log_info "Found ${#backup_files[@]} backup files to restore"

    # Restore each backup
    local restored_count=0
    local failed_count=0

    for backup_file in "${backup_files[@]}"; do
        local original_name
        original_name=$(basename "$backup_file" | sed 's/\.backup\..*$//')
        local target_file="${target_dir}/${original_name}"

        log_debug "Restoring: $backup_file -> $target_file"

        if cp "$backup_file" "$target_file" 2>/dev/null; then
            ((restored_count++))
            log_info "✅ Restored: $original_name"
        else
            ((failed_count++))
            log_error "❌ Failed to restore: $original_name"
        fi
    done

    # Report results
    log_info "Rollback complete: $restored_count restored, $failed_count failed"

    if [[ $failed_count -eq 0 ]]; then
        display_success "Rollback Complete" "$restored_count files restored successfully"
        return $SUCCESS
    else
        display_error "Rollback Partial" "$failed_count files failed to restore"
        return $GENERAL_ERROR
    fi
}

# =============================================================================
# REPORT GENERATION FUNCTIONS
# =============================================================================

############################################################################################
# Generate usage analysis in JSON format                                                  #
############################################################################################
function _generate_usage_analysis_json() {
    local total_files="$1"
    local files_with_legacy="$2"

    local json_output
    json_output=$(jq -n \
        --argjson total_files "$total_files" \
        --argjson files_with_legacy "$files_with_legacy" \
        --argjson timestamp "$(date +%s)" \
        '{
            analysis_metadata: {
                total_files: $total_files,
                files_with_legacy: $files_with_legacy,
                analysis_date: ($timestamp | todateiso8601)
            },
            legacy_function_usage: {},
            migration_recommendations: []
        }')

    # Add usage data
    for usage_key in "${!LEGACY_FUNCTION_USAGE[@]}"; do
        local file_path="${usage_key%:*}"
        local function_name="${usage_key#*:}"
        local usage_count="${LEGACY_FUNCTION_USAGE[$usage_key]}"

        json_output=$(echo "$json_output" | jq \
            --arg file "$file_path" \
            --arg func "$function_name" \
            --argjson count "$usage_count" \
            '.legacy_function_usage[$file] += {($func): $count}')
    done

    # Save to file
    echo "$json_output" > "$MIGRATION_ANALYSIS_FILE"
    log_info "Usage analysis saved to: $MIGRATION_ANALYSIS_FILE"
}

############################################################################################
# Generate usage analysis in text format                                                  #
############################################################################################
function _generate_usage_analysis_text() {
    local total_files="$1"
    local files_with_legacy="$2"

    {
        echo "SAP Deployment Automation Framework - Legacy Usage Analysis"
        echo "=========================================================="
        echo "Analysis Date: $(date)"
        echo "Total Files Analyzed: $total_files"
        echo "Files with Legacy Functions: $files_with_legacy"
        echo ""

        if [[ ${#LEGACY_FUNCTION_USAGE[@]} -gt 0 ]]; then
            echo "Legacy Function Usage:"
            echo "----------------------"

            for usage_key in "${!LEGACY_FUNCTION_USAGE[@]}"; do
                local file_path="${usage_key%:*}"
                local function_name="${usage_key#*:}"
                local usage_count="${LEGACY_FUNCTION_USAGE[$usage_key]}"
                local refactored_func="${REFACTORED_FUNCTION_MAPPING[$function_name]:-unknown}"

                echo "File: $file_path"
                echo "  Function: $function_name (used $usage_count times)"
                echo "  Recommended replacement: $refactored_func"
                echo ""
            done
        else
            echo "No legacy function usage found."
        fi

    } > "${MIGRATION_ANALYSIS_FILE%.*}.txt"

    log_info "Text analysis saved to: ${MIGRATION_ANALYSIS_FILE%.*}.txt"
}

############################################################################################
# Generate HTML compatibility report                                                      #
############################################################################################
function _generate_html_report() {
    local report_file="$1"

    {
        cat << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>SAP Deployment Automation Framework - Compatibility Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { background-color: #e6f3ff; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .section { margin: 20px 0; }
        .legacy-usage { background-color: #fff3cd; padding: 10px; margin: 10px 0; border-radius: 3px; }
        .recommendation { background-color: #d4edda; padding: 10px; margin: 10px 0; border-radius: 3px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>SAP Deployment Automation Framework</h1>
        <h2>Legacy Function Compatibility Report</h2>
        <p>Generated: <span id="report-date"></span></p>
    </div>

    <div class="summary">
        <h3>Summary</h3>
        <p>This report analyzes the usage of legacy functions in your SAP deployment automation scripts and provides recommendations for migration to the refactored architecture.</p>
    </div>

    <script>
        document.getElementById('report-date').textContent = new Date().toISOString();
    </script>
</body>
</html>
EOF
    } > "$report_file"

    log_info "HTML report template generated: $report_file"
}

# =============================================================================
# MIGRATION STRATEGY HELPERS
# =============================================================================

function _generate_strategy_overview() {
    local strategy="$1"

    echo "## Migration Strategy: $strategy"
    echo ""

    case "$strategy" in
        conservative)
            echo "### Conservative Approach"
            echo "- Gradual migration with extensive testing"
            echo "- Feature flags enabled for rollback capability"
            echo "- Manual verification at each step"
            echo "- Minimal risk, longer timeline"
            ;;
        moderate)
            echo "### Moderate Approach"
            echo "- Balanced migration with automated testing"
            echo "- Phased rollout with monitoring"
            echo "- Some manual verification for critical functions"
            echo "- Moderate risk, reasonable timeline"
            ;;
        aggressive)
            echo "### Aggressive Approach"
            echo "- Rapid migration with automated validation"
            echo "- Comprehensive testing suite execution"
            echo "- Minimal manual intervention"
            echo "- Higher risk, faster timeline"
            ;;
    esac
    echo ""
}

function _generate_migration_phases() {
    local analysis_file="$1"
    local strategy="$2"

    echo "## Migration Phases"
    echo ""
    echo "### Phase 1: Preparation and Validation"
    echo "- [ ] Run compatibility analysis"
    echo "- [ ] Execute comprehensive test suite"
    echo "- [ ] Create backup of all scripts"
    echo "- [ ] Validate migration readiness"
    echo ""
    echo "### Phase 2: Feature Flag Enablement"
    echo "- [ ] Enable refactored display functions"
    echo "- [ ] Enable refactored validation functions"
    echo "- [ ] Enable refactored utility functions"
    echo "- [ ] Test each component individually"
    echo ""
    echo "### Phase 3: Operations Layer Migration"
    echo "- [ ] Enable refactored Terraform operations"
    echo "- [ ] Enable refactored Azure integration"
    echo "- [ ] Validate complex operations"
    echo "- [ ] Performance testing"
    echo ""
    echo "### Phase 4: Production Deployment"
    echo "- [ ] Deploy to production environment"
    echo "- [ ] Monitor for issues"
    echo "- [ ] Validate all functionality"
    echo "- [ ] Document lessons learned"
    echo ""
}

function _generate_risk_assessment() {
    local strategy="$1"

    echo "## Risk Assessment"
    echo ""
    echo "### Identified Risks"
    echo "- **Backward Compatibility**: Risk of breaking existing scripts"
    echo "  - Mitigation: 100% backward compatibility maintained"
    echo ""
    echo "- **Performance Impact**: Risk of performance degradation"
    echo "  - Mitigation: Performance testing included in migration"
    echo ""
    echo "- **Integration Issues**: Risk of module integration problems"
    echo "  - Mitigation: Comprehensive integration testing"
    echo ""
    echo "- **Operational Disruption**: Risk of service interruption"
    echo "  - Mitigation: Feature flags enable immediate rollback"
    echo ""
}

function _generate_rollback_plan() {
    echo "## Rollback Plan"
    echo ""
    echo "### Quick Rollback (Feature Flags)"
    echo "1. Execute: \`disable_refactored_functions\`"
    echo "2. Verify legacy functions are working"
    echo "3. Monitor for stability"
    echo ""
    echo "### Full Rollback (File Restoration)"
    echo "1. Execute: \`rollback_migration /path/to/backup /path/to/scripts\`"
    echo "2. Restart affected services"
    echo "3. Validate functionality"
    echo "4. Document rollback reason"
    echo ""
    echo "### Emergency Contacts"
    echo "- Operations Team: ops@company.com"
    echo "- Development Team: dev@company.com"
    echo "- Management Escalation: manager@company.com"
    echo ""
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Create migration directories if they don't exist
create_directory_safe "$MIGRATION_BACKUP_DIR" "755" "true"

log_info "Migration utilities module loaded successfully"
log_debug "Available functions: analyze_legacy_usage, generate_compatibility_report, validate_migration_readiness, migrate_scripts_automatically"
log_debug "Migration configuration - Log: $MIGRATION_LOG_FILE, Analysis: $MIGRATION_ANALYSIS_FILE, Backup: $MIGRATION_BACKUP_DIR"
