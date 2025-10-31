# Azure Infrastructure Scripts

This directory contains scripts for deploying and managing the Azure infrastructure for the OpenTelemetry demo application.

## Scripts Overview

### `deploy.sh`
Complete infrastructure deployment script that:
- Checks prerequisites (Azure CLI, Terraform, kubectl)
- Guides through configuration
- Initializes and deploys Terraform infrastructure
- Configures kubectl for AKS access
- Provides deployment summary and next steps

### `destroy.sh`
Safe infrastructure destruction script that:
- Confirms destruction with multiple prompts
- Creates backups of state and outputs
- Destroys all resources
- Cleans up local files
- Provides cost impact summary

## Prerequisites

1. **Azure CLI** - Authenticated to your Azure subscription
2. **Terraform** - Version 1.5 or later
3. **kubectl** - For AKS cluster management (optional)
4. **jq** - For JSON processing in scripts

## Quick Start

### Deploy Infrastructure
```bash
# Make scripts executable
chmod +x *.sh

# Run deployment
./deploy.sh
```

The script will guide you through:
1. Configuration selection
2. Resource planning
3. Deployment confirmation
4. Post-deployment setup

### Destroy Infrastructure
```bash
# Run destruction (BE CAREFUL!)
./destroy.sh
```

**Warning**: This permanently deletes all resources and data.

## Script Features

### Safety Features
- Multiple confirmation prompts for destruction
- State file backups before changes
- Error handling and cleanup
- Resource verification steps

### User Experience
- Colored output for better readability
- Progress indicators and timers
- Clear error messages and suggestions
- Comprehensive summaries

### Automation Support
- Environment variable support
- Exit codes for CI/CD integration
- JSON output preservation
- Unattended operation options

## Customization

### Environment Variables
```bash
export TF_VAR_resource_group_name="my-custom-rg"
export TF_VAR_location="West US 2"
export TF_VAR_environment="staging"
```

### Script Modification
Key configuration variables at the top of each script:
```bash
TERRAFORM_DIR="../terraform"
RESOURCE_GROUP=""
LOCATION="East US"
ENVIRONMENT="dev"
```

## Integration with CI/CD

### GitHub Actions Example
```yaml
- name: Deploy Infrastructure
  run: |
    cd infrastructure/scripts
    chmod +x deploy.sh
    # Set environment variables for automation
    export AUTO_APPROVE=true
    ./deploy.sh
```

### Azure DevOps Pipeline
```yaml
- script: |
    cd infrastructure/scripts
    chmod +x deploy.sh
    ./deploy.sh
  displayName: 'Deploy Infrastructure'
  env:
    ARM_CLIENT_ID: $(ARM_CLIENT_ID)
    ARM_CLIENT_SECRET: $(ARM_CLIENT_SECRET)
    ARM_SUBSCRIPTION_ID: $(ARM_SUBSCRIPTION_ID)
    ARM_TENANT_ID: $(ARM_TENANT_ID)
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check Azure login
   az account show
   
   # Verify permissions
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   ```

2. **Terraform State Issues**
   ```bash
   # Refresh state
   terraform refresh
   
   # Import existing resources if needed
   terraform import azurerm_resource_group.main /subscriptions/.../resourceGroups/...
   ```

3. **Network Connectivity**
   ```bash
   # Test Azure connectivity
   az account list-locations
   
   # Check Terraform provider
   terraform providers
   ```

### Debug Mode
Enable detailed logging:
```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log
./deploy.sh
```

### Manual Recovery
If scripts fail, you can continue manually:
```bash
cd ../terraform
terraform init
terraform plan
terraform apply
```

## Security Considerations

### Sensitive Data
- Passwords are randomly generated and marked sensitive
- Connection strings are stored in outputs but not displayed
- State files contain sensitive information - secure appropriately

### Access Control
- Use Azure RBAC for fine-grained permissions
- Consider using service principals for automation
- Implement just-in-time access for production

### Network Security
- VMs use Network Security Groups with minimal required ports
- AKS uses private networking where possible
- Databases have firewall rules restricting access

## Cost Management

### Development Optimization
Scripts deploy cost-optimized resources for development:
- Smaller VM sizes
- Lower-tier database SKUs
- Minimal Redis capacity
- Basic monitoring retention

### Production Considerations
For production, modify variables:
- Increase VM sizes and counts
- Use Premium storage
- Enable zone redundancy
- Extend monitoring retention

### Cost Monitoring
After deployment:
1. Set up Azure Cost Management alerts
2. Review cost allocation by tags
3. Use Azure Advisor recommendations
4. Regular cost reviews

## Support

For issues with the scripts:
1. Check script output and error messages
2. Review Terraform logs
3. Verify Azure permissions and quotas
4. Consult Azure documentation
5. Contact platform team