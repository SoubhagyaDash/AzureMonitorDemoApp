#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="../terraform"
RESOURCE_GROUP=""
LOCATION="East US"
ENVIRONMENT="dev"

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
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is not installed. Install it to manage AKS cluster."
    fi
    
    print_success "Prerequisites check completed"
}

# Function to get user inputs
get_user_inputs() {
    print_status "Getting deployment configuration..."
    
    # Get subscription
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_status "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Get resource group name
    read -p "Enter resource group name (default: rg-otel-demo-dev): " input_rg
    RESOURCE_GROUP=${input_rg:-rg-otel-demo-dev}
    
    # Get location
    read -p "Enter Azure location (default: East US): " input_location
    LOCATION=${input_location:-"East US"}
    
    # Get environment
    read -p "Enter environment (dev/staging/prod) (default: dev): " input_env
    ENVIRONMENT=${input_env:-dev}
    
    print_success "Configuration collected"
}

# Function to initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    cd "$TERRAFORM_DIR"
    
    terraform init
    
    if [ $? -eq 0 ]; then
        print_success "Terraform initialized successfully"
    else
        print_error "Terraform initialization failed"
        exit 1
    fi
}

# Function to create terraform.tfvars
create_tfvars() {
    print_status "Creating terraform.tfvars file..."
    
    cat > terraform.tfvars << EOF
resource_group_name = "$RESOURCE_GROUP"
location           = "$LOCATION"
environment        = "$ENVIRONMENT"
project_name       = "otel-demo"

# AKS Configuration
aks_node_count     = 3
aks_vm_size        = "Standard_D2s_v3"
kubernetes_version = "1.28"

# VM Configuration
vm_count      = 2
vm_size       = "Standard_D2s_v3"
admin_username = "azureuser"

# Database Configuration
sql_sku_name = "S1"
sql_admin_username = "sqladmin"

# Redis Configuration
redis_sku_name = "Standard"
redis_family   = "C"
redis_capacity = 1

# Cosmos DB Configuration
cosmos_consistency_level = "Session"
cosmos_throughput       = 400

# EventHub Configuration
eventhub_partition_count    = 4
eventhub_message_retention = 1

# Monitoring Configuration
log_analytics_retention_days = 30
application_insights_type    = "web"

# Tags
tags = {
  Project     = "OpenTelemetry Demo"
  Environment = "$ENVIRONMENT"
  Owner       = "Platform Team"
  Purpose     = "Azure Monitor OTel Showcase"
  CostCenter  = "Engineering"
  DeployedBy  = "$(whoami)"
  DeployedAt  = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    print_success "terraform.tfvars created"
}

# Function to plan deployment
plan_deployment() {
    print_status "Planning Terraform deployment..."
    
    terraform plan -out=tfplan
    
    if [ $? -eq 0 ]; then
        print_success "Terraform plan completed successfully"
        
        # Ask for confirmation
        echo ""
        print_warning "Please review the plan above carefully."
        read -p "Do you want to proceed with the deployment? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            print_warning "Deployment cancelled by user"
            exit 0
        fi
    else
        print_error "Terraform plan failed"
        exit 1
    fi
}

# Function to apply deployment
apply_deployment() {
    print_status "Applying Terraform deployment..."
    
    # Start timer
    start_time=$(date +%s)
    
    terraform apply tfplan
    
    if [ $? -eq 0 ]; then
        # Calculate deployment time
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        minutes=$((duration / 60))
        seconds=$((duration % 60))
        
        print_success "Infrastructure deployed successfully in ${minutes}m ${seconds}s"
        
        # Save outputs
        terraform output -json > ../outputs.json
        print_success "Outputs saved to ../outputs.json"
        
    else
        print_error "Terraform apply failed"
        exit 1
    fi
}

# Function to configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl for AKS..."
    
    if command -v kubectl &> /dev/null; then
        AKS_NAME=$(terraform output -raw aks_cluster_name)
        RG_NAME=$(terraform output -raw resource_group_name)
        
        az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing
        
        if [ $? -eq 0 ]; then
            print_success "kubectl configured successfully"
            
            # Test connection
            kubectl get nodes
            if [ $? -eq 0 ]; then
                print_success "Successfully connected to AKS cluster"
            else
                print_warning "Could not connect to AKS cluster. Check your configuration."
            fi
        else
            print_warning "Failed to configure kubectl"
        fi
    else
        print_warning "kubectl not installed. Skipping AKS configuration."
    fi
}

# Function to display deployment summary
display_summary() {
    print_status "Deployment Summary"
    echo "===================="
    
    # Get outputs
    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "N/A")
    AKS_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "N/A")
    LB_IP=$(terraform output -raw load_balancer_public_ip 2>/dev/null || echo "N/A")
    VM_IPS=$(terraform output -json vm_public_ips 2>/dev/null | jq -r '.[]' | tr '\n' ' ' || echo "N/A")
    
    echo "Resource Group: $RG_NAME"
    echo "AKS Cluster: $AKS_NAME"
    echo "Load Balancer IP: $LB_IP"
    echo "VM Public IPs: $VM_IPS"
    echo ""
    
    print_success "🌐 Frontend Access URLs:"
    terraform output frontend_urls 2>/dev/null || echo "Frontend URLs not available"
    echo ""
    
    print_success "🔗 Application Access:"
    terraform output application_access_guide 2>/dev/null || echo "Access guide not available"
    echo ""
    
    print_status "Next Steps:"
    echo "1. Deploy frontend code to your chosen hosting option:"
    echo "   • App Service: ./frontend/deploy-appservice.sh"
    echo "   • Static Web App: Deploy via GitHub Actions"
    echo "   • VM Hosting: SSH and deploy manually"
    echo "2. Build and deploy container images to ACR"
    echo "3. Deploy applications to AKS using Kubernetes manifests"
    echo "4. Configure VMs with application services"
    echo "5. Test the complete application flow"
    echo ""
    
    print_status "📋 Quick Access Commands:"
    echo "# Primary Frontend URL"
    echo "echo \$(terraform output -raw frontend_urls | jq -r '.app_service_url')"
    echo ""
    echo "# API Gateway Swagger"
    echo "echo \"http://\$(terraform output -raw load_balancer_public_ip)/swagger\""
    echo ""
    echo "# Application Insights Dashboard"
    echo "terraform output application_access_guide | jq -r '.monitoring_dashboard'"
    echo ""
    
    print_status "� Quick Deploy Frontend:"
    echo "cd infrastructure/scripts/frontend"
    echo "./deploy-appservice.sh    # Deploy to Azure App Service"
    echo ""
    
    print_status "�🔧 Development Commands:"
    echo "# Connect to VMs"
    if [ "$VM_IPS" != "N/A" ]; then
        for ip in $VM_IPS; do
            echo "ssh azureuser@$ip"
        done
    fi
    echo ""
    echo "# Configure kubectl for AKS"
    echo "az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME"
    echo ""
    echo "# View AKS cluster"
    echo "kubectl get all --all-namespaces"
}

# Function to handle cleanup on error
cleanup_on_error() {
    print_error "Deployment failed. You may want to clean up resources."
    print_warning "To destroy created resources, run:"
    echo "cd $TERRAFORM_DIR && terraform destroy"
}

# Main execution
main() {
    echo "================================================"
    echo "   Azure OpenTelemetry Demo Infrastructure"
    echo "             Deployment Script"
    echo "================================================"
    echo ""
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    get_user_inputs
    init_terraform
    create_tfvars
    plan_deployment
    apply_deployment
    configure_kubectl
    display_summary
    
    print_success "Deployment completed successfully!"
}

# Run main function
main "$@"