// Simplified OpenTelemetry setup using auto-instrumentations
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

// Set environment variables for OpenTelemetry configuration
process.env.OTEL_SERVICE_NAME = process.env.SERVICE_NAME || 'inventory-service';
process.env.OTEL_SERVICE_VERSION = process.env.SERVICE_VERSION || '1.0.0';
process.env.OTEL_RESOURCE_ATTRIBUTES = `service.name=${process.env.OTEL_SERVICE_NAME},service.version=${process.env.OTEL_SERVICE_VERSION}`;

// Simple auto-instrumentation setup
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

module.exports = {};