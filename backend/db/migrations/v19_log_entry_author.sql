-- ---------------------------------------------------------------------------
-- v19 - Verfasser und Bearbeitungszeitpunkt eines Verlaufseintrags
--
-- Bisher stand in TaskLogEntry.[user] nur ein Anzeigename. Der taugt nicht als
-- Grundlage fuer eine Berechtigung: Zwei Konten duerfen denselben Namen tragen,
-- und wer seinen Namen aendert, verliert sonst den Zugriff auf seine eigenen
-- Eintraege. Fuer "nur der Verfasser darf aendern" braucht es die Konto-ID.
--
-- editedAt haelt fest, ob ein Eintrag nachtraeglich geaendert wurde. Ohne das
-- koennte jemand seinen Beitrag im Nachhinein umschreiben, ohne dass es den
-- anderen im Orbit auffaellt.
--
-- Im Azure-Portal (Query-Editor) ausfuehren. Die drei Abschnitte sind durch GO
-- getrennt und muessen in dieser Reihenfolge laufen.
-- ---------------------------------------------------------------------------

IF COL_LENGTH('TaskLogEntry', 'createdBy') IS NULL
    ALTER TABLE TaskLogEntry ADD createdBy NVARCHAR(100) NULL;
GO

IF COL_LENGTH('TaskLogEntry', 'editedAt') IS NULL
    ALTER TABLE TaskLogEntry ADD editedAt DATETIME2 NULL;
GO

-- Bestehende Eintraege ihrem Konto zuordnen.
--
-- Bewusst nur dort, wo die Zuordnung eindeutig ist: Der Abgleich laeuft ueber
-- einen Anzeigenamen, und der ist nicht eindeutig. Passen zwei Konten auf
-- denselben Namen, bleibt createdBy leer - lieber niemand darf den Eintrag
-- aendern als der Falsche.
UPDATE tle
SET createdBy = (
        SELECT MIN(au.id) FROM AppUser au
        WHERE au.email = tle.[user] OR au.displayName = tle.[user]
    )
FROM TaskLogEntry tle
WHERE tle.createdBy IS NULL
  AND (
        SELECT COUNT(*) FROM AppUser au
        WHERE au.email = tle.[user] OR au.displayName = tle.[user]
      ) = 1;
GO

-- Kontrolle: Wie viele Eintraege haben jetzt einen Verfasser?
SELECT
    COUNT(*)                                             AS eintraege_gesamt,
    SUM(CASE WHEN createdBy IS NULL THEN 1 ELSE 0 END)   AS ohne_verfasser
FROM TaskLogEntry;
