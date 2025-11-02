const express = require('express');
const path = require('path');
const cors = require('cors');
const fetch = require('node-fetch');

const app = express();
const PORT = process.env.PORT || 8080;

// Enable CORS for all origins
app.use(cors());
app.use(express.json());

// API proxy endpoints to avoid CORS issues
// Using private IPs for VNet integration
const trimTrailingSlash = (value = '') => value.replace(/\/$/, '');

const SERVICES = {
  inventory: process.env.INVENTORY_SERVICE_URL || 'http://localhost:3001',
  orders: process.env.ORDER_SERVICE_URL || '',
  payment: process.env.PAYMENT_SERVICE_URL || '',
  apiGateway: process.env.API_GATEWAY_URL || ''
};

const INVENTORY_API_BASE = `${trimTrailingSlash(SERVICES.inventory)}/api/inventory`;
const ORDER_SERVICE_API_BASE = SERVICES.orders ? `${trimTrailingSlash(SERVICES.orders)}/api/orders` : '';
const API_GATEWAY_ORDERS_BASE = SERVICES.apiGateway ? `${trimTrailingSlash(SERVICES.apiGateway)}/api/orders` : '';

const fetchJsonOrThrow = async (url, options = {}) => {
  const response = await fetch(url, options);
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Request to ${url} failed with status ${response.status}: ${body}`);
  }
  return response.json();
};

// Proxy for inventory service
app.get('/api/inventory', async (req, res) => {
  try {
    const data = await fetchJsonOrThrow(INVENTORY_API_BASE);
    res.json(data);
  } catch (error) {
    console.error('Inventory service error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Proxy for inventory check
app.get('/api/inventory/check/:productId', async (req, res) => {
  try {
    const { productId } = req.params;
    const { quantity } = req.query;
    const url = `${INVENTORY_API_BASE}/check/${encodeURIComponent(productId)}${quantity ? `?quantity=${quantity}` : ''}`;
    const data = await fetchJsonOrThrow(url);
    res.json(data);
  } catch (error) {
    console.error('Inventory check error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Proxy for orders service - get all orders (for UI to filter by customer)
app.get('/api/orders', async (req, res) => {
  try {
    if (!API_GATEWAY_ORDERS_BASE) {
      res.status(502).json({ error: 'Order service endpoint is not configured.' });
      return;
    }

    const data = await fetchJsonOrThrow(API_GATEWAY_ORDERS_BASE);
    res.json(data);
  } catch (error) {
    console.error('Orders service error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Proxy for orders service - get customer orders
app.get('/api/orders/customer/:customerId', async (req, res) => {
  try {
    if (ORDER_SERVICE_API_BASE) {
      const data = await fetchJsonOrThrow(`${ORDER_SERVICE_API_BASE}/customer/${encodeURIComponent(req.params.customerId)}`);
      res.json(data);
      return;
    }

    if (!API_GATEWAY_ORDERS_BASE) {
      res.status(502).json({ error: 'Order service endpoint is not configured.' });
      return;
    }

    const orders = await fetchJsonOrThrow(API_GATEWAY_ORDERS_BASE);
    const filtered = Array.isArray(orders)
      ? orders.filter(order => order && order.customerId === req.params.customerId)
      : [];
    res.json(filtered);
  } catch (error) {
    console.error('Orders service error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Proxy for orders service - create order (primary route)
app.post('/api/orders', async (req, res) => {
  try {
    console.log('Creating order:', req.body);

    let targetUrl = '';
    if (API_GATEWAY_ORDERS_BASE) {
      targetUrl = API_GATEWAY_ORDERS_BASE;
    } else if (ORDER_SERVICE_API_BASE) {
      targetUrl = ORDER_SERVICE_API_BASE;
    } else {
      res.status(502).json({ error: 'Order creation endpoint is not configured.' });
      return;
    }

    console.log(`Proxying order creation to: ${targetUrl}`);
    const response = await fetch(targetUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body)
    });

    // Check if response is JSON before parsing
    const contentType = response.headers.get('content-type');
    if (contentType && contentType.includes('application/json')) {
      const data = await response.json();
      res.status(response.status).json(data);
    } else {
      const text = await response.text();
      console.error(`Non-JSON response from ${targetUrl}: ${text.substring(0, 200)}`);
      res.status(response.status).json({ 
        error: 'Invalid response from order service', 
        details: text.substring(0, 500)
      });
    }
  } catch (error) {
    console.error('Error creating order:', error);
    res.status(500).json({ error: error.message });
  }
});

// Proxy for orders service - process order (legacy route)
app.post('/api/orders/process', async (req, res) => {
  try {
    console.log('Processing order:', req.body);

    let targetUrl = '';
    if (API_GATEWAY_ORDERS_BASE) {
      targetUrl = API_GATEWAY_ORDERS_BASE;
    } else if (ORDER_SERVICE_API_BASE) {
      targetUrl = `${ORDER_SERVICE_API_BASE}/process`;
    } else {
      res.status(502).json({ error: 'Order processing endpoint is not configured.' });
      return;
    }

    const data = await fetchJsonOrThrow(targetUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body)
    });

    console.log('Order created:', data);
    res.json(data);
  } catch (error) {
    console.error('Order creation error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Proxy for payments service
app.post('/api/payments', async (req, res) => {
  try {
    console.log('Processing payment:', req.body);

    const API_GATEWAY_PAYMENTS_BASE = SERVICES.apiGateway ? `${trimTrailingSlash(SERVICES.apiGateway)}/api/payments` : '';
    
    if (!API_GATEWAY_PAYMENTS_BASE) {
      res.status(502).json({ error: 'Payment service endpoint is not configured.' });
      return;
    }

    console.log(`Proxying payment to: ${API_GATEWAY_PAYMENTS_BASE}`);
    const response = await fetch(API_GATEWAY_PAYMENTS_BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body)
    });

    const contentType = response.headers.get('content-type');
    if (contentType && contentType.includes('application/json')) {
      const data = await response.json();
      res.status(response.status).json(data);
    } else {
      const text = await response.text();
      console.error(`Non-JSON response from payment service: ${text.substring(0, 200)}`);
      res.status(response.status).json({ 
        error: 'Invalid response from payment service', 
        details: text.substring(0, 500)
      });
    }
  } catch (error) {
    console.error('Payment processing error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Serve static files from current directory
app.use(express.static(__dirname));

// Serve index.html for root
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(PORT, () => {
  console.log(`✓ eCommerce Frontend running on http://localhost:${PORT}`);
  console.log(`✓ API Proxy enabled - proxying requests to:`);
  console.log(`  - Inventory: ${INVENTORY_API_BASE}`);
  if (ORDER_SERVICE_API_BASE) {
    console.log(`  - Orders (Java service): ${ORDER_SERVICE_API_BASE}`);
  }
  if (API_GATEWAY_ORDERS_BASE) {
    console.log(`  - Orders (API Gateway): ${API_GATEWAY_ORDERS_BASE}`);
  }
  console.log(`✓ Open http://localhost:${PORT} in your browser`);
});
