import React, { useState, useEffect } from 'react';
import './TrafficGenerator.css';

const TrafficGenerator = () => {
  const [isRunning, setIsRunning] = useState(false);
  const [intensity, setIntensity] = useState(50);
  const [patterns, setPatterns] = useState([]);
  const [stats, setStats] = useState({
    totalRequests: 0,
    successRate: 0,
    averageResponseTime: 0,
    activeUsers: 0
  });

  // Traffic patterns
  const trafficPatterns = [
    { id: 'normal', name: 'Normal Traffic', description: 'Steady baseline traffic' },
    { id: 'spike', name: 'Traffic Spike', description: 'Sudden increase in traffic' },
    { id: 'gradual', name: 'Gradual Increase', description: 'Slowly increasing traffic' },
    { id: 'random', name: 'Random Pattern', description: 'Random traffic bursts' },
    { id: 'stress', name: 'Stress Test', description: 'High volume stress testing' }
  ];

  useEffect(() => {
    if (isRunning) {
      const interval = setInterval(() => {
        // Simulate traffic stats updates
        setStats(prev => ({
          totalRequests: prev.totalRequests + Math.floor(Math.random() * intensity / 10),
          successRate: 95 + Math.random() * 5,
          averageResponseTime: 100 + Math.random() * 200,
          activeUsers: Math.floor(intensity / 2) + Math.floor(Math.random() * 20)
        }));
      }, 1000);

      return () => clearInterval(interval);
    }
  }, [isRunning, intensity]);

  const startTraffic = async () => {
    try {
      const response = await fetch('/api/traffic/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ intensity, patterns })
      });
      
      if (response.ok) {
        setIsRunning(true);
      }
    } catch (error) {
      console.error('Failed to start traffic generation:', error);
    }
  };

  const stopTraffic = async () => {
    try {
      const response = await fetch('/api/traffic/stop', { method: 'POST' });
      if (response.ok) {
        setIsRunning(false);
      }
    } catch (error) {
      console.error('Failed to stop traffic generation:', error);
    }
  };

  const togglePattern = (patternId) => {
    setPatterns(prev => 
      prev.includes(patternId) 
        ? prev.filter(p => p !== patternId)
        : [...prev, patternId]
    );
  };

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
                  <strong>{pattern.name}</strong>
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
              <div className="stat-value">{stats.successRate.toFixed(1)}%</div>
              <div className="stat-label">Success Rate</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{stats.averageResponseTime.toFixed(0)}ms</div>
              <div className="stat-label">Avg Response Time</div>
            </div>
            <div className="stat-card">
              <div className="stat-value">{stats.activeUsers}</div>
              <div className="stat-label">Active Users</div>
            </div>
          </div>
        </div>
      )}

      <div className="traffic-info">
        <h3>ℹ️ About Synthetic Traffic</h3>
        <p>
          This tool generates realistic traffic patterns to demonstrate OpenTelemetry 
          observability features including:
        </p>
        <ul>
          <li>Distributed tracing across microservices</li>
          <li>Metrics collection and visualization</li>
          <li>Error injection and monitoring</li>
          <li>Performance monitoring and alerting</li>
        </ul>
      </div>
    </div>
  );
};

export default TrafficGenerator;