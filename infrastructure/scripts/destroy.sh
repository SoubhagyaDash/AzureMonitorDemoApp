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

# Function to confirm destruction
confirm_destruction() {
    echo "================================================"
    echo "   DESTRUCTIVE OPERATION WARNING"
    echo "================================================"
    echo ""
    print_warning "This will PERMANENTLY DELETE ALL RESOURCES in the deployment!"
    echo ""
    print_status "Resources that will be destroyed:"
    echo "• AKS cluster and all workloads"
    echo "• Virtual machines and disks"
    echo "• Databases (SQL Server, Cosmos DB)"
    echo "• Storage accounts and data"
    echo "• Container registry and images"
    echo "• EventHub namespaces and data"
    echo "• Redis cache and data"
    echo "• Networking components"
    echo "• Monitoring and log data"
    echo ""
    
    # Show current resources
    cd "$TERRAFORM_DIR"
    if [ -f "terraform.tfstate" ]; then
        print_status "Current deployed resources:"
        terraform show -json | jq -r '.values.root_module.resources[].address' 2>/dev/null | sort || echo "Could not list resources"
        echo ""
    fi
    
    # Multiple confirmations for safety
    read -p "Type 'yes' to confirm you want to destroy all resources: " confirm1
    if [ "$confirm1" != "yes" ]; then
        print_warning "Destruction cancelled"
        exit 0
    fi
    
    read -p "Type 'DESTROY' to confirm again: " confirm2
    if [ "$confirm2" != "DESTROY" ]; then
        print_warning "Destruction cancelled"
        exit 0
    fi
    
    print_warning "Starting destruction in 10 seconds... Press Ctrl+C to cancel"
    sleep 10
}

# Function to backup state before destruction
backup_state() {
    print_status "Creating state backup..."
    
    if [ -f "terraform.tfstate" ]; then
        cp terraform.tfstate "terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "State backup created"
    fi
    
    if [ -f "../outputs.json" ]; then
        cp ../outputs.json "../outputs.backup.$(date +%Y%m%d_%H%M%S).json"
        print_success "Outputs backup created"
    fi
}

# Function to destroy resources
destroy_resources() {
    print_status "Destroying infrastructure..."
    
    # Start timer
    start_time=$(date +%s)
    
    # Plan destruction first
    terraform plan -destroy -out=destroy.tfplan
    
    if [ $? -ne 0 ]; then
        print_error "Terraform destroy plan failed"
        exit 1
    fi
    
    # Apply destruction
    terraform apply destroy.tfplan
    
    if [ $? -eq 0 ]; then
        # Calculate destruction time
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        minutes=$((duration / 60))
        seconds=$((duration % 60))
        
        print_success "Infrastructure destroyed successfully in ${minutes}m ${seconds}s"
        
        # Clean up plan file
        rm -f destroy.tfplan
        
    else
        print_error "Terraform destroy failed"
        print_warning "Some resources may still exist. Check Azure portal and run destroy again if needed."
        exit 1
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    print_status "Cleaning up local files..."
    
    # Ask before cleaning local files
    read -p "Do you want to clean up local Terraform files? (yes/no): " cleanup_confirm
    
    if [ "$cleanup_confirm" = "yes" ]; then
        # Remove terraform files but keep backups
        rm -f terraform.tfvars
        rm -f tfplan
        rm -f .terraform.lock.hcl
        rm -rf .terraform/
        rm -f ../outputs.json
        
        print_success "Local files cleaned up"
    else
        print_warning "Local files preserved"
    fi
}

# Function to verify destruction
verify_destruction() {
    print_status "Verifying resource destruction..."
    
    # Check if any resources still exist
    if [ -f "terraform.tfstate" ]; then
        REMAINING_RESOURCES=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources | length' 2>/dev/null || echo "0")
        
        if [ "$REMAINING_RESOURCES" -gt 0 ]; then
            print_warning "$REMAINING_RESOURCES resources may still exist"
            print_status "Run 'terraform show' to see remaining resources"
        else
            print_success "All resources destroyed successfully"
        fi
    fi
}

# Function to show cost savings
show_cost_savings() {
    print_status "Cost Impact"
    echo "==============="
    print_success "The following resources have been destroyed, stopping charges:"
    echo "• AKS cluster nodes (compute charges)"
    echo "• Virtual machines (compute and storage)"
    echo "• SQL Database (database charges)"
    echo "• Cosmos DB (throughput charges)"
    echo "• Redis Cache (memory charges)"
    echo "• EventHub (messaging charges)"
    echo "• Log Analytics (data ingestion charges)"
    echo ""
    print_warning "Note: Some minimal charges may continue for:"
    echo "• Storage accounts (if data remains)"
    echo "• Reserved capacity (if applicable)"
    echo "• Log Analytics (data retention)"
}

# Function to provide next steps
show_next_steps() {
    print_status "Next Steps:"
    echo "1. Verify in Azure Portal that all resources are destroyed"
    echo "2. Check for any orphaned resources in resource groups"
    echo "3. Review Azure billing to confirm charges have stopped"
    echo "4. Clean up any external resources (DNS, certificates, etc.)"
    echo ""
    print_status "To redeploy:"
    echo "Run './deploy.sh' from the scripts directory"
}

# Main execution
main() {
    echo "================================================"
    echo "   Azure OpenTelemetry Demo Infrastructure"
    echo "             Destruction Script"
    echo "================================================"
    echo ""
    
    # Change to terraform directory
    cd "$TERRAFORM_DIR"
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        print_error "Terraform not initialized. Nothing to destroy."
        exit 1
    fi
    
    # Check if state exists
    if [ ! -f "terraform.tfstate" ]; then
        print_warning "No terraform state found. Infrastructure may already be destroyed."
        exit 0
    fi
    
    # Run destruction steps
    confirm_destruction
    backup_state
    destroy_resources
    verify_destruction
    cleanup_local_files
    show_cost_savings
    show_next_steps
    
    print_success "Destruction completed!"
}

# Run main function
main "$@"