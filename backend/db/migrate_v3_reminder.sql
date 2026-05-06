-- Migration v3: Erinnerungsfunktion
-- Fügt reminderAt-Spalte zur Task-Tabelle hinzu.
-- Gilt orbit-weit für alle Nutzer (kein Nutzer-FK nötig).
ALTER TABLE Task ADD reminderAt DATETIME2 NULL;
