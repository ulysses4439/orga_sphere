const express = require('express');
const sql = require('mssql');
const cors = require('cors');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// SQL Server configuration
const config = {
  user: process.env.SQL_USER,
  password: process.env.SQL_PASSWORD,
  server: process.env.SQL_SERVER,
  database: process.env.SQL_DATABASE,
  options: {
    encrypt: true, // Use encryption
    trustServerCertificate: false, // Change to true for local dev / self-signed certs
  },
};

// Connect to SQL Server
sql.connect(config).then(() => {
  console.log('Connected to SQL Server');
}).catch(err => {
  console.error('Database connection failed:', err);
});

// Basic route
app.get('/', (req, res) => {
  res.send('OrgaSphere API');
});

// Domains routes
app.get('/domains', async (req, res) => {
  try {
    const result = await sql.query`SELECT * FROM TaskDomain`;
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/domains', async (req, res) => {
  const { name, description } = req.body;
  try {
    const result = await sql.query`INSERT INTO TaskDomain (name, description) OUTPUT INSERTED.* VALUES (${name}, ${description})`;
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Templates routes
app.get('/templates', async (req, res) => {
  try {
    const result = await sql.query`SELECT * FROM TaskTemplate`;
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/templates', async (req, res) => {
  const { title, description, recurrence, domainId } = req.body;
  try {
    const result = await sql.query`INSERT INTO TaskTemplate (title, description, recurrence, domainId) OUTPUT INSERTED.* VALUES (${title}, ${description}, ${recurrence}, ${domainId})`;
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Instances routes
app.get('/instances', async (req, res) => {
  try {
    const result = await sql.query`SELECT * FROM TaskInstance WHERE isArchived = 0`;
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/instances', async (req, res) => {
  const { templateId, status, dueDate } = req.body;
  try {
    const result = await sql.query`INSERT INTO TaskInstance (templateId, status, dueDate) OUTPUT INSERTED.* VALUES (${templateId}, ${status}, ${dueDate})`;
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Logs routes
app.get('/logs/:instanceId', async (req, res) => {
  const { instanceId } = req.params;
  try {
    const result = await sql.query`SELECT * FROM TaskLogEntry WHERE instanceId = ${instanceId}`;
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/logs', async (req, res) => {
  const { instanceId, user, text } = req.body;
  try {
    const result = await sql.query`INSERT INTO TaskLogEntry (instanceId, user, text) OUTPUT INSERTED.* VALUES (${instanceId}, ${user}, ${text})`;
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Start server
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});