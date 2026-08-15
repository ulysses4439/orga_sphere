#!/usr/bin/env node
/* ---------------------------------------------------------------------------
 * Selbsttest fuer die Offline-Grundlagen (Stufe C, Serverseite).
 *
 * Prueft die Faelle, die sich NUR gegen einen laufenden Server zeigen:
 * doppelt gesendete Auftraege, veraltete Auftraege, Auftraege auf inzwischen
 * geloeschte Spheres, mitgebrachte Kennungen und berechenbare Kennungen fuer
 * Folge-Spheres.
 *
 * Legt dafuer einen eigenen Orbit an und raeumt ihn am Ende wieder ab.
 *
 * Aufruf (im Repo-Wurzelverzeichnis):
 *   node tools/check_sync.js
 *
 * Fragt nach E-Mail und Passwort. Alternativ:
 *   --email x  --passwort y  --url https://...
 * oder ueber ORGA_EMAIL / ORGA_PASSWORD.
 *
 * Ausgabe ohne Umlaute - die Windows-Konsole stellt sie je nach Einstellung
 * falsch dar.
 * ------------------------------------------------------------------------- */

const readline = require('readline');
const crypto = require('crypto');

const STANDARD_URL =
  'https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net';

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
    rl.question(text, (a) => {
      rl.close();
      if (versteckt) process.stdout.write('\n');
      resolve(a.trim());
    });
    rl.stdoutMuted = versteckt;
  });
}

let bestanden = 0;
let gescheitert = 0;
const ok = (t, z) => { bestanden++; console.log(`  [OK]     ${t}${z ? '  (' + z + ')' : ''}`); };
const fehler = (t, g) => { gescheitert++; console.log(`  [FEHLER] ${t}`); if (g) console.log(`           ${g}`); };

let basisUrl = argument('url') || process.env.ORGA_API || STANDARD_URL;
let token = null;

const neueKennung = () => crypto.randomUUID();

async function api(pfad, { method = 'GET', json, commandId } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (json !== undefined) headers['Content-Type'] = 'application/json';
  if (commandId) headers['X-Command-Id'] = commandId;
  const antwort = await fetch(basisUrl + pfad, {
    method,
    headers,
    body: json !== undefined ? JSON.stringify(json) : undefined,
  });
  let daten = null;
  const text = await antwort.text();
  try { daten = text ? JSON.parse(text) : {}; } catch { daten = { error: text.slice(0, 200) }; }
  return { status: antwort.status, daten };
}

async function mussKlappen(pfad, optionen, was) {
  const a = await api(pfad, optionen);
  if (a.status < 200 || a.status >= 300) {
    throw new Error(`${was} fehlgeschlagen (HTTP ${a.status}): ${a.daten?.error || 'keine Angabe'}`);
  }
  return a.daten;
}

const vorTagen = (n) => new Date(Date.now() - n * 24 * 60 * 60 * 1000).toISOString();

async function main() {
  console.log('\nOrgaSphere - Selbsttest Offline-Grundlagen');
  console.log('Server: ' + basisUrl + '\n');

  const email = argument('email') || process.env.ORGA_EMAIL || (await frage('E-Mail: '));
  const passwort = argument('passwort') || process.env.ORGA_PASSWORD || (await frage('Passwort: ', true));

  let orbitId = null;
  try {
    // -- Anmelden ---------------------------------------------------------
    console.log('\n1. Anmelden');
    const login = await mussKlappen('/auth/login',
      { method: 'POST', json: { email, password: passwort } }, 'Anmeldung');
    token = login.token;
    if (!token) throw new Error('kein Token erhalten');
    ok('angemeldet');

    // -- Testumgebung -----------------------------------------------------
    console.log('\n2. Testumgebung');
    const orbit = await mussKlappen('/domains', {
      method: 'POST',
      json: {
        name: 'OrgaSphere Sync-Test ' + new Date().toISOString().slice(11, 19),
        description: 'Wird automatisch wieder geloescht.',
        color: '#F5F5F5',
      },
    }, 'Orbit anlegen');
    orbitId = orbit.id;
    ok('Orbit angelegt');

    // -- Kennung vom Geraet -----------------------------------------------
    console.log('\n3. Kennung vom Geraet');
    const eigeneId = 'client-' + neueKennung();
    const cmdCreate = neueKennung();
    const sphere = await mussKlappen('/tasks', {
      method: 'POST',
      commandId: cmdCreate,
      json: {
        id: eigeneId,
        domainId: orbitId,
        title: 'Sphere mit eigener Kennung',
        description: '',
        startDate: new Date().toISOString(),
      },
    }, 'Sphere anlegen');
    if (sphere.id === eigeneId) ok('Server hat die mitgebrachte Kennung uebernommen');
    else fehler('Kennung wurde ersetzt', `gesendet ${eigeneId}, zurueck ${sphere.id}`);

    // Zweiter Versuch mit derselben Auftragskennung
    const nochmal = await mussKlappen('/tasks', {
      method: 'POST',
      commandId: cmdCreate,
      json: {
        id: eigeneId, domainId: orbitId, title: 'Darf nicht doppelt entstehen',
        description: '', startDate: new Date().toISOString(),
      },
    }, 'Sphere erneut anlegen');
    if (nochmal.id === eigeneId && nochmal.title === sphere.title) {
      ok('doppelt gesendeter Anlege-Auftrag legt nichts Zweites an');
    } else {
      fehler('doppelter Anlege-Auftrag hat etwas veraendert', JSON.stringify(nochmal).slice(0, 120));
    }

    // -- Zeitpunkt vom Geraet ---------------------------------------------
    console.log('\n4. Zeitpunkt vom Geraet');
    const drieTage = vorTagen(3);
    await mussKlappen(`/tasks/${eigeneId}/done`, {
      method: 'PATCH', commandId: neueKennung(), json: { occurredAt: drieTage },
    }, 'Erledigen mit Zeitpunkt');
    const nachErledigen = await mussKlappen('/sync', {}, 'Abgleich');
    const erledigt = (nachErledigen.archived || []).find((t) => t.id === eigeneId);
    if (!erledigt) {
      fehler('erledigte Sphere nicht im Archiv gefunden');
    } else {
      const abstand = Math.abs(new Date(erledigt.completedAt) - new Date(drieTage));
      if (abstand < 60000) ok('Erledigungszeitpunkt vom Geraet uebernommen', 'vor 3 Tagen');
      else fehler('Zeitpunkt wurde nicht uebernommen', 'completedAt=' + erledigt.completedAt);
    }

    // -- Doppelter Auftrag -------------------------------------------------
    console.log('\n5. Doppelt gesendeter Auftrag');
    const s2 = await mussKlappen('/tasks', {
      method: 'POST',
      json: {
        domainId: orbitId, title: 'Taegliche Sphere', description: '',
        startDate: new Date().toISOString(),
        recurrenceFrequency: 'daily', recurrenceInterval: 1,
      },
    }, 'wiederkehrende Sphere anlegen');

    const cmdDone = neueKennung();
    const ersteAntwort = await mussKlappen(`/tasks/${s2.id}/done`,
      { method: 'PATCH', commandId: cmdDone }, 'Erledigen');
    const zweiteAntwort = await mussKlappen(`/tasks/${s2.id}/done`,
      { method: 'PATCH', commandId: cmdDone }, 'Erledigen (Wiederholung)');

    const id1 = ersteAntwort.nextTask?.id || null;
    const id2 = zweiteAntwort.nextTask?.id || null;
    if (id1 && id1 === id2) {
      ok('Wiederholung liefert dieselbe Antwort, keine zweite Folge-Sphere');
    } else {
      fehler('Wiederholung hat etwas veraendert', `erst ${id1}, dann ${id2}`);
    }

    // -- Berechenbare Kennung ----------------------------------------------
    console.log('\n6. Berechenbare Kennung der Folge-Sphere');
    if (!id1) {
      fehler('keine Folge-Sphere entstanden');
    } else {
      const passt = /^.+:\d{4}-\d{2}-\d{2}$/.test(id1);
      if (passt) ok('Kennung hat die Form <serie>:<datum>', id1.slice(-20));
      else fehler('Kennung ist nicht berechenbar aufgebaut', id1);

      const serie = s2.seriesId || s2.id;
      if (id1.startsWith(serie + ':')) ok('Kennung traegt die Serie der Vorgaengerin');
      else fehler('Serie stimmt nicht', `erwartet ${serie}, bekommen ${id1}`);
    }

    // -- Veralteter Auftrag -------------------------------------------------
    console.log('\n7. Veralteter Auftrag wird verworfen');
    const s3 = await mussKlappen('/tasks', {
      method: 'POST',
      json: { domainId: orbitId, title: 'Neuer Titel', description: '', startDate: new Date().toISOString() },
    }, 'Sphere anlegen');
    // Frische Aenderung (jetzt), danach eine aeltere aus der Warteschlange
    await mussKlappen(`/tasks/${s3.id}/title`,
      { method: 'PATCH', json: { title: 'Aktuell' } }, 'Titel setzen');
    const alt = await mussKlappen(`/tasks/${s3.id}/title`, {
      method: 'PATCH', commandId: neueKennung(),
      json: { title: 'Veraltet', occurredAt: vorTagen(2) },
    }, 'veralteten Titel senden');
    if (alt.superseded === true) ok('Server meldet den Auftrag als ueberholt');
    else fehler('ueberholter Auftrag wurde nicht erkannt', JSON.stringify(alt));

    const kontrolle = await mussKlappen('/sync', {}, 'Abgleich');
    const s3neu = (kontrolle.tasks || []).find((t) => t.id === s3.id);
    if (s3neu && s3neu.title === 'Aktuell') ok('der neuere Titel steht weiterhin');
    else fehler('der veraltete Titel hat gewonnen', s3neu ? s3neu.title : 'Sphere weg');

    // -- Auftrag auf geloeschte Sphere -------------------------------------
    console.log('\n8. Auftrag auf inzwischen geloeschte Sphere');
    const s4 = await mussKlappen('/tasks', {
      method: 'POST',
      json: { domainId: orbitId, title: 'Wird geloescht', description: '', startDate: new Date().toISOString() },
    }, 'Sphere anlegen');
    await mussKlappen(`/tasks/${s4.id}`, { method: 'DELETE' }, 'Sphere loeschen');

    const aufGeloeschte = await api(`/tasks/${s4.id}/done`,
      { method: 'PATCH', commandId: neueKennung() });
    if (aufGeloeschte.status === 200 && aufGeloeschte.daten.gone === true) {
      ok('kein Fehler, Auftrag gilt als erledigt');
    } else {
      fehler('geloeschte Sphere liefert weiterhin einen Fehler',
        `HTTP ${aufGeloeschte.status}: ${JSON.stringify(aufGeloeschte.daten).slice(0, 100)}`);
    }

    // Ohne Auftragskennung muss es weiterhin 404 geben (Verhalten fuer die
    // heutige App darf sich nicht aendern).
    const ohneKennung = await api(`/tasks/${s4.id}/done`, { method: 'PATCH' });
    if (ohneKennung.status === 404) ok('ohne Auftragskennung weiterhin 404 wie bisher');
    else fehler('Verhalten ohne Auftragskennung hat sich geaendert', 'HTTP ' + ohneKennung.status);
  } finally {
    if (orbitId) {
      try {
        await api(`/domains/${orbitId}`, { method: 'DELETE' });
        console.log('\n(Testorbit aufgeraeumt.)');
      } catch {
        console.log(`\nACHTUNG: Testorbit ${orbitId} blieb stehen.`);
      }
    }
  }

  console.log('\n----------------------------------------');
  console.log(`Bestanden: ${bestanden}   Gescheitert: ${gescheitert}`);
  console.log('----------------------------------------\n');
  process.exit(gescheitert === 0 ? 0 : 1);
}

main().catch((err) => {
  console.log('\nABBRUCH: ' + err.message + '\n');
  process.exit(1);
});
