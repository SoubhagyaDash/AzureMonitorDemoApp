#!/bin/bash

# Azure Function Deployment Script for Synthetic Traffic Generator
# This script builds and deploys the Azure Function

set -e

echo "=== OpenTelemetry Demo - Azure Function Deployment ==="

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
FUNCTION_DIR="$PROJECT_ROOT/services/synthetic-traffic-function"
BUILD_DIR="$FUNCTION_DIR/bin/Release/net8.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check .NET SDK
    if ! command -v dotnet &> /dev/null; then
        print_error ".NET SDK not found. Please install .NET 8.0 SDK"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Please install Azure CLI"
        exit 1
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login'"
        exit 1
    fi
    
    # Check Azure Functions Core Tools
    if ! command -v func &> /dev/null; then
        print_warning "Azure Functions Core Tools not found. Install for local testing:"
        print_warning "npm install -g azure-functions-core-tools@4 --unsafe-perm true"
    fi
    
    print_success "Prerequisites check completed"
}

# Function to build the function
build_function() {
    print_status "Building Azure Function..."
    
    cd "$FUNCTION_DIR"
    
    # Restore packages
    dotnet restore
    if [ $? -ne 0 ]; then
        print_error "Failed to restore packages"
        exit 1
    fi
    
    # Build the project
    dotnet build -c Release
    if [ $? -ne 0 ]; then
        print_error "Build failed"
        exit 1
    fi
    
    # Publish for deployment
    dotnet publish -c Release --output ./publish
    if [ $? -ne 0 ]; then
        print_error "Publish failed"
        exit 1
    fi
    
    print_success "Function built successfully"
}

# Function to test locally
test_local() {
    print_status "Starting local testing..."
    
    cd "$FUNCTION_DIR"
    
    if command -v func &> /dev/null; then
        print_status "Starting Azure Functions runtime locally..."
        print_status "Function will be available at: http://localhost:7071"
        print_status "Press Ctrl+C to stop"
        
        func start --port 7071
    else
        print_warning "Azure Functions Core Tools not available. Skipping local test."
        print_warning "Install with: npm install -g azure-functions-core-tools@4 --unsafe-perm true"
    fi
}

# Function to deploy to Azure
deploy_to_azure() {
    local function_app_name="$1"
    local resource_group="$2"
    
    if [ -z "$function_app_name" ] || [ -z "$resource_group" ]; then
        print_error "Function app name and resource group are required for deployment"
        echo "Usage: $0 deploy <function-app-name> <resource-group>"
        exit 1
    fi
    
    print_status "Deploying to Azure Function App: $function_app_name"
    
    cd "$FUNCTION_DIR"
    
    # Check if function app exists
    if ! az functionapp show --name "$function_app_name" --resource-group "$resource_group" &> /dev/null; then
        print_error "Function app '$function_app_name' not found in resource group '$resource_group'"
        print_status "Please create the function app first using Terraform or the Azure portal"
        exit 1
    fi
    
    # Deploy using zip deployment
    print_status "Creating deployment package..."
    cd publish
    zip -r ../deployment.zip . > /dev/null
    cd ..
    
    print_status "Uploading to Azure..."
    az functionapp deployment source config-zip \
        --name "$function_app_name" \
        --resource-group "$resource_group" \
        --src deployment.zip
    
    if [ $? -eq 0 ]; then
        print_success "Deployment completed successfully"
        
        # Get function app URL
        local function_url=$(az functionapp show --name "$function_app_name" --resource-group "$resource_group" --query "defaultHostName" -o tsv)
        print_status "Function App URL: https://$function_url"
        print_status "Traffic Status: https://$function_url/api/GetTrafficStatus"
        print_status "Manual Trigger: https://$function_url/api/GenerateTrafficHttp"
        
        # Clean up
        rm -f deployment.zip
    else
        print_error "Deployment failed"
        rm -f deployment.zip
        exit 1
    fi
}

# Function to configure function app settings
configure_function() {
    local function_app_name="$1"
    local resource_group="$2"
    local api_gateway_url="$3"
    
    if [ -z "$function_app_name" ] || [ -z "$resource_group" ] || [ -z "$api_gateway_url" ]; then
        print_error "Function app name, resource group, and API gateway URL are required"
        echo "Usage: $0 configure <function-app-name> <resource-group> <api-gateway-url>"
        exit 1
    fi
    
    print_status "Configuring function app settings..."
    
    # Update application settings
    az functionapp config appsettings set \
        --name "$function_app_name" \
        --resource-group "$resource_group" \
        --settings \
        "API_GATEWAY_URL=$api_gateway_url" \
        "TRAFFIC_MIN_REQUESTS=5" \
        "TRAFFIC_MAX_REQUESTS=40" \
        "TRAFFIC_ERROR_RATE=0.02" \
        "TRAFFIC_ENABLED_SCENARIOS=Product Browsing,Shopping Cart,Order Processing,User Registration,Health Monitoring"
    
    print_success "Configuration updated successfully"
}

# Function to show function status
show_status() {
    local function_app_name="$1"
    local resource_group="$2"
    
    if [ -z "$function_app_name" ] || [ -z "$resource_group" ]; then
        print_error "Function app name and resource group are required"
        echo "Usage: $0 status <function-app-name> <resource-group>"
        exit 1
    fi
    
    print_status "Checking function app status..."
    
    # Get function app details
    local app_details=$(az functionapp show --name "$function_app_name" --resource-group "$resource_group" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local state=$(echo "$app_details" | jq -r '.state')
        local url=$(echo "$app_details" | jq -r '.defaultHostName')
        local runtime_version=$(echo "$app_details" | jq -r '.siteConfig.netFrameworkVersion // .siteConfig.linuxFxVersion')
        
        echo "=== Function App Status ==="
        echo "Name: $function_app_name"
        echo "State: $state"
        echo "URL: https://$url"
        echo "Runtime: $runtime_version"
        echo ""
        
        # Test if functions are accessible
        print_status "Testing function endpoints..."
        
        local status_url="https://$url/api/GetTrafficStatus"
        if curl -s --max-time 10 "$status_url" > /dev/null; then
            print_success "Status endpoint is accessible: $status_url"
        else
            print_warning "Status endpoint not accessible: $status_url"
        fi
        
        # Show recent logs if available
        print_status "Recent logs:"
        az functionapp logs tail --name "$function_app_name" --resource-group "$resource_group" --timeout 10 2>/dev/null || print_warning "Could not retrieve logs"
        
    else
        print_error "Function app not found: $function_app_name"
    fi
}

# Function to show logs
show_logs() {
    local function_app_name="$1"
    local resource_group="$2"
    
    if [ -z "$function_app_name" ] || [ -z "$resource_group" ]; then
        print_error "Function app name and resource group are required"
        echo "Usage: $0 logs <function-app-name> <resource-group>"
        exit 1
    fi
    
    print_status "Streaming logs from function app: $function_app_name"
    print_status "Press Ctrl+C to stop"
    
    az functionapp logs tail --name "$function_app_name" --resource-group "$resource_group"
}

# Function to show help
show_help() {
    echo "Azure Function Deployment Script for Synthetic Traffic Generator"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  build                                           - Build the function locally"
    echo "  test                                            - Test the function locally"
    echo "  deploy <function-app-name> <resource-group>     - Deploy to Azure"
    echo "  configure <function-app-name> <resource-group> <api-gateway-url> - Configure app settings"
    echo "  status <function-app-name> <resource-group>     - Show function status"
    echo "  logs <function-app-name> <resource-group>       - Stream function logs"
    echo "  help                                            - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 build"
    echo "  $0 test"
    echo "  $0 deploy otel-demo-traffic-generator myResourceGroup"
    echo "  $0 configure otel-demo-traffic-generator myResourceGroup https://my-api-gateway.azurewebsites.net"
    echo "  $0 status otel-demo-traffic-generator myResourceGroup"
}

# Main script logic
case "${1:-help}" in
    "build")
        check_prerequisites
        build_function
        ;;
    "test")
        check_prerequisites
        build_function
        test_local
        ;;
    "deploy")
        check_prerequisites
        build_function
        deploy_to_azure "$2" "$3"
        ;;
    "configure")
        configure_function "$2" "$3" "$4"
        ;;
    "status")
        show_status "$2" "$3"
        ;;
    "logs")
        show_logs "$2" "$3"
        ;;
    "help")
        show_help
        ;;
    *)
        print_error "Invalid command: $1"
        show_help
        exit 1
        ;;
esac