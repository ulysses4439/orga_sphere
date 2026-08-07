-- v10: Einfache Listen ("Einkaufslisten-Modus") fuer Orbits
--
-- Ein Orbit mit isShoppingList = 1 verhaelt sich wie eine Einkaufsliste:
--   * Positionen haben nur einen Titel (keine Beschreibung, Zuweisung,
--     Wiederholung, Start-/Faelligkeitsdatum, Erinnerung, Aktivitaetsverlauf)
--   * ein Klick auf den Kreis setzt direkt auf "gelandet" (kein "in Bearbeitung")
--   * gelandete Positionen werden nach 24 Stunden automatisch geloescht
--   * es werden keine Team-Benachrichtigungen ausgeloest
--
-- Ausfuehren im Azure-Portal: SQL-DB orgaSphereDb -> Query-Editor -> Run.

ALTER TABLE TaskDomain
    ADD isShoppingList BIT NOT NULL DEFAULT 0;
