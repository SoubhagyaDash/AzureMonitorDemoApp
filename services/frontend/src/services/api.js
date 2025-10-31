import axios from 'axios';

// API configuration
const API_CONFIG = {
  apiGateway: process.env.REACT_APP_API_GATEWAY_URL || 'http://localhost:5000/api',
  orderService: process.env.REACT_APP_ORDER_SERVICE_URL || 'http://localhost:8080/api',
  inventoryService: process.env.REACT_APP_INVENTORY_SERVICE_URL || 'http://localhost:3000/api',
  paymentService: process.env.REACT_APP_PAYMENT_SERVICE_URL || 'http://localhost:5002/api',
  eventProcessor: process.env.REACT_APP_EVENT_PROCESSOR_URL || 'http://localhost:8001/api',
  notificationService: process.env.REACT_APP_NOTIFICATION_SERVICE_URL || 'http://localhost:8082/api'
};

// Create axios instances for each service
const apiGatewayClient = axios.create({
  baseURL: API_CONFIG.apiGateway,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
});

const orderServiceClient = axios.create({
  baseURL: API_CONFIG.orderService,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
});

const inventoryServiceClient = axios.create({
  baseURL: API_CONFIG.inventoryService,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
});

const eventProcessorClient = axios.create({
  baseURL: API_CONFIG.eventProcessor,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
});

const notificationServiceClient = axios.create({
  baseURL: API_CONFIG.notificationService,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
});

// Request interceptors for tracing
const addTraceHeaders = (config) => {
  // Add correlation IDs and tracing headers
  config.headers['X-Correlation-ID'] = generateCorrelationId();
  config.headers['X-Request-Source'] = 'frontend';
  config.headers['X-Request-Timestamp'] = new Date().toISOString();
  return config;
};

apiGatewayClient.interceptors.request.use(addTraceHeaders);
orderServiceClient.interceptors.request.use(addTraceHeaders);
inventoryServiceClient.interceptors.request.use(addTraceHeaders);
eventProcessorClient.interceptors.request.use(addTraceHeaders);
notificationServiceClient.interceptors.request.use(addTraceHeaders);

// Response interceptors for error handling
const handleResponse = (response) => response;
const handleError = (error) => {
  console.error('API Error:', error);
  return Promise.reject(error);
};

apiGatewayClient.interceptors.response.use(handleResponse, handleError);
orderServiceClient.interceptors.response.use(handleResponse, handleError);
inventoryServiceClient.interceptors.response.use(handleResponse, handleError);
eventProcessorClient.interceptors.response.use(handleResponse, handleError);
notificationServiceClient.interceptors.response.use(handleResponse, handleError);

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
  // Health checks
  async getServiceStatus() {
    try {
      const services = [
        { name: 'API Gateway', client: apiGatewayClient, endpoint: '/health' },
        { name: 'Order Service', client: orderServiceClient, endpoint: '/api/orders/health' },
        { name: 'Inventory Service', client: inventoryServiceClient, endpoint: '/health' },
        { name: 'Event Processor', client: eventProcessorClient, endpoint: '/health' },
        { name: 'Notification Service', client: notificationServiceClient, endpoint: '/health' }
      ];

      const results = await Promise.allSettled(
        services.map(async (service) => {
          try {
            const response = await service.client.get(service.endpoint);
            return {
              name: service.name,
              status: 'healthy',
              responseTime: response.headers['x-response-time'] || 'N/A',
              data: response.data
            };
          } catch (error) {
            return {
              name: service.name,
              status: 'unhealthy',
              error: error.message,
              responseTime: 'N/A'
            };
          }
        })
      );

      return results.map((result, index) => ({
        ...services[index],
        ...result.value
      }));
    } catch (error) {
      console.error('Error checking service status:', error);
      return [];
    }
  },

  // Orders API
  async getOrders() {
    const response = await apiGatewayClient.get('/api/orders');
    return response.data;
  },

  async getRecentOrders() {
    try {
      const response = await apiGatewayClient.get('/api/orders');
      return response.data || [];
    } catch (error) {
      console.warn('Failed to fetch recent orders:', error);
      return [];
    }
  },

  async createOrder(orderData) {
    const response = await apiGatewayClient.post('/api/orders', orderData);
    return response.data;
  },

  async updateOrderStatus(orderId, status) {
    const response = await apiGatewayClient.put(`/api/orders/${orderId}/status`, { status });
    return response.data;
  },

  // Inventory API
  async getInventory() {
    const response = await inventoryServiceClient.get('/api/inventory');
    return response.data;
  },

  async checkInventory(productId, quantity = 1) {
    const response = await inventoryServiceClient.get(`/api/inventory/check/${productId}?quantity=${quantity}`);
    return response.data;
  },

  async reserveInventory(productId, quantity) {
    const response = await inventoryServiceClient.post('/api/inventory/reserve', {
      productId,
      quantity
    });
    return response.data;
  },

  // Order Service API (Java)
  async processOrder(orderData) {
    const response = await orderServiceClient.post('/api/orders/process', orderData);
    return response.data;
  },

  async processOrderAsync(orderData) {
    const response = await orderServiceClient.post('/api/orders/process-async', orderData);
    return response.data;
  },

  async validateOrder(orderId) {
    const response = await orderServiceClient.post(`/api/orders/${orderId}/validate`);
    return response.data;
  },

  async processBulkOrders(orders) {
    const response = await orderServiceClient.post('/api/orders/bulk-process', orders);
    return response.data;
  },

  // Event Processor API
  async startEventProcessing() {
    const response = await eventProcessorClient.post('/start-processing');
    return response.data;
  },

  async configureFailureInjection(config) {
    const response = await eventProcessorClient.post('/failure-injection', config);
    return response.data;
  },

  async getEventProcessorMetrics() {
    const response = await eventProcessorClient.get('/metrics');
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
    const response = await notificationServiceClient.post('/api/v1/notifications', notificationData);
    return response.data;
  },

  async getNotifications(customerId) {
    const response = await notificationServiceClient.get(`/api/v1/notifications?customerId=${customerId}`);
    return response.data;
  },

  async sendBulkNotifications(notifications) {
    const response = await notificationServiceClient.post('/api/v1/notifications/bulk', {
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
        const results = await Promise.allSettled([
          inventoryServiceClient.get(endpoints.inventory),
          eventProcessorClient.get(endpoints.eventProcessor)
        ]);

        return {
          inventory: results[0].status === 'fulfilled' ? results[0].value.data : null,
          eventProcessor: results[1].status === 'fulfilled' ? results[1].value.data : null
        };
      } else if (endpoints[service]) {
        const client = service === 'inventory' ? inventoryServiceClient : eventProcessorClient;
        const response = await client.get(endpoints[service]);
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
      // First create the order
      const orderResponse = await apiGatewayClient.post('/orders', {
        customerId: orderData.customerId,
        items: orderData.items,
        totalAmount: orderData.totalAmount
      });

      const order = orderResponse.data;

      // Then process payment
      const paymentResponse = await apiGatewayClient.post('/payments', {
        orderId: order.id,
        customerId: orderData.customerId,
        amount: orderData.totalAmount,
        currency: 'USD',
        paymentMethod: orderData.paymentMethod
      });

      const payment = paymentResponse.data;

      return { order, payment };
    } catch (error) {
      console.error('Error processing payment:', error);
      throw error;
    }
  },

  getPayment: async (paymentId) => {
    try {
      const response = await apiGatewayClient.get(`/payments/${paymentId}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching payment:', error);
      throw error;
    }
  },

  getPaymentsByOrder: async (orderId) => {
    try {
      const response = await apiGatewayClient.get(`/payments/order/${orderId}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching payments for order:', error);
      throw error;
    }
  },

  refundPayment: async (paymentId, amount, reason) => {
    try {
      const response = await apiGatewayClient.post(`/payments/${paymentId}/refund`, {
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