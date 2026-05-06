const express = require('express');
const sql = require('mssql');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const nodemailer = require('nodemailer');
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
  if (!pool || !pool.connected) {
    pool = await sql.connect(config);
  }
  return pool;
}

sql.connect(config)
  .then(p => { pool = p; console.log('DB connection ready'); })
  .catch(err => console.error('Startup DB connect failed (will retry on first request):', err.message));

// -----------------------------------------------------------------------
// E-Mail
// -----------------------------------------------------------------------

const mailTransport = process.env.SMTP_HOST
  ? nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT || '587'),
      secure: process.env.SMTP_SECURE === 'true',
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    })
  : null;

async function sendReminderEmail(toAddresses, task, domainName) {
  if (!mailTransport) {
    console.log('SMTP not configured – skipping e-mail for task', task.id);
    return;
  }
  const dueStr = new Date(task.dueDate).toLocaleDateString('de-DE', {
    day: '2-digit', month: 'long', year: 'numeric',
  });
  const reminderStr = new Date(task.reminderAt).toLocaleString('de-DE', {
    day: '2-digit', month: 'long', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
  await mailTransport.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: toAddresses,
    subject: `⏰ Erinnerung: ${task.title}`,
    html: `
      <h2>Erinnerung für Sphere: ${task.title}</h2>
      <p><strong>Orbit:</strong> ${domainName}</p>
      <p><strong>Fällig am:</strong> ${dueStr}</p>
      <p><strong>Erinnerungszeit:</strong> ${reminderStr}</p>
      ${task.description ? `<p><strong>Beschreibung:</strong> ${task.description}</p>` : ''}
      <hr>
      <p style="color:#666;font-size:12px">OrgaSphere – Orbit-weite Erinnerung</p>
    `,
  });
}

// -----------------------------------------------------------------------
// Recurrence
// -----------------------------------------------------------------------

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

// Creates the next capsule for a recurring task if none exists yet.
// Returns the new task row or null if no capsule was created.
async function createNextCapsuleIfNeeded(p, task) {
  if (task.recurrenceFrequency === 'none') return null;

  const existing = await p.request()
    .input('prevId', sql.NVarChar, task.id)
    .query('SELECT id FROM Task WHERE previousTaskId = @prevId');

  if (existing.recordset.length > 0) return null;

  const nextStart = nextDate(task.startDate, task.recurrenceFrequency, task.recurrenceInterval);
  const nextDue   = nextDate(task.dueDate,   task.recurrenceFrequency, task.recurrenceInterval);
  const nextId    = uuidv4();

  const result = await p.request()
    .input('id',                   sql.NVarChar,  nextId)
    .input('domainId',             sql.NVarChar,  task.domainId)
    .input('title',                sql.NVarChar,  task.title)
    .input('description',          sql.NVarChar,  task.description)
    .input('startDate',            sql.DateTime2, nextStart)
    .input('dueDate',              sql.DateTime2, nextDue)
    .input('recurrenceFrequency',  sql.NVarChar,  task.recurrenceFrequency)
    .input('recurrenceInterval',   sql.Int,       task.recurrenceInterval)
    .input('previousTaskId',       sql.NVarChar,  task.id)
    .query(`INSERT INTO Task
              (id, domainId, title, description, startDate, dueDate,
               recurrenceFrequency, recurrenceInterval, status, previousTaskId)
            OUTPUT INSERTED.*
            VALUES (@id, @domainId, @title, @description, @startDate, @dueDate,
                    @recurrenceFrequency, @recurrenceInterval, 'open', @previousTaskId)`);

  return result.recordset[0];
}

// -----------------------------------------------------------------------
// Health
// -----------------------------------------------------------------------

app.get('/', (req, res) => res.send('OrgaSphere API'));

app.get('/health', async (req, res) => {
  try {
    const p = await getPool();
    await p.request().query('SELECT 1');
    res.json({ status: 'ok', db: 'connected' });
  } catch (err) {
    res.status(503).json({ status: 'error', db: err.message });
  }
});

// -----------------------------------------------------------------------
// Domains
// -----------------------------------------------------------------------

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
  const { name, description, color, notificationEmails } = req.body;
  const id = uuidv4();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',                 sql.NVarChar, id)
      .input('name',               sql.NVarChar, name)
      .input('description',        sql.NVarChar, description)
      .input('color',              sql.NVarChar, color || '#F5F5F5')
      .input('notificationEmails', sql.NVarChar, notificationEmails || null)
      .query(`INSERT INTO TaskDomain (id, name, description, color, notificationEmails)
              OUTPUT INSERTED.*
              VALUES (@id, @name, @description, @color, @notificationEmails)`);
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/domains/:id', async (req, res) => {
  const { id } = req.params;
  const { notificationEmails } = req.body;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',                 sql.NVarChar, id)
      .input('notificationEmails', sql.NVarChar, notificationEmails ?? null)
      .query('UPDATE TaskDomain SET notificationEmails = @notificationEmails WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Domain not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Tasks
// -----------------------------------------------------------------------

app.get('/tasks', async (req, res) => {
  try {
    const p = await getPool();
    const result = await p.request().query("SELECT * FROM Task WHERE status != 'done' ORDER BY dueDate ASC");
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/tasks/archived', async (req, res) => {
  try {
    const p = await getPool();
    const result = await p.request().query("SELECT * FROM Task WHERE status = 'done' ORDER BY completedAt DESC");
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/tasks', async (req, res) => {
  const { domainId, title, description, startDate, dueDate, recurrenceFrequency, recurrenceInterval } = req.body;
  const id = uuidv4();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',                  sql.NVarChar,  id)
      .input('domainId',            sql.NVarChar,  domainId)
      .input('title',               sql.NVarChar,  title)
      .input('description',         sql.NVarChar,  description || '')
      .input('startDate',           sql.DateTime2, new Date(startDate))
      .input('dueDate',             sql.DateTime2, new Date(dueDate))
      .input('recurrenceFrequency', sql.NVarChar,  recurrenceFrequency || 'none')
      .input('recurrenceInterval',  sql.Int,       recurrenceInterval || 1)
      .query(`INSERT INTO Task
                (id, domainId, title, description, startDate, dueDate,
                 recurrenceFrequency, recurrenceInterval, status)
              OUTPUT INSERTED.*
              VALUES (@id, @domainId, @title, @description, @startDate, @dueDate,
                      @recurrenceFrequency, @recurrenceInterval, 'open')`);
    res.json(result.recordset[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Mark task as done; auto-creates next capsule for recurring tasks
app.patch('/tasks/:id/done', async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();

    const taskResult = await p.request()
      .input('id', sql.NVarChar, id)
      .query('SELECT * FROM Task WHERE id = @id');

    if (taskResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }
    const task = taskResult.recordset[0];

    const now = new Date();
    await p.request()
      .input('id',          sql.NVarChar,  id)
      .input('completedAt', sql.DateTime2, now)
      .query("UPDATE Task SET status = 'done', completedAt = @completedAt WHERE id = @id");

    const nextTask = await createNextCapsuleIfNeeded(p, task);

    res.json({ success: true, nextTask: nextTask || null });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Set task to inProgress
app.patch('/tasks/:id/start', async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id', sql.NVarChar, id)
      .query("UPDATE Task SET status = 'inProgress' WHERE id = @id AND status = 'open'");
    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Task not found or not open' });
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Reopen a completed task (undo done)
app.patch('/tasks/:id/reopen', async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();
    const taskResult = await p.request()
      .input('id', sql.NVarChar, id)
      .query('SELECT * FROM Task WHERE id = @id');

    if (taskResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }

    await p.request()
      .input('id', sql.NVarChar, id)
      .query("UPDATE Task SET status = 'open', completedAt = NULL WHERE id = @id");

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Set or clear orbit-wide reminder for a task
app.patch('/tasks/:id/reminder', async (req, res) => {
  const { id } = req.params;
  const { reminderAt } = req.body;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',         sql.NVarChar,  id)
      .input('reminderAt', sql.DateTime2, reminderAt ? new Date(reminderAt) : null)
      .query('UPDATE Task SET reminderAt = @reminderAt WHERE id = @id');
    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete a task and its log entries
app.delete('/tasks/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();

    const taskResult = await p.request()
      .input('id', sql.NVarChar, id)
      .query('SELECT id FROM Task WHERE id = @id');

    if (taskResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }

    // Detach successor tasks before deleting (they keep their own data, just lose the chain link)
    await p.request()
      .input('id', sql.NVarChar, id)
      .query('UPDATE Task SET previousTaskId = NULL WHERE previousTaskId = @id');

    await p.request()
      .input('id', sql.NVarChar, id)
      .query('DELETE FROM TaskLogEntry WHERE taskId = @id');

    await p.request()
      .input('id', sql.NVarChar, id)
      .query('DELETE FROM Task WHERE id = @id');

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Logs
// -----------------------------------------------------------------------

app.get('/logs/:taskId', async (req, res) => {
  const { taskId } = req.params;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('taskId', sql.NVarChar, taskId)
      .query('SELECT * FROM TaskLogEntry WHERE taskId = @taskId ORDER BY timestamp DESC');
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/logs', async (req, res) => {
  const { taskId, user, text } = req.body;
  const id  = uuidv4();
  const now = new Date();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',        sql.NVarChar,  id)
      .input('taskId',    sql.NVarChar,  taskId)
      .input('user',      sql.NVarChar,  user)
      .input('text',      sql.NVarChar,  text)
      .input('timestamp', sql.DateTime2, now)
      .query(`INSERT INTO TaskLogEntry (id, taskId, [user], [text], timestamp)
              OUTPUT INSERTED.*
              VALUES (@id, @taskId, @user, @text, @timestamp)`);

    // Auto-set to inProgress on first log entry
    const update = await p.request()
      .input('taskId', sql.NVarChar, taskId)
      .query("UPDATE Task SET status = 'inProgress' WHERE id = @taskId AND status = 'open'");
    const taskStatus = update.rowsAffected[0] > 0 ? 'inProgress' : null;

    res.json({ ...result.recordset[0], taskStatus });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Scheduler: auto-create next capsule when a recurring task's next
// start date has been reached and no successor exists yet.
// Runs every hour.
// -----------------------------------------------------------------------

async function runScheduler() {
  try {
    const p = await getPool();
    const now = new Date();

    // 1. Recurring tasks: auto-create next capsule if due
    const recurring = await p.request().query(
      "SELECT * FROM Task WHERE status != 'done' AND recurrenceFrequency != 'none'"
    );
    for (const task of recurring.recordset) {
      const nextStart = nextDate(task.startDate, task.recurrenceFrequency, task.recurrenceInterval);
      if (nextStart <= now) {
        const created = await createNextCapsuleIfNeeded(p, task);
        if (created) {
          console.log(`Scheduler: created next capsule ${created.id} for task ${task.id}`);
        }
      }
    }

    // 2. Reminders: send e-mail for due reminders not yet sent
    const dueReminders = await p.request()
      .input('now', sql.DateTime2, now)
      .query(`SELECT t.*, d.name AS domainName, d.notificationEmails
              FROM Task t
              JOIN TaskDomain d ON t.domainId = d.id
              WHERE t.reminderAt IS NOT NULL
                AND t.reminderAt <= @now
                AND t.reminderEmailSentAt IS NULL
                AND t.status != 'done'`);

    for (const task of dueReminders.recordset) {
      const emails = (task.notificationEmails || '').split(',').map(e => e.trim()).filter(Boolean);
      if (emails.length > 0) {
        try {
          await sendReminderEmail(emails, task, task.domainName);
          console.log(`Scheduler: reminder e-mail sent for task ${task.id} to ${emails.join(', ')}`);
        } catch (mailErr) {
          console.error(`Scheduler: e-mail failed for task ${task.id}:`, mailErr.message);
        }
      }
      // Mark as sent regardless of mail success to avoid infinite retry loops
      await p.request()
        .input('id',  sql.NVarChar,  task.id)
        .input('now', sql.DateTime2, now)
        .query('UPDATE Task SET reminderEmailSentAt = @now WHERE id = @id');
    }
  } catch (err) {
    console.error('Scheduler error:', err.message);
  }
}

setInterval(runScheduler, 60 * 60 * 1000);

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
  runScheduler();
});
