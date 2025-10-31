#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="../../terraform"
FRONTEND_DIR="../../../services/frontend"
BUILD_DIR="build"
DEPLOY_ZIP="frontend-deploy.zip"

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install it first."
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Terraform state exists
    if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        print_error "Terraform state not found. Please deploy infrastructure first."
        print_warning "Run: cd ../../terraform && terraform apply"
        exit 1
    fi
    
    # Check if frontend directory exists
    if [ ! -d "$FRONTEND_DIR" ]; then
        print_error "Frontend directory not found: $FRONTEND_DIR"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to get infrastructure details
get_infrastructure_details() {
    print_status "Getting infrastructure details..."
    
    cd "$TERRAFORM_DIR"
    
    # Get resource group name
    RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$RESOURCE_GROUP" ]; then
        print_error "Could not get resource group name from Terraform output"
        exit 1
    fi
    
    # Get App Service name
    APP_SERVICE_NAME=$(terraform output -json frontend_urls 2>/dev/null | jq -r '.app_service_url' | sed 's|https://||' | sed 's|\..*||')
    if [ $? -ne 0 ] || [ -z "$APP_SERVICE_NAME" ] || [ "$APP_SERVICE_NAME" = "null" ]; then
        print_error "Could not get App Service name from Terraform output"
        print_warning "Make sure the frontend infrastructure is deployed with App Service"
        exit 1
    fi
    
    # Get connection strings and endpoints
    LOAD_BALANCER_IP=$(terraform output -raw load_balancer_public_ip 2>/dev/null)
    AKS_FQDN=$(terraform output -raw aks_cluster_name 2>/dev/null)
    VM_IPS=$(terraform output -json vm_public_ips 2>/dev/null | jq -r '.[1]' 2>/dev/null)
    APP_INSIGHTS_KEY=$(terraform output -raw application_insights_instrumentation_key 2>/dev/null)
    APP_INSIGHTS_CONNECTION=$(terraform output -raw application_insights_connection_string 2>/dev/null)
    
    print_success "Infrastructure details retrieved:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  App Service: $APP_SERVICE_NAME"
    echo "  Load Balancer IP: $LOAD_BALANCER_IP"
    echo "  AKS Cluster: $AKS_FQDN"
    echo "  VM2 IP: $VM_IPS"
    
    cd - > /dev/null
}

# Function to prepare environment file
prepare_environment() {
    print_status "Preparing environment configuration..."
    
    cd "$FRONTEND_DIR"
    
    # Create .env.production file with correct service endpoints
    cat > .env.production << EOF
# API Service Endpoints
REACT_APP_API_GATEWAY_URL=http://${LOAD_BALANCER_IP}
REACT_APP_ORDER_SERVICE_URL=http://${AKS_FQDN}/api/orders
REACT_APP_PAYMENT_SERVICE_URL=http://${AKS_FQDN}/api/payments
REACT_APP_INVENTORY_SERVICE_URL=http://${VM_IPS}:3000
REACT_APP_EVENT_PROCESSOR_URL=http://${VM_IPS}:8001
REACT_APP_NOTIFICATION_SERVICE_URL=http://${AKS_FQDN}/api/notifications

# Application Insights Configuration
REACT_APP_APPINSIGHTS_INSTRUMENTATIONKEY=${APP_INSIGHTS_KEY}
REACT_APP_APPINSIGHTS_CONNECTION_STRING=${APP_INSIGHTS_CONNECTION}

# Build Configuration
GENERATE_SOURCEMAP=false
SKIP_PREFLIGHT_CHECK=true
EOF
    
    print_success "Environment configuration created"
    cd - > /dev/null
}

# Function to build React application
build_application() {
    print_status "Building React application..."
    
    cd "$FRONTEND_DIR"
    
    # Install dependencies
    print_status "Installing npm dependencies..."
    npm install
    
    if [ $? -ne 0 ]; then
        print_error "npm install failed"
        exit 1
    fi
    
    # Build for production
    print_status "Building for production..."
    npm run build
    
    if [ $? -ne 0 ]; then
        print_error "npm build failed"
        exit 1
    fi
    
    # Verify build directory exists
    if [ ! -d "$BUILD_DIR" ]; then
        print_error "Build directory not found after build"
        exit 1
    fi
    
    print_success "React application built successfully"
    cd - > /dev/null
}

# Function to create deployment package
create_deployment_package() {
    print_status "Creating deployment package..."
    
    cd "$FRONTEND_DIR"
    
    # Remove existing zip if it exists
    if [ -f "$DEPLOY_ZIP" ]; then
        rm "$DEPLOY_ZIP"
    fi
    
    # Create web.config for App Service Node.js hosting
    cat > build/web.config << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="React Routes" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
          </conditions>
          <action type="Rewrite" url="/index.html" />
        </rule>
      </rules>
    </rewrite>
    <staticContent>
      <mimeMap fileExtension=".json" mimeType="application/json" />
    </staticContent>
  </system.webServer>
</configuration>
EOF
    
    # Create package.json for App Service
    cat > build/package.json << 'EOF'
{
  "name": "otel-demo-frontend",
  "version": "1.0.0",
  "description": "OpenTelemetry Demo Frontend",
  "main": "index.html",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "path": "^0.12.7"
  }
}
EOF
    
    # Create simple Express server for App Service
    cat > build/server.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();
const port = process.env.PORT || 3000;

// Serve static files from the build directory
app.use(express.static(path.join(__dirname)));

// Handle React Router - send all requests to index.html
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(port, () => {
  console.log(`Frontend server running on port ${port}`);
});
EOF
    
    # Create zip file
    cd build
    zip -r "../$DEPLOY_ZIP" .
    cd ..
    
    if [ ! -f "$DEPLOY_ZIP" ]; then
        print_error "Failed to create deployment package"
        exit 1
    fi
    
    print_success "Deployment package created: $DEPLOY_ZIP"
    cd - > /dev/null
}

# Function to deploy to App Service
deploy_to_app_service() {
    print_status "Deploying to Azure App Service..."
    
    cd "$FRONTEND_DIR"
    
    # Deploy using Azure CLI
    print_status "Uploading deployment package..."
    az webapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_SERVICE_NAME" \
        --src "$DEPLOY_ZIP"
    
    if [ $? -ne 0 ]; then
        print_error "Deployment to App Service failed"
        exit 1
    fi
    
    print_success "Deployment completed successfully"
    cd - > /dev/null
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    # Get App Service URL
    APP_SERVICE_URL="https://${APP_SERVICE_NAME}.azurewebsites.net"
    
    print_status "Waiting for App Service to start..."
    sleep 30
    
    # Test if the application is responding
    print_status "Testing application response..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_SERVICE_URL" || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        print_success "Application is responding successfully"
        print_success "Frontend URL: $APP_SERVICE_URL"
    else
        print_warning "Application may still be starting (HTTP: $HTTP_CODE)"
        print_warning "Frontend URL: $APP_SERVICE_URL"
        print_warning "Please wait a few minutes and check the URL manually"
    fi
}

# Function to show post-deployment information
show_post_deployment_info() {
    print_status "Post-Deployment Information"
    echo "=================================="
    
    APP_SERVICE_URL="https://${APP_SERVICE_NAME}.azurewebsites.net"
    
    print_success "🌐 Frontend Access:"
    echo "  Primary URL: $APP_SERVICE_URL"
    echo "  App Service: $APP_SERVICE_NAME"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo ""
    
    print_status "🔗 Backend Services:"
    echo "  API Gateway: http://$LOAD_BALANCER_IP"
    echo "  Swagger UI: http://$LOAD_BALANCER_IP/swagger"
    echo "  AKS Services: http://$AKS_FQDN (requires ingress)"
    echo "  VM Services: http://$VM_IPS (Event Processor, Inventory)"
    echo ""
    
    print_status "📊 Monitoring:"
    echo "  Application Insights: Azure Portal > Application Insights"
    echo "  Logs: Azure Portal > App Service > Log stream"
    echo ""
    
    print_status "🔧 Management Commands:"
    echo "# View App Service logs"
    echo "az webapp log tail --resource-group $RESOURCE_GROUP --name $APP_SERVICE_NAME"
    echo ""
    echo "# Restart App Service"
    echo "az webapp restart --resource-group $RESOURCE_GROUP --name $APP_SERVICE_NAME"
    echo ""
    echo "# Open in browser"
    if command -v start &> /dev/null; then
        echo "start $APP_SERVICE_URL"
    elif command -v open &> /dev/null; then
        echo "open $APP_SERVICE_URL"
    else
        echo "xdg-open $APP_SERVICE_URL"
    fi
    echo ""
    
    print_success "✅ Deployment completed successfully!"
    print_status "Frontend is now available at: $APP_SERVICE_URL"
}

# Function to cleanup temporary files
cleanup() {
    print_status "Cleaning up temporary files..."
    
    cd "$FRONTEND_DIR"
    
    # Remove deployment zip
    if [ -f "$DEPLOY_ZIP" ]; then
        rm "$DEPLOY_ZIP"
        print_success "Removed deployment package"
    fi
    
    # Remove production env file
    if [ -f ".env.production" ]; then
        rm ".env.production"
        print_success "Removed temporary environment file"
    fi
    
    cd - > /dev/null
}

# Main execution
main() {
    echo "================================================"
    echo "   Azure App Service Frontend Deployment"
    echo "================================================"
    echo ""
    
    # Set up error handling
    trap cleanup EXIT
    
    # Run deployment steps
    check_prerequisites
    get_infrastructure_details
    prepare_environment
    build_application
    create_deployment_package
    deploy_to_app_service
    verify_deployment
    show_post_deployment_info
    
    print_success "🚀 Frontend deployment to App Service completed!"
}

# Run main function
main "$@"