// Idempotenter Runner für Migration v8 (assignedToMemberId an Task).
// Nutzt dieselben SQL_*-Zugangsdaten aus backend/.env wie der Server.
// Ausführen aus dem backend-Ordner:  node db/run_v8.js
require('dotenv').config();
const sql = require('mssql');

const config = {
  user: process.env.SQL_USER,
  password: process.env.SQL_PASSWORD,
  server: process.env.SQL_SERVER,
  database: process.env.SQL_DATABASE,
  options: { encrypt: true, trustServerCertificate: false },
};

(async () => {
  let pool;
  try {
    console.log(`Verbinde mit ${config.server} / ${config.database} ...`);
    pool = await sql.connect(config);

    const before = await pool.request()
      .query("SELECT COL_LENGTH('Task','assignedToMemberId') AS len");
    if (before.recordset[0].len !== null) {
      console.log('→ Spalte assignedToMemberId existiert bereits. Nichts zu tun.');
    } else {
      await pool.request()
        .query('ALTER TABLE Task ADD assignedToMemberId NVARCHAR(100) NULL');
      console.log('✓ Spalte assignedToMemberId hinzugefügt.');
    }

    const after = await pool.request()
      .query("SELECT COL_LENGTH('Task','assignedToMemberId') AS len");
    console.log('Verifikation: COL_LENGTH =', after.recordset[0].len, '(nicht-null = vorhanden)');
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
