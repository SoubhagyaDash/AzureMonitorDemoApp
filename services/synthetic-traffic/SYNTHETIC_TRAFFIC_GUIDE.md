# Always-On Synthetic Traffic Generator

The OpenTelemetry demo includes a comprehensive always-on synthetic traffic generation system that continuously produces realistic load patterns to showcase Azure Monitor's observability capabilities.

## 🚀 **Quick Start**

### **Windows**
```powershell
.\infrastructure\scripts\deploy-synthetic-traffic.bat start
```

### **Linux/macOS**
```bash
./infrastructure/scripts/deploy-synthetic-traffic.sh start
```

### **Always-On Orchestrator**
```bash
./infrastructure/scripts/always-on-traffic.sh start
```

## 🎯 **Traffic Generation Overview**

The synthetic traffic system generates realistic e-commerce application usage patterns with:

### **📊 Traffic Patterns**
- **Business Hours** (9 AM - 5 PM): 15-25 requests/minute
- **Peak Hours** (12 PM - 2 PM): 25-40 requests/minute  
- **Evening Hours** (6 PM - 10 PM): 10-18 requests/minute
- **Night/Early Morning**: 3-8 requests/minute

### **🛍️ Realistic User Scenarios**
1. **Product Browsing** (30% of traffic)
   - Browse product catalog
   - View individual product details
   - Check inventory availability

2. **Shopping Cart Operations** (25% of traffic)
   - Add items to cart
   - Update quantities
   - View cart contents

3. **Order Processing** (20% of traffic)
   - Place orders
   - Process payments
   - Check order status

4. **User Registration** (10% of traffic)
   - New user registrations
   - Login operations

5. **Inventory Management** (10% of traffic)
   - Stock level checks
   - Restock notifications

6. **Health Monitoring** (5% of traffic)
   - Service health checks
   - Metrics collection

## ⚙️ **Configuration**

### **Basic Configuration**
Edit `services/synthetic-traffic/appsettings.json`:

```json
{
  "ApiGateway": {
    "BaseUrl": "http://localhost:5000"
  },
  "TrafficGeneration": {
    "Enabled": true,
    "MinRequestsPerMinute": 5,
    "MaxRequestsPerMinute": 40,
    "EnableRealisticPatterns": true,
    "EnableErrorInjection": true,
    "BaseErrorRate": 0.02
  }
}
```

### **Always-On Configuration**
Edit `infrastructure/scripts/traffic-config.sh`:

```bash
# API Gateway URL
API_GATEWAY_URL="http://localhost:5000"

# Traffic patterns to run
TRAFFIC_PATTERNS="business,peak,evening,night"

# Monitoring settings
ENABLE_HEALTH_MONITORING="true"
RESTART_ON_FAILURE="true"
HEALTH_CHECK_INTERVAL="60"
```

### **Environment-Specific Settings**

**Development:**
- Lower traffic volumes (3-20 requests/minute)
- Reduced error rates (0.5%)
- Debug logging enabled

**Production:**
- Full traffic volumes (8-50 requests/minute)
- Realistic error rates (1.5-8%)
- Comprehensive monitoring

## 🔧 **Deployment Options**

### **1. Azure Functions (Recommended) ⚡**
Serverless, cost-effective traffic generation:

```bash
# Deploy with infrastructure
cd infrastructure/terraform && terraform apply

# Or deploy manually
./infrastructure/scripts/deploy-function.sh build
./infrastructure/scripts/deploy-function.sh deploy <function-app-name> <resource-group>
```

**Benefits:**
- **97% cost reduction** vs always-on VMs ($0.36/month vs $15/month)
- **Auto-scaling** based on demand
- **Built-in monitoring** with Application Insights
- **Timer-based** execution every 2 minutes
- **HTTP triggers** for manual traffic generation

### **2. Standalone Service**
Run as a standalone .NET service:

```bash
# Build and start
./infrastructure/scripts/deploy-synthetic-traffic.sh start

# Check status
./infrastructure/scripts/deploy-synthetic-traffic.sh status

# View logs
./infrastructure/scripts/deploy-synthetic-traffic.sh logs
```

### **3. Always-On Orchestrator**
Multiple traffic generators with health monitoring:

```bash
# Start all patterns
./infrastructure/scripts/always-on-traffic.sh start

# Monitor continuously
./infrastructure/scripts/always-on-traffic.sh monitor

# Show detailed status
./infrastructure/scripts/always-on-traffic.sh status
```

### **3. Docker Deployment**
```bash
# Start all traffic containers
docker-compose -f infrastructure/docker/synthetic-traffic-compose.yml up -d

# View logs
docker-compose -f infrastructure/docker/synthetic-traffic-compose.yml logs -f
```

## 📊 **Monitoring & Observability**

### **Service Health**
- Automatic health checks every 60 seconds
- Restart on failure (configurable)
- PID file management
- Comprehensive logging

### **Traffic Metrics**
The generators track and report:
- Requests per minute by pattern
- Response times and errors
- Service availability
- Failure injection statistics

### **Azure Monitor Integration**
All synthetic traffic is fully instrumented:
- **Application Insights**: Request telemetry
- **Distributed Tracing**: End-to-end request flows
- **Custom Metrics**: Traffic generation statistics
- **Structured Logging**: Detailed request information

## 🎮 **Control Commands**

### **Basic Service Management**
```bash
# Start traffic generation
./deploy-synthetic-traffic.sh start

# Stop traffic generation
./deploy-synthetic-traffic.sh stop

# Restart with new configuration
./deploy-synthetic-traffic.sh restart

# Build service only
./deploy-synthetic-traffic.sh build

# View current logs
./deploy-synthetic-traffic.sh logs

# Check service status
./deploy-synthetic-traffic.sh status
```

### **Always-On Orchestrator**
```bash
# Start all traffic patterns
./always-on-traffic.sh start

# Stop all generators
./always-on-traffic.sh stop

# Restart everything
./always-on-traffic.sh restart

# Enter monitoring mode
./always-on-traffic.sh monitor

# Show detailed status
./always-on-traffic.sh status

# View all logs
# View all logs
./always-on-traffic.sh logs
```

### **4. Docker Deployment**
```

## 🔍 **Troubleshooting**

### **Common Issues**

**Traffic Generator Won't Start:**
```bash
# Check .NET SDK installation
dotnet --version

# Verify API Gateway accessibility
curl http://localhost:5000/health

# Check logs for errors
tail -f logs/synthetic-traffic.log
```

**High Error Rates:**
- Verify API Gateway is running
- Check network connectivity
- Review failure injection settings
- Monitor Azure Monitor for service issues

**Performance Issues:**
- Reduce traffic volume in configuration
- Check system resources
- Monitor API Gateway response times
- Review Azure Monitor performance data

### **Log Locations**
- **Service Logs**: `logs/synthetic-traffic.log`
- **Orchestrator Logs**: `logs/orchestrator.log`
- **Instance Logs**: `logs/traffic-pattern-instance.log`
- **PID Files**: `logs/*.pid`

## 🎯 **Demo Scenarios**

### **Baseline Load Demo**
1. Start basic traffic: `./deploy-synthetic-traffic.sh start`
2. Access Azure Monitor Application Insights
3. Show steady baseline request patterns
4. Demonstrate normal error rates and response times

### **Peak Load Simulation**
1. Start orchestrator: `./always-on-traffic.sh start`
2. Wait for peak hours (12 PM - 2 PM) or force peak configuration
3. Show increased request volumes in Azure Monitor
4. Demonstrate auto-scaling and performance monitoring

### **Failure Injection Combined**
1. Start always-on traffic
2. Access failure injection UI at `/failures`
3. Increase error rates while traffic is running
4. Show how Azure Monitor captures failure propagation

### **Recovery Testing**
1. Stop traffic generators: `./always-on-traffic.sh stop`
2. Show baseline metrics in Azure Monitor
3. Restart traffic: `./always-on-traffic.sh start`
4. Demonstrate service recovery and ramp-up patterns

## 🏗️ **Architecture**

### **Traffic Generator Service**
- **.NET 8.0** background service
- **Configurable patterns** for different times of day
- **Realistic scenarios** mimicking user behavior
- **Built-in error injection** for chaos testing
- **Health monitoring** and automatic restart

### **Always-On Orchestrator**
- **Bash script** managing multiple generator instances
- **Pattern-based configuration** (business, peak, evening, night)
- **Health monitoring** with automatic recovery
- **Distributed load** across multiple instances
- **Comprehensive logging** and status reporting

### **Integration Points**
- **API Gateway**: Primary target for all requests
- **Azure Monitor**: Full telemetry integration
- **Failure Injection**: Coordinates with chaos engineering
- **Frontend Monitoring**: Synthetic user interaction patterns

## 📈 **Benefits for Demo**

✅ **Always Available**: Continuous traffic for immediate demos
✅ **Realistic Patterns**: Time-based traffic that mimics real usage
✅ **Comprehensive Coverage**: All services and endpoints exercised
✅ **Failure Integration**: Works with failure injection for chaos demos
✅ **Azure Monitor Showcase**: Rich telemetry data for monitoring demos
✅ **Easy Control**: Simple commands for demo management
✅ **Health Monitoring**: Self-healing for reliable demonstrations

The always-on synthetic traffic system ensures your OpenTelemetry demo environment always has meaningful data flowing through Azure Monitor, making it perfect for showcasing observability capabilities! 🚀