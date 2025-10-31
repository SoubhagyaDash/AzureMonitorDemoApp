# Azure OpenTelemetry Demo Infrastructure

This Terraform configuration creates the complete Azure infrastructure needed for the OpenTelemetry demonstration application.

## Architecture Overview

The infrastructure includes:

- **Azure Kubernetes Service (AKS)** - For containerized services (Order, Payment, Notification services)
- **Virtual Machines** - For VM-hosted services (API Gateway, Event Processor, Inventory Service)
- **Azure Container Registry** - For storing container images
- **EventHub** - For event streaming and messaging
- **SQL Database** - For order and payment data storage
- **Cosmos DB** - For event store and analytics
- **Redis Cache** - For distributed caching
- **Application Insights** - For monitoring and telemetry
- **Log Analytics** - For centralized logging
- **Virtual Network** - For secure networking between components

## Prerequisites

1. **Azure CLI** - Install and login to Azure
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Terraform** - Install Terraform v1.5 or later
   ```bash
   terraform version
   ```

3. **Service Principal** (recommended for production)
   ```bash
   az ad sp create-for-rbac --name "terraform-otel-demo" --role="Contributor" --scopes="/subscriptions/YOUR_SUBSCRIPTION_ID"
   ```

## Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd infrastructure/terraform
   ```

2. **Copy and customize variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferred values
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   ```

4. **Plan the deployment**
   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure**
   ```bash
   terraform apply
   ```

6. **Save important outputs**
   ```bash
   terraform output -json > ../outputs.json
   ```

## Configuration

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `resource_group_name` | Resource group name | `rg-otel-demo` |
| `location` | Azure region | `East US` |
| `environment` | Environment (dev/staging/prod) | `dev` |
| `aks_node_count` | Number of AKS nodes | `3` |
| `vm_count` | Number of VMs | `2` |

### Environment-Specific Configuration

For different environments, create separate `.tfvars` files:

- `dev.tfvars` - Development environment
- `staging.tfvars` - Staging environment  
- `prod.tfvars` - Production environment

Deploy with:
```bash
terraform apply -var-file="dev.tfvars"
```

## Security Considerations

### Network Security
- VMs are deployed in a dedicated subnet with Network Security Groups
- AKS uses Azure CNI with network policies
- All databases have firewall rules restricting access

### Access Control
- AKS uses managed identity and Azure AD integration
- Container Registry uses admin credentials (consider service principals for production)
- Secrets are marked as sensitive in Terraform outputs

### Monitoring
- Azure Monitor agents are installed on VMs
- AKS has Container Insights enabled
- All resources send logs to Log Analytics workspace

## Resource Naming

Resources follow Azure naming conventions:
- `{resource-type}-{project-name}-{environment}-{random-suffix}`
- Example: `aks-otel-demo-dev-abc123`

## Outputs

After deployment, retrieve connection strings and endpoints:

```bash
# Get all outputs
terraform output

# Get specific sensitive output
terraform output -raw sql_admin_password

# Get connection strings for app configuration
terraform output connection_strings
```

## Post-Deployment Steps

1. **Configure kubectl for AKS**
   ```bash
   az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_cluster_name)
   ```

2. **Connect to VMs**
   ```bash
   ssh azureuser@$(terraform output -raw vm_public_ips | jq -r '.[0]')
   ```

3. **Configure application secrets**
   - Update application configuration files with connection strings
   - Deploy applications using CI/CD pipelines

## Cost Management

### Development Environment
- Uses smaller VM sizes (Standard_D2s_v3)
- SQL Database S1 tier
- Redis Standard C1
- Cosmos DB with 400 RU/s

### Cost Optimization Tips
- Use `terraform destroy` when not in use
- Consider Azure Dev/Test pricing for non-production
- Monitor costs with Azure Cost Management

## Troubleshooting

### Common Issues

1. **Terraform state conflicts**
   ```bash
   terraform refresh
   terraform plan
   ```

2. **Resource naming conflicts**
   - Random suffix is generated to avoid conflicts
   - If needed, run `terraform taint random_string.suffix`

3. **Permission errors**
   - Ensure proper Azure RBAC permissions
   - Check service principal permissions

### Debugging

Enable Terraform logging:
```bash
export TF_LOG=DEBUG
terraform apply
```

View Azure Activity Log for resource creation issues.

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Warning**: This will permanently delete all resources and data.

## Production Considerations

### Backend Configuration
Uncomment and configure remote backend in `backend.tf`:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "terraformstate"
    container_name      = "tfstate"
    key                 = "otel-demo.tfstate"
  }
}
```

### High Availability
- Enable zone redundancy for databases
- Use multiple AKS node pools
- Configure load balancer health probes

### Security
- Use Key Vault for secrets management
- Enable private endpoints for databases
- Implement network segmentation

### Monitoring
- Configure alert rules
- Set up automated responses
- Enable diagnostic settings

## Support

For issues and questions:
1. Check Azure Resource Health
2. Review Terraform logs
3. Consult Azure documentation
4. Contact platform team