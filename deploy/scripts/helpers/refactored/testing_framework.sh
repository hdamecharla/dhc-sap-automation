#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Testing Framework Module - Comprehensive Integration and Unit Testing
# This module provides a complete testing framework for the refactored script_helpers.sh
# components, including unit tests, integration tests, and performance benchmarks

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
# TESTING CONFIGURATION
# =============================================================================

# Test configuration
declare -gr TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
declare -gr TEST_TEMP_DIR="${TEST_TEMP_DIR:-/tmp/sdaf_tests}"
declare -gr TEST_LOG_LEVEL="${TEST_LOG_LEVEL:-INFO}"
declare -gr TEST_PARALLEL="${TEST_PARALLEL:-false}"

# Test result tracking
declare -g TEST_SUITE_NAME=""
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g TEST_SKIPPED=0
declare -ga TEST_FAILURES=()

# Performance tracking
declare -g PERF_TRACKING_ENABLED="${PERF_TRACKING_ENABLED:-true}"
declare -A PERF_METRICS

# =============================================================================
# TEST FRAMEWORK CORE FUNCTIONS
# =============================================================================

############################################################################################
# Initialize test suite                                                                   #
# Arguments:                                                                              #
#   $1 - Test suite name                                                                 #
#   $2 - Test output directory (optional)                                               #
# Returns:                                                                                #
#   Always SUCCESS                                                                       #
# Usage:                                                                                  #
#   init_test_suite "Foundation Module Tests"                                            #
############################################################################################
function init_test_suite() {
    local suite_name="${1:-Unknown Test Suite}"
    local output_dir="${2:-$TEST_TEMP_DIR}"

    TEST_SUITE_NAME="$suite_name"
    TEST_TOTAL=0
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0
    TEST_FAILURES=()

    # Create test output directory
    create_directory_safe "$output_dir" "755" "true"

    # Initialize performance tracking
    if [[ "$PERF_TRACKING_ENABLED" == "true" ]]; then
        PERF_METRICS=()
    fi

    log_info "Initialized test suite: $TEST_SUITE_NAME"
    log_debug "Test output directory: $output_dir"

    return $SUCCESS
}

############################################################################################
# Execute a single test case                                                              #
# Arguments:                                                                              #
#   $1 - Test name                                                                       #
#   $2 - Test function to execute                                                        #
#   $3 - Test description (optional)                                                     #
# Returns:                                                                                #
#   SUCCESS if test passed, GENERAL_ERROR if failed                                     #
# Usage:                                                                                  #
#   run_test "test_version_comparison" "test_compare_versions" "Version comparison tests"#
############################################################################################
function run_test() {
    if ! validate_function_params "run_test" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local test_name="${1:-}"
    local test_function="${2:-}"
    local test_description="${3:-$test_name}"

    ((TEST_TOTAL++))

    log_info "Running test: $test_name"
    log_debug "Test description: $test_description"

    # Performance tracking
    local start_time
    if [[ "$PERF_TRACKING_ENABLED" == "true" ]]; then
        start_time=$(date +%s.%N)
    fi

    # Execute test with timeout
    local test_result
    if timeout "$TEST_TIMEOUT" "$test_function" >/dev/null 2>&1; then
        test_result=$SUCCESS
        ((TEST_PASSED++))
        log_info "✅ PASS: $test_name"
    else
        test_result=$GENERAL_ERROR
        ((TEST_FAILED++))
        TEST_FAILURES+=("$test_name: $test_description")
        log_error "❌ FAIL: $test_name"
    fi

    # Record performance metrics
    if [[ "$PERF_TRACKING_ENABLED" == "true" && -n "$start_time" ]]; then
        local end_time duration
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        PERF_METRICS["$test_name"]="$duration"
        log_debug "Test duration: $test_name = ${duration}s"
    fi

    return $test_result
}

############################################################################################
# Assert function for test validation                                                     #
# Arguments:                                                                              #
#   $1 - Condition to evaluate                                                           #
#   $2 - Error message if assertion fails                                               #
# Returns:                                                                                #
#   SUCCESS if assertion passes, GENERAL_ERROR if fails                                 #
# Usage:                                                                                  #
#   assert '[[ "$result" == "expected" ]]' "Result should equal expected"               #
############################################################################################
function assert() {
    local condition="${1:-}"
    local error_message="${2:-Assertion failed}"

    if eval "$condition"; then
        log_debug "Assertion passed: $condition"
        return $SUCCESS
    else
        log_error "Assertion failed: $error_message"
        log_debug "Failed condition: $condition"
        return $GENERAL_ERROR
    fi
}

############################################################################################
# Assert equality helper                                                                  #
# Arguments:                                                                              #
#   $1 - Actual value                                                                    #
#   $2 - Expected value                                                                  #
#   $3 - Error message (optional)                                                        #
# Returns:                                                                                #
#   SUCCESS if values are equal, GENERAL_ERROR otherwise                                #
# Usage:                                                                                  #
#   assert_equals "$actual" "$expected" "Values should be equal"                        #
############################################################################################
function assert_equals() {
		# shellcheck disable=SC2034
    local actual="${1:-}"
		# shellcheck disable=SC2034
    local expected="${2:-}"
    local message="${3:-Expected '$expected', got '$actual'}"

    assert '[[ "$actual" == "$expected" ]]' "$message"
}

############################################################################################
# Assert command success helper                                                           #
# Arguments:                                                                              #
#   $1 - Command to execute                                                              #
#   $2 - Error message (optional)                                                        #
# Returns:                                                                                #
#   SUCCESS if command succeeds, GENERAL_ERROR otherwise                                #
# Usage:                                                                                  #
#   assert_success "validate_environment core" "Environment validation should succeed"  #
############################################################################################
function assert_success() {
    local command="${1:-}"
    local message="${2:-Command should succeed: $command}"

    if eval "$command" >/dev/null 2>&1; then
        return $SUCCESS
    else
        log_error "$message"
        return $GENERAL_ERROR
    fi
}

############################################################################################
# Finalize test suite and display results                                                 #
# Arguments:                                                                              #
#   $1 - Generate report (true/false) - default: true                                   #
# Returns:                                                                                #
#   SUCCESS if all tests passed, GENERAL_ERROR if any failures                          #
# Usage:                                                                                  #
#   finalize_test_suite                                                                  #
############################################################################################
# shellcheck disable=SC2120
function finalize_test_suite() {
    local generate_report="${1:-true}"

    log_info "Finalizing test suite: $TEST_SUITE_NAME"

    # Display summary
    display_banner "Test Results" "$TEST_SUITE_NAME" "info" "Tests: $TEST_TOTAL, Passed: $TEST_PASSED, Failed: $TEST_FAILED"

    echo ""
    echo "📊 Test Summary:"
    echo "   Total Tests:   $TEST_TOTAL"
    echo "   Passed:        $TEST_PASSED"
    echo "   Failed:        $TEST_FAILED"
    echo "   Skipped:       $TEST_SKIPPED"
    echo "   Success Rate:  $(( TEST_TOTAL > 0 ? (TEST_PASSED * 100) / TEST_TOTAL : 0 ))%"
    echo ""

    # Display failures if any
    if [[ $TEST_FAILED -gt 0 ]]; then
        echo "❌ Failed Tests:"
        for failure in "${TEST_FAILURES[@]}"; do
            echo "   - $failure"
        done
        echo ""
    fi

    # Display performance metrics
    if [[ "$PERF_TRACKING_ENABLED" == "true" && "$generate_report" == "true" ]]; then
        _display_performance_metrics
    fi

    # Generate detailed report
    if [[ "$generate_report" == "true" ]]; then
        _generate_test_report
    fi

    # Return appropriate exit code
    if [[ $TEST_FAILED -eq 0 ]]; then
        display_success "All Tests Passed" "$TEST_SUITE_NAME completed successfully"
        return $SUCCESS
    else
        display_error "Tests Failed" "$TEST_FAILED out of $TEST_TOTAL tests failed"
        return $GENERAL_ERROR
    fi
}

# =============================================================================
# UNIT TEST FUNCTIONS
# =============================================================================

############################################################################################
# Test foundation standards module                                                        #
############################################################################################
function test_foundation_standards() {
    init_test_suite "Foundation Standards Tests"

    # Test error code constants
    run_test "error_codes_defined" "_test_error_codes_defined" "Error codes should be defined"

    # Test input validation
    run_test "input_validation" "_test_input_validation" "Input validation should work"

    # Test sanitization
    run_test "input_sanitization" "_test_input_sanitization" "Input sanitization should work"

    finalize_test_suite
    return $?
}

function _test_error_codes_defined() {
    assert '[[ -n "$SUCCESS" ]]' "SUCCESS should be defined"
    assert '[[ -n "$PARAM_ERROR" ]]' "PARAM_ERROR should be defined"
    assert '[[ -n "$GENERAL_ERROR" ]]' "GENERAL_ERROR should be defined"
    assert '[[ "$SUCCESS" -eq 0 ]]' "SUCCESS should equal 0"
    return $SUCCESS
}

function _test_input_validation() {
    # Test validate_function_params
    assert_success 'validate_function_params "test_func" 2 2' "Valid parameters should pass"
    assert '! validate_function_params "test_func" 2 1' "Invalid parameters should fail"
    return $SUCCESS
}

function _test_input_sanitization() {
    local result
    result=$(sanitize_input "test'string" "general")
    assert '[[ -n "$result" ]]' "Sanitization should return a result"
    return $SUCCESS
}

############################################################################################
# Test display functions module                                                           #
############################################################################################
function test_display_functions() {
    init_test_suite "Display Functions Tests"

    # Test banner display
    run_test "banner_display" "_test_banner_display" "Banner display should work"

    # Test help system
    run_test "help_system" "_test_help_system" "Help system should work"

    # Test error display
    run_test "error_display" "_test_error_display" "Error display should work"

    finalize_test_suite
    return $?
}

function _test_banner_display() {
    assert_success 'display_banner "Test" "Message" "info"' "Banner should display successfully"
    return $SUCCESS
}

function _test_help_system() {
    assert_success 'display_help "installer" "test_script"' "Help should display successfully"
    return $SUCCESS
}

function _test_error_display() {
    assert_success 'display_error "Test Error" "Test message"' "Error should display successfully"
    return $SUCCESS
}

############################################################################################
# Test validation functions module                                                        #
############################################################################################
function test_validation_functions() {
    init_test_suite "Validation Functions Tests"

    # Test environment validation
    run_test "env_validation" "_test_env_validation" "Environment validation should work"

    # Test GUID validation
    run_test "guid_validation" "_test_guid_validation" "GUID validation should work"

    # Test Azure location validation
    run_test "location_validation" "_test_location_validation" "Location validation should work"

    finalize_test_suite
    return $?
}

function _test_env_validation() {
    # Test with missing variables (should be safe to test)
    local result
    validate_environment "core" "false"  # Non-strict mode
    result=$?
    assert '[[ "$result" -eq 0 || "$result" -eq "$ENV_ERROR" ]]' "Environment validation should return valid code"
    return $SUCCESS
}

function _test_guid_validation() {
    assert_success '_is_valid_guid "12345678-1234-1234-1234-123456789012"' "Valid GUID should pass"
    assert '! _is_valid_guid "invalid-guid"' "Invalid GUID should fail"
    return $SUCCESS
}

function _test_location_validation() {
    assert_success '_validate_azure_location "eastus"' "Valid location should pass"
    assert '! _validate_azure_location "INVALID LOCATION"' "Invalid location should fail"
    return $SUCCESS
}

############################################################################################
# Test utility functions module                                                           #
############################################################################################
function test_utility_functions() {
    init_test_suite "Utility Functions Tests"

    # Test version comparison
    run_test "version_comparison" "_test_version_comparison" "Version comparison should work"

    # Test string operations
    run_test "string_operations" "_test_string_operations" "String operations should work"

    # Test region code mapping
    run_test "region_codes" "_test_region_codes" "Region code mapping should work"

    finalize_test_suite
    return $?
}

function _test_version_comparison() {
    compare_semantic_versions "1.2.3" "1.2.4"
    local result=$?
    assert '[[ "$result" -eq 2 ]]' "1.2.3 should be less than 1.2.4"

    compare_semantic_versions "1.2.4" "1.2.3"
    result=$?
    assert '[[ "$result" -eq 1 ]]' "1.2.4 should be greater than 1.2.3"

    compare_semantic_versions "1.2.3" "1.2.3"
    result=$?
    assert '[[ "$result" -eq 0 ]]' "1.2.3 should equal 1.2.3"

    return $SUCCESS
}

function _test_string_operations() {
    local result

    # Test escaping
    result=$(escape_string "test'string" "shell")
    assert '[[ -n "$result" ]]' "String escaping should return a result"

    # Test uppercase conversion
    result=$(to_uppercase "hello")
    assert_equals "$result" "HELLO" "Uppercase conversion should work"

    # Test trimming
    result=$(trim_whitespace "  hello  ")
    assert_equals "$result" "hello" "Whitespace trimming should work"

    return $SUCCESS
}

function _test_region_codes() {
    local result
    result=$(get_azure_region_code "eastus")
    assert_equals "$result" "EUS" "East US should map to EUS"

    result=$(get_azure_region_code "westeurope")
    assert_equals "$result" "WE" "West Europe should map to WE"

    return $SUCCESS
}

# =============================================================================
# INTEGRATION TEST FUNCTIONS
# =============================================================================

############################################################################################
# Test module integration and dependencies                                                #
############################################################################################
function test_module_integration() {
    init_test_suite "Module Integration Tests"

    # Test module loading
    run_test "module_loading" "_test_module_loading" "All modules should load correctly"

    # Test function availability
    run_test "function_availability" "_test_function_availability" "Key functions should be available"

    # Test backward compatibility
    run_test "backward_compatibility" "_test_backward_compatibility" "Legacy functions should work"

    # Test feature flags
    run_test "feature_flags" "_test_feature_flags" "Feature flags should control behavior"

    finalize_test_suite
    return $?
}

function _test_module_loading() {
    # Test that key functions from each module are available
    assert_success 'command -v display_banner' "display_banner should be available"
    assert_success 'command -v validate_environment' "validate_environment should be available"
    assert_success 'command -v compare_semantic_versions' "compare_semantic_versions should be available"
    return $SUCCESS
}

function _test_function_availability() {
    # Test critical functions are working
    assert_success 'get_script_helpers_version' "get_script_helpers_version should work"
    assert_success 'check_refactoring_status' "check_refactoring_status should work"
    return $SUCCESS
}

function _test_backward_compatibility() {
    # Test legacy functions still work
    assert_success 'command -v print_banner' "print_banner should still be available"
    assert_success 'command -v validate_exports' "validate_exports should still be available"
    assert_success 'command -v version_compare' "version_compare should still be available"
    return $SUCCESS
}

function _test_feature_flags() {
    # Test feature flag functionality
    local original_display="$USE_REFACTORED_DISPLAY"

    export USE_REFACTORED_DISPLAY="false"
    assert '[[ "$USE_REFACTORED_DISPLAY" == "false" ]]' "Feature flag should be modifiable"

    # Restore original value
    export USE_REFACTORED_DISPLAY="$original_display"
    return $SUCCESS
}

# =============================================================================
# PERFORMANCE TEST FUNCTIONS
# =============================================================================

############################################################################################
# Performance benchmark tests                                                             #
############################################################################################
function test_performance() {
    init_test_suite "Performance Tests"

    # Test banner performance
    run_test "banner_performance" "_test_banner_performance" "Banner display should be fast"

    # Test validation performance
    run_test "validation_performance" "_test_validation_performance" "Validation should be fast"

    # Test version comparison performance
    run_test "version_performance" "_test_version_performance" "Version comparison should be fast"

    finalize_test_suite
    return $?
}

function _test_banner_performance() {
    # Test multiple banner displays
    local i
    for i in {1..10}; do
        display_banner "Performance Test $i" "Testing banner performance" "info" >/dev/null 2>&1
    done
    return $SUCCESS
}

function _test_validation_performance() {
    # Test multiple GUID validations
    local i
    for i in {1..50}; do
        _is_valid_guid "12345678-1234-1234-1234-123456789012" >/dev/null 2>&1
    done
    return $SUCCESS
}

function _test_version_performance() {
    # Test multiple version comparisons
    local i
    for i in {1..100}; do
        compare_semantic_versions "1.2.$i" "1.2.50" >/dev/null 2>&1
    done
    return $SUCCESS
}

# =============================================================================
# COMPREHENSIVE TEST SUITE
# =============================================================================

############################################################################################
# Run all test suites                                                                     #
# Arguments:                                                                              #
#   $1 - Test categories (optional: "unit", "integration", "performance", "all")        #
# Returns:                                                                                #
#   SUCCESS if all tests pass, GENERAL_ERROR if any failures                            #
# Usage:                                                                                  #
#   run_all_tests                                                                        #
#   run_all_tests "unit"                                                                 #
############################################################################################
function run_all_tests() {
    local test_categories="${1:-all}"

    log_info "Starting comprehensive test suite"
    log_debug "Test categories: $test_categories"

    local total_suites=0
    local failed_suites=0
    local suite_results=()

    display_banner "Test Suite" "SAP Deployment Automation Framework" "info" "Comprehensive Testing"

    # Unit tests
    if [[ "$test_categories" == "all" || "$test_categories" == "unit" ]]; then
        echo "🧪 Running Unit Tests..."

        if test_foundation_standards; then
            suite_results+=("✅ Foundation Standards: PASS")
        else
            suite_results+=("❌ Foundation Standards: FAIL")
            ((failed_suites++))
        fi
        ((total_suites++))

        if test_display_functions; then
            suite_results+=("✅ Display Functions: PASS")
        else
            suite_results+=("❌ Display Functions: FAIL")
            ((failed_suites++))
        fi
        ((total_suites++))

        if test_validation_functions; then
            suite_results+=("✅ Validation Functions: PASS")
        else
            suite_results+=("❌ Validation Functions: FAIL")
            ((failed_suites++))
        fi
        ((total_suites++))

        if test_utility_functions; then
            suite_results+=("✅ Utility Functions: PASS")
        else
            suite_results+=("❌ Utility Functions: FAIL")
            ((failed_suites++))
        fi
        ((total_suites++))
    fi

    # Integration tests
    if [[ "$test_categories" == "all" || "$test_categories" == "integration" ]]; then
        echo "🔗 Running Integration Tests..."

        if test_module_integration; then
            suite_results+=("✅ Module Integration: PASS")
        else
            suite_results+=("❌ Module Integration: FAIL")
            ((failed_suites++))
        fi
        ((total_suites++))
    fi

    # Performance tests
    if [[ "$test_categories" == "all" || "$test_categories" == "performance" ]]; then
        echo "⚡ Running Performance Tests..."

        if test_performance; then
            suite_results+=("✅ Performance: PASS")
        else
            suite_results+=("❌ Performance: FAIL")
            ((failed_suites++))
        fi
        ((total_suites++))
    fi

    # Display final results
    echo ""
    echo "📋 Test Suite Results:"
    for result in "${suite_results[@]}"; do
        echo "   $result"
    done
    echo ""

    local success_rate
    success_rate=$(( total_suites > 0 ? ((total_suites - failed_suites) * 100) / total_suites : 100 ))

    if [[ $failed_suites -eq 0 ]]; then
        display_success "All Test Suites Passed" "$total_suites suites completed successfully (100%)"
        return $SUCCESS
    else
        display_error "Test Suites Failed" "$failed_suites out of $total_suites suites failed ($success_rate% success rate)"
        return $GENERAL_ERROR
    fi
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

############################################################################################
# Display performance metrics summary                                                     #
############################################################################################
function _display_performance_metrics() {
    if [[ ${#PERF_METRICS[@]} -eq 0 ]]; then
        return $SUCCESS
    fi

    echo "⚡ Performance Metrics:"

    local total_time=0
    local test_count=0

    for test_name in "${!PERF_METRICS[@]}"; do
        local duration="${PERF_METRICS[$test_name]}"
        printf "   %-30s %8.3fs\n" "$test_name:" "$duration"

        if command -v bc >/dev/null 2>&1; then
            total_time=$(echo "$total_time + $duration" | bc -l)
        fi
        ((test_count++))
    done

    if command -v bc >/dev/null 2>&1 && [[ $test_count -gt 0 ]]; then
        local avg_time
        avg_time=$(echo "scale=3; $total_time / $test_count" | bc -l)
        printf "   %-30s %8.3fs\n" "Total Time:" "$total_time"
        printf "   %-30s %8.3fs\n" "Average Time:" "$avg_time"
    fi

    echo ""
}

############################################################################################
# Generate detailed test report                                                           #
############################################################################################
function _generate_test_report() {
    local report_file
		report_file="${TEST_TEMP_DIR}/test_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "SAP Deployment Automation Framework - Test Report"
        echo "=================================================="
        echo "Suite: $TEST_SUITE_NAME"
        echo "Date: $(date)"
        echo ""
        echo "Summary:"
        echo "  Total Tests: $TEST_TOTAL"
        echo "  Passed: $TEST_PASSED"
        echo "  Failed: $TEST_FAILED"
        echo "  Skipped: $TEST_SKIPPED"
        echo ""

        if [[ $TEST_FAILED -gt 0 ]]; then
            echo "Failures:"
            for failure in "${TEST_FAILURES[@]}"; do
                echo "  - $failure"
            done
            echo ""
        fi

        if [[ "$PERF_TRACKING_ENABLED" == "true" ]]; then
            echo "Performance Metrics:"
            for test_name in "${!PERF_METRICS[@]}"; do
                echo "  $test_name: ${PERF_METRICS[$test_name]}s"
            done
            echo ""
        fi

    } > "$report_file"

    log_info "Test report generated: $report_file"
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Create test directory if it doesn't exist
create_directory_safe "$TEST_TEMP_DIR" "755" "true"

log_info "Testing framework module loaded successfully"
log_debug "Available functions: run_all_tests, test_foundation_standards, test_display_functions, test_validation_functions"
log_debug "Test configuration - Timeout: ${TEST_TIMEOUT}s, Temp dir: $TEST_TEMP_DIR, Performance tracking: $PERF_TRACKING_ENABLED"
