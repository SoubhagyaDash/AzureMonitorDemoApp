const client = require('prom-client');

// Create a Registry to register the metrics
const register = new client.Registry();

// Add a default label which is added to all metrics
register.setDefaultLabels({
  app: 'inventory-service'
});

// Enable the collection of default metrics
client.collectDefaultMetrics({ register });

// Create custom metrics
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register]
});

const activeConnections = new client.Gauge({
  name: 'active_connections',
  help: 'Number of active connections',
  registers: [register]
});

const inventoryOperationsTotal = new client.Counter({
  name: 'inventory_operations_total',
  help: 'Total number of inventory operations',
  labelNames: ['operation', 'product_id', 'success'],
  registers: [register]
});

const inventoryLevels = new client.Gauge({
  name: 'inventory_levels',
  help: 'Current inventory levels',
  labelNames: ['product_id', 'product_name'],
  registers: [register]
});

// Middleware to collect metrics
const metricsMiddleware = (req, res, next) => {
  const start = Date.now();
  
  // Increment active connections
  activeConnections.inc();
  
  // Override res.end to capture response time and status
  const originalEnd = res.end;
  res.end = function(...args) {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    
    // Record metrics
    httpRequestsTotal.inc({
      method: req.method,
      route: route,
      status_code: res.statusCode
    });
    
    httpRequestDuration.observe({
      method: req.method,
      route: route,
      status_code: res.statusCode
    }, duration);
    
    // Decrement active connections
    activeConnections.dec();
    
    // Call original end
    originalEnd.apply(this, args);
  };
  
  next();
};

// Function to update inventory level metrics
const updateInventoryMetrics = (inventory) => {
  // Clear existing inventory metrics
  inventoryLevels.reset();
  
  // Set current inventory levels
  Object.values(inventory).forEach(item => {
    inventoryLevels.set({
      product_id: item.id.toString(),
      product_name: item.name
    }, item.quantity - item.reserved);
  });
};

// Export metrics and middleware
module.exports = {
  metricsMiddleware,
  register,
  metrics: {
    httpRequestsTotal,
    httpRequestDuration,
    activeConnections,
    inventoryOperationsTotal,
    inventoryLevels
  },
  updateInventoryMetrics
};