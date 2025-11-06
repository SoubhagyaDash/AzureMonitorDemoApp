# Azure Monitor AKS App Monitoring Preview Setup Guide

This document outlines all environment changes required to use the Azure Monitor AKS App Monitoring (preview) feature with this demo application.

## Overview

Azure Monitor AKS App Monitoring (preview) enables automatic OTLP endpoint injection for applications running on AKS, supporting both:
- **Auto-instrumentation**: Automatic agent injection for supported languages (Java, .NET, Node.js, Python)
- **SDK-based instrumentation**: OTLP endpoint configuration for applications using OSS OpenTelemetry SDKs

## Prerequisites

### 1. Feature Registration

Enable the preview feature on your Azure subscription:

```bash
# Register the feature
az feature register --namespace Microsoft.ContainerService --name AzureMonitorAppMonitoringPreview

# Wait for registration to complete (may take 10-15 minutes)
az feature show --namespace Microsoft.ContainerService --name AzureMonitorAppMonitoringPreview

# Refresh the provider registration
az provider register --namespace Microsoft.ContainerService
```

### 2. AKS Cluster Requirements

- **Kubernetes Version**: 1.30 or higher (this demo uses 1.31.11 with LTS support)
- **SKU Tier**: Premium (required for preview features)
- **Support Plan**: AKSLongTermSupport
- **Azure Monitor Integration**: Log Analytics workspace connected

### 3. Application Insights Workspace

- **Workspace-based Application Insights** resource (classic mode not supported)
- Connection string with the format: `InstrumentationKey=...;IngestionEndpoint=...;LiveEndpoint=...;ApplicationId=...`

## Infrastructure Changes

### Terraform Configuration (`infrastructure/terraform/`)

#### AKS Cluster Configuration (`aks.tf`)

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-${var.project_name}-${var.environment}"
  kubernetes_version  = var.kubernetes_version  # Must be >= 1.30
  sku_tier           = "Premium"                 # Required for preview
  support_plan       = "AKSLongTermSupport"      # Recommended for stability

  default_node_pool {
    name                = "default"
    vm_size             = var.aks_vm_size
    vnet_subnet_id      = azurerm_subnet.aks_subnet.id
    
    # Autoscaling configuration (optional but recommended)
    enable_auto_scaling = var.aks_enable_autoscale
    node_count          = var.aks_enable_autoscale ? null : var.aks_node_count
    min_count           = var.aks_enable_autoscale ? var.aks_min_count : null
    max_count           = var.aks_enable_autoscale ? var.aks_max_count : null
  }

  # Azure Monitor integration (required)
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }
  
  # Other configurations...
}
```

#### Variables (`variables.tf`)

```hcl
variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.31.11"  # Must be >= 1.30 for preview
}

variable "aks_enable_autoscale" {
  description = "Enable autoscaling for AKS default node pool"
  type        = bool
  default     = true
}

variable "aks_min_count" {
  description = "Minimum number of nodes when autoscaling is enabled"
  type        = number
  default     = 2
}

variable "aks_max_count" {
  description = "Maximum number of nodes when autoscaling is enabled"
  type        = number
  default     = 10
}
```

## Kubernetes Configuration

### 1. Instrumentation Custom Resource (`k8s/instrumentation-otel-demo.yaml`)

Create an `Instrumentation` CR to configure Azure Monitor app monitoring:

```yaml
apiVersion: monitor.azure.com/v1
kind: Instrumentation
metadata:
  name: otel-demo-instrumentation
  namespace: otel-demo
spec:
  destination:
    applicationInsightsConnectionString: "InstrumentationKey=...;IngestionEndpoint=...;LiveEndpoint=...;ApplicationId=..."
  settings:
    # Empty array opts out of automatic agent injection
    # Use this when you want SDK-based apps to only receive OTLP endpoints
    autoInstrumentationPlatforms: []
```

**Configuration Options**:

- **`autoInstrumentationPlatforms: []`**: Disables auto-instrumentation for all languages. Azure Monitor will only inject OTLP endpoint environment variables.
- **`autoInstrumentationPlatforms: ["java", "dotnet"]`**: Enables auto-instrumentation for specific languages globally.

### 2. Service Deployment Annotations

#### For Auto-Instrumentation (e.g., Java)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: otel-demo
spec:
  template:
    metadata:
      annotations:
        # Language-specific annotation for auto-instrumentation
        instrumentation.opentelemetry.io/inject-java: "otel-demo-instrumentation"
    spec:
      containers:
      - name: order-service
        image: your-acr.azurecr.io/order-service:latest
        env:
        - name: OTEL_SERVICE_NAME
          value: "order-service"
        # Java agent is automatically injected
        # OTLP endpoints are automatically configured
```

**Available Language Annotations**:
- `instrumentation.opentelemetry.io/inject-java`
- `instrumentation.opentelemetry.io/inject-dotnet`
- `instrumentation.opentelemetry.io/inject-nodejs`
- `instrumentation.opentelemetry.io/inject-python`

#### For SDK-Based Instrumentation (OTLP Endpoints Only)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: otel-demo
spec:
  template:
    metadata:
      annotations:
        # Generic annotation for OTLP endpoint injection only
        instrumentation.opentelemetry.io/inject-configuration: "otel-demo-instrumentation"
    spec:
      containers:
      - name: payment-service
        image: your-acr.azurecr.io/payment-service:latest
        env:
        - name: OTEL_SERVICE_NAME
          value: "payment-service"
        # Application uses OSS OpenTelemetry SDK
        # Azure Monitor injects these environment variables:
        # - OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
        # - OTEL_EXPORTER_OTLP_METRICS_ENDPOINT
        # - OTEL_EXPORTER_OTLP_LOGS_ENDPOINT
```

## Application Code Changes

### .NET Service (e.g., Payment Service)

#### Project Dependencies (`PaymentService.csproj`)

```xml
<ItemGroup>
  <PackageReference Include="OpenTelemetry" Version="1.9.0" />
  <PackageReference Include="OpenTelemetry.Extensions.Hosting" Version="1.9.0" />
  <PackageReference Include="OpenTelemetry.Instrumentation.AspNetCore" Version="1.9.0" />
  <PackageReference Include="OpenTelemetry.Instrumentation.Http" Version="1.9.0" />
  <PackageReference Include="OpenTelemetry.Exporter.OpenTelemetryProtocol" Version="1.9.0" />
</ItemGroup>
```

#### OpenTelemetry Configuration (`Program.cs`)

```csharp
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Exporter;

// Read OTLP endpoints from environment (injected by Azure Monitor)
var otlpTracesEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT");
var otlpMetricsEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT");
var otlpLogsEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT");

builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: "payment-service", serviceVersion: "1.0.0"))
    .WithTracing(tracing =>
    {
        tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation();

        if (!string.IsNullOrEmpty(otlpTracesEndpoint))
        {
            tracing.AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri(otlpTracesEndpoint);
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
            });
        }
    })
    .WithMetrics(metrics =>
    {
        metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation();

        if (!string.IsNullOrEmpty(otlpMetricsEndpoint))
        {
            metrics.AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri(otlpMetricsEndpoint);
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
            });
        }
    });

// Configure logging with OTLP export
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
    
    if (!string.IsNullOrEmpty(otlpLogsEndpoint))
    {
        logging.AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(otlpLogsEndpoint);
            options.Protocol = OtlpExportProtocol.HttpProtobuf;
        });
    }
});
```

### Go Service (e.g., Notification Service)

#### Module Dependencies (`go.mod`)

```go
require (
    // OpenTelemetry Core - Latest stable v1.31.0
    go.opentelemetry.io/otel v1.31.0
    go.opentelemetry.io/otel/metric v1.31.0
    go.opentelemetry.io/otel/sdk v1.31.0
    go.opentelemetry.io/otel/sdk/metric v1.31.0
    go.opentelemetry.io/otel/trace v1.31.0
    
    // OTLP Exporters
    go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.31.0
    go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp v1.31.0
    go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp v0.7.0
    go.opentelemetry.io/otel/log v0.7.0
    go.opentelemetry.io/otel/sdk/log v0.7.0
)
```

#### Configuration (`internal/config/config.go`)

```go
type Config struct {
    // OpenTelemetry configuration
    OTLPTracesEndpoint  string
    OTLPMetricsEndpoint string
    OTLPLogsEndpoint    string
    ServiceName         string
}

func Load() *Config {
    return &Config{
        OTLPTracesEndpoint:  getEnv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", ""),
        OTLPMetricsEndpoint: getEnv("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", ""),
        OTLPLogsEndpoint:    getEnv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", ""),
        ServiceName:         getEnv("OTEL_SERVICE_NAME", "notification-service"),
    }
}
```

#### Telemetry Initialization (`internal/telemetry/telemetry.go`)

```go
import (
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
    "go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
)

func newTraceProvider(ctx context.Context, cfg *config.Config, res *resource.Resource) (*sdktrace.TracerProvider, error) {
    if cfg.OTLPTracesEndpoint == "" {
        return sdktrace.NewTracerProvider(sdktrace.WithResource(res)), nil
    }

    // Parse endpoint - Azure Monitor provides complete URL with path
    // Example: "http://10.0.2.91:28331/v1/traces"
    parsedURL, err := url.Parse(cfg.OTLPTracesEndpoint)
    if err != nil {
        return nil, fmt.Errorf("failed to parse traces endpoint: %w", err)
    }

    traceExporter, err := otlptracehttp.New(
        ctx,
        otlptracehttp.WithEndpoint(parsedURL.Host),  // Just "host:port"
        otlptracehttp.WithURLPath(parsedURL.Path),   // Explicit path "/v1/traces"
        otlptracehttp.WithInsecure(),
        otlptracehttp.WithCompression(otlptracehttp.GzipCompression),
    )
    if err != nil {
        return nil, fmt.Errorf("failed to create trace exporter: %w", err)
    }

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(traceExporter),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.AlwaysSample()),
    )

    return tp, nil
}

// Similar pattern for metrics and logs...
```

### Python Service (e.g., Event Processor)

#### Dependencies (`requirements.txt`)

```
opentelemetry-api==1.25.0
opentelemetry-sdk==1.25.0
opentelemetry-instrumentation==0.46b0
opentelemetry-exporter-otlp-proto-grpc==1.25.0
```

#### Telemetry Setup (`main.py`)

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor

def setup_telemetry():
    # Read OTLP endpoints from environment (injected by Azure Monitor)
    otlp_traces_endpoint = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
    otlp_metrics_endpoint = os.getenv("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT")
    otlp_logs_endpoint = os.getenv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT")
    
    resource = Resource.create({
        "service.name": "event-processor",
        "service.version": "1.0.0",
    })
    
    # Configure tracing
    if otlp_traces_endpoint:
        trace_provider = TracerProvider(resource=resource)
        otlp_exporter = OTLPSpanExporter(endpoint=otlp_traces_endpoint, insecure=True)
        span_processor = BatchSpanProcessor(otlp_exporter)
        trace_provider.add_span_processor(span_processor)
        trace.set_tracer_provider(trace_provider)
    
    # Configure metrics
    if otlp_metrics_endpoint:
        metric_reader = PeriodicExportingMetricReader(
            OTLPMetricExporter(endpoint=otlp_metrics_endpoint, insecure=True),
            export_interval_millis=30000
        )
        metrics.set_meter_provider(MeterProvider(
            resource=resource,
            metric_readers=[metric_reader]
        ))
    
    # Configure logging
    if otlp_logs_endpoint:
        logger_provider = LoggerProvider(resource=resource)
        logger_provider.add_log_record_processor(
            BatchLogRecordProcessor(
                OTLPLogExporter(endpoint=otlp_logs_endpoint, insecure=True)
            )
        )
        handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
        logging.getLogger().addHandler(handler)
```

## Environment Variables Injected by Azure Monitor

When you annotate a pod with `instrumentation.opentelemetry.io/inject-configuration`, Azure Monitor automatically injects these environment variables:

```bash
# Injected by Azure Monitor webhook
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://<node-ip>:28331/v1/traces
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://<node-ip>:28333/v1/metrics
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://<node-ip>:28331/v1/logs

# Standard OpenTelemetry environment variables (if not already set)
OTEL_SERVICE_NAME=<your-service-name>
OTEL_RESOURCE_ATTRIBUTES=service.namespace=otel-demo
```

**Note**: The IP addresses and ports are node-local OTLP receivers managed by Azure Monitor agents running on each AKS node.

## Deployment Process

### 1. Update Infrastructure

```bash
cd infrastructure/terraform

# Update kubernetes_version in terraform.tfvars or variables.tf
# kubernetes_version = "1.31.11"

terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Deploy Instrumentation CR

```bash
cd k8s

# Update connection string in instrumentation-otel-demo.yaml
# Then apply:
kubectl apply -f instrumentation-otel-demo.yaml
```

### 3. Deploy Applications

Update deployment manifests with appropriate annotations and apply:

```bash
kubectl apply -f payment-service.yaml
kubectl apply -f notification-service.yaml
kubectl apply -f event-processor.yaml
kubectl apply -f order-service.yaml
```

### 4. Verify OTLP Endpoint Injection

Check that environment variables are injected:

```bash
kubectl get pod -n otel-demo -l app=payment-service -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")].value}'
```

Expected output: `http://<node-ip>:28331/v1/traces`

### 5. Verify Telemetry Export

Check application logs for successful OTLP export:

```bash
kubectl logs -n otel-demo -l app=payment-service --tail=50 | grep -i "otlp\|export"
```

Look for log entries indicating successful telemetry export with HTTP 200 responses.

## Troubleshooting

### Issue: OTLP endpoints not injected

**Symptoms**: Environment variables like `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` are not present in pod.

**Solutions**:
1. Verify Instrumentation CR is applied: `kubectl get instrumentation -n otel-demo`
2. Check webhook configuration: `kubectl get mutatingwebhookconfiguration | grep azure-monitor`
3. Verify pod has correct annotation: `kubectl get pod <pod-name> -n otel-demo -o yaml | grep instrumentation.opentelemetry.io`
4. Delete and recreate pod to trigger webhook injection

### Issue: Connection refused to OTLP endpoint

**Symptoms**: Logs show errors like "connection refused" or "dial tcp <ip>:28331: connect: connection refused"

**Solutions**:
1. Check Azure Monitor agents are running: `kubectl get pods -n kube-system -l app=ama-metrics`
2. Verify node has OTLP receivers listening: `kubectl debug node/<node-name> -it --image=nicolaka/netshoot -- netstat -tlnp | grep 28331`
3. Check Azure Monitor agent logs: `kubectl logs -n kube-system -l app=ama-metrics --tail=100`
4. Wait 2-3 minutes after pod creation for receivers to initialize

### Issue: HTTP 400 Bad Request from OTLP endpoint

**Symptoms**: Telemetry export fails with "400 Bad Request" errors

**Solutions**:
1. Verify OTLP protocol matches (HTTP Protobuf vs gRPC)
2. Check resource attributes are valid
3. Ensure service name is set correctly
4. Review Azure Monitor agent version compatibility

### Issue: Telemetry not appearing in Application Insights

**Symptoms**: No errors in logs, but telemetry not visible in Azure portal

**Solutions**:
1. Verify Application Insights connection string is correct in Instrumentation CR
2. Check Application Insights ingestion quota hasn't been exceeded
3. Wait 2-5 minutes for telemetry to propagate
4. Query directly using Log Analytics: `requests | where cloud_RoleName == "payment-service"`

## Mixed Instrumentation Strategy

This demo uses a **mixed instrumentation approach**:

| Service | Language | Strategy | Annotation |
|---------|----------|----------|------------|
| order-service | Java | Auto-instrumentation | `inject-java` |
| payment-service | .NET | OSS SDK + OTLP | `inject-configuration` |
| notification-service | Go | OSS SDK + OTLP | `inject-configuration` |
| event-processor | Python | OSS SDK + OTLP | `inject-configuration` |

**Benefits**:
- **order-service**: Zero code changes, automatic Java agent injection
- **payment/notification/event-processor**: Full control over instrumentation, custom metrics, advanced tracing

## Best Practices

1. **Resource Attributes**: Include comprehensive resource attributes (service.name, service.version, deployment.environment) for better telemetry correlation
2. **Sampling**: Use appropriate sampling strategies based on traffic volume
3. **Error Handling**: Gracefully handle missing OTLP endpoints (application should work even if Azure Monitor is unavailable)
4. **Health Checks**: Don't depend on telemetry export for application health
5. **Probe Delays**: Increase `initialDelaySeconds` for services with auto-instrumentation (agent initialization takes time)
6. **Batch Processing**: Use batch processors for traces/metrics/logs to reduce network overhead
7. **Compression**: Enable gzip compression for OTLP exports to reduce bandwidth usage

## References

- [Azure Monitor OpenTelemetry Distro](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable)
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/)
- [OTLP Protocol](https://opentelemetry.io/docs/specs/otlp/)
- [OpenTelemetry .NET](https://opentelemetry.io/docs/languages/net/)
- [OpenTelemetry Go](https://opentelemetry.io/docs/languages/go/)
- [OpenTelemetry Python](https://opentelemetry.io/docs/languages/python/)

## Support

For issues with Azure Monitor AKS App Monitoring preview:
- Azure Support Portal: https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade
- GitHub Issues: https://github.com/Azure/azure-monitor-opentelemetry
