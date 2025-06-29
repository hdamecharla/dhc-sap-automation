#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Performance Optimization Module - Monitoring and Optimization Tools
# This module provides performance monitoring, optimization, and benchmarking
# capabilities for the refactored SAP deployment automation framework

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
# PERFORMANCE CONFIGURATION
# =============================================================================

# Performance monitoring settings
declare -g PERF_MONITORING_ENABLED="${PERF_MONITORING_ENABLED:-true}"
declare -g PERF_LOG_FILE="${PERF_LOG_FILE:-/tmp/sdaf_performance.log}"
declare -g PERF_METRICS_FILE="${PERF_METRICS_FILE:-/tmp/sdaf_metrics.json}"
declare -g PERF_THRESHOLD_WARNING="${PERF_THRESHOLD_WARNING:-5.0}"
declare -g PERF_THRESHOLD_CRITICAL="${PERF_THRESHOLD_CRITICAL:-10.0}"

# Performance tracking arrays
declare -A FUNCTION_CALL_COUNTS
declare -A FUNCTION_EXECUTION_TIMES
declare -A FUNCTION_PERFORMANCE_HISTORY

# Optimization settings
declare -g ENABLE_FUNCTION_CACHING="${ENABLE_FUNCTION_CACHING:-true}"
declare -g CACHE_TTL_SECONDS="${CACHE_TTL_SECONDS:-300}"
declare -A FUNCTION_CACHE
declare -A CACHE_TIMESTAMPS

# =============================================================================
# PERFORMANCE MONITORING FUNCTIONS
# =============================================================================

############################################################################################
# Start performance monitoring for a function                                             #
# Arguments:                                                                              #
#   $1 - Function name                                                                   #
# Returns:                                                                                #
#   Always SUCCESS                                                                       #
# Usage:                                                                                  #
#   start_performance_monitoring "my_function"                                          #
############################################################################################
function start_performance_monitoring() {
    local function_name="${1:-unknown}"

    if [[ "$PERF_MONITORING_ENABLED" != "true" ]]; then
        return $SUCCESS
    fi

    # Record start time
    local start_time
    start_time=$(date +%s.%N)
    export "PERF_START_${function_name}=${start_time}"

    # Increment call count
    FUNCTION_CALL_COUNTS["$function_name"]=$((${FUNCTION_CALL_COUNTS["$function_name"]:-0} + 1))

    log_debug "Performance monitoring started for: $function_name"
    return $SUCCESS
}

############################################################################################
# Stop performance monitoring and record metrics                                          #
# Arguments:                                                                              #
#   $1 - Function name                                                                   #
#   $2 - Success/failure status (optional)                                              #
# Returns:                                                                                #
#   Always SUCCESS                                                                       #
# Usage:                                                                                  #
#   stop_performance_monitoring "my_function" "success"                                 #
############################################################################################
function stop_performance_monitoring() {
    local function_name="${1:-unknown}"
    local status="${2:-unknown}"

    if [[ "$PERF_MONITORING_ENABLED" != "true" ]]; then
        return $SUCCESS
    fi

    # Get start time
    local start_time_var="PERF_START_${function_name}"
    local start_time="${!start_time_var:-}"

    if [[ -z "$start_time" ]]; then
        log_warn "No start time found for function: $function_name"
        return $SUCCESS
    fi

    # Calculate execution time
    local end_time duration
    end_time=$(date +%s.%N)

    if command -v bc >/dev/null 2>&1; then
        duration=$(echo "$end_time - $start_time" | bc -l)
    else
        # Fallback calculation (less precise)
        duration=$(echo "$end_time $start_time" | awk '{print $1 - $2}')
    fi

    # Store metrics
    FUNCTION_EXECUTION_TIMES["$function_name"]="$duration"
    _update_performance_history "$function_name" "$duration" "$status"

    # Check performance thresholds
    _check_performance_thresholds "$function_name" "$duration"

    # Clean up start time variable
    unset "$start_time_var"

    log_debug "Performance monitoring stopped for: $function_name (${duration}s)"
    return $SUCCESS
}

############################################################################################
# Performance monitoring wrapper for functions                                            #
# Arguments:                                                                              #
#   $1 - Function name to monitor                                                        #
#   $@ - Arguments to pass to the function                                              #
# Returns:                                                                                #
#   Return code of the wrapped function                                                  #
# Usage:                                                                                  #
#   monitor_function_performance "validate_environment" "core"                          #
############################################################################################
function monitor_function_performance() {
    if ! validate_function_params "monitor_function_performance" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local function_name="${1:-}"
    shift

    # Start monitoring
    start_performance_monitoring "$function_name"

    # Execute function
    local result
    if "$function_name" "$@"; then
        result=$SUCCESS
        stop_performance_monitoring "$function_name" "success"
    else
        result=$?
        stop_performance_monitoring "$function_name" "failure"
    fi

    return $result
}

############################################################################################
# Get performance metrics for a function                                                  #
# Arguments:                                                                              #
#   $1 - Function name                                                                   #
#   $2 - Output format (json, text) - default: text                                     #
# Returns:                                                                                #
#   SUCCESS and outputs metrics, PARAM_ERROR if function not found                      #
# Usage:                                                                                  #
#   get_function_metrics "validate_environment" "json"                                  #
############################################################################################
function get_function_metrics() {
    if ! validate_function_params "get_function_metrics" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local function_name="${1:-}"
    local output_format="${2:-text}"

    # Check if we have metrics for this function
    if [[ -z "${FUNCTION_CALL_COUNTS[$function_name]:-}" ]]; then
        log_debug "No metrics available for function: $function_name"
        return $PARAM_ERROR
    fi

    local call_count="${FUNCTION_CALL_COUNTS[$function_name]}"
    local last_execution_time="${FUNCTION_EXECUTION_TIMES[$function_name]:-0}"
    local history="${FUNCTION_PERFORMANCE_HISTORY[$function_name]:-[]}"

    case "$output_format" in
        json)
            jq -n \
                --arg function_name "$function_name" \
                --argjson call_count "$call_count" \
                --arg last_execution_time "$last_execution_time" \
                --argjson history "$history" \
                '{
                    function_name: $function_name,
                    call_count: $call_count,
                    last_execution_time: $last_execution_time,
                    performance_history: $history
                }'
            ;;
        text)
            echo "Function: $function_name"
            echo "  Call Count: $call_count"
            echo "  Last Execution Time: ${last_execution_time}s"
            echo "  Performance History: $history"
            ;;
        *)
            log_error "Invalid output format: $output_format"
            return $PARAM_ERROR
            ;;
    esac

    return $SUCCESS
}

# =============================================================================
# PERFORMANCE OPTIMIZATION FUNCTIONS
# =============================================================================

############################################################################################
# Enable function result caching                                                          #
# Arguments:                                                                              #
#   $1 - Function name to cache                                                          #
#   $2 - Cache key (optional, derived from arguments if not provided)                   #
#   $3 - TTL in seconds (optional, uses global default)                                 #
# Returns:                                                                                #
#   Always SUCCESS                                                                       #
# Usage:                                                                                  #
#   enable_function_caching "expensive_function" "key_123" 600                          #
############################################################################################
function enable_function_caching() {
    local function_name="${1:-}"
    local cache_key="${2:-}"
    local ttl="${3:-$CACHE_TTL_SECONDS}"

    if [[ "$ENABLE_FUNCTION_CACHING" != "true" ]]; then
        log_debug "Function caching is disabled"
        return $SUCCESS
    fi

    if [[ -z "$function_name" ]]; then
        log_error "Function name required for caching"
        return $PARAM_ERROR
    fi

    # Generate cache key if not provided
    if [[ -z "$cache_key" ]]; then
        cache_key="${function_name}_$(echo "$*" | md5sum | cut -d' ' -f1 2>/dev/null || echo "default")"
    fi

    # Store caching configuration
    export "CACHE_ENABLED_${function_name}=true"
    export "CACHE_TTL_${function_name}=${ttl}"

    log_debug "Caching enabled for function: $function_name (TTL: ${ttl}s)"
    return $SUCCESS
}

############################################################################################
# Get cached function result if available and valid                                       #
# Arguments:                                                                              #
#   $1 - Cache key                                                                       #
# Returns:                                                                                #
#   SUCCESS and outputs cached result if available, GENERAL_ERROR if not cached         #
# Usage:                                                                                  #
#   if cached_result=$(get_cached_result "my_cache_key"); then                          #
############################################################################################
function get_cached_result() {
    local cache_key="${1:-}"

    if [[ "$ENABLE_FUNCTION_CACHING" != "true" || -z "$cache_key" ]]; then
        return $GENERAL_ERROR
    fi

    # Check if cached result exists
    if [[ -z "${FUNCTION_CACHE[$cache_key]:-}" ]]; then
        return $GENERAL_ERROR
    fi

    # Check if cache is still valid
    local cache_timestamp="${CACHE_TIMESTAMPS[$cache_key]:-0}"
    local current_time
    current_time=$(date +%s)
    local cache_age=$((current_time - cache_timestamp))

    if [[ $cache_age -gt $CACHE_TTL_SECONDS ]]; then
        # Cache expired, remove it
        unset FUNCTION_CACHE["$cache_key"]
        unset CACHE_TIMESTAMPS["$cache_key"]
        log_debug "Cache expired for key: $cache_key"
        return $GENERAL_ERROR
    fi

    # Return cached result
    echo "${FUNCTION_CACHE[$cache_key]}"
    log_debug "Cache hit for key: $cache_key"
    return $SUCCESS
}

############################################################################################
# Store function result in cache                                                          #
# Arguments:                                                                              #
#   $1 - Cache key                                                                       #
#   $2 - Result to cache                                                                 #
# Returns:                                                                                #
#   Always SUCCESS                                                                       #
# Usage:                                                                                  #
#   store_cached_result "my_cache_key" "expensive_computation_result"                   #
############################################################################################
function store_cached_result() {
    local cache_key="${1:-}"
    local result="${2:-}"

    if [[ "$ENABLE_FUNCTION_CACHING" != "true" || -z "$cache_key" ]]; then
        return $SUCCESS
    fi

    # Store result and timestamp
    FUNCTION_CACHE["$cache_key"]="$result"
    CACHE_TIMESTAMPS["$cache_key"]=$(date +%s)

    log_debug "Cached result for key: $cache_key"
    return $SUCCESS
}

############################################################################################
# Clear function cache                                                                    #
# Arguments:                                                                              #
#   $1 - Cache key pattern (optional, clears all if not provided)                       #
# Returns:                                                                                #
#   Always SUCCESS                                                                       #
# Usage:                                                                                  #
#   clear_function_cache "validate_*"                                                   #
#   clear_function_cache  # Clear all cache                                             #
############################################################################################
function clear_function_cache() {
    local pattern="${1:-*}"

    log_info "Clearing function cache with pattern: $pattern"

    local cleared_count=0

    for cache_key in "${!FUNCTION_CACHE[@]}"; do
        if [[ "$cache_key" == $pattern ]]; then
            unset FUNCTION_CACHE["$cache_key"]
            unset CACHE_TIMESTAMPS["$cache_key"]
            ((cleared_count++))
        fi
    done

    log_info "Cleared $cleared_count cache entries"
    return $SUCCESS
}

# =============================================================================
# PERFORMANCE ANALYSIS FUNCTIONS
# =============================================================================

############################################################################################
# Generate performance report                                                             #
# Arguments:                                                                              #
#   $1 - Output file (optional, outputs to stdout if not provided)                      #
#   $2 - Report format (json, html, text) - default: text                              #
# Returns:                                                                                #
#   SUCCESS if report generated, FILE_ERROR on failure                                  #
# Usage:                                                                                  #
#   generate_performance_report "/tmp/perf_report.html" "html"                          #
############################################################################################
function generate_performance_report() {
    local output_file="${1:-}"
    local report_format="${2:-text}"

    log_info "Generating performance report in format: $report_format"

    case "$report_format" in
        json)
            _generate_json_performance_report "$output_file"
            ;;
        html)
            _generate_html_performance_report "$output_file"
            ;;
        text)
            _generate_text_performance_report "$output_file"
            ;;
        *)
            log_error "Invalid report format: $report_format"
            return $PARAM_ERROR
            ;;
    esac

    return $SUCCESS
}

############################################################################################
# Identify performance bottlenecks                                                        #
# Arguments:                                                                              #
#   $1 - Analysis threshold in seconds (optional, default: 1.0)                         #
# Returns:                                                                                #
#   SUCCESS and outputs bottleneck analysis                                             #
# Usage:                                                                                  #
#   identify_performance_bottlenecks 2.0                                                #
############################################################################################
function identify_performance_bottlenecks() {
    local threshold="${1:-1.0}"

    log_info "Identifying performance bottlenecks (threshold: ${threshold}s)"

    local bottlenecks=()
    local total_slow_functions=0

    echo "🐌 Performance Bottleneck Analysis"
    echo "=================================="
    echo ""

    for function_name in "${!FUNCTION_EXECUTION_TIMES[@]}"; do
        local execution_time="${FUNCTION_EXECUTION_TIMES[$function_name]}"

        # Compare execution time with threshold
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$execution_time > $threshold" | bc -l) )); then
                bottlenecks+=("$function_name:$execution_time")
                ((total_slow_functions++))
            fi
        else
            # Fallback comparison for systems without bc
            local time_int=${execution_time%.*}
            local threshold_int=${threshold%.*}
            if [[ ${time_int:-0} -gt ${threshold_int:-1} ]]; then
                bottlenecks+=("$function_name:$execution_time")
                ((total_slow_functions++))
            fi
        fi
    done

    if [[ ${#bottlenecks[@]} -eq 0 ]]; then
        echo "✅ No performance bottlenecks detected above ${threshold}s threshold"
    else
        echo "⚠️  Found $total_slow_functions slow functions:"
        echo ""

        # Sort bottlenecks by execution time (descending)
        printf '%s\n' "${bottlenecks[@]}" | sort -t: -k2 -nr | while IFS=: read -r func_name exec_time; do
            local call_count="${FUNCTION_CALL_COUNTS[$func_name]:-1}"
            printf "   %-30s %8.3fs (%d calls)\n" "$func_name:" "$exec_time" "$call_count"
        done

        echo ""
        echo "Recommendations:"
        echo "- Consider optimizing the slowest functions"
        echo "- Enable function caching for expensive operations"
        echo "- Review algorithms and external dependencies"
        echo "- Consider parallel processing where applicable"
    fi

    echo ""
    return $SUCCESS
}

############################################################################################
# Benchmark function performance                                                          #
# Arguments:                                                                              #
#   $1 - Function name to benchmark                                                      #
#   $2 - Number of iterations (default: 10)                                             #
#   $@ - Arguments to pass to function                                                   #
# Returns:                                                                                #
#   SUCCESS and outputs benchmark results                                               #
# Usage:                                                                                  #
#   benchmark_function "validate_environment" 20 "core"                                 #
############################################################################################
function benchmark_function() {
    if ! validate_function_params "benchmark_function" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local function_name="${1:-}"
    local iterations="${2:-10}"
    shift 2

    log_info "Benchmarking function: $function_name ($iterations iterations)"

    # Validate that function exists
    if ! command -v "$function_name" >/dev/null 2>&1; then
        log_error "Function not found: $function_name"
        return $PARAM_ERROR
    fi

    # Validate iterations
    if [[ ! "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -lt 1 ]]; then
        log_error "Invalid iteration count: $iterations"
        return $PARAM_ERROR
    fi

    local execution_times=()
    local successful_runs=0
    local failed_runs=0

    echo "🏃 Benchmarking $function_name"
    echo "=============================="
    echo ""

    # Run benchmark iterations
    for ((i=1; i<=iterations; i++)); do
        local start_time end_time duration
        start_time=$(date +%s.%N)

        if "$function_name" "$@" >/dev/null 2>&1; then
            ((successful_runs++))
            end_time=$(date +%s.%N)

            if command -v bc >/dev/null 2>&1; then
                duration=$(echo "$end_time - $start_time" | bc -l)
            else
                duration=$(echo "$end_time $start_time" | awk '{print $1 - $2}')
            fi

            execution_times+=("$duration")
            printf "Iteration %2d: %8.3fs ✅\n" "$i" "$duration"
        else
            ((failed_runs++))
            printf "Iteration %2d: FAILED ❌\n" "$i"
        fi
    done

    echo ""

    # Calculate statistics
    if [[ $successful_runs -gt 0 ]]; then
        local total_time=0
        local min_time="${execution_times[0]}"
        local max_time="${execution_times[0]}"

        for time in "${execution_times[@]}"; do
            if command -v bc >/dev/null 2>&1; then
                total_time=$(echo "$total_time + $time" | bc -l)
                if (( $(echo "$time < $min_time" | bc -l) )); then
                    min_time="$time"
                fi
                if (( $(echo "$time > $max_time" | bc -l) )); then
                    max_time="$time"
                fi
            fi
        done

        local avg_time
        if command -v bc >/dev/null 2>&1; then
            avg_time=$(echo "scale=3; $total_time / $successful_runs" | bc -l)
        else
            avg_time="N/A"
        fi

        echo "📊 Benchmark Results:"
        echo "   Successful runs: $successful_runs/$iterations"
        echo "   Failed runs:     $failed_runs/$iterations"
        echo "   Average time:    ${avg_time}s"
        echo "   Minimum time:    ${min_time}s"
        echo "   Maximum time:    ${max_time}s"
        echo "   Total time:      ${total_time}s"
    else
        echo "❌ All benchmark iterations failed"
    fi

    echo ""
    return $SUCCESS
}

# =============================================================================
# INTERNAL HELPER FUNCTIONS
# =============================================================================

############################################################################################
# Update performance history for a function                                               #
############################################################################################
function _update_performance_history() {
    local function_name="$1"
    local duration="$2"
    local status="$3"

    # Create history entry
    local history_entry
    history_entry=$(jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg duration "$duration" \
        --arg status "$status" \
        '{
            timestamp: $timestamp,
            duration: ($duration | tonumber),
            status: $status
        }')

    # Update or create history array
    local current_history="${FUNCTION_PERFORMANCE_HISTORY[$function_name]:-[]}"
    local updated_history

    if command -v jq >/dev/null 2>&1; then
        updated_history=$(echo "$current_history" | jq ". + [$history_entry]")

        # Keep only last 100 entries
        updated_history=$(echo "$updated_history" | jq 'if length > 100 then .[-100:] else . end')

        FUNCTION_PERFORMANCE_HISTORY["$function_name"]="$updated_history"
    fi
}

############################################################################################
# Check performance thresholds and log warnings                                           #
############################################################################################
function _check_performance_thresholds() {
    local function_name="$1"
    local duration="$2"

    # Check against warning threshold
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$duration > $PERF_THRESHOLD_WARNING" | bc -l) )); then
            if (( $(echo "$duration > $PERF_THRESHOLD_CRITICAL" | bc -l) )); then
                log_error "CRITICAL: Function $function_name took ${duration}s (threshold: ${PERF_THRESHOLD_CRITICAL}s)"
            else
                log_warn "WARNING: Function $function_name took ${duration}s (threshold: ${PERF_THRESHOLD_WARNING}s)"
            fi
        fi
    fi
}

############################################################################################
# Generate JSON performance report                                                        #
############################################################################################
function _generate_json_performance_report() {
    local output_file="$1"

    local report
    report=$(jq -n \
        --argjson timestamp "$(date +%s)" \
        --argjson call_counts "$(declare -p FUNCTION_CALL_COUNTS | sed 's/^declare -A[^=]*=//' | jq -R 'split(" ") | map(select(length > 0)) | map(split("=")) | map({key: .[0], value: (.[1] | tonumber)}) | from_entries')" \
        --argjson execution_times "$(declare -p FUNCTION_EXECUTION_TIMES | sed 's/^declare -A[^=]*=//' | jq -R 'split(" ") | map(select(length > 0)) | map(split("=")) | map({key: .[0], value: (.[1] | tonumber)}) | from_entries')" \
        '{
            report_timestamp: ($timestamp | todateiso8601),
            summary: {
                total_functions_monitored: ($call_counts | length),
                performance_monitoring_enabled: env.PERF_MONITORING_ENABLED,
                function_caching_enabled: env.ENABLE_FUNCTION_CACHING
            },
            function_call_counts: $call_counts,
            function_execution_times: $execution_times
        }')

    if [[ -n "$output_file" ]]; then
        echo "$report" > "$output_file"
        log_info "JSON performance report saved to: $output_file"
    else
        echo "$report"
    fi
}

############################################################################################
# Generate HTML performance report                                                        #
############################################################################################
function _generate_html_performance_report() {
    local output_file="$1"
		local html_content
    html_content="<!DOCTYPE html>
<html>
<head>
    <title>SAP Deployment Automation Framework - Performance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .metric { background-color: #e6f3ff; padding: 15px; margin: 10px 0; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .slow { background-color: #fff3cd; }
        .critical { background-color: #f8d7da; }
    </style>
</head>
<body>
    <div class=\"header\">
        <h1>SAP Deployment Automation Framework</h1>
        <h2>Performance Report</h2>
        <p>Generated: $(date)</p>
    </div>

    <div class=\"metric\">
        <h3>Performance Summary</h3>
        <p>Functions Monitored: ${#FUNCTION_CALL_COUNTS[@]}</p>
        <p>Performance Monitoring: $PERF_MONITORING_ENABLED</p>
        <p>Function Caching: $ENABLE_FUNCTION_CACHING</p>
    </div>

    <h3>Function Performance Metrics</h3>
    <table>
        <tr>
            <th>Function Name</th>
            <th>Call Count</th>
            <th>Last Execution Time (s)</th>
            <th>Status</th>
        </tr>"

    for function_name in "${!FUNCTION_CALL_COUNTS[@]}"; do
        local call_count="${FUNCTION_CALL_COUNTS[$function_name]}"
        local execution_time="${FUNCTION_EXECUTION_TIMES[$function_name]:-0}"
        local status_class=""

        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$execution_time > $PERF_THRESHOLD_CRITICAL" | bc -l) )); then
                status_class="critical"
            elif (( $(echo "$execution_time > $PERF_THRESHOLD_WARNING" | bc -l) )); then
                status_class="slow"
            fi
        fi

        html_content+="
        <tr class=\"$status_class\">
            <td>$function_name</td>
            <td>$call_count</td>
            <td>$execution_time</td>
            <td>$([ -n "$status_class" ] && echo "Slow" || echo "Normal")</td>
        </tr>"
    done

    html_content+="
    </table>
</body>
</html>"

    if [[ -n "$output_file" ]]; then
        echo "$html_content" > "$output_file"
        log_info "HTML performance report saved to: $output_file"
    else
        echo "$html_content"
    fi
}

############################################################################################
# Generate text performance report                                                        #
############################################################################################
function _generate_text_performance_report() {
    local output_file="$1"

    local report_content
		report_content="SAP Deployment Automation Framework - Performance Report
================================================================
Generated: $(date)

Performance Summary:
  Functions Monitored: ${#FUNCTION_CALL_COUNTS[@]}
  Performance Monitoring: $PERF_MONITORING_ENABLED
  Function Caching: $ENABLE_FUNCTION_CACHING
  Warning Threshold: ${PERF_THRESHOLD_WARNING}s
  Critical Threshold: ${PERF_THRESHOLD_CRITICAL}s

Function Performance Metrics:
-----------------------------"

    if [[ ${#FUNCTION_CALL_COUNTS[@]} -gt 0 ]]; then
        printf "\n%-30s %10s %15s %10s\n" "Function Name" "Calls" "Last Time (s)" "Status"
        printf "%-30s %10s %15s %10s\n" "-------------" "-----" "-------------" "------"

        for function_name in "${!FUNCTION_CALL_COUNTS[@]}"; do
            local call_count="${FUNCTION_CALL_COUNTS[$function_name]}"
            local execution_time="${FUNCTION_EXECUTION_TIMES[$function_name]:-0}"
            local status="Normal"

            if command -v bc >/dev/null 2>&1; then
                if (( $(echo "$execution_time > $PERF_THRESHOLD_CRITICAL" | bc -l) )); then
                    status="CRITICAL"
                elif (( $(echo "$execution_time > $PERF_THRESHOLD_WARNING" | bc -l) )); then
                    status="SLOW"
                fi
            fi

            printf "%-30s %10d %15.3f %10s\n" "$function_name" "$call_count" "$execution_time" "$status"
        done
    else
        report_content+="\n\nNo performance metrics available."
    fi

    if [[ -n "$output_file" ]]; then
        echo "$report_content" > "$output_file"
        log_info "Text performance report saved to: $output_file"
    else
        echo "$report_content"
    fi
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Initialize performance logging
if [[ "$PERF_MONITORING_ENABLED" == "true" ]]; then
    log_info "Performance monitoring enabled"
    log_debug "Performance log file: $PERF_LOG_FILE"
    log_debug "Performance thresholds - Warning: ${PERF_THRESHOLD_WARNING}s, Critical: ${PERF_THRESHOLD_CRITICAL}s"
fi

if [[ "$ENABLE_FUNCTION_CACHING" == "true" ]]; then
    log_info "Function caching enabled (TTL: ${CACHE_TTL_SECONDS}s)"
fi

log_info "Performance optimization module loaded successfully"
log_debug "Available functions: monitor_function_performance, generate_performance_report, identify_performance_bottlenecks, benchmark_function"
