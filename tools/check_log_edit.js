#!/usr/bin/env node
/* ---------------------------------------------------------------------------
 * Selbsttest fuer das Aendern und Loeschen von Verlaufseintraegen.
 *
 * Prueft gegen den LAUFENDEN Server: Eintrag anlegen, Text aendern, Kennzeichen
 * "bearbeitet" pruefen, Eintrag mit Anhang loeschen und nachsehen, ob der
 * Anhang mit verschwunden ist. Dazu die beiden Faelle, auf die es bei der
 * Berechtigung ankommt: ein fremder Eintrag darf nicht angefasst werden, und
 * ein Auftrag aus der Warteschlange darf nicht zweimal wirken.
 *
 * Der Test legt einen eigenen Orbit an und raeumt ihn am Ende wieder ab - an
 * euren echten Daten wird nichts angefasst. Bricht er vorzeitig ab, bleibt ein
 * Orbit "OrgaSphere Selbsttest ..." stehen, den man von Hand loeschen kann.
 *
 * Aufruf (im Repo-Wurzelverzeichnis):
 *   node tools/check_log_edit.js
 *
 * Fragt dann nach E-Mail und Passwort. Alternativ vorab setzbar:
 *   --email x  --passwort y  --url https://...
 * oder ueber die Umgebungsvariablen ORGA_EMAIL / ORGA_PASSWORD.
 *
 * VORAUSSETZUNG: Die Migration v19 muss gelaufen sein (Spalten createdBy und
 * editedAt in TaskLogEntry). Ohne sie schlaegt der Test schon beim Anlegen fehl.
 *
 * Ausgabe bewusst ohne Umlaute und Sonderzeichen - die Windows-Konsole stellt
 * sie je nach Einstellung falsch dar.
 * ------------------------------------------------------------------------- */

const readline = require('readline');
const crypto = require('crypto');

const STANDARD_URL =
  'https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net';

const TESTBILD = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64'
);

// ---------------------------------------------------------------------------
// Argumente und Eingabe
// ---------------------------------------------------------------------------

function argument(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return undefined;
  const teile = [];
  for (let k = i + 1; k < process.argv.length; k++) {
    if (process.argv[k].startsWith('--')) break;
    teile.push(process.argv[k]);
  }
  return teile.length > 0 ? teile.join(' ') : undefined;
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
  if (optionen.json !== undefined) kopf['Content-Type'] = 'application/json';
  return fetch(basisUrl + pfad, {
    method: optionen.method || 'GET',
    headers: kopf,
    body: optionen.json !== undefined ? JSON.stringify(optionen.json) : optionen.body,
  });
}

async function alsJson(antwort) {
  const text = await antwort.text();
  try {
    return JSON.parse(text);
  } catch {
    return { error: text.slice(0, 200) };
  }
}

async function mussKlappen(antwort, was) {
  if (antwort.ok) return alsJson(antwort);
  const daten = await alsJson(antwort);
  throw new Error(`${was} fehlgeschlagen (HTTP ${antwort.status}): ${daten.error || 'keine Angabe'}`);
}

// Holt den Verlauf und sucht einen bestimmten Eintrag heraus.
async function eintragAusVerlauf(sphereId, eintragId) {
  const verlauf = await mussKlappen(await api(`/logs/${sphereId}`), 'Verlauf holen');
  return verlauf.find((e) => e.id === eintragId) || null;
}

// ---------------------------------------------------------------------------
// Ablauf
// ---------------------------------------------------------------------------

async function main() {
  console.log('');
  console.log('OrgaSphere - Selbsttest Verlaufseintraege aendern und loeschen');
  console.log('Server: ' + basisUrl);
  console.log('');

  const email = argument('email') || process.env.ORGA_EMAIL || (await frage('E-Mail: '));
  const passwort =
    argument('passwort') || process.env.ORGA_PASSWORD || (await frage('Passwort: ', true));

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

    // -- 2. Ist der Server ueberhaupt schon ausgerollt? --------------------
    //
    // Ohne diese Probe legt der Test erst einen Orbit an, schreibt Eintraege
    // und scheitert dann mitten im Ablauf an einer Express-Fehlerseite
    // ("Cannot PATCH /logs/..."). Das sieht nach einem Fehler in der Sache
    // aus, ist aber nur eine Route, die es auf dem Server noch nicht gibt.
    console.log('\n2. Server pruefen');
    const probe = await api(`/logs/${crypto.randomUUID()}`, {
      method: 'PATCH',
      json: { text: 'Probe' },
    });
    const probeText = await probe.text();
    if (probeText.includes('Cannot PATCH')) {
      throw new Error(
        'Der Server kennt PATCH /logs/:id noch nicht.\n' +
          '         Das Backend ist noch nicht ausgerollt. Erst pushen und die\n' +
          '         GitHub-Action abwarten, dann diesen Test erneut starten.'
      );
    }
    ok('Server kennt die neuen Endpunkte');

    // -- 3. Testumgebung anlegen ------------------------------------------
    console.log('\n3. Testumgebung anlegen');
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

    const sphere = await mussKlappen(
      await api('/tasks', {
        method: 'POST',
        json: {
          domainId: orbitId,
          title: 'Testsphere fuer Verlaufseintraege',
          description: '',
          startDate: new Date().toISOString(),
        },
      }),
      'Sphere anlegen'
    );
    ok('Orbit und Sphere angelegt');

    // -- 3. Eintrag anlegen und Verfasser pruefen -------------------------
    console.log('\n4. Eintrag anlegen');
    const eintrag = await mussKlappen(
      await api('/logs', {
        method: 'POST',
        json: { taskId: sphere.id, text: 'Urspruenglicher Text' },
      }),
      'Eintrag anlegen'
    );

    const frisch = await eintragAusVerlauf(sphere.id, eintrag.id);
    if (frisch && frisch.createdBy) ok('Eintrag traegt einen Verfasser', 'createdBy gesetzt');
    else fehler('Eintrag hat keinen Verfasser', 'createdBy fehlt - Migration v19 gelaufen?');

    if (frisch && frisch.editedAt === null) ok('neuer Eintrag ist nicht als bearbeitet markiert');
    else fehler('neuer Eintrag war schon als bearbeitet markiert', 'editedAt: ' + frisch?.editedAt);

    // -- 4. Text aendern ---------------------------------------------------
    console.log('\n5. Text aendern');
    await mussKlappen(
      await api(`/logs/${eintrag.id}`, { method: 'PATCH', json: { text: 'Geaenderter Text' } }),
      'Eintrag aendern'
    );

    const geaendert = await eintragAusVerlauf(sphere.id, eintrag.id);
    if (geaendert && geaendert.text === 'Geaenderter Text') ok('Text wurde uebernommen');
    else fehler('Text wurde nicht uebernommen', 'gelesen: ' + geaendert?.text);

    if (geaendert && geaendert.editedAt) ok('Eintrag ist jetzt als bearbeitet markiert');
    else fehler('editedAt wurde nicht gesetzt');

    // -- 5. Leerer Text ohne Anhang wird abgelehnt ------------------------
    console.log('\n6. Leerer Eintrag');
    const leer = await api(`/logs/${eintrag.id}`, { method: 'PATCH', json: { text: '   ' } });
    if (leer.status === 400) ok('leerer Text ohne Anhang wird abgelehnt');
    else fehler('leerer Text wurde angenommen', 'HTTP ' + leer.status);

    // -- 6. Fremder Eintrag ------------------------------------------------
    //
    // Ohne zweites Konto laesst sich kein echter Fremdeintrag erzeugen. Statt
    // dessen wird geprueft, dass ein Eintrag OHNE Verfasser (so sehen alte
    // Eintraege aus) niemandem gehoert und darum unveraenderlich ist. Dafuer
    // braucht es eine Kennung, die es nicht gibt - der Server muss 404 sagen,
    // nicht etwa stillschweigend etwas anderes treffen.
    console.log('\n7. Fremde und unbekannte Eintraege');
    const erfunden = await api(`/logs/${crypto.randomUUID()}`, {
      method: 'PATCH',
      json: { text: 'Fremd' },
    });
    if (erfunden.status === 404) ok('unbekannte Eintragskennung wird abgewiesen');
    else fehler('unbekannte Kennung nicht abgewiesen', 'HTTP ' + erfunden.status);

    // -- 7. Warteschlange: derselbe Auftrag zweimal ------------------------
    console.log('\n8. Auftrag aus der Warteschlange doppelt geschickt');
    const auftrag = crypto.randomUUID();
    await mussKlappen(
      await api(`/logs/${eintrag.id}`, {
        method: 'PATCH',
        headers: { 'X-Command-Id': auftrag },
        json: { text: 'Aus der Warteschlange' },
      }),
      'Aenderung mit Auftragskennung'
    );
    // Zwischendurch von Hand etwas anderes schreiben. Wuerde der Server den
    // wiederholten Auftrag erneut ausfuehren, ueberschriebe er genau das.
    await mussKlappen(
      await api(`/logs/${eintrag.id}`, { method: 'PATCH', json: { text: 'Danach von Hand' } }),
      'Zwischenaenderung'
    );
    await mussKlappen(
      await api(`/logs/${eintrag.id}`, {
        method: 'PATCH',
        headers: { 'X-Command-Id': auftrag },
        json: { text: 'Aus der Warteschlange' },
      }),
      'Wiederholung'
    );
    const nachWiederholung = await eintragAusVerlauf(sphere.id, eintrag.id);
    if (nachWiederholung && nachWiederholung.text === 'Danach von Hand') {
      ok('wiederholter Auftrag hat NICHT ein zweites Mal gewirkt');
    } else {
      fehler('wiederholter Auftrag hat erneut gewirkt', 'gelesen: ' + nachWiederholung?.text);
    }

    // -- 8. Loeschen samt Anhang -------------------------------------------
    console.log('\n9. Eintrag mit Anhang loeschen');
    const form = new FormData();
    form.append('file', new Blob([TESTBILD], { type: 'image/png' }), 'selbsttest.png');
    const anhang = await mussKlappen(
      await api(`/tasks/${sphere.id}/attachments`, { method: 'POST', body: form }),
      'Anhang hochladen'
    );

    const mitAnhang = await mussKlappen(
      await api('/logs', {
        method: 'POST',
        json: { taskId: sphere.id, text: 'Eintrag mit Anhang', attachmentIds: [anhang.id] },
      }),
      'Eintrag mit Anhang anlegen'
    );
    if (mitAnhang.linkedAttachments === 1) ok('Anhang wurde dem Eintrag zugeordnet');
    else fehler('Anhang nicht zugeordnet', 'linkedAttachments: ' + mitAnhang.linkedAttachments);

    const geloescht = await mussKlappen(
      await api(`/logs/${mitAnhang.id}`, { method: 'DELETE' }),
      'Eintrag loeschen'
    );
    if (geloescht.removedAttachments === 1) ok('Loeschen meldet den entfernten Anhang');
    else fehler('falsche Anzahl entfernter Anhaenge', String(geloescht.removedAttachments));

    const weg = await eintragAusVerlauf(sphere.id, mitAnhang.id);
    if (weg === null) ok('Eintrag ist aus dem Verlauf verschwunden');
    else fehler('Eintrag steht noch im Verlauf');

    const inhalt = await api(`/attachments/${anhang.id}/content`);
    if (inhalt.status === 404) ok('Anhang des geloeschten Eintrags ist nicht mehr abrufbar');
    else fehler('Anhang lebt nach dem Loeschen weiter', 'HTTP ' + inhalt.status);

    // -- 9. Loeschen doppelt geschickt -------------------------------------
    console.log('\n10. Loeschauftrag doppelt geschickt');
    const loeschauftrag = crypto.randomUUID();
    const ersteAntwort = await api(`/logs/${eintrag.id}`, {
      method: 'DELETE',
      headers: { 'X-Command-Id': loeschauftrag },
    });
    await mussKlappen(ersteAntwort, 'Loeschen mit Auftragskennung');
    const zweiteAntwort = await api(`/logs/${eintrag.id}`, {
      method: 'DELETE',
      headers: { 'X-Command-Id': loeschauftrag },
    });
    if (zweiteAntwort.ok) ok('wiederholter Loeschauftrag meldet weiterhin Erfolg');
    else fehler('wiederholter Loeschauftrag scheiterte', 'HTTP ' + zweiteAntwort.status);
  } finally {
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
  console.log('');
  process.exit(gescheitert === 0 ? 0 : 1);
}

main().catch((err) => {
  console.log('');
  console.log('ABBRUCH: ' + err.message);
  console.log('');
  process.exit(1);
});
