import React, { useState, useEffect, useRef } from 'react';
import './TrafficGenerator.css';
import api from '../services/api';
import { telemetry } from '../services/telemetry';

const TrafficGenerator = ({ onNotification }) => {
  const [isRunning, setIsRunning] = useState(false);
  const [intensity, setIntensity] = useState(50);
  const [patterns, setPatterns] = useState([]);
  const [stats, setStats] = useState({
    totalRequests: 0,
    successfulRequests: 0,
    failedRequests: 0,
    averageResponseTime: 0
  });
  
  const intervalRef = useRef(null);
  const requestTimesRef = useRef([]);

  // Traffic patterns
  const trafficPatterns = [
    { id: 'normal', name: 'Normal Traffic', description: 'Steady baseline traffic', requestsPerMin: 10 },
    { id: 'spike', name: 'Traffic Spike', description: 'Sudden increase in traffic', requestsPerMin: 50 },
    { id: 'gradual', name: 'Gradual Increase', description: 'Slowly increasing traffic', requestsPerMin: 20 },
    { id: 'random', name: 'Random Pattern', description: 'Random traffic bursts', requestsPerMin: 15 },
    { id: 'stress', name: 'Stress Test', description: 'High volume stress testing', requestsPerMin: 100 }
  ];

  // Sample customer IDs and product data
  const sampleCustomers = ['customer-a', 'customer-b', 'customer-c', 'customer-d', 'customer-e'];
  const sampleProducts = [
    { id: 1, price: 19.99 },
    { id: 2, price: 29.99 },
    { id: 3, price: 39.99 },
    { id: 4, price: 49.99 },
    { id: 5, price: 59.99 }
  ];

  useEffect(() => {
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, []);

  const generateOrder = async () => {
    const startTime = Date.now();
    try {
      // Random customer and product
      const customerId = sampleCustomers[Math.floor(Math.random() * sampleCustomers.length)];
      const product = sampleProducts[Math.floor(Math.random() * sampleProducts.length)];
      const quantity = Math.floor(Math.random() * 3) + 1;

      const order = {
        customerId: `${customerId}-${Date.now()}`,
        productId: product.id,
        quantity: quantity,
        unitPrice: product.price
      };

      await api.createOrder(order);
      
      const responseTime = Date.now() - startTime;
      requestTimesRef.current.push(responseTime);
      if (requestTimesRef.current.length > 100) {
        requestTimesRef.current.shift();
      }

      setStats(prev => ({
        totalRequests: prev.totalRequests + 1,
        successfulRequests: prev.successfulRequests + 1,
        failedRequests: prev.failedRequests,
        averageResponseTime: requestTimesRef.current.reduce((a, b) => a + b, 0) / requestTimesRef.current.length
      }));

      // Track in Application Insights
      telemetry.trackEvent('SyntheticOrderCreated', {
        customerId,
        productId: product.id,
        quantity,
        responseTime
      });

    } catch (error) {
      const responseTime = Date.now() - startTime;
      setStats(prev => ({
        totalRequests: prev.totalRequests + 1,
        successfulRequests: prev.successfulRequests,
        failedRequests: prev.failedRequests + 1,
        averageResponseTime: prev.averageResponseTime
      }));

      telemetry.trackException(error, {
        component: 'TrafficGenerator',
        operation: 'generateOrder'
      });
      
      console.error('Failed to create order:', error);
    }
  };

  const startTraffic = async () => {
    if (patterns.length === 0) {
      onNotification?.('Please select at least one traffic pattern', 'warning');
      return;
    }

    setIsRunning(true);
    onNotification?.('Traffic generation started', 'success');

    // Calculate total requests per minute based on selected patterns and intensity
    const totalRequestsPerMin = patterns.reduce((sum, patternId) => {
      const pattern = trafficPatterns.find(p => p.id === patternId);
      return sum + (pattern?.requestsPerMin || 10);
    }, 0);

    // Adjust by intensity (intensity is 1-100, use as percentage)
    const adjustedRequestsPerMin = Math.max(1, Math.floor((totalRequestsPerMin * intensity) / 100));
    const intervalMs = Math.max(100, Math.floor(60000 / adjustedRequestsPerMin)); // Minimum 100ms between requests

    console.log(`Starting traffic: ${adjustedRequestsPerMin} requests/min (every ${intervalMs}ms)`);

    // Start generating traffic
    intervalRef.current = setInterval(() => {
      generateOrder();
    }, intervalMs);

    telemetry.trackEvent('TrafficGenerationStarted', {
      intensity,
      patterns: patterns.join(','),
      requestsPerMin: adjustedRequestsPerMin
    });
  };

  const stopTraffic = () => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    setIsRunning(false);
    onNotification?.('Traffic generation stopped', 'info');

    telemetry.trackEvent('TrafficGenerationStopped', {
      totalRequests: stats.totalRequests,
      successfulRequests: stats.successfulRequests,
      failedRequests: stats.failedRequests
    });
  };


  const togglePattern = (patternId) => {
    setPatterns(prev => 
      prev.includes(patternId) 
        ? prev.filter(p => p !== patternId)
        : [...prev, patternId]
    );
  };

  const successRate = stats.totalRequests > 0 
    ? ((stats.successfulRequests / stats.totalRequests) * 100).toFixed(1)
    : 0;

  return (
    <div className="traffic-generator">
      <div className="traffic-header">
        <h2>🚦 Synthetic Traffic Generator</h2>
        <p>Generate realistic traffic patterns for OpenTelemetry demo</p>
      </div>

      <div className="traffic-controls">
        <div className="control-group">
          <label htmlFor="intensity">Traffic Intensity</label>
          <input
            id="intensity"
            type="range"
            min="1"
            max="100"
            value={intensity}
            onChange={(e) => setIntensity(parseInt(e.target.value))}
            disabled={isRunning}
          />
          <span className="intensity-value">{intensity}%</span>
        </div>

        <div className="control-group">
          <label>Traffic Patterns</label>
          <div className="pattern-checkboxes">
            {trafficPatterns.map(pattern => (
              <label key={pattern.id} className="pattern-checkbox">
                <input
                  type="checkbox"
                  checked={patterns.includes(pattern.id)}
                  onChange={() => togglePattern(pattern.id)}
                  disabled={isRunning}
                />
                <span className="pattern-info">
                  <strong>{pattern.name}</strong> ({pattern.requestsPerMin} req/min)
                  <br />
                  <small>{pattern.description}</small>
                </span>
              </label>
            ))}
          </div>
        </div>

        <div className="control-actions">
          {!isRunning ? (
            <button 
              className="btn-start" 
              onClick={startTraffic}
              disabled={patterns.length === 0}
            >
              🚀 Start Traffic Generation
            </button>
          ) : (
            <button className="btn-stop" onClick={stopTraffic}>
              ⏹️ Stop Traffic Generation
            </button>
          )}
        </div>
      </div>

      {isRunning && (
        <div className="traffic-stats">
          <h3>📊 Live Traffic Statistics</h3>
          <div className="stats-grid">
            <div className="stat-card">
              <div className="stat-value">{stats.totalRequests.toLocaleString()}</div>
              <div className="stat-label">Total Requests</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{successRate}%</div>
              <div className="stat-label">Success Rate</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{Math.round(stats.averageResponseTime)}ms</div>
              <div className="stat-label">Avg Response Time</div>
            </div>
            <div className="stat-card success">
              <div className="stat-value">{stats.successfulRequests}</div>
              <div className="stat-label">Successful</div>
            </div>
            <div className="stat-card error">
              <div className="stat-value">{stats.failedRequests}</div>
              <div className="stat-label">Failed</div>
            </div>
          </div>
        </div>
      )}

      <div className="traffic-info">
        <h3>ℹ️ About Synthetic Traffic</h3>
        <p>
          This tool generates real orders to demonstrate OpenTelemetry 
          observability features including:
        </p>
        <ul>
          <li>Distributed tracing across microservices (API Gateway → Order Service → Payment Service)</li>
          <li>Metrics collection and visualization in Azure Monitor</li>
          <li>Real-time monitoring of success rates and response times</li>
          <li>Performance monitoring and alerting</li>
          <li>End-to-end transaction tracking with Application Insights</li>
        </ul>
        <p>
          <strong>Note:</strong> Traffic generation creates real orders in the system. 
          Each pattern has a base rate (requests/min) that is scaled by the intensity slider.
        </p>
      </div>
    </div>
  );
};

export default TrafficGenerator;