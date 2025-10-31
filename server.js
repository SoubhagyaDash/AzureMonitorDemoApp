const express = require('express');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

// Serve static files from the React app build directory
// Check multiple possible locations for the build directory
let buildPath;
if (require('fs').existsSync(path.join(__dirname, 'build'))) {
  buildPath = path.join(__dirname, 'build');
} else if (require('fs').existsSync(path.join(__dirname, 'services/frontend/build'))) {
  buildPath = path.join(__dirname, 'services/frontend/build');
} else {
  console.error('Build directory not found!');
  process.exit(1);
}

console.log('Serving static files from:', buildPath);
app.use(express.static(buildPath));

// API routes for health checks
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'otel-demo-frontend',
    timestamp: new Date().toISOString() 
  });
});

// Handle React routing, return all requests to React app
app.get('*', (req, res) => {
  res.sendFile(path.join(buildPath, 'index.html'));
});

app.listen(port, () => {
  console.log(`OpenTelemetry Demo Frontend server running on port ${port}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

module.exports = app;