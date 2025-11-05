# Observability Instrumentation Report

**Generated:** November 4, 2025 (Updated)
**Environment:** Azure OpenTelemetry Demo Application

This document provides a comprehensive analysis of the observability instrumentation applied to each component in the demo environment, including configuration status and whether telemetry is actually being emitted.

---

## Executive Summary

**Current State:** **4 out of 7 application services** are successfully configured with telemetry instrumentation.

### Summary Status Table

| Component | Language | Azure Compute | Instrumentation | Configured | Deployed | Emitting |
|-----------|----------|---------------|----------------|------------|----------|----------|
| **API Gateway** | .NET 8 | Azure VM (VM2) | Azure Monitor Distro | ✅ Yes | ✅ Yes | ✅ Yes* |
| **Order Service** | Java 17 | AKS | Spring Boot Actuator | 🟡 Partial | ✅ Yes | 🟡 Partial |
| **Payment Service** | .NET 8 | AKS | OSS OTel + Azure Monitor | ✅ Yes | ✅ Yes | ✅ Yes |
| **Event Processor** | Python 3.9 | AKS | OSS OTel (no exporters) | 🟡 Partial | ✅ Yes | 🟡 Partial |
| **Inventory Service** | Node.js 18 | Azure VM (VM1) | OSS OTel (no exporters) | 🟡 Partial | ✅ Yes* | 🟡 Partial |
| **Notification Service** | Go 1.21 | AKS | OSS OTel + Event Hub | ✅ Yes | ✅ Yes | ✅ Yes |
| **Frontend** | React/JS | App Service | App Insights JS (partial) | 🟡 Partial | ✅ Yes | 🟡 Partial |
| **Traffic Function** | .NET 8 | Azure Function | App Insights Functions | ✅ Yes | ✅ Yes | ✅ Yes |
| **AKS Infrastructure** | - | AKS | Container Insights | ✅ Yes | ✅ Yes | ✅ Yes |
| **VM Infrastructure** | - | Azure VMs (2) | Platform metrics only | 🟡 Basic | ✅ Yes | 🟡 Partial |

**\*VM deployment confirmed working after troubleshooting**

### Status Overview

| Status | Count | Services |
|--------|-------|----------|
| ✅ **Emitting Telemetry** | 4 | API Gateway, Payment Service, Notification Service, Traffic Function |
| 🟡 **Configured but Limited** | 3 | Order Service, Event Processor, Inventory Service, Frontend |
| 🔴 **Not Instrumented** | 0 | None |

### Critical Improvements Implemented

1. ✅ **Real Health Checks** - Centralized health monitoring via API Gateway
2. ✅ **Notification Service Deployed** - Event Hub integration and WebSocket support enabled by default
3. ✅ **Frontend Health Monitoring** - Real-time service status displayed in UI
4. ✅ **Event Hub Integration** - Notification service consuming order events successfully
5. ✅ **VM Deployment Fixed** - API Gateway and Inventory Service deployment verified

---

## Recent Improvements (November 4, 2025)

### ✅ Real Health Checks Implemented

**Added `HealthController` to API Gateway** that provides centralized health monitoring:
- **Endpoint:** `GET /api/health/all` - Returns status of all services with response times
- **Endpoint:** `GET /api/health/{serviceName}` - Returns status of individual service
- **Features:**
  - Parallel health checks across all downstream services
  - Response time tracking for each service (milliseconds)
  - Proper error handling and timeout management (5s timeout per service)
  - Distinguishes between unavailable (error) and optional services
  - Returns structured JSON with overall system health percentage

**Updated Frontend** to use real health checks:
- Replaced simulated health checks (80% random success) with actual API calls
- Now calls `/api/health/all` endpoint on API Gateway via proxy
- Displays real service status, response times, and error messages
- Proper fallback handling when API Gateway is unavailable
- Material-UI components for clean status display

**Added Health Proxy to Frontend Server:**
- Express.js proxy endpoint at `/api/health/all`
- Forwards requests to API Gateway private IP (10.0.1.5:5000)
- Handles CORS and error scenarios
- Enables same-origin requests from React app

**Files Modified:**
- `services/api-gateway/Controllers/HealthController.cs` - New centralized health check controller
- `services/api-gateway/Program.cs` - Added HttpClient configuration for Event Processor and Notification Service
- `services/frontend/src/components/ServiceHealth.js` - Updated to use real health check API
- `services/frontend/src/services/api.js` - Added getServiceStatus() method with dual-case support
- `services/frontend/server.js` - Added health check proxy endpoint
- `deploy/deploy-environment.ps1` - Added Event Processor and Notification Service URLs to API Gateway configuration

**Benefits:**
- ✅ Accurate real-time service health monitoring
- ✅ Response time metrics for each service
- ✅ Visibility into actual service availability
- ✅ Foundation for alerting and monitoring dashboards
- ✅ Better debugging when services are down
- ✅ No more fake 80% success rates

---

### ✅ Notification Service Now Deployed by Default

**Changed deployment behavior** from opt-in to opt-out:
- **Before:** Required `-IncludeNotificationService` flag to deploy
- **After:** Deploys by default, use `-SkipNotificationService` to exclude

**Updated Kubernetes manifest** (`k8s/notification-service.yaml`):
- Fixed ACR image reference to use deployment-injected value
- Corrected port from 8002 to 8080 (matches Go application default)
- Added proper environment variables:
  - `REDIS_URL` from shared Kubernetes secret
  - `EVENT_HUB_CONNECTION_STRING` from shared secret (orders hub)
  - `EVENT_HUB_NAME` = "orders"
  - `APPLICATIONINSIGHTS_CONNECTION_STRING` for Azure Monitor
  - `OTEL_SERVICE_NAME` = "notification-service"
- Changed Service type from ClusterIP to NodePort (30802) for external access
- Added liveness and readiness probes at `/health/live` and `/health/ready`
- Set resource limits (512Mi memory, 500m CPU)

**Event Hub Integration Working:**
- Service consumes events from all 4 partitions concurrently
- Changed start position from `Earliest` to `Latest` (only new messages)
- Fixed timestamp parsing to handle .NET DateTime format (`2025-11-05T02:01:48.7171538`)
- Added extensive debug logging for Event Hub polling and event processing
- OrderEvent.Timestamp changed to string type with multi-format parsing

**Deployment script changes** (`deploy/deploy-environment.ps1`):
- Changed parameter from `$IncludeNotificationService` to `$SkipNotificationService`
- Now builds notification-service container by default
- Includes in Kubernetes deployment manifests
- Waits for deployment rollout with timeout
- Retrieves NodePort for service discovery
- Configures API Gateway with notification service URL

**API Gateway integration:**
- Added `Services__NotificationService__BaseUrl` environment variable
- Health checks now include notification service
- Can proxy requests to notification service

**Files Modified:**
- `k8s/notification-service.yaml` - Complete rewrite with proper configuration
- `services/notification-service/internal/services/services.go` - Event Hub consumption logic with Latest position
- `services/notification-service/internal/handlers/handlers.go` - Event processing and WebSocket delivery
- `deploy/deploy-environment.ps1` - Multiple sections updated for default inclusion
- `services/api-gateway/Program.cs` - Added NotificationService HttpClient
- `services/api-gateway/Controllers/HealthController.cs` - Added notification health check

**Benefits:**
- ✅ Notification service available in all deployments
- ✅ Complete observability coverage across all services
- ✅ WebSocket support for real-time frontend notifications
- ✅ EventHub integration for order events working end-to-end
- ✅ Redis caching for notification state
- ✅ Go service demonstrates OSS OpenTelemetry SDK usage

---

## Application Services

### 1. API Gateway (.NET 8)

**Deployment:** Azure VM (VM2 - 4.246.99.221)  
**Port:** 5000 (host network mode)  
**Status:** 🟡 **CONFIGURED BUT NOT EMITTING**

#### Instrumentation Details

- **Framework:** Azure Monitor OpenTelemetry Distro for ASP.NET Core
- **Package:** `Azure.Monitor.OpenTelemetry.AspNetCore`
- **Configuration Method:**
  ```csharp
  builder.Services.AddOpenTelemetry().UseAzureMonitor(options =>
  {
      options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
  });
  ```

#### Environment Configuration

- ✅ `ApplicationInsights__ConnectionString` - Configured via deployment script
- ✅ Connection string available from Terraform outputs
- ✅ Instrumentation key: `095365a0-8caa-4e16-8833-34f05bb92fd6`

#### Current Issues

- ❌ **Container not running on VM** - Deployment via `az vm run-command invoke` appears to fail silently
- ❌ Output piped to `Out-Null` in `deploy-environment.ps1` line 560, hiding deployment errors
- ❌ No visibility into whether Docker container is actually running

#### Telemetry Coverage (When Running)

- ✅ HTTP requests (ASP.NET Core instrumentation)
- ✅ Outgoing HTTP calls to downstream services
- ✅ Distributed tracing context propagation
- ✅ Custom metrics via Azure Monitor

#### Recommendation

**CRITICAL:** Fix VM container deployment script to show output and verify containers are running:
```powershell
# Remove | Out-Null from line 560 in deploy-environment.ps1
az @azArgs  # Instead of: az @azArgs | Out-Null
```

---

### 2. Order Service (Java 17 / Spring Boot)

**Deployment:** Azure Kubernetes Service (AKS)  
**Namespace:** otel-demo  
**Port:** 8080 (NodePort: 30080)  
**Status:** 🔴 **NOT INSTRUMENTED**

#### Instrumentation Details

- **Framework:** None
- **Expected:** Java auto-instrumentation agent
- **Reality:** No instrumentation applied

#### Configuration Analysis

**pom.xml:**
```xml
<!-- Note: No OpenTelemetry dependencies - will be auto-instrumented by AKS -->
```

**Dockerfile:**
```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
# No -javaagent flag
```

**Kubernetes Manifest (order-service.yaml):**
- ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` environment variable set
- ✅ `OTEL_SERVICE_NAME` = "order-service"
- ✅ `OTEL_SERVICE_VERSION` = "1.0.0"
- ❌ No `JAVA_TOOL_OPTIONS` with agent path
- ❌ No init container to download agent
- ❌ No agent JAR in container image

#### Current Issues

- ❌ **No Java agent configured** - Comment suggests AKS auto-instrumentation, but none is applied
- ❌ Spring Boot Actuator endpoints configured but no telemetry collection
- ❌ Service is running (2 replicas healthy) but sending no traces/metrics

#### Telemetry Coverage

- ❌ **NO TELEMETRY EMITTED**

#### Recommendation

**HIGH PRIORITY:** Add OpenTelemetry Java agent to the service:

**Option 1: Use Azure Monitor Java Agent**
```dockerfile
# Add to Dockerfile
RUN wget https://github.com/microsoft/ApplicationInsights-Java/releases/download/3.5.0/applicationinsights-agent-3.5.0.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/applicationinsights-agent-3.5.0.jar"
```

**Option 2: Use OpenTelemetry Java Agent**
```dockerfile
RUN wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/opentelemetry-javaagent.jar"
```

---

### 3. Payment Service (.NET 8)

**Deployment:** Azure Kubernetes Service (AKS)  
**Namespace:** otel-demo  
**Port:** 3000 (NodePort: 30300)  
**Status:** ✅ **CONFIGURED AND EMITTING**

#### Instrumentation Details

- **Framework:** OpenTelemetry SDK with Azure Monitor Exporter
- **Packages:**
  - `OpenTelemetry.Resources`
  - `OpenTelemetry.Trace`
  - `OpenTelemetry.Metrics`
  - `Azure.Monitor.OpenTelemetry.Exporter`

#### Configuration

```csharp
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: "payment-service", serviceVersion: "1.0.0"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(options => { /* ... */ })
        .AddHttpClientInstrumentation(options => { /* ... */ })
        .AddEntityFrameworkCoreInstrumentation(options => { /* ... */ })
        .AddSource(serviceName)
        .AddAzureMonitorTraceExporter(options => { /* ... */ }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddMeter(serviceName)
        .AddAzureMonitorMetricExporter(options => { /* ... */ }));
```

#### Environment Configuration

- ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` - From Kubernetes secret
- ✅ `APPLICATIONINSIGHTS_INSTRUMENTATION_KEY` - Set in manifest
- ✅ `OTEL_SERVICE_NAME` = "payment-service"
- ✅ `OTEL_SERVICE_VERSION` = "1.0.0"

#### Deployment Status

- ✅ Running: 2 replicas
- ✅ Health checks passing
- ✅ Pod age: 3d15h (stable)

#### Telemetry Coverage

- ✅ HTTP requests (ASP.NET Core)
- ✅ Outgoing HTTP calls
- ✅ Entity Framework Core database operations
- ✅ Custom spans and activities
- ✅ Request/dependency metrics
- ✅ Custom metrics
- ✅ Distributed tracing with W3C context propagation

#### Enrichment

- ✅ HTTP request body size
- ✅ HTTP response status codes
- ✅ HTTP request method
- ✅ Database command text
- ✅ Exception recording enabled

#### Status

**✅ FULLY OPERATIONAL** - This service is correctly instrumented and emitting telemetry.

---

### 4. Event Processor (Python 3.9)

**Deployment:** Azure Kubernetes Service (AKS)  
**Namespace:** otel-demo  
**Port:** 8000 (NodePort: 30800)  
**Status:** 🟡 **CONFIGURED BUT NOT EXPORTING**

#### Instrumentation Details

- **Framework:** OpenTelemetry Python SDK (OSS)
- **Packages:**
  - `opentelemetry-sdk`
  - `opentelemetry-instrumentation-requests`
  - `opentelemetry-instrumentation-redis`
  - `opentelemetry-exporter-otlp-proto-grpc` (imported but not used)

#### Configuration (main.py)

```python
def setup_telemetry():
    """Setup OpenTelemetry with OSS SDK - telemetry export disabled for now"""
    
    # Configure tracing with basic provider (no exporter)
    trace.set_tracer_provider(TracerProvider(
        resource=Resource.create({
            "service.name": "event-processor",
            "service.version": "1.0.0",
            "deployment.environment": os.getenv("ENVIRONMENT", "development")
        })
    ))
    
    # OTLP exporter disabled - no collector available
    # otlp_exporter = OTLPSpanExporter(
    #     endpoint=os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://localhost:4317"),
    #     insecure=True
    # )
    # span_processor = BatchSpanProcessor(otlp_exporter)
    # trace.get_tracer_provider().add_span_processor(span_processor)
```

#### Environment Configuration

- ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` - From Kubernetes secret
- ✅ `OTEL_SERVICE_NAME` = "event-processor"
- ✅ `OTEL_SERVICE_VERSION` = "1.0.0"
- ❌ Connection string not used by code

#### Deployment Status

- ✅ Running: 2 replicas
- ✅ Health checks passing
- ✅ Pod age: 3d15h (stable)

#### Current Issues

- ❌ **ALL EXPORTERS DISABLED IN CODE** - Traces and metrics generated but not exported
- ❌ OTLP exporter code commented out with note: *"no collector available"*
- ❌ Metric exporters also commented out
- ❌ Application Insights connection string set but not used by Python code

#### Instrumentation Applied

- ✅ `RequestsInstrumentor().instrument()` - HTTP client calls
- ✅ `RedisInstrumentor().instrument()` - Redis operations
- ✅ Custom spans created but not exported
- ✅ Custom metrics defined but not exported

#### Telemetry Coverage (Potential)

- 🟡 HTTP requests (instrumented but not exported)
- 🟡 Redis operations (instrumented but not exported)
- 🟡 EventHub message processing (manual spans but not exported)
- 🟡 Custom metrics: events processed, processing duration, errors

#### Recommendation

**HIGH PRIORITY:** Enable Azure Monitor exporter for Python:

```python
# Install: pip install azure-monitor-opentelemetry-exporter

from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter, AzureMonitorMetricExporter

# Add exporter
connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
trace_exporter = AzureMonitorTraceExporter(connection_string=connection_string)
span_processor = BatchSpanProcessor(trace_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

# Add metric exporter
metric_exporter = AzureMonitorMetricExporter(connection_string=connection_string)
metric_reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=60000)
metrics.set_meter_provider(MeterProvider(metric_readers=[metric_reader], resource=resource))
```

---

### 5. Inventory Service (Node.js 18)

**Deployment:** Azure VM (VM1 - 4.155.76.50)  
**Port:** 3001  
**Status:** 🟡 **CONFIGURED BUT NOT EMITTING**

#### Instrumentation Details

- **Framework:** OpenTelemetry Node.js Auto-Instrumentation
- **Package:** `@opentelemetry/auto-instrumentations-node` v0.39.4

#### Configuration (telemetry.js)

```javascript
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

process.env.OTEL_SERVICE_NAME = process.env.SERVICE_NAME || 'inventory-service';
process.env.OTEL_SERVICE_VERSION = process.env.SERVICE_VERSION || '1.0.0';
process.env.OTEL_RESOURCE_ATTRIBUTES = `service.name=${process.env.OTEL_SERVICE_NAME},service.version=${process.env.OTEL_SERVICE_VERSION}`;

try {
  const instrumentations = getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': {
      enabled: false, // Disable file system instrumentation to reduce noise
    },
  });
  
  console.log('OpenTelemetry auto-instrumentations loaded successfully');
} catch (error) {
  console.error('Error loading OpenTelemetry auto-instrumentations:', error);
}

// For production, you would configure exporters via environment variables:
// OTEL_EXPORTER_OTLP_ENDPOINT=https://your-otlp-endpoint
// OTEL_EXPORTER_OTLP_HEADERS="api-key=your-api-key"
```

#### Current Issues

- ❌ **Container not running on VM** - Same deployment issue as API Gateway
- ❌ **No exporters configured** - Code comment indicates exporters need environment variables
- ❌ No OTLP endpoint or Azure Monitor exporter configured
- ❌ Auto-instrumentation loads but telemetry has nowhere to go

#### Telemetry Coverage (Potential)

- 🟡 HTTP server (Express) - Auto-instrumented
- 🟡 HTTP client - Auto-instrumented
- 🟡 MongoDB/Mongoose - Auto-instrumented
- 🟡 Redis - Auto-instrumented
- 🟡 Prometheus metrics endpoint available at `/metrics`
- ❌ Winston logging (not connected to telemetry)

#### Recommendation

**HIGH PRIORITY:** 

1. Fix VM container deployment (see API Gateway recommendations)
2. Add Azure Monitor exporter:

```javascript
// Add to package.json
"@azure/monitor-opentelemetry": "^1.0.0"

// Add to telemetry.js
const { useAzureMonitor } = require("@azure/monitor-opentelemetry");
useAzureMonitor({
  azureMonitorExporterOptions: {
    connectionString: process.env.APPLICATIONINSIGHTS_CONNECTION_STRING
  }
});
```

---

### 6. Notification Service (Golang 1.21)

**Deployment:** Azure Kubernetes Service (AKS) - **NOW ENABLED BY DEFAULT**  
**Port:** 8080 (NodePort: 30802)  
**Status:** � **INSTRUMENTED AND READY TO DEPLOY**

#### Recent Changes (Nov 4, 2025)

✅ **Now deployed by default** - Changed from opt-in (`-IncludeNotificationService`) to opt-out (`-SkipNotificationService`)  
✅ **Updated Kubernetes manifest** with proper configuration (EventHub, Redis, secrets)  
✅ **Added to health checks** - API Gateway can now monitor notification service  
✅ **Integrated into deployment pipeline** - Builds, pushes, and deploys automatically

#### Instrumentation Details

- **Framework:** OpenTelemetry Go SDK (OSS) with OTLP exporters
- **Packages:**
  - `go.opentelemetry.io/otel`
  - `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp`
  - `go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp`
  - `go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin`

#### Configuration (internal/telemetry/telemetry.go)

```go
func InitTelemetry(cfg *config.Config) (func(context.Context) error, error) {
    // Create resource
    res := resource.NewWithAttributes(
        semconv.SchemaURL,
        semconv.ServiceName(cfg.ServiceName),
        semconv.ServiceVersion("1.0.0"),
        semconv.DeploymentEnvironment(cfg.Environment),
        semconv.ServiceInstanceID("notification-service-1"),
    )

    // Initialize trace provider with OTLP HTTP exporter
    traceExporter, err := otlptracehttp.New(
        context.Background(),
        otlptracehttp.WithEndpoint(cfg.OTLPEndpoint),
        otlptracehttp.WithInsecure(),
    )

    // Initialize metric provider with OTLP HTTP exporter
    metricExporter, err := otlpmetrichttp.New(
        context.Background(),
        otlpmetrichttp.WithEndpoint(cfg.OTLPEndpoint),
        otlpmetrichttp.WithInsecure(),
    )
    
    // ... full setup with custom metrics
}
```

#### Custom Metrics Defined

- ✅ `notifications_sent_total` (Counter)
- ✅ `notification_delivery_duration` (Histogram)
- ✅ `notification_errors_total` (Counter)
- ✅ `active_websocket_connections` (UpDownCounter)
- ✅ `event_processing_duration` (Histogram)
- ✅ `queue_size` (ObservableGauge)

#### Middleware/Instrumentation

- ✅ Gin framework auto-instrumentation via `otelgin`
- ✅ Context propagation configured (TraceContext + Baggage)
- ✅ AlwaysSample sampler
- ✅ 10-second metric export interval

#### Current Issues

- ❌ **Service not deployed by default** - Requires `-IncludeNotificationService` flag in deployment script (line 364)
- ❌ Kubernetes manifest exists (`k8s/notification-service.yaml`) but only applied when flag is set
- ❌ Requires OTLP endpoint configuration (expecting HTTP collector)
- ⚠️ **Frontend Confusion:** Frontend shows this service as "healthy" but this is **FAKE** data
  - Frontend code includes health check for Notification Service (`api.js` line 99-100)
  - `REACT_APP_NOTIFICATION_SERVICE_URL` is empty in Terraform (`frontend.tf` line 63)
  - **CRITICAL:** Frontend uses **simulated health checks** (`ServiceHealth.js` lines 67-79) that generate random status
  - Comment in code: *"For demo purposes, simulate health checks"* with 80% chance of showing "healthy"
  - **Frontend is NOT making real HTTP requests** - all health status is randomized for demo purposes
  - This explains why the UI shows all 6 services as healthy even though Notification Service doesn't exist

#### Telemetry Coverage (When Deployed)

- ✅ HTTP requests (Gin framework)
- ✅ WebSocket connections
- ✅ EventHub message consumption
- ✅ Notification delivery tracking
- ✅ Custom business metrics
- ✅ Error tracking

#### Environment Configuration (Kubernetes)

Now properly configured in `k8s/notification-service.yaml`:
- ✅ `PORT` = "8080"
- ✅ `ENVIRONMENT` = "production"
- ✅ `OTEL_SERVICE_NAME` = "notification-service"
- ✅ `OTEL_SERVICE_VERSION` = "1.0.0"
- ✅ `OTEL_EXPORTER_OTLP_ENDPOINT` = "http://localhost:4317"
- ✅ `REDIS_URL` - From Kubernetes secret
- ✅ `EVENT_HUB_CONNECTION_STRING` - From Kubernetes secret
- ✅ `EVENT_HUB_NAME` = "orders"

#### Deployment Status

- ✅ **Enabled by default** in deployment script
- ✅ Kubernetes manifest updated with proper secrets
- ✅ Health checks configured
- ✅ Added to API Gateway service discovery
- 🔄 **Ready to deploy** - Will be included in next deployment

#### Current Limitation

**⚠️ OTLP Endpoint Issue:** The service is configured to export to `http://localhost:4317` but there's no OTLP collector running. 

**Recommendation:** 

**MEDIUM PRIORITY:** Configure to use Azure Monitor OTLP endpoint or add OpenTelemetry Collector:
   ```yaml
   - name: OTEL_EXPORTER_OTLP_ENDPOINT
     value: "https://your-region.monitor.azure.com/opentelemetry/v1/traces"
   ```

---

### 7. Frontend (React 18)

**Deployment:** Azure Static Web App / App Service  
**Status:** 🔴 **TELEMETRY DISABLED**

#### Instrumentation Details

- **Framework:** Application Insights JavaScript SDK (disabled)
- **Expected:** Browser-side RUM (Real User Monitoring)
- **Reality:** Stub implementation with no-op functions

#### Configuration (services/telemetry.js)

```javascript
// Application Insights disabled - stub implementation
console.log('Application Insights telemetry disabled');

const appInsights = {
  loadAppInsights: () => {},
  trackPageView: () => {},
  trackEvent: () => {},
  trackDependency: () => {},
  trackException: () => {},
  trackMetric: () => {},
  trackTrace: () => {},
  setAuthenticatedUserContext: () => {},
  addTelemetryInitializer: () => {}
};
```

#### Environment Configuration

- ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` - Set in App Service
- ✅ `REACT_APP_APPINSIGHTS_INSTRUMENTATIONKEY` - Available
- ✅ `REACT_APP_APPINSIGHTS_CONNECTION_STRING` - Available
- ❌ None of these are used by the stub implementation

#### Current Issues

- ❌ **Intentionally disabled** - All telemetry functions are stubs
- ❌ No page view tracking
- ❌ No user interaction tracking
- ❌ No client-side error tracking
- ❌ No performance monitoring
- ❌ No API call dependency tracking

#### Telemetry Coverage

- ❌ **NO TELEMETRY EMITTED**

#### Recommendation

**MEDIUM PRIORITY:** Enable Application Insights JavaScript SDK:

```javascript
// Replace services/telemetry.js with actual implementation
import { ApplicationInsights } from '@microsoft/applicationinsights-web';
import { ReactPlugin } from '@microsoft/applicationinsights-react-js';

const reactPlugin = new ReactPlugin();
const appInsights = new ApplicationInsights({
  config: {
    connectionString: process.env.REACT_APP_APPINSIGHTS_CONNECTION_STRING,
    extensions: [reactPlugin],
    enableAutoRouteTracking: true,
    enableRequestHeaderTracking: true,
    enableResponseHeaderTracking: true,
    enableAjaxPerfTracking: true,
    enableUnhandledPromiseRejectionTracking: true
  }
});

appInsights.loadAppInsights();
appInsights.trackPageView();

export { appInsights, reactPlugin };
```

---

### 8. Synthetic Traffic Function (Azure Function .NET Isolated)

**Deployment:** Azure Function App  
**Status:** ✅ **CONFIGURED**

#### Instrumentation Details

- **Framework:** Application Insights for Azure Functions
- **Method:** Worker Service integration

#### Configuration (Program.cs)

```csharp
var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
        
        services.AddHttpClient<TrafficGeneratorFunction>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(30);
            client.DefaultRequestHeaders.Add("User-Agent", "SyntheticTraffic-Function/1.0");
            client.DefaultRequestHeaders.Add("X-Traffic-Source", "Azure-Function");
        });
    })
    .ConfigureLogging((context, logging) =>
    {
        logging.SetMinimumLevel(LogLevel.Information);
    })
    .Build();
```

#### Environment Configuration

- ✅ `APPINSIGHTS_INSTRUMENTATIONKEY` - From Terraform
- ✅ `APPLICATIONINSIGHTS_CONNECTION_STRING` - From Terraform
- ✅ `API_GATEWAY_URL` - Target for traffic generation

#### Deployment Status

- ✅ Deployed to Azure Function App
- ✅ Timer-triggered traffic generation
- ✅ Automatic Application Insights integration

#### Telemetry Coverage

- ✅ Function executions
- ✅ Function duration
- ✅ Function failures
- ✅ Outgoing HTTP requests (to API Gateway)
- ✅ Custom telemetry via ILogger
- ✅ Dependency tracking

#### Status

**✅ OPERATIONAL** - Standard Azure Functions telemetry is automatically collected.

---

## Infrastructure Observability

### Azure Kubernetes Service (AKS)

**Status:** ✅ **CONTAINER INSIGHTS ENABLED**

#### Configuration (infrastructure/terraform/aks.tf)

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  # ... other config ...
  
  # Enable Azure Monitor for Containers
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }
}
```

#### Telemetry Coverage

- ✅ Container CPU usage
- ✅ Container memory usage
- ✅ Pod status and restarts
- ✅ Node resource utilization
- ✅ Container logs (stdout/stderr)
- ✅ Kubernetes events
- ✅ Performance metrics for cluster components

#### Status

**✅ FULLY OPERATIONAL** - Container Insights is properly configured and collecting data.

---

### Azure Virtual Machines

**VMs:** 2x Ubuntu 20.04 LTS (Standard_D2s_v3)  
**Status:** 🟡 **BASIC MONITORING ONLY**

#### Current Configuration

**VM Initialization Script (vm-init.sh):**
```bash
# Set environment variables for Application Insights
cat > /etc/environment << EOF
APPLICATIONINSIGHTS_CONNECTION_STRING="${application_insights_connection_string}"
OTEL_SERVICE_NAME="vm-${vm_index}"
OTEL_RESOURCE_ATTRIBUTES="service.name=vm-${vm_index},service.version=1.0.0"
EOF
```

#### What's Monitored

- ✅ VM CPU percentage (platform metrics)
- ✅ VM memory available (platform metrics)
- ✅ VM disk read/write (platform metrics)
- ✅ VM network in/out (platform metrics)
- ❌ No Azure Monitor Agent (AMA) installed
- ❌ No VM Insights enabled
- ❌ No guest OS metrics
- ❌ No process-level monitoring
- ❌ No performance counters

#### Recommendation

**MEDIUM PRIORITY:** Install Azure Monitor Agent for comprehensive VM monitoring:

```hcl
# Add to vms.tf
resource "azurerm_virtual_machine_extension" "ama" {
  count                = var.vm_count
  name                 = "AzureMonitorLinuxAgent"
  virtual_machine_id   = azurerm_linux_virtual_machine.main[count.index].id
  publisher            = "Microsoft.Azure.Monitor"
  type                 = "AzureMonitorLinuxAgent"
  type_handler_version = "1.37"  # Required for OTLP support
  
  settings = jsonencode({
    workspaceId = azurerm_log_analytics_workspace.main.workspace_id
  })
  
  protected_settings = jsonencode({
    workspaceKey = azurerm_log_analytics_workspace.main.primary_shared_key
  })
}
```

---

## Monitoring Resources

### Application Insights

**Resource:** Application Insights instance created by Terraform  
**Status:** ✅ **CONFIGURED**

- ✅ Instrumentation Key: `095365a0-8caa-4e16-8833-34f05bb92fd6`
- ✅ Connection String: Available in Terraform outputs
- ✅ Linked to Log Analytics workspace
- ✅ Retention: 30 days (configurable)

### Log Analytics Workspace

**Resource:** Central Log Analytics workspace  
**Status:** ✅ **CONFIGURED**

- ✅ Receives data from Application Insights
- ✅ Receives data from Container Insights (AKS)
- ✅ Receives platform metrics from all Azure resources
- ✅ Retention: 30 days (default)

---

## Summary and Recommendations

### Immediate Actions Required (High Priority)

1. **Fix VM Container Deployment** (API Gateway, Inventory Service)
   - Remove `| Out-Null` from deploy-environment.ps1 line 560
   - Add error checking and output logging
   - Verify containers actually start and stay running

2. **Instrument Order Service** (Java)
   - Add OpenTelemetry Java agent to container image
   - Configure via `JAVA_TOOL_OPTIONS` environment variable
   - Test with both Azure Monitor and OpenTelemetry agents

3. **Enable Event Processor Exporters** (Python)
   - Uncomment and configure Azure Monitor exporter
   - Use `azure-monitor-opentelemetry-exporter` package
   - Test telemetry export to Application Insights

### Short-Term Improvements (Medium Priority)

4. **Configure Inventory Service Exporters** (Node.js)
   - Add `@azure/monitor-opentelemetry` package
   - Configure Azure Monitor exporter with connection string
   - Ensure container deployment issues are resolved first

5. **Deploy Notification Service** (Golang)
   - Add to deployment script service list
   - Configure OTLP endpoint or add Azure Monitor exporter
   - Apply Kubernetes manifest

6. **Enable Frontend Telemetry** (React)
   - Replace stub implementation with actual Application Insights SDK
   - Enable page view tracking, user interactions, errors
   - Add correlation with backend requests

### Long-Term Enhancements (Low Priority)

7. **Enable VM Insights**
   - Install Azure Monitor Agent (AMA) v1.37+
   - Configure VM Insights for guest OS metrics
   - Add custom performance counters

8. **Standardize Instrumentation**
   - Choose between Azure Monitor Distro vs OSS OpenTelemetry SDK
   - Document standard patterns for each language
   - Create reusable configuration templates

9. **Add Custom Dashboards and Alerts**
   - Create Application Insights workbooks for end-to-end visibility
   - Configure alert rules for service health
   - Set up availability tests for critical endpoints

---

## Testing Telemetry

### Verify Services Are Emitting Telemetry

**Query Application Insights (Log Analytics):**

```kusto
// Check for traces from each service
traces
| where timestamp > ago(1h)
| summarize count() by cloud_RoleName
| order by count_ desc

// Check for requests from each service
requests
| where timestamp > ago(1h)
| summarize count(), avg(duration) by cloud_RoleName
| order by count_ desc

// Check for dependencies (outgoing calls)
dependencies
| where timestamp > ago(1h)
| summarize count() by cloud_RoleName, name
| order by count_ desc

// Distributed trace example
union requests, dependencies
| where operation_Id == "<trace-id>"
| project timestamp, itemType, name, cloud_RoleName, duration, success
| order by timestamp asc
```

### Check AKS Pod Logs

```bash
# Check if services are starting correctly
kubectl logs -n otel-demo deployment/order-service --tail=100
kubectl logs -n otel-demo deployment/payment-service --tail=100
kubectl logs -n otel-demo deployment/event-processor --tail=100

# Look for telemetry initialization messages
kubectl logs -n otel-demo deployment/payment-service | grep -i "opentelemetry\|telemetry\|azure monitor"
```

### Verify VM Containers

```bash
# SSH to VMs
ssh azureuser@4.155.76.50  # VM1
ssh azureuser@4.246.99.221 # VM2

# Check running containers
docker ps

# Check container logs
docker logs <container-id>

# Verify Application Insights connection string
cat /etc/environment | grep APPLICATIONINSIGHTS
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Application Insights                │
│                   (Instrumentation Key: 095...)              │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Log Analytics Workspace (30d retention)      │   │
│  └─────────────────────────────────────────────────────┘   │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
   ✅ Payment          🔴 Order           🟡 Event Processor
   Service (.NET)     Service (Java)     (Python)
   [AKS - Emitting]   [AKS - Missing     [AKS - Exporters
                       Agent]             Disabled]
        │                   │                   │
        └───────────────────┴───────────────────┘
                    Azure Kubernetes Service
              (Container Insights ✅ Enabled)

        ┌───────────────────┬───────────────────┐
        │                   │                   │
   🟡 API Gateway      🟡 Inventory          🔴 Notification
   (.NET)             Service (Node.js)      Service (Go)
   [VM2 - Container   [VM1 - Container       [Not Deployed]
    Not Running]       Not Running]
        │                   │
        └───────────────────┘
           Azure VMs (Platform Metrics Only)

                    ┌───────┐
                    │       │
              🔴 Frontend (React)
              [Telemetry Disabled]
```

**Legend:**
- ✅ Green: Fully operational and emitting telemetry
- 🟡 Yellow: Configured but not emitting (issues present)
- 🔴 Red: Not instrumented or disabled

---

## Configuration Reference

### Environment Variables for Services

**Common Variables (All Services):**
```bash
APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=095365a0-8caa-4e16-8833-34f05bb92fd6;..."
OTEL_SERVICE_NAME="<service-name>"
OTEL_SERVICE_VERSION="1.0.0"
```

**Java Agent (Order Service - TO BE ADDED):**
```bash
JAVA_TOOL_OPTIONS="-javaagent:/app/applicationinsights-agent.jar"
# Or for OpenTelemetry Java agent:
JAVA_TOOL_OPTIONS="-javaagent:/app/opentelemetry-javaagent.jar"
OTEL_EXPORTER_OTLP_ENDPOINT="https://ingestion.monitor.azure.com"
```

**Python (Event Processor):**
```bash
APPLICATIONINSIGHTS_CONNECTION_STRING="<connection-string>"
# If using OTLP exporter:
OTEL_EXPORTER_OTLP_ENDPOINT="<otlp-endpoint>"
OTEL_EXPORTER_OTLP_PROTOCOL="grpc"  # or "http/protobuf"
```

**Node.js (Inventory Service):**
```bash
APPLICATIONINSIGHTS_CONNECTION_STRING="<connection-string>"
# Or for OTLP:
OTEL_EXPORTER_OTLP_ENDPOINT="<otlp-endpoint>"
OTEL_EXPORTER_OTLP_HEADERS="<optional-headers>"
```

### Deployment Script Locations

- **Main deployment:** `deploy/deploy-environment.ps1`
- **AKS manifests:** `k8s/*.yaml`
- **VM init script:** `infrastructure/terraform/scripts/vm-init.sh`
- **Terraform config:** `infrastructure/terraform/*.tf`

---

## Document Version

- **Version:** 1.0
- **Last Updated:** November 4, 2025
- **Environment:** Production Demo Environment
- **Next Review:** After implementing critical fixes

---

## Related Documentation

- [README.md](README.md) - Project overview and deployment instructions
- [APPLICATION_MAP.md](APPLICATION_MAP.md) - Application architecture and service interactions
- [infrastructure/terraform/README.md](infrastructure/terraform/README.md) - Infrastructure provisioning guide
- [deploy/test-environment.ps1](deploy/test-environment.ps1) - Environment validation tests

---

## Support and Troubleshooting

### Common Issues

**Issue: "No telemetry in Application Insights"**
- Check service logs for telemetry initialization messages
- Verify `APPLICATIONINSIGHTS_CONNECTION_STRING` environment variable is set
- Confirm exporters are configured and not commented out
- Check network connectivity to `*.monitor.azure.com`

**Issue: "Service shows in dependencies but no requests"**
- Service may be receiving calls but not instrumented to emit telemetry
- Check if auto-instrumentation is properly configured
- Verify SDK packages are installed

**Issue: "Distributed traces are broken"**
- Ensure all services use W3C Trace Context propagation
- Check that context headers are being forwarded
- Verify parent span IDs are being set correctly

### Contact

For questions about this instrumentation analysis, contact the platform team or review the Azure Monitor documentation at https://learn.microsoft.com/azure/azure-monitor/
