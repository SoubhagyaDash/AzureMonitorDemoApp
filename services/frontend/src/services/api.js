import axios from 'axios';

// API configuration
// When empty, use same origin (proxied by server) - no localhost fallback
const API_CONFIG = {
  apiGateway: process.env.REACT_APP_API_GATEWAY_URL || '',
  inventoryService: process.env.REACT_APP_INVENTORY_SERVICE_URL || '',
  eventProcessor: process.env.REACT_APP_EVENT_PROCESSOR_URL || '',
  orderService: process.env.REACT_APP_ORDER_SERVICE_URL || '',
  notificationService: process.env.REACT_APP_NOTIFICATION_SERVICE_URL || '',
  paymentService: process.env.REACT_APP_PAYMENT_SERVICE_URL || ''
};

// Create axios instances for each service
// Empty baseURL means use relative paths (same origin)
const createClient = (baseURL) => {
  return axios.create({
    baseURL: baseURL || undefined, // undefined = relative URLs
    timeout: 10000,
    headers: {
      'Content-Type': 'application/json'
    }
  });
};

const apiGatewayClient = createClient(API_CONFIG.apiGateway);
const inventoryServiceClient = createClient(API_CONFIG.inventoryService);
const eventProcessorClient = createClient(API_CONFIG.eventProcessor);
const orderServiceClient = createClient(API_CONFIG.orderService);
const notificationServiceClient = createClient(API_CONFIG.notificationService);
const paymentServiceClient = createClient(API_CONFIG.paymentService);

// Request interceptors for tracing
const addTraceHeaders = (config) => {
  // Add correlation IDs and tracing headers
  config.headers['X-Correlation-ID'] = generateCorrelationId();
  config.headers['X-Request-Source'] = 'frontend';
  config.headers['X-Request-Timestamp'] = new Date().toISOString();
  return config;
};

const attachInterceptors = (client) => {
  if (!client) {
    return;
  }

  client.interceptors.request.use(addTraceHeaders);
  client.interceptors.response.use(
    (response) => response,
    (error) => {
      console.error('API Error:', error);
      return Promise.reject(error);
    }
  );
};

attachInterceptors(apiGatewayClient);
attachInterceptors(orderServiceClient);
attachInterceptors(inventoryServiceClient);
attachInterceptors(eventProcessorClient);
attachInterceptors(notificationServiceClient);
attachInterceptors(paymentServiceClient);

// Utility functions
function generateCorrelationId() {
  return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}

function generateCustomerId() {
  const customers = ['customer-001', 'customer-002', 'customer-003', 'customer-004', 'customer-005'];
  return customers[Math.floor(Math.random() * customers.length)];
}

function generateProductId() {
  return Math.floor(Math.random() * 5) + 1;
}

// API methods
const api = {
  // Health checks - Use API Gateway's health endpoint for all services
  async getServiceStatus() {
    try {
      // Call API Gateway's centralized health check endpoint
      const response = await apiGatewayClient.get('/api/health/all');
      
      // Handle both camelCase (services) and PascalCase (Services) for compatibility
      const services = response.data?.services || response.data?.Services;
      
      if (services && Array.isArray(services)) {
        // Transform the response to match the expected format
        return services.map(service => ({
          name: service.name || service.Name,
          status: (service.isHealthy || service.IsHealthy) ? 'healthy' : 'unhealthy',
          responseTime: `${service.responseTimeMs || service.ResponseTimeMs}ms`,
          data: {
            status: service.status || service.Status,
            lastChecked: service.lastChecked || service.LastChecked,
            error: service.error || service.Error
          }
        }));
      }
      
      // Fallback if response structure is unexpected
      return [];
    } catch (error) {
      console.error('Failed to fetch service status:', error);
      
      // Return error status for all services if the health check fails
      return [
        { name: 'API Gateway', status: 'unhealthy', error: error.message, responseTime: 'N/A' },
        { name: 'Order Service', status: 'unknown', error: 'Health check unavailable', responseTime: 'N/A' },
        { name: 'Payment Service', status: 'unknown', error: 'Health check unavailable', responseTime: 'N/A' },
        { name: 'Inventory Service', status: 'unknown', error: 'Health check unavailable', responseTime: 'N/A' },
        { name: 'Event Processor', status: 'unknown', error: 'Health check unavailable', responseTime: 'N/A' },
        { name: 'Notification Service', status: 'unknown', error: 'Health check unavailable', responseTime: 'N/A' }
      ];
    }
  },

  // Individual service health check (optional, for detailed checks)
  async getIndividualServiceHealth(serviceName) {
    try {
      const response = await apiGatewayClient.get(`/api/health/${serviceName}`);
      return {
        name: response.data.Name,
        status: response.data.IsHealthy ? 'healthy' : 'unhealthy',
        responseTime: `${response.data.ResponseTimeMs}ms`,
        data: response.data
      };
    } catch (error) {
      console.error(`Failed to fetch health for ${serviceName}:`, error);
      return {
        name: serviceName,
        status: 'unhealthy',
        error: error.message,
        responseTime: 'N/A'
      };
    }
  },

  // Orders API
  async getOrders() {
    const client = apiGatewayClient;
    const response = await client.get('/api/orders');
    return response.data;
  },

  async getRecentOrders() {
    try {
      const client = apiGatewayClient;
      const response = await client.get('/api/orders');
      return response.data || [];
    } catch (error) {
      console.warn('Failed to fetch recent orders:', error);
      return [];
    }
  },

  async createOrder(orderData) {
    const client = apiGatewayClient;
    const response = await client.post('/api/orders', orderData);
    return response.data;
  },

  async updateOrderStatus(orderId, status) {
    const client = apiGatewayClient;
    const response = await client.put(`/api/orders/${orderId}/status`, { status });
    return response.data;
  },

  // Inventory API - Call directly (no API Gateway proxy exists for inventory)
  async getInventory() {
    const client = inventoryServiceClient;
    const response = await client.get('/api/inventory');
    return response.data;
  },

  async checkInventory(productId, quantity = 1) {
    const client = inventoryServiceClient;
    const response = await client.get(`/api/inventory/check/${productId}?quantity=${quantity}`);
    return response.data;
  },

  async reserveInventory(productId, quantity) {
    const client = inventoryServiceClient;
    const response = await client.post('/api/inventory/reserve', {
      productId,
      quantity
    });
    return response.data;
  },

  // Order Service API (Java)
  async processOrder(orderData) {
    const client = orderServiceClient;
    const response = await client.post('/api/orders/process', orderData);
    return response.data;
  },

  async processOrderAsync(orderData) {
    const client = orderServiceClient;
    const response = await client.post('/api/orders/process-async', orderData);
    return response.data;
  },

  async validateOrder(orderId) {
    const client = orderServiceClient;
    const response = await client.post(`/api/orders/${orderId}/validate`);
    return response.data;
  },

  async processBulkOrders(orders) {
    const client = orderServiceClient;
    const response = await client.post('/api/orders/bulk-process', orders);
    return response.data;
  },

  // Event Processor API
  async startEventProcessing() {
    const client = eventProcessorClient;
    const response = await client.post('/start-processing');
    return response.data;
  },

  async configureFailureInjection(config) {
    const client = eventProcessorClient;
    const response = await client.post('/failure-injection', config);
    return response.data;
  },

  async getEventProcessorMetrics() {
    const client = eventProcessorClient;
    const response = await client.get('/metrics');
    return response.data;
  },

  // System Health
  async getSystemHealth() {
    try {
      // This would normally aggregate health from multiple sources
      return {
        overall: 'healthy',
        services: 4,
        healthyServices: 4,
        warningServices: 0,
        errorServices: 0,
        lastChecked: new Date().toISOString()
      };
    } catch (error) {
      return {
        overall: 'error',
        error: error.message
      };
    }
  },

  // Traffic generation utilities
  async generateRandomOrder() {
    const orderData = {
      customerId: generateCustomerId(),
      productId: generateProductId(),
      quantity: Math.floor(Math.random() * 5) + 1,
      totalAmount: (Math.random() * 500 + 50).toFixed(2)
    };

    return this.createOrder(orderData);
  },

  async generateTrafficBurst(requests = 10, delayMs = 1000) {
    const promises = [];
    
    for (let i = 0; i < requests; i++) {
      promises.push(
        new Promise(async (resolve) => {
          await new Promise(resolve => setTimeout(resolve, i * delayMs));
          try {
            const result = await this.generateRandomOrder();
            resolve({ success: true, result });
          } catch (error) {
            resolve({ success: false, error: error.message });
          }
        })
      );
    }

    return Promise.all(promises);
  },

  // Notifications API
  async createNotification(notificationData) {
    const client = notificationServiceClient;
    const response = await client.post('/api/v1/notifications', notificationData);
    return response.data;
  },

  async getNotifications(customerId) {
    const client = notificationServiceClient;
    const response = await client.get(`/api/v1/notifications?customerId=${customerId}`);
    return response.data;
  },

  async sendBulkNotifications(notifications) {
    const client = notificationServiceClient;
    const response = await client.post('/api/v1/notifications/bulk', {
      notifications
    });
    return response.data;
  },

  // Metrics and monitoring
  async getMetrics(service = 'all') {
    try {
      const endpoints = {
        inventory: '/metrics',
        orderService: '/actuator/metrics', // Spring Boot Actuator
        eventProcessor: '/metrics'
      };

      if (service === 'all') {
        const [inventoryResult, eventProcessorResult] = await Promise.allSettled([
          inventoryServiceClient ? inventoryServiceClient.get(endpoints.inventory) : Promise.resolve(null),
          eventProcessorClient ? eventProcessorClient.get(endpoints.eventProcessor) : Promise.resolve(null)
        ]);

        const extractData = (result) => {
          if (result.status !== 'fulfilled' || !result.value) {
            return null;
          }
          return result.value.data ?? result.value;
        };

        return {
          inventory: extractData(inventoryResult),
          eventProcessor: extractData(eventProcessorResult)
        };
      }

      if (service === 'inventory') {
        const client = inventoryServiceClient;
        const response = await client.get(endpoints.inventory);
        return response.data;
      }

      if (service === 'orderService') {
        const client = orderServiceClient;
        const response = await client.get(endpoints.orderService);
        return response.data;
      }

      if (service === 'eventProcessor') {
        const client = eventProcessorClient;
        const response = await client.get(endpoints.eventProcessor);
        return response.data;
      }
    } catch (error) {
      console.error('Error fetching metrics:', error);
      return null;
    }
  },

  // Payment operations
  processPayment: async (orderData) => {
    try {
      const client = apiGatewayClient;

      // API Gateway expects one order per product
      // Create orders for each item in cart
      const orders = [];
      for (const item of orderData.items) {
        const orderPayload = {
          customerId: orderData.customerId,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice
        };
        console.log('Creating order with payload:', orderPayload);
        const orderResponse = await client.post('/api/orders', orderPayload);
        orders.push(orderResponse.data);
      }

      // Use first order for payment (simplified)
      const primaryOrder = orders[0];

      // Process payment through API Gateway
      const paymentPayload = {
        orderId: primaryOrder.id.toString(),
        customerId: orderData.customerId,
        amount: orderData.totalAmount,
        currency: 'USD',
        paymentMethod: orderData.paymentMethod
      };
      
      console.log('Processing payment with payload:', JSON.stringify(paymentPayload, null, 2));
      console.log('Payment method details:', JSON.stringify(orderData.paymentMethod, null, 2));
      
      const paymentResponse = await client.post('/api/payments', paymentPayload);
      const payment = paymentResponse.data;

      return { 
        order: { ...primaryOrder, relatedOrders: orders },
        payment
      };
    } catch (error) {
      console.error('Error processing payment:', error);
      throw error;
    }
  },

  getPayment: async (paymentId) => {
    try {
      const client = apiGatewayClient;
      const response = await client.get(`/api/payments/${paymentId}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching payment:', error);
      throw error;
    }
  },

  getPaymentsByOrder: async (orderId) => {
    try {
      const client = apiGatewayClient;
      const response = await client.get(`/api/payments/order/${orderId}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching payments for order:', error);
      throw error;
    }
  },

  refundPayment: async (paymentId, amount, reason) => {
    try {
      const client = apiGatewayClient;
      const response = await client.post(`/api/payments/${paymentId}/refund`, {
        amount,
        reason
      });
      return response.data;
    } catch (error) {
      console.error('Error processing refund:', error);
      throw error;
    }
  },

  // Failure Injection Management
  getServiceBaseUrl: (serviceKey) => {
    const baseUrls = {
      'api-gateway': process.env.REACT_APP_API_GATEWAY_URL || 'http://localhost:5000',
      'order-service': process.env.REACT_APP_ORDER_SERVICE_URL || 'http://localhost:8080',
      'event-processor': process.env.REACT_APP_EVENT_PROCESSOR_URL || 'http://localhost:8001',
      'inventory-service': process.env.REACT_APP_INVENTORY_SERVICE_URL || 'http://localhost:3001',
      'notification-service': process.env.REACT_APP_NOTIFICATION_SERVICE_URL || 'http://localhost:8002',
      'payment-service': process.env.REACT_APP_PAYMENT_SERVICE_URL || 'http://localhost:5001'
    };
    return baseUrls[serviceKey] || '';
  },

  async updateFailureInjectionConfig(serviceKey, config) {
    try {
      const baseUrl = this.getServiceBaseUrl(serviceKey);
      if (!baseUrl) {
        throw new Error(`Failure injection endpoint for ${serviceKey} is not configured.`);
      }
      const endpoint = serviceKey === 'event-processor' ? '/failure-injection' : '/api/failure-injection';
      
      const response = await fetch(`${baseUrl}${endpoint}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Correlation-ID': generateCorrelationId()
        },
        body: JSON.stringify(config)
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      return await response.json();
    } catch (error) {
      console.error(`Error updating failure injection for ${serviceKey}:`, error);
      throw error;
    }
  },

  async getFailureInjectionConfig(serviceKey) {
    try {
      const baseUrl = this.getServiceBaseUrl(serviceKey);
      if (!baseUrl) {
        throw new Error(`Failure injection endpoint for ${serviceKey} is not configured.`);
      }
      const endpoint = serviceKey === 'event-processor' ? '/failure-injection' : '/api/failure-injection';
      
      const response = await fetch(`${baseUrl}${endpoint}`, {
        method: 'GET',
        headers: {
          'X-Correlation-ID': generateCorrelationId()
        }
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      return await response.json();
    } catch (error) {
      console.error(`Error getting failure injection config for ${serviceKey}:`, error);
      throw error;
    }
  },

  async triggerChaosScenario(scenarioName, config) {
    try {
      const services = ['api-gateway', 'order-service', 'event-processor', 'payment-service'];
      const results = await Promise.allSettled(
        services.map(serviceKey => this.updateFailureInjectionConfig(serviceKey, config))
      );

      const successful = results.filter(result => result.status === 'fulfilled').length;
      const failed = results.filter(result => result.status === 'rejected').length;

      return {
        scenario: scenarioName,
        successful,
        failed,
        total: services.length,
        results
      };
    } catch (error) {
      console.error('Error triggering chaos scenario:', error);
      throw error;
    }
  }
};

export default api;
