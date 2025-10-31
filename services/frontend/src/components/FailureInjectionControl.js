import React, { useState, useEffect } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Grid,
  Slider,
  Switch,
  FormControlLabel,
  Button,
  Chip,
  Alert,
  Tabs,
  Tab,
  TextField,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  LinearProgress,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  IconButton,
  Tooltip
} from '@mui/material';
import {
  ExpandMore as ExpandMoreIcon,
  PlayArrow as PlayIcon,
  Stop as StopIcon,
  Refresh as RefreshIcon,
  Warning as WarningIcon,
  Speed as SpeedIcon,
  Error as ErrorIcon,
  Settings as SettingsIcon
} from '@mui/icons-material';
import api from '../services/api';
import { telemetry } from '../services/telemetry';

const FailureInjectionControl = ({ onNotification }) => {
  const [currentTab, setCurrentTab] = useState(0);
  const [services, setServices] = useState({
    'api-gateway': {
      name: 'API Gateway (.NET)',
      status: 'unknown',
      config: {
        enabled: true,
        latency: {
          probability: 0.1,
          minDelayMs: 100,
          maxDelayMs: 2000
        },
        errors: {
          probability: 0.05,
          types: ['timeout', 'database', 'network']
        }
      },
      endpoint: '/api/failure-injection',
      lastUpdated: null
    },
    'order-service': {
      name: 'Order Service (Java)',
      status: 'unknown',
      config: {
        enabled: true,
        latency: {
          probability: 0.1,
          min: 100,
          max: 2000
        },
        error: {
          probability: 0.05
        }
      },
      endpoint: '/api/failure-injection',
      lastUpdated: null
    },
    'event-processor': {
      name: 'Event Processor (Python)',
      status: 'unknown',
      config: {
        enabled: true,
        latency_probability: 0.1,
        error_probability: 0.05
      },
      endpoint: '/failure-injection',
      lastUpdated: null
    },
    'payment-service': {
      name: 'Payment Service (.NET)',
      status: 'unknown',
      config: {
        enabled: true,
        credit_card_failure_rate: 0.05,
        paypal_failure_rate: 0.02,
        bank_transfer_failure_rate: 0.01,
        unknown_method_failure_rate: 0.1
      },
      endpoint: '/api/failure-injection',
      lastUpdated: null
    }
  });

  const [globalConfig, setGlobalConfig] = useState({
    enabled: true,
    latencyProbability: 0.1,
    errorProbability: 0.05,
    minLatency: 100,
    maxLatency: 2000
  });

  const [scenarios, setScenarios] = useState([
    {
      name: 'Normal Operations',
      description: 'Minimal failure injection for baseline',
      config: { latencyProbability: 0.02, errorProbability: 0.01 }
    },
    {
      name: 'Light Load Testing',
      description: 'Low failure rates for demo scenarios',
      config: { latencyProbability: 0.05, errorProbability: 0.02 }
    },
    {
      name: 'Moderate Chaos',
      description: 'Medium failure rates for testing resilience',
      config: { latencyProbability: 0.15, errorProbability: 0.08 }
    },
    {
      name: 'Heavy Chaos',
      description: 'High failure rates for stress testing',
      config: { latencyProbability: 0.3, errorProbability: 0.15 }
    },
    {
      name: 'Disaster Simulation',
      description: 'Extreme failure rates for disaster recovery testing',
      config: { latencyProbability: 0.5, errorProbability: 0.25 }
    }
  ]);

  const [loading, setLoading] = useState(false);
  const [activeScenario, setActiveScenario] = useState('Normal Operations');

  useEffect(() => {
    loadCurrentConfigurations();
  }, []);

  const loadCurrentConfigurations = async () => {
    setLoading(true);
    try {
      // Get current service status and configurations
      const serviceStatus = await api.getServiceStatus();
      
      setServices(prev => {
        const updated = { ...prev };
        serviceStatus.forEach(service => {
          const serviceKey = service.name.toLowerCase().replace(' ', '-');
          if (updated[serviceKey]) {
            updated[serviceKey].status = service.status;
            updated[serviceKey].lastUpdated = new Date().toISOString();
          }
        });
        return updated;
      });

      onNotification('Service configurations loaded', 'success');
    } catch (error) {
      onNotification('Failed to load service configurations', 'error');
      console.error('Error loading configurations:', error);
    } finally {
      setLoading(false);
    }
  };

  const updateServiceConfig = async (serviceKey, config) => {
    setLoading(true);
    try {
      const service = services[serviceKey];
      
      // Transform config based on service type
      let payload = config;
      if (serviceKey === 'event-processor') {
        payload = {
          enabled: config.enabled,
          latency_probability: config.latency?.probability || config.latency_probability,
          error_probability: config.errors?.probability || config.error_probability
        };
      } else if (serviceKey === 'order-service') {
        payload = {
          'failure.injection.enabled': config.enabled,
          'failure.injection.latency.probability': config.latency?.probability,
          'failure.injection.error.probability': config.errors?.probability || config.error?.probability
        };
      }

      // Make API call to update service configuration
      const response = await fetch(`${api.getServiceBaseUrl(serviceKey)}${service.endpoint}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload)
      });

      if (response.ok) {
        setServices(prev => ({
          ...prev,
          [serviceKey]: {
            ...prev[serviceKey],
            config: { ...prev[serviceKey].config, ...config },
            lastUpdated: new Date().toISOString(),
            status: 'healthy'
          }
        }));

        telemetry.trackEvent('FailureInjectionConfigured', {
          service: serviceKey,
          enabled: config.enabled,
          latencyProbability: config.latency?.probability || config.latency_probability,
          errorProbability: config.errors?.probability || config.error_probability
        });

        onNotification(`${service.name} configuration updated`, 'success');
      } else {
        throw new Error(`Failed to update ${service.name}`);
      }
    } catch (error) {
      onNotification(`Failed to update ${services[serviceKey].name}`, 'error');
      console.error('Error updating service config:', error);
    } finally {
      setLoading(false);
    }
  };

  const applyGlobalConfiguration = async () => {
    setLoading(true);
    try {
      const updates = Object.keys(services).map(serviceKey => {
        const adaptedConfig = {
          enabled: globalConfig.enabled,
          latency: {
            probability: globalConfig.latencyProbability,
            minDelayMs: globalConfig.minLatency,
            maxDelayMs: globalConfig.maxLatency
          },
          errors: {
            probability: globalConfig.errorProbability
          }
        };
        return updateServiceConfig(serviceKey, adaptedConfig);
      });

      await Promise.all(updates);
      onNotification('Global configuration applied to all services', 'success');
      
      telemetry.trackEvent('GlobalFailureInjectionApplied', {
        ...globalConfig,
        servicesCount: Object.keys(services).length
      });
    } catch (error) {
      onNotification('Failed to apply global configuration', 'error');
    } finally {
      setLoading(false);
    }
  };

  const applyScenario = async (scenario) => {
    const updatedGlobalConfig = {
      ...globalConfig,
      ...scenario.config
    };
    
    setGlobalConfig(updatedGlobalConfig);
    setActiveScenario(scenario.name);
    
    // Apply the scenario configuration
    await applyGlobalConfiguration();
    
    telemetry.trackEvent('ChaosScenarioApplied', {
      scenarioName: scenario.name,
      ...scenario.config
    });
  };

  const toggleAllServices = async (enabled) => {
    const updatedGlobalConfig = { ...globalConfig, enabled };
    setGlobalConfig(updatedGlobalConfig);
    await applyGlobalConfiguration();
  };

  const ServiceConfigCard = ({ serviceKey, service }) => (
    <Card sx={{ mb: 2 }}>
      <CardContent>
        <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
          <Typography variant="h6" component="div">
            {service.name}
          </Typography>
          <Box display="flex" alignItems="center" gap={1}>
            <Chip 
              label={service.status} 
              color={service.status === 'healthy' ? 'success' : 'error'}
              size="small"
            />
            <FormControlLabel
              control={
                <Switch
                  checked={service.config.enabled}
                  onChange={(e) => updateServiceConfig(serviceKey, { 
                    ...service.config, 
                    enabled: e.target.checked 
                  })}
                />
              }
              label="Enabled"
            />
          </Box>
        </Box>

        <Grid container spacing={3}>
          <Grid item xs={12} md={6}>
            <Typography variant="subtitle2" gutterBottom>
              Latency Injection
            </Typography>
            <Box sx={{ px: 2 }}>
              <Typography variant="body2" color="text.secondary" gutterBottom>
                Probability: {((service.config.latency?.probability || service.config.latency_probability || 0) * 100).toFixed(1)}%
              </Typography>
              <Slider
                value={(service.config.latency?.probability || service.config.latency_probability || 0) * 100}
                onChange={(e, value) => {
                  const probability = value / 100;
                  const updatedConfig = { ...service.config };
                  if (service.config.latency) {
                    updatedConfig.latency.probability = probability;
                  } else {
                    updatedConfig.latency_probability = probability;
                  }
                  updateServiceConfig(serviceKey, updatedConfig);
                }}
                min={0}
                max={50}
                step={1}
                marks={[
                  { value: 0, label: '0%' },
                  { value: 10, label: '10%' },
                  { value: 25, label: '25%' },
                  { value: 50, label: '50%' }
                ]}
                valueLabelDisplay="auto"
                valueLabelFormat={(value) => `${value}%`}
              />
            </Box>
          </Grid>

          <Grid item xs={12} md={6}>
            <Typography variant="subtitle2" gutterBottom>
              Error Injection
            </Typography>
            <Box sx={{ px: 2 }}>
              <Typography variant="body2" color="text.secondary" gutterBottom>
                Probability: {((service.config.errors?.probability || service.config.error?.probability || service.config.error_probability || 0) * 100).toFixed(1)}%
              </Typography>
              <Slider
                value={(service.config.errors?.probability || service.config.error?.probability || service.config.error_probability || 0) * 100}
                onChange={(e, value) => {
                  const probability = value / 100;
                  const updatedConfig = { ...service.config };
                  if (service.config.errors) {
                    updatedConfig.errors.probability = probability;
                  } else if (service.config.error) {
                    updatedConfig.error.probability = probability;
                  } else {
                    updatedConfig.error_probability = probability;
                  }
                  updateServiceConfig(serviceKey, updatedConfig);
                }}
                min={0}
                max={30}
                step={1}
                marks={[
                  { value: 0, label: '0%' },
                  { value: 5, label: '5%' },
                  { value: 15, label: '15%' },
                  { value: 30, label: '30%' }
                ]}
                valueLabelDisplay="auto"
                valueLabelFormat={(value) => `${value}%`}
              />
            </Box>
          </Grid>
        </Grid>

        {service.lastUpdated && (
          <Typography variant="caption" color="text.secondary" mt={2} display="block">
            Last updated: {new Date(service.lastUpdated).toLocaleString()}
          </Typography>
        )}
      </CardContent>
    </Card>
  );

  return (
    <Box sx={{ p: 3 }}>
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h4" component="h1">
          <SettingsIcon sx={{ mr: 1, verticalAlign: 'middle' }} />
          Failure Injection Control Center
        </Typography>
        <Box>
          <Tooltip title="Refresh service status">
            <IconButton onClick={loadCurrentConfigurations} disabled={loading}>
              <RefreshIcon />
            </IconButton>
          </Tooltip>
          <Button
            variant="contained"
            color="error"
            startIcon={globalConfig.enabled ? <StopIcon /> : <PlayIcon />}
            onClick={() => toggleAllServices(!globalConfig.enabled)}
            disabled={loading}
            sx={{ ml: 1 }}
          >
            {globalConfig.enabled ? 'Disable All' : 'Enable All'}
          </Button>
        </Box>
      </Box>

      {loading && <LinearProgress sx={{ mb: 2 }} />}

      <Alert severity="warning" sx={{ mb: 3 }}>
        <Typography variant="body2">
          Failure injection is enabled. This will introduce artificial latency and errors to demonstrate 
          observability patterns. Use responsibly in demo environments only.
        </Typography>
      </Alert>

      <Tabs value={currentTab} onChange={(e, newValue) => setCurrentTab(newValue)} sx={{ mb: 3 }}>
        <Tab label="Quick Scenarios" />
        <Tab label="Individual Services" />
        <Tab label="Global Configuration" />
      </Tabs>

      {currentTab === 0 && (
        <Box>
          <Typography variant="h5" gutterBottom>
            Chaos Engineering Scenarios
          </Typography>
          <Typography variant="body1" color="text.secondary" mb={3}>
            Select a pre-configured scenario to quickly apply failure injection patterns across all services.
          </Typography>
          
          <Grid container spacing={2}>
            {scenarios.map((scenario) => (
              <Grid item xs={12} md={6} lg={4} key={scenario.name}>
                <Card 
                  sx={{ 
                    cursor: 'pointer',
                    border: activeScenario === scenario.name ? 2 : 1,
                    borderColor: activeScenario === scenario.name ? 'primary.main' : 'divider'
                  }}
                  onClick={() => applyScenario(scenario)}
                >
                  <CardContent>
                    <Typography variant="h6" gutterBottom>
                      {scenario.name}
                    </Typography>
                    <Typography variant="body2" color="text.secondary" mb={2}>
                      {scenario.description}
                    </Typography>
                    <Box display="flex" gap={1} flexWrap="wrap">
                      <Chip 
                        icon={<SpeedIcon />}
                        label={`${(scenario.config.latencyProbability * 100)}% Latency`}
                        size="small"
                        variant="outlined"
                      />
                      <Chip 
                        icon={<ErrorIcon />}
                        label={`${(scenario.config.errorProbability * 100)}% Errors`}
                        size="small"
                        variant="outlined"
                        color="error"
                      />
                    </Box>
                  </CardContent>
                </Card>
              </Grid>
            ))}
          </Grid>
        </Box>
      )}

      {currentTab === 1 && (
        <Box>
          <Typography variant="h5" gutterBottom>
            Individual Service Configuration
          </Typography>
          <Typography variant="body1" color="text.secondary" mb={3}>
            Fine-tune failure injection settings for each service independently.
          </Typography>
          
          {Object.entries(services).map(([serviceKey, service]) => (
            <ServiceConfigCard key={serviceKey} serviceKey={serviceKey} service={service} />
          ))}
        </Box>
      )}

      {currentTab === 2 && (
        <Box>
          <Typography variant="h5" gutterBottom>
            Global Configuration
          </Typography>
          <Typography variant="body1" color="text.secondary" mb={3}>
            Apply consistent failure injection settings across all services.
          </Typography>

          <Card>
            <CardContent>
              <Grid container spacing={4}>
                <Grid item xs={12}>
                  <FormControlLabel
                    control={
                      <Switch
                        checked={globalConfig.enabled}
                        onChange={(e) => setGlobalConfig({ ...globalConfig, enabled: e.target.checked })}
                      />
                    }
                    label="Enable Failure Injection Globally"
                  />
                </Grid>

                <Grid item xs={12} md={6}>
                  <Typography variant="h6" gutterBottom>
                    Latency Configuration
                  </Typography>
                  <Box sx={{ px: 2 }}>
                    <Typography variant="body2" color="text.secondary" gutterBottom>
                      Probability: {(globalConfig.latencyProbability * 100).toFixed(1)}%
                    </Typography>
                    <Slider
                      value={globalConfig.latencyProbability * 100}
                      onChange={(e, value) => setGlobalConfig({ 
                        ...globalConfig, 
                        latencyProbability: value / 100 
                      })}
                      min={0}
                      max={50}
                      step={1}
                      marks={[
                        { value: 0, label: '0%' },
                        { value: 10, label: '10%' },
                        { value: 25, label: '25%' },
                        { value: 50, label: '50%' }
                      ]}
                      valueLabelDisplay="auto"
                      valueLabelFormat={(value) => `${value}%`}
                    />
                    
                    <Box display="flex" gap={2} mt={2}>
                      <TextField
                        label="Min Latency (ms)"
                        type="number"
                        value={globalConfig.minLatency}
                        onChange={(e) => setGlobalConfig({ 
                          ...globalConfig, 
                          minLatency: parseInt(e.target.value) || 0 
                        })}
                        size="small"
                      />
                      <TextField
                        label="Max Latency (ms)"
                        type="number"
                        value={globalConfig.maxLatency}
                        onChange={(e) => setGlobalConfig({ 
                          ...globalConfig, 
                          maxLatency: parseInt(e.target.value) || 1000 
                        })}
                        size="small"
                      />
                    </Box>
                  </Box>
                </Grid>

                <Grid item xs={12} md={6}>
                  <Typography variant="h6" gutterBottom>
                    Error Configuration
                  </Typography>
                  <Box sx={{ px: 2 }}>
                    <Typography variant="body2" color="text.secondary" gutterBottom>
                      Probability: {(globalConfig.errorProbability * 100).toFixed(1)}%
                    </Typography>
                    <Slider
                      value={globalConfig.errorProbability * 100}
                      onChange={(e, value) => setGlobalConfig({ 
                        ...globalConfig, 
                        errorProbability: value / 100 
                      })}
                      min={0}
                      max={30}
                      step={1}
                      marks={[
                        { value: 0, label: '0%' },
                        { value: 5, label: '5%' },
                        { value: 15, label: '15%' },
                        { value: 30, label: '30%' }
                      ]}
                      valueLabelDisplay="auto"
                      valueLabelFormat={(value) => `${value}%`}
                    />
                  </Box>
                </Grid>

                <Grid item xs={12}>
                  <Button
                    variant="contained"
                    size="large"
                    onClick={applyGlobalConfiguration}
                    disabled={loading}
                    fullWidth
                  >
                    Apply Global Configuration to All Services
                  </Button>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        </Box>
      )}
    </Box>
  );
};

export default FailureInjectionControl;