#!/bin/bash

# Synthetic Traffic Generator Deployment Script
# This script builds and runs the synthetic traffic generator

set -e

echo "=== OpenTelemetry Demo - Synthetic Traffic Deployment ==="

# Configuration
SERVICE_NAME="synthetic-traffic"
BUILD_DIR="$(pwd)/services/$SERVICE_NAME"
LOG_DIR="$(pwd)/logs"
PID_FILE="$LOG_DIR/$SERVICE_NAME.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if service is running
check_service_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "Synthetic traffic generator is running (PID: $pid)"
            return 0
        else
            print_warning "PID file exists but process is not running. Cleaning up..."
            rm -f "$PID_FILE"
            return 1
        fi
    else
        return 1
    fi
}

# Function to stop the service
stop_service() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        print_status "Stopping synthetic traffic generator (PID: $pid)..."
        
        if kill "$pid" 2>/dev/null; then
            # Wait for graceful shutdown
            sleep 5
            
            # Force kill if still running
            if ps -p "$pid" > /dev/null 2>&1; then
                print_warning "Process still running, force killing..."
                kill -9 "$pid" 2>/dev/null || true
            fi
            
            rm -f "$PID_FILE"
            print_success "Synthetic traffic generator stopped"
        else
            print_warning "Could not stop process, it may have already exited"
            rm -f "$PID_FILE"
        fi
    else
        print_warning "Service is not running"
    fi
}

# Function to build the service
build_service() {
    print_status "Building synthetic traffic generator..."
    
    cd "$BUILD_DIR"
    
    if command -v dotnet >/dev/null 2>&1; then
        dotnet restore
        dotnet build -c Release
        print_success "Build completed successfully"
    else
        print_error ".NET SDK not found. Please install .NET 8.0 SDK"
        exit 1
    fi
}

# Function to start the service
start_service() {
    print_status "Starting synthetic traffic generator..."
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    cd "$BUILD_DIR"
    
    # Set environment variables
    export ASPNETCORE_ENVIRONMENT="${ENVIRONMENT:-Production}"
    export DOTNET_ENVIRONMENT="${ENVIRONMENT:-Production}"
    
    # Start the service in background
    nohup dotnet run -c Release > "$LOG_DIR/$SERVICE_NAME.log" 2>&1 &
    local pid=$!
    
    # Save PID
    echo "$pid" > "$PID_FILE"
    
    # Wait a moment and check if process is still running
    sleep 3
    if ps -p "$pid" > /dev/null 2>&1; then
        print_success "Synthetic traffic generator started successfully (PID: $pid)"
        print_status "Log file: $LOG_DIR/$SERVICE_NAME.log"
        print_status "PID file: $PID_FILE"
    else
        print_error "Failed to start synthetic traffic generator"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# Function to show logs
show_logs() {
    local log_file="$LOG_DIR/$SERVICE_NAME.log"
    
    if [[ -f "$log_file" ]]; then
        print_status "Showing last 50 lines of log file..."
        echo "----------------------------------------"
        tail -n 50 "$log_file"
        echo "----------------------------------------"
        print_status "To follow logs in real-time: tail -f $log_file"
    else
        print_warning "Log file not found: $log_file"
    fi
}

# Function to show service status
show_status() {
    echo "=== Synthetic Traffic Generator Status ==="
    
    if check_service_status; then
        local pid=$(cat "$PID_FILE")
        local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
        print_success "Service is running"
        print_status "PID: $pid"
        print_status "Uptime: $uptime"
        print_status "Log file: $LOG_DIR/$SERVICE_NAME.log"
        
        # Show recent log entries
        echo ""
        print_status "Recent log entries:"
        echo "----------------------------------------"
        tail -n 10 "$LOG_DIR/$SERVICE_NAME.log" 2>/dev/null || echo "No logs available"
        echo "----------------------------------------"
    else
        print_warning "Service is not running"
    fi
    
    echo ""
    print_status "Available commands:"
    echo "  $0 start    - Start the traffic generator"
    echo "  $0 stop     - Stop the traffic generator" 
    echo "  $0 restart  - Restart the traffic generator"
    echo "  $0 build    - Build the service"
    echo "  $0 logs     - Show logs"
    echo "  $0 status   - Show service status"
}

# Main script logic
case "${1:-status}" in
    "start")
        if check_service_status; then
            print_warning "Service is already running"
            show_status
        else
            build_service
            start_service
        fi
        ;;
    "stop")
        stop_service
        ;;
    "restart")
        stop_service
        sleep 2
        build_service
        start_service
        ;;
    "build")
        build_service
        ;;
    "logs")
        show_logs
        ;;
    "status")
        show_status
        ;;
    *)
        print_error "Invalid command: $1"
        print_status "Usage: $0 {start|stop|restart|build|logs|status}"
        exit 1
        ;;
esac