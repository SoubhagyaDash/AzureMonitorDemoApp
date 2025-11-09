import React, { useState, useEffect } from 'react';
import {
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Chip,
  LinearProgress,
  List,
  ListItem,
  ListItemText,
  Divider,
  Alert,
  IconButton
} from '@mui/material';
import {
  CheckCircle as HealthyIcon,
  Error as ErrorIcon,
  Warning as WarningIcon,
  Info as InfoIcon,
  Refresh as RefreshIcon
} from '@mui/icons-material';
import api from '../services/api';

const Dashboard = ({ onNotification }) => {
  const [services, setServices] = useState([]);
  const [recentOrders, setRecentOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState(new Date());

  useEffect(() => {
    fetchDashboardData();
    const interval = setInterval(fetchDashboardData, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchDashboardData = async () => {
    try {
      const [servicesData, ordersData] = await Promise.all([
        api.getServiceStatus(),
        api.getRecentOrders().catch(() => [])
      ]);
      
      setServices(servicesData || []);
      setRecentOrders(ordersData || []);
      setLastUpdated(new Date());
      setLoading(false);
    } catch (error) {
      console.error('Error fetching dashboard data:', error);
      onNotification?.('Failed to fetch dashboard data', 'error');
      setLoading(false);
    }
  };

  const handleRefresh = () => {
    setLoading(true);
    fetchDashboardData();
  };

  const getStatusIcon = (status) => {
    switch (status?.toLowerCase()) {
      case 'healthy':
        return <HealthyIcon sx={{ color: '#4caf50' }} />;
      case 'warning':
      case 'unhealthy':
        return <WarningIcon sx={{ color: '#ff9800' }} />;
      case 'error':
        return <ErrorIcon sx={{ color: '#f44336' }} />;
      default:
        return <InfoIcon sx={{ color: '#9e9e9e' }} />;
    }
  };

  const getStatusColor = (status) => {
    switch (status?.toLowerCase()) {
      case 'healthy':
        return 'success';
      case 'warning':
      case 'unhealthy':
        return 'warning';
      case 'error':
        return 'error';
      default:
        return 'default';
    }
  };

  const getTechnologyBadge = (serviceName) => {
    if (serviceName.includes('Gateway')) return { label: '.NET', color: '#512BD4' };
    if (serviceName.includes('Order')) return { label: 'Java', color: '#ED8B00' };
    if (serviceName.includes('Payment')) return { label: '.NET', color: '#512BD4' };
    if (serviceName.includes('Event')) return { label: 'Python', color: '#3776AB' };
    if (serviceName.includes('Notification')) return { label: 'Go', color: '#00ADD8' };
    if (serviceName.includes('Inventory')) return { label: 'Node.js', color: '#339933' };
    return { label: 'Service', color: '#666' };
  };

  const getDeploymentTarget = (serviceName) => {
    if (serviceName.includes('Gateway') || serviceName.includes('Inventory')) {
      return { label: 'VM', icon: '🖥️', color: '#0078D4' };
    }
    return { label: 'AKS', icon: '☸️', color: '#326CE5' };
  };

  const getInstrumentationType = (serviceName) => {
    if (serviceName.includes('Order')) {
      return { label: 'Auto-instrumentation', short: 'Auto', color: '#107C10' };
    }
    return { label: 'OSS OTel SDK', short: 'OTel', color: '#0078D4' };
  };

  const overallHealth = services.length > 0 ? 
    (services.filter(s => s.status === 'healthy').length / services.length * 100).toFixed(0) : 0;

  if (loading && services.length === 0) {
    return (
      <Box sx={{ mt: 4 }}>
        <LinearProgress />
        <Typography sx={{ mt: 2, textAlign: 'center' }}>
          Loading dashboard data...
        </Typography>
      </Box>
    );
  }

  return (
    <Box>
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h4">
          System Dashboard
        </Typography>
        <Box display="flex" alignItems="center" gap={2}>
          <Typography variant="body2" color="textSecondary">
            Last updated: {lastUpdated.toLocaleTimeString()}
          </Typography>
          <IconButton onClick={handleRefresh} disabled={loading} size="small">
            <RefreshIcon />
          </IconButton>
        </Box>
      </Box>

      <Alert severity="info" sx={{ mb: 3 }}>
        This dashboard showcases Azure Monitor OpenTelemetry integration across multiple languages and deployment targets.
        Use the Traffic Generator to create synthetic load and observe distributed tracing in action.
      </Alert>

      {/* Overall Health Summary */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" color="textSecondary">
                Overall Health
              </Typography>
              <Typography variant="h3" sx={{ mt: 1 }}>
                {overallHealth}%
              </Typography>
              <Typography variant="body2" color="textSecondary">
                {services.filter(s => s.status === 'healthy').length} of {services.length} services healthy
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" color="textSecondary">
                Total Services
              </Typography>
              <Typography variant="h3" sx={{ mt: 1 }}>
                {services.length}
              </Typography>
              <Typography variant="body2" color="textSecondary">
                Active monitoring endpoints
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" color="textSecondary">
                Recent Orders
              </Typography>
              <Typography variant="h3" sx={{ mt: 1 }}>
                {recentOrders.length}
              </Typography>
              <Typography variant="body2" color="textSecondary">
                In the last 5 minutes
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <Grid container spacing={3}>
        {/* Service Status Cards */}
        <Grid item xs={12}>
          <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
            <Typography variant="h5">
              Service Health
            </Typography>
            {loading && <LinearProgress sx={{ width: '100px' }} />}
          </Box>
        </Grid>

        {services.map((service, index) => {
          const tech = getTechnologyBadge(service.name);
          const deployment = getDeploymentTarget(service.name);
          const instrumentation = getInstrumentationType(service.name);
          
          return (
            <Grid item xs={12} sm={6} md={4} key={index}>
              <Card sx={{ 
                borderLeft: `4px solid ${tech.color}`,
                height: '100%'
              }}>
                <CardContent>
                  <Box display="flex" justifyContent="space-between" alignItems="flex-start" mb={2}>
                    <Typography variant="h6" sx={{ flexGrow: 1 }}>
                      {service.name}
                    </Typography>
                    {getStatusIcon(service.status)}
                  </Box>
                  
                  <Box display="flex" gap={1} mb={2} flexWrap="wrap">
                    <Chip 
                      label={tech.label} 
                      size="small" 
                      sx={{ 
                        backgroundColor: tech.color, 
                        color: 'white',
                        fontWeight: 'bold'
                      }} 
                    />
                    <Chip 
                      label={service.status || 'Unknown'} 
                      size="small" 
                      color={getStatusColor(service.status)}
                    />
                  </Box>
                  
                  <Box display="flex" gap={1} mb={1} flexWrap="wrap">
                    <Chip 
                      label={`${deployment.icon} ${deployment.label}`}
                      size="small" 
                      variant="outlined"
                      sx={{ 
                        borderColor: deployment.color,
                        color: deployment.color,
                        fontWeight: 500
                      }} 
                    />
                    <Chip 
                      label={instrumentation.short}
                      title={instrumentation.label}
                      size="small" 
                      variant="outlined"
                      sx={{ 
                        borderColor: instrumentation.color,
                        color: instrumentation.color,
                        fontWeight: 500
                      }} 
                    />
                  </Box>
                  
                  {service.responseTime && (
                    <Typography variant="body2" color="textSecondary" sx={{ mt: 1 }}>
                      Response time: {service.responseTime}
                    </Typography>
                  )}
                  
                  {service.data?.message && (
                    <Typography variant="body2" color="textSecondary" sx={{ mt: 1 }}>
                      {service.data.message}
                    </Typography>
                  )}
                </CardContent>
              </Card>
            </Grid>
          );
        })}

        {/* Recent Orders */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                Recent Orders
              </Typography>
              <List dense>
                {recentOrders.length > 0 ? (
                  recentOrders.slice(0, 5).map((order, index) => (
                    <React.Fragment key={order.id || index}>
                      <ListItem>
                        <ListItemText
                          primary={`Order #${order.id || index + 1}`}
                          secondary={
                            <Box>
                              <Typography variant="body2" component="span">
                                Customer: {order.customerId || `customer-${index + 1}`}
                              </Typography>
                              <br />
                              <Chip
                                label={order.status || 'Pending'}
                                size="small"
                                color={getStatusColor(order.status)}
                                sx={{ mt: 0.5 }}
                              />
                            </Box>
                          }
                        />
                      </ListItem>
                      {index < Math.min(recentOrders.length, 5) - 1 && <Divider />}
                    </React.Fragment>
                  ))
                ) : (
                  <ListItem>
                    <ListItemText
                      primary="No recent orders"
                      secondary="Start the traffic generator to see orders here"
                    />
                  </ListItem>
                )}
              </List>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
};

export default Dashboard;
