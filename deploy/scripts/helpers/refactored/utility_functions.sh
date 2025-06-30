#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Utility Functions Module - Pure Functions for Common Operations
# This module provides utility functions that have no side effects and can be used
# throughout the SAP deployment automation framework

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
# VERSION MANAGEMENT FUNCTIONS
# =============================================================================

################################################################################
# Enhanced semantic version comparison with detailed logging                   #
# This replaces the original version_compare() with improved functionality     #
# Arguments:                                                                   #
#   $1 - First version string (e.g., "1.2.3")                                  #
#   $2 - Second version string (e.g., "1.2.4")                                 #
# Returns:                                                                     #
#   0 - Versions are equal                                                     #
#   1 - First version is greater than second                                   #
#   2 - First version is less than second                                      #
#   PARAM_ERROR - Invalid input parameters                                     #
# Usage:                                                                       #
#   compare_semantic_versions "1.2.3" "1.2.4"                                  #
#   result=$?; echo "Comparison result: $result"                               #
################################################################################
function compare_semantic_versions() {
    if ! validate_function_params "compare_semantic_versions" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local version1="${1:-}"
    local version2="${2:-}"

    log_debug "Comparing versions: $version1 vs $version2"

    # Input validation
    if [[ -z "$version1" ]]; then
        log_error "First version parameter is empty"
        return $PARAM_ERROR
    fi

    if [[ -z "$version2" ]]; then
        log_error "Second version parameter is empty"
        return $PARAM_ERROR
    fi

    # Validate version format
    if ! _is_valid_version_format "$version1"; then
        log_error "Invalid version format: $version1"
        return $PARAM_ERROR
    fi

    if ! _is_valid_version_format "$version2"; then
        log_error "Invalid version format: $version2"
        return $PARAM_ERROR
    fi

    # Quick equality check
    if [[ "$version1" == "$version2" ]]; then
        log_debug "Versions are equal: $version1 = $version2"
        return 0
    fi

    # Parse and compare version components
    local -a v1_parts v2_parts
    IFS='.' read -ra v1_parts <<< "$version1"
    IFS='.' read -ra v2_parts <<< "$version2"

    # Normalize arrays to same length (pad with zeros)
    local max_parts
    max_parts=$(( ${#v1_parts[@]} > ${#v2_parts[@]} ? ${#v1_parts[@]} : ${#v2_parts[@]} ))

    while [[ ${#v1_parts[@]} -lt $max_parts ]]; do
        v1_parts+=("0")
    done

    while [[ ${#v2_parts[@]} -lt $max_parts ]]; do
        v2_parts+=("0")
    done

    # Compare each version component
    for ((i=0; i<max_parts; i++)); do
        local part1="${v1_parts[i]:-0}"
        local part2="${v2_parts[i]:-0}"

        # Convert to integers for comparison
        part1=$((10#$part1))
        part2=$((10#$part2))

        if [[ $part1 -gt $part2 ]]; then
            log_debug "Version comparison result: $version1 > $version2 (component $i: $part1 > $part2)"
            return 1
        elif [[ $part1 -lt $part2 ]]; then
            log_debug "Version comparison result: $version1 < $version2 (component $i: $part1 < $part2)"
            return 2
        fi
    done

    # All components are equal
    log_debug "Versions are equal after detailed comparison: $version1 = $version2"
    return 0
}

########################################################################
# Validate semantic version format                                     #
# Arguments:                                                           #
#   $1 - Version string to validate                                    #
# Returns:                                                             #
#   SUCCESS if valid format, PARAM_ERROR otherwise                     #
# Usage:                                                               #
#   if _is_valid_version_format "1.2.3"; then                          #
########################################################################
function _is_valid_version_format() {
    local version="$1"

    # Basic semantic version pattern: major.minor.patch with optional additional components
    local version_pattern="^[0-9]+(\.[0-9]+)*$"

    if [[ "$version" =~ $version_pattern ]]; then
        return $SUCCESS
    else
        return $PARAM_ERROR
    fi
}

################################################################################
# Check if version meets minimum requirement                                   #
# Arguments:                                                                   #
#   $1 - Current version                                                       #
#   $2 - Minimum required version                                              #
# Returns:                                                                     #
#   SUCCESS if current version meets requirement, GENERAL_ERROR otherwise      #
# Usage:                                                                       #
#   if meets_minimum_version "1.2.5" "1.2.3"; then                             #
################################################################################
function meets_minimum_version() {
    if ! validate_function_params "meets_minimum_version" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local current_version="$1"
    local minimum_version="$2"

    log_debug "Checking if $current_version meets minimum $minimum_version"

    compare_semantic_versions "$current_version" "$minimum_version"
    local result=$?

    case $result in
        0|1)  # Equal or greater
            log_debug "Version requirement met: $current_version >= $minimum_version"
            return $SUCCESS
            ;;
        2)    # Less than
            log_debug "Version requirement not met: $current_version < $minimum_version"
            return $GENERAL_ERROR
            ;;
        *)    # Error
            log_error "Version comparison failed"
            return $PARAM_ERROR
            ;;
    esac
}

# =============================================================================
# STRING MANIPULATION FUNCTIONS
# =============================================================================

################################################################################
# Safe string escaping for shell usage                                         #
# This replaces get_escaped_string() with improved functionality               #
# Arguments:                                                                   #
#   $1 - String to escape                                                      #
#   $2 - Escape type (shell, sed, regex) - default: shell                      #
# Returns:                                                                     #
#   SUCCESS and outputs escaped string, PARAM_ERROR on failure                 #
# Usage:                                                                       #
#   escaped=$(escape_string "user input with special chars")                   #
#   escaped=$(escape_string "regex pattern" "regex")                           #
################################################################################
function escape_string() {
    if ! validate_function_params "escape_string" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local input_string="${1:-}"
    local escape_type="${2:-shell}"

    log_debug "Escaping string for type: $escape_type"

    if [[ -z "$input_string" ]]; then
        echo ""
        return $SUCCESS
    fi

    case "$escape_type" in
        shell)
            # Escape for safe shell usage
            echo "$input_string" | sed -e 's/[^a-zA-Z0-9,._+@%/-]/\\&/g; 1{$s/^$/""/}; 1!s/^/"/; $!s/$/"/'
            ;;
        sed)
            # Escape for sed command usage
            echo "$input_string" | sed 's/[[\.*^$()+?{|]/\\&/g'
            ;;
        regex)
            # Escape for regex pattern usage
            echo "$input_string" | sed 's/[.*^$(){}?+|[\]\\]/\\&/g'
            ;;
        json)
            # Escape for JSON string usage
            echo "$input_string" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\//\\\//g; s/\x08/\\b/g; s/\x0c/\\f/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'
            ;;
        *)
            log_error "Unknown escape type: $escape_type"
            return $PARAM_ERROR
            ;;
    esac

    return $SUCCESS
}

################################################################################
# Extract substring safely with bounds checking                                #
# Arguments:                                                                   #
#   $1 - Source string                                                         #
#   $2 - Start position (0-based)                                              #
#   $3 - Length (optional, if not provided extracts to end)                    #
# Returns:                                                                     #
#   SUCCESS and outputs substring, PARAM_ERROR on invalid parameters           #
# Usage:                                                                       #
#   substring=$(extract_substring "hello world" 6 5)  # Returns "world"        #
#   substring=$(extract_substring "hello world" 6)    # Returns "world"        #
################################################################################
function extract_substring() {
    if ! validate_function_params "extract_substring" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local source_string="$1"
    local start_pos="$2"
    local length="${3:-}"

    log_debug "Extracting substring from position $start_pos"

    # Validate start position
    if [[ ! "$start_pos" =~ ^[0-9]+$ ]]; then
        log_error "Invalid start position: $start_pos"
        return $PARAM_ERROR
    fi

    # Validate length if provided
    if [[ -n "$length" ]] && [[ ! "$length" =~ ^[0-9]+$ ]]; then
        log_error "Invalid length: $length"
        return $PARAM_ERROR
    fi

    local string_length=${#source_string}

    # Check bounds
    if [[ $start_pos -ge $string_length ]]; then
        log_debug "Start position beyond string length, returning empty string"
        echo ""
        return $SUCCESS
    fi

    # Extract substring
    if [[ -n "$length" ]]; then
        echo "${source_string:$start_pos:$length}"
    else
        echo "${source_string:$start_pos}"
    fi

    return $SUCCESS
}

################################################################################
# Convert string to uppercase safely                                           #
# Arguments:                                                                   #
#   $1 - String to convert                                                     #
# Returns:                                                                     #
#   SUCCESS and outputs uppercase string                                       #
# Usage:                                                                       #
#   upper_string=$(to_uppercase "hello world")                                 #
################################################################################
function to_uppercase() {
    local input_string="${1:-}"

    if [[ -z "$input_string" ]]; then
        echo ""
        return $SUCCESS
    fi

    echo "${input_string^^}"
    return $SUCCESS
}

################################################################################
# Convert string to lowercase safely                                           #
# Arguments:                                                                   #
#   $1 - String to convert                                                     #
# Returns:                                                                     #
#   SUCCESS and outputs lowercase string                                       #
# Usage:                                                                       #
#   lower_string=$(to_lowercase "HELLO WORLD")                                 #
################################################################################
function to_lowercase() {
    local input_string="${1:-}"

    if [[ -z "$input_string" ]]; then
        echo ""
        return $SUCCESS
    fi

    echo "${input_string,,}"
    return $SUCCESS
}

################################################################################
# Trim whitespace from string                                                  #
# Arguments:                                                                   #
#   $1 - String to trim                                                        #
#   $2 - Trim type (both, left, right) - default: both                         #
# Returns:                                                                     #
#   SUCCESS and outputs trimmed string                                         #
# Usage:                                                                       #
#   trimmed=$(trim_whitespace "  hello world  ")                               #
#   trimmed=$(trim_whitespace "  hello world  " "left")                        #
################################################################################
function trim_whitespace() {
    local input_string="${1:-}"
    local trim_type="${2:-both}"

    if [[ -z "$input_string" ]]; then
        echo ""
        return $SUCCESS
    fi

    case "$trim_type" in
        both)
            echo "${input_string}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            ;;
        left)
            echo "${input_string}" | sed 's/^[[:space:]]*//'
            ;;
        right)
            echo "${input_string}" | sed 's/[[:space:]]*$//'
            ;;
        *)
            log_error "Invalid trim type: $trim_type"
            return $PARAM_ERROR
            ;;
    esac

    return $SUCCESS
}

# =============================================================================
# FILE OPERATION FUNCTIONS
# =============================================================================

################################################################################
# Safe file path validation and normalization                                  #
# Arguments:                                                                   #
#   $1 - File path to validate                                                 #
#   $2 - Path type (file, directory) - default: file                           #
# Returns:                                                                     #
#   SUCCESS and outputs normalized path, FILE_ERROR on invalid path            #
# Usage:                                                                       #
#   normalized_path=$(normalize_file_path "/path/to/../file.txt")              #
################################################################################
function normalize_file_path() {
    if ! validate_function_params "normalize_file_path" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local file_path="${1:-}"
    local path_type="${2:-file}"

    log_debug "Normalizing file path: $file_path (type: $path_type)"

    if [[ -z "$file_path" ]]; then
        log_error "Empty file path provided"
        return $FILE_ERROR
    fi

    # Basic path traversal protection
    if [[ "$file_path" =~ \.\./|/\.\. ]]; then
        log_warn "Path contains directory traversal sequences: $file_path"
    fi

    # Normalize path using realpath if available
    if command -v realpath >/dev/null 2>&1; then
        local normalized
        if normalized=$(realpath -m "$file_path" 2>/dev/null); then
            echo "$normalized"
            return $SUCCESS
        else
            log_error "Failed to normalize path: $file_path"
            return $FILE_ERROR
        fi
    else
        # Fallback normalization
        echo "$file_path" | sed 's|/\+|/|g; s|/\./|/|g; s|/$||'
        return $SUCCESS
    fi
}

################################################################################
# Create directory with proper error handling                                  #
# Arguments:                                                                   #
#   $1 - Directory path to create                                              #
#   $2 - Permissions (optional, default: 755)                                  #
#   $3 - Create parents (true/false, default: true)                            #
# Returns:                                                                     #
#   SUCCESS if directory created or exists, FILE_ERROR on failure              #
# Usage:                                                                       #
#   create_directory_safe "/path/to/dir"                                       #
#   create_directory_safe "/path/to/dir" "700" "false"                         #
################################################################################
function create_directory_safe() {
    if ! validate_function_params "create_directory_safe" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local dir_path="${1:-}"
    local permissions="${2:-755}"
    local create_parents="${3:-true}"

    log_debug "Creating directory: $dir_path (permissions: $permissions, parents: $create_parents)"

    # Validate permissions format
    if [[ ! "$permissions" =~ ^[0-7]{3}$ ]]; then
        log_error "Invalid permissions format: $permissions"
        return $PARAM_ERROR
    fi

    # Check if directory already exists
    if [[ -d "$dir_path" ]]; then
        log_debug "Directory already exists: $dir_path"
        return $SUCCESS
    fi

    # Create directory
    local mkdir_options="-m $permissions"
    if [[ "$create_parents" == "true" ]]; then
        mkdir_options="$mkdir_options -p"
    fi

    if mkdir $mkdir_options "$dir_path" 2>/dev/null; then
        log_info "Directory created successfully: $dir_path"
        return $SUCCESS
    else
        log_error "Failed to create directory: $dir_path"
        return $FILE_ERROR
    fi
}

# =============================================================================
# AZURE REGION AND CONFIGURATION FUNCTIONS
# =============================================================================

################################################################################
# Get Azure region code from region name                                       #
# This replaces get_region_code() with improved functionality                  #
# Arguments:                                                                   #
#   $1 - Azure region name (e.g., "East US", "westeurope")                     #
# Returns:                                                                     #
#   SUCCESS and outputs region code, PARAM_ERROR on invalid region             #
# Usage:                                                                       #
#   region_code=$(get_azure_region_code "East US")                             #
################################################################################
function get_azure_region_code() {
    if ! validate_function_params "get_azure_region_code" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local region_name="${1:-}"

    log_debug "Getting region code for: $region_name"

    # Normalize region name to lowercase
    region_name=$(to_lowercase "$region_name")

    # Define region mappings
    declare -A region_mappings=(
        ["australiacentral"]="AUCE"
        ["australiacentral2"]="AUC2"
        ["australiaeast"]="AUEA"
        ["australiasoutheast"]="AUSE"
        ["brazilsouth"]="BRSO"
        ["brazilsoutheast"]="BRSE"
        ["brazilus"]="BRUS"
        ["canadacentral"]="CACE"
        ["canadaeast"]="CAEA"
        ["centralindia"]="CEIN"
        ["centralus"]="CEUS"
        ["centraluseuap"]="CEUA"
        ["eastasia"]="EAAS"
        ["eastus"]="EAUS"
        ["eastus2"]="EUS2"
        ["eastus2euap"]="EUSA"
        ["eastusstg"]="EUSG"
        ["francecentral"]="FRCE"
        ["francesouth"]="FRSO"
        ["germanynorth"]="GENO"
        ["germanywestcentral"]="GEWC"
        ["israelcentral"]="ISCE"
        ["italynorth"]="ITNO"
        ["japaneast"]="JAEA"
        ["japanwest"]="JAWE"
        ["jioindiacentral"]="JINC"
        ["jioindiawest"]="JINW"
        ["koreacentral"]="KOCE"
        ["koreasouth"]="KOSO"
        ["northcentralus"]="NCUS"
        ["northeurope"]="NOEU"
        ["norwayeast"]="NOEA"
        ["norwaywest"]="NOW"
        ["newzealandnorth"]="NZNO"
        ["polandcentral"]="PLCE"
        ["qatarcentral"]="QACE"
        ["southafricanorth"]="SANO"
        ["southafricawest"]="SAWE"
        ["southcentralus"]="SCUS"
        ["southcentralusstg"]="SCUG"
        ["southeastasia"]="SOEA"
        ["southindia"]="SOIN"
        ["swedencentral"]="SECE"
        ["switzerlandnorth"]="SWNO"
        ["switzerlandwest"]="SWWE"
        ["uaecentral"]="UACE"
        ["uaenorth"]="UANO"
        ["uksouth"]="UKSO"
        ["ukwest"]="UKWE"
        ["westcentralus"]="WCUS"
        ["westeurope"]="WEEU"
        ["westindia"]="WEIN"
        ["westus"]="WEUS"
        ["westus2"]="WUS2"
        ["westus3"]="WUS3"
    )

    # Look up region code
    if [[ -n "${region_mappings[$region_name]:-}" ]]; then
        echo "${region_mappings[$region_name]}"
        log_debug "Region code found: $region_name -> ${region_mappings[$region_name]}"
        return $SUCCESS
    else
        log_error "Unknown Azure region: $region_name"
        return $PARAM_ERROR
    fi
}

# =============================================================================
# BACKWARD COMPATIBILITY FUNCTIONS
# =============================================================================

################################################################################
# Legacy version_compare function for backward compatibility                   #
################################################################################
function version_compare() {
    deprecation_warning "version_compare" "compare_semantic_versions"

    local version1="$1"
    local version2="$2"

    # Legacy behavior: echo comparison message and return result
    echo "Comparison: $version1 <= $version2"

    compare_semantic_versions "$version1" "$version2"
    return $?
}

################################################################################
# Legacy get_escaped_string function for backward compatibility                #
################################################################################
function get_escaped_string() {
    deprecation_warning "get_escaped_string" "escape_string"
    escape_string "$1" "shell"
    return $?
}

################################################################################
# Legacy get_region_code function for backward compatibility                   #
################################################################################
function get_region_code() {
    deprecation_warning "get_region_code" "get_azure_region_code"

    local region="$1"
    region_code=$(get_azure_region_code "$region")
    local result=$?

    # Set global variable for backward compatibility
    export region_code

    return $result
}

# =============================================================================
# UTILITY TESTING FUNCTIONS
# =============================================================================

################################################################################
# Test all utility functions with sample data                                  #
# This function can be used for validation after module loading                #
# Arguments: None                                                              #
# Returns: SUCCESS if all tests pass, GENERAL_ERROR otherwise                  #
# Usage: test_utility_functions                                                #
################################################################################
function test_utility_functions() {
    log_info "Running utility functions self-test"

    local test_failures=0

    # Test version comparison
    if compare_semantic_versions "1.2.3" "1.2.4"; then
        log_error "Version comparison test failed: 1.2.3 should be less than 1.2.4"
        ((test_failures++))
    fi

    # Test string escaping
    local escaped
    escaped=$(escape_string "test'string\"with'quotes")
    if [[ -z "$escaped" ]]; then
        log_error "String escaping test failed"
        ((test_failures++))
    fi

    # Test region code lookup
    local region_code
    region_code=$(get_azure_region_code "eastus")
    if [[ "$region_code" != "EUS" ]]; then
        log_error "Region code test failed: expected EUS, got $region_code"
        ((test_failures++))
    fi

    if [[ $test_failures -eq 0 ]]; then
        log_info "All utility function tests passed"
        return $SUCCESS
    else
        log_error "Utility function tests failed: $test_failures failures"
        return $GENERAL_ERROR
    fi
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

log_info "Utility functions module loaded successfully"
log_debug "Available functions: compare_semantic_versions, escape_string, normalize_file_path, get_azure_region_code"
log_debug "Backward compatibility functions available for legacy scripts"

# Run self-test if DEBUG is enabled
if [[ "${DEBUG:-false}" == "true" ]]; then
    test_utility_functions
fi
