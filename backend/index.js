const express = require('express');
const sql = require('mssql');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const nodemailer = require('nodemailer');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 Minuten
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Zu viele Versuche. Bitte warte 15 Minuten und versuche es erneut.' },
});
app.use('/auth/login', authLimiter);
app.use('/auth/register', authLimiter);
app.use('/auth/forgot-password', authLimiter);

const JWT_SECRET = process.env.JWT_SECRET || 'changeme-in-production';
const JWT_EXPIRES_IN = '30d';

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
// Feldlaengen
//
// Die Werte spiegeln die Spaltenbreiten aus db/schema.sql und muessen mit
// lib/utils/field_limits.dart uebereinstimmen. Ohne diese Pruefung quittiert
// SQL Server zu lange Texte mit "String or binary data would be truncated" –
// ein 500er, aus dem in der App keine brauchbare Meldung wird.
// -----------------------------------------------------------------------

const FIELD_LIMITS = {
  sphereTitle:       200,   // Task.title
  sphereDescription: 1000,  // Task.description
  orbitName:         100,   // TaskDomain.name
  orbitDescription:  500,   // TaskDomain.description
  logText:           1000,  // TaskLogEntry.text
  displayName:       200,   // AppUser.displayName
};

/// Antwortet mit 400 und gibt true zurueck, wenn `value` zu lang ist.
/// Aufrufer beenden dann mit `return`.
function rejectIfTooLong(res, label, value, max) {
  if (typeof value !== 'string') return false;
  const length = value.trim().length;
  if (length <= max) return false;
  res.status(400).json({
    error: `${label} darf höchstens ${max} Zeichen lang sein (aktuell ${length}).`,
  });
  return true;
}

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

async function sendMail(to, subject, html) {
  if (!mailTransport) {
    console.log('SMTP not configured – skipping e-mail to', to);
    return;
  }
  await mailTransport.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to,
    subject,
    html,
  });
}

async function sendReminderEmail(toAddresses, task, domainName) {
  const tz = 'Europe/Berlin';
  const dueStr = task.dueDate ? new Date(task.dueDate).toLocaleDateString('de-DE', {
    day: '2-digit', month: 'long', year: 'numeric', timeZone: tz,
  }) : null;
  const reminderStr = new Date(task.reminderAt).toLocaleString('de-DE', {
    day: '2-digit', month: 'long', year: 'numeric',
    hour: '2-digit', minute: '2-digit', timeZone: tz,
  });
  await sendMail(
    toAddresses,
    `⏰ Erinnerung: ${task.title}`,
    `
      <h2>Erinnerung für Sphere: ${task.title}</h2>
      <p><strong>Orbit:</strong> ${domainName}</p>
      ${dueStr ? `<p><strong>Fällig am:</strong> ${dueStr}</p>` : ''}
      <p><strong>Erinnerungszeit:</strong> ${reminderStr}</p>
      ${task.description ? `<p><strong>Beschreibung:</strong> ${task.description}</p>` : ''}
      <hr>
      <p style="color:#666;font-size:12px">OrgaSphere – Orbit-weite Erinnerung</p>
    `
  );
}

// -----------------------------------------------------------------------
// Push (Firebase Cloud Messaging)
// -----------------------------------------------------------------------

// Service-Account als JSON im App-Setting FIREBASE_SERVICE_ACCOUNT.
// Fehlt die Config, bleibt Push ein No-Op (analog zu mailTransport oben).
let fcmReady = false;
try {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (raw) {
    const serviceAccount = JSON.parse(raw);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    fcmReady = true;
    console.log('FCM ready');
  } else {
    console.log('FIREBASE_SERVICE_ACCOUNT not set – push notifications disabled');
  }
} catch (err) {
  console.error('FCM init failed – push notifications disabled:', err.message);
}

// Sendet einen Push an eine Liste von Tokens und entfernt ungültige Tokens aus der DB.
async function sendPushToTokens(p, tokens, body, data) {
  if (!fcmReady || tokens.length === 0) return;
  try {
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: 'OrgaSphere', body },
      data,
      android: { priority: 'high', notification: { channelId: 'orga_events' } },
    });
    const stale = [];
    response.responses.forEach((r, i) => {
      if (!r.success) {
        const code = r.error?.code || '';
        if (code.includes('registration-token-not-registered') ||
            code.includes('invalid-argument')) {
          stale.push(tokens[i]);
        }
      }
    });
    for (const token of stale) {
      await p.request()
        .input('token', sql.NVarChar, token)
        .query('DELETE FROM DeviceToken WHERE token = @token');
    }
    if (stale.length > 0) console.log(`FCM: removed ${stale.length} stale token(s)`);
  } catch (err) {
    console.error('FCM send failed:', err.message);
  }
}

// Schreibt ein Team-Ereignis in OrbitEvent und pusht es an alle aktiven Mitglieder
// des Orbits AUSSER dem Auslöser. Darf die auslösende Aktion niemals scheitern lassen.
async function emitOrbitEvent(p, { orbitId, actorUserId, actorName, type, sphereId, sphereTitle, orbitName, body }) {
  try {
    // Einfache Listen ("Einkaufslisten-Modus") bleiben stumm. Sonst wuerde das
    // Erfassen von 20 Positionen und das spaetere Abhaken im Laden 40 Meldungen
    // beim Co-Piloten ausloesen und die Glocke unbrauchbar machen.
    const listCheck = await p.request()
      .input('orbitId', sql.NVarChar, orbitId)
      .query('SELECT isShoppingList FROM TaskDomain WHERE id = @orbitId');
    if (listCheck.recordset[0]?.isShoppingList) return;

    await p.request()
      .input('id',          sql.NVarChar,  uuidv4())
      .input('orbitId',     sql.NVarChar,  orbitId)
      .input('actorUserId', sql.NVarChar,  actorUserId || null)
      .input('actorName',   sql.NVarChar,  actorName || null)
      .input('type',        sql.NVarChar,  type)
      .input('sphereId',    sql.NVarChar,  sphereId || null)
      .input('sphereTitle', sql.NVarChar,  sphereTitle || null)
      .input('orbitName',   sql.NVarChar,  orbitName || null)
      .input('body',        sql.NVarChar,  body)
      .query(`INSERT INTO OrbitEvent
                (id, orbitId, actorUserId, actorName, type, sphereId, sphereTitle, orbitName, body)
              VALUES (@id, @orbitId, @actorUserId, @actorName, @type, @sphereId, @sphereTitle, @orbitName, @body)`);

    const recipients = await p.request()
      .input('orbitId', sql.NVarChar, orbitId)
      .input('actor',   sql.NVarChar, actorUserId || '')
      .query(`SELECT dt.token
              FROM OrbitMember om
              JOIN DeviceToken dt ON dt.userId = om.userId
              WHERE om.orbitId = @orbitId AND om.status = 'active' AND om.userId <> @actor`);
    const tokens = recipients.recordset.map(r => r.token).filter(Boolean);

    await sendPushToTokens(p, tokens, body, {
      type,
      orbitId: orbitId || '',
      sphereId: sphereId || '',
    });
  } catch (err) {
    console.error('emitOrbitEvent failed:', err.message);
  }
}

// Klarnamen des eingeloggten Nutzers frisch aus AppUser holen (displayName, sonst email).
async function resolveActorName(p, userId, fallbackEmail) {
  try {
    const row = await p.request()
      .input('userId', sql.NVarChar, userId)
      .query('SELECT displayName, email FROM AppUser WHERE id = @userId');
    const u = row.recordset[0] || {};
    return (u.displayName && u.displayName.trim()) || u.email || fallbackEmail;
  } catch {
    return fallbackEmail;
  }
}

// -----------------------------------------------------------------------
// JWT-Middleware
// -----------------------------------------------------------------------

function requireAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Nicht authentifiziert' });
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.user = { userId: payload.userId, email: payload.email };
    next();
  } catch {
    return res.status(401).json({ error: 'Token ungültig oder abgelaufen' });
  }
}

// Prüft ob der eingeloggte User Pilot des Orbits ist.
async function requirePilot(req, res, next) {
  const orbitId = req.params.id || req.params.orbitId;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('orbitId', sql.NVarChar, orbitId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember
              WHERE orbitId = @orbitId AND userId = @userId AND role = 'pilot' AND status = 'active'`);
    if (result.recordset.length === 0) {
      return res.status(403).json({ error: 'Nur der Pilot darf diese Aktion ausführen' });
    }
    next();
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// Prüft ob der eingeloggte User Mitglied (Pilot oder aktiver Co-Pilot) des Orbits ist.
async function requireMember(req, res, next) {
  const orbitId = req.params.id || req.params.orbitId || req.body?.domainId;
  if (!orbitId) return res.status(400).json({ error: 'orbitId fehlt' });
  try {
    const p = await getPool();
    const result = await p.request()
      .input('orbitId', sql.NVarChar, orbitId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember
              WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (result.recordset.length === 0) {
      return res.status(403).json({ error: 'Kein Zugriff auf diesen Orbit' });
    }
    next();
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// -----------------------------------------------------------------------
// Recurrence
// -----------------------------------------------------------------------

// Zeitzone, in der Erinnerungen "nach Wanduhr" gelten. Ueber die
// Umgebungsvariable APP_TIMEZONE aenderbar, falls die App einmal ausserhalb
// Deutschlands laufen soll. Ein fester Wert ist hier bewusst gewaehlt: Die
// Zeitzone des einzelnen Nutzers wird bislang nirgends gespeichert.
const APP_TIMEZONE = process.env.APP_TIMEZONE || 'Europe/Berlin';

// Zerlegt einen Zeitpunkt in das, was in der Zielzone auf der Wanduhr steht.
function getZonedParts(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    hour12: false,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const parts = {};
  for (const part of formatter.formatToParts(date)) {
    if (part.type !== 'literal') parts[part.type] = Number(part.value);
  }
  // Mitternacht liefert je nach Node-Version 24 statt 0.
  if (parts.hour === 24) parts.hour = 0;
  return parts;
}

// Abstand der Zielzone zu UTC in Minuten, gueltig fuer genau diesen Zeitpunkt
// (Sommerzeit +120, Winterzeit +60 fuer Deutschland).
function getZoneOffsetMinutes(date, timeZone) {
  const p = getZonedParts(date, timeZone);
  const asIfUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  const whole = Math.floor(date.getTime() / 1000) * 1000; // Millisekunden weg
  return (asIfUtc - whole) / 60000;
}

// Rechnet eine Wanduhrzeit der Zielzone zurueck in einen echten Zeitpunkt.
//
// Der Offset haengt vom Ergebnis ab und das Ergebnis vom Offset. Ausserhalb der
// Umstellungsnaechte loest sich das nach einem Schritt auf. In den beiden
// Sonderfaellen gibt es keine saubere Loesung, deshalb werden sie ausdruecklich
// entschieden statt sich auf eine Schleife zu verlassen (die pendelt dort
// zwischen zwei Werten):
//   * Uebersprungene Stunde (Fruehjahr, 02:00 -> 03:00): Die Wanduhrzeit gibt
//     es nicht. Die Erinnerung rutscht um die fehlende Stunde nach hinten,
//     also 02:30 -> 03:30. Nach vorn waere sie vor dem gewuenschten Zeitpunkt.
//   * Doppelte Stunde (Herbst, 03:00 -> 02:00): Die Wanduhrzeit gibt es
//     zweimal. Es gewinnt der erste Durchgang – die Erinnerung kommt also
//     eher statt spaeter.
function zonedPartsToUtc(parts, timeZone) {
  const naive = Date.UTC(
    parts.year, parts.month - 1, parts.day,
    parts.hour, parts.minute, parts.second,
  );

  // Ueberlaeufe wie "Tag 35" hat Date.UTC schon aufgeloest – ab hier zaehlt die
  // bereinigte Wanduhrzeit.
  const target = new Date(naive);
  const matchesTarget = (timestamp) => {
    const p = getZonedParts(new Date(timestamp), timeZone);
    return p.year === target.getUTCFullYear()
        && p.month === target.getUTCMonth() + 1
        && p.day === target.getUTCDate()
        && p.hour === target.getUTCHours()
        && p.minute === target.getUTCMinutes();
  };

  // Alle Offsets, die rund um den gesuchten Zeitpunkt gelten koennen. Ein Tag
  // davor und danach umschliesst die Umstellungsnacht sicher; ausserhalb davon
  // sind alle drei gleich und es bleibt bei einem einzigen Kandidaten.
  const offsets = new Set([
    getZoneOffsetMinutes(new Date(naive - 86400000), timeZone),
    getZoneOffsetMinutes(target, timeZone),
    getZoneOffsetMinutes(new Date(naive + 86400000), timeZone),
  ]);
  const candidates = [...offsets].map((offset) => naive - offset * 60000);

  const valid = candidates.filter(matchesTarget);
  if (valid.length > 0) return new Date(Math.min(...valid));
  return new Date(Math.max(...candidates));
}

// Einmal beim Start protokollieren, damit in den Azure-Logs sofort sichtbar
// ist, nach welcher Uhr Erinnerungen weitergezaehlt werden.
console.log(
  `Erinnerungen rechnen in Zeitzone ${APP_TIMEZONE} ` +
  `(derzeit UTC+${getZoneOffsetMinutes(new Date(), APP_TIMEZONE) / 60}h)`
);

// Verschiebt ein Datum um genau einen Wiederholungsrhythmus.
//
// Fuer Start- und Faelligkeitsdatum. Die liegen als reine Datumswerte auf
// 00:00:00 (siehe db/schema.sql), da zaehlen nur ganze Tage – die
// Zeitumstellung spielt keine Rolle und wuerde die Mitternacht sogar
// verschieben.
//
// Der Null-Fall ist Absicht und wichtig: Faelligkeit und Erinnerung sind
// optional. Ohne die Abfrage macht `new Date(null)` daraus den 01.01.1970 –
// die Folge-Sphere truege dann ein Datum aus der Steinzeit und stuende sofort
// als ueberfaellig da.
function nextDate(current, frequency, interval) {
  if (!current) return null;
  const d = new Date(current);
  switch (frequency) {
    case 'daily':   d.setDate(d.getDate() + interval); break;
    case 'weekly':  d.setDate(d.getDate() + 7 * interval); break;
    case 'monthly': d.setMonth(d.getMonth() + interval); break;
    case 'yearly':  d.setFullYear(d.getFullYear() + interval); break;
  }
  return d;
}

// Verschiebt eine ERINNERUNG um einen Wiederholungsrhythmus.
//
// Anders als bei Start und Faelligkeit zaehlt hier die Uhrzeit, und die soll
// bleiben, wo sie ist: 06:30 Uhr bleibt 06:30 Uhr – auch wenn zwischen den
// beiden Terminen die Uhr umgestellt wird. Deshalb wird nicht in UTC
// gerechnet (das ergaebe exakt 72 Stunden und damit nach der Umstellung
// ploetzlich 05:30 Uhr), sondern auf der Wanduhr der Zielzone.
function nextReminderDate(current, frequency, interval, timeZone = APP_TIMEZONE) {
  if (!current) return null;
  const parts = getZonedParts(new Date(current), timeZone);
  switch (frequency) {
    case 'daily':   parts.day += interval; break;
    case 'weekly':  parts.day += 7 * interval; break;
    case 'monthly': parts.month += interval; break;
    case 'yearly':  parts.year += interval; break;
    default: return new Date(current);
  }
  // Ueberlaeufe (Tag 35, Monat 13) rechnet Date.UTC selbst um – genau wie
  // setDate/setMonth in nextDate, damit beide gleich rollen.
  return zonedPartsToUtc(parts, timeZone);
}

async function createNextCapsuleIfNeeded(p, task) {
  if (task.recurrenceFrequency === 'none') return null;

  const existing = await p.request()
    .input('prevId', sql.NVarChar, task.id)
    .query('SELECT id FROM Task WHERE previousTaskId = @prevId');

  if (existing.recordset.length > 0) return null;

  const nextStart = nextDate(task.startDate, task.recurrenceFrequency, task.recurrenceInterval);
  const nextDue   = nextDate(task.dueDate,   task.recurrenceFrequency, task.recurrenceInterval);

  // Die Erinnerung gehoert zur Sphere und wandert mit – um genau denselben
  // Rhythmus versetzt wie Start und Faelligkeit. Erinnerung am 12.08. um 06:30
  // bei Wiederholung "alle 3 Tage" ergibt also den 15.08. um 06:30.
  // Ohne das fiel die Erinnerung nach dem ersten Durchlauf stillschweigend weg,
  // obwohl die Wiederholung weiterlief.
  //
  // nextReminderDate statt nextDate: Die Uhrzeit soll die Zeitumstellung
  // ueberleben (siehe dort).
  //
  // reminderEmailSentAt wird bewusst NICHT uebernommen (Spaltendefault NULL),
  // sonst haette der Scheduler die neue Erinnerung als bereits verschickt
  // angesehen und nie eine Mail geschickt.
  const nextReminder = nextReminderDate(task.reminderAt, task.recurrenceFrequency, task.recurrenceInterval);

  const nextId    = uuidv4();

  const result = await p.request()
    .input('id',                   sql.NVarChar,  nextId)
    .input('domainId',             sql.NVarChar,  task.domainId)
    .input('title',                sql.NVarChar,  task.title)
    .input('description',          sql.NVarChar,  task.description)
    .input('startDate',            sql.DateTime2, nextStart)
    .input('dueDate',              sql.DateTime2, nextDue)
    .input('reminderAt',           sql.DateTime2, nextReminder)
    .input('recurrenceFrequency',  sql.NVarChar,  task.recurrenceFrequency)
    .input('recurrenceInterval',   sql.Int,       task.recurrenceInterval)
    .input('previousTaskId',       sql.NVarChar,  task.id)
    .input('assignedToMemberId',   sql.NVarChar,  task.assignedToMemberId || null)
    .query(`INSERT INTO Task
              (id, domainId, title, description, startDate, dueDate, reminderAt,
               recurrenceFrequency, recurrenceInterval, status, previousTaskId, assignedToMemberId)
            OUTPUT INSERTED.*
            VALUES (@id, @domainId, @title, @description, @startDate, @dueDate, @reminderAt,
                    @recurrenceFrequency, @recurrenceInterval, 'open', @previousTaskId, @assignedToMemberId)`);

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
// Auth
// -----------------------------------------------------------------------

// Nach erfolgreicher Registrierung oder Login: alle OrbitMember-Einträge mit dieser
// E-Mail und userId=NULL mit dem neuen Account verknüpfen (z.B. Admin-Migration oder
// ausstehende Einladungen).
async function linkPendingMemberships(p, userId, email) {
  await p.request()
    .input('userId', sql.NVarChar, userId)
    .input('email',  sql.NVarChar, email)
    .query(`UPDATE OrbitMember
            SET userId = @userId, status = 'active', joinedAt = GETUTCDATE()
            WHERE email = @email AND userId IS NULL AND status = 'active'`);
}

app.post('/auth/register', async (req, res) => {
  const { email, password, displayName } = req.body;
  if (!email?.trim() || !password) {
    return res.status(400).json({ error: 'E-Mail und Passwort erforderlich' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Passwort muss mindestens 8 Zeichen haben' });
  }
  try {
    const p = await getPool();
    const existing = await p.request()
      .input('email', sql.NVarChar, email.trim().toLowerCase())
      .query('SELECT id FROM AppUser WHERE email = @email');
    if (existing.recordset.length > 0) {
      return res.status(409).json({ error: 'Diese E-Mail ist bereits registriert' });
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const userId = uuidv4();
    const nameValue = displayName?.trim() || null;
    await p.request()
      .input('id',           sql.NVarChar, userId)
      .input('email',        sql.NVarChar, email.trim().toLowerCase())
      .input('passwordHash', sql.NVarChar, passwordHash)
      .input('displayName',  sql.NVarChar, nameValue)
      .query('INSERT INTO AppUser (id, email, passwordHash, displayName) VALUES (@id, @email, @passwordHash, @displayName)');

    await linkPendingMemberships(p, userId, email.trim().toLowerCase());

    const token = jwt.sign({ userId, email: email.trim().toLowerCase(), displayName: nameValue }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
    res.json({ token, userId, email: email.trim().toLowerCase(), displayName: nameValue });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/auth/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email?.trim() || !password) {
    return res.status(400).json({ error: 'E-Mail und Passwort erforderlich' });
  }
  try {
    const p = await getPool();
    const result = await p.request()
      .input('email', sql.NVarChar, email.trim().toLowerCase())
      .query('SELECT * FROM AppUser WHERE email = @email');
    const user = result.recordset[0];
    if (!user) {
      return res.status(401).json({ error: 'E-Mail oder Passwort falsch' });
    }
    const valid = await bcrypt.compare(password, user.passwordHash);
    if (!valid) {
      return res.status(401).json({ error: 'E-Mail oder Passwort falsch' });
    }
    const token = jwt.sign({ userId: user.id, email: user.email, displayName: user.displayName || null }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
    res.json({ token, userId: user.id, email: user.email, displayName: user.displayName || null });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/auth/me', requireAuth, async (req, res) => {
  res.json({ userId: req.user.userId, email: req.user.email, displayName: req.user.displayName || null });
});

app.patch('/auth/profile', requireAuth, async (req, res) => {
  const { displayName, email } = req.body;
  if (rejectIfTooLong(res, 'Der Name', displayName, FIELD_LIMITS.displayName)) return;
  const userId = req.user.userId;
  try {
    const p = await getPool();
    if (email !== undefined) {
      const emailLower = email.trim().toLowerCase();
      if (!emailLower.includes('@')) return res.status(400).json({ error: 'Ungültige E-Mail-Adresse' });
      const existing = await p.request()
        .input('email', sql.NVarChar, emailLower)
        .input('userId', sql.NVarChar, userId)
        .query('SELECT id FROM AppUser WHERE email = @email AND id <> @userId');
      if (existing.recordset.length > 0) {
        return res.status(409).json({ error: 'Diese E-Mail wird bereits verwendet' });
      }
      await p.request()
        .input('email', sql.NVarChar, emailLower)
        .input('userId', sql.NVarChar, userId)
        .query('UPDATE AppUser SET email = @email WHERE id = @userId');

      // Mitgliedschaften mitziehen. Sonst behalten die OrbitMember-Zeilen die
      // alte Adresse, und daran haengt mehr als nur eine Anzeige: Der
      // Erinnerungs-Scheduler verschickt seine Mails an OrbitMember.email,
      // wuerde also weiter die alte Adresse anschreiben.
      await p.request()
        .input('email', sql.NVarChar, emailLower)
        .input('userId', sql.NVarChar, userId)
        .query('UPDATE OrbitMember SET email = @email WHERE userId = @userId');
    }
    if (displayName !== undefined) {
      const nameValue = displayName?.trim() || null;
      await p.request()
        .input('displayName', sql.NVarChar, nameValue)
        .input('userId', sql.NVarChar, userId)
        .query('UPDATE AppUser SET displayName = @displayName WHERE id = @userId');
    }
    const updated = await p.request()
      .input('userId', sql.NVarChar, userId)
      .query('SELECT email, displayName FROM AppUser WHERE id = @userId');
    const user = updated.recordset[0];
    const token = jwt.sign(
      { userId, email: user.email, displayName: user.displayName || null },
      JWT_SECRET, { expiresIn: JWT_EXPIRES_IN }
    );
    res.json({ token, email: user.email, displayName: user.displayName || null });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/auth/password', requireAuth, async (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) {
    return res.status(400).json({ error: 'Aktuelles und neues Passwort erforderlich' });
  }
  if (newPassword.length < 8) {
    return res.status(400).json({ error: 'Neues Passwort muss mindestens 8 Zeichen haben' });
  }
  try {
    const p = await getPool();
    const result = await p.request()
      .input('userId', sql.NVarChar, req.user.userId)
      .query('SELECT passwordHash FROM AppUser WHERE id = @userId');
    const user = result.recordset[0];
    if (!user) return res.status(404).json({ error: 'Nutzer nicht gefunden' });
    const valid = await bcrypt.compare(currentPassword, user.passwordHash);
    if (!valid) return res.status(401).json({ error: 'Aktuelles Passwort ist falsch' });
    const newHash = await bcrypt.hash(newPassword, 12);
    await p.request()
      .input('hash', sql.NVarChar, newHash)
      .input('userId', sql.NVarChar, req.user.userId)
      .query('UPDATE AppUser SET passwordHash = @hash WHERE id = @userId');
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Passwort zurücksetzen
// -----------------------------------------------------------------------

app.post('/auth/forgot-password', async (req, res) => {
  const { email } = req.body;
  if (!email?.trim()) return res.status(400).json({ error: 'E-Mail erforderlich' });
  try {
    const p = await getPool();
    const result = await p.request()
      .input('email', sql.NVarChar, email.trim().toLowerCase())
      .query('SELECT id FROM AppUser WHERE email = @email');
    if (result.recordset.length > 0) {
      const resetToken = uuidv4();
      const expiry = new Date(Date.now() + 60 * 60 * 1000);
      await p.request()
        .input('token', sql.NVarChar, resetToken)
        .input('expiry', sql.DateTime2, expiry)
        .input('userId', sql.NVarChar, result.recordset[0].id)
        .query('UPDATE AppUser SET resetToken = @token, resetTokenExpiry = @expiry WHERE id = @userId');
      const appBase = process.env.APP_BASE_URL || 'http://localhost:3000';
      await sendMail(
        email.trim().toLowerCase(),
        'OrgaSphere – Passwort zurücksetzen',
        `<div style="font-family:sans-serif;max-width:480px;margin:0 auto">
          <h2 style="color:#1a1a2e">Passwort zurücksetzen</h2>
          <p>Du hast angefordert, dein OrgaSphere-Passwort zurückzusetzen.</p>
          <p style="margin:24px 0">
            <a href="${appBase}/reset-password?token=${resetToken}"
               style="background:#1a1a2e;color:white;padding:12px 24px;border-radius:6px;text-decoration:none;display:inline-block">
              Passwort jetzt zurücksetzen
            </a>
          </p>
          <p style="color:#666;font-size:14px">Der Link ist 1 Stunde gültig. Falls du diese Anfrage nicht gestellt hast, kannst du diese E-Mail ignorieren.</p>
          <hr style="border:none;border-top:1px solid #eee;margin:24px 0">
          <p style="color:#999;font-size:12px">OrgaSphere – Orbit-Management</p>
        </div>`
      );
    }
    // Immer 200 zurückgeben – verhindert, dass man testen kann ob eine E-Mail registriert ist
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/reset-password', async (req, res) => {
  const { token } = req.query;
  if (!token) return res.status(400).send('<h2>Ungültiger Reset-Link.</h2>');
  try {
    const p = await getPool();
    const result = await p.request()
      .input('token', sql.NVarChar, token)
      .query('SELECT id FROM AppUser WHERE resetToken = @token AND resetTokenExpiry > GETUTCDATE()');
    if (result.recordset.length === 0) {
      return res.status(404).send(`<!DOCTYPE html><html lang="de"><head><meta charset="UTF-8">
        <title>OrgaSphere</title>
        <style>body{font-family:sans-serif;max-width:480px;margin:60px auto;padding:0 20px;color:#333}</style>
        </head><body><h1>OrgaSphere</h1>
        <p style="color:#c62828">Dieser Link ist ungültig oder abgelaufen.<br>Bitte fordere in der App einen neuen Link an.</p>
        </body></html>`);
    }
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(`<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OrgaSphere – Passwort zurücksetzen</title>
  <style>
    body { font-family: sans-serif; max-width: 480px; margin: 60px auto; padding: 0 20px; color: #333; }
    h1 { color: #1a1a2e; }
    input { width: 100%; padding: 10px; margin: 8px 0 16px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 16px; }
    button { background: #1a1a2e; color: white; border: none; padding: 12px 24px; border-radius: 6px; font-size: 16px; cursor: pointer; width: 100%; }
    button:hover { background: #2d2d4e; }
    .error { color: #c62828; margin-top: 12px; }
    .success { color: #2e7d32; margin-top: 12px; }
  </style>
</head>
<body>
  <h1>OrgaSphere</h1>
  <p>Gib dein neues Passwort ein:</p>
  <form id="form">
    <input type="password" id="password" placeholder="Neues Passwort (mind. 8 Zeichen)" required>
    <input type="password" id="password2" placeholder="Passwort wiederholen" required>
    <button type="submit">Passwort speichern</button>
  </form>
  <div id="msg"></div>
  <script>
    document.getElementById('form').addEventListener('submit', async e => {
      e.preventDefault();
      const pw = document.getElementById('password').value;
      const pw2 = document.getElementById('password2').value;
      const msg = document.getElementById('msg');
      if (pw !== pw2) { msg.className = 'error'; msg.textContent = 'Passwörter stimmen nicht überein.'; return; }
      if (pw.length < 8) { msg.className = 'error'; msg.textContent = 'Passwort muss mindestens 8 Zeichen haben.'; return; }
      const res = await fetch('/reset-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: '${token}', password: pw })
      });
      const data = await res.json();
      if (res.ok) {
        msg.className = 'success';
        msg.textContent = 'Passwort erfolgreich geändert. Du kannst dich jetzt in der App anmelden.';
        document.getElementById('form').style.display = 'none';
      } else {
        msg.className = 'error';
        msg.textContent = data.error || 'Fehler beim Zurücksetzen.';
      }
    });
  </script>
</body>
</html>`);
  } catch (err) {
    res.status(500).send('<h2>Serverfehler. Bitte versuche es später erneut.</h2>');
  }
});

app.post('/reset-password', async (req, res) => {
  const { token, password } = req.body;
  if (!token || !password) return res.status(400).json({ error: 'Token und Passwort erforderlich' });
  if (password.length < 8) return res.status(400).json({ error: 'Passwort muss mindestens 8 Zeichen haben' });
  try {
    const p = await getPool();
    const result = await p.request()
      .input('token', sql.NVarChar, token)
      .query('SELECT id FROM AppUser WHERE resetToken = @token AND resetTokenExpiry > GETUTCDATE()');
    if (result.recordset.length === 0) {
      return res.status(400).json({ error: 'Ungültiger oder abgelaufener Link. Bitte fordere einen neuen an.' });
    }
    const newHash = await bcrypt.hash(password, 12);
    await p.request()
      .input('hash', sql.NVarChar, newHash)
      .input('userId', sql.NVarChar, result.recordset[0].id)
      .query('UPDATE AppUser SET passwordHash = @hash, resetToken = NULL, resetTokenExpiry = NULL WHERE id = @userId');
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Einladung (HTML-Seite + Annahme)
// -----------------------------------------------------------------------

app.get('/invite', async (req, res) => {
  const { token } = req.query;
  if (!token) {
    return res.status(400).send('<h2>Ungültiger Einladungslink.</h2>');
  }
  try {
    const p = await getPool();
    const result = await p.request()
      .input('token', sql.NVarChar, token)
      .query(`SELECT om.*, td.name AS orbitName
              FROM OrbitMember om
              JOIN TaskDomain td ON om.orbitId = td.id
              WHERE om.inviteToken = @token AND om.status = 'pending'`);
    if (result.recordset.length === 0) {
      return res.status(404).send('<h2>Dieser Einladungslink ist ungültig oder wurde bereits verwendet.</h2>');
    }
    const invite = result.recordset[0];

    // Hat die eingeladene Person schon ein Konto, waere ein Registrierformular
    // falsch. Sie bestaetigt stattdessen mit ihrem Passwort – das beweist, dass
    // wirklich sie am Werk ist und nicht jemand, an den die Mail weitergeleitet
    // wurde.
    const accountResult = await p.request()
      .input('email', sql.NVarChar, invite.email)
      .query('SELECT id FROM AppUser WHERE email = @email');
    const hasAccount = accountResult.recordset.length > 0;

    if (hasAccount) {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      return res.send(`<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OrgaSphere – Einladung annehmen</title>
  <style>
    body { font-family: sans-serif; max-width: 480px; margin: 60px auto; padding: 0 20px; color: #333; }
    h1 { color: #512DA8; }
    input { width: 100%; padding: 10px; margin: 8px 0 16px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 16px; }
    button { background: #512DA8; color: white; border: none; padding: 12px 24px; border-radius: 6px; font-size: 16px; cursor: pointer; width: 100%; }
    button:hover { background: #4527A0; }
    .hint { color: #666; font-size: 14px; margin-top: 8px; }
    .error { color: #c62828; margin-top: 12px; }
    .success { color: #2e7d32; margin-top: 12px; }
  </style>
</head>
<body>
  <h1>OrgaSphere</h1>
  <p>Du wurdest als <strong>Co-Pilot</strong> zum Orbit <strong>"${invite.orbitName}"</strong> eingeladen.</p>
  <p>Du kannst die Einladung auch direkt in der OrgaSphere-App annehmen. Hier im Browser geht es mit deinem Passwort:</p>
  <form id="form">
    <input type="email" id="email" value="${invite.email}" readonly style="background:#f5f5f5">
    <input type="password" id="password" placeholder="Dein OrgaSphere-Passwort" required>
    <button type="submit">Einladung annehmen</button>
  </form>
  <div id="msg"></div>
  <script>
    document.getElementById('form').addEventListener('submit', async e => {
      e.preventDefault();
      const msg = document.getElementById('msg');
      const res = await fetch('/invite', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: '${token}', password: document.getElementById('password').value })
      });
      const data = await res.json();
      if (res.ok) {
        msg.className = 'success';
        msg.textContent = 'Einladung angenommen! Der Orbit steht dir jetzt in der OrgaSphere-App zur Verfügung.';
        document.getElementById('form').style.display = 'none';
      } else {
        msg.className = 'error';
        msg.textContent = data.error || 'Einladung konnte nicht angenommen werden.';
      }
    });
  </script>
</body>
</html>`);
    }

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(`<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OrgaSphere – Einladung annehmen</title>
  <style>
    body { font-family: sans-serif; max-width: 480px; margin: 60px auto; padding: 0 20px; color: #333; }
    h1 { color: #512DA8; }
    input { width: 100%; padding: 10px; margin: 8px 0 16px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 16px; }
    button { background: #512DA8; color: white; border: none; padding: 12px 24px; border-radius: 6px; font-size: 16px; cursor: pointer; width: 100%; }
    button:hover { background: #4527A0; }
    .hint { color: #666; font-size: 14px; margin-top: 8px; }
    .error { color: #c62828; margin-top: 12px; }
    .success { color: #2e7d32; margin-top: 12px; }
  </style>
</head>
<body>
  <h1>OrgaSphere</h1>
  <p>Du wurdest als <strong>Co-Pilot</strong> zum Orbit <strong>"${invite.orbitName}"</strong> eingeladen.</p>
  <p>Erstelle jetzt dein Konto, um loszulegen:</p>
  <form id="form">
    <input type="email" id="email" value="${invite.email}" readonly style="background:#f5f5f5">
    <input type="password" id="password" placeholder="Passwort (mind. 8 Zeichen)" required>
    <input type="password" id="password2" placeholder="Passwort wiederholen" required>
    <button type="submit">Konto erstellen & Einladung annehmen</button>
  </form>
  <div id="msg"></div>
  <script>
    document.getElementById('form').addEventListener('submit', async e => {
      e.preventDefault();
      const pw = document.getElementById('password').value;
      const pw2 = document.getElementById('password2').value;
      const msg = document.getElementById('msg');
      if (pw !== pw2) { msg.className = 'error'; msg.textContent = 'Passwörter stimmen nicht überein.'; return; }
      if (pw.length < 8) { msg.className = 'error'; msg.textContent = 'Passwort muss mindestens 8 Zeichen haben.'; return; }
      const res = await fetch('/invite', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: '${token}', password: pw })
      });
      const data = await res.json();
      if (res.ok) {
        msg.className = 'success';
        msg.textContent = 'Konto erstellt! Du kannst dich jetzt in der OrgaSphere-App mit deiner E-Mail anmelden.';
        document.getElementById('form').style.display = 'none';
      } else {
        msg.className = 'error';
        msg.textContent = data.error || 'Fehler beim Erstellen des Kontos.';
      }
    });
  </script>
</body>
</html>`);
  } catch (err) {
    res.status(500).send('<h2>Serverfehler. Bitte versuche es später erneut.</h2>');
  }
});

app.post('/invite', async (req, res) => {
  const { token, password } = req.body;
  if (!token || !password) {
    return res.status(400).json({ error: 'Token und Passwort erforderlich' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Passwort muss mindestens 8 Zeichen haben' });
  }
  try {
    const p = await getPool();
    const inviteResult = await p.request()
      .input('token', sql.NVarChar, token)
      .query(`SELECT * FROM OrbitMember WHERE inviteToken = @token AND status = 'pending'`);
    if (inviteResult.recordset.length === 0) {
      return res.status(404).json({ error: 'Einladungslink ungültig oder bereits verwendet' });
    }
    const invite = inviteResult.recordset[0];

    // Prüfen ob E-Mail schon registriert
    const existing = await p.request()
      .input('email', sql.NVarChar, invite.email)
      .query('SELECT id FROM AppUser WHERE email = @email');

    let userId;
    if (existing.recordset.length > 0) {
      // Konto vorhanden: Das Passwort dient hier nicht zum Anlegen, sondern als
      // Nachweis. Ohne diese Pruefung koennte jeder, der den Link in die Finger
      // bekommt, die Einladung an ihrer Stelle annehmen.
      const account = await p.request()
        .input('email', sql.NVarChar, invite.email)
        .query('SELECT id, passwordHash FROM AppUser WHERE email = @email');
      const valid = await bcrypt.compare(password, account.recordset[0].passwordHash);
      if (!valid) {
        return res.status(401).json({ error: 'Passwort falsch' });
      }
      userId = existing.recordset[0].id;
    } else {
      const passwordHash = await bcrypt.hash(password, 12);
      userId = uuidv4();
      await p.request()
        .input('id',           sql.NVarChar, userId)
        .input('email',        sql.NVarChar, invite.email)
        .input('passwordHash', sql.NVarChar, passwordHash)
        .query('INSERT INTO AppUser (id, email, passwordHash) VALUES (@id, @email, @passwordHash)');
    }

    // Einladung aktivieren und alle weiteren pending-Einladungen für diese E-Mail verknüpfen
    await linkPendingMemberships(p, userId, invite.email);

    // Diesen spezifischen Eintrag falls noch nicht durch linkPendingMemberships erfasst:
    await p.request()
      .input('token',  sql.NVarChar,  invite.inviteToken)
      .input('userId', sql.NVarChar,  userId)
      .query(`UPDATE OrbitMember SET userId = @userId, status = 'active',
              joinedAt = GETUTCDATE(), inviteToken = NULL
              WHERE inviteToken = @token`);

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Offene Einladungen des angemeldeten Nutzers
//
// Eine Einladung ist eine OrbitMember-Zeile mit status = 'pending'. Sie gibt
// noch keinerlei Zugriff – jede Abfrage von Orbits, Spheres, Push und
// Erinnerungsmails filtert auf status = 'active'.
// -----------------------------------------------------------------------

// Die eigene, aktuelle Adresse aus der Datenbank. Die im Token kann veraltet
// sein, wenn die E-Mail nach dem Login geaendert wurde.
async function getCurrentEmail(p, userId, fallback) {
  try {
    const row = await p.request()
      .input('userId', sql.NVarChar, userId)
      .query('SELECT email FROM AppUser WHERE id = @userId');
    return row.recordset[0]?.email || fallback;
  } catch {
    return fallback;
  }
}

app.get('/invitations', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    const email = await getCurrentEmail(p, req.user.userId, req.user.email);
    const result = await p.request()
      .input('userId', sql.NVarChar, req.user.userId)
      .input('email',  sql.NVarChar, email)
      .query(`SELECT om.id, om.orbitId, om.invitedAt,
                     td.name AS orbitName, td.color AS orbitColor,
                     (SELECT TOP 1 COALESCE(NULLIF(au.displayName, ''), pm.email)
                        FROM OrbitMember pm
                        LEFT JOIN AppUser au ON au.id = pm.userId
                       WHERE pm.orbitId = om.orbitId
                         AND pm.role = 'pilot' AND pm.status = 'active') AS pilotName
              FROM OrbitMember om
              JOIN TaskDomain td ON td.id = om.orbitId
              WHERE om.status = 'pending'
                AND (om.userId = @userId OR om.email = @email)
              ORDER BY om.invitedAt DESC`);
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Die Einladung muss dem Aufrufer gehoeren – geprueft ueber userId ODER
// E-Mail, denn bei Eingeladenen ohne Konto steht die userId noch nicht fest.
async function loadOwnInvitation(p, memberId, userId, email) {
  const result = await p.request()
    .input('id',     sql.NVarChar, memberId)
    .input('userId', sql.NVarChar, userId)
    .input('email',  sql.NVarChar, email)
    .query(`SELECT om.*, td.name AS orbitName
            FROM OrbitMember om
            JOIN TaskDomain td ON td.id = om.orbitId
            WHERE om.id = @id AND om.status = 'pending'
              AND (om.userId = @userId OR om.email = @email)`);
  return result.recordset[0] || null;
}

app.post('/invitations/:id/accept', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    const email = await getCurrentEmail(p, req.user.userId, req.user.email);
    const invite = await loadOwnInvitation(p, req.params.id, req.user.userId, email);
    if (!invite) return res.status(404).json({ error: 'Einladung nicht gefunden' });

    await p.request()
      .input('id',     sql.NVarChar, invite.id)
      .input('userId', sql.NVarChar, req.user.userId)
      .query(`UPDATE OrbitMember
              SET userId = @userId, status = 'active',
                  joinedAt = GETUTCDATE(), inviteToken = NULL
              WHERE id = @id`);

    res.json({ success: true, orbitId: invite.orbitId, orbitName: invite.orbitName });

    // Das Team erfaehrt, dass jemand dazugekommen ist.
    const actorName = await resolveActorName(p, req.user.userId, email);
    await emitOrbitEvent(p, {
      orbitId: invite.orbitId, actorUserId: req.user.userId, actorName,
      type: 'member_joined', orbitName: invite.orbitName,
      body: `${actorName} ist „${invite.orbitName}" als Co-Pilot beigetreten.`,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/invitations/:id/decline', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    const email = await getCurrentEmail(p, req.user.userId, req.user.email);
    const invite = await loadOwnInvitation(p, req.params.id, req.user.userId, email);
    if (!invite) return res.status(404).json({ error: 'Einladung nicht gefunden' });

    // Zeile loeschen statt auf 'declined' setzen: So kann der Pilot dieselbe
    // Person spaeter erneut einladen, ohne an der Doppelpruefung zu scheitern.
    await p.request()
      .input('id', sql.NVarChar, invite.id)
      .query('DELETE FROM OrbitMember WHERE id = @id');

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Domains (Orbits)
// -----------------------------------------------------------------------

app.get('/domains', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    // myRole: die eigene Rolle in diesem Orbit. Die App blendet danach die
    // Aktionen aus, die nur dem Piloten zustehen (Umbenennen, Loeschen,
    // Einladen). Die Rechte selbst haengen NICHT daran – die prueft weiterhin
    // requirePilot am jeweiligen Endpunkt.
    const result = await p.request()
      .input('userId', sql.NVarChar, req.user.userId)
      .query(`SELECT d.*, om.role AS myRole
              FROM TaskDomain d
              JOIN OrbitMember om ON om.orbitId = d.id
              WHERE om.userId = @userId AND om.status = 'active'`);
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/domains', requireAuth, async (req, res) => {
  const { name, description, color, isShoppingList } = req.body;
  if (rejectIfTooLong(res, 'Der Name', name, FIELD_LIMITS.orbitName)) return;
  if (rejectIfTooLong(res, 'Die Beschreibung', description, FIELD_LIMITS.orbitDescription)) return;
  const id = uuidv4();
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',          sql.NVarChar, id)
      .input('name',        sql.NVarChar, name)
      .input('description', sql.NVarChar, description)
      .input('color',       sql.NVarChar, color || '#F5F5F5')
      .input('isShoppingList', sql.Bit,   isShoppingList ? 1 : 0)
      .query(`INSERT INTO TaskDomain (id, name, description, color, isShoppingList)
              OUTPUT INSERTED.*
              VALUES (@id, @name, @description, @color, @isShoppingList)`);

    // Ersteller wird automatisch Pilot
    await p.request()
      .input('id',       sql.NVarChar,  uuidv4())
      .input('orbitId',  sql.NVarChar,  id)
      .input('userId',   sql.NVarChar,  req.user.userId)
      .input('email',    sql.NVarChar,  req.user.email)
      .query(`INSERT INTO OrbitMember (id, orbitId, userId, email, role, status, joinedAt)
              VALUES (@id, @orbitId, @userId, @email, 'pilot', 'active', GETUTCDATE())`);

    // Wer anlegt, ist Pilot – analog zu GET /domains mitliefern, damit die App
    // den neuen Orbit sofort mit den richtigen Aktionen zeichnet.
    res.json({ ...result.recordset[0], myRole: 'pilot' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/domains/:id', requireAuth, requireMember, async (req, res) => {
  const { id } = req.params;
  const { color } = req.body;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',    sql.NVarChar, id)
      .input('color', sql.NVarChar, color ?? null)
      .query('UPDATE TaskDomain SET color = @color WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Domain not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Umbenennen ist Pilotensache. Der Orbit-Name taucht in Einladungsmails,
// Erinnerungen und Team-Meldungen aller Mitglieder auf – ein Co-Pilot soll ihn
// nicht unter allen anderen wegziehen koennen.
app.patch('/domains/:id/name', requireAuth, requirePilot, async (req, res) => {
  const { id } = req.params;
  const { name } = req.body;
  if (!name?.trim()) return res.status(400).json({ error: 'Name required' });
  if (rejectIfTooLong(res, 'Der Name', name, FIELD_LIMITS.orbitName)) return;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',   sql.NVarChar, id)
      .input('name', sql.NVarChar, name.trim())
      .query('UPDATE TaskDomain SET name = @name WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Domain not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Beschreibung aendern – wie das Umbenennen Pilotensache. Sie steht im
// Kopfbereich des Orbits bei allen Mitgliedern.
app.patch('/domains/:id/description', requireAuth, requirePilot, async (req, res) => {
  const { id } = req.params;
  const { description } = req.body;
  if (rejectIfTooLong(res, 'Die Beschreibung', description, FIELD_LIMITS.orbitDescription)) return;
  try {
    const p = await getPool();
    const result = await p.request()
      .input('id',          sql.NVarChar, id)
      .input('description', sql.NVarChar, description ?? '')
      .query('UPDATE TaskDomain SET description = @description WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Domain not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/domains/:id', requireAuth, requirePilot, async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();
    const tasks = await p.request()
      .input('domainId', sql.NVarChar, id)
      .query('SELECT id FROM Task WHERE domainId = @domainId');

    for (const task of tasks.recordset) {
      await p.request()
        .input('prevId', sql.NVarChar, task.id)
        .query('UPDATE Task SET previousTaskId = NULL WHERE previousTaskId = @prevId');
      await p.request()
        .input('taskId', sql.NVarChar, task.id)
        .query('DELETE FROM TaskLogEntry WHERE taskId = @taskId');
    }

    await p.request()
      .input('domainId', sql.NVarChar, id)
      .query('DELETE FROM Task WHERE domainId = @domainId');

    await p.request()
      .input('id', sql.NVarChar, id)
      .query('DELETE FROM OrbitMember WHERE orbitId = @id');

    const result = await p.request()
      .input('id', sql.NVarChar, id)
      .query('DELETE FROM TaskDomain WHERE id = @id');

    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Domain not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// OrbitMember (Pilot / Co-Pilot Verwaltung)
// -----------------------------------------------------------------------

app.get('/domains/:id/members', requireAuth, requireMember, async (req, res) => {
  try {
    const p = await getPool();
    const result = await p.request()
      .input('orbitId', sql.NVarChar, req.params.id)
      .query(`SELECT om.id, om.orbitId, om.userId, om.email, om.role, om.status, om.invitedAt, om.joinedAt,
                     au.displayName
              FROM OrbitMember om
              LEFT JOIN AppUser au ON au.id = om.userId
              WHERE om.orbitId = @orbitId ORDER BY om.role DESC, om.joinedAt ASC`);
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/domains/:id/members', requireAuth, requirePilot, async (req, res) => {
  const orbitId = req.params.id;
  const { email } = req.body;
  if (!email?.trim()) return res.status(400).json({ error: 'E-Mail erforderlich' });
  const inviteEmail = email.trim().toLowerCase();

  if (inviteEmail === req.user.email) {
    return res.status(400).json({ error: 'Du bist bereits Pilot dieses Orbits' });
  }

  try {
    const p = await getPool();

    // Orbit-Name für E-Mail
    const orbitResult = await p.request()
      .input('id', sql.NVarChar, orbitId)
      .query('SELECT name FROM TaskDomain WHERE id = @id');
    if (orbitResult.recordset.length === 0) return res.status(404).json({ error: 'Orbit nicht gefunden' });
    const orbitName = orbitResult.recordset[0].name;

    // Prüfen ob bereits Mitglied
    const existing = await p.request()
      .input('orbitId', sql.NVarChar, orbitId)
      .input('email',   sql.NVarChar, inviteEmail)
      .query('SELECT id, status FROM OrbitMember WHERE orbitId = @orbitId AND email = @email');
    if (existing.recordset.length > 0) {
      return res.status(409).json({ error: 'Diese Person ist bereits Mitglied dieses Orbits' });
    }

    // Prüfen ob Nutzer schon registriert
    const userResult = await p.request()
      .input('email', sql.NVarChar, inviteEmail)
      .query('SELECT id FROM AppUser WHERE email = @email');

    const memberId = uuidv4();

    if (userResult.recordset.length > 0) {
      // Nutzer existiert → trotzdem nur EINLADEN, nicht sofort aufnehmen.
      // Sonst steht jemand als vollwertiger Teilnehmer in der Leiste, der von
      // seiner Mitgliedschaft noch gar nichts weiss.
      //
      // userId wird schon jetzt gesetzt, damit die App die Einladung beim
      // naechsten Start zuverlaessig findet – auch wenn die Person ihre
      // E-Mail-Adresse zwischenzeitlich aendert. Zugriff verschafft das nicht:
      // Orbits, Spheres, Push und Erinnerungsmails haengen ausnahmslos an
      // status = 'active'.
      const existingUserId = userResult.recordset[0].id;
      const inviteToken = uuidv4();
      const baseUrl = process.env.APP_BASE_URL || `https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net`;
      const inviteLink = `${baseUrl}/invite?token=${inviteToken}`;

      await p.request()
        .input('id',          sql.NVarChar,  memberId)
        .input('orbitId',     sql.NVarChar,  orbitId)
        .input('userId',      sql.NVarChar,  existingUserId)
        .input('email',       sql.NVarChar,  inviteEmail)
        .input('inviteToken', sql.NVarChar,  inviteToken)
        .query(`INSERT INTO OrbitMember (id, orbitId, userId, email, role, status, inviteToken, invitedAt)
                VALUES (@id, @orbitId, @userId, @email, 'copilot', 'pending', @inviteToken, GETUTCDATE())`);

      sendMail(
        inviteEmail,
        `OrgaSphere: Einladung zum Orbit "${orbitName}"`,
        `<h2>OrgaSphere</h2>
         <p>Du wurdest als <strong>Co-Pilot</strong> zum Orbit <strong>"${orbitName}"</strong> eingeladen.</p>
         <p>Öffne einfach die OrgaSphere-App – die Einladung wartet dort auf dich und lässt sich mit einem Tippen annehmen.</p>
         <p style="color:#666;font-size:12px;margin-top:16px">Lieber im Browser? Dann hier annehmen:<br>${inviteLink}</p>`
      ).catch(err => console.error('Einladungsmail fehlgeschlagen:', err.message));

      res.json({ status: 'invited', memberId });
    } else {
      // Nutzer nicht registriert → Einladung per E-Mail
      const inviteToken = uuidv4();
      const baseUrl = process.env.APP_BASE_URL || `https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net`;
      const inviteLink = `${baseUrl}/invite?token=${inviteToken}`;

      await p.request()
        .input('id',          sql.NVarChar,  memberId)
        .input('orbitId',     sql.NVarChar,  orbitId)
        .input('email',       sql.NVarChar,  inviteEmail)
        .input('inviteToken', sql.NVarChar,  inviteToken)
        .query(`INSERT INTO OrbitMember (id, orbitId, userId, email, role, status, inviteToken, invitedAt)
                VALUES (@id, @orbitId, NULL, @email, 'copilot', 'pending', @inviteToken, GETUTCDATE())`);

      sendMail(
        inviteEmail,
        `OrgaSphere: Einladung zum Orbit "${orbitName}"`,
        `<h2>OrgaSphere</h2>
         <p>Du wurdest als <strong>Co-Pilot</strong> zum Orbit <strong>"${orbitName}"</strong> eingeladen.</p>
         <p><a href="${inviteLink}" style="background:#512DA8;color:white;padding:12px 24px;border-radius:6px;text-decoration:none;display:inline-block;margin-top:12px">Einladung annehmen</a></p>
         <p style="color:#666;font-size:12px;margin-top:16px">Oder kopiere diesen Link in deinen Browser:<br>${inviteLink}</p>`
      ).catch(err => console.error('Einladungsmail fehlgeschlagen:', err.message));

      res.json({ status: 'invited', memberId });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/domains/:id/members/:memberId/suspend', requireAuth, requirePilot, async (req, res) => {
  const { memberId } = req.params;
  try {
    const p = await getPool();
    // Pilot kann sich nicht selbst sperren
    const memberCheck = await p.request()
      .input('id', sql.NVarChar, memberId)
      .query('SELECT role FROM OrbitMember WHERE id = @id');
    if (memberCheck.recordset[0]?.role === 'pilot') {
      return res.status(400).json({ error: 'Der Pilot kann nicht gesperrt werden' });
    }
    await p.request()
      .input('id', sql.NVarChar, memberId)
      .query("UPDATE OrbitMember SET status = 'suspended' WHERE id = @id");
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/domains/:id/members/:memberId/reactivate', requireAuth, requirePilot, async (req, res) => {
  const { memberId } = req.params;
  try {
    const p = await getPool();
    await p.request()
      .input('id', sql.NVarChar, memberId)
      .query("UPDATE OrbitMember SET status = 'active' WHERE id = @id AND role = 'copilot'");
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/domains/:id/members/:memberId', requireAuth, requirePilot, async (req, res) => {
  const { memberId } = req.params;
  try {
    const p = await getPool();
    const memberCheck = await p.request()
      .input('id', sql.NVarChar, memberId)
      .query('SELECT role FROM OrbitMember WHERE id = @id');
    if (memberCheck.recordset[0]?.role === 'pilot') {
      return res.status(400).json({ error: 'Der Pilot kann nicht entfernt werden' });
    }
    // Zuweisungen dieses Mitglieds aufheben, sonst zeigen Spheres auf ein gelöschtes Mitglied
    await p.request()
      .input('memberId', sql.NVarChar, memberId)
      .query('UPDATE Task SET assignedToMemberId = NULL WHERE assignedToMemberId = @memberId');
    await p.request()
      .input('id', sql.NVarChar, memberId)
      .query('DELETE FROM OrbitMember WHERE id = @id');
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Tasks
// -----------------------------------------------------------------------

// Hilfsfunktion: alle Orbit-IDs abrufen, auf die der User Zugriff hat
async function getUserOrbitIds(p, userId) {
  const result = await p.request()
    .input('userId', sql.NVarChar, userId)
    .query(`SELECT orbitId FROM OrbitMember WHERE userId = @userId AND status = 'active'`);
  return result.recordset.map(r => r.orbitId);
}

app.get('/tasks', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    const orbitIds = await getUserOrbitIds(p, req.user.userId);
    if (orbitIds.length === 0) return res.json([]);

    const placeholders = orbitIds.map((_, i) => `@oid${i}`).join(',');
    const request = p.request();
    orbitIds.forEach((id, i) => request.input(`oid${i}`, sql.NVarChar, id));
    const result = await request.query(
      `SELECT t.*, om.email AS assignedToEmail, au.displayName AS assignedToName
       FROM Task t
       LEFT JOIN OrbitMember om ON om.id = t.assignedToMemberId
       LEFT JOIN AppUser au ON au.id = om.userId
       WHERE t.status != 'done' AND t.domainId IN (${placeholders})
       ORDER BY CASE WHEN t.dueDate IS NULL THEN 1 ELSE 0 END, t.dueDate ASC`
    );
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/tasks/archived', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    const orbitIds = await getUserOrbitIds(p, req.user.userId);
    if (orbitIds.length === 0) return res.json([]);

    const placeholders = orbitIds.map((_, i) => `@oid${i}`).join(',');
    const request = p.request();
    orbitIds.forEach((id, i) => request.input(`oid${i}`, sql.NVarChar, id));
    const result = await request.query(
      `SELECT t.*, om.email AS assignedToEmail, au.displayName AS assignedToName
       FROM Task t
       LEFT JOIN OrbitMember om ON om.id = t.assignedToMemberId
       LEFT JOIN AppUser au ON au.id = om.userId
       WHERE t.status = 'done' AND t.domainId IN (${placeholders})
       ORDER BY t.completedAt DESC`
    );
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/tasks', requireAuth, async (req, res) => {
  const { domainId, title, description, startDate, dueDate, recurrenceFrequency, recurrenceInterval } = req.body;
  if (rejectIfTooLong(res, 'Der Titel', title, FIELD_LIMITS.sphereTitle)) return;
  if (rejectIfTooLong(res, 'Die Beschreibung', description, FIELD_LIMITS.sphereDescription)) return;
  const id = uuidv4();
  try {
    const p = await getPool();

    // Zugriffsprüfung: User muss Mitglied des Orbits sein
    const access = await p.request()
      .input('orbitId', sql.NVarChar, domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) {
      return res.status(403).json({ error: 'Kein Zugriff auf diesen Orbit' });
    }

    const result = await p.request()
      .input('id',                  sql.NVarChar,  id)
      .input('domainId',            sql.NVarChar,  domainId)
      .input('title',               sql.NVarChar,  title)
      .input('description',         sql.NVarChar,  description || '')
      .input('startDate',           sql.DateTime2, new Date(startDate))
      .input('dueDate',             sql.DateTime2, dueDate ? new Date(dueDate) : null)
      .input('recurrenceFrequency', sql.NVarChar,  recurrenceFrequency || 'none')
      .input('recurrenceInterval',  sql.Int,       recurrenceInterval || 1)
      .query(`INSERT INTO Task
                (id, domainId, title, description, startDate, dueDate,
                 recurrenceFrequency, recurrenceInterval, status)
              OUTPUT INSERTED.*
              VALUES (@id, @domainId, @title, @description, @startDate, @dueDate,
                      @recurrenceFrequency, @recurrenceInterval, 'open')`);
    res.json(result.recordset[0]);

    // Team-Benachrichtigung (nach der Antwort – darf die Erstellung nicht blockieren)
    const orbitRow = await p.request()
      .input('id', sql.NVarChar, domainId)
      .query('SELECT name FROM TaskDomain WHERE id = @id');
    const orbitName = orbitRow.recordset[0]?.name || 'Orbit';
    const actorName = await resolveActorName(p, req.user.userId, req.user.email);
    await emitOrbitEvent(p, {
      orbitId: domainId, actorUserId: req.user.userId, actorName,
      type: 'sphere_created', sphereId: id, sphereTitle: title, orbitName,
      body: `${actorName} hat „${title}" zu „${orbitName}" hinzugefügt.`,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/done', requireAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();
    const taskResult = await p.request()
      .input('id', sql.NVarChar, id)
      .query('SELECT * FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const task = taskResult.recordset[0];

    // Zugriffsprüfung
    const access = await p.request()
      .input('orbitId', sql.NVarChar, task.domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    const now = new Date();
    await p.request()
      .input('id',          sql.NVarChar,  id)
      .input('completedAt', sql.DateTime2, now)
      .query("UPDATE Task SET status = 'done', completedAt = @completedAt WHERE id = @id");

    const nextTask = await createNextCapsuleIfNeeded(p, task);
    res.json({ success: true, nextTask: nextTask || null });

    const orbitRow = await p.request()
      .input('id', sql.NVarChar, task.domainId)
      .query('SELECT name FROM TaskDomain WHERE id = @id');
    const orbitName = orbitRow.recordset[0]?.name || 'Orbit';
    const actorName = await resolveActorName(p, req.user.userId, req.user.email);
    await emitOrbitEvent(p, {
      orbitId: task.domainId, actorUserId: req.user.userId, actorName,
      type: 'sphere_landed', sphereId: id, sphereTitle: task.title, orbitName,
      body: `${actorName} hat „${task.title}" in „${orbitName}" erledigt.`,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/start', requireAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    const result = await p.request()
      .input('id', sql.NVarChar, id)
      .query("UPDATE Task SET status = 'inProgress' WHERE id = @id AND status = 'open'");
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Task not found or not open' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/reopen', requireAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    await p.request()
      .input('id', sql.NVarChar, id)
      .query("UPDATE Task SET status = 'open', completedAt = NULL WHERE id = @id");
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/title', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { title } = req.body;
  if (!title || !title.trim()) return res.status(400).json({ error: 'Titel darf nicht leer sein' });
  if (rejectIfTooLong(res, 'Der Titel', title, FIELD_LIMITS.sphereTitle)) return;
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    const result = await p.request()
      .input('id',    sql.NVarChar, id)
      .input('title', sql.NVarChar, title.trim())
      .query('UPDATE Task SET title = @title WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Task not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/description', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { description } = req.body;
  if (rejectIfTooLong(res, 'Die Beschreibung', description, FIELD_LIMITS.sphereDescription)) return;
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    const result = await p.request()
      .input('id',          sql.NVarChar, id)
      .input('description', sql.NVarChar, description ?? '')
      .query('UPDATE Task SET description = @description WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Task not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/reminder', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { reminderAt } = req.body;
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    const result = await p.request()
      .input('id',         sql.NVarChar,  id)
      .input('reminderAt', sql.DateTime2, reminderAt ? new Date(reminderAt) : null)
      .query('UPDATE Task SET reminderAt = @reminderAt, reminderEmailSentAt = NULL WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Task not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/domain', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { domainId } = req.body;
  if (!domainId) return res.status(400).json({ error: 'domainId required' });
  try {
    const p = await getPool();
    // Zugriff auf Quell-Task und Ziel-Orbit prüfen
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });

    const sourceAccess = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    const targetAccess = await p.request()
      .input('orbitId', sql.NVarChar, domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (sourceAccess.recordset.length === 0 || targetAccess.recordset.length === 0) {
      return res.status(403).json({ error: 'Kein Zugriff' });
    }

    const result = await p.request()
      .input('id',       sql.NVarChar, id)
      .input('domainId', sql.NVarChar, domainId)
      .query('UPDATE Task SET domainId = @domainId WHERE id = @id');
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Task not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Sphere einer Person zuweisen (oder Zuweisung aufheben mit memberId = null).
// Die Person muss aktives Mitglied (Pilot/Co-Pilot) DESSELBEN Orbits sein.
app.patch('/tasks/:id/assignee', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { memberId } = req.body;
  try {
    const p = await getPool();

    const taskResult = await p.request()
      .input('id', sql.NVarChar, id)
      .query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const orbitId = taskResult.recordset[0].domainId;

    // Aufrufer muss aktives Mitglied des Orbits sein
    const access = await p.request()
      .input('orbitId', sql.NVarChar, orbitId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    // Wenn zugewiesen: Zielperson muss aktives Mitglied genau dieses Orbits sein
    if (memberId) {
      const member = await p.request()
        .input('memberId', sql.NVarChar, memberId)
        .input('orbitId',  sql.NVarChar, orbitId)
        .query(`SELECT id FROM OrbitMember WHERE id = @memberId AND orbitId = @orbitId AND status = 'active'`);
      if (member.recordset.length === 0) {
        return res.status(400).json({ error: 'Person ist kein aktives Mitglied dieses Orbits' });
      }
    }

    await p.request()
      .input('id',       sql.NVarChar, id)
      .input('memberId', sql.NVarChar, memberId || null)
      .query('UPDATE Task SET assignedToMemberId = @memberId WHERE id = @id');
    res.json({ success: true });

    // Nur bei aktiver Zuweisung benachrichtigen (nicht beim Aufheben).
    if (memberId) {
      const info = await p.request()
        .input('taskId',   sql.NVarChar, id)
        .input('memberId', sql.NVarChar, memberId)
        .query(`SELECT t.title AS title, d.name AS orbitName,
                       COALESCE(au.displayName, om.email) AS assigneeName
                FROM Task t
                JOIN TaskDomain d ON d.id = t.domainId
                LEFT JOIN OrbitMember om ON om.id = @memberId
                LEFT JOIN AppUser au ON au.id = om.userId
                WHERE t.id = @taskId`);
      const row = info.recordset[0];
      if (row) {
        const actorName = await resolveActorName(p, req.user.userId, req.user.email);
        await emitOrbitEvent(p, {
          orbitId, actorUserId: req.user.userId, actorName,
          type: 'sphere_assigned', sphereId: id, sphereTitle: row.title, orbitName: row.orbitName,
          body: `${actorName} hat „${row.title}" an ${row.assigneeName || 'jemanden'} übergeben.`,
        });
      }
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.patch('/tasks/:id/schedule', requireAuth, async (req, res) => {
  const { id } = req.params;
  const { startDate, dueDate, recurrenceFrequency, recurrenceInterval } = req.body;
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    const setClauses = [];
    const req2 = p.request().input('id', sql.NVarChar, id);
    if (startDate !== undefined) {
      setClauses.push('startDate = @startDate');
      req2.input('startDate', sql.DateTime2, startDate ? new Date(startDate) : null);
    }
    if (dueDate !== undefined) {
      setClauses.push('dueDate = @dueDate');
      req2.input('dueDate', sql.DateTime2, dueDate ? new Date(dueDate) : null);
    }
    if (recurrenceFrequency !== undefined) {
      setClauses.push('recurrenceFrequency = @recurrenceFrequency');
      req2.input('recurrenceFrequency', sql.NVarChar, recurrenceFrequency);
    }
    if (recurrenceInterval !== undefined) {
      setClauses.push('recurrenceInterval = @recurrenceInterval');
      req2.input('recurrenceInterval', sql.Int, recurrenceInterval);
    }
    if (setClauses.length === 0) return res.status(400).json({ error: 'Nothing to update' });

    const result = await req2.query(`UPDATE Task SET ${setClauses.join(', ')} WHERE id = @id`);
    if (result.rowsAffected[0] === 0) return res.status(404).json({ error: 'Task not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/tasks/:id', requireAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, id).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

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

app.get('/logs/:taskId', requireAuth, async (req, res) => {
  const { taskId } = req.params;
  try {
    const p = await getPool();
    // Zugriffsprüfung via Task → Orbit
    const taskResult = await p.request().input('id', sql.NVarChar, taskId).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    const result = await p.request()
      .input('taskId', sql.NVarChar, taskId)
      .query(`SELECT tle.id, tle.taskId, COALESCE(au.displayName, tle.[user]) AS [user], tle.[text], tle.timestamp
              FROM TaskLogEntry tle
              LEFT JOIN AppUser au ON au.email = tle.[user]
              WHERE tle.taskId = @taskId ORDER BY tle.timestamp DESC`);
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/logs', requireAuth, async (req, res) => {
  const { taskId, text } = req.body;
  if (rejectIfTooLong(res, 'Der Eintrag', text, FIELD_LIMITS.logText)) return;
  const id  = uuidv4();
  const now = new Date();
  try {
    const p = await getPool();
    const taskResult = await p.request().input('id', sql.NVarChar, taskId).query('SELECT domainId FROM Task WHERE id = @id');
    if (taskResult.recordset.length === 0) return res.status(404).json({ error: 'Task not found' });
    const access = await p.request()
      .input('orbitId', sql.NVarChar, taskResult.recordset[0].domainId)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`SELECT id FROM OrbitMember WHERE orbitId = @orbitId AND userId = @userId AND status = 'active'`);
    if (access.recordset.length === 0) return res.status(403).json({ error: 'Kein Zugriff' });

    // Klarname immer frisch aus AppUser holen – der displayName im JWT kann
    // veraltet sein (z. B. erst nach dem Login gesetzt). E-Mail nur als
    // Fallback, wenn für das Konto wirklich kein Name hinterlegt ist.
    const userRow = await p.request()
      .input('userId', sql.NVarChar, req.user.userId)
      .query('SELECT displayName, email FROM AppUser WHERE id = @userId');
    const u = userRow.recordset[0] || {};
    const userLabel = (u.displayName && u.displayName.trim()) || u.email || req.user.email;

    const result = await p.request()
      .input('id',        sql.NVarChar,  id)
      .input('taskId',    sql.NVarChar,  taskId)
      .input('user',      sql.NVarChar,  userLabel)
      .input('text',      sql.NVarChar,  text)
      .input('timestamp', sql.DateTime2, now)
      .query(`INSERT INTO TaskLogEntry (id, taskId, [user], [text], timestamp)
              OUTPUT INSERTED.*
              VALUES (@id, @taskId, @user, @text, @timestamp)`);

    const update = await p.request()
      .input('taskId', sql.NVarChar, taskId)
      .query("UPDATE Task SET status = 'inProgress' WHERE id = @taskId AND status = 'open'");
    const taskStatus = update.rowsAffected[0] > 0 ? 'inProgress' : null;

    res.json({ ...result.recordset[0], user: userLabel, taskStatus });

    const orbitId = taskResult.recordset[0].domainId;
    const titleRow = await p.request()
      .input('taskId', sql.NVarChar, taskId)
      .query(`SELECT t.title AS title, d.name AS orbitName
              FROM Task t JOIN TaskDomain d ON d.id = t.domainId WHERE t.id = @taskId`);
    const tr = titleRow.recordset[0] || {};
    await emitOrbitEvent(p, {
      orbitId, actorUserId: req.user.userId, actorName: userLabel,
      type: 'log_added', sphereId: taskId, sphereTitle: tr.title, orbitName: tr.orbitName,
      body: `${userLabel} hat einen Eintrag zu „${tr.title || 'einer Sphere'}" hinzugefügt.`,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Devices (Push-Token-Registrierung)
// -----------------------------------------------------------------------

app.post('/devices', requireAuth, async (req, res) => {
  const { token, platform } = req.body;
  if (!token) return res.status(400).json({ error: 'token erforderlich' });
  try {
    const p = await getPool();
    // Upsert: existiert das Token bereits, Besitzer + lastSeenAt aktualisieren.
    const existing = await p.request()
      .input('token', sql.NVarChar, token)
      .query('SELECT id FROM DeviceToken WHERE token = @token');
    if (existing.recordset.length > 0) {
      await p.request()
        .input('token',    sql.NVarChar,  token)
        .input('userId',   sql.NVarChar,  req.user.userId)
        .input('platform', sql.NVarChar,  platform || 'unknown')
        .query(`UPDATE DeviceToken
                SET userId = @userId, platform = @platform, lastSeenAt = GETUTCDATE()
                WHERE token = @token`);
    } else {
      await p.request()
        .input('id',       sql.NVarChar, uuidv4())
        .input('userId',   sql.NVarChar, req.user.userId)
        .input('token',    sql.NVarChar, token)
        .input('platform', sql.NVarChar, platform || 'unknown')
        .query(`INSERT INTO DeviceToken (id, userId, token, platform)
                VALUES (@id, @userId, @token, @platform)`);
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/devices', requireAuth, async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'token erforderlich' });
  try {
    const p = await getPool();
    await p.request()
      .input('token',  sql.NVarChar, token)
      .input('userId', sql.NVarChar, req.user.userId)
      .query('DELETE FROM DeviceToken WHERE token = @token AND userId = @userId');
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Events (Team-Aktivitäten-Feed)
// -----------------------------------------------------------------------

app.get('/events', requireAuth, async (req, res) => {
  const { since } = req.query;
  try {
    const p = await getPool();
    const orbitIds = await getUserOrbitIds(p, req.user.userId);
    if (orbitIds.length === 0) return res.json([]);

    const placeholders = orbitIds.map((_, i) => `@oid${i}`).join(',');
    const request = p.request().input('actor', sql.NVarChar, req.user.userId);
    orbitIds.forEach((id, i) => request.input(`oid${i}`, sql.NVarChar, id));

    let sinceClause = '';
    if (since) {
      request.input('since', sql.DateTime2, new Date(since));
      sinceClause = 'AND createdAt > @since';
    }

    const result = await request.query(
      `SELECT TOP 50 e.id, e.orbitId, e.actorUserId, e.actorName, e.type,
              e.sphereId, e.sphereTitle, e.orbitName, e.body, e.createdAt
       FROM OrbitEvent e
       WHERE e.orbitId IN (${placeholders})
         AND (e.actorUserId IS NULL OR e.actorUserId <> @actor)
         AND NOT EXISTS (
           SELECT 1 FROM OrbitEventDismissed d
           WHERE d.eventId = e.id AND d.userId = @actor
         )
         ${sinceClause.replace('createdAt', 'e.createdAt')}
       ORDER BY e.createdAt DESC`
    );
    res.json(result.recordset);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Eine Meldung fuer den eigenen Account ausblenden. Die OrbitEvent-Zeile
// bleibt bestehen - andere Mitglieder des Orbits sehen ihre Meldung weiter.
app.delete('/events/:id', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    // Mehrfaches Ausblenden darf nicht am Primaerschluessel scheitern.
    await p.request()
      .input('eventId', sql.NVarChar, req.params.id)
      .input('userId',  sql.NVarChar, req.user.userId)
      .query(`IF NOT EXISTS (SELECT 1 FROM OrbitEventDismissed
                             WHERE eventId = @eventId AND userId = @userId)
              INSERT INTO OrbitEventDismissed (eventId, userId)
              VALUES (@eventId, @userId)`);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Alle derzeit sichtbaren Meldungen auf einmal ausblenden.
app.delete('/events', requireAuth, async (req, res) => {
  try {
    const p = await getPool();
    const orbitIds = await getUserOrbitIds(p, req.user.userId);
    if (orbitIds.length === 0) return res.json({ success: true, dismissed: 0 });

    const placeholders = orbitIds.map((_, i) => `@oid${i}`).join(',');
    const request = p.request().input('userId', sql.NVarChar, req.user.userId);
    orbitIds.forEach((id, i) => request.input(`oid${i}`, sql.NVarChar, id));

    const result = await request.query(
      `INSERT INTO OrbitEventDismissed (eventId, userId)
       SELECT e.id, @userId
       FROM OrbitEvent e
       WHERE e.orbitId IN (${placeholders})
         AND (e.actorUserId IS NULL OR e.actorUserId <> @userId)
         AND NOT EXISTS (
           SELECT 1 FROM OrbitEventDismissed d
           WHERE d.eventId = e.id AND d.userId = @userId
         )`
    );
    res.json({ success: true, dismissed: result.rowsAffected[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------
// Scheduler
// -----------------------------------------------------------------------

async function runScheduler() {
  const now = new Date();
  console.log(`Scheduler: run at ${now.toISOString()}`);
  try {
    const p = await getPool();

    // 1. Wiederkehrende Tasks: nächste Kapsel anlegen wenn fällig
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

    // 2. Erinnerungsmails: an alle aktiven Mitglieder des Orbits senden
    const dueReminders = await p.request()
      .input('now', sql.DateTime2, now)
      .query(`SELECT t.*, d.name AS domainName
              FROM Task t
              JOIN TaskDomain d ON t.domainId = d.id
              WHERE t.reminderAt IS NOT NULL
                AND t.reminderAt <= @now
                AND t.reminderEmailSentAt IS NULL
                AND t.status != 'done'`);

    console.log(`Scheduler: ${dueReminders.recordset.length} due reminder(s) found`);
    for (const task of dueReminders.recordset) {
      // E-Mail-Adressen aller aktiven Mitglieder des Orbits
      const membersResult = await p.request()
        .input('orbitId', sql.NVarChar, task.domainId)
        .query(`SELECT email FROM OrbitMember WHERE orbitId = @orbitId AND status = 'active'`);
      const emails = membersResult.recordset.map(r => r.email).filter(Boolean);

      console.log(`Scheduler: task ${task.id} ("${task.title}"), reminderAt=${task.reminderAt}, recipients=${emails.length}`);
      if (emails.length > 0) {
        try {
          await sendReminderEmail(emails, task, task.domainName);
          console.log(`Scheduler: reminder sent to ${emails.join(', ')}`);
        } catch (mailErr) {
          console.error(`Scheduler: e-mail failed for task ${task.id}:`, mailErr.message);
        }
      }

      // Zusätzlich als Push-Popup an alle aktiven Mitglieder (kein actor → niemand
      // wird ausgeschlossen, Erinnerung ist zeitbasiert, nicht personenbezogen).
      // Roter Wecker ⏰ am Anfang – analog zur Erinnerungs-Mail.
      await emitOrbitEvent(p, {
        orbitId: task.domainId, actorUserId: null, actorName: null,
        type: 'reminder', sphereId: task.id, sphereTitle: task.title, orbitName: task.domainName,
        body: `⏰ Erinnerung: ${task.title}`,
      });

      await p.request()
        .input('id',  sql.NVarChar,  task.id)
        .input('now', sql.DateTime2, now)
        .query('UPDATE Task SET reminderEmailSentAt = @now WHERE id = @id');
    }

    // 3. Einfache Listen aufraeumen: gelandete Positionen werden 24 Stunden nach
    //    dem Abhaken endgueltig geloescht, damit eine Einkaufsliste dauerhaft
    //    klein bleibt. Innerhalb dieser Frist laesst sich eine Position aus dem
    //    Archiv zurueckholen. Betrifft ausschliesslich Orbits mit
    //    isShoppingList = 1 – normale Orbits behalten ihr Archiv unveraendert.
    const cutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const stale = await p.request()
      .input('cutoff', sql.DateTime2, cutoff)
      .query(`SELECT t.id
              FROM Task t
              JOIN TaskDomain d ON t.domainId = d.id
              WHERE d.isShoppingList = 1
                AND t.status = 'done'
                AND t.completedAt IS NOT NULL
                AND t.completedAt <= @cutoff`);

    for (const row of stale.recordset) {
      try {
        // Verlaufseintraege zuerst – der Fremdschluessel verhindert sonst das Loeschen.
        await p.request()
          .input('taskId', sql.NVarChar, row.id)
          .query('DELETE FROM TaskLogEntry WHERE taskId = @taskId');
        await p.request()
          .input('id', sql.NVarChar, row.id)
          .query('DELETE FROM Task WHERE id = @id');
      } catch (delErr) {
        console.error(`Scheduler: cleanup failed for task ${row.id}:`, delErr.message);
      }
    }
    if (stale.recordset.length > 0) {
      console.log(`Scheduler: ${stale.recordset.length} erledigte Listenposition(en) geloescht`);
    }
  } catch (err) {
    console.error('Scheduler error:', err.message);
  }
}

setInterval(runScheduler, 5 * 60 * 1000);

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
  runScheduler();
});
