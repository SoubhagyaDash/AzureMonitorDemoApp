// Application Insights disabled - stub implementation
console.log('Application Insights telemetry disabled');

const reactPlugin = { 
  identifier: 'ReactPlugin',
  setGlobalContext: () => {}
};
const clickAnalyticsPlugin = { identifier: 'ClickAnalyticsPlugin' };

// Stub appInsights object with all required methods
const appInsights = {
  loadAppInsights: () => {},
  trackPageView: () => {},
  trackEvent: () => {},
  trackDependency: () => {},
  trackException: () => {},
  trackMetric: () => {},
  trackTrace: () => {},
  setAuthenticatedUserContext: () => {},
  addTelemetryInitializer: () => {}
};

// Custom telemetry helper functions
export const telemetry = {
  // Track page views
  trackPageView: (name, url, properties = {}) => {
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
    const context = appInsights.getPlugin('AppInsightsChannelPlugin')?.core?.getTraceId();
    return {
      'Request-Id': context || '',
      'Request-Context': `appId=${appInsights.appId || ''}`
    };
  },

  // Flush telemetry immediately
  flush: () => {
    appInsights.flush();
  }
};

export { appInsights, reactPlugin };
export default appInsights;