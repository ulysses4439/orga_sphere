# Feedbackliste

Gesammelte Bugs und Anpassungswünsche aus dem Beta-Test. Wird laufend gepflegt.

**Grundregel:** Jede Änderung muss in der **Desktop-Version (Windows)** und in der
**App-Version (Android)** umgesetzt werden. Vor der Umsetzung wird geprüft und
festgehalten, ob und wie weit sich die Änderung auf beiden Plattformen realisieren lässt.

---

## Offen

_(keine offenen Punkte – neue Meldungen hier eintragen)_

---

## Nachtrag

### 7. Eigene Rolle im Orbit ist sichtbar (kein Fehler, sondern Rückmeldung)
**Gemeldet:** 08.08.2026 · **Umgesetzt in:** v1.0.14 · **Plattformen:** Desktop + App

**Meldung:** In manchen Orbits fehlt der Knopf zum Einladen von Co-Piloten.

**Befund: kein Fehler.** Der Knopf erscheint nur für Piloten — Co-Piloten dürfen niemanden
einladen. In den betroffenen Orbits war Steven per Datenbank-Abfrage bestätigt Co-Pilot
(er nutzt zwei Konten: privat und Arbeit). Auch der Einkaufslisten-Modus war unbeteiligt,
die Teilnehmerleiste wird dort normal angezeigt.

**Trotzdem geändert:** Die eigene Rolle war nur am *Fehlen* eines Knopfes erkennbar — eine
wortlose Lücke, die sich nicht von einer Störung unterscheiden lässt. Statt der Lücke steht
dort jetzt „Co-Pilot" mit einem Hinweis, dass nur der Pilot Co-Piloten verwalten darf.

**Zwei Härtungen aus der Fehlersuche mitgenommen:**
- Die Pilot-Erkennung lief über einen zeichengenauen E-Mail-Vergleich, obwohl jedes Mitglied
  eine stabile `userId` mitliefert. Jetzt über die ID, E-Mail nur noch als Rückfallebene für
  Eingeladene ohne Konto (dann ohne Rücksicht auf Groß-/Kleinschreibung).
- **Echter latenter Fehler:** `PATCH /auth/profile` änderte bei einer E-Mail-Umstellung nur
  `AppUser` — die `OrbitMember`-Zeilen behielten die alte Adresse. Da der Erinnerungs-Scheduler
  seine Mails an `OrbitMember.email` schickt, wären Erinnerungen still an die alte Adresse
  gegangen. Das Backend zieht die Mitgliedschaften jetzt mit;
  das einmalige Aufräumskript `v11_orbitmember_email_sync.sql` hat die Altbestände bereinigt
  (Stand 08.08.2026 geprüft: keine Abweichungen vorhanden; Skript danach entfernt).

### 8. Kräftige Farben zur Auswahl beim Orbit anlegen
**Gewünscht:** 08.08.2026 · **Umgesetzt in:** v1.0.14 · **Plattformen:** Desktop + App

Vierte Reihe in der Farbauswahl mit kräftigen Tönen (Rot, Orange, Grün, Blau, Violett)
zusätzlich zu den bisherigen Pastelltönen.

**Nicht nur Farben hinzugefügt:** Die Orbit-Farbe ist der Hintergrund der Sphere-Kacheln, und
die Schrift darauf war fest schwarz. Kräftige Farben hätten die Kacheln unlesbar gemacht.
[TaskListItem](lib/widgets/task_list_item.dart) wählt die Schriftfarbe jetzt selbst — es
vergleicht die WCAG-Kontrastwerte gegen Weiß und gegen Schwarz und nimmt die besser lesbare.

Ein fester Helligkeits-Schwellwert wäre hier falsch gewesen: Orange (#FB8C00) wirkt dunkel,
erreicht mit weißer Schrift aber nur 2,4:1 — mit schwarzer dagegen 8,8:1. Violett (#8E24AA)
liegt umgekehrt. Von den fünf neuen Farben bekommt daher nur Violett weiße Schrift.

**Geprüft:** Alle 20 Palettenfarben erreichen mit der gewählten Schriftfarbe mindestens
4,5:1 (WCAG AA); der schlechteste Wert ist Rot mit 4,97:1.

### 9. Balken im Eingabefeld beim Bearbeiten einer Listenposition
**Gemeldet:** 08.08.2026 · **Erledigt in:** v1.0.15 · **Plattformen:** Desktop + App

**Problem:** Im Dialog „Position bearbeiten" lag ein dicker blauer Balken quer über dem
Eingabefeld, darunter ein grauer Block. Der Dialog war praktisch unbenutzbar.

**Ursache — Fehler aus Punkt 5:** In `showSimpleListItemDialog` stand ein `Spacer()` zwischen
den Schaltflächen, um „Löschen" nach links zu rücken. Die Aktionsleiste eines `AlertDialog`
ist aber ein `OverflowBar` und damit **kein Flex-Widget**; ein `Spacer` benötigt zwingend
eines. Dadurch wurde das Textfeld auf Nullhöhe zusammengedrückt — der „Balken" waren die
zusammenfallenden Rahmenlinien des Eingabefelds.

**Lösung:** `actionsAlignment: MainAxisAlignment.spaceBetween` statt `Spacer`; Abbrechen und
OK als Gruppe rechts. Reicht der Platz nicht, bricht die Leiste jetzt sauber um.

**Zweiter Fehler in derselben Funktion, mit erledigt:** Löschen und Speichern gaben beide
`true` zurück. Nach dem Löschen lief deshalb zusätzlich ein Titel-Update auf die bereits
gelöschte Sphere — der Fehler wurde stillschweigend verschluckt. Der Dialog unterscheidet die
Fälle jetzt.

**Warum es nicht auffiel:** `flutter analyze` erkennt so etwas nicht — es ist ein reines
Laufzeit-Layoutproblem. Der Dialog wurde vor der Auslieferung nie geöffnet.

### 10. Meldungen in der Glocke einzeln ausblenden
**Gewünscht:** 08.08.2026 · **Umgesetzt in:** v1.0.15 · **Plattformen:** Desktop + App

**Ausgangsfrage war entscheidend:** Liegen die Meldungen zentral oder lokal? Antwort:
`OrbitEvent` enthält **eine Zeile pro Ereignis, geteilt von allen Mitgliedern des Orbits**.
Ein echtes `DELETE` hätte die Meldung bei allen entfernt. Lokal liegt bisher nur der
Lesestatus — und zwar pro Gerät, nicht pro Konto.

**Lösung:** Ausblenden statt löschen. Neue Tabelle `OrbitEventDismissed (eventId, userId)`
hält je Nutzer fest, was er weggeräumt hat; `GET /events` filtert per `NOT EXISTS`. Die
Ereigniszeile bleibt unangetastet, andere Mitglieder sehen ihre Meldung unverändert.

**Serverseitig statt im Gerätespeicher**, damit das Aufräumen am Desktop auch am Handy gilt.

**Bedienung:** In der App nach rechts wischen, auf dem Desktop ein kleines X. Zusätzlich
oben in der Liste „Alle ausblenden". Der Server wird jeweils zuerst gefragt — schlägt es
fehl, kommt der Eintrag zurück, statt nur optisch zu verschwinden.

**Erforderte Migration** `v12_event_dismissed.sql` (Tabelle `OrbitEventDismissed`, ausgeführt;
inzwischen Teil von [backend/db/schema.sql](backend/db/schema.sql)). Sie musste **vor** dem
Backend-Deploy laufen: Fehlt die Tabelle, scheitert `GET /events` und es kommen gar keine
Meldungen mehr an.

**Offen geblieben:** Der Lesestatus (rotes Badge) liegt weiterhin pro Gerät. Am Desktop
gelesen heißt am Handy noch ungelesen. Ließe sich mit derselben Technik auf das Konto
umstellen — bisher nicht beauftragt.

### 11. Fälligkeitsdatum springt einen Tag zurück
**Gemeldet:** 09.08.2026 · **Erledigt in:** v1.0.15 · **Plattformen:** Desktop + App

**Problem:** Nach dem Setzen einer Erinnerung stand als Fälligkeitsdatum plötzlich der
Vortag (09.08. → 08.08.), reproduzierbar.

**Ursache — zwei verschiedene Schreibweisen für dasselbe Feld:**

| Weg | Übertragen wurde |
|---|---|
| `createTask` (Anlegen) | `2026-08-09T00:00:00.000` — ohne Zeitzone, korrekt |
| `updateTaskSchedule` (Ändern) | `2026-08-08T22:00:00.000Z` — **per `toUtc()` verschoben** |

Start- und Fälligkeitsdatum bezeichnen einen **Tag**, keinen Zeitpunkt. Das `toUtc()` machte
aus Mitternacht deutscher Sommerzeit 22:00 des Vortages. Da die Anzeige die Werte ohne
Rückrechnung formatiert, stand dort der Vortag. Betroffen war nur das Feld, das zuletzt über
die Detailansicht geschrieben wurde — deshalb sprang das Fälligkeitsdatum, das Startdatum
aber nicht.

**Warum die Erinnerung als Auslöser wirkte:** Direkt nach dem Ändern zeigt die App noch ihren
eigenen, korrekten Wert. Erst der nächste Abgleich mit dem Server (spätestens der
30-Sekunden-Takt, oder eben ausgelöst durch das Setzen der Erinnerung) holt den verschobenen
Wert. Die Erinnerung selbst fasst das Datum nicht an.

**Lösung:** `updateTaskSchedule` überträgt Datumsangaben jetzt ohne Zeitzonenumrechnung und
auf Mitternacht normalisiert — genau wie `createTask`. `reminderAt` bleibt bewusst UTC, das
ist ein echter Zeitpunkt.

**Altbestand:** Das einmalige Datenskript `v13_fix_shifted_dates.sql` hat bereits verschobene
Werte geradegerückt (Prüfung 09.08.2026: 1 Zeile Zeitzonen-Verschiebung, 49 Zeilen
Erfassungszeitstempel; Skript danach entfernt).

**Zur Randbedingung „nur wenn Start = Fällig":** Vermutlich ein Wahrnehmungseffekt — die
Verschiebung trat immer auf, fiel aber nur dann sofort ins Auge, weil aus „heute fällig"
ein **rot markiertes „überfällig"** wurde. Bei einem Datum in der Zukunft (11.08. → 10.08.)
bleibt die Kachel unauffällig. Bitte nach dem Update gegenprüfen.

**Datenkorrektur ausgeführt 09.08.2026.** Die Prüfabfrage zeigte 1 verschobenes `dueDate`
(exakt 22:00) und 49 `startDate` mit Erfassungszeitpunkten aus der Schnellerfassung. Die
erste Fassung des Skripts hätte 34 davon fälschlich auf den Folgetag geschoben — sie wurde
vor der Ausführung auf zwei getrennte Fälle umgestellt: exakt 22:00/23:00 werden angehoben,
alles andere wird nur auf Mitternacht abgeschnitten.

### 12. Windows: App fehlt im Startmenü eines zweiten Profils
**Gemeldet:** 09.08.2026 · **Erledigt in:** v1.0.15 · **Plattform:** Windows

**Problem:** Auf einem Rechner mit zwei Windows-Profilen (privat + Verein) ließ sich die App
im zweiten Profil nicht nutzen. Die Installation meldete Erfolg, das Startmenü blieb leer.

**Ursache:** `Add-AppxPackage` installiert eine MSIX-App **immer nur für den ausführenden
Benutzer**. Der alte Installer forderte aber ganz zu Beginn Admin-Rechte für das **gesamte**
Skript an. Im Vereinsprofil (kein Admin) musste dafür die private Admin-Kennung eingegeben
werden — damit lief auch die App-Installation als *privater* Nutzer. Die App wurde also ein
zweites Mal ins private Profil installiert, nicht ins Vereinsprofil.

**Lösung:** Der Installer eleviert nicht mehr pauschal. Admin-Rechte werden nur noch für den
Zertifikats-Import geholt — und nur, wenn das Zertifikat auf dem Rechner überhaupt fehlt
(einmalig pro Rechner, nicht pro Profil). `Add-AppxPackage` läuft bewusst im normalen
Benutzerkontext. Zum Schluss prüft das Skript, ob das Paket im aktuellen Profil wirklich
auffindbar ist, statt Erfolg nur zu melden.

**Zu den getrennten Kennungen:** Funktioniert bereits ohne Änderung. Die App-Daten liegen unter
`%LOCALAPPDATA%\Packages\CoatesEventSystems.OrgaSphere_jaf9vzakqgcjp` und damit pro
Windows-Profil getrennt — jedes Profil kann sich mit einem eigenen OrgaSphere-Konto anmelden.

**Paketinhalt geändert:** Ab v1.0.15 enthält das ZIP **vier** Dateien; `install_orgasphere.ps1`
gehört jetzt zwingend dazu, die `.bat` ruft sie nur noch auf.

### 13. Langer Sphere-Titel lässt sich nicht speichern — ohne jeden Hinweis
**Gemeldet:** 12.08.2026 · **Erledigt in:** v1.0.16 · **Plattformen:** Desktop + App

**Problem:** Ein sehr langer Titel ließ sich nicht speichern. Es erschien weder eine Meldung
noch ein Hinweis auf eine Zeichengrenze — das Speichern passierte schlicht nicht.

**Ursache:** `Task.title` ist in der Datenbank `NVARCHAR(200)`. Ab 201 Zeichen antwortet Azure
SQL mit *„String or binary data would be truncated"*, das Backend reichte das als 500er durch.
An zwei Stellen wurde der Fehler in der App zusätzlich verschluckt: beim Verlassen der
Detailansicht (`_flushPendingEdits`, dort bewusst still) und in der Schnell-Eingabe der
Sphere-Liste, die ein leeres `catch (_) {}` hatte. Deshalb kam gar keine Rückmeldung an.

**Lösung — drei Ebenen:**
- Neue zentrale Datei [field_limits.dart](lib/utils/field_limits.dart) hält die Grenzen exakt
  passend zu den Spaltenbreiten: Sphere-Titel und Listenposition 200, Sphere-Beschreibung 1000,
  Orbit-Name 100, Orbit-Beschreibung 500, Verlaufseintrag 1000, Anzeigename 200.
- **Jedes** Eingabefeld, das in diese Spalten schreibt, hat jetzt `maxLength`. Zu lang tippen
  ist damit unmöglich, eingefügter Text wird beim Einfügen gekappt statt beim Speichern zu
  scheitern. In den Anlege-Formularen steht der Zähler dauerhaft unter dem Feld; in den
  schlanken Inline-Feldern (Detailtitel, Schnell-Eingabe, Dialoge) blendet er sich ab 80 %
  Füllstand ein und wird bei 200/200 rot — dauerhaft sichtbar würde er dort das Layout stören.
- Das Backend prüft dieselben Grenzen und antwortet mit Klartext („Der Titel darf höchstens
  200 Zeichen lang sein (aktuell 340).") statt mit einem 500er. Das verschluckte `catch (_) {}`
  in der Schnell-Eingabe zeigt jetzt ebenfalls eine Meldung.

### 14. Windows: OrgaSphere lässt sich mehrfach starten
**Gemeldet:** 12.08.2026 · **Erledigt in:** v1.0.16 · **Plattform:** Windows

**Problem:** Jeder Klick auf Kachel oder Verknüpfung öffnete ein weiteres OrgaSphere-Fenster,
statt das laufende in den Vordergrund zu holen.

**Ursache: kein Fehler im eigentlichen Sinn, sondern eine Lücke.** Der Flutter-Runner für
Windows kennt keine Instanzsperre — Windows startet bei jeder Aktivierung einen neuen Prozess.
Auf Android tritt das nicht auf, dort verwendet das System die vorhandene Activity wieder.
Mehrere Instanzen bedeuteten je eigenen Zustand, eigenes Polling und doppelte Meldungen.

**Lösung** in [main.cpp](windows/runner/main.cpp), noch bevor die Flutter-Engine startet: Ein
benannter Mutex (`Local\OrgaSphere.SingleInstance`) erkennt die laufende Instanz. Der zweite
Start sucht deren Fenster, holt es nach vorn und beendet sich. Die Fenstersuche prüft die
Fensterklasse **und** den EXE-Pfad — die Klasse `FLUTTER_RUNNER_WIN32_WINDOW` ist bei jeder
Flutter-App gleich, sonst würde im Zweifel eine fremde Anwendung nach vorn geholt. Minimierte
Fenster werden wiederhergestellt; blockiert Windows `SetForegroundWindow`, greift ein Fallback
über `AttachThreadInput`, damit nicht nur die Taskleiste blinkt.

`Local\` statt `Global\` ist Absicht: Ein zweiter angemeldeter Windows-Benutzer darf OrgaSphere
weiterhin starten, sein Fenster liegt auf einem anderen Desktop. Schlägt das Anlegen des Mutex
fehl, startet die App normal — lieber zwei Fenster als gar keins.

**Geprüft** am Release-Build: dreimal gestartet → bleibt bei einem Prozess; nach dem Beenden
wieder startbar; minimiertes Fenster wird wiederhergestellt und ist danach das Vordergrundfenster.
**Hinweis für die Entwicklung:** Läuft die App bereits, beendet sich ein zusätzliches
`flutter run` sofort wieder — das ist die gewollte Wirkung.

### 15. Co-Pilot kann einen Orbit umbenennen
**Gemeldet:** 12.08.2026 · **Erledigt in:** v1.0.16 · **Plattformen:** Desktop + App

**Ursache:** `PATCH /domains/:id/name` lief unter `requireMember` statt `requirePilot` — anders
als Löschen und Einladen, die bereits korrekt abgesichert waren. Der Orbit-Name taucht in
Einladungsmails, Erinnerungen und Team-Meldungen aller Mitglieder auf; ein Co-Pilot konnte ihn
also unter allen anderen wegziehen.

**Lösung:** Der Endpunkt verlangt jetzt Pilotenrechte. Damit die Aktion gar nicht erst
angeboten wird, liefert `GET /domains` neu die eigene Rolle je Orbit mit (`myRole`); `TaskDomain`
hat dafür `isPilot`. Auf dem Desktop entfällt für Co-Piloten das Drei-Punkte-Menü am Orbit
vollständig, auf dem Handy zeigt das Menü beim Langdrücken statt der Aktionen den Grund an.
Fehlt das Feld (älteres Backend), gilt der Fallback „Pilot" — ungefährlich, weil die Rechte am
Server hängen und nicht an dieser Anzeige.

### 16. Co-Pilot sieht nicht, wer der Pilot ist
**Gemeldet:** 12.08.2026 · **Erledigt in:** v1.0.16 · **Plattformen:** Desktop + App

**Problem:** Seit v1.0.14 steht in der Teilnehmerleiste „Co-Pilot", wo der Einladen-Knopf
fehlt (siehe Punkt 7). Damit war zwar klar, dass man nichts ändern darf — aber nicht, wen man
für Änderungen ansprechen muss.

**Lösung:** Statt „Co-Pilot" steht dort jetzt **„Pilot: Anna Schmidt"**; ein Klick öffnet die
Angaben inklusive E-Mail-Adresse. Zusätzlich reagieren alle Avatare der Leiste auf Tippen: Der
Pilot verwaltet damit wie bisher, alle anderen sehen Name, E-Mail, Rolle und Status. Vorher war
das nur per Tooltip erreichbar — auf dem Handy also praktisch gar nicht.

### 17. Eingeladene Co-Piloten sehen sofort wie aktive Teilnehmer aus
**Gemeldet:** 12.08.2026 · **Erledigt in:** v1.0.16 · **Plattformen:** Desktop + App

**Problem:** Direkt nach dem Einladen erschien der Avatar des Co-Piloten farbig — als wäre er
bereits aktiv dabei, obwohl er von der Einladung noch gar nichts wusste.

**Ursache — tiefer als die Darstellung:** Für eine E-Mail-Adresse **mit** OrgaSphere-Konto gab
es den Zustand „eingeladen" überhaupt nicht. `POST /domains/:id/members` trug solche Nutzer
sofort als `active` ein. Nur Eingeladene ohne Konto bekamen `pending`.

**Lösung — Einladungen müssen angenommen werden:**
- Jede Einladung startet als `pending`, mit und ohne Konto.
- Der offene Avatar ist ein **grauer Ring mit grauer Schrift** auf dem schwarzen Grund der
  Leiste, dazu eine kleine Uhr in der Ecke. Bewusst kein gefüllter grauer Kreis: Eine gefüllte
  Fläche wirkt auf Schwarz wie eine eigene Farbe und damit wieder wie „dabei". Die leere Kontur
  liest sich als „Platz reserviert, noch nicht besetzt", die Uhr macht den Unterschied auch
  ohne Farbwahrnehmung erkennbar.
- Der Eingeladene sieht beim nächsten App-Start ein Banner über der Orbit-Liste mit
  **Annehmen / Ablehnen** (Desktop und Handy). Annehmen aktiviert die Mitgliedschaft, lädt den
  Orbit nach und meldet dem Team „… ist beigetreten". Ablehnen entfernt den Eintrag, sodass der
  Pilot dieselbe Person später erneut einladen kann.
- Neue Endpunkte: `GET /invitations`, `POST /invitations/:id/accept`, `POST /invitations/:id/decline`.
- Der E-Mail-Link funktioniert weiter und hat jetzt eine Variante für bereits registrierte
  Konten: Bestätigung mit dem eigenen Passwort statt Konto anlegen.

**Nebenbefund, mitbehoben:** Auf dem alten Weg konnte jeder, der den Einladungslink in die
Hände bekam, die Einladung ohne Passwortprüfung annehmen. `POST /invite` prüft bei vorhandenem
Konto jetzt das Passwort.

**Zur Sicherheit der Zwischenstufe geprüft:** Eine offene Einladung gibt **keinerlei** Zugriff.
Orbit-Liste, Sphere-Abfragen, Push-Empfänger und der Erinnerungs-Scheduler filtern ausnahmslos
auf `status = 'active'`. Die `userId` wird bei Eingeladenen mit Konto trotzdem schon gesetzt,
damit die Einladung auch nach einem Adresswechsel zugeordnet bleibt.

### 18. Wiederholende Sphere verliert ihre Erinnerung
**Gemeldet:** 12.08.2026 · **Erledigt in:** v1.0.16 · **Plattformen:** Desktop + App (Backend)

**Problem:** Bei einer Sphere mit Wiederholung (z. B. alle 3 Tage) wurde die Folge-Sphere
zuverlässig angelegt — eine gesetzte Erinnerung fehlte dort aber. Erwartet: Die Erinnerung
wandert mit, versetzt um genau den Wiederholungsrhythmus (12.08. 06:30 → 15.08. 06:30).

**Ursache:** In `createNextCapsuleIfNeeded` wurden Start- und Fälligkeitsdatum verschoben
übernommen, `reminderAt` stand im INSERT schlicht nicht drin. Die Spalte blieb NULL, die
Erinnerung war ab dem ersten Durchlauf still verschwunden.

**Lösung:** Die Erinnerung wandert jetzt um denselben Rhythmus mit. `reminderEmailSentAt` wird
bewusst **nicht** übernommen — sonst hielte der Scheduler die neue Erinnerung für bereits
verschickt und würde nie eine Mail senden. Der Fix greift für beide Wege: Erledigen per Klick
und den Scheduler, der fällige Folge-Spheres selbst anlegt.

**Sommer-/Winterzeit berücksichtigt:** In UTC gerechnet wären „3 Tage" exakt 72 Stunden — fällt
die Zeitumstellung dazwischen, würde aus 06:30 plötzlich 05:30 bzw. 07:30, und die Sphere liefe
dauerhaft auf der falschen Uhrzeit weiter. Erinnerungen werden deshalb **auf der Wanduhr der
Zeitzone** weitergezählt (`nextReminderDate`, Zone über `APP_TIMEZONE`, Standard `Europe/Berlin`).
Start- und Fälligkeitsdatum rechnen weiter über reine Tage — sie liegen auf 00:00:00, dort gibt
es keine Uhrzeit zu erhalten, und eine Zonenrechnung würde die Mitternacht verschieben.

Die beiden unvermeidbaren Sonderfälle sind ausdrücklich entschieden: Die **übersprungene
Stunde** im Frühjahr (02:30 gibt es nicht) rutscht nach hinten auf 03:30; die **doppelte Stunde**
im Herbst nimmt den ersten Durchgang, die Erinnerung kommt also eher statt später.

**Zweiter Fehler in derselben Funktion, mitbehoben:** `nextDate(null, …)` ergab über
`new Date(null)` den 01.01.1970. Eine wiederkehrende Sphere **ohne** Fälligkeitsdatum bekam
damit bei jedem Durchlauf ein Datum aus dem Jahr 1970 und stand sofort rot als überfällig da.
Leere Datums liefern jetzt `null`.

**Geprüft** gegen die echten Funktionen aus `index.js`, bewertet in deutscher Ortszeit: 12 Fälle,
darunter beide Umstellungsrichtungen, übersprungene und doppelte Stunde, Mitternacht als
Erinnerungszeit sowie leere Fälligkeit — alle wie erwartet.

**Einschränkung:** Die Zeitzone ist fest auf `Europe/Berlin` (per `APP_TIMEZONE` änderbar). Pro
Nutzer ginge es erst, wenn die Gerätezeitzone gespeichert wird — das braucht ein Feld an
`AppUser`, eine Migration und ein Paket wie `flutter_timezone`. Relevant erst bei Nutzern
außerhalb Deutschlands.

### 19. Orbit-Beschreibung lässt sich nachträglich nicht ändern
**Gemeldet:** 12.08.2026 · **Erledigt in:** v1.0.17 · **Plattformen:** Desktop + App

**Problem:** Beim Anlegen eines Orbits lassen sich Name und Beschreibung erfassen. Danach war
nur noch der Name änderbar — wer die Beschreibung vergessen hatte, kam nicht mehr heran.

**Ursache:** Es gab ausschließlich `PATCH /domains/:id/name`. Für die Beschreibung existierte
kein Endpunkt und im Menü kein Einstieg. Angezeigt wird sie durchaus: auf dem Desktop mittig
unter dem Orbit-Namen, auf dem Handy unter der Teilnehmerleiste — nur eben unveränderlich.

**Lösung:** Aus „Umbenennen" wird **„Bearbeiten"**. Der Dialog enthält jetzt Name *und*
Beschreibung, beide mit den Zeichengrenzen aus Punkt 13 (100 bzw. 500). Gespeichert wird nur,
was sich geändert hat. Neuer Endpunkt `PATCH /domains/:id/description`, wie das Umbenennen mit
`requirePilot` abgesichert — die Beschreibung steht im Kopfbereich bei allen Mitgliedern und
gehört damit in dieselbe Rechteklasse. Auf dem Handy trägt der Menüpunkt den Zusatz „Name und
Beschreibung", damit erkennbar ist, dass er mehr kann als früher.

**Latenter Fehler, mitbehoben:** `renameDomain` setzte den Orbit lokal von Hand neu zusammen
und ließ dabei `isShoppingList` und `myRole` fallen. Beim Umbenennen eines Einkaufslisten-Orbits
verlor dieser bis zum nächsten Abgleich (bis zu 30 Sekunden) seinen Listen-Modus und verhielt
sich wie ein normaler Orbit. `TaskDomain` hat jetzt ein `copyWith`, das alle Felder mitnimmt.

---

## Erledigt

### 1. Rotes Glocken-Badge verschwindet nicht beim direkten Öffnen einer Sphere
**Gemeldet:** 07.08.2026 · **Erledigt in:** v1.0.13 · **Plattformen:** Desktop + App

**Problem:** Das rote Zähler-Symbol an der Glocke verschwand nur, wenn man die
Benachrichtigungsliste öffnete. Ging man stattdessen direkt in den Orbit und tippte die
betroffene Sphere an, blieb der Zähler stehen — obwohl man die Meldung faktisch gesehen hatte.

**Ursache:** Das `NotificationCenter` kannte keinen Lesestatus pro Ereignis, sondern nur einen
einzigen Zeitstempel `_lastSeen`. Der wurde ausschließlich beim Schließen der Glockenliste
gesetzt. Das Öffnen einer Sphere hatte technisch keinerlei Verbindung zum Badge.

**Lösung:** Lesestatus zusätzlich pro Ereignis-ID (persistiert). Neu: `markSphereRead(sphereId)`,
aufgerufen beim Öffnen der Sphere-Detailansicht. Umfang: alle Ereignisse dieser Sphere
(Erinnerung, Zuweisung, erledigt, Kommentar). Orbit-Ebene markiert bewusst **nicht** mit —
eine Titelliste bedeutet nicht, dass die Meldung gesehen wurde.

**Nebenbefund:** Die Glocke war in der App auf der Startseite unsichtbar — weißes Icon auf
`navyPale` (#E6EEF7). Korrigiert. Zusätzlich ist die Glocke jetzt auch in der Orbit- und der
Sphere-Ansicht der App erreichbar, nicht mehr nur auf der Startseite.

### 2. Aktivitätsverlauf liegt hinter der Samsung-Navigationsleiste
**Gemeldet:** 07.08.2026 · **Erledigt in:** v1.0.13 · **Plattformen:** App (Desktop unverändert)

**Problem:** In der Sphere-Detailansicht auf dem Handy verschwand der unterste Eintrag des
Aktivitätsverlaufs hinter den Funktionstasten des Geräts und war kaum lesbar.

**Ursache:** Der Aktivitätsverlauf ist der letzte Block der Scroll-Ansicht und hatte unten nur
16px Padding — die Höhe der Systemleiste war nirgends eingerechnet.

**Lösung:** Unteres Padding um `MediaQuery.viewPadding.bottom` erweitert. `viewPadding` statt
`padding`, damit der Wert bei geöffneter Tastatur stabil bleibt. Auf Desktop ist der Wert 0,
die Darstellung dort ändert sich also nicht — ein Codepfad für beide Plattformen.

**Mit erledigt:** Dieselbe Lücke bestand in der Orbit-Übersicht und der Sphere-Liste der App.
Dort verdeckte zusätzlich der schwebende Plus-Button den letzten Listeneintrag; beide Listen
haben jetzt Reserve für Systemleiste **und** Button.

### 3. Kalender startet mit Sonntag, Texte und Monatsnamen englisch
**Gemeldet:** 07.08.2026 · **Erledigt in:** v1.0.13 · **Plattformen:** Desktop + App

**Problem:** Im Datumsauswahl-Dialog begann die Woche am Sonntag (US-Konvention), die
Kopfzeile hieß „Select date", und die Monatsnamen waren englisch („December" statt „Dezember").

**Ursache:** Eine Ursache für alle drei Symptome — der App fehlte die deutsche Lokalisierung.
Ohne `localizationsDelegates`/`supportedLocales` läuft Flutter als `en_US`, und daraus zieht
der Kalender sowohl den Wochenbeginn als auch alle Beschriftungen.

**Lösung:** `flutter_localizations` als Abhängigkeit, in `MaterialApp` die drei Global-Delegates
plus fest `locale: Locale('de','DE')`. Wochenbeginn ist damit Montag (Samstag/Sonntag stehen
rechts), Beschriftungen und Monatsnamen sind deutsch.

**Bewusste Entscheidung:** Die Sprache ist fest verdrahtet und folgt **nicht** der Systemsprache
des Geräts — die App ist durchgehend deutsch, ein englisches Handy soll keine gemischte
Oberfläche ergeben. Falls später weitere Sprachen dazukommen, ist `locale:` in
[lib/main.dart](lib/main.dart) der Punkt zum Ändern.

**Nebeneffekt:** Alle eingebauten Material-Dialoge sind jetzt deutsch (z. B. „Abbrechen" statt
„Cancel"), und die Uhrzeitauswahl nutzt das 24-Stunden-Format statt AM/PM.

### 4. Geänderter Sphere-Titel erscheint erst nach erneutem Öffnen in der Liste
**Gemeldet:** 07.08.2026 · **Erledigt in:** v1.0.13 · **Plattformen:** Desktop + App

**Problem:** Nach dem Umbenennen einer Sphere zeigte die Orbit-Liste beim Zurückgehen weiter
den alten Titel. Erst erneutes Öffnen der Sphere (oder der 30-Sekunden-Poll) brachte den
neuen Namen.

**Ursache:** Zwei Punkte, die zusammenwirkten.
1. `TaskService` ist ein `ChangeNotifier`, aber von 15 datenverändernden Methoden riefen nur
   vier `notifyListeners()`. Die Listenansichten horchen korrekt auf den Service — sie warteten
   nur auf ein Signal, das nie kam.
2. Der Titel wird erst gespeichert, wenn das Eingabefeld den Fokus verliert. Beim direkten
   Tippen auf „Zurück" ist das ein Wettlauf gegen den Abbau der Ansicht.

**Lösung:** `notifyListeners()` in allen verändernden Methoden ergänzt (Titel, Beschreibung,
Termine/Wiederholung, Erinnerung, Anlegen/Löschen, Orbit umbenennen/löschen, Verschieben,
Log-Eintrag, Wiedereröffnen). Zusätzlich sichert `_flushPendingEdits()` in `dispose()` offene
Eingaben, bevor die Ansicht abgebaut wird.

**Mit erledigt:** Dieselbe fehlende Benachrichtigung betraf auch Beschreibung, Fälligkeits-/
Startdatum, Wiederholung, Erinnerung und das Verschieben von Spheres — überall wäre dieselbe
Meldung noch einmal aufgeschlagen.

### 5. Einkaufslisten-Modus für Orbits
**Gewünscht:** 07.08.2026 · **Umgesetzt in:** v1.0.13 · **Plattformen:** Desktop + App

Beim Anlegen eines Orbits lässt sich per Haken „Einfache Liste (z. B. Einkaufsliste)" wählen.
Ein solcher Orbit ist bewusst abgespeckt:

| | Normaler Orbit | Einfache Liste |
|---|---|---|
| Ampelsymbol | ja | nein |
| Status-Kreis | unten, offen → in Arbeit → erledigt | **oben neben dem Namen**, ein Tippen = erledigt |
| Felder | Beschreibung, Zuweisung, Wiederholung, Termine, Erinnerung, Verlauf | nur der Name |
| Antippen | volle Detailansicht | kleiner Dialog (umbenennen/löschen) |
| Erfassen | Formular | Eingabefeld in der Liste, Enter = nächste Position |
| Erledigte | bleiben im Archiv | **werden nach 24 Std. endgültig gelöscht** |
| Team-Meldungen | ja | nein (stumm) |

**Entscheidungen:** Der Modus wird beim Anlegen festgelegt und ist danach unveränderlich —
nachträgliches Umschalten würde die Frage aufwerfen, was mit Terminen und Verläufen
bestehender Spheres geschieht. Listen-Orbits lösen keine Team-Benachrichtigungen aus, sonst
ergäben 20 erfasste Positionen 20 Meldungen beim Co-Piloten.

**Umsetzung:**
- DB: Spalte `isShoppingList` in `TaskDomain` (Migration `v10_shopping_list.sql` im
  Azure-Query-Editor ausgeführt; die Spalte steht jetzt in
  [backend/db/schema.sql](backend/db/schema.sql)).
- Backend: Feld in `GET`/`POST /domains`; Guard in `emitOrbitEvent()` (deckt alle fünf
  Ereignisarten auf einmal ab); Aufräum-Schritt im 5-Minuten-Scheduler löscht erledigte
  Positionen 24 Std. nach `completedAt` (Verlaufseinträge zuerst wegen Fremdschlüssel).
- Flutter: gemeinsame Bausteine in
  [lib/widgets/simple_list_widgets.dart](lib/widgets/simple_list_widgets.dart) und ein
  `simpleList`-Modus in [TaskListItem](lib/widgets/task_list_item.dart) — beide Plattformen
  nutzen dieselben Widgets, damit sie nicht auseinanderlaufen.
- Die Reiter heißen in Listen-Orbits „Offen"/„Erledigt" statt „Im Flug"/„Gelandet" bzw.
  „Aktiv"/„Archiv" — „Archiv" wäre bei 24-Stunden-Löschung irreführend.
- Auf dem Desktop ersetzt die schlanke Eingabe die bestehende Schnellerfassung an derselben
  Stelle (unten im Panel), statt eine zweite Eingabestelle einzuführen.

### 6. Erinnerungs-Dialog auf dem Handy unbrauchbar, Zeitpunkt nicht editierbar
**Gemeldet:** 07.08.2026 · **Erledigt in:** v1.0.13 · **Plattformen:** Desktop + App

**Problem 1:** Der selbstgebaute Kombi-Dialog („Erinnerung setzen") war auf dem Handy zu hoch —
„Abbrechen"/„Speichern" lagen quer über dem Kalender. Für die Uhrzeit erzwang er die
Zifferntastatur, die den halben Dialog verdeckte.

**Problem 2:** Ein einmal gesetzter Erinnerungszeitpunkt ließ sich nicht ändern — nur löschen
und komplett neu eingeben.

**Ursache zu 1:** Der Dialoginhalt war eine `Column` ohne Scroll-Möglichkeit bei fest
gesetzter Breite (320). Der eingebettete `CalendarDatePicker` braucht mehr Höhe, als ein Dialog
auf einem Handy hergibt. Die Uhrzeit lag in zwei `TextField` — Tippen hieß zwangsläufig
Tastatur.

**Lösung:** Eigener Dialog ersetzt durch die eingebauten Material-Dialoge, nacheinander:
`showDatePicker` → `showTimePicker`. Beide bringen für kleine Bildschirme eine eigene
Darstellung mit; die Uhrzeit wird per Zifferblatt gewählt, ganz ohne Tastatur.
[reminder_picker_dialog.dart](lib/widgets/reminder_picker_dialog.dart) enthält jetzt drei
Funktionen statt einer Dialog-Klasse: kompletter Zeitpunkt, nur Datum, nur Uhrzeit.

**Zu 2:** In der Detailansicht sind Datum und Uhrzeit **einzeln antippbar** (gepunktet
unterstrichen) und öffnen jeweils genau den passenden Dialog — der andere Teil bleibt
unverändert. „Erinnerung löschen" bleibt erhalten: als ✕ beim normalen Zustand, als
beschrifteter roter Knopf bei abgelaufener Erinnerung.

**Nebenbefund:** Abgelaufene Erinnerungen waren bisher gar nicht bearbeitbar (nur löschbar) —
jetzt sind sie es ebenfalls.
