# Centralized Failure Injection Control Center

The OpenTelemetry demo includes a comprehensive failure injection control center that allows you to manipulate failure scenarios across all services from a single, intuitive web interface.

## 🎯 **Access the Control Center**

Navigate to **`/failures`** in the React frontend to access the Failure Injection Control Center.

## 🎛️ **Interface Overview**

The control center is organized into three main tabs:

### **1. Quick Scenarios**
Pre-configured chaos engineering scenarios for common testing patterns:

- **Normal Operations** (2% latency, 1% errors)
- **Light Load Testing** (5% latency, 2% errors)  
- **Moderate Chaos** (15% latency, 8% errors)
- **Heavy Chaos** (30% latency, 15% errors)
- **Disaster Simulation** (50% latency, 25% errors)

**Usage**: Click any scenario card to instantly apply those settings across all services.

### **2. Individual Services**
Fine-tune failure injection for each service independently:

- **API Gateway (.NET)** - VM-hosted service with Azure Monitor OTel Distro
- **Order Service (Java)** - AKS-hosted Spring Boot service
- **Event Processor (Python)** - VM-hosted FastAPI service with OSS OTel
- **Payment Service (.NET)** - AKS-hosted service with built-in failure rates

**Per-Service Controls**:
- Enable/disable failure injection
- Latency injection probability (0-50%)
- Error injection probability (0-30%)
- Real-time status monitoring

### **3. Global Configuration**
Apply consistent settings across all services:

- **Global Enable/Disable**: Master switch for all failure injection
- **Latency Configuration**: Set probability and delay ranges (100ms - 2000ms)
- **Error Configuration**: Control error injection rates
- **Bulk Apply**: Push settings to all services simultaneously

## 🚀 **How to Use**

### **Quick Demo Setup**
1. Navigate to `/failures` in the frontend
2. Click "Light Load Testing" scenario
3. Go to `/traffic` and generate some load
4. Observe failure patterns in Azure Application Insights

### **Custom Configuration**
1. Switch to "Individual Services" tab
2. Enable failure injection for specific services
3. Adjust latency and error probabilities with sliders
4. Changes apply immediately

### **Chaos Engineering**
1. Use "Global Configuration" tab
2. Set baseline failure rates (5-10% latency, 2-5% errors)
3. Gradually increase rates during demos
4. Monitor distributed tracing to see failure propagation

## 🔧 **Technical Details**

### **Real-time Configuration**
All changes apply immediately without service restarts:
- **API Gateway**: Runtime configuration via REST API
- **Event Processor**: Dynamic configuration updates
- **Order Service**: Spring Boot actuator integration
- **Payment Service**: Built-in failure simulation

### **Failure Types**
- **Latency Injection**: Variable delays (100ms - 2000ms)
- **Timeout Errors**: Simulated network timeouts  
- **Database Errors**: Connection and query failures
- **Network Errors**: HTTP request failures
- **Processing Errors**: Business logic failures
- **Payment Failures**: Gateway-specific error rates

### **Observability Integration**
All injected failures are properly instrumented:
- **OpenTelemetry Traces**: Failure spans with error details
- **Custom Attributes**: `failure_injection.type`, `failure_injection.latency`
- **Structured Logging**: Detailed failure information
- **Metrics**: Failure rates and injection statistics

## 📊 **Monitoring Failure Injection**

### **Application Insights**
- **Performance Tab**: View latency increases
- **Failures Tab**: See injected errors
- **Application Map**: Observe failure propagation
- **Live Metrics**: Real-time failure rates

### **Service Status**
Each service card shows:
- Current health status
- Last configuration update
- Active failure injection settings
- Injection statistics

## 🎭 **Demo Scenarios**

### **Baseline Demonstration**
```
1. Start with "Normal Operations" (minimal failures)
2. Generate traffic via frontend
3. Show baseline performance in Azure Monitor
```

### **Gradual Degradation**
```
1. Apply "Light Load Testing"
2. Increase to "Moderate Chaos"
3. Demonstrate how Azure Monitor captures degradation
4. Show distributed tracing of failed requests
```

### **Service-Specific Issues**
```
1. Enable high error rates (20%) on Order Service only
2. Show how failures propagate upstream
3. Demonstrate circuit breaker patterns
4. View service dependency mapping
```

### **Recovery Testing**
```
1. Apply "Heavy Chaos" scenario
2. Reset to "Normal Operations"
3. Demonstrate service recovery
4. Show Azure Monitor alerting capabilities
```

## 🛡️ **Safety Features**

- **Maximum Limits**: Error rates capped at 30%, latency at 2000ms
- **Service Health Monitoring**: Real-time status checks
- **One-Click Disable**: "Disable All" button for emergency stops
- **Configuration Logging**: All changes tracked for audit

## 🔍 **Troubleshooting**

**Services Not Responding**:
- Check service health status indicators
- Verify network connectivity
- Review service logs for configuration errors

**Changes Not Applied**:
- Refresh service status
- Check individual service endpoints
- Verify service deployment status

**High Failure Rates**:
- Use "Reset" buttons to restore defaults
- Check current scenario selection
- Monitor service recovery time

## 🎉 **Best Practices**

1. **Start Small**: Begin with low failure rates (2-5%)
2. **Monitor Impact**: Watch Azure Monitor for propagation
3. **Gradual Increases**: Slowly raise failure rates during demos
4. **Document Scenarios**: Save effective configurations
5. **Reset After Demos**: Return to baseline settings
6. **Service-Specific Tuning**: Different services have different tolerance levels

The centralized failure injection control center provides a powerful, user-friendly way to demonstrate Azure Monitor's observability capabilities and showcase how OpenTelemetry captures failure scenarios across your distributed application! 🚀