# Frontend App Service Deployment

This directory contains scripts for deploying the React frontend to Azure App Service.

## Prerequisites

1. **Infrastructure Deployed**: Run `../deploy.sh` first to create Azure resources
2. **Azure CLI**: Authenticated to your subscription
3. **Node.js & npm**: For building the React application
4. **PowerShell** (Windows) or **Bash** (Linux/macOS)

## Quick Deploy

### Windows:
```cmd
deploy-appservice.bat
```

### Linux/macOS:
```bash
chmod +x deploy-appservice.sh
./deploy-appservice.sh
```

## What the Script Does

### 🔍 **Pre-deployment Checks:**
- Verifies Azure CLI authentication
- Checks Node.js and npm installation
- Validates Terraform infrastructure exists
- Retrieves all service endpoints from Terraform outputs

### 🏗️ **Build Process:**
- Creates production environment configuration
- Installs npm dependencies
- Builds React application for production
- Optimizes bundle for Azure App Service

### 📦 **Deployment Package:**
- Creates Express.js server for App Service hosting
- Adds web.config for IIS URL rewriting (SPA routing)
- Generates package.json with dependencies
- Creates deployment ZIP package

### 🚀 **Azure Deployment:**
- Deploys to App Service using Azure CLI
- Configures environment variables
- Verifies deployment success
- Provides access URLs and management commands

## Configuration

The script automatically configures these environment variables:

```javascript
// API Endpoints (from Terraform outputs)
REACT_APP_API_GATEWAY_URL=http://[load-balancer-ip]
REACT_APP_ORDER_SERVICE_URL=http://[aks-fqdn]/api/orders
REACT_APP_PAYMENT_SERVICE_URL=http://[aks-fqdn]/api/payments
REACT_APP_INVENTORY_SERVICE_URL=http://[vm2-ip]:3000
REACT_APP_EVENT_PROCESSOR_URL=http://[vm2-ip]:8001
REACT_APP_NOTIFICATION_SERVICE_URL=http://[aks-fqdn]/api/notifications

// Application Insights
REACT_APP_APPINSIGHTS_INSTRUMENTATIONKEY=[ai-key]
REACT_APP_APPINSIGHTS_CONNECTION_STRING=[ai-connection]
```

## Post-Deployment

After successful deployment, you'll get:

### **🌐 Access URLs:**
- **Primary Frontend**: `https://[app-name].azurewebsites.net`
- **API Gateway**: `http://[load-balancer-ip]`
- **Swagger UI**: `http://[load-balancer-ip]/swagger`

### **📊 Monitoring:**
- Application Insights dashboard
- App Service logs and metrics
- Real-time application telemetry

### **🔧 Management Commands:**
```bash
# View real-time logs
az webapp log tail --resource-group [rg-name] --name [app-name]

# Restart the app
az webapp restart --resource-group [rg-name] --name [app-name]

# Open in browser
start https://[app-name].azurewebsites.net
```

## Troubleshooting

### **Build Errors:**
- Ensure Node.js 16+ is installed
- Clear npm cache: `npm cache clean --force`
- Delete node_modules and reinstall: `rm -rf node_modules && npm install`

### **Deployment Errors:**
- Check Azure CLI authentication: `az account show`
- Verify App Service exists: Check Terraform outputs
- Check resource group permissions

### **Runtime Errors:**
- Check App Service logs in Azure Portal
- Verify environment variables are set
- Test backend service connectivity

### **CORS Issues:**
- Ensure API Gateway allows frontend domain
- Check network security group rules
- Verify service endpoints are accessible

## Advanced Configuration

### **Custom Environment:**
Create `.env.custom` file in frontend directory:
```bash
REACT_APP_CUSTOM_API_URL=https://my-custom-api.com
REACT_APP_FEATURE_FLAG=enabled
```

### **Build Optimization:**
Modify the script to add build optimizations:
```bash
# Add to build command
npm run build -- --production --optimization
```

### **Multiple Environments:**
Create environment-specific scripts:
- `deploy-appservice-dev.sh`
- `deploy-appservice-staging.sh`
- `deploy-appservice-prod.sh`

## CI/CD Integration

### **GitHub Actions Example:**
```yaml
- name: Deploy to App Service
  run: |
    cd infrastructure/scripts/frontend
    chmod +x deploy-appservice.sh
    ./deploy-appservice.sh
  env:
    AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
    AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

### **Azure DevOps Pipeline:**
```yaml
- script: |
    cd infrastructure/scripts/frontend
    ./deploy-appservice.sh
  displayName: 'Deploy Frontend to App Service'
```

This deployment script provides a complete, automated solution for deploying your React frontend to Azure App Service with proper configuration and monitoring! 🚀