import React, { useState, useEffect } from 'react';
import {
  Grid,
  Card,
  CardContent,
  CardMedia,
  Typography,
  Button,
  Box,
  Badge,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Stepper,
  Step,
  StepLabel,
  Alert,
  List,
  ListItem,
  ListItemText,
  ListItemSecondaryAction,
  Divider,
  Chip,
  Paper,
  CircularProgress
} from '@mui/material';
import {
  ShoppingCart as CartIcon,
  Add as AddIcon,
  Remove as RemoveIcon,
  Delete as DeleteIcon,
  Notifications as NotificationIcon,
  LocalShipping as ShippingIcon,
  Payment as PaymentIcon,
  CheckCircle as CheckCircleIcon
} from '@mui/icons-material';
import { telemetry } from '../services/telemetry';
import api from '../services/api';

const ECommerceStore = ({ onNotification }) => {
  const [products, setProducts] = useState([]);
  const [cart, setCart] = useState([]);
  const [orders, setOrders] = useState([]);
  const [selectedCustomer, setSelectedCustomer] = useState('customer-001');
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const [activeStep, setActiveStep] = useState(0);
  const [orderStatus, setOrderStatus] = useState({});
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(false);
  const [wsConnection, setWsConnection] = useState(null);
  
  // Checkout form state
  const [shippingInfo, setShippingInfo] = useState({
    address: '123 Main St',
    city: 'Seattle',
    zipCode: '98101'
  });
  
  const [paymentInfo, setPaymentInfo] = useState({
    cardNumber: '**** **** **** 1234',
    expiryDate: '12/26',
    cvv: '123'
  });

  const customers = [
    { id: 'customer-001', name: 'John Doe', email: 'john@example.com' },
    { id: 'customer-002', name: 'Jane Smith', email: 'jane@example.com' },
    { id: 'customer-003', name: 'Bob Johnson', email: 'bob@example.com' },
    { id: 'customer-004', name: 'Alice Brown', email: 'alice@example.com' },
    { id: 'customer-005', name: 'Charlie Wilson', email: 'charlie@example.com' }
  ];

  const checkoutSteps = ['Cart Review', 'Shipping Info', 'Payment'];
  const [orderPlaced, setOrderPlaced] = useState(false);

  useEffect(() => {
    loadProducts();
    loadOrders();
    connectWebSocket();
    
    // Track store visit
    telemetry.trackBusinessEvent('StoreVisit', {
      customerId: selectedCustomer,
      timestamp: new Date().toISOString()
    });

    return () => {
      if (wsConnection) {
        wsConnection.close();
      }
    };
  }, []);

  useEffect(() => {
    // Track customer selection and reload orders for the new customer
    telemetry.trackUserAction('CustomerSelected', selectedCustomer, {
      previousCustomer: selectedCustomer
    });
    loadOrders();
  }, [selectedCustomer]);

  const loadProducts = async () => {
    try {
      const inventoryData = await api.getInventory();
      const mockProducts = inventoryData.map(item => ({
        id: item.id,
        name: item.name,
        price: item.price,
        quantity: item.quantity,
        reserved: item.reserved,
        image: `https://picsum.photos/300/200?random=${item.id}`,
        description: `High-quality ${item.name.toLowerCase()} for your needs.`,
        category: 'Electronics'
      }));
      setProducts(mockProducts);
      
      // Track products loaded
      telemetry.trackEvent('ProductsLoaded', {
        productCount: mockProducts.length,
        customerId: selectedCustomer
      });
    } catch (error) {
      console.error('Error loading products:', error);
      onNotification('Failed to load products', 'error');
      telemetry.trackException(error, { operation: 'loadProducts' });
    }
  };

  const loadOrders = async () => {
    try {
      const ordersData = await api.getOrders();
      // Filter orders for the selected customer
      const customerOrders = ordersData.filter(order => order.customerId === selectedCustomer);
      setOrders(customerOrders);
    } catch (error) {
      console.error('Error loading orders:', error);
    }
  };

  const connectWebSocket = () => {
    try {
      const notificationServiceUrl = process.env.REACT_APP_NOTIFICATION_SERVICE_URL;
      
      // Skip WebSocket if notification service URL is not configured
      if (!notificationServiceUrl) {
        console.log('Notification service not configured, skipping WebSocket connection');
        return;
      }
      
      const ws = new WebSocket(`${notificationServiceUrl}/ws?customerId=${selectedCustomer}`);
      
      ws.onopen = () => {
        console.log('WebSocket connected');
        telemetry.trackEvent('WebSocketConnected', { customerId: selectedCustomer });
      };
      
      ws.onmessage = (event) => {
        const message = JSON.parse(event.data);
        setNotifications(prev => [message, ...prev.slice(0, 9)]); // Keep last 10
        onNotification(`New notification: ${message.data?.subject || 'Update'}`, 'info');
        
        telemetry.trackEvent('NotificationReceived', {
          customerId: selectedCustomer,
          notificationType: message.type,
          messageType: message.data?.type
        });
      };
      
      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        telemetry.trackException(new Error('WebSocket error'), { operation: 'websocket' });
      };
      
      setWsConnection(ws);
    } catch (error) {
      console.error('Failed to connect WebSocket:', error);
    }
  };

  const addToCart = async (product) => {
    const startTime = performance.now();
    
    try {
      // Check inventory availability
      const availabilityCheck = await api.checkInventory(product.id, 1);
      
      if (!availabilityCheck.available) {
        onNotification('Product not available', 'warning');
        telemetry.trackBusinessEvent('AddToCartFailed', {
          productId: product.id.toString(),
          customerId: selectedCustomer,
          reason: 'outOfStock'
        });
        return;
      }

      const existingItem = cart.find(item => item.id === product.id);
      if (existingItem) {
        setCart(cart.map(item =>
          item.id === product.id
            ? { ...item, quantity: item.quantity + 1 }
            : item
        ));
      } else {
        setCart([...cart, { ...product, quantity: 1 }]);
      }

      const duration = performance.now() - startTime;
      telemetry.trackPerformance('AddToCart', duration, true, {
        productId: product.id.toString(),
        customerId: selectedCustomer
      });

      telemetry.trackBusinessEvent('AddToCart', {
        productId: product.id.toString(),
        productName: product.name,
        price: product.price,
        customerId: selectedCustomer
      });

      onNotification(`${product.name} added to cart`, 'success');
    } catch (error) {
      console.error('Error adding to cart:', error);
      telemetry.trackException(error, { operation: 'addToCart', productId: product.id.toString() });
      onNotification('Failed to add item to cart', 'error');
    }
  };

  const removeFromCart = (productId) => {
    const item = cart.find(item => item.id === productId);
    setCart(cart.filter(item => item.id !== productId));
    
    telemetry.trackBusinessEvent('RemoveFromCart', {
      productId: productId.toString(),
      customerId: selectedCustomer,
      quantity: item?.quantity || 0
    });
  };

  const updateCartQuantity = (productId, newQuantity) => {
    if (newQuantity <= 0) {
      removeFromCart(productId);
      return;
    }

    setCart(cart.map(item =>
      item.id === productId
        ? { ...item, quantity: newQuantity }
        : item
    ));

    telemetry.trackUserAction('UpdateCartQuantity', 'cart', {
      productId: productId.toString(),
      newQuantity: newQuantity.toString(),
      customerId: selectedCustomer
    });
  };

  const getCartTotal = () => {
    return cart.reduce((total, item) => total + (item.price * item.quantity), 0);
  };

  const getCartItemCount = () => {
    return cart.reduce((total, item) => total + item.quantity, 0);
  };

  const startCheckout = () => {
    if (cart.length === 0) {
      onNotification('Cart is empty', 'warning');
      return;
    }

    setCheckoutOpen(true);
    setActiveStep(0);
    
    telemetry.trackBusinessEvent('CheckoutStarted', {
      customerId: selectedCustomer,
      cartItems: cart.length,
      totalAmount: getCartTotal()
    });

    telemetry.trackFormInteraction('Checkout', 'start', null, {
      customerId: selectedCustomer,
      itemCount: cart.length
    });
  };

  const processOrder = async () => {
    setLoading(true);
    const startTime = performance.now();
    
    try {
      // Process cart as a single order with payment
      const orderData = {
        customerId: selectedCustomer,
        items: cart.map(item => ({
          productId: item.id,
          quantity: item.quantity,
          unitPrice: item.price,
          totalPrice: item.price * item.quantity
        })),
        totalAmount: getCartTotal(),
        paymentMethod: {
          type: 'credit_card',
          cardNumber: '**** **** **** 1234',
          expiryMonth: '12',
          expiryYear: '2026',
          cvv: '***',
          cardHolderName: customers.find(c => c.id === selectedCustomer)?.name
        }
      };

      // Process payment through API Gateway
      const result = await api.processPayment(orderData);
      
      setOrders([...orders, result.order]);
      
      // Mark order as placed and show confirmation
      setOrderPlaced(true);
      setActiveStep(3); // Move to confirmation step

      const duration = performance.now() - startTime;
      
      // Track successful order and payment
      telemetry.trackBusinessEvent('OrderCompleted', {
        customerId: selectedCustomer,
        orderId: result.order.id,
        paymentId: result.payment.paymentId,
        totalAmount: orderData.totalAmount,
        paymentStatus: result.payment.status,
        processingTime: duration
      });

      telemetry.trackFormInteraction('Checkout', 'complete', null, {
        customerId: selectedCustomer,
        orderId: result.order.id,
        paymentStatus: result.payment.status
      });

      telemetry.trackPerformance('OrderProcessing', duration, true, {
        customerId: selectedCustomer,
        itemCount: cart.length
      });

      onNotification(`Successfully placed order!`, 'success');

      // Simulate order status updates
      setTimeout(() => {
        setOrderStatus(prev => ({
          ...prev,
          [result.order.id]: 'Processing'
        }));
          
        telemetry.trackOrderEvent('StatusUpdate', result.order.id.toString(), selectedCustomer, result.order.totalAmount, {
          status: 'Processing'
        });
      }, 2000);

      setTimeout(() => {
        setOrderStatus(prev => ({
          ...prev,
          [result.order.id]: 'Shipped'
        }));
        
        telemetry.trackOrderEvent('StatusUpdate', result.order.id.toString(), selectedCustomer, result.order.totalAmount, {
          status: 'Shipped'
        });
      }, 5000);

    } catch (error) {
      console.error('Error processing order:', error);
      telemetry.trackException(error, { 
        operation: 'processOrder',
        customerId: selectedCustomer,
        cartItems: cart.length
      });
      
      telemetry.trackFormInteraction('Checkout', 'error', null, {
        customerId: selectedCustomer,
        error: error.message
      });

      onNotification('Failed to process order', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleNext = () => {
    if (activeStep === checkoutSteps.length - 1) {
      processOrder();
    } else {
      setActiveStep(activeStep + 1);
      
      telemetry.trackFormInteraction('Checkout', 'next', `step_${activeStep}`, {
        customerId: selectedCustomer,
        stepName: checkoutSteps[activeStep]
      });
    }
  };

  const handleBack = () => {
    setActiveStep(activeStep - 1);
    
    telemetry.trackFormInteraction('Checkout', 'back', `step_${activeStep}`, {
      customerId: selectedCustomer,
      stepName: checkoutSteps[activeStep]
    });
  };

  const getStepContent = (step) => {
    // Show confirmation if order was placed
    if (orderPlaced) {
      return (
        <Box sx={{ p: 2, textAlign: 'center' }}>
          <CheckCircleIcon sx={{ fontSize: 60, color: 'green', mb: 2 }} />
          <Typography variant="h6">Order Confirmed!</Typography>
          <Typography>Your orders have been placed successfully.</Typography>
        </Box>
      );
    }

    switch (step) {
      case 0:
        return (
          <List>
            {cart.map((item) => (
              <ListItem key={item.id}>
                <ListItemText
                  primary={item.name}
                  secondary={`$${item.price} x ${item.quantity} = $${(item.price * item.quantity).toFixed(2)}`}
                />
              </ListItem>
            ))}
            <Divider />
            <ListItem>
              <ListItemText
                primary={<Typography variant="h6">Total: ${getCartTotal().toFixed(2)}</Typography>}
              />
            </ListItem>
          </List>
        );
      case 1:
        return (
          <Box sx={{ p: 2 }}>
            <Typography variant="h6" gutterBottom>Shipping Information</Typography>
            <TextField fullWidth label="Address" margin="normal" defaultValue="123 Main St" />
            <TextField fullWidth label="City" margin="normal" defaultValue="Seattle" />
            <TextField fullWidth label="ZIP Code" margin="normal" defaultValue="98101" />
          </Box>
        );
      case 2:
        return (
          <Box sx={{ p: 2 }}>
            <Typography variant="h6" gutterBottom>Payment Information</Typography>
            <TextField fullWidth label="Card Number" margin="normal" defaultValue="**** **** **** 1234" />
            <TextField fullWidth label="Expiry Date (MM/YY)" margin="normal" defaultValue="12/26" />
            <TextField fullWidth label="CVV" margin="normal" defaultValue="123" type="password" />
          </Box>
        );
      default:
        return 'Unknown step';
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h4">eCommerce Store Demo</Typography>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
          <FormControl sx={{ minWidth: 200 }}>
            <InputLabel>Customer</InputLabel>
            <Select
              value={selectedCustomer}
              onChange={(e) => setSelectedCustomer(e.target.value)}
              label="Customer"
            >
              {customers.map((customer) => (
                <MenuItem key={customer.id} value={customer.id}>
                  {customer.name}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          
          <Badge badgeContent={notifications.length} color="secondary">
            <IconButton>
              <NotificationIcon />
            </IconButton>
          </Badge>

          <Badge badgeContent={getCartItemCount()} color="primary">
            <IconButton onClick={startCheckout}>
              <CartIcon />
            </IconButton>
          </Badge>
        </Box>
      </Box>

      <Alert severity="info" sx={{ mb: 3 }}>
        Browse products, add to cart, and complete orders to generate telemetry data across all services.
        Real-time notifications will appear via WebSocket from the Golang notification service.
      </Alert>

      {/* Products Grid */}
      <Typography variant="h5" sx={{ mb: 2 }}>Products</Typography>
      <Grid container spacing={3} sx={{ mb: 4 }}>
        {products.map((product) => (
          <Grid item xs={12} sm={6} md={4} lg={3} key={product.id}>
            <Card sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
              <CardMedia
                component="img"
                height="200"
                image={product.image}
                alt={product.name}
              />
              <CardContent sx={{ flexGrow: 1 }}>
                <Typography variant="h6" gutterBottom>
                  {product.name}
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                  {product.description}
                </Typography>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Typography variant="h6" color="primary">
                    ${product.price}
                  </Typography>
                  <Chip 
                    label={`${product.quantity - product.reserved} available`} 
                    size="small" 
                    color={product.quantity - product.reserved > 10 ? 'success' : 'warning'}
                  />
                </Box>
                <Button
                  fullWidth
                  variant="contained"
                  onClick={() => addToCart(product)}
                  disabled={product.quantity - product.reserved <= 0}
                >
                  Add to Cart
                </Button>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      {/* Recent Orders */}
      <Typography variant="h5" sx={{ mb: 2 }}>Recent Orders</Typography>
      <Paper sx={{ p: 2 }}>
        {orders.length > 0 ? (
          <List>
            {orders.slice(0, 5).map((order) => (
              <ListItem key={order.id}>
                <ListItemText
                  primary={`Order #${order.id}`}
                  secondary={
                    <Box>
                      <Typography variant="body2">
                        Customer: {order.customerId} | Amount: ${order.totalAmount}
                      </Typography>
                      <Box sx={{ mt: 1 }}>
                        <Chip
                          icon={orderStatus[order.id] === 'Shipped' ? <ShippingIcon /> : <PaymentIcon />}
                          label={orderStatus[order.id] || order.status || 'Pending'}
                          color={orderStatus[order.id] === 'Shipped' ? 'success' : 'primary'}
                          size="small"
                        />
                      </Box>
                    </Box>
                  }
                />
                <ListItemSecondaryAction>
                  <Typography variant="caption">
                    {new Date(order.createdAt).toLocaleTimeString()}
                  </Typography>
                </ListItemSecondaryAction>
              </ListItem>
            ))}
          </List>
        ) : (
          <Typography>No orders yet. Start shopping to see orders here!</Typography>
        )}
      </Paper>

      {/* Checkout Dialog */}
      <Dialog
        open={checkoutOpen}
        onClose={() => {
          setCheckoutOpen(false);
          setActiveStep(0);
          setOrderPlaced(false);
          if (orderPlaced) {
            setCart([]);
          }
        }}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>Checkout</DialogTitle>
        <DialogContent>
          <Stepper activeStep={activeStep} sx={{ mb: 3 }}>
            {checkoutSteps.map((label) => (
              <Step key={label}>
                <StepLabel>{label}</StepLabel>
              </Step>
            ))}
          </Stepper>
          {getStepContent(activeStep)}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => {
            setCheckoutOpen(false);
            setActiveStep(0);
            setOrderPlaced(false);
            if (orderPlaced) {
              setCart([]);
            }
          }}>
            {orderPlaced ? 'Close' : 'Cancel'}
          </Button>
          {!orderPlaced && (
            <>
              <Button onClick={handleBack} disabled={activeStep === 0}>
                Back
              </Button>
              <Button
                onClick={handleNext}
                variant="contained"
                disabled={loading}
                startIcon={loading ? <CircularProgress size={20} /> : null}
              >
                {activeStep === checkoutSteps.length - 1 ? 'Place Order' : 'Next'}
              </Button>
            </>
          )}
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default ECommerceStore;