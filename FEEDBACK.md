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
  [v11_orbitmember_email_sync.sql](backend/db/v11_orbitmember_email_sync.sql) räumt Altbestände
  auf (Stand 08.08.2026 geprüft: keine Abweichungen vorhanden).

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
- DB: [backend/db/v10_shopping_list.sql](backend/db/v10_shopping_list.sql) — Spalte
  `isShoppingList` in `TaskDomain`. **Muss im Azure-Query-Editor ausgeführt werden.**
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
