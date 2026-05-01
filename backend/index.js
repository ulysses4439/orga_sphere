const express = require('express');
const sql = require('mssql');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const config = {
  user: process.env.SQL_USER,
  password: process.env.SQL_PASSWORD,
  server: process.env.SQL_SERVER,
  database: process.env.SQL_DATABASE,
  options: {
    encrypt: true,
    trustServerCertificate: false,
  },
};

let pool;

async function getPool() {
  if (!pool) {
    pool = await sql.connect(config);
  }
  return pool;
}

function nextDate(current, frequency, interval) {
  const d = new Date(current);
  switch (frequency) {
    case 'daily':   d.setDate(d.getDate() + interval); break;
    case 'weekly':  d.setDate(d.getDate() + 7 * interval); break;
    case 'monthly': d.setMonth(d.getMonth() + interval); break;
    case 'yearly':  d.setFullYear(d.getFullYear() + interval); break;
  }
  return d;
}

app.get('/', (req, res) => {
  res.send('OrgaSphere API');
});

// --- Domains ---

app.get('/domains', async (req, res) => {
  try {
    const p = await getPool();
    const result = await p.request().query('SELECT * FROM TaskDomain');
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/domains', async (req, res) => {
  const { name, description } = req.body;
  const id = uuidv4();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',          sql.NVarChar, id)
      .input('name',        sql.NVarChar, name)
      .input('description', sql.NVarChar, description)
      .query('INSERT INTO TaskDomain (id, name, description) OUTPUT INSERTED.* VALUES (@id, @name, @description)');
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- Templates ---

app.get('/templates', async (req, res) => {
  try {
    const p = await getPool();
    const result = await p.request().query('SELECT * FROM TaskTemplate');
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/templates', async (req, res) => {
  const { domainId, title, description, startDate, dueDate, recurrenceFrequency, recurrenceInterval } = req.body;
  const id = uuidv4();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',                  sql.NVarChar, id)
      .input('domainId',            sql.NVarChar, domainId)
      .input('title',               sql.NVarChar, title)
      .input('description',         sql.NVarChar, description)
      .input('startDate',           sql.DateTime2, new Date(startDate))
      .input('dueDate',             sql.DateTime2, new Date(dueDate))
      .input('recurrenceFrequency', sql.NVarChar, recurrenceFrequency || 'none')
      .input('recurrenceInterval',  sql.Int,      recurrenceInterval || 1)
      .query(`INSERT INTO TaskTemplate
                (id, domainId, title, description, startDate, dueDate, recurrenceFrequency, recurrenceInterval)
              OUTPUT INSERTED.*
              VALUES (@id, @domainId, @title, @description, @startDate, @dueDate, @recurrenceFrequency, @recurrenceInterval)`);
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- Instances ---

app.get('/instances', async (req, res) => {
  try {
    const p = await getPool();
    const result = await p.request().query("SELECT * FROM TaskInstance WHERE status != 'done'");
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/instances/archived', async (req, res) => {
  try {
    const p = await getPool();
    const result = await p.request().query("SELECT * FROM TaskInstance WHERE status = 'done'");
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/instances', async (req, res) => {
  const { templateId, domainId, title, description, startDate, dueDate } = req.body;
  const id = uuidv4();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',          sql.NVarChar,  id)
      .input('templateId',  sql.NVarChar,  templateId)
      .input('domainId',    sql.NVarChar,  domainId)
      .input('title',       sql.NVarChar,  title)
      .input('description', sql.NVarChar,  description)
      .input('startDate',   sql.DateTime2, new Date(startDate))
      .input('dueDate',     sql.DateTime2, new Date(dueDate))
      .query(`INSERT INTO TaskInstance
                (id, templateId, domainId, title, description, startDate, dueDate, status)
              OUTPUT INSERTED.*
              VALUES (@id, @templateId, @domainId, @title, @description, @startDate, @dueDate, 'open')`);
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Mark instance as done; auto-creates next occurrence for recurring tasks
app.patch('/instances/:id/done', async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();

    const instResult = await p.request()
      .input('id', sql.NVarChar, id)
      .query('SELECT * FROM TaskInstance WHERE id = @id');

    if (instResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Instance not found' });
    }
    const instance = instResult.recordset[0];

    const now = new Date();
    await p.request()
      .input('id',          sql.NVarChar,  id)
      .input('completedAt', sql.DateTime2, now)
      .query("UPDATE TaskInstance SET status = 'done', completedAt = @completedAt WHERE id = @id");

    const tmplResult = await p.request()
      .input('templateId', sql.NVarChar, instance.templateId)
      .query('SELECT * FROM TaskTemplate WHERE id = @templateId');

    if (tmplResult.recordset.length > 0) {
      const template = tmplResult.recordset[0];
      if (template.recurrenceFrequency !== 'none') {
        const nextStart = nextDate(instance.startDate, template.recurrenceFrequency, template.recurrenceInterval);
        const nextDue   = nextDate(instance.dueDate,   template.recurrenceFrequency, template.recurrenceInterval);
        const nextId    = uuidv4();
        await p.request()
          .input('id',          sql.NVarChar,  nextId)
          .input('templateId',  sql.NVarChar,  instance.templateId)
          .input('domainId',    sql.NVarChar,  instance.domainId)
          .input('title',       sql.NVarChar,  instance.title)
          .input('description', sql.NVarChar,  instance.description)
          .input('startDate',   sql.DateTime2, nextStart)
          .input('dueDate',     sql.DateTime2, nextDue)
          .query(`INSERT INTO TaskInstance
                    (id, templateId, domainId, title, description, startDate, dueDate, status)
                  VALUES (@id, @templateId, @domainId, @title, @description, @startDate, @dueDate, 'open')`);
      }
    }

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- Logs ---

app.get('/logs/:instanceId', async (req, res) => {
  const { instanceId } = req.params;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('instanceId', sql.NVarChar, instanceId)
      .query('SELECT * FROM TaskLogEntry WHERE instanceId = @instanceId ORDER BY timestamp DESC');
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/logs', async (req, res) => {
  const { instanceId, user, text } = req.body;
  const id  = uuidv4();
  const now = new Date();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',         sql.NVarChar,  id)
      .input('instanceId', sql.NVarChar,  instanceId)
      .input('user',       sql.NVarChar,  user)
      .input('text',       sql.NVarChar,  text)
      .input('timestamp',  sql.DateTime2, now)
      .query(`INSERT INTO TaskLogEntry (id, instanceId, [user], [text], timestamp)
              OUTPUT INSERTED.*
              VALUES (@id, @instanceId, @user, @text, @timestamp)`);
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
