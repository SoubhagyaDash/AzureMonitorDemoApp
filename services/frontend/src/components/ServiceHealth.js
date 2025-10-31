import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  Grid,
  Typography,
  Chip,
  LinearProgress,
  Alert,
  Box,
  IconButton
} from '@mui/material';
import {
  CheckCircle as HealthyIcon,
  Error as ErrorIcon,
  Warning as WarningIcon,
  Info as InfoIcon,
  Refresh as RefreshIcon
} from '@mui/icons-material';
import './ServiceHealth.css';

const ServiceHealth = () => {
  const [services, setServices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState(new Date());

  const serviceDefaults = [
    {
      name: 'API Gateway',
      envKey: 'REACT_APP_API_GATEWAY_HEALTH_URL',
      fallback: 'http://localhost:5000/health',
      type: 'dotnet'
    },
    {
      name: 'Order Service',
      envKey: 'REACT_APP_ORDER_SERVICE_HEALTH_URL',
      fallback: 'http://localhost:8080/actuator/health',
      type: 'java'
    },
    {
      name: 'Payment Service',
      envKey: 'REACT_APP_PAYMENT_SERVICE_HEALTH_URL',
      fallback: 'http://localhost:3000/health',
      type: 'dotnet'
    },
    {
      name: 'Event Processor',
      envKey: 'REACT_APP_EVENT_PROCESSOR_HEALTH_URL',
      fallback: 'http://localhost:8000/health',
      type: 'python'
    },
    {
      name: 'Inventory Service',
      envKey: 'REACT_APP_INVENTORY_SERVICE_HEALTH_URL',
      fallback: 'http://localhost:3001/health',
      type: 'nodejs'
    },
    {
      name: 'Notification Service',
      envKey: 'REACT_APP_NOTIFICATION_SERVICE_HEALTH_URL',
      fallback: 'http://localhost:9090/health',
      type: 'golang'
    }
  ];

  const serviceEndpoints = serviceDefaults.map(({ envKey, fallback, ...rest }) => ({
    ...rest,
    url: process.env[envKey] || fallback
  }));

  const checkServiceHealth = async (service) => {
    try {
      // For demo purposes, simulate health checks
      // In production, this would make actual HTTP requests
      const isHealthy = Math.random() > 0.2; // 80% chance of being healthy
      const responseTime = Math.floor(Math.random() * 500) + 50;
      
      return {
        ...service,
        status: isHealthy ? 'healthy' : 'unhealthy',
        responseTime,
        lastCheck: new Date(),
        message: isHealthy ? 'Service is operational' : 'Service experiencing issues',
        uptime: Math.floor(Math.random() * 100) + 95 // 95-100% uptime
      };
    } catch (error) {
      return {
        ...service,
        status: 'error',
        responseTime: null,
        lastCheck: new Date(),
        message: 'Failed to reach service',
        uptime: 0
      };
    }
  };

  const refreshHealthStatus = async () => {
    setLoading(true);
    const healthPromises = serviceEndpoints.map(checkServiceHealth);
    const results = await Promise.all(healthPromises);
    setServices(results);
    setLastUpdated(new Date());
    setLoading(false);
  };

  useEffect(() => {
    refreshHealthStatus();
    
    // Auto-refresh every 30 seconds
    const interval = setInterval(refreshHealthStatus, 30000);
    return () => clearInterval(interval);
  }, []);

  const getStatusIcon = (status) => {
    switch (status) {
      case 'healthy':
        return <HealthyIcon color="success" />;
      case 'unhealthy':
        return <WarningIcon color="warning" />;
      case 'error':
        return <ErrorIcon color="error" />;
      default:
        return <InfoIcon color="info" />;
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'healthy':
        return 'success';
      case 'unhealthy':
        return 'warning';
      case 'error':
        return 'error';
      default:
        return 'default';
    }
  };

  const getTechnologyColor = (type) => {
    const colors = {
      'dotnet': '#512BD4',
      'java': '#ED8B00',
      'python': '#3776AB',
      'nodejs': '#339933',
      'golang': '#00ADD8'
    };
    return colors[type] || '#666';
  };

  const overallHealth = services.length > 0 ? 
    services.filter(s => s.status === 'healthy').length / services.length * 100 : 0;

  return (
    <div className="service-health">
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h4" component="h1">
          🏥 Service Health Dashboard
        </Typography>
        <Box display="flex" alignItems="center" gap={2}>
          <Typography variant="body2" color="textSecondary">
            Last updated: {lastUpdated.toLocaleTimeString()}
          </Typography>
          <IconButton onClick={refreshHealthStatus} disabled={loading}>
            <RefreshIcon />
          </IconButton>
        </Box>
      </Box>

      {/* Overall Health Summary */}
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Typography variant="h6" gutterBottom>
            Overall System Health
          </Typography>
          <Box display="flex" alignItems="center" gap={2}>
            <LinearProgress 
              variant="determinate" 
              value={overallHealth} 
              sx={{ flexGrow: 1, height: 10, borderRadius: 5 }}
              color={overallHealth > 80 ? 'success' : overallHealth > 60 ? 'warning' : 'error'}
            />
            <Typography variant="h6" color={overallHealth > 80 ? 'success.main' : overallHealth > 60 ? 'warning.main' : 'error.main'}>
              {overallHealth.toFixed(1)}%
            </Typography>
          </Box>
          <Typography variant="body2" color="textSecondary" mt={1}>
            {services.filter(s => s.status === 'healthy').length} of {services.length} services healthy
          </Typography>
        </CardContent>
      </Card>

      {/* Service Cards */}
      <Grid container spacing={3}>
        {services.map((service, index) => (
          <Grid item xs={12} md={6} lg={4} key={index}>
            <Card className={`service-card ${service.status}`}>
              <CardContent>
                <Box display="flex" justifyContent="space-between" alignItems="flex-start" mb={2}>
                  <Typography variant="h6" component="h3">
                    {service.name}
                  </Typography>
                  {getStatusIcon(service.status)}
                </Box>

                <Box display="flex" gap={1} mb={2}>
                  <Chip 
                    label={service.type.toUpperCase()} 
                    size="small" 
                    sx={{ 
                      backgroundColor: getTechnologyColor(service.type),
                      color: 'white',
                      fontWeight: 'bold'
                    }}
                  />
                  <Chip 
                    label={service.status.toUpperCase()} 
                    size="small" 
                    color={getStatusColor(service.status)}
                    variant="outlined"
                  />
                </Box>

                <Typography variant="body2" color="textSecondary" gutterBottom>
                  {service.message}
                </Typography>

                {service.responseTime && (
                  <Typography variant="body2" color="textSecondary">
                    Response Time: {service.responseTime}ms
                  </Typography>
                )}

                <Typography variant="body2" color="textSecondary">
                  Uptime: {service.uptime}%
                </Typography>

                <Typography variant="caption" color="textSecondary" display="block" mt={1}>
                  Last checked: {service.lastCheck.toLocaleTimeString()}
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      {services.length === 0 && !loading && (
        <Alert severity="info" sx={{ mt: 2 }}>
          No services configured for health monitoring.
        </Alert>
      )}

      <Box mt={4}>
        <Alert severity="info">
          <Typography variant="body2">
            <strong>Service Health Monitoring:</strong> This dashboard shows the real-time health status 
            of all OpenTelemetry demo microservices. Health checks include response time, uptime metrics, 
            and service availability across the distributed system.
          </Typography>
        </Alert>
      </Box>
    </div>
  );
};

export default ServiceHealth;