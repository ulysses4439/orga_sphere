// Idempotenter Runner für Migration v9 (DeviceToken, OrbitEvent).
// Nutzt dieselben SQL_*-Zugangsdaten aus backend/.env wie der Server.
// Ausführen aus dem backend-Ordner:  node db/run_v9.js
require('dotenv').config();
const sql = require('mssql');

const config = {
  user: process.env.SQL_USER,
  password: process.env.SQL_PASSWORD,
  server: process.env.SQL_SERVER,
  database: process.env.SQL_DATABASE,
  options: { encrypt: true, trustServerCertificate: false },
};

async function tableExists(pool, name) {
  const r = await pool.request()
    .input('name', sql.NVarChar, name)
    .query('SELECT OBJECT_ID(@name) AS id');
  return r.recordset[0].id !== null;
}

(async () => {
  let pool;
  try {
    console.log(`Verbinde mit ${config.server} / ${config.database} ...`);
    pool = await sql.connect(config);

    if (await tableExists(pool, 'DeviceToken')) {
      console.log('→ Tabelle DeviceToken existiert bereits.');
    } else {
      await pool.request().query(`
        CREATE TABLE DeviceToken (
          id         NVARCHAR(100) NOT NULL PRIMARY KEY,
          userId     NVARCHAR(100) NOT NULL,
          token      NVARCHAR(500) NOT NULL,
          platform   NVARCHAR(20)  NOT NULL,
          createdAt  DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
          lastSeenAt DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
          CONSTRAINT FK_DeviceToken_User FOREIGN KEY (userId) REFERENCES AppUser(id),
          CONSTRAINT UQ_DeviceToken_Token UNIQUE (token)
        )`);
      console.log('✓ Tabelle DeviceToken angelegt.');
    }

    if (await tableExists(pool, 'OrbitEvent')) {
      console.log('→ Tabelle OrbitEvent existiert bereits.');
    } else {
      await pool.request().query(`
        CREATE TABLE OrbitEvent (
          id          NVARCHAR(100)  NOT NULL PRIMARY KEY,
          orbitId     NVARCHAR(100)  NOT NULL,
          actorUserId NVARCHAR(100)  NULL,
          actorName   NVARCHAR(200)  NULL,
          type        NVARCHAR(30)   NOT NULL,
          sphereId    NVARCHAR(100)  NULL,
          sphereTitle NVARCHAR(200)  NULL,
          orbitName   NVARCHAR(200)  NULL,
          body        NVARCHAR(1000) NOT NULL,
          createdAt   DATETIME2      NOT NULL DEFAULT GETUTCDATE()
        )`);
      await pool.request().query(
        'CREATE INDEX IX_OrbitEvent_Orbit_CreatedAt ON OrbitEvent (orbitId, createdAt DESC)');
      console.log('✓ Tabelle OrbitEvent (+ Index) angelegt.');
    }

    console.log('Fertig.');
    process.exit(0);
  } catch (e) {
    console.error('FEHLER:', e.message);
    if (/firewall|not allowed to access/i.test(e.message)) {
      console.error('\nHinweis: Die Azure-SQL-Firewall blockiert deine aktuelle IP.');
      console.error('Entweder deine IP im Azure-Portal (SQL-Server → Networking) freigeben');
      console.error('oder die Migration über den Query-Editor im Azure-Portal ausführen.');
    }
    process.exit(1);
  } finally {
    if (pool) try { await pool.close(); } catch (_) {}
  }
})();
