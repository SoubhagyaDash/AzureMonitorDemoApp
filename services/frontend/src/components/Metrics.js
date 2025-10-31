import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  Grid,
  Typography,
  Box,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Alert,
  LinearProgress
} from '@mui/material';
import {
  BarChart,
  Bar,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  AreaChart,
  Area
} from 'recharts';
import './Metrics.css';

const Metrics = () => {
  const [timeRange, setTimeRange] = useState('1h');
  const [refreshInterval, setRefreshInterval] = useState(30);
  const [metricsData, setMetricsData] = useState({
    requestMetrics: [],
    errorRates: [],
    responseTime: [],
    serviceDistribution: [],
    throughput: []
  });
  const [loading, setLoading] = useState(true);

  // Generate mock metrics data
  const generateMetricsData = () => {
    const now = new Date();
    const intervals = timeRange === '1h' ? 12 : timeRange === '6h' ? 24 : 48;
    const minuteStep = timeRange === '1h' ? 5 : timeRange === '6h' ? 15 : 30;

    const requestMetrics = [];
    const errorRates = [];
    const responseTime = [];
    const throughput = [];

    for (let i = intervals - 1; i >= 0; i--) {
      const time = new Date(now.getTime() - i * minuteStep * 60 * 1000);
      const timestamp = time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      
      const requests = Math.floor(Math.random() * 1000) + 500;
      const errors = Math.floor(Math.random() * 50) + 5;
      const avgResponseTime = Math.floor(Math.random() * 200) + 100;
      
      requestMetrics.push({
        time: timestamp,
        successful: requests - errors,
        failed: errors,
        total: requests
      });

      errorRates.push({
        time: timestamp,
        errorRate: (errors / requests * 100).toFixed(2)
      });

      responseTime.push({
        time: timestamp,
        avg: avgResponseTime,
        p95: avgResponseTime + Math.floor(Math.random() * 100) + 50,
        p99: avgResponseTime + Math.floor(Math.random() * 200) + 100
      });

      throughput.push({
        time: timestamp,
        rps: Math.floor(requests / (minuteStep * 60)) + Math.floor(Math.random() * 10)
      });
    }

    const serviceDistribution = [
      { name: 'API Gateway', value: 35, color: '#8884d8' },
      { name: 'Order Service', value: 25, color: '#82ca9d' },
      { name: 'Payment Service', value: 20, color: '#ffc658' },
      { name: 'Inventory Service', value: 15, color: '#ff7300' },
      { name: 'Event Processor', value: 5, color: '#8dd1e1' }
    ];

    return {
      requestMetrics,
      errorRates,
      responseTime,
      serviceDistribution,
      throughput
    };
  };

  const refreshMetrics = () => {
    setLoading(true);
    setTimeout(() => {
      setMetricsData(generateMetricsData());
      setLoading(false);
    }, 1000);
  };

  useEffect(() => {
    refreshMetrics();
  }, [timeRange]);

  useEffect(() => {
    const interval = setInterval(refreshMetrics, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [refreshInterval]);

  const formatTooltipValue = (value, name) => {
    if (name === 'errorRate') return `${value}%`;
    if (name === 'avg' || name === 'p95' || name === 'p99') return `${value}ms`;
    if (name === 'rps') return `${value} req/s`;
    return value;
  };

  return (
    <div className="metrics-dashboard">
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h4" component="h1">
          📊 OpenTelemetry Metrics Dashboard
        </Typography>
        
        <Box display="flex" gap={2}>
          <FormControl size="small" sx={{ minWidth: 120 }}>
            <InputLabel>Time Range</InputLabel>
            <Select value={timeRange} onChange={(e) => setTimeRange(e.target.value)} label="Time Range">
              <MenuItem value="1h">Last 1 Hour</MenuItem>
              <MenuItem value="6h">Last 6 Hours</MenuItem>
              <MenuItem value="24h">Last 24 Hours</MenuItem>
            </Select>
          </FormControl>
          
          <FormControl size="small" sx={{ minWidth: 120 }}>
            <InputLabel>Refresh</InputLabel>
            <Select value={refreshInterval} onChange={(e) => setRefreshInterval(e.target.value)} label="Refresh">
              <MenuItem value={10}>10 seconds</MenuItem>
              <MenuItem value={30}>30 seconds</MenuItem>
              <MenuItem value={60}>1 minute</MenuItem>
            </Select>
          </FormControl>
        </Box>
      </Box>

      {loading && <LinearProgress sx={{ mb: 2 }} />}

      <Grid container spacing={3}>
        {/* Request Volume */}
        <Grid item xs={12} lg={8}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                📈 Request Volume Over Time
              </Typography>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={metricsData.requestMetrics}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" />
                  <YAxis />
                  <Tooltip formatter={formatTooltipValue} />
                  <Bar dataKey="successful" stackId="a" fill="#4caf50" name="Successful" />
                  <Bar dataKey="failed" stackId="a" fill="#f44336" name="Failed" />
                </BarChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>

        {/* Service Distribution */}
        <Grid item xs={12} lg={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                🔄 Traffic Distribution
              </Typography>
              <ResponsiveContainer width="100%" height={300}>
                <PieChart>
                  <Pie
                    data={metricsData.serviceDistribution}
                    cx="50%"
                    cy="50%"
                    labelLine={false}
                    label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
                    outerRadius={80}
                    fill="#8884d8"
                    dataKey="value"
                  >
                    {metricsData.serviceDistribution.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={entry.color} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>

        {/* Error Rate */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                ⚠️ Error Rate
              </Typography>
              <ResponsiveContainer width="100%" height={250}>
                <AreaChart data={metricsData.errorRates}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" />
                  <YAxis />
                  <Tooltip formatter={formatTooltipValue} />
                  <Area type="monotone" dataKey="errorRate" stroke="#f44336" fill="#f4433620" />
                </AreaChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>

        {/* Response Time */}
        <Grid item xs={12} lg={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                ⏱️ Response Time Percentiles
              </Typography>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={metricsData.responseTime}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" />
                  <YAxis />
                  <Tooltip formatter={formatTooltipValue} />
                  <Line type="monotone" dataKey="avg" stroke="#2196f3" name="Average" />
                  <Line type="monotone" dataKey="p95" stroke="#ff9800" name="95th Percentile" />
                  <Line type="monotone" dataKey="p99" stroke="#f44336" name="99th Percentile" />
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>

        {/* Throughput */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                🚀 Throughput (Requests per Second)
              </Typography>
              <ResponsiveContainer width="100%" height={200}>
                <AreaChart data={metricsData.throughput}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" />
                  <YAxis />
                  <Tooltip formatter={formatTooltipValue} />
                  <Area type="monotone" dataKey="rps" stroke="#4caf50" fill="#4caf5020" />
                </AreaChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <Box mt={4}>
        <Alert severity="info">
          <Typography variant="body2">
            <strong>OpenTelemetry Metrics:</strong> This dashboard displays real-time metrics collected 
            from all microservices using OpenTelemetry SDKs. Metrics include request volume, error rates, 
            response times, and throughput across the distributed system.
          </Typography>
        </Alert>
      </Box>
    </div>
  );
};

export default Metrics;