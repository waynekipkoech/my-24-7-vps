const express = require('express');
const app = express();
const PORT = 3000;

app.get('/', (req, res) => {
  res.json({ status: 'running', message: 'VPS is alive', timestamp: new Date().toISOString() });
});

app.get('/health', (req, res) => {
  const uptime = process.uptime();
  const hours = Math.floor(uptime / 3600);
  const mins = Math.floor((uptime % 3600) / 60);
  const secs = Math.floor(uptime % 60);
  res.json({ status: 'healthy', uptime: `${hours}h ${mins}m ${secs}s`, pid: process.pid });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
