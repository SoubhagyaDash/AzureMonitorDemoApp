import React, { useState, useEffect } from 'react';
import { Routes, Route, Link, useLocation, useNavigate } from 'react-router-dom';
import {
  AppBar,
  Toolbar,
  Typography,
  Container,
  Tabs,
  Tab,
  Box,
  Alert,
  Snackbar
} from '@mui/material';
import {
  Dashboard as DashboardIcon,
  Traffic as TrafficIcon,
  Settings as SettingsIcon,
  Timeline as TimelineIcon,
  BugReport as BugReportIcon,
  ShoppingCart as ShoppingCartIcon
} from '@mui/icons-material';

// Import telemetry
import { reactPlugin, telemetry } from './services/telemetry';

// Import components
import Dashboard from './components/Dashboard';
import TrafficGenerator from './components/TrafficGenerator';
import ServiceHealth from './components/ServiceHealth';
import FailureInjectionControl from './components/FailureInjectionControl';
import Metrics from './components/Metrics';
import ECommerceStore from './components/ECommerceStore';

// Set up Application Insights React plugin with router history
function App() {
  const location = useLocation();
  const navigate = useNavigate();
  const [currentTab, setCurrentTab] = useState(0);
  const [notification, setNotification] = useState({ open: false, message: '', severity: 'info' });

  // Configure Application Insights with router history
  useEffect(() => {
    if (reactPlugin && typeof reactPlugin.setGlobalContext === 'function') {
      reactPlugin.setGlobalContext({
        history: { location, navigate }
      });
    }
  }, [location, navigate]);

  const tabs = [
    { label: 'Dashboard', icon: <DashboardIcon />, path: '/' },
    { label: 'eCommerce Store', icon: <ShoppingCartIcon />, path: '/store' },
    { label: 'Traffic Generator', icon: <TrafficIcon />, path: '/traffic' },
    { label: 'Service Health', icon: <TimelineIcon />, path: '/health' },
    { label: 'Failure Injection', icon: <BugReportIcon />, path: '/failures' },
    { label: 'Metrics', icon: <SettingsIcon />, path: '/metrics' }
  ];

  useEffect(() => {
    const tabIndex = tabs.findIndex(tab => tab.path === location.pathname);
    setCurrentTab(tabIndex !== -1 ? tabIndex : 0);
    
    // Track page views
    telemetry.trackPageView(tabs[tabIndex]?.label || 'Unknown', location.pathname, {
      tabIndex: tabIndex.toString(),
      userAgent: navigator.userAgent
    });
  }, [location.pathname]);

  const handleTabChange = (event, newValue) => {
    setCurrentTab(newValue);
    telemetry.trackUserAction('TabChange', tabs[newValue]?.label, {
      fromTab: tabs[currentTab]?.label,
      toTab: tabs[newValue]?.label
    });
  };

  const showNotification = (message, severity = 'info') => {
    setNotification({ open: true, message, severity });
    
    // Track notification display
    telemetry.trackEvent('NotificationShown', {
      message: message.substring(0, 100), // Limit message length
      severity
    });
  };

  const handleCloseNotification = () => {
    setNotification({ ...notification, open: false });
  };

  // Track application startup
  useEffect(() => {
    telemetry.trackEvent('ApplicationStartup', {
      userAgent: navigator.userAgent,
      screenResolution: `${window.screen.width}x${window.screen.height}`,
      language: navigator.language,
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone
    });
  }, []);

  return (
    <Box sx={{ flexGrow: 1 }}>
      <AppBar position="static" sx={{ backgroundColor: '#0078d4' }}>
        <Toolbar>
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            Azure Monitor OpenTelemetry Demo
          </Typography>
          <Typography variant="body2" sx={{ opacity: 0.8 }}>
            Microservices Observability Showcase
          </Typography>
        </Toolbar>
      </AppBar>

      <Container maxWidth="xl" sx={{ mt: 2 }}>
        <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 3 }}>
          <Tabs 
            value={currentTab} 
            onChange={handleTabChange}
            variant="scrollable"
            scrollButtons="auto"
          >
            {tabs.map((tab, index) => (
              <Tab
                key={index}
                icon={tab.icon}
                label={tab.label}
                component={Link}
                to={tab.path}
                sx={{ textTransform: 'none' }}
              />
            ))}
          </Tabs>
        </Box>

        <Routes>
          <Route 
            path="/" 
            element={<Dashboard onNotification={showNotification} />} 
          />
          <Route 
            path="/store" 
            element={<ECommerceStore onNotification={showNotification} />} 
          />
          <Route 
            path="/traffic" 
            element={<TrafficGenerator onNotification={showNotification} />} 
          />
          <Route 
            path="/health" 
            element={<ServiceHealth onNotification={showNotification} />} 
          />
          <Route 
            path="/failures" 
            element={<FailureInjectionControl onNotification={showNotification} />} 
          />
          <Route 
            path="/metrics" 
            element={<Metrics onNotification={showNotification} />} 
          />
        </Routes>
      </Container>

      <Snackbar
        open={notification.open}
        autoHideDuration={6000}
        onClose={handleCloseNotification}
      >
        <Alert
          onClose={handleCloseNotification}
          severity={notification.severity}
          sx={{ width: '100%' }}
        >
          {notification.message}
        </Alert>
      </Snackbar>
    </Box>
  );
}

export default App;