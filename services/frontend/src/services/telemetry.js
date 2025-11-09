// Application Insights initialization
import { ApplicationInsights } from '@microsoft/applicationinsights-web';
import { ReactPlugin } from '@microsoft/applicationinsights-react-js';
import { ClickAnalyticsPlugin } from '@microsoft/applicationinsights-clickanalytics-js';

// Initialize React Plugin for React-specific telemetry
const reactPlugin = new ReactPlugin();

// Initialize Click Analytics Plugin for automatic click tracking
const clickAnalyticsPlugin = new ClickAnalyticsPlugin();

// Create Application Insights instance (will be initialized after fetching config)
let appInsights = null;
let isInitialized = false;

// Initialize Application Insights with connection string
const initializeAppInsights = (connectionString) => {
  if (isInitialized || !connectionString) {
    return;
  }

  appInsights = new ApplicationInsights({
    config: {
      connectionString: connectionString,
      enableAutoRouteTracking: true, // Automatically track route changes
      enableRequestHeaderTracking: true,
      enableResponseHeaderTracking: true,
      enableCorsCorrelation: true, // Enable cross-origin correlation
      enableUnhandledPromiseRejectionTracking: true,
      disableFetchTracking: false,
      disableAjaxTracking: false,
      autoTrackPageVisitTime: true,
      extensions: [reactPlugin, clickAnalyticsPlugin],
      extensionConfig: {
        [reactPlugin.identifier]: {
          debug: false
        },
        [clickAnalyticsPlugin.identifier]: {
          autoCapture: true,
          dataTags: {
            useDefaultContentNameOrId: true
          }
        }
      }
    }
  });

  appInsights.loadAppInsights();
  appInsights.trackPageView(); // Track initial page view
  isInitialized = true;
  console.log('Application Insights initialized successfully');
};

// Fetch configuration from server and initialize App Insights
const fetchConfigAndInitialize = async () => {
  try {
    // First try to get from build-time environment variable (for local dev)
    const buildTimeConnectionString = process.env.REACT_APP_APPLICATIONINSIGHTS_CONNECTION_STRING;
    
    if (buildTimeConnectionString) {
      initializeAppInsights(buildTimeConnectionString);
      return;
    }

    // Otherwise fetch from server (for production App Service)
    const response = await fetch('/api/config');
    if (response.ok) {
      const config = await response.json();
      if (config.applicationInsights?.connectionString) {
        initializeAppInsights(config.applicationInsights.connectionString);
      } else {
        console.warn('Application Insights connection string not found in server config');
      }
    } else {
      console.warn('Failed to fetch runtime configuration from server');
    }
  } catch (error) {
    console.error('Error fetching App Insights configuration:', error);
  }
};

// Start initialization immediately
fetchConfigAndInitialize();

// Custom telemetry helper functions
export const telemetry = {
  // Track page views
  trackPageView: (name, url, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackPageView({
      name,
      uri: url,
      properties: {
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      }
    });
  },

  // Track custom events
  trackEvent: (name, properties = {}, measurements = {}) => {
    if (!appInsights) return;
    appInsights.trackEvent({
      name,
      properties: {
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      },
      measurements
    });
  },

  // Track user actions
  trackUserAction: (action, target, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackEvent({
      name: 'UserAction',
      properties: {
        action,
        target,
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      }
    });
  },

  // Track API calls
  trackApiCall: (method, url, duration, statusCode, success, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackDependency({
      target: url,
      name: `${method} ${url}`,
      data: url,
      duration,
      success,
      resultCode: statusCode,
      type: 'Ajax',
      properties: {
        ...properties,
        component: 'react-frontend'
      }
    });
  },

  // Track exceptions
  trackException: (error, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackException({
      exception: error,
      properties: {
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      }
    });
  },

  // Track metrics
  trackMetric: (name, value, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackMetric({
      name,
      average: value,
      properties: {
        ...properties,
        component: 'react-frontend'
      }
    });
  },

  // Track business events
  trackBusinessEvent: (eventType, eventData = {}) => {
    if (!appInsights) return;
    appInsights.trackEvent({
      name: `Business_${eventType}`,
      properties: {
        eventType,
        ...eventData,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      }
    });
  },

  // Track performance metrics
  trackPerformance: (operation, duration, success = true, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackMetric({
      name: `Performance_${operation}`,
      average: duration,
      properties: {
        operation,
        success: success.toString(),
        ...properties,
        component: 'react-frontend'
      }
    });
  },

  // Set user context
  setUser: (userId, authenticatedUserId = null, accountId = null) => {
    if (!appInsights) return;
    appInsights.setAuthenticatedUserContext(
      authenticatedUserId || userId,
      accountId,
      true
    );
    
    appInsights.addTelemetryInitializer((envelope) => {
      if (!envelope.tags) envelope.tags = {};
      envelope.tags['ai.user.id'] = userId;
      if (accountId) envelope.tags['ai.user.accountId'] = accountId;
    });
  },

  // Track feature usage
  trackFeatureUsage: (featureName, used, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackEvent({
      name: 'FeatureUsage',
      properties: {
        featureName,
        used: used.toString(),
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      }
    });
  },

  // Track form interactions
  trackFormInteraction: (formName, action, fieldName = null, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackEvent({
      name: 'FormInteraction',
      properties: {
        formName,
        action, // 'start', 'complete', 'abandon', 'error'
        fieldName,
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      }
    });
  },

  // Track eCommerce events
  trackOrderEvent: (action, orderId, customerId, amount = null, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackEvent({
      name: `Order_${action}`,
      properties: {
        orderId,
        customerId,
        amount: amount?.toString(),
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      },
      measurements: amount ? { orderAmount: amount } : {}
    });
  },

  // Track traffic generation
  trackTrafficGeneration: (type, requests, duration, successRate, properties = {}) => {
    if (!appInsights) return;
    appInsights.trackEvent({
      name: 'TrafficGeneration',
      properties: {
        type,
        ...properties,
        component: 'react-frontend',
        timestamp: new Date().toISOString()
      },
      measurements: {
        requests,
        duration,
        successRate
      }
    });
  },

  // Get correlation context for API calls
  getCorrelationContext: () => {
    if (!appInsights) {
      return {
        'Request-Id': '',
        'Request-Context': ''
      };
    }
    
    try {
      const context = appInsights.context;
      const operationId = context?.telemetryTrace?.traceID;
      const appId = appInsights.appInsights?.config?.instrumentationKey;
      
      return {
        'Request-Id': operationId || '',
        'Request-Context': appId ? `appId=${appId}` : ''
      };
    } catch (error) {
      console.warn('Failed to get correlation context:', error);
      return {
        'Request-Id': '',
        'Request-Context': ''
      };
    }
  },

  // Flush telemetry immediately
  flush: () => {
    if (appInsights?.appInsights) {
      appInsights.flush();
    }
  }
};

export { appInsights, reactPlugin };
export default appInsights;