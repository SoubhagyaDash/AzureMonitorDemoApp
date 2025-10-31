# Frontend Deployment Guide

After your Azure infrastructure is deployed, you have multiple options for accessing the frontend application.

## 🚀 **Frontend Access Options**

### **Option 1: Azure App Service (Recommended for Demo)**
**URL**: Retrieved from Terraform output `frontend_urls.app_service_url`

```bash
# Get the App Service URL
terraform output frontend_urls
```

**Features:**
- ✅ Automatic HTTPS
- ✅ Built-in CI/CD integration
- ✅ Application Insights pre-configured
- ✅ Environment variables set for all backend services

### **Option 2: Azure Static Web App (Best for Production)**
**URL**: Retrieved from Terraform output `frontend_urls.static_web_app_url`

```bash
# Get the Static Web App URL
terraform output frontend_urls
```

**Features:**
- ✅ Global CDN distribution
- ✅ Built-in authentication
- ✅ GitHub Actions integration
- ✅ Cost-effective for static content

### **Option 3: Load Balancer (VM-hosted)**
**URL**: `http://<load-balancer-ip>:3000`

```bash
# Get the load balancer IP
terraform output load_balancer_public_ip
```

**Features:**
- ✅ Direct VM hosting
- ✅ Full control over environment
- ✅ Suitable for development/testing

### **Option 4: Direct VM Access**
**URL**: `http://<vm-ip>:3000`

```bash
# Get VM IPs
terraform output vm_public_ips
```

## 📋 **Post-Deployment Steps**

### **1. Deploy Frontend Code**

#### **For App Service:**
```bash
# Build the React app
cd services/frontend
npm install
npm run build

# Deploy to App Service (using Azure CLI)
az webapp deployment source config-zip \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw frontend_urls | jq -r '.app_service_url' | sed 's/https:\/\///') \
  --src build.zip
```

#### **For Static Web App:**
```bash
# Deploy using Static Web Apps CLI
cd services/frontend
npm install
npm run build

# Deploy to Static Web App
swa deploy ./build \
  --app-name $(terraform output -raw frontend_urls | jq -r '.static_web_app_url' | sed 's/https:\/\/\(.*\)\..*$/\1/')
```

#### **For VM Hosting:**
```bash
# SSH to the VM
ssh azureuser@$(terraform output -raw vm_public_ips | jq -r '.[0]')

# On the VM, clone and build
git clone <your-repo-url> /opt/otel-demo
cd /opt/otel-demo/services/frontend
npm install
npm run build
npm start
```

### **2. Configure Environment Variables**

The infrastructure automatically sets these environment variables for App Service:

```javascript
REACT_APP_API_GATEWAY_URL=http://<load-balancer-ip>
REACT_APP_ORDER_SERVICE_URL=http://<aks-fqdn>/api/orders
REACT_APP_PAYMENT_SERVICE_URL=http://<aks-fqdn>/api/payments
REACT_APP_INVENTORY_SERVICE_URL=http://<vm2-ip>:3000
REACT_APP_EVENT_PROCESSOR_URL=http://<vm2-ip>:8001
REACT_APP_NOTIFICATION_SERVICE_URL=http://<aks-fqdn>/api/notifications
APPLICATIONINSIGHTS_CONNECTION_STRING=<ai-connection-string>
```

### **3. Verify Application Access**

After deployment, verify each service is accessible:

```bash
# Check API Gateway
curl http://$(terraform output -raw load_balancer_public_ip)/health

# Check frontend
curl http://$(terraform output -raw load_balancer_public_ip):3000

# Check App Service frontend
curl $(terraform output -raw frontend_urls | jq -r '.app_service_url')
```

## 🎯 **Complete Application URLs**

After deployment, get all access URLs:

```bash
# Get comprehensive access guide
terraform output application_access_guide
```

**Example Output:**
```json
{
  "primary_frontend": "https://app-otel-demo-frontend-dev-abc123.azurewebsites.net",
  "api_gateway": "http://<public-lb-ip>",
  "swagger_ui": "http://<public-lb-ip>/swagger",
  "vm1_services": "http://<vm1-public-ip> (Inventory Service)",
  "vm2_services": "http://<vm2-public-ip> (API + Event Processor)",
  "aks_services": "Access via kubectl port-forward or ingress",
  "monitoring_dashboard": "https://portal.azure.com/#@/resource/subscriptions/.../overview"
}
```

## 🔧 **Development Access**

For development and testing:

1. **Local Development:**
   ```bash
   cd services/frontend
   npm install
   npm start
   # Access at http://localhost:3000
   ```

2. **Port Forwarding to AKS services:**
   ```bash
   # Forward AKS services to local ports
   kubectl port-forward service/order-service 8080:8080
   kubectl port-forward service/payment-service 5002:5002
   kubectl port-forward service/notification-service 8082:8082
   ```

3. **SSH Tunneling to VMs:**
   ```bash
   # Create SSH tunnel to VM services
   ssh -L 5000:localhost:5000 azureuser@$(terraform output -raw vm_public_ips | jq -r '.[0]')
   ssh -L 3001:localhost:3000 azureuser@$(terraform output -raw vm_public_ips | jq -r '.[1]')
   ```

## 📊 **Monitoring and Debugging**

### **Application Insights:**
- **URL**: From `terraform output application_access_guide`
- **Features**: Real-time monitoring, performance insights, error tracking

### **Log Analytics:**
- **Workspace ID**: `terraform output log_analytics_workspace_id`
- **Query logs**: Use Kusto queries in Azure Portal

### **Health Checks:**
```bash
# Check all service health endpoints
curl http://$(terraform output -raw load_balancer_public_ip)/health
curl http://$(terraform output -raw vm_public_ips | jq -r '.[1]'):3000/health
curl http://$(terraform output -raw vm_public_ips | jq -r '.[1]'):8001/health
```

## 🚨 **Troubleshooting**

### **Frontend Not Loading:**
1. Check NSG rules allow port 3000
2. Verify frontend service is running on VM
3. Check Application Insights for errors

### **API Calls Failing:**
1. Verify backend services are deployed and running
2. Check CORS configuration
3. Verify environment variables are set correctly

### **No Data in Monitoring:**
1. Verify Application Insights connection string
2. Check that OpenTelemetry instrumentation is working
3. Review service logs for errors

## 📈 **Performance Optimization**

### **CDN Configuration:**
The infrastructure includes Azure CDN for optimal frontend performance:
- **CDN URL**: From `terraform output frontend_urls.cdn_url`
- **Global edge locations** for faster loading
- **SPA routing** configured for React Router

### **Caching Strategy:**
- Static assets cached at CDN edge
- API responses cached with Redis
- Application Insights data aggregated

This setup provides multiple frontend access options suitable for different scenarios - from development testing to production deployment! 🎉