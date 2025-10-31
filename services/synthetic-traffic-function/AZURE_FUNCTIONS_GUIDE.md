# Azure Functions Synthetic Traffic Generator

The OpenTelemetry demo now includes an **Azure Functions-based synthetic traffic generator** that provides serverless, cost-effective, and scalable traffic generation for your demo environment.

## 🚀 **Azure Functions Benefits**

✅ **Serverless & Cost-Effective**: Pay only for execution time, no always-on compute costs
✅ **Automatic Scaling**: Scales based on demand, handles traffic spikes automatically  
✅ **Built-in Monitoring**: Full Application Insights integration out of the box
✅ **Timer-Based Execution**: Automated traffic generation every 2 minutes
✅ **HTTP Triggers**: Manual traffic generation and configuration via REST APIs
✅ **Zero Infrastructure Management**: No VMs or containers to maintain

## 🎯 **Function Endpoints**

### **1. Automatic Traffic Generation**
- **Timer Trigger**: Runs every 2 minutes automatically
- **Pattern-Aware**: Adjusts traffic based on time of day
- **Realistic Load**: 3-40 requests per burst depending on business hours

### **2. Manual Traffic Generation**
```http
POST https://your-function-app.azurewebsites.net/api/GenerateTrafficHttp
Content-Type: application/json

{
  "requestCount": 10,
  "scenarioName": "Product Browsing"
}
```

### **3. Traffic Status Monitoring**
```http
GET https://your-function-app.azurewebsites.net/api/GetTrafficStatus
```

### **4. Runtime Configuration**
```http
POST https://your-function-app.azurewebsites.net/api/ConfigureTrafficPattern
Content-Type: application/json

{
  "minRequestsPerBurst": 5,
  "maxRequestsPerBurst": 30,
  "errorRate": 0.025,
  "enabledScenarios": ["Product Browsing", "Shopping Cart", "Order Processing"]
}
```

## 🔧 **Deployment**

### **Option 1: Using Terraform (Recommended)**
The function app is automatically provisioned with your infrastructure:

```bash
# Deploy infrastructure including Function App
cd infrastructure/terraform
terraform apply
```

### **Option 2: Manual Deployment**
```bash
# Build and deploy the function
./infrastructure/scripts/deploy-function.sh build
./infrastructure/scripts/deploy-function.sh deploy <function-app-name> <resource-group>

# Configure for your API Gateway
./infrastructure/scripts/deploy-function.sh configure <function-app-name> <resource-group> <api-gateway-url>
```

### **Option 3: Local Development**
```bash
# Test locally first
./infrastructure/scripts/deploy-function.sh build
./infrastructure/scripts/deploy-function.sh test

# Function available at: http://localhost:7071
```

## ⚙️ **Configuration**

### **Environment Variables**
Set these in your Function App configuration:

```json
{
  "API_GATEWAY_URL": "https://your-api-gateway.azurewebsites.net",
  "TRAFFIC_MIN_REQUESTS": "5",
  "TRAFFIC_MAX_REQUESTS": "40", 
  "TRAFFIC_ERROR_RATE": "0.02",
  "TRAFFIC_ENABLED_SCENARIOS": "Product Browsing,Shopping Cart,Order Processing"
}
```

### **Timer Schedule**
Default: `"0 */2 * * * *"` (every 2 minutes)

To modify, update the `TimerTrigger` attribute in `TrafficGeneratorFunction.cs`:
```csharp
[TimerTrigger("0 */5 * * * *")] // Every 5 minutes
[TimerTrigger("0 0 * * * *")]   // Every hour
[TimerTrigger("0 */1 * * * *")] // Every minute
```

### **Traffic Patterns**
The function automatically adjusts traffic based on time:

- **Business Hours** (9 AM - 5 PM): 15-25 requests per burst
- **Peak Hours** (12 PM - 2 PM): 25-40 requests per burst
- **Evening Hours** (6 PM - 10 PM): 10-18 requests per burst  
- **Night/Early Morning**: 3-8 requests per burst

## 📊 **Monitoring & Observability**

### **Application Insights Integration**
- **Request Telemetry**: All generated traffic appears in Application Insights
- **Function Execution Logs**: Timer triggers and HTTP requests logged
- **Custom Metrics**: Traffic generation statistics and patterns
- **Dependency Tracking**: HTTP calls to your API Gateway automatically tracked

### **Function App Monitoring**
```bash
# Check function status
./infrastructure/scripts/deploy-function.sh status <function-app-name> <resource-group>

# Stream live logs
./infrastructure/scripts/deploy-function.sh logs <function-app-name> <resource-group>
```

### **Azure Portal**
- **Function App Overview**: Execution count, success rate, duration
- **Application Insights**: End-to-end request correlation
- **Log Stream**: Real-time function execution logs
- **Metrics**: Invocation count, execution duration, error rates

## 🎮 **Usage Examples**

### **Generate Immediate Traffic**
```bash
# Single request
curl -X POST "https://your-function-app.azurewebsites.net/api/GenerateTrafficHttp" \
  -H "Content-Type: application/json" \
  -d '{"requestCount": 1, "scenarioName": "Product Browsing"}'

# Traffic burst
curl -X POST "https://your-function-app.azurewebsites.net/api/GenerateTrafficHttp" \
  -H "Content-Type: application/json" \
  -d '{"requestCount": 20}'
```

### **Check Traffic Status**
```bash
curl "https://your-function-app.azurewebsites.net/api/GetTrafficStatus"
```

### **Configure Traffic Patterns**
```bash
curl -X POST "https://your-function-app.azurewebsites.net/api/ConfigureTrafficPattern" \
  -H "Content-Type: application/json" \
  -d '{
    "minRequestsPerBurst": 10,
    "maxRequestsPerBurst": 50,
    "errorRate": 0.03,
    "enabledScenarios": ["Product Browsing", "Shopping Cart", "Order Processing", "User Registration"]
  }'
```

## 🎯 **Demo Scenarios**

### **Always-On Background Traffic**
- Timer function runs automatically every 2 minutes
- Provides consistent baseline traffic for Azure Monitor
- Demonstrates realistic daily traffic patterns

### **On-Demand Load Testing**
```bash
# Generate immediate load for demo
curl -X POST "https://your-function-app.azurewebsites.net/api/GenerateTrafficHttp" \
  -d '{"requestCount": 50}'
```

### **Scheduled Peak Traffic**
- Configure higher traffic during business hours
- Automatic scaling during peak times
- Demonstrates Azure Monitor's ability to capture traffic variations

### **Failure Injection Integration**
- Combine with failure injection UI
- Generate traffic while failures are active
- Show distributed tracing of failed requests

## 💰 **Cost Benefits**

### **Consumption Plan Pricing**
- **First 1M executions**: Free per month
- **Additional executions**: $0.000016 per execution
- **Execution time**: $0.000016 per GB-second

### **Example Monthly Cost**
- **Timer executions**: 21,600 per month (every 2 minutes)
- **Manual executions**: ~1,000 per month for demos
- **Total cost**: **~$0.36/month** for continuous traffic generation

### **Comparison to VM**
- **B1ms VM**: $15.33/month for always-on
- **Function**: $0.36/month for equivalent traffic
- **Savings**: **97% cost reduction**

## 🔧 **Advanced Configuration**

### **Custom Scenarios**
Add new traffic scenarios by modifying `GetScenarios()` in `TrafficGeneratorFunction.cs`:

```csharp
new TrafficScenario
{
    Name = "Custom Workflow",
    Weight = 15,
    Steps = new List<TrafficStep>
    {
        new TrafficStep { Method = "GET", Endpoint = "/api/custom" },
        new TrafficStep { Method = "POST", Endpoint = "/api/custom/action", Body = "{\"data\": \"test\"}" }
    }
}
```

### **Integration with Frontend**
The React frontend can trigger traffic generation:

```javascript
// Generate traffic burst
const response = await fetch('https://your-function-app.azurewebsites.net/api/GenerateTrafficHttp', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ requestCount: 20, scenarioName: 'Shopping Cart' })
});
```

### **Terraform Integration**
The function app is automatically configured with your infrastructure outputs:

```hcl
app_settings = {
  "API_GATEWAY_URL" = "https://${azurerm_linux_web_app.api_gateway.default_hostname}"
  "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
}
```

## 🛡️ **Security & Best Practices**

### **Function-Level Security**
- HTTP triggers use `AuthorizationLevel.Function` (requires function key)
- Status endpoint uses `AuthorizationLevel.Anonymous` for monitoring
- Timer triggers are automatically secured

### **Network Security**
- Outbound calls to API Gateway only
- No inbound network access required
- Built-in DDoS protection via Azure Functions platform

### **Configuration Management**
- Environment variables for sensitive settings
- Application Insights connection strings managed securely
- Function keys automatically generated and managed

## 🚀 **Getting Started**

1. **Deploy Infrastructure**: Run `terraform apply` to create the Function App
2. **Build Function**: `./infrastructure/scripts/deploy-function.sh build`
3. **Deploy Function**: `./infrastructure/scripts/deploy-function.sh deploy <function-name> <resource-group>`
4. **Configure Target**: Set API_GATEWAY_URL to your deployed API Gateway
5. **Monitor**: Check Application Insights for traffic generation telemetry

The Azure Functions synthetic traffic generator provides a powerful, cost-effective, and maintenance-free solution for continuous traffic generation in your OpenTelemetry demo environment! 🎯