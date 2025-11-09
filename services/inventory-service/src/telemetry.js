// OpenTelemetry SDK Configuration for Inventory Service
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');
const { BatchSpanProcessor, ConsoleSpanExporter } = require('@opentelemetry/sdk-trace-node');
const { PeriodicExportingMetricReader, ConsoleMetricExporter } = require('@opentelemetry/sdk-metrics');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-grpc');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-grpc');
const { BatchLogRecordProcessor, ConsoleLogRecordExporter } = require('@opentelemetry/sdk-logs');

// Service configuration
const serviceName = process.env.SERVICE_NAME || 'inventory-service';
const serviceVersion = process.env.SERVICE_VERSION || '1.0.0';
const environment = process.env.ENVIRONMENT || 'development';

console.log(`Initializing OpenTelemetry for ${serviceName} v${serviceVersion} in ${environment} environment`);

// Configure resource attributes
const applicationId = process.env.APPLICATION_INSIGHTS_APPLICATION_ID || 'e4580258-7369-47ea-a880-d85e204cfe5d';
const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: serviceName,
  [SemanticResourceAttributes.SERVICE_VERSION]: serviceVersion,
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: environment,
  [SemanticResourceAttributes.SERVICE_INSTANCE_ID]: process.env.HOSTNAME || require('os').hostname(),
  'service.language': 'nodejs',
  'service.runtime': 'nodejs',
  'service.runtime.version': process.version,
  'microsoft.applicationId': applicationId
});

// Configure OTLP exporters with gRPC
const otlpTracesEndpoint = process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT || 'localhost:4319';
const otlpMetricsEndpoint = process.env.OTEL_EXPORTER_OTLP_METRICS_ENDPOINT || 'localhost:4317';
const otlpLogsEndpoint = process.env.OTEL_EXPORTER_OTLP_LOGS_ENDPOINT || 'localhost:4319';
const otlpHeaders = process.env.OTEL_EXPORTER_OTLP_HEADERS || '';

const otlpTraceExporter = new OTLPTraceExporter({
  url: otlpTracesEndpoint,
  headers: otlpHeaders ? JSON.parse(otlpHeaders) : {}
});

const otlpMetricExporter = new OTLPMetricExporter({
  url: otlpMetricsEndpoint,
  headers: otlpHeaders ? JSON.parse(otlpHeaders) : {}
});

const otlpLogExporter = new OTLPLogExporter({
  url: otlpLogsEndpoint,
  headers: otlpHeaders ? JSON.parse(otlpHeaders) : {}
});

// Configure trace processors
const traceProcessors = [
  new BatchSpanProcessor(otlpTraceExporter, {
    maxQueueSize: 1000,
    scheduledDelayMillis: 5000
  })
];

// Add console exporter in development
if (environment === 'development') {
  traceProcessors.push(new BatchSpanProcessor(new ConsoleSpanExporter()));
}

// Configure metric readers
const metricReaders = [
  new PeriodicExportingMetricReader({
    exporter: otlpMetricExporter,
    exportIntervalMillis: 60000, // Export every 60 seconds
  })
];

// Add console metric reader in development
if (environment === 'development') {
  metricReaders.push(
    new PeriodicExportingMetricReader({
      exporter: new ConsoleMetricExporter(),
      exportIntervalMillis: 60000
    })
  );
}

// Configure log processors
const logProcessors = [
  new BatchLogRecordProcessor(otlpLogExporter)
];

if (environment === 'development') {
  logProcessors.push(new BatchLogRecordProcessor(new ConsoleLogRecordExporter()));
}

// Initialize OpenTelemetry SDK
const sdk = new NodeSDK({
  resource: resource,
  spanProcessors: traceProcessors,
  metricReader: metricReaders[0], // Primary metric reader
  logRecordProcessors: logProcessors,
  instrumentations: [
    getNodeAutoInstrumentations({
      // Configure individual instrumentations
      '@opentelemetry/instrumentation-http': {
        enabled: true,
        ignoreIncomingRequestHook: (request) => {
          // Ignore health check requests
          return request.url?.includes('/health') || false;
        },
        ignoreOutgoingRequestHook: (request) => {
          // Ignore internal health checks
          return request.path?.includes('/health') || false;
        },
        requestHook: (span, request) => {
          span.setAttribute('http.flavor', request.httpVersion);
        },
        responseHook: (span, response) => {
          span.setAttribute('http.response.header.content-type', response.headers['content-type']);
        },
        requireParentforOutgoingSpans: false,
        requireParentforIncomingSpans: false,
        serverName: serviceName,
        headersToSpanAttributes: {
          server: {
            requestHeaders: ['x-request-id', 'x-correlation-id', 'user-agent'],
            responseHeaders: ['content-type']
          },
          client: {
            requestHeaders: ['x-request-id', 'x-correlation-id'],
            responseHeaders: ['content-type']
          }
        }
      },
      '@opentelemetry/instrumentation-express': {
        enabled: true,
        requestHook: (span, requestInfo) => {
          span.setAttribute('express.type', requestInfo.layerType);
        }
      },
      '@opentelemetry/instrumentation-mongodb': {
        enabled: true,
        enhancedDatabaseReporting: true,
      },
      '@opentelemetry/instrumentation-redis-4': {
        enabled: true,
        requireParentSpan: false
      },
      '@opentelemetry/instrumentation-winston': {
        enabled: true,
        logSeverity: true,
        logHook: (span, record) => {
          record['resource.service.name'] = serviceName;
        }
      },
      '@opentelemetry/instrumentation-fs': {
        enabled: false, // Disable file system instrumentation to reduce noise
      },
      '@opentelemetry/instrumentation-dns': {
        enabled: false, // Disable DNS instrumentation
      },
      '@opentelemetry/instrumentation-net': {
        enabled: false, // Disable net instrumentation
      }
    })
  ]
});

// Start the SDK
// Start the SDK
try {
  sdk.start();
  console.log('✅ OpenTelemetry SDK initialized successfully');
  console.log(`   Service: ${serviceName}`);
  console.log(`   Version: ${serviceVersion}`);
  console.log(`   Environment: ${environment}`);
  console.log(`   OTLP Traces Endpoint: ${otlpTracesEndpoint}`);
  console.log(`   OTLP Metrics Endpoint: ${otlpMetricsEndpoint}`);
  console.log(`   OTLP Logs Endpoint: ${otlpLogsEndpoint}`);
  console.log(`   Azure Monitor: ${azureConnectionString ? 'Enabled' : 'Disabled'}`);
} catch (error) {
  console.error('❌ Error initializing OpenTelemetry SDK:', error);
}

// Graceful shutdown
process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => {
      console.log('OpenTelemetry SDK shut down successfully');
      process.exit(0);
    })
    .catch((error) => {
      console.error('Error shutting down OpenTelemetry SDK:', error);
      process.exit(1);
    });
});

module.exports = sdk;