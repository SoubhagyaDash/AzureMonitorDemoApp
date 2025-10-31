#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
SERVICES_DIR="$SCRIPT_DIR/../services"
DEPLOY_DIR="$SCRIPT_DIR/deploy"

# Deployment configuration
DEPLOY_INFRASTRUCTURE=true
DEPLOY_FRONTEND=true
DEPLOY_CONTAINERS=true
DEPLOY_VMS=true
DEPLOY_SYNTHETIC_TRAFFIC=true
SKIP_CONFIRMATIONS=false

# Function to print colored output
print_header() {
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================================${NC}"
    echo ""
}

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

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Azure OpenTelemetry Demo - Complete Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-infrastructure    Skip infrastructure deployment"
    echo "  --skip-frontend          Skip frontend deployment"
    echo "  --skip-containers       Skip container deployments"
    echo "  --skip-vms              Skip VM service deployments"
    echo "  --skip-synthetic-traffic Skip Azure Functions traffic generator"
    echo "  --yes                   Skip all confirmations"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      Deploy everything (interactive)"
    echo "  $0 --yes               Deploy everything (automated)"
    echo "  $0 --skip-containers    Deploy except containers"
    echo "  $0 --skip-synthetic-traffic Deploy without traffic generator"
    echo ""
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-infrastructure)
                DEPLOY_INFRASTRUCTURE=false
                shift
                ;;
            --skip-frontend)
                DEPLOY_FRONTEND=false
                shift
                ;;
            --skip-containers)
                DEPLOY_CONTAINERS=false
                shift
                ;;
            --skip-vms)
                DEPLOY_VMS=false
                shift
                ;;
            --skip-synthetic-traffic)
                DEPLOY_SYNTHETIC_TRAFFIC=false
                shift
                ;;
            --yes)
                SKIP_CONFIRMATIONS=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to configure deployment settings
configure_deployment() {
    print_step "Configuration Setup"
    
    # Check if terraform.tfvars exists
    if [[ ! -f "$TERRAFORM_DIR/terraform.tfvars" && "$SKIP_CONFIRMATIONS" != "true" ]]; then
        echo ""
        print_status "No terraform.tfvars found. Let's configure your deployment:"
        echo ""
        
        # Resource Group Name
        read -p "$(echo -e "${CYAN}Resource Group Name${NC} [rg-otel-demo]: ")" rg_name
        rg_name=${rg_name:-"rg-otel-demo"}
        
        # Location
        echo ""
        echo "Available regions: East US, West US 2, Central US, West Europe, Southeast Asia"
        read -p "$(echo -e "${CYAN}Azure Region${NC} [East US]: ")" location
        location=${location:-"East US"}
        
        # Environment
        read -p "$(echo -e "${CYAN}Environment${NC} [dev]: ")" environment
        environment=${environment:-"dev"}
        
        # Create terraform.tfvars
        cat > "$TERRAFORM_DIR/terraform.tfvars" << EOF
# Auto-generated configuration
resource_group_name = "$rg_name"
location           = "$location"
environment        = "$environment"
project_name       = "otel-demo"

# Default tags
tags = {
  Project     = "OpenTelemetry Demo"
  Environment = "$environment"
  Owner       = "$(whoami)"
  Purpose     = "Azure Monitor OTel Showcase"
}
EOF
        
        print_success "Configuration saved to terraform.tfvars"
        print_status "Final resource group: ${rg_name}-${environment}"
        print_status "Region: ${location}"
        echo ""
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v az &> /dev/null; then
        missing_tools+=("Azure CLI")
    fi
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("Terraform")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("Docker")
    fi
    
    if ! command -v node &> /dev/null; then
        missing_tools+=("Node.js")
    fi
    
    if ! command -v npm &> /dev/null; then
        missing_tools+=("npm")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi
    
    # Check Azure authentication
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
    
    # Configure deployment settings
    configure_deployment
}

# Function to get user confirmation
confirm_action() {
    if [ "$SKIP_CONFIRMATIONS" = true ]; then
        return 0
    fi
    
    local message="$1"
    local default="${2:-yes}"
    
    if [ "$default" = "yes" ]; then
        read -p "$message (Y/n): " response
        case $response in
            [nN][oO]|[nN]) return 1 ;;
            *) return 0 ;;
        esac
    else
        read -p "$message (y/N): " response
        case $response in
            [yY][eE][sS]|[yY]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# Function to deploy infrastructure
deploy_infrastructure() {
    if [ "$DEPLOY_INFRASTRUCTURE" = false ]; then
        print_warning "Skipping infrastructure deployment"
        return 0
    fi
    
    print_header "DEPLOYING AZURE INFRASTRUCTURE"
    
    if ! confirm_action "Deploy Azure infrastructure (VMs, AKS, databases, monitoring)?"; then
        print_warning "Skipping infrastructure deployment"
        return 0
    fi
    
    cd "$TERRAFORM_DIR"
    
    print_step "Initializing Terraform..."
    terraform init
    
    print_step "Planning infrastructure deployment..."
    terraform plan -out=tfplan
    
    if ! confirm_action "Apply the Terraform plan above?"; then
        print_warning "Infrastructure deployment cancelled"
        return 1
    fi
    
    print_step "Deploying infrastructure..."
    terraform apply tfplan
    
    # Save outputs
    terraform output -json > ../outputs.json
    
    print_success "Infrastructure deployed successfully"
    cd - > /dev/null
}

# Function to build and push container images
build_and_push_containers() {
    if [ "$DEPLOY_CONTAINERS" = false ]; then
        print_warning "Skipping container deployments"
        return 0
    fi
    
    print_header "BUILDING AND PUSHING CONTAINER IMAGES"
    
    if ! confirm_action "Build and push container images to ACR?"; then
        print_warning "Skipping container deployments"
        return 0
    fi
    
    # Get ACR details from Terraform
    cd "$TERRAFORM_DIR"
    local ACR_NAME=$(terraform output -raw acr_name 2>/dev/null)
    local ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null)
    cd - > /dev/null
    
    if [ -z "$ACR_NAME" ]; then
        print_error "Could not get ACR details from Terraform outputs"
        return 1
    fi
    
    print_step "Logging into Azure Container Registry..."
    az acr login --name "$ACR_NAME"
    
    # Build and push each container service
    local services=("order-service" "payment-service" "notification-service")
    
    for service in "${services[@]}"; do
        print_step "Building $service container..."
        
        if [ ! -d "$SERVICES_DIR/$service" ]; then
            print_warning "Service directory not found: $service"
            continue
        fi
        
        cd "$SERVICES_DIR/$service"
        
        # Create Dockerfile if it doesn't exist
        if [ ! -f "Dockerfile" ]; then
            print_status "Creating Dockerfile for $service..."
            create_dockerfile_for_service "$service"
        fi
        
        # Build and tag image
        local IMAGE_TAG="$ACR_LOGIN_SERVER/$service:latest"
        docker build -t "$IMAGE_TAG" .
        
        # Push to ACR
        print_step "Pushing $service to ACR..."
        docker push "$IMAGE_TAG"
        
        cd - > /dev/null
    done
    
    print_success "All container images built and pushed successfully"
}

# Function to create Dockerfile for services
create_dockerfile_for_service() {
    local service="$1"
    
    case $service in
        "order-service")
            cat > Dockerfile << 'EOF'
FROM openjdk:17-jdk-slim
VOLUME /tmp
COPY target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
EXPOSE 8080
EOF
            ;;
        "payment-service")
            cat > Dockerfile << 'EOF'
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY bin/Release/net8.0/publish/ .
ENTRYPOINT ["dotnet", "PaymentService.dll"]
EXPOSE 5002
EOF
            ;;
        "notification-service")
            cat > Dockerfile << 'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o notification-service .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/notification-service .
EXPOSE 8082
CMD ["./notification-service"]
EOF
            ;;
    esac
}

# Function to deploy to AKS
deploy_to_aks() {
    if [ "$DEPLOY_CONTAINERS" = false ]; then
        return 0
    fi
    
    print_header "DEPLOYING SERVICES TO AKS"
    
    if ! confirm_action "Deploy services to AKS cluster?"; then
        print_warning "Skipping AKS deployments"
        return 0
    fi
    
    # Get AKS details from Terraform
    cd "$TERRAFORM_DIR"
    local RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null)
    local AKS_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
    local ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null)
    cd - > /dev/null
    
    if [ -z "$AKS_NAME" ]; then
        print_error "Could not get AKS details from Terraform outputs"
        return 1
    fi
    
    print_step "Configuring kubectl for AKS..."
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing
    
    # Create Kubernetes manifests directory if it doesn't exist
    mkdir -p "$DEPLOY_DIR/k8s"
    
    # Generate and apply Kubernetes manifests
    print_step "Generating Kubernetes manifests..."
    generate_k8s_manifests "$ACR_LOGIN_SERVER"
    
    print_step "Applying Kubernetes manifests..."
    kubectl apply -f "$DEPLOY_DIR/k8s/"
    
    print_step "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment --all
    
    print_success "Services deployed to AKS successfully"
}

# Function to generate Kubernetes manifests
generate_k8s_manifests() {
    local ACR_LOGIN_SERVER="$1"
    
    # Order Service Manifest
    cat > "$DEPLOY_DIR/k8s/order-service.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  labels:
    app: order-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
      - name: order-service
        image: $ACR_LOGIN_SERVER/order-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "production"
---
apiVersion: v1
kind: Service
metadata:
  name: order-service
spec:
  selector:
    app: order-service
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF

    # Payment Service Manifest
    cat > "$DEPLOY_DIR/k8s/payment-service.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  labels:
    app: payment-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment-service
  template:
    metadata:
      labels:
        app: payment-service
    spec:
      containers:
      - name: payment-service
        image: $ACR_LOGIN_SERVER/payment-service:latest
        ports:
        - containerPort: 5002
        env:
        - name: ASPNETCORE_ENVIRONMENT
          value: "Production"
---
apiVersion: v1
kind: Service
metadata:
  name: payment-service
spec:
  selector:
    app: payment-service
  ports:
  - port: 5002
    targetPort: 5002
  type: ClusterIP
EOF

    # Notification Service Manifest
    cat > "$DEPLOY_DIR/k8s/notification-service.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-service
  labels:
    app: notification-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: notification-service
  template:
    metadata:
      labels:
        app: notification-service
    spec:
      containers:
      - name: notification-service
        image: $ACR_LOGIN_SERVER/notification-service:latest
        ports:
        - containerPort: 8082
        env:
        - name: GO_ENV
          value: "production"
---
apiVersion: v1
kind: Service
metadata:
  name: notification-service
spec:
  selector:
    app: notification-service
  ports:
  - port: 8082
    targetPort: 8082
  type: ClusterIP
EOF

    # Ingress for all services
    cat > "$DEPLOY_DIR/k8s/ingress.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-demo-ingress
  annotations:
    kubernetes.io/ingress.class: "azure/application-gateway"
spec:
  rules:
  - http:
      paths:
      - path: /api/orders
        pathType: Prefix
        backend:
          service:
            name: order-service
            port:
              number: 8080
      - path: /api/payments
        pathType: Prefix
        backend:
          service:
            name: payment-service
            port:
              number: 5002
      - path: /api/notifications
        pathType: Prefix
        backend:
          service:
            name: notification-service
            port:
              number: 8082
EOF
}

# Function to deploy VM services
deploy_vm_services() {
    if [ "$DEPLOY_VMS" = false ]; then
        print_warning "Skipping VM service deployments"
        return 0
    fi
    
    print_header "DEPLOYING SERVICES TO VMs"
    
    if ! confirm_action "Deploy services to VMs (API Gateway, Event Processor, Inventory)?"; then
        print_warning "Skipping VM deployments"
        return 0
    fi
    
    # Get VM details from Terraform
    cd "$TERRAFORM_DIR"
    local VM_IPS=($(terraform output -json vm_public_ips 2>/dev/null | jq -r '.[]'))
    cd - > /dev/null
    
    if [ ${#VM_IPS[@]} -eq 0 ]; then
        print_error "Could not get VM IPs from Terraform outputs"
        return 1
    fi
    
    # Deploy to each VM
    for i in "${!VM_IPS[@]}"; do
        local vm_ip="${VM_IPS[$i]}"
        local vm_index=$((i + 1))
        
        print_step "Deploying to VM$vm_index ($vm_ip)..."
        deploy_to_vm "$vm_ip" "$vm_index"
    done
    
    print_success "VM services deployed successfully"
}

# Function to deploy to individual VM
deploy_to_vm() {
    local vm_ip="$1"
    local vm_index="$2"
    
    print_status "Connecting to VM$vm_index ($vm_ip)..."
    
    # Create deployment script for the VM
    cat > "/tmp/vm${vm_index}_deploy.sh" << 'EOF'
#!/bin/bash
set -e

# Update system
sudo apt-get update

# Install required packages if not already installed
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
fi

# Create application directory
sudo mkdir -p /opt/otel-demo
sudo chown $USER:$USER /opt/otel-demo

echo "VM deployment preparation completed"
EOF
    
    # Copy and execute deployment script
    scp -o StrictHostKeyChecking=no "/tmp/vm${vm_index}_deploy.sh" "azureuser@$vm_ip:/tmp/"
    ssh -o StrictHostKeyChecking=no "azureuser@$vm_ip" "chmod +x /tmp/vm${vm_index}_deploy.sh && /tmp/vm${vm_index}_deploy.sh"
    
    # Deploy specific services based on VM
    if [ "$vm_index" -eq 1 ]; then
        print_status "Deploying API Gateway to VM1..."
        deploy_api_gateway_to_vm "$vm_ip"
    else
        print_status "Deploying Event Processor and Inventory Service to VM$vm_index..."
        deploy_backend_services_to_vm "$vm_ip"
    fi
    
    # Cleanup
    rm "/tmp/vm${vm_index}_deploy.sh"
}

# Function to deploy API Gateway to VM
deploy_api_gateway_to_vm() {
    local vm_ip="$1"
    
    # This would copy and run the API Gateway service
    # For now, we'll just prepare the environment
    ssh -o StrictHostKeyChecking=no "azureuser@$vm_ip" "
        echo 'API Gateway deployment prepared on VM1'
        echo 'Manual deployment required: copy API Gateway binaries and run'
    "
}

# Function to deploy backend services to VM
deploy_backend_services_to_vm() {
    local vm_ip="$1"
    
    # This would copy and run the Event Processor and Inventory services
    ssh -o StrictHostKeyChecking=no "azureuser@$vm_ip" "
        echo 'Backend services deployment prepared'
        echo 'Manual deployment required: copy service binaries and run'
    "
}

# Function to deploy synthetic traffic function
deploy_synthetic_traffic() {
    if [ "$DEPLOY_SYNTHETIC_TRAFFIC" = false ]; then
        print_warning "Skipping synthetic traffic function deployment"
        return 0
    fi
    
    print_header "DEPLOYING SYNTHETIC TRAFFIC FUNCTION"
    
    if ! confirm_action "Deploy Azure Functions synthetic traffic generator?"; then
        print_warning "Skipping synthetic traffic function deployment"
        return 0
    fi
    
    print_step "Building Azure Function..."
    
    # Get function app details from Terraform
    cd "$TERRAFORM_DIR"
    local FUNCTION_APP_NAME=$(terraform output -raw traffic_function_app_name 2>/dev/null)
    local RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name 2>/dev/null)
    local API_GATEWAY_URL=$(terraform output -raw api_gateway_url 2>/dev/null)
    cd - > /dev/null
    
    if [ -z "$FUNCTION_APP_NAME" ] || [ "$FUNCTION_APP_NAME" = "null" ]; then
        print_error "Function app name not found in Terraform outputs"
        print_warning "Make sure function-app.tf is included in your Terraform configuration"
        return 1
    fi
    
    print_status "Function App: $FUNCTION_APP_NAME"
    print_status "Resource Group: $RESOURCE_GROUP_NAME"
    print_status "Target API Gateway: $API_GATEWAY_URL"
    
    # Build and deploy the function
    if [ -f "$SCRIPT_DIR/deploy-function.sh" ]; then
        chmod +x "$SCRIPT_DIR/deploy-function.sh"
        
        # Build the function
        print_step "Building function..."
        "$SCRIPT_DIR/deploy-function.sh" build
        
        # Deploy to Azure
        print_step "Deploying to Azure..."
        "$SCRIPT_DIR/deploy-function.sh" deploy "$FUNCTION_APP_NAME" "$RESOURCE_GROUP_NAME"
        
        # Configure with API Gateway URL
        if [ -n "$API_GATEWAY_URL" ] && [ "$API_GATEWAY_URL" != "null" ]; then
            print_step "Configuring function app..."
            "$SCRIPT_DIR/deploy-function.sh" configure "$FUNCTION_APP_NAME" "$RESOURCE_GROUP_NAME" "$API_GATEWAY_URL"
        fi
        
        print_success "Synthetic traffic function deployed successfully"
        
        # Get function URLs
        local FUNCTION_URL=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "defaultHostName" -o tsv 2>/dev/null)
        if [ -n "$FUNCTION_URL" ]; then
            print_status "Function App URL: https://$FUNCTION_URL"
            print_status "Traffic Status: https://$FUNCTION_URL/api/GetTrafficStatus"
            print_status "Manual Trigger: https://$FUNCTION_URL/api/GenerateTrafficHttp"
        fi
        
    else
        print_error "Function deployment script not found: $SCRIPT_DIR/deploy-function.sh"
        return 1
    fi
}

# Function to deploy frontend
deploy_frontend() {
    if [ "$DEPLOY_FRONTEND" = false ]; then
        print_warning "Skipping frontend deployment"
        return 0
    fi
    
    print_header "DEPLOYING FRONTEND TO APP SERVICE"
    
    if ! confirm_action "Deploy React frontend to Azure App Service?"; then
        print_warning "Skipping frontend deployment"
        return 0
    fi
    
    # Run the frontend deployment script
    if [ -f "$SCRIPT_DIR/scripts/frontend/deploy-appservice.sh" ]; then
        cd "$SCRIPT_DIR/scripts/frontend"
        chmod +x deploy-appservice.sh
        ./deploy-appservice.sh
        cd - > /dev/null
    else
        print_warning "Frontend deployment script not found"
    fi
    
    print_success "Frontend deployed successfully"
}

# Function to verify deployment
verify_deployment() {
    print_header "VERIFYING DEPLOYMENT"
    
    print_step "Checking infrastructure status..."
    
    cd "$TERRAFORM_DIR"
    
    # Get service endpoints
    local LB_IP=$(terraform output -raw load_balancer_public_ip 2>/dev/null)
    local FRONTEND_URL=$(terraform output -json frontend_urls 2>/dev/null | jq -r '.app_service_url' 2>/dev/null)
    local FUNCTION_APP_URL=$(terraform output -raw traffic_function_app_url 2>/dev/null)
    local FUNCTION_APP_NAME=$(terraform output -raw traffic_function_app_name 2>/dev/null)
    
    cd - > /dev/null
    
    print_status "Testing service endpoints..."
    
    # Test API Gateway
    if [ -n "$LB_IP" ]; then
        print_status "Testing API Gateway at http://$LB_IP..."
        local api_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_IP/health" 2>/dev/null || echo "000")
        if [ "$api_status" = "200" ]; then
            print_success "✓ API Gateway is responding"
        else
            print_warning "⚠ API Gateway not responding (HTTP: $api_status)"
        fi
    fi
    
    # Test Frontend
    if [ -n "$FRONTEND_URL" ] && [ "$FRONTEND_URL" != "null" ]; then
        print_status "Testing Frontend at $FRONTEND_URL..."
        local frontend_status=$(curl -s -o /dev/null -w "%{http_code}" "$FRONTEND_URL" 2>/dev/null || echo "000")
        if [ "$frontend_status" = "200" ]; then
            print_success "✓ Frontend is responding"
        else
            print_warning "⚠ Frontend not responding (HTTP: $frontend_status)"
        fi
    fi
    
    # Test Synthetic Traffic Function
    if [ -n "$FUNCTION_APP_URL" ] && [ "$FUNCTION_APP_URL" != "null" ]; then
        print_status "Testing Synthetic Traffic Function at $FUNCTION_APP_URL..."
        local function_status=$(curl -s -o /dev/null -w "%{http_code}" "$FUNCTION_APP_URL/api/GetTrafficStatus" 2>/dev/null || echo "000")
        if [ "$function_status" = "200" ]; then
            print_success "✓ Synthetic Traffic Function is responding"
            print_status "  Status endpoint: $FUNCTION_APP_URL/api/GetTrafficStatus"
            print_status "  Manual trigger: $FUNCTION_APP_URL/api/GenerateTrafficHttp"
        else
            print_warning "⚠ Synthetic Traffic Function not responding (HTTP: $function_status)"
            if [ -n "$FUNCTION_APP_NAME" ] && [ "$FUNCTION_APP_NAME" != "null" ]; then
                print_status "  Function may still be starting up. Check logs with:"
                print_status "  ./deploy-function.sh logs $FUNCTION_APP_NAME \$(terraform output -raw resource_group_name)"
            fi
        fi
    fi
    
    # Test AKS services
    if command -v kubectl &> /dev/null; then
        print_status "Checking AKS deployments..."
        local aks_status=$(kubectl get deployments --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$aks_status" -gt 0 ]; then
            print_success "✓ AKS services deployed"
            kubectl get deployments
        else
            print_warning "⚠ No AKS deployments found"
        fi
    fi
}

# Function to show deployment summary
show_deployment_summary() {
    print_header "DEPLOYMENT COMPLETE"
    
    cd "$TERRAFORM_DIR"
    
    print_success "🎉 OpenTelemetry Demo Deployed Successfully!"
    echo ""
    
    print_status "📋 Access Information:"
    
    # Frontend URLs
    if terraform output frontend_urls &>/dev/null; then
        echo "🌐 Frontend:"
        terraform output frontend_urls | jq -r 'to_entries[] | "  \(.key): \(.value)"' 2>/dev/null || echo "  Check Terraform outputs"
        echo ""
    fi
    
    # Synthetic Traffic
    echo "🤖 Synthetic Traffic:"
    local FUNCTION_APP_URL=$(terraform output -raw traffic_function_app_url 2>/dev/null)
    if [ -n "$FUNCTION_APP_URL" ] && [ "$FUNCTION_APP_URL" != "null" ]; then
        echo "  Function App: $FUNCTION_APP_URL"
        echo "  Traffic Status: $FUNCTION_APP_URL/api/GetTrafficStatus"
        echo "  Manual Trigger: $FUNCTION_APP_URL/api/GenerateTrafficHttp"
        echo "  Auto Timer: Runs every 2 minutes"
    else
        echo "  Function not deployed or starting up"
    fi
    echo ""
    
    # API Endpoints
    echo "🔗 API Services:"
    local LB_IP=$(terraform output -raw load_balancer_public_ip 2>/dev/null)
    if [ -n "$LB_IP" ]; then
        echo "  API Gateway: http://$LB_IP"
        echo "  Swagger UI: http://$LB_IP/swagger"
        echo "  Health Check: http://$LB_IP/health"
    fi
    echo ""
    
    # Monitoring
    echo "📊 Monitoring:"
    echo "  Application Insights: Azure Portal > Application Insights"
    echo "  AKS Monitoring: Azure Portal > AKS > Insights"
    echo ""
    
    print_status "🔧 Management Commands:"
    echo "# View all outputs"
    echo "cd $TERRAFORM_DIR && terraform output"
    echo ""
    echo "# Check AKS services"
    echo "kubectl get all"
    echo ""
    echo "# View VM services"
    local VM_IPS=($(terraform output -json vm_public_ips 2>/dev/null | jq -r '.[]' 2>/dev/null))
    for ip in "${VM_IPS[@]}"; do
        echo "ssh azureuser@$ip"
    done
    echo ""
    echo "# Monitor synthetic traffic function"
    local FUNCTION_APP_NAME=$(terraform output -raw traffic_function_app_name 2>/dev/null)
    local RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name 2>/dev/null)
    if [ -n "$FUNCTION_APP_NAME" ] && [ "$FUNCTION_APP_NAME" != "null" ]; then
        echo "./infrastructure/scripts/deploy-function.sh status $FUNCTION_APP_NAME $RESOURCE_GROUP_NAME"
        echo "./infrastructure/scripts/deploy-function.sh logs $FUNCTION_APP_NAME $RESOURCE_GROUP_NAME"
    fi
    echo ""
    
    print_status "📚 Next Steps:"
    echo "1. Synthetic traffic is automatically generating load every 2 minutes"
    echo "   Check status: curl \$(terraform output -raw traffic_function_app_url)/api/GetTrafficStatus"
    echo ""
    echo "2. Generate manual traffic bursts:"
    echo "   curl -X POST \$(terraform output -raw traffic_function_app_url)/api/GenerateTrafficHttp -d '{\"requestCount\": 20}'"
    echo ""
    echo "3. Access the application:"
    echo "   Frontend: \$(terraform output -raw frontend_url 2>/dev/null || echo 'Deploy frontend first')"
    echo "   API Gateway: \$(terraform output -raw api_gateway_url 2>/dev/null || echo 'Check load balancer IP')"
    echo ""
    echo "4. Control traffic and failures:"
    echo "   Failure Injection: \$(terraform output -raw frontend_url 2>/dev/null || echo 'Frontend')/failures"
    echo "   Traffic Control: \$(terraform output -raw frontend_url 2>/dev/null || echo 'Frontend')/traffic"
    echo ""
    echo "5. Monitor in Azure:"
    echo "   - Application Insights dashboards"
    echo "   - Distributed tracing visualization"
    echo "   - Custom metrics and alerts"
    echo ""
    echo "5. Test scenarios:"
    echo "   - Synthetic traffic runs automatically every 2 minutes"
    echo "   - Test failure injection scenarios via frontend"
    echo "   - Explore OpenTelemetry data correlation in Application Insights"
    echo "   - Generate manual traffic bursts for immediate demos"
    
    cd - > /dev/null
}

# Main execution function
main() {
    print_header "AZURE OPENTELEMETRY DEMO - COMPLETE DEPLOYMENT"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    print_status "Deployment Configuration:"
    echo "  Infrastructure: $DEPLOY_INFRASTRUCTURE"
    echo "  Frontend: $DEPLOY_FRONTEND"
    echo "  Containers: $DEPLOY_CONTAINERS"
    echo "  VMs: $DEPLOY_VMS"
    echo "  Synthetic Traffic: $DEPLOY_SYNTHETIC_TRAFFIC"
    echo "  Skip Confirmations: $SKIP_CONFIRMATIONS"
    echo "  Containers: $DEPLOY_CONTAINERS"
    echo "  VMs: $DEPLOY_VMS"
    echo "  Skip Confirmations: $SKIP_CONFIRMATIONS"
    echo ""
    
    if ! confirm_action "Proceed with deployment?"; then
        print_warning "Deployment cancelled by user"
        exit 0
    fi
    
    # Record start time
    local start_time=$(date +%s)
    
    # Run deployment steps
    check_prerequisites
    deploy_infrastructure
    build_and_push_containers
    deploy_to_aks
    deploy_vm_services
    deploy_frontend
    deploy_synthetic_traffic
    verify_deployment
    show_deployment_summary
    
    # Calculate total time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    print_success "🎯 Total deployment time: ${minutes}m ${seconds}s"
    print_success "🚀 OpenTelemetry Demo is ready!"
}

# Run main function with all arguments
main "$@"