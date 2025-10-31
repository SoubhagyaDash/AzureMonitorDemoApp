#!/bin/bash

# Always-On Synthetic Traffic Orchestrator
# This script manages multiple traffic generators and monitors their health

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TRAFFIC_SERVICE_DIR="$PROJECT_ROOT/services/synthetic-traffic"
LOG_DIR="$PROJECT_ROOT/logs"
CONFIG_DIR="$PROJECT_ROOT/config"

# Load configuration
source "$SCRIPT_DIR/traffic-config.sh" 2>/dev/null || {
    echo "Warning: traffic-config.sh not found, using defaults"
}

# Default configuration if not loaded from file
API_GATEWAY_URL="${API_GATEWAY_URL:-http://localhost:5000}"
TRAFFIC_PATTERNS="${TRAFFIC_PATTERNS:-business,peak,evening,night}"
ENABLE_HEALTH_MONITORING="${ENABLE_HEALTH_MONITORING:-true}"
RESTART_ON_FAILURE="${RESTART_ON_FAILURE:-true}"
MAX_RESTART_ATTEMPTS="${MAX_RESTART_ATTEMPTS:-3}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-60}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${PURPLE}[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
    fi
}

# Function to check if API Gateway is accessible
check_api_gateway() {
    local url="$1"
    local timeout=10
    
    log_debug "Checking API Gateway health: $url"
    
    if curl -s --max-time $timeout "$url/health" >/dev/null 2>&1; then
        return 0
    elif curl -s --max-time $timeout "$url/api/health" >/dev/null 2>&1; then
        return 0
    elif curl -s --max-time $timeout "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to start traffic generator with specific configuration
start_traffic_generator() {
    local config_name="$1"
    local instance_id="$2"
    local api_url="$3"
    
    log_info "Starting traffic generator instance: $config_name-$instance_id"
    
    # Create instance-specific configuration
    local config_file="$CONFIG_DIR/traffic-$config_name-$instance_id.json"
    local pid_file="$LOG_DIR/traffic-$config_name-$instance_id.pid"
    local log_file="$LOG_DIR/traffic-$config_name-$instance_id.log"
    
    # Generate configuration based on pattern
    generate_traffic_config "$config_name" "$api_url" > "$config_file"
    
    # Start the traffic generator
    cd "$TRAFFIC_SERVICE_DIR"
    
    ASPNETCORE_ENVIRONMENT="Production" \
    DOTNET_ENVIRONMENT="Production" \
    TRAFFIC_CONFIG_FILE="$config_file" \
    nohup dotnet run -c Release > "$log_file" 2>&1 &
    
    local pid=$!
    echo "$pid" > "$pid_file"
    
    # Wait and verify startup
    sleep 3
    if ps -p "$pid" > /dev/null 2>&1; then
        log_success "Traffic generator started: $config_name-$instance_id (PID: $pid)"
        return 0
    else
        log_error "Failed to start traffic generator: $config_name-$instance_id"
        rm -f "$pid_file"
        return 1
    fi
}

# Function to generate traffic configuration for different patterns
generate_traffic_config() {
    local pattern="$1"
    local api_url="$2"
    
    case "$pattern" in
        "business")
            cat << EOF
{
  "ApiGateway": { "BaseUrl": "$api_url" },
  "TrafficGeneration": {
    "MinRequestsPerMinute": 10,
    "MaxRequestsPerMinute": 25,
    "BusinessHoursMultiplier": 1.5,
    "PeakHoursMultiplier": 2.0,
    "NightHoursMultiplier": 0.3,
    "EnableRealisticPatterns": true,
    "BaseErrorRate": 0.02
  },
  "Scenarios": {
    "ProductBrowsing": { "Weight": 40, "Enabled": true },
    "ShoppingCart": { "Weight": 30, "Enabled": true },
    "OrderProcessing": { "Weight": 20, "Enabled": true },
    "UserRegistration": { "Weight": 5, "Enabled": true },
    "InventoryManagement": { "Weight": 3, "Enabled": true },
    "HealthMonitoring": { "Weight": 2, "Enabled": true }
  }
}
EOF
            ;;
        "peak")
            cat << EOF
{
  "ApiGateway": { "BaseUrl": "$api_url" },
  "TrafficGeneration": {
    "MinRequestsPerMinute": 20,
    "MaxRequestsPerMinute": 50,
    "BusinessHoursMultiplier": 2.0,
    "PeakHoursMultiplier": 3.5,
    "NightHoursMultiplier": 0.5,
    "EnableRealisticPatterns": true,
    "BaseErrorRate": 0.03
  },
  "Scenarios": {
    "OrderProcessing": { "Weight": 35, "Enabled": true },
    "ShoppingCart": { "Weight": 25, "Enabled": true },
    "ProductBrowsing": { "Weight": 25, "Enabled": true },
    "UserRegistration": { "Weight": 10, "Enabled": true },
    "InventoryManagement": { "Weight": 3, "Enabled": true },
    "HealthMonitoring": { "Weight": 2, "Enabled": true }
  }
}
EOF
            ;;
        "evening")
            cat << EOF
{
  "ApiGateway": { "BaseUrl": "$api_url" },
  "TrafficGeneration": {
    "MinRequestsPerMinute": 8,
    "MaxRequestsPerMinute": 18,
    "BusinessHoursMultiplier": 0.8,
    "PeakHoursMultiplier": 1.0,
    "NightHoursMultiplier": 1.2,
    "EnableRealisticPatterns": true,
    "BaseErrorRate": 0.015
  },
  "Scenarios": {
    "ProductBrowsing": { "Weight": 50, "Enabled": true },
    "ShoppingCart": { "Weight": 25, "Enabled": true },
    "OrderProcessing": { "Weight": 15, "Enabled": true },
    "UserRegistration": { "Weight": 5, "Enabled": true },
    "InventoryManagement": { "Weight": 3, "Enabled": true },
    "HealthMonitoring": { "Weight": 2, "Enabled": true }
  }
}
EOF
            ;;
        "night")
            cat << EOF
{
  "ApiGateway": { "BaseUrl": "$api_url" },
  "TrafficGeneration": {
    "MinRequestsPerMinute": 2,
    "MaxRequestsPerMinute": 8,
    "BusinessHoursMultiplier": 0.2,
    "PeakHoursMultiplier": 0.3,
    "NightHoursMultiplier": 1.0,
    "EnableRealisticPatterns": true,
    "BaseErrorRate": 0.01
  },
  "Scenarios": {
    "HealthMonitoring": { "Weight": 40, "Enabled": true },
    "InventoryManagement": { "Weight": 30, "Enabled": true },
    "ProductBrowsing": { "Weight": 20, "Enabled": true },
    "ShoppingCart": { "Weight": 5, "Enabled": true },
    "OrderProcessing": { "Weight": 3, "Enabled": true },
    "UserRegistration": { "Weight": 2, "Enabled": true }
  }
}
EOF
            ;;
    esac
}

# Function to stop all traffic generators
stop_all_generators() {
    log_info "Stopping all traffic generators..."
    
    local stopped_count=0
    for pid_file in "$LOG_DIR"/traffic-*.pid; do
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            local instance_name=$(basename "$pid_file" .pid)
            
            if ps -p "$pid" > /dev/null 2>&1; then
                log_info "Stopping $instance_name (PID: $pid)"
                kill "$pid" 2>/dev/null || true
                sleep 2
                
                # Force kill if still running
                if ps -p "$pid" > /dev/null 2>&1; then
                    kill -9 "$pid" 2>/dev/null || true
                fi
                
                ((stopped_count++))
            fi
            
            rm -f "$pid_file"
        fi
    done
    
    log_success "Stopped $stopped_count traffic generator instances"
}

# Function to monitor traffic generators
monitor_generators() {
    log_info "Starting traffic generator monitoring..."
    
    while true; do
        local active_count=0
        local failed_count=0
        
        for pid_file in "$LOG_DIR"/traffic-*.pid; do
            if [[ -f "$pid_file" ]]; then
                local pid=$(cat "$pid_file")
                local instance_name=$(basename "$pid_file" .pid)
                
                if ps -p "$pid" > /dev/null 2>&1; then
                    ((active_count++))
                    log_debug "$instance_name is running (PID: $pid)"
                else
                    ((failed_count++))
                    log_warning "$instance_name has stopped unexpectedly"
                    
                    if [[ "$RESTART_ON_FAILURE" == "true" ]]; then
                        # Extract pattern and instance ID from filename
                        local pattern=$(echo "$instance_name" | cut -d'-' -f2)
                        local instance_id=$(echo "$instance_name" | cut -d'-' -f3)
                        
                        log_info "Attempting to restart $instance_name..."
                        rm -f "$pid_file"
                        start_traffic_generator "$pattern" "$instance_id" "$API_GATEWAY_URL"
                    fi
                fi
            fi
        done
        
        log_info "Traffic generator status: $active_count active, $failed_count failed"
        
        # Health check for API Gateway
        if ! check_api_gateway "$API_GATEWAY_URL"; then
            log_warning "API Gateway health check failed: $API_GATEWAY_URL"
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# Function to start all configured traffic generators
start_all_generators() {
    log_info "Starting always-on synthetic traffic generators..."
    
    # Create required directories
    mkdir -p "$LOG_DIR" "$CONFIG_DIR"
    
    # Check API Gateway availability
    if ! check_api_gateway "$API_GATEWAY_URL"; then
        log_warning "API Gateway not available at $API_GATEWAY_URL, but starting generators anyway"
    else
        log_success "API Gateway is accessible at $API_GATEWAY_URL"
    fi
    
    # Start traffic generators for each pattern
    local instance_count=0
    IFS=',' read -ra PATTERNS <<< "$TRAFFIC_PATTERNS"
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs) # trim whitespace
        
        # Start multiple instances for load distribution
        for instance_id in 1 2; do
            if start_traffic_generator "$pattern" "$instance_id" "$API_GATEWAY_URL"; then
                ((instance_count++))
            fi
            sleep 2 # Stagger startup
        done
    done
    
    log_success "Started $instance_count traffic generator instances"
}

# Function to show status
show_status() {
    echo "=== Always-On Synthetic Traffic Status ==="
    echo "API Gateway URL: $API_GATEWAY_URL"
    echo "Traffic Patterns: $TRAFFIC_PATTERNS"
    echo "Health Monitoring: $ENABLE_HEALTH_MONITORING"
    echo "Auto Restart: $RESTART_ON_FAILURE"
    echo ""
    
    local active_count=0
    local total_requests=0
    
    for pid_file in "$LOG_DIR"/traffic-*.pid; do
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            local instance_name=$(basename "$pid_file" .pid)
            local log_file="$LOG_DIR/$instance_name.log"
            
            if ps -p "$pid" > /dev/null 2>&1; then
                ((active_count++))
                echo "✅ $instance_name (PID: $pid)"
                
                # Show recent activity if log exists
                if [[ -f "$log_file" ]]; then
                    local recent_requests=$(tail -n 100 "$log_file" 2>/dev/null | grep -c "Request:" || echo "0")
                    echo "   Recent requests: $recent_requests"
                    ((total_requests += recent_requests))
                fi
            else
                echo "❌ $instance_name (Not running)"
                rm -f "$pid_file"
            fi
        fi
    done
    
    echo ""
    echo "Active Generators: $active_count"
    echo "Total Recent Requests: $total_requests"
    
    # API Gateway health
    if check_api_gateway "$API_GATEWAY_URL"; then
        echo "API Gateway: ✅ Accessible"
    else
        echo "API Gateway: ❌ Not accessible"
    fi
    
    echo ""
    echo "Available commands:"
    echo "  $0 start     - Start all traffic generators"
    echo "  $0 stop      - Stop all traffic generators"
    echo "  $0 restart   - Restart all traffic generators"
    echo "  $0 monitor   - Start monitoring mode"
    echo "  $0 status    - Show current status"
    echo "  $0 logs      - Show recent logs"
}

# Function to show logs
show_logs() {
    echo "=== Recent Traffic Generator Logs ==="
    
    for log_file in "$LOG_DIR"/traffic-*.log; do
        if [[ -f "$log_file" ]]; then
            local instance_name=$(basename "$log_file" .log)
            echo ""
            echo "--- $instance_name ---"
            tail -n 20 "$log_file" 2>/dev/null || echo "No logs available"
        fi
    done
    
    echo ""
    echo "--- Orchestrator Logs ---"
    tail -n 20 "$LOG_DIR/orchestrator.log" 2>/dev/null || echo "No orchestrator logs available"
}

# Signal handlers for graceful shutdown
trap 'log_info "Received SIGTERM, shutting down..."; stop_all_generators; exit 0' TERM
trap 'log_info "Received SIGINT, shutting down..."; stop_all_generators; exit 0' INT

# Main script logic
case "${1:-status}" in
    "start")
        stop_all_generators  # Stop any existing instances
        start_all_generators
        ;;
    "stop")
        stop_all_generators
        ;;
    "restart")
        stop_all_generators
        sleep 3
        start_all_generators
        ;;
    "monitor")
        monitor_generators
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|monitor|status|logs}"
        exit 1
        ;;
esac