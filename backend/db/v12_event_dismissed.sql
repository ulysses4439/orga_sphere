-- v12: Meldungen der Glocke je Nutzer ausblenden
--
-- OrbitEvent enthaelt EINE Zeile pro Ereignis, geteilt von allen Mitgliedern
-- des Orbits. Ein echtes DELETE wuerde die Meldung deshalb bei ALLEN
-- Beteiligten entfernen. Stattdessen merkt sich diese Tabelle je Nutzer,
-- welche Meldung er fuer sich ausgeblendet hat; GET /events blendet sie dann
-- nur fuer ihn aus.
--
-- Bewusst serverseitig statt im Geraetespeicher: Wer am Desktop aufraeumt,
-- soll die Meldung auch am Handy los sein.
--
-- Ausfuehren im Azure-Portal: SQL-DB orgaSphereDb -> Query-Editor -> Run.

CREATE TABLE OrbitEventDismissed (
    eventId     NVARCHAR(100) NOT NULL,
    userId      NVARCHAR(100) NOT NULL,
    dismissedAt DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT PK_OrbitEventDismissed PRIMARY KEY (eventId, userId),
    CONSTRAINT FK_OrbitEventDismissed_Event
        FOREIGN KEY (eventId) REFERENCES OrbitEvent(id) ON DELETE CASCADE,
    CONSTRAINT FK_OrbitEventDismissed_User
        FOREIGN KEY (userId) REFERENCES AppUser(id)
);

-- Der Filter in GET /events fragt immer nach userId + eventId; der
-- Primaerschluessel deckt das ab. Zusaetzlicher Index fuer das Aufraeumen
-- aller Meldungen eines Nutzers.
CREATE INDEX IX_OrbitEventDismissed_User ON OrbitEventDismissed (userId);
