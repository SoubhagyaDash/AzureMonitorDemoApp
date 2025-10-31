const express = require('express');
const { trace, metrics, SpanStatusCode } = require('@opentelemetry/api');
const winston = require('winston');

const router = express.Router();
const tracer = trace.getTracer('inventory-service');
const meter = metrics.getMeter('inventory-service');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

// Custom metrics
const inventoryChecksTotal = meter.createCounter('inventory_checks_total');
const inventoryUpdatesTotal = meter.createCounter('inventory_updates_total');
const inventoryLevelsGauge = meter.createUpDownCounter('inventory_levels');

// In-memory inventory data (in production, this would be a database)
let inventory = {
  1: { id: 1, name: 'Widget A', quantity: 100, price: 19.99, reserved: 0 },
  2: { id: 2, name: 'Widget B', quantity: 50, price: 29.99, reserved: 0 },
  3: { id: 3, name: 'Widget C', quantity: 75, price: 39.99, reserved: 0 },
  4: { id: 4, name: 'Widget D', quantity: 200, price: 9.99, reserved: 0 },
  5: { id: 5, name: 'Widget E', quantity: 25, price: 49.99, reserved: 0 }
};

// Helper function to simulate async operations
const simulateDelay = (min = 10, max = 100) => {
  return new Promise(resolve => {
    setTimeout(resolve, Math.floor(Math.random() * (max - min + 1)) + min);
  });
};

// Get all inventory items
router.get('/', async (req, res) => {
  const span = tracer.startSpan('get_all_inventory');
  
  try {
    span.setAttributes({
      'inventory.operation': 'get_all',
      'inventory.count': Object.keys(inventory).length
    });

    await simulateDelay();
    
    const items = Object.values(inventory);
    inventoryChecksTotal.add(1, { operation: 'get_all' });
    
    logger.info('Retrieved all inventory items', { count: items.length });
    
    span.setStatus({ code: SpanStatusCode.OK });
    res.json(items);
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    logger.error('Error retrieving inventory items', { error: error.message });
    res.status(500).json({ error: 'Failed to retrieve inventory' });
  } finally {
    span.end();
  }
});

// Get specific inventory item
router.get('/:id', async (req, res) => {
  const productId = parseInt(req.params.id);
  const span = tracer.startSpan('get_inventory_item');
  
  try {
    span.setAttributes({
      'inventory.operation': 'get_item',
      'inventory.product_id': productId
    });

    await simulateDelay();
    
    const item = inventory[productId];
    inventoryChecksTotal.add(1, { operation: 'get_item' });
    
    if (!item) {
      span.setAttributes({ 'inventory.found': false });
      logger.warn('Inventory item not found', { productId });
      return res.status(404).json({ error: 'Product not found' });
    }
    
    span.setAttributes({
      'inventory.found': true,
      'inventory.quantity': item.quantity,
      'inventory.reserved': item.reserved
    });
    
    logger.info('Retrieved inventory item', { productId, quantity: item.quantity });
    
    span.setStatus({ code: SpanStatusCode.OK });
    res.json(item);
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    logger.error('Error retrieving inventory item', { productId, error: error.message });
    res.status(500).json({ error: 'Failed to retrieve inventory item' });
  } finally {
    span.end();
  }
});

// Check inventory availability
router.get('/check/:id', async (req, res) => {
  const productId = parseInt(req.params.id);
  const quantity = parseInt(req.query.quantity) || 1;
  const span = tracer.startSpan('check_inventory_availability');
  
  try {
    span.setAttributes({
      'inventory.operation': 'check_availability',
      'inventory.product_id': productId,
      'inventory.requested_quantity': quantity
    });

    await simulateDelay();
    
    const item = inventory[productId];
    inventoryChecksTotal.add(1, { operation: 'check_availability' });
    
    if (!item) {
      span.setAttributes({ 'inventory.available': false, 'inventory.reason': 'product_not_found' });
      logger.warn('Product not found for availability check', { productId });
      return res.status(404).json({ error: 'Product not found', available: false });
    }
    
    const availableQuantity = item.quantity - item.reserved;
    const isAvailable = availableQuantity >= quantity;
    
    span.setAttributes({
      'inventory.available': isAvailable,
      'inventory.available_quantity': availableQuantity,
      'inventory.total_quantity': item.quantity,
      'inventory.reserved': item.reserved
    });
    
    logger.info('Checked inventory availability', {
      productId,
      requestedQuantity: quantity,
      availableQuantity,
      isAvailable
    });
    
    span.setStatus({ code: SpanStatusCode.OK });
    res.json({
      productId,
      available: isAvailable,
      availableQuantity,
      requestedQuantity: quantity
    });
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    logger.error('Error checking inventory availability', { productId, error: error.message });
    res.status(500).json({ error: 'Failed to check inventory availability' });
  } finally {
    span.end();
  }
});

// Reserve inventory
router.post('/reserve', async (req, res) => {
  const { productId, quantity } = req.body;
  const span = tracer.startSpan('reserve_inventory');
  
  try {
    span.setAttributes({
      'inventory.operation': 'reserve',
      'inventory.product_id': productId,
      'inventory.quantity': quantity
    });

    await simulateDelay(50, 200);
    
    const item = inventory[productId];
    
    if (!item) {
      span.setAttributes({ 'inventory.reserved': false, 'inventory.reason': 'product_not_found' });
      logger.warn('Product not found for reservation', { productId });
      return res.status(404).json({ error: 'Product not found', reserved: false });
    }
    
    const availableQuantity = item.quantity - item.reserved;
    
    if (availableQuantity < quantity) {
      span.setAttributes({
        'inventory.reserved': false,
        'inventory.reason': 'insufficient_quantity',
        'inventory.available': availableQuantity
      });
      logger.warn('Insufficient inventory for reservation', {
        productId,
        requestedQuantity: quantity,
        availableQuantity
      });
      return res.status(400).json({
        error: 'Insufficient inventory',
        reserved: false,
        availableQuantity
      });
    }
    
    // Reserve the inventory
    inventory[productId].reserved += quantity;
    inventoryUpdatesTotal.add(1, { operation: 'reserve' });
    inventoryLevelsGauge.add(-quantity, { product_id: productId.toString(), type: 'available' });
    
    span.setAttributes({
      'inventory.reserved': true,
      'inventory.new_reserved_total': item.reserved,
      'inventory.remaining_available': item.quantity - item.reserved
    });
    
    logger.info('Inventory reserved successfully', {
      productId,
      quantity,
      totalReserved: item.reserved,
      remainingAvailable: item.quantity - item.reserved
    });
    
    span.setStatus({ code: SpanStatusCode.OK });
    res.json({
      productId,
      reserved: true,
      reservedQuantity: quantity,
      totalReserved: item.reserved,
      remainingAvailable: item.quantity - item.reserved
    });
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    logger.error('Error reserving inventory', { productId, quantity, error: error.message });
    res.status(500).json({ error: 'Failed to reserve inventory' });
  } finally {
    span.end();
  }
});

// Release reserved inventory
router.post('/release', async (req, res) => {
  const { productId, quantity } = req.body;
  const span = tracer.startSpan('release_inventory');
  
  try {
    span.setAttributes({
      'inventory.operation': 'release',
      'inventory.product_id': productId,
      'inventory.quantity': quantity
    });

    await simulateDelay();
    
    const item = inventory[productId];
    
    if (!item) {
      span.setAttributes({ 'inventory.released': false, 'inventory.reason': 'product_not_found' });
      logger.warn('Product not found for release', { productId });
      return res.status(404).json({ error: 'Product not found', released: false });
    }
    
    if (item.reserved < quantity) {
      span.setAttributes({
        'inventory.released': false,
        'inventory.reason': 'insufficient_reserved',
        'inventory.reserved': item.reserved
      });
      logger.warn('Insufficient reserved inventory for release', {
        productId,
        requestedQuantity: quantity,
        reservedQuantity: item.reserved
      });
      return res.status(400).json({
        error: 'Insufficient reserved inventory',
        released: false,
        reservedQuantity: item.reserved
      });
    }
    
    // Release the inventory
    inventory[productId].reserved -= quantity;
    inventoryUpdatesTotal.add(1, { operation: 'release' });
    inventoryLevelsGauge.add(quantity, { product_id: productId.toString(), type: 'available' });
    
    span.setAttributes({
      'inventory.released': true,
      'inventory.new_reserved_total': item.reserved,
      'inventory.new_available': item.quantity - item.reserved
    });
    
    logger.info('Inventory released successfully', {
      productId,
      quantity,
      totalReserved: item.reserved,
      availableQuantity: item.quantity - item.reserved
    });
    
    span.setStatus({ code: SpanStatusCode.OK });
    res.json({
      productId,
      released: true,
      releasedQuantity: quantity,
      totalReserved: item.reserved,
      availableQuantity: item.quantity - item.reserved
    });
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    logger.error('Error releasing inventory', { productId, quantity, error: error.message });
    res.status(500).json({ error: 'Failed to release inventory' });
  } finally {
    span.end();
  }
});

// Update inventory levels
router.put('/:id', async (req, res) => {
  const productId = parseInt(req.params.id);
  const { quantity, name, price } = req.body;
  const span = tracer.startSpan('update_inventory');
  
  try {
    span.setAttributes({
      'inventory.operation': 'update',
      'inventory.product_id': productId
    });

    await simulateDelay(30, 150);
    
    const item = inventory[productId];
    
    if (!item) {
      span.setAttributes({ 'inventory.updated': false, 'inventory.reason': 'product_not_found' });
      logger.warn('Product not found for update', { productId });
      return res.status(404).json({ error: 'Product not found', updated: false });
    }
    
    const oldQuantity = item.quantity;
    
    // Update fields if provided
    if (quantity !== undefined) {
      inventory[productId].quantity = quantity;
      span.setAttributes({
        'inventory.old_quantity': oldQuantity,
        'inventory.new_quantity': quantity
      });
    }
    if (name !== undefined) {
      inventory[productId].name = name;
    }
    if (price !== undefined) {
      inventory[productId].price = price;
    }
    
    inventoryUpdatesTotal.add(1, { operation: 'update' });
    
    if (quantity !== undefined) {
      inventoryLevelsGauge.add(quantity - oldQuantity, {
        product_id: productId.toString(),
        type: 'total'
      });
    }
    
    span.setAttributes({ 'inventory.updated': true });
    
    logger.info('Inventory updated successfully', {
      productId,
      oldQuantity,
      newQuantity: item.quantity,
      name: item.name,
      price: item.price
    });
    
    span.setStatus({ code: SpanStatusCode.OK });
    res.json({
      productId,
      updated: true,
      item: inventory[productId]
    });
    
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    logger.error('Error updating inventory', { productId, error: error.message });
    res.status(500).json({ error: 'Failed to update inventory' });
  } finally {
    span.end();
  }
});

module.exports = router;
