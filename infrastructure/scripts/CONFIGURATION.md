# Configuration Guide: Customizing Resource Group and Region

This guide shows you how to customize the resource group name and Azure region for your OpenTelemetry demo deployment.

## 🎯 Quick Start Options

### Option 1: Environment Variables (Simplest)

**Windows PowerShell:**
```powershell
# Set your preferences
$env:TF_VAR_resource_group_name = "rg-my-otel-demo"
$env:TF_VAR_location = "West US 2"
$env:TF_VAR_environment = "production"

# Deploy
.\infrastructure\scripts\deploy-complete.bat
```

**Linux/macOS:**
```bash
# Set your preferences
export TF_VAR_resource_group_name="rg-my-otel-demo"
export TF_VAR_location="West US 2"
export TF_VAR_environment="production"

# Deploy
./infrastructure/scripts/deploy-complete.sh
```

### Option 2: Configuration File (Best for Teams)

1. **Copy the example configuration:**
   ```bash
   cd infrastructure/terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   ```hcl
   # Your custom configuration
   resource_group_name = "rg-ignite-otel-demo"
   location           = "Central US"
   environment        = "demo"
   project_name       = "ignite-showcase"
   
   tags = {
     Project     = "Ignite OpenTelemetry Demo"
     Environment = "Demo"
     Owner       = "Your Name"
     Event       = "Microsoft Ignite"
   }
   ```

3. **Deploy normally:**
   ```bash
   ./infrastructure/scripts/deploy-complete.sh
   ```

### Option 3: Interactive Configuration (Enhanced)

The deployment script will now prompt you for configuration if no `terraform.tfvars` exists:

```bash
./infrastructure/scripts/deploy-complete.sh

# You'll be prompted for:
# - Resource Group Name
# - Azure Region  
# - Environment
```

## 🌍 Popular Azure Regions

| Region | Location Code |
|--------|---------------|
| East US | `East US` |
| West US 2 | `West US 2` |
| Central US | `Central US` |
| West Europe | `West Europe` |
| North Europe | `North Europe` |
| Southeast Asia | `Southeast Asia` |
| Australia East | `Australia East` |
| Canada Central | `Canada Central` |
| UK South | `UK South` |
| Japan East | `Japan East` |

## 📝 Example Configurations

### For Microsoft Ignite Demo:
```hcl
resource_group_name = "rg-ignite-otel-demo"
location           = "East US"
environment        = "ignite"
project_name       = "ignite-otel-showcase"
```

### For Production Showcase:
```hcl
resource_group_name = "rg-otel-production"
location           = "West US 2"
environment        = "prod"
project_name       = "otel-enterprise-demo"
```

### For Development/Testing:
```hcl
resource_group_name = "rg-otel-dev"
location           = "Central US"
environment        = "dev"
project_name       = "otel-testing"
```

## 🔧 Advanced Customization

You can also override other settings in `terraform.tfvars`:

```hcl
# Resource sizing
aks_node_count = 5
aks_vm_size = "Standard_D4s_v3"
vm_size = "Standard_D4s_v3"

# Monitoring retention
log_analytics_retention_days = 180

# Database configuration
sql_sku_name = "S2"
cosmos_throughput = 800

# Tags
tags = {
  Project     = "Your Project Name"
  Environment = "Your Environment"
  Owner       = "Your Team"
  CostCenter  = "Your Cost Center"
  Purpose     = "OpenTelemetry Demonstration"
}
```

## 🚀 Quick Deploy Examples

**For Ignite Demo:**
```powershell
$env:TF_VAR_resource_group_name = "rg-ignite-otel"
$env:TF_VAR_location = "East US"
.\infrastructure\scripts\deploy-complete.bat --yes
```

**For Production Showcase:**
```bash
export TF_VAR_resource_group_name="rg-otel-enterprise"
export TF_VAR_location="West US 2"
export TF_VAR_environment="production"
./infrastructure/scripts/deploy-complete.sh --yes
```

The final resource group name will be: `{resource_group_name}-{environment}`

Example: `rg-ignite-otel-demo` becomes `rg-ignite-otel-demo-ignite`