const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const port = process.env.PORT || 3000;

console.log('Starting OpenTelemetry Demo Frontend Server...');
console.log('Port:', port);
console.log('Working directory:', __dirname);
console.log('Files in working directory:', fs.readdirSync(__dirname));

// Serve static files from the React app build directory
// Check multiple possible locations for the build directory
let buildPath;
if (fs.existsSync(path.join(__dirname, 'build'))) {
  buildPath = path.join(__dirname, 'build');
} else if (fs.existsSync(path.join(__dirname, 'services/frontend/build'))) {
  buildPath = path.join(__dirname, 'services/frontend/build');
} else {
  console.error('Build directory not found!');
  console.error('Checked paths:');
  console.error('  -', path.join(__dirname, 'build'));
  console.error('  -', path.join(__dirname, 'services/frontend/build'));
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

// Test route to verify server is working
app.get('/test', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head><title>Server Test</title></head>
    <body>
      <h1>Express Server is Working!</h1>
      <p>Build path: ${buildPath}</p>
      <p>Port: ${port}</p>
      <p>Time: ${new Date().toISOString()}</p>
      <p>Files in build directory:</p>
      <ul>
        ${fs.readdirSync(buildPath).map(file => `<li>${file}</li>`).join('')}
      </ul>
    </body>
    </html>
  `);
});

// Handle React routing, return all requests to React app
app.get('*', (req, res) => {
  console.log('Serving request for:', req.path);
  res.sendFile(path.join(buildPath, 'index.html'));
});

app.listen(port, () => {
  console.log(`OpenTelemetry Demo Frontend server running on port ${port}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

module.exports = app;