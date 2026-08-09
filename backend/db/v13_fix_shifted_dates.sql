-- v13: Um Stunden verschobene Start-/Faelligkeitsdaten geraderuecken
--
-- Ursache (ab v1.0.15 behoben): Beim Aendern ueber die Detailansicht wurden
-- Start- und Faelligkeitsdatum in UTC umgerechnet uebertragen. Aus Mitternacht
-- deutscher Zeit wurde dadurch 22:00 (Sommerzeit) bzw. 23:00 (Winterzeit) des
-- VORTAGES. In der Anzeige sprang das Datum entsprechend einen Tag zurueck.
--
-- Start- und Faelligkeitsdatum sind reine Kalenderdaten; korrekt ist immer
-- 00:00:00. Dieses Skript hebt betroffene Werte auf die naechste Mitternacht.
--
-- Ausfuehren im Azure-Portal: SQL-DB orgaSphereDb -> Query-Editor -> Run.

-- 1. ERST PRUEFEN: Welche Zeilen haben eine Uhrzeit ungleich 00:00?
--    (nur Anzeige, aendert nichts)
SELECT
    t.id,
    t.title,
    t.startDate,
    t.dueDate,
    CASE WHEN CAST(t.startDate AS TIME) <> '00:00:00' THEN 'ja' ELSE '' END AS startVerschoben,
    CASE WHEN CAST(t.dueDate   AS TIME) <> '00:00:00' THEN 'ja' ELSE '' END AS faelligVerschoben
FROM Task t
WHERE CAST(t.startDate AS TIME) <> '00:00:00'
   OR CAST(t.dueDate   AS TIME) <> '00:00:00';

-- 2. DANN KORRIGIEREN.
--
--    ACHTUNG, zwei voellig verschiedene Faelle - eine pauschale Regel richtet
--    hier Schaden an (Pruefung vom 09.08.2026: 1 Zeile Fall A, 49 Fall B):
--
--    Fall A - Zeitzonen-Verschiebung: Uhrzeit ist EXAKT 22:00:00 (Sommerzeit)
--             oder 23:00:00 (Winterzeit). Der Tag ist um eins zu frueh und
--             muss angehoben werden.
--
--    Fall B - Erfassungszeitpunkt aus der Schnellerfassung, die frueher
--             DateTime.now() als Startdatum gesetzt hat (z.B. 16:48:36.245).
--             Der TAG STIMMT BEREITS - hier darf nur die Uhrzeit weg, sonst
--             wandert die Aufgabe faelschlich einen Tag nach hinten.
--
--    Unterscheidungsmerkmal: Fall A hat glatte Minuten und Sekunden.

-- Fall A: exakt 22:00 / 23:00 -> auf die naechste Mitternacht anheben
UPDATE Task
SET startDate = DATEADD(DAY, 1, CAST(CAST(startDate AS DATE) AS DATETIME2))
WHERE CAST(startDate AS TIME) IN ('22:00:00', '23:00:00');

UPDATE Task
SET dueDate = DATEADD(DAY, 1, CAST(CAST(dueDate AS DATE) AS DATETIME2))
WHERE dueDate IS NOT NULL
  AND CAST(dueDate AS TIME) IN ('22:00:00', '23:00:00');

-- Fall B: alles Uebrige -> nur die Uhrzeit abschneiden, Tag bleibt
UPDATE Task
SET startDate = CAST(CAST(startDate AS DATE) AS DATETIME2)
WHERE CAST(startDate AS TIME) <> '00:00:00';

UPDATE Task
SET dueDate = CAST(CAST(dueDate AS DATE) AS DATETIME2)
WHERE dueDate IS NOT NULL
  AND CAST(dueDate AS TIME) <> '00:00:00';

-- 3. KONTROLLE: sollte 0 Zeilen liefern.
SELECT COUNT(*) AS verbleibendeVerschiebungen
FROM Task
WHERE CAST(startDate AS TIME) <> '00:00:00'
   OR CAST(dueDate   AS TIME) <> '00:00:00';
