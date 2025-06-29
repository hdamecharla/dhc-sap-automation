#!/bin/bash

# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Monitoring and Alerting Integration Module - External System Integration
# This module provides integration with external monitoring and alerting systems
# for the SAP deployment automation framework, including metrics collection,
# alerting, and operational insights

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
# MONITORING CONFIGURATION
# =============================================================================

# Monitoring system types
declare -gr MONITOR_TYPE_AZURE="${MONITOR_TYPE_AZURE:-azure_monitor}"
declare -gr MONITOR_TYPE_PROMETHEUS="${MONITOR_TYPE_PROMETHEUS:-prometheus}"
declare -gr MONITOR_TYPE_SPLUNK="${MONITOR_TYPE_SPLUNK:-splunk}"
declare -gr MONITOR_TYPE_ELASTIC="${MONITOR_TYPE_ELASTIC:-elasticsearch}"
declare -gr MONITOR_TYPE_WEBHOOK="${MONITOR_TYPE_WEBHOOK:-webhook}"

# Configuration
declare -g MONITORING_ENABLED="${MONITORING_ENABLED:-true}"
declare -g MONITORING_ENDPOINT="${MONITORING_ENDPOINT:-}"
declare -g MONITORING_TYPE="${MONITORING_TYPE:-azure_monitor}"
declare -g MONITORING_API_KEY="${MONITORING_API_KEY:-}"
declare -g MONITORING_WORKSPACE_ID="${MONITORING_WORKSPACE_ID:-}"

# Alert levels
declare -gr ALERT_LEVEL_INFO="info"
declare -gr ALERT_LEVEL_WARNING="warning"
declare -gr ALERT_LEVEL_ERROR="error"
declare -gr ALERT_LEVEL_CRITICAL="critical"

# Metric categories
# shellcheck disable=SC2034
declare -ga METRIC_CATEGORIES=(
    "deployment"
    "performance"
    "security"
    "compliance"
    "cost"
)

# =============================================================================
# METRICS COLLECTION FUNCTIONS
# =============================================================================

############################################################################################
# Send metric to monitoring system                                                        #
# Arguments:                                                                              #
#   $1 - Metric name                                                                     #
#   $2 - Metric value                                                                    #
#   $3 - Metric type (counter, gauge, histogram) - default: gauge                       #
#   $4 - Tags (comma-separated key=value pairs)                                         #
#   $5 - Timestamp (optional, current time if not provided)                             #
# Returns:                                                                                #
#   SUCCESS if metric sent, NETWORK_ERROR on failure                                    #
# Usage:                                                                                  #
#   send_metric "deployment.duration" "120.5" "histogram" "env=prod,region=eastus"      #
############################################################################################
function send_metric() {
    if ! validate_function_params "send_metric" 2 "$#"; then
        return $PARAM_ERROR
    fi

    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        log_debug "Monitoring disabled, skipping metric: $1"
        return $SUCCESS
    fi

    local metric_name="${1:-}"
    local metric_value="${2:-}"
    local metric_type="${3:-gauge}"
    local tags="${4:-}"
    local timestamp="${5:-$(date +%s)}"

    log_debug "Sending metric: $metric_name = $metric_value ($metric_type)"

    # Validate metric name
    if ! _validate_metric_name "$metric_name"; then
        log_error "Invalid metric name: $metric_name"
        return $PARAM_ERROR
    fi

    # Validate metric value
    if ! _validate_metric_value "$metric_value"; then
        log_error "Invalid metric value: $metric_value"
        return $PARAM_ERROR
    fi

    # Route to appropriate monitoring system
    case "$MONITORING_TYPE" in
        "$MONITOR_TYPE_AZURE")
            _send_metric_azure_monitor "$metric_name" "$metric_value" "$metric_type" "$tags" "$timestamp"
            ;;
        "$MONITOR_TYPE_PROMETHEUS")
            _send_metric_prometheus "$metric_name" "$metric_value" "$metric_type" "$tags" "$timestamp"
            ;;
        "$MONITOR_TYPE_SPLUNK")
            _send_metric_splunk "$metric_name" "$metric_value" "$metric_type" "$tags" "$timestamp"
            ;;
        "$MONITOR_TYPE_WEBHOOK")
            _send_metric_webhook "$metric_name" "$metric_value" "$metric_type" "$tags" "$timestamp"
            ;;
        *)
            log_error "Unsupported monitoring type: $MONITORING_TYPE"
            return $PARAM_ERROR
            ;;
    esac

    return $?
}

############################################################################################
# Send deployment event to monitoring system                                              #
# Arguments:                                                                              #
#   $1 - Event type (start, success, failure, progress)                                 #
#   $2 - Deployment name                                                                 #
#   $3 - Environment                                                                     #
#   $4 - Additional metadata (JSON string, optional)                                    #
# Returns:                                                                                #
#   SUCCESS if event sent, NETWORK_ERROR on failure                                     #
# Usage:                                                                                  #
#   send_deployment_event "start" "sap-prod-deployment" "production"                    #
#   send_deployment_event "failure" "sap-dev" "dev" '{"error":"timeout"}'               #
############################################################################################
function send_deployment_event() {
    if ! validate_function_params "send_deployment_event" 3 "$#"; then
        return $PARAM_ERROR
    fi

    local event_type="${1:-}"
    local deployment_name="${2:-}"
    local environment="${3:-}"
    local metadata="${4:-{}}"

    log_info "Sending deployment event: $event_type for $deployment_name ($environment)"

    # Create deployment event structure
    local event_data
    event_data=$(jq -n \
        --arg event_type "$event_type" \
        --arg deployment_name "$deployment_name" \
        --arg environment "$environment" \
        --arg timestamp "$(date -Iseconds)" \
        --arg hostname "$(hostname)" \
        --arg user "${USER:-unknown}" \
        --argjson metadata "$metadata" \
        '{
            event_type: $event_type,
            deployment_name: $deployment_name,
            environment: $environment,
            timestamp: $timestamp,
            source: {
                hostname: $hostname,
                user: $user,
                framework: "SAP Deployment Automation"
            },
            metadata: $metadata
        }')

    # Send as structured event
    _send_structured_event "deployment" "$event_data"
    return $?
}

############################################################################################
# Send alert to monitoring system                                                         #
# Arguments:                                                                              #
#   $1 - Alert level (info, warning, error, critical)                                   #
#   $2 - Alert title                                                                     #
#   $3 - Alert message                                                                   #
#   $4 - Alert source (optional)                                                        #
#   $5 - Additional context (JSON string, optional)                                     #
# Returns:                                                                                #
#   SUCCESS if alert sent, NETWORK_ERROR on failure                                     #
# Usage:                                                                                  #
#   send_alert "critical" "Deployment Failed" "SAP production deployment timeout"       #
#   send_alert "warning" "Performance Issue" "High response time" "terraform"           #
############################################################################################
function send_alert() {
    if ! validate_function_params "send_alert" 3 "$#"; then
        return $PARAM_ERROR
    fi

    local alert_level="${1:-}"
    local alert_title="${2:-}"
    local alert_message="${3:-}"
    local alert_source="${4:-sdaf}"
    local context="${5:-{}}"

    log_info "Sending $alert_level alert: $alert_title"

    # Validate alert level
    case "$alert_level" in
        "$ALERT_LEVEL_INFO"|"$ALERT_LEVEL_WARNING"|"$ALERT_LEVEL_ERROR"|"$ALERT_LEVEL_CRITICAL")
            ;;
        *)
            log_error "Invalid alert level: $alert_level"
            return $PARAM_ERROR
            ;;
    esac

    # Create alert structure
    local alert_data
    alert_data=$(jq -n \
        --arg alert_level "$alert_level" \
        --arg alert_title "$alert_title" \
        --arg alert_message "$alert_message" \
        --arg alert_source "$alert_source" \
        --arg timestamp "$(date -Iseconds)" \
        --arg hostname "$(hostname)" \
        --argjson context "$context" \
        '{
            level: $alert_level,
            title: $alert_title,
            message: $alert_message,
            source: $alert_source,
            timestamp: $timestamp,
            hostname: $hostname,
            context: $context
        }')

    # Send alert
    _send_structured_event "alert" "$alert_data"

    # Also log locally
    case "$alert_level" in
        "$ALERT_LEVEL_CRITICAL"|"$ALERT_LEVEL_ERROR")
            log_error "ALERT [$alert_level]: $alert_title - $alert_message"
            ;;
        "$ALERT_LEVEL_WARNING")
            log_warn "ALERT [$alert_level]: $alert_title - $alert_message"
            ;;
        *)
            log_info "ALERT [$alert_level]: $alert_title - $alert_message"
            ;;
    esac

    return $?
}

# =============================================================================
# HEALTH MONITORING FUNCTIONS
# =============================================================================

############################################################################################
# Send health check status                                                                #
# Arguments:                                                                              #
#   $1 - Component name                                                                  #
#   $2 - Health status (healthy, degraded, unhealthy)                                   #
#   $3 - Response time in milliseconds (optional)                                       #
#   $4 - Additional details (optional)                                                   #
# Returns:                                                                                #
#   SUCCESS if health status sent                                                       #
# Usage:                                                                                  #
#   send_health_status "terraform" "healthy" "1250"                                     #
#   send_health_status "azure_auth" "degraded" "5000" "Slow authentication"             #
############################################################################################
function send_health_status() {
    if ! validate_function_params "send_health_status" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local component="${1:-}"
    local status="${2:-}"
    local response_time="${3:-}"
    local details="${4:-}"

    log_debug "Sending health status: $component = $status"

    # Validate health status
    case "$status" in
        "healthy"|"degraded"|"unhealthy")
            ;;
        *)
            log_error "Invalid health status: $status"
            return $PARAM_ERROR
            ;;
    esac

    # Send health metric
    local health_value
    case "$status" in
        "healthy") health_value=1 ;;
        "degraded") health_value=0.5 ;;
        "unhealthy") health_value=0 ;;
    esac

    send_metric "health.${component}.status" "$health_value" "gauge" "component=$component,status=$status"

    # Send response time if provided
    if [[ -n "$response_time" ]]; then
        send_metric "health.${component}.response_time" "$response_time" "histogram" "component=$component"
    fi

    # Send alert for unhealthy components
    if [[ "$status" == "unhealthy" ]]; then
        send_alert "error" "Component Unhealthy" "$component is reporting unhealthy status" "$component" "{\"details\":\"$details\"}"
    elif [[ "$status" == "degraded" ]]; then
        send_alert "warning" "Component Degraded" "$component is reporting degraded performance" "$component" "{\"details\":\"$details\"}"
    fi

    return $SUCCESS
}

############################################################################################
# Monitor function execution and send metrics                                             #
# Arguments:                                                                              #
#   $1 - Function name                                                                   #
#   $@ - Function arguments                                                              #
# Returns:                                                                                #
#   Return code of the monitored function                                               #
# Usage:                                                                                  #
#   monitor_function_execution "validate_environment" "core"                            #
############################################################################################
function monitor_function_execution() {
    if ! validate_function_params "monitor_function_execution" 1 "$#"; then
        return $PARAM_ERROR
    fi

    local function_name="${1:-}"
    shift

    local start_time end_time duration
    start_time=$(date +%s.%N)

    log_debug "Starting monitored execution of: $function_name"

    # Execute function
    local result
    if "$function_name" "$@"; then
        result=$SUCCESS

        # Calculate execution time
        end_time=$(date +%s.%N)
        if command -v bc >/dev/null 2>&1; then
            duration=$(echo "$end_time - $start_time" | bc -l)
        else
            duration=$(echo "$end_time $start_time" | awk '{print $1 - $2}')
        fi

        # Send success metrics
        send_metric "function.${function_name}.execution_time" "$duration" "histogram" "status=success"
        send_metric "function.${function_name}.calls" "1" "counter" "status=success"

        log_debug "Function execution completed successfully: $function_name (${duration}s)"
    else
        result=$?

        # Calculate execution time
        end_time=$(date +%s.%N)
        if command -v bc >/dev/null 2>&1; then
            duration=$(echo "$end_time - $start_time" | bc -l)
        else
            duration=$(echo "$end_time $start_time" | awk '{print $1 - $2}')
        fi

        # Send failure metrics
        send_metric "function.${function_name}.execution_time" "$duration" "histogram" "status=failure"
        send_metric "function.${function_name}.calls" "1" "counter" "status=failure"
        send_metric "function.${function_name}.failures" "1" "counter" "error_code=$result"

        # Send alert for critical function failures
        if _is_critical_function "$function_name"; then
            send_alert "error" "Critical Function Failed" "Function $function_name failed with code $result" "function_monitor"
        fi

        log_debug "Function execution failed: $function_name (${duration}s, code: $result)"
    fi

    return $result
}

# =============================================================================
# COST MONITORING FUNCTIONS
# =============================================================================

############################################################################################
# Send cost metrics                                                                       #
# Arguments:                                                                              #
#   $1 - Resource type                                                                   #
#   $2 - Cost amount                                                                     #
#   $3 - Currency (default: USD)                                                         #
#   $4 - Environment                                                                     #
#   $5 - Additional tags (optional)                                                      #
# Returns:                                                                                #
#   SUCCESS if cost metric sent                                                          #
# Usage:                                                                                  #
#   send_cost_metric "virtual_machine" "150.25" "USD" "production" "size=Standard_D4s"  #
############################################################################################
function send_cost_metric() {
    if ! validate_function_params "send_cost_metric" 4 "$#"; then
        return $PARAM_ERROR
    fi

    local resource_type="${1:-}"
    local cost_amount="${2:-}"
    local currency="${3:-USD}"
    local environment="${4:-}"
    local additional_tags="${5:-}"

    log_debug "Sending cost metric: $resource_type = $cost_amount $currency"

    # Validate cost amount is numeric
    if ! [[ "$cost_amount" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid cost amount: $cost_amount"
        return $PARAM_ERROR
    fi

    # Build tags
    local tags="resource_type=$resource_type,currency=$currency,environment=$environment"
    if [[ -n "$additional_tags" ]]; then
        tags="$tags,$additional_tags"
    fi

    # Send cost metric
    send_metric "cost.${resource_type}.amount" "$cost_amount" "gauge" "$tags"

    return $SUCCESS
}

############################################################################################
# Send resource utilization metrics                                                       #
# Arguments:                                                                              #
#   $1 - Resource type                                                                   #
#   $2 - Utilization percentage (0-100)                                                  #
#   $3 - Resource identifier                                                             #
#   $4 - Environment                                                                     #
# Returns:                                                                                #
#   SUCCESS if utilization metric sent                                                   #
# Usage:                                                                                  #
#   send_utilization_metric "cpu" "75.5" "vm-web-01" "production"                       #
############################################################################################
function send_utilization_metric() {
    if ! validate_function_params "send_utilization_metric" 4 "$#"; then
        return $PARAM_ERROR
    fi

    local resource_type="${1:-}"
    local utilization="${2:-}"
    local resource_id="${3:-}"
    local environment="${4:-}"

    log_debug "Sending utilization metric: $resource_type = $utilization%"

    # Validate utilization is numeric and within range
    if ! [[ "$utilization" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$utilization > 100" | bc -l) )); then
        log_error "Invalid utilization percentage: $utilization"
        return $PARAM_ERROR
    fi

    # Send utilization metric
    send_metric "utilization.${resource_type}" "$utilization" "gauge" "resource_id=$resource_id,environment=$environment"

    # Send alert for high utilization
    if (( $(echo "$utilization > 90" | bc -l) )); then
        send_alert "warning" "High Resource Utilization" "$resource_type utilization is ${utilization}% on $resource_id" "utilization_monitor"
    fi

    return $SUCCESS
}

# =============================================================================
# MONITORING SYSTEM SPECIFIC IMPLEMENTATIONS
# =============================================================================

############################################################################################
# Send metric to Azure Monitor                                                            #
############################################################################################
function _send_metric_azure_monitor() {
    local metric_name="$1"
    local metric_value="$2"
    local metric_type="$3"
    local tags="$4"
    local timestamp="$5"

    if [[ -z "$MONITORING_WORKSPACE_ID" ]]; then
        log_error "Azure Monitor workspace ID not configured"
        return $PARAM_ERROR
    fi

    # Create Azure Monitor payload
    local payload
    payload=$(jq -n \
        --arg metric_name "$metric_name" \
        --arg metric_value "$metric_value" \
        --arg timestamp "$timestamp" \
        --arg computer "$(hostname)" \
        '[{
            TimeGenerated: ($timestamp | todateiso8601),
            Computer: $computer,
            MetricName: $metric_name,
            MetricValue: ($metric_value | tonumber),
            Source: "SDAF"
        }]')

    # Send to Azure Monitor via REST API
    if command -v az >/dev/null 2>&1; then
        az monitor log-analytics workspace data-collection-rule create \
            --workspace-id "$MONITORING_WORKSPACE_ID" \
            --data "$payload" \
            >/dev/null 2>&1
    else
        log_warn "Azure CLI not available for Azure Monitor integration"
        return $DEPENDENCY_ERROR
    fi
}

############################################################################################
# Send metric to Prometheus                                                               #
############################################################################################
function _send_metric_prometheus() {
    local metric_name="$1"
    local metric_value="$2"
    local metric_type="$3"
    local tags="$4"
    local timestamp="$5"

    if [[ -z "$MONITORING_ENDPOINT" ]]; then
        log_error "Prometheus endpoint not configured"
        return $PARAM_ERROR
    fi

    # Convert tags to Prometheus format
    local prometheus_tags=""
    if [[ -n "$tags" ]]; then
        prometheus_tags="{$(echo "$tags" | sed 's/,/",/g' | sed 's/=/="/g')}"
    fi

    # Create Prometheus metric format
    local metric_line="${metric_name}${prometheus_tags} ${metric_value} ${timestamp}000"

    # Send to Prometheus pushgateway
    if command -v curl >/dev/null 2>&1; then
        echo "$metric_line" | curl -X POST \
            --data-binary @- \
            "${MONITORING_ENDPOINT}/metrics/job/sdaf" \
            >/dev/null 2>&1
    else
        log_warn "curl not available for Prometheus integration"
        return $DEPENDENCY_ERROR
    fi
}

############################################################################################
# Send metric via webhook                                                                 #
############################################################################################
function _send_metric_webhook() {
    local metric_name="$1"
    local metric_value="$2"
    local metric_type="$3"
    local tags="$4"
    local timestamp="$5"

    if [[ -z "$MONITORING_ENDPOINT" ]]; then
        log_error "Webhook endpoint not configured"
        return $PARAM_ERROR
    fi

    # Create webhook payload
    local payload
    payload=$(jq -n \
        --arg metric_name "$metric_name" \
        --arg metric_value "$metric_value" \
        --arg metric_type "$metric_type" \
        --arg tags "$tags" \
        --arg timestamp "$timestamp" \
        '{
            metric_name: $metric_name,
            metric_value: ($metric_value | tonumber),
            metric_type: $metric_type,
            tags: $tags,
            timestamp: ($timestamp | tonumber),
            source: "SAP Deployment Automation Framework"
        }')

    # Send webhook
    if command -v curl >/dev/null 2>&1; then
        curl -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$MONITORING_ENDPOINT" \
            >/dev/null 2>&1
    else
        log_warn "curl not available for webhook integration"
        return $DEPENDENCY_ERROR
    fi
}

############################################################################################
# Send structured event to monitoring system                                              #
############################################################################################
function _send_structured_event() {
    local event_type="$1"
    local event_data="$2"

    case "$MONITORING_TYPE" in
        "$MONITOR_TYPE_WEBHOOK")
            # Send event via webhook
            if [[ -n "$MONITORING_ENDPOINT" ]] && command -v curl >/dev/null 2>&1; then
                curl -X POST \
                    -H "Content-Type: application/json" \
                    -d "$event_data" \
                    "${MONITORING_ENDPOINT}/events" \
                    >/dev/null 2>&1
            fi
            ;;
        *)
            # For other systems, convert to metric
            send_metric "events.${event_type}" "1" "counter" "type=$event_type"
            ;;
    esac
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

############################################################################################
# Validate metric name format                                                             #
############################################################################################
function _validate_metric_name() {
    local metric_name="$1"

    # Metric names should contain only alphanumeric characters, dots, and underscores
    if [[ "$metric_name" =~ ^[a-zA-Z][a-zA-Z0-9._]*$ ]]; then
        return $SUCCESS
    else
        return $PARAM_ERROR
    fi
}

############################################################################################
# Validate metric value                                                                   #
############################################################################################
function _validate_metric_value() {
    local metric_value="$1"

    # Metric values should be numeric
    if [[ "$metric_value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        return $SUCCESS
    else
        return $PARAM_ERROR
    fi
}

############################################################################################
# Check if function is considered critical                                                #
############################################################################################
function _is_critical_function() {
    local function_name="$1"

    local critical_functions=(
        "authenticate_azure"
        "terraform_apply_with_recovery"
        "validate_environment"
        "process_terraform_errors"
    )

    for critical_func in "${critical_functions[@]}"; do
        if [[ "$function_name" == "$critical_func" ]]; then
            return $SUCCESS
        fi
    done

    return $GENERAL_ERROR
}

# =============================================================================
# MONITORING CONFIGURATION FUNCTIONS
# =============================================================================

############################################################################################
# Configure monitoring system                                                             #
# Arguments:                                                                              #
#   $1 - Monitoring type                                                                 #
#   $2 - Endpoint URL                                                                    #
#   $3 - API key or workspace ID                                                         #
# Returns:                                                                                #
#   SUCCESS if configured, PARAM_ERROR on invalid input                                 #
# Usage:                                                                                  #
#   configure_monitoring "azure_monitor" "" "workspace-id"                              #
#   configure_monitoring "webhook" "https://monitor.example.com" "api-key"              #
############################################################################################
function configure_monitoring() {
    if ! validate_function_params "configure_monitoring" 2 "$#"; then
        return $PARAM_ERROR
    fi

    local monitor_type="${1:-}"
    local endpoint="${2:-}"
    local api_key="${3:-}"

    log_info "Configuring monitoring: $monitor_type"

    # Validate monitoring type
    case "$monitor_type" in
        "$MONITOR_TYPE_AZURE"|"$MONITOR_TYPE_PROMETHEUS"|"$MONITOR_TYPE_SPLUNK"|"$MONITOR_TYPE_WEBHOOK")
            ;;
        *)
            log_error "Unsupported monitoring type: $monitor_type"
            return $PARAM_ERROR
            ;;
    esac

    # Update configuration
    export MONITORING_TYPE="$monitor_type"
    export MONITORING_ENDPOINT="$endpoint"

    if [[ "$monitor_type" == "$MONITOR_TYPE_AZURE" ]]; then
        export MONITORING_WORKSPACE_ID="$api_key"
    else
        export MONITORING_API_KEY="$api_key"
    fi

    export MONITORING_ENABLED="true"

    log_info "Monitoring configured successfully"
    return $SUCCESS
}

############################################################################################
# Test monitoring connectivity                                                            #
# Arguments: None                                                                         #
# Returns:                                                                                #
#   SUCCESS if test successful, NETWORK_ERROR on failure                                #
# Usage:                                                                                  #
#   test_monitoring_connectivity                                                         #
############################################################################################
function test_monitoring_connectivity() {
    log_info "Testing monitoring connectivity"

    if [[ "$MONITORING_ENABLED" != "true" ]]; then
        log_warn "Monitoring is disabled"
        return $SUCCESS
    fi

    # Send test metric
    if send_metric "test.connectivity" "1" "gauge" "test=true"; then
        log_info "✅ Monitoring connectivity test successful"
        return $SUCCESS
    else
        log_error "❌ Monitoring connectivity test failed"
        return $NETWORK_ERROR
    fi
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Test monitoring connectivity if enabled
if [[ "$MONITORING_ENABLED" == "true" && -n "$MONITORING_ENDPOINT" ]]; then
    log_debug "Testing monitoring system connectivity"
    if ! test_monitoring_connectivity >/dev/null 2>&1; then
        log_warn "Monitoring system connectivity issues detected"
    fi
fi

log_info "Monitoring and alerting integration module loaded successfully"
log_debug "Available functions: send_metric, send_deployment_event, send_alert, send_health_status"
log_debug "Monitoring configuration - Type: $MONITORING_TYPE, Enabled: $MONITORING_ENABLED"
