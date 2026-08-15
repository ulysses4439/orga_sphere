#!/usr/bin/env node
/* ---------------------------------------------------------------------------
 * Selbsttest fuer Dateianhaenge an Spheres.
 *
 * Prueft den kompletten Weg gegen den LAUFENDEN Server: anmelden, hochladen,
 * auflisten, einem Verlaufseintrag zuordnen, wieder abrufen, loeschen. Und zum
 * Schluss, ob beim Loeschen einer Sphere auch ihre Anhaenge verschwinden.
 *
 * Der Test legt dafuer einen eigenen Orbit an und raeumt ihn am Ende wieder
 * ab - an euren echten Daten wird nichts angefasst. Bricht er vorzeitig ab,
 * bleibt ein Orbit "OrgaSphere Selbsttest ..." stehen, den man von Hand
 * loeschen kann.
 *
 * Aufruf (im Repo-Wurzelverzeichnis):
 *   node tools/check_attachments.js
 *
 * Fragt dann nach E-Mail und Passwort. Alternativ vorab setzbar:
 *   --email x  --passwort y  --url https://...  --datei C:\pfad\bild.png
 * oder ueber die Umgebungsvariablen ORGA_EMAIL / ORGA_PASSWORD.
 *
 * Mit --datei wird eine eigene Datei statt des eingebauten Testbildes
 * hochgeladen. Die zurueckgeholte Fassung landet dann im aktuellen
 * Verzeichnis, sodass man sie oeffnen und vergleichen kann.
 *
 * Ausgabe bewusst ohne Umlaute und Sonderzeichen - die Windows-Konsole stellt
 * sie je nach Einstellung falsch dar.
 * ------------------------------------------------------------------------- */

const fs = require('fs');
const path = require('path');
const readline = require('readline');

const STANDARD_URL =
  'https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net';

// Ein gueltiges 1x1-PNG. Dient als Testbild, wenn keine eigene Datei angegeben
// wurde - die ersten Bytes reichen dem Server, um es als Bild zu erkennen.
const TESTBILD = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64'
);

const MIME_NACH_ENDUNG = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  gif: 'image/gif',
  webp: 'image/webp',
  bmp: 'image/bmp',
};

// ---------------------------------------------------------------------------
// Argumente und Eingabe
// ---------------------------------------------------------------------------

function argument(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function frage(text, versteckt = false) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.stdoutMuted = false;
    rl._writeToOutput = function (s) {
      if (rl.stdoutMuted) rl.output.write('*');
      else rl.output.write(s);
    };
    rl.question(text, (antwort) => {
      rl.close();
      if (versteckt) process.stdout.write('\n');
      resolve(antwort.trim());
    });
    rl.stdoutMuted = versteckt;
  });
}

// ---------------------------------------------------------------------------
// Ergebnisprotokoll
// ---------------------------------------------------------------------------

let bestanden = 0;
let gescheitert = 0;

function ok(text, zusatz) {
  bestanden++;
  console.log(`  [OK]     ${text}${zusatz ? '  (' + zusatz + ')' : ''}`);
}

function fehler(text, grund) {
  gescheitert++;
  console.log(`  [FEHLER] ${text}`);
  if (grund) console.log(`           ${grund}`);
}

// ---------------------------------------------------------------------------
// HTTP-Hilfen
// ---------------------------------------------------------------------------

let basisUrl = argument('url') || process.env.ORGA_API || STANDARD_URL;
let token = null;

async function api(pfad, optionen = {}) {
  const kopf = { ...(optionen.headers || {}) };
  if (token) kopf.Authorization = `Bearer ${token}`;
  // FormData setzt seinen Content-Type samt Trennmarke selbst - da darf nichts
  // von Hand hineingeschrieben werden.
  if (optionen.json !== undefined) {
    kopf['Content-Type'] = 'application/json';
  }
  const antwort = await fetch(basisUrl + pfad, {
    method: optionen.method || 'GET',
    headers: kopf,
    body: optionen.json !== undefined ? JSON.stringify(optionen.json) : optionen.body,
  });
  return antwort;
}

async function alsJson(antwort) {
  const text = await antwort.text();
  try {
    return JSON.parse(text);
  } catch {
    return { error: text.slice(0, 200) };
  }
}

// Bricht mit klarer Meldung ab, wenn ein Schritt scheitert, ohne den der Rest
// keinen Sinn ergibt.
async function mussKlappen(antwort, was) {
  if (antwort.ok) return alsJson(antwort);
  const daten = await alsJson(antwort);
  throw new Error(`${was} fehlgeschlagen (HTTP ${antwort.status}): ${daten.error || 'keine Angabe'}`);
}

// ---------------------------------------------------------------------------
// Ablauf
// ---------------------------------------------------------------------------

async function main() {
  console.log('');
  console.log('OrgaSphere - Selbsttest Dateianhaenge');
  console.log('Server: ' + basisUrl);
  console.log('');

  const email = argument('email') || process.env.ORGA_EMAIL || (await frage('E-Mail: '));
  const passwort =
    argument('passwort') || process.env.ORGA_PASSWORD || (await frage('Passwort: ', true));

  // Eigene Datei oder eingebautes Testbild
  const eigeneDatei = argument('datei');
  let bildInhalt = TESTBILD;
  let bildName = 'selbsttest.png';
  let bildTyp = 'image/png';
  if (eigeneDatei) {
    if (!fs.existsSync(eigeneDatei)) throw new Error(`Datei nicht gefunden: ${eigeneDatei}`);
    bildInhalt = fs.readFileSync(eigeneDatei);
    bildName = path.basename(eigeneDatei);
    const endung = path.extname(bildName).slice(1).toLowerCase();
    bildTyp = MIME_NACH_ENDUNG[endung] || 'application/octet-stream';
    console.log(`\nEigene Datei: ${bildName} (${(bildInhalt.length / 1024).toFixed(1)} KB)`);
  }

  let orbitId = null;

  try {
    // -- 1. Anmelden ------------------------------------------------------
    console.log('\n1. Anmelden');
    const login = await mussKlappen(
      await api('/auth/login', { method: 'POST', json: { email, password: passwort } }),
      'Anmeldung'
    );
    token = login.token;
    if (!token) throw new Error('Server hat kein Token geliefert');
    ok('angemeldet als ' + email);

    // -- 2. Testumgebung anlegen -----------------------------------------
    console.log('\n2. Testumgebung anlegen');
    const orbit = await mussKlappen(
      await api('/domains', {
        method: 'POST',
        json: {
          name: 'OrgaSphere Selbsttest ' + new Date().toISOString().slice(11, 19),
          description: 'Wird vom Selbsttest automatisch wieder geloescht.',
          color: '#F5F5F5',
        },
      }),
      'Orbit anlegen'
    );
    orbitId = orbit.id;
    ok('Orbit angelegt');

    const sphere = await mussKlappen(
      await api('/tasks', {
        method: 'POST',
        json: {
          domainId: orbitId,
          title: 'Testsphere fuer Anhaenge',
          description: '',
          startDate: new Date().toISOString(),
        },
      }),
      'Sphere anlegen'
    );
    ok('Sphere angelegt');

    // -- 3. Hochladen -----------------------------------------------------
    console.log('\n3. Hochladen');

    const bildForm = new FormData();
    bildForm.append('file', new Blob([bildInhalt], { type: bildTyp }), bildName);
    const bildAntwort = await api(`/tasks/${sphere.id}/attachments`, {
      method: 'POST',
      body: bildForm,
    });
    const bild = await mussKlappen(bildAntwort, 'Bild hochladen');
    if (bild.isImage) ok('Bild hochgeladen und als Bild erkannt', bild.fileName);
    else fehler('Bild wurde NICHT als Bild erkannt', 'isImage war ' + bild.isImage);

    const textInhalt = Buffer.from(
      'Das ist eine gewoehnliche Textdatei aus dem Selbsttest.\n',
      'utf8'
    );
    const textForm = new FormData();
    textForm.append('file', new Blob([textInhalt], { type: 'text/plain' }), 'notiz.txt');
    const datei = await mussKlappen(
      await api(`/tasks/${sphere.id}/attachments`, { method: 'POST', body: textForm }),
      'Textdatei hochladen'
    );
    if (!datei.isImage) ok('Textdatei hochgeladen und korrekt NICHT als Bild gewertet');
    else fehler('Textdatei wurde faelschlich als Bild gewertet');

    // -- 4. Auflisten -----------------------------------------------------
    console.log('\n4. Auflisten');
    const liste = await mussKlappen(
      await api(`/tasks/${sphere.id}/attachments`),
      'Anhaenge auflisten'
    );
    if (liste.length === 2) ok('beide Anhaenge werden gelistet');
    else fehler('falsche Anzahl in der Liste', 'erwartet 2, bekommen ' + liste.length);

    if (liste.every((a) => a.logEntryId === null)) {
      ok('beide warten korrekt auf ihren Verlaufseintrag');
    } else {
      fehler('Anhang war schon einem Eintrag zugeordnet');
    }

    // -- 5. Eintrag mit Anhaengen -----------------------------------------
    console.log('\n5. Verlaufseintrag mit Anhaengen');
    const eintrag = await mussKlappen(
      await api('/logs', {
        method: 'POST',
        json: {
          taskId: sphere.id,
          text: 'Eintrag aus dem Selbsttest',
          attachmentIds: [bild.id, datei.id],
        },
      }),
      'Verlaufseintrag anlegen'
    );
    if (eintrag.linkedAttachments === 2) ok('beide Anhaenge dem Eintrag zugeordnet');
    else fehler('Zuordnung unvollstaendig', 'zugeordnet: ' + eintrag.linkedAttachments);

    // -- 6. Wieder abrufen ------------------------------------------------
    console.log('\n6. Wieder abrufen');
    const abruf = await api(`/attachments/${bild.id}/content`);
    if (!abruf.ok) {
      fehler('Bild konnte nicht abgerufen werden', 'HTTP ' + abruf.status);
    } else {
      const zurueck = Buffer.from(await abruf.arrayBuffer());
      if (zurueck.equals(bildInhalt)) {
        ok('Bild kam Byte fuer Byte unveraendert zurueck', zurueck.length + ' Bytes');
      } else {
        fehler('Bild kam veraendert zurueck', `${bildInhalt.length} Bytes hin, ${zurueck.length} zurueck`);
      }
      if (eigeneDatei) {
        const zielName = path.basename(bildName, path.extname(bildName)) +
          '_zurueckgeholt' + path.extname(bildName);
        fs.writeFileSync(zielName, zurueck);
        console.log(`           -> zum Ansehen gespeichert als: ${path.resolve(zielName)}`);
      }
      const typ = abruf.headers.get('content-type') || '';
      if (typ.startsWith('image/')) ok('Server meldet den richtigen Dateityp', typ);
      else fehler('falscher Dateityp gemeldet', typ);
    }

    const dateiAbruf = await api(`/attachments/${datei.id}/content`);
    const disposition = dateiAbruf.headers.get('content-disposition') || '';
    if (disposition.startsWith('attachment')) {
      ok('Textdatei wird zum Speichern angeboten statt angezeigt');
    } else {
      fehler('Textdatei wurde nicht zum Speichern angeboten', disposition || 'kein Header');
    }

    // -- 7. Groessengrenze ------------------------------------------------
    console.log('\n7. Groessengrenze (laedt 11 MB hoch, dauert einen Moment)');
    try {
      const zuGross = new FormData();
      zuGross.append('file', new Blob([Buffer.alloc(11 * 1024 * 1024)]), 'zu_gross.bin');
      const grenzAntwort = await api(`/tasks/${sphere.id}/attachments`, {
        method: 'POST',
        body: zuGross,
      });
      if (grenzAntwort.status === 400) {
        const daten = await alsJson(grenzAntwort);
        ok('zu grosse Datei abgewiesen', daten.error);
      } else {
        fehler('zu grosse Datei wurde NICHT abgewiesen', 'HTTP ' + grenzAntwort.status);
      }
    } catch (err) {
      // Der Server bricht die Uebertragung teils ab, sobald die Grenze
      // ueberschritten ist - dann kommt statt einer Antwort ein
      // Verbindungsfehler. Abgewiesen wurde die Datei so oder so.
      ok('zu grosse Datei abgewiesen', 'Verbindung beendet: ' + err.message);
    }

    // -- 8. Einzelnen Anhang loeschen -------------------------------------
    console.log('\n8. Loeschen');
    await mussKlappen(
      await api(`/attachments/${datei.id}`, { method: 'DELETE' }),
      'Anhang loeschen'
    );
    const nachLoeschen = await api(`/attachments/${datei.id}/content`);
    if (nachLoeschen.status === 404) ok('geloeschter Anhang ist nicht mehr abrufbar');
    else fehler('geloeschter Anhang noch erreichbar', 'HTTP ' + nachLoeschen.status);

    // -- 9. Aufraeumen beim Loeschen der Sphere ---------------------------
    console.log('\n9. Aufraeumen beim Loeschen des Orbits');
    await mussKlappen(await api(`/domains/${orbitId}`, { method: 'DELETE' }), 'Orbit loeschen');
    orbitId = null;
    const nachOrbitLoeschen = await api(`/attachments/${bild.id}/content`);
    if (nachOrbitLoeschen.status === 404) {
      ok('Anhaenge der geloeschten Sphere sind mit verschwunden');
    } else {
      fehler('Anhang lebt nach dem Loeschen weiter', 'HTTP ' + nachOrbitLoeschen.status);
    }
  } finally {
    // Falls der Test unterwegs abbricht, den Testorbit trotzdem wegraeumen.
    if (orbitId) {
      try {
        await api(`/domains/${orbitId}`, { method: 'DELETE' });
        console.log('\n(Testorbit wurde aufgeraeumt.)');
      } catch {
        console.log(`\nACHTUNG: Testorbit ${orbitId} konnte nicht geloescht werden.`);
      }
    }
  }

  console.log('');
  console.log('----------------------------------------');
  console.log(`Bestanden: ${bestanden}   Gescheitert: ${gescheitert}`);
  console.log('----------------------------------------');
  if (gescheitert === 0) {
    console.log('Alles in Ordnung. Der Weg App -> Server -> Speicher steht.');
    console.log('Zur Gegenprobe: Der Container "sphere-attachments" im Azure-Portal');
    console.log('sollte jetzt wieder leer sein - der Test raeumt hinter sich auf.');
  }
  console.log('');
  process.exit(gescheitert === 0 ? 0 : 1);
}

main().catch((err) => {
  console.log('');
  console.log('ABBRUCH: ' + err.message);
  console.log('');
  process.exit(1);
});
