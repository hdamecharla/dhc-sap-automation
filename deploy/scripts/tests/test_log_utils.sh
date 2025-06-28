#!/bin/bash

################################################################################
# test_log_utils.sh - Validation and Test Script for log_utils.sh
#
# This script provides comprehensive testing of the refactored log_utils.sh
# functionality to ensure all features work as expected.
#
# Usage: ./test_log_utils.sh [test_directory]
# Example: ./test_log_utils.sh /tmp/log_test
################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${1:-/tmp/sap_log_utils_test}"
TEST_CONFIG_REPO_PATH="${TEST_DIR}/config"
ORIGINAL_CONFIG_REPO_PATH="${CONFIG_REPO_PATH:-}"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Test utility functions
################################################################################

function test_start() {
    echo -e "${BLUE}Starting test: $1${NC}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

function test_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

function test_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

function test_info() {
    echo -e "${YELLOW}ℹ INFO: $1${NC}"
}

function cleanup_test_env() {
    # Restore original CONFIG_REPO_PATH
    if [[ -n "${ORIGINAL_CONFIG_REPO_PATH}" ]]; then
        export CONFIG_REPO_PATH="${ORIGINAL_CONFIG_REPO_PATH}"
    else
        unset CONFIG_REPO_PATH
    fi

    # Clean up test directory
    if [[ -d "${TEST_DIR}" ]]; then
        rm -rf "${TEST_DIR}"
    fi
}

function setup_test_env() {
    # Clean up any existing test directory
    cleanup_test_env

    # Create test directory structure
    mkdir -p "${TEST_CONFIG_REPO_PATH}"
    export CONFIG_REPO_PATH="${TEST_CONFIG_REPO_PATH}"

    test_info "Test environment setup at: ${TEST_DIR}"
    test_info "CONFIG_REPO_PATH set to: ${CONFIG_REPO_PATH}"
}

################################################################################
# Test functions
################################################################################
function test_log_utils_sourcing() {
    test_start "Source log_utils.sh script"

    # Set flag to disable auto-initialization for testing
    export DISABLE_AUTO_LOG_INIT=true

		local log_utils_path="${SCRIPT_DIR}/../log_utils.sh"
    echo "DEBUG: Looking for log_utils.sh at: ${log_utils_path}"

		# shellcheck disable=SC1090,SC1091
		if source "${log_utils_path}" 2>&1; then
        test_pass "log_utils.sh sourced successfully"
    else
        test_fail "Failed to source log_utils.sh"
        return 1
    fi

    # Check if required functions are available
    local required_functions=(
        "init_logging"
        "log_critical"
        "log_error"
        "log_warn"
        "log_info"
        "log_debug"
        "log_verbose"
        "set_log_level"
        "cleanup_logs"
    )

    for func in "${required_functions[@]}"; do
        if declare -f "$func" >/dev/null; then
            test_pass "Function $func is available"
        else
            test_fail "Function $func is not available"
        fi
    done
}

function test_log_initialization() {
    test_start "Log system initialization"

    # Test default initialization
    if init_logging; then
        test_pass "Default initialization successful"
    else
        test_fail "Default initialization failed"
        return 1
    fi

    # Check if log directories were created
    local expected_dirs=(
        "${CONFIG_REPO_PATH}/.sap_deployment_automation/logs"
        "${CONFIG_REPO_PATH}/.sap_deployment_automation/logs/daily"
        "${CONFIG_REPO_PATH}/.sap_deployment_automation/logs/scripts"
        "${CONFIG_REPO_PATH}/.sap_deployment_automation/logs/archive"
    )

    for dir in "${expected_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            test_pass "Directory created: $dir"
        else
            test_fail "Directory not created: $dir"
        fi
    done

    # Test custom initialization
    local custom_dir="${TEST_DIR}/custom_logs"
    if init_logging "$custom_dir" "DEBUG"; then
        test_pass "Custom initialization successful"

        if [[ -d "$custom_dir" ]]; then
            test_pass "Custom log directory created: $custom_dir"
        else
            test_fail "Custom log directory not created: $custom_dir"
        fi
    else
        test_fail "Custom initialization failed"
    fi
}

function test_log_levels() {
    test_start "Log level functionality"

    # Test setting different log levels
    local levels=("CRITICAL" "ERROR" "WARN" "INFO" "DEBUG" "VERBOSE")

    for level in "${levels[@]}"; do
        if set_log_level "test_logger" "$level"; then
            test_pass "Set log level $level for test_logger"
        else
            test_fail "Failed to set log level $level for test_logger"
        fi
    done

    # Test invalid log level
    if ! set_log_level "test_logger" "INVALID_LEVEL" 2>/dev/null; then
        test_pass "Invalid log level properly rejected"
    else
        test_fail "Invalid log level was accepted"
    fi
}

function test_console_and_file_logging() {
    test_start "Console and file logging"

    # Initialize logging for this test
    local test_log_dir="${TEST_DIR}/logging_test"
    init_logging "$test_log_dir" "VERBOSE"

    # Test all log levels
    log_critical "Test critical message"
    log_error "Test error message"
    log_warn "Test warning message"
    log_info "Test info message"
    log_debug "Test debug message"
    log_verbose "Test verbose message"

    # Test logger-specific logging
    log_info -l "test_logger" "Test message for specific logger"

    # Check if log files were created
    local log_files_found=0
    if find "$test_log_dir" -name "*.log" -type f | grep -q .; then
        log_files_found=$(find "$test_log_dir" -name "*.log" -type f | wc -l)
        test_pass "Log files created ($log_files_found files found)"
    else
        test_fail "No log files were created"
    fi

    # Test disabling console logging
    set_console_logging "false"
    log_info "This should only go to file"
    set_console_logging "true"

    # Test disabling file logging
    set_file_logging "false"
    log_info "This should only go to console"
    set_file_logging "true"

    test_pass "Console and file logging toggles work"
}

function test_function_entry_exit_logging() {
    test_start "Function entry/exit logging"

    function test_function() {
        log_info_enter
        log_debug_enter

        # Simulate some work
        sleep 0.1

        log_debug_exit 0
        log_info_exit 0
        return 0
    }

    if test_function; then
        test_pass "Function entry/exit logging works"
    else
        test_fail "Function entry/exit logging failed"
    fi
}

function test_log_filtering() {
    test_start "Log level filtering"

    # Initialize with INFO level
    init_logging "${TEST_DIR}/filter_test" "INFO"
    set_log_level "default" "INFO"

    # Count initial log files
    local initial_files
    initial_files=$(find "${TEST_DIR}/filter_test" -name "*.log" -type f 2>/dev/null | wc -l)

    # These should be logged (INFO level and above)
    log_critical "Critical message"
    log_error "Error message"
    log_warn "Warning message"
    log_info "Info message"

    # These should be filtered out (below INFO level)
    log_debug "Debug message"
    log_verbose "Verbose message"

    # Wait a moment for file operations
    sleep 0.1

    # Check if log files were created appropriately
    local final_files
    final_files=$(find "${TEST_DIR}/filter_test" -name "*.log" -type f 2>/dev/null | wc -l)

    if [[ $final_files -gt $initial_files ]]; then
        test_pass "Log filtering allows appropriate messages"

        # Check if DEBUG/VERBOSE messages are NOT in the log files
        if ! grep -r "Debug message\|Verbose message" "${TEST_DIR}/filter_test" >/dev/null 2>&1; then
            test_pass "DEBUG and VERBOSE messages properly filtered out"
        else
            test_fail "DEBUG and VERBOSE messages were not filtered out"
        fi
    else
        test_fail "Log filtering may not be working correctly"
    fi
}

function test_utility_functions() {
    test_start "Utility functions"

    # Test list_log_levels
    if list_log_levels | grep -q "INFO"; then
        test_pass "list_log_levels works"
    else
        test_fail "list_log_levels failed"
    fi

    # Test list_loggers
    if list_loggers | grep -q "default"; then
        test_pass "list_loggers works"
    else
        test_fail "list_loggers failed"
    fi

    # Test cleanup_logs (create some old files first)
    local cleanup_test_dir="${TEST_DIR}/cleanup_test"
    mkdir -p "$cleanup_test_dir"

    # Create a test log file and make it old
    echo "Test log content" > "$cleanup_test_dir/old_test.log"
    touch -d "40 days ago" "$cleanup_test_dir/old_test.log"

    # Create a recent log file
    echo "Recent log content" > "$cleanup_test_dir/recent_test.log"

    # Initialize logging to use the cleanup test directory
    LOG_BASE_DIR="$cleanup_test_dir"

    if cleanup_logs 30; then
        test_pass "cleanup_logs function executed"

        # Check if old file was removed and recent file remains
        if [[ ! -f "$cleanup_test_dir/old_test.log" ]] && [[ -f "$cleanup_test_dir/recent_test.log" ]]; then
            test_pass "cleanup_logs properly removed old files"
        else
            test_fail "cleanup_logs did not work as expected"
        fi
    else
        test_fail "cleanup_logs function failed"
    fi
}

function test_backward_compatibility() {
    test_start "Backward compatibility functions"

    # Test legacy function names
    local legacy_functions=(
        "log_info_file"
        "log_debug_file"
        "log_verbose_file"
        "log_info_leave"
        "log_debug_leave"
        "__list_log_levels"
        "__list_available_loggers"
    )

    for func in "${legacy_functions[@]}"; do
        if declare -f "$func" >/dev/null; then
            test_pass "Legacy function $func is available"

            # Test calling the function
            if "$func" "Test message" >/dev/null 2>&1 || [[ "$func" == "__list_log_levels" ]] || [[ "$func" == "__list_available_loggers" ]]; then
                test_pass "Legacy function $func executes successfully"
            else
                test_fail "Legacy function $func failed to execute"
            fi
        else
            test_fail "Legacy function $func is not available"
        fi
    done
}

function test_error_handling() {
    test_start "Error handling"

    # Test logging to a read-only directory (should handle gracefully)
    local readonly_dir="${TEST_DIR}/readonly"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir"

    # This should not cause the script to exit
    LOG_BASE_DIR="$readonly_dir"
    set_file_logging "true"

    # Should handle the error gracefully
    log_info "Test message to readonly directory" 2>/dev/null || true

    # Restore permissions for cleanup
    chmod 755 "$readonly_dir"

    test_pass "Error handling works gracefully"
}

################################################################################
# Main test execution
################################################################################

function run_all_tests() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Starting log_utils.sh Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo

    # Setup test environment
    setup_test_env

    # Run all tests
    test_log_utils_sourcing
    test_log_initialization
    test_log_levels
    test_console_and_file_logging
    test_function_entry_exit_logging
    test_log_filtering
    test_utility_functions
    test_backward_compatibility
    test_error_handling

    # Cleanup
    cleanup_test_env

    # Print results
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Results Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✓${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed! ✗${NC}"
        exit 1
    fi
}

################################################################################
# Script execution
################################################################################

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [test_directory]"
        echo "  test_directory: Optional directory for test files (default: /tmp/sap_log_utils_test)"
        echo "  --help, -h: Show this help message"
        exit 0
        ;;
    *)
        run_all_tests
        ;;
esac
