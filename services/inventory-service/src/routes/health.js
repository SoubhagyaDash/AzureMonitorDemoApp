const express = require('express');
const { trace, SpanStatusCode } = require('@opentelemetry/api');

const router = express.Router();
const tracer = trace.getTracer('inventory-service');

// Health check endpoint
router.get('/', async (req, res) => {
  const span = tracer.startSpan('health_check');
  
  try {
    span.setAttributes({
      'health.check': 'basic',
      'service.name': 'inventory-service'
    });

    // Basic health check
    const healthCheck = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      service: 'inventory-service',
      version: '1.0.0',
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      checks: {
        database: 'healthy', // Would check actual database in real implementation
        cache: 'healthy',    // Would check Redis in real implementation
        external_apis: 'healthy'
      }
    };

    span.setAttributes({
      'health.status': healthCheck.status,
      'health.uptime': healthCheck.uptime
    });

    span.setStatus({ code: SpanStatusCode.OK });
    res.json(healthCheck);
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    res.status(500).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  } finally {
    span.end();
  }
});

// Detailed health check
router.get('/detailed', async (req, res) => {
  const span = tracer.startSpan('detailed_health_check');
  
  try {
    // Simulate more comprehensive health checks
    const checks = await Promise.all([
      checkDatabase(),
      checkCache(),
      checkExternalAPIs()
    ]);

    const isHealthy = checks.every(check => check.status === 'healthy');
    const statusCode = isHealthy ? 200 : 503;

    const healthCheck = {
      status: isHealthy ? 'healthy' : 'unhealthy',
      timestamp: new Date().toISOString(),
      service: 'inventory-service',
      version: '1.0.0',
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      checks: {
        database: checks[0],
        cache: checks[1],
        external_apis: checks[2]
      }
    };

    span.setAttributes({
      'health.status': healthCheck.status,
      'health.database': checks[0].status,
      'health.cache': checks[1].status,
      'health.external_apis': checks[2].status
    });

    span.setStatus({ code: SpanStatusCode.OK });
    res.status(statusCode).json(healthCheck);
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    res.status(500).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  } finally {
    span.end();
  }
});

// Readiness probe
router.get('/ready', (req, res) => {
  const span = tracer.startSpan('readiness_check');
  
  try {
    // Check if service is ready to accept traffic
    const ready = {
      ready: true,
      timestamp: new Date().toISOString(),
      service: 'inventory-service'
    };

    span.setAttributes({
      'readiness.ready': ready.ready
    });

    span.setStatus({ code: SpanStatusCode.OK });
    res.json(ready);
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    res.status(503).json({
      ready: false,
      timestamp: new Date().toISOString(),
      error: error.message
    });
  } finally {
    span.end();
  }
});

// Liveness probe
router.get('/live', (req, res) => {
  const span = tracer.startSpan('liveness_check');
  
  try {
    const live = {
      alive: true,
      timestamp: new Date().toISOString(),
      service: 'inventory-service',
      pid: process.pid
    };

    span.setAttributes({
      'liveness.alive': live.alive,
      'liveness.pid': live.pid
    });

    span.setStatus({ code: SpanStatusCode.OK });
    res.json(live);
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    res.status(503).json({
      alive: false,
      timestamp: new Date().toISOString(),
      error: error.message
    });
  } finally {
    span.end();
  }
});

// Helper functions for health checks
async function checkDatabase() {
  // Simulate database health check
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({
        status: Math.random() > 0.05 ? 'healthy' : 'unhealthy',
        responseTime: Math.floor(Math.random() * 50) + 10,
        lastChecked: new Date().toISOString()
      });
    }, Math.random() * 100);
  });
}

async function checkCache() {
  // Simulate cache health check
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({
        status: Math.random() > 0.02 ? 'healthy' : 'unhealthy',
        responseTime: Math.floor(Math.random() * 20) + 5,
        lastChecked: new Date().toISOString()
      });
    }, Math.random() * 50);
  });
}

async function checkExternalAPIs() {
  // Simulate external API health check
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({
        status: Math.random() > 0.1 ? 'healthy' : 'unhealthy',
        responseTime: Math.floor(Math.random() * 200) + 50,
        lastChecked: new Date().toISOString()
      });
    }, Math.random() * 200);
  });
}

module.exports = router;