// Import telemetry first
require('./telemetry');

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
require('dotenv').config();

const { trace, metrics, context, SpanStatusCode } = require('@opentelemetry/api');
const winston = require('winston');
const client = require('prom-client');

// Import routes and middleware
const inventoryRoutes = require('./routes/inventory');
const healthRoutes = require('./routes/health');
const failureInjection = require('./middleware/failureInjection');
const { metricsMiddleware } = require('./middleware/metrics');

// Configure logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
    new winston.transports.File({ filename: 'logs/combined.log' })
  ]
});

// Get tracer and meter
const tracer = trace.getTracer('inventory-service');
const meter = metrics.getMeter('inventory-service');

// Create custom metrics
const httpRequestsTotal = meter.createCounter('http_requests_total', {
  description: 'Total number of HTTP requests'
});

const httpRequestDuration = meter.createHistogram('http_request_duration_seconds', {
  description: 'HTTP request duration in seconds'
});

const inventoryOperationsTotal = meter.createCounter('inventory_operations_total', {
  description: 'Total number of inventory operations'
});

// Initialize Express app
const app = express();
const port = process.env.PORT || 3000;

// Security middleware
app.use(helmet());
app.use(cors());

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Custom middleware for tracing and metrics
app.use((req, res, next) => {
  const startTime = Date.now();
  
  // Create span for each request
  const span = tracer.startSpan(`${req.method} ${req.path}`);
  
  // Set span attributes
  span.setAttributes({
    'http.method': req.method,
    'http.url': req.url,
    'http.scheme': req.protocol,
    'http.host': req.get('host'),
    'http.user_agent': req.get('user-agent') || '',
    'http.route': req.path
  });

  // Add span to context
  context.with(trace.setSpan(context.active(), span), () => {
    // Log request
    logger.info('HTTP Request', {
      method: req.method,
      url: req.url,
      userAgent: req.get('user-agent'),
      ip: req.ip,
      traceId: span.spanContext().traceId,
      spanId: span.spanContext().spanId
    });

    // Override res.end to capture response details
    const originalEnd = res.end;
    res.end = function(...args) {
      const duration = (Date.now() - startTime) / 1000;
      
      // Set response attributes on span
      span.setAttributes({
        'http.status_code': res.statusCode,
        'http.response_size': res.get('content-length') || 0
      });

      // Record metrics
      httpRequestsTotal.add(1, {
        method: req.method,
        status_code: res.statusCode.toString(),
        route: req.path
      });

      httpRequestDuration.record(duration, {
        method: req.method,
        status_code: res.statusCode.toString(),
        route: req.path
      });

      // Log response
      logger.info('HTTP Response', {
        method: req.method,
        url: req.url,
        statusCode: res.statusCode,
        duration: duration,
        traceId: span.spanContext().traceId,
        spanId: span.spanContext().spanId
      });

      // End span
      if (res.statusCode >= 400) {
        span.recordException(new Error(`HTTP ${res.statusCode}`));
        span.setStatus({ code: SpanStatusCode.ERROR });
      } else {
        span.setStatus({ code: SpanStatusCode.OK });
      }
      
      span.end();
      
      // Call original end
      originalEnd.apply(this, args);
    };

    next();
  });
});

// Failure injection middleware
app.use(failureInjection);

// Metrics middleware
app.use(metricsMiddleware);

// Routes
app.use('/api/inventory', inventoryRoutes);
app.use('/health', healthRoutes);

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'inventory-service',
    version: '1.0.0',
    status: 'running',
    timestamp: new Date().toISOString()
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  const span = trace.getActiveSpan();
  if (span) {
    span.recordException(err);
    span.setStatus({ code: trace.SpanStatusCode.ERROR, message: err.message });
  }

  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    url: req.url,
    method: req.method
  });

  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    message: `Route ${req.method} ${req.url} not found`
  });
});

// Start server
const server = app.listen(port, () => {
  logger.info(`Inventory service listening on port ${port}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    logger.info('HTTP server closed');
  });
});

process.on('SIGINT', () => {
  logger.info('SIGINT signal received: closing HTTP server');
  server.close(() => {
    logger.info('HTTP server closed');
    process.exit(0);
  });
});

module.exports = app;