# Feedbackliste

Gesammelte Bugs und Anpassungswünsche aus dem Beta-Test. Wird laufend gepflegt.

**Grundregel:** Jede Änderung muss in der **Desktop-Version (Windows)** und in der
**App-Version (Android)** umgesetzt werden. Vor der Umsetzung wird geprüft und
festgehalten, ob und wie weit sich die Änderung auf beiden Plattformen realisieren lässt.

---

## Offen

_(keine offenen Punkte – neue Meldungen hier eintragen)_

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
