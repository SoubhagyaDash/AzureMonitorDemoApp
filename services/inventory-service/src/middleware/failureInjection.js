const { trace, SpanStatusCode } = require('@opentelemetry/api');

// Failure injection configuration
const failureConfig = {
  enabled: process.env.FAILURE_INJECTION_ENABLED !== 'false',
  latencyProbability: parseFloat(process.env.LATENCY_INJECTION_PROBABILITY) || 0.1,
  errorProbability: parseFloat(process.env.ERROR_INJECTION_PROBABILITY) || 0.05,
  latencyMin: parseInt(process.env.LATENCY_MIN_MS) || 100,
  latencyMax: parseInt(process.env.LATENCY_MAX_MS) || 2000
};

const errorTypes = [
  'TIMEOUT',
  'DATABASE_ERROR',
  'NETWORK_ERROR',
  'VALIDATION_ERROR',
  'RATE_LIMIT_ERROR'
];

function getRandomDelay() {
  return Math.floor(Math.random() * (failureConfig.latencyMax - failureConfig.latencyMin + 1)) + failureConfig.latencyMin;
}

function getRandomError() {
  const errorType = errorTypes[Math.floor(Math.random() * errorTypes.length)];
  
  switch (errorType) {
    case 'TIMEOUT':
      return { statusCode: 408, message: 'Request timeout - simulated failure' };
    case 'DATABASE_ERROR':
      return { statusCode: 503, message: 'Database connection failed - simulated failure' };
    case 'NETWORK_ERROR':
      return { statusCode: 502, message: 'Network error - simulated failure' };
    case 'VALIDATION_ERROR':
      return { statusCode: 400, message: 'Validation failed - simulated failure' };
    case 'RATE_LIMIT_ERROR':
      return { statusCode: 429, message: 'Rate limit exceeded - simulated failure' };
    default:
      return { statusCode: 500, message: 'Internal server error - simulated failure' };
  }
}

const failureInjectionMiddleware = async (req, res, next) => {
  if (!failureConfig.enabled) {
    return next();
  }

  const span = trace.getActiveSpan();
  
  // Skip failure injection for health check endpoints
  if (req.path.includes('/health') || req.path.includes('/metrics')) {
    return next();
  }

  try {
    // Inject latency
    if (Math.random() < failureConfig.latencyProbability) {
      const delay = getRandomDelay();
      
      if (span) {
        span.addEvent('failure_injection.latency', {
          'failure.type': 'latency',
          'failure.delay_ms': delay
        });
      }
      
      console.log(`[FAILURE INJECTION] Injecting ${delay}ms latency for ${req.method} ${req.path}`);
      
      await new Promise(resolve => setTimeout(resolve, delay));
    }

    // Inject errors
    if (Math.random() < failureConfig.errorProbability) {
      const error = getRandomError();
      
      if (span) {
        span.addEvent('failure_injection.error', {
          'failure.type': 'error',
          'failure.error_type': error.message,
          'failure.status_code': error.statusCode
        });
        span.setStatus({
          code: SpanStatusCode.ERROR,
          message: error.message
        });
      }
      
      console.log(`[FAILURE INJECTION] Injecting error for ${req.method} ${req.path}: ${error.message}`);
      
      return res.status(error.statusCode).json({
        error: error.message,
        injected: true,
        timestamp: new Date().toISOString()
      });
    }

    next();
    
  } catch (error) {
    console.error('[FAILURE INJECTION] Error in failure injection middleware:', error);
    next();
  }
};

module.exports = failureInjectionMiddleware;
