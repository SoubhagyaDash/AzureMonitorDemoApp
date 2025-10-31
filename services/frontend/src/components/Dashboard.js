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
  Alert
} from '@mui/material';
import {
  CheckCircle as CheckCircleIcon,
  Error as ErrorIcon,
  Warning as WarningIcon,
  Computer as ComputerIcon,
  Cloud as CloudIcon,
  Storage as StorageIcon
} from '@mui/icons-material';
import { Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend } from 'chart.js';
import { Line } from 'react-chartjs-2';
import { format } from 'date-fns';
import api from '../services/api';

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend);

const Dashboard = ({ onNotification }) => {
  const [services, setServices] = useState([]);
  const [metrics, setMetrics] = useState({});
  const [recentOrders, setRecentOrders] = useState([]);
  const [systemHealth, setSystemHealth] = useState({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchDashboardData();
    const interval = setInterval(fetchDashboardData, 5000); // Refresh every 5 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchDashboardData = async () => {
    try {
      const [servicesData, ordersData, healthData] = await Promise.all([
        api.getServiceStatus(),
        api.getRecentOrders(),
        api.getSystemHealth()
      ]);
      
      setServices(servicesData);
      setRecentOrders(ordersData);
      setSystemHealth(healthData);
      setLoading(false);
    } catch (error) {
      console.error('Error fetching dashboard data:', error);
      onNotification('Failed to fetch dashboard data', 'error');
      setLoading(false);
    }
  };

  const getStatusIcon = (status) => {
    switch (status?.toLowerCase()) {
      case 'healthy':
        return <CheckCircleIcon sx={{ color: '#4caf50' }} />;
      case 'warning':
        return <WarningIcon sx={{ color: '#ff9800' }} />;
      case 'error':
      case 'unhealthy':
        return <ErrorIcon sx={{ color: '#f44336' }} />;
      default:
        return <WarningIcon sx={{ color: '#9e9e9e' }} />;
    }
  };

  const getStatusColor = (status) => {
    switch (status?.toLowerCase()) {
      case 'healthy':
        return 'success';
      case 'warning':
        return 'warning';
      case 'error':
      case 'unhealthy':
        return 'error';
      default:
        return 'default';
    }
  };

  // Sample data for metrics chart
  const chartData = {
    labels: Array.from({ length: 20 }, (_, i) => format(new Date(Date.now() - (19 - i) * 60000), 'HH:mm')),
    datasets: [
      {
        label: 'Requests/min',
        data: Array.from({ length: 20 }, () => Math.floor(Math.random() * 100) + 50),
        borderColor: '#0078d4',
        backgroundColor: 'rgba(0, 120, 212, 0.1)',
        tension: 0.4,
      },
      {
        label: 'Errors/min',
        data: Array.from({ length: 20 }, () => Math.floor(Math.random() * 10)),
        borderColor: '#d13438',
        backgroundColor: 'rgba(209, 52, 56, 0.1)',
        tension: 0.4,
      }
    ]
  };

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top',
      },
      title: {
        display: true,
        text: 'System Metrics Overview'
      }
    },
    scales: {
      y: {
        beginAtZero: true
      }
    }
  };

  if (loading) {
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
      <Typography variant="h4" sx={{ mb: 3 }}>
        System Dashboard
      </Typography>

      <Alert severity="info" sx={{ mb: 3 }}>
        This dashboard showcases Azure Monitor OpenTelemetry integration across multiple languages and deployment targets.
        Use the Traffic Generator to create synthetic load and observe distributed tracing in action.
      </Alert>

      <Grid container spacing={3}>
        {/* Service Status Cards */}
        <Grid item xs={12}>
          <Typography variant="h5" sx={{ mb: 2 }}>
            Service Health
          </Typography>
        </Grid>

        <Grid item xs={12} md={6} lg={3}>
          <Card className="metric-card">
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <ComputerIcon sx={{ mr: 1, color: '#0078d4' }} />
                <Typography variant="h6">API Gateway (.NET)</Typography>
              </Box>
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                {getStatusIcon('healthy')}
                <Chip label="VM Deployed" size="small" variant="outlined" />
              </Box>
              <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
                Azure Monitor OTel Distro
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={6} lg={3}>
          <Card className="metric-card">
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <CloudIcon sx={{ mr: 1, color: '#107c10' }} />
                <Typography variant="h6">Order Service (Java)</Typography>
              </Box>
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                {getStatusIcon('healthy')}
                <Chip label="AKS Deployed" size="small" variant="outlined" />
              </Box>
              <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
                Auto-instrumentation
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={6} lg={3}>
          <Card className="metric-card">
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <StorageIcon sx={{ mr: 1, color: '#ff6f00' }} />
                <Typography variant="h6">Event Processor (Python)</Typography>
              </Box>
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                {getStatusIcon('healthy')}
                <Chip label="AKS Deployed" size="small" variant="outlined" />
              </Box>
              <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
                OSS OTel SDK
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={6} lg={3}>
          <Card className="metric-card">
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <StorageIcon sx={{ mr: 1, color: '#8bc34a' }} />
                <Typography variant="h6">Inventory Service (Node.js)</Typography>
              </Box>
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                {getStatusIcon('healthy')}
                <Chip label="AKS Deployed" size="small" variant="outlined" />
              </Box>
              <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
                OSS OTel SDK
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        {/* Metrics Chart */}
        <Grid item xs={12} lg={8}>
          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                System Metrics
              </Typography>
              <Box sx={{ height: 300 }}>
                <Line data={chartData} options={chartOptions} />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Recent Orders */}
        <Grid item xs={12} lg={4}>
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

        {/* System Information */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                OpenTelemetry Configuration
              </Typography>
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" color="primary">
                    Azure Monitor Distro Services
                  </Typography>
                  <Typography variant="body2">
                    • API Gateway (.NET) - Running on Azure VMs
                  </Typography>
                </Grid>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" color="primary">
                    OSS OpenTelemetry Services
                  </Typography>
                  <Typography variant="body2">
                    • Event Processor (Python) - OTLP Export<br />
                    • Inventory Service (Node.js) - OTLP Export
                  </Typography>
                </Grid>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" color="primary">
                    Auto-instrumented Services
                  </Typography>
                  <Typography variant="body2">
                    • Order Service (Java) - AKS Auto-instrumentation
                  </Typography>
                </Grid>
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" color="primary">
                    Azure Resources
                  </Typography>
                  <Typography variant="body2">
                    • Event Hub, SQL Database, Cosmos DB, Redis Cache
                  </Typography>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
};

export default Dashboard;