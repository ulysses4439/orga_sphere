-- Migration v9: Team-Benachrichtigungen (Push + In-App-Feed)
-- Neue Tabellen:
--   DeviceToken — registrierte Push-Tokens je Nutzer (FCM auf Android, später WNS/APNs)
--   OrbitEvent  — Feed der Team-Ereignisse je Orbit (In-App-Liste + Windows-Toast-Polling)

-- -----------------------------------------------------------------------
-- 1. DeviceToken
--    Ein Nutzer kann mehrere Geräte haben. token ist global eindeutig.
--    platform: 'android' | 'windows' | 'ios'
-- -----------------------------------------------------------------------
CREATE TABLE DeviceToken (
    id         NVARCHAR(100) NOT NULL PRIMARY KEY,
    userId     NVARCHAR(100) NOT NULL,
    token      NVARCHAR(500) NOT NULL,
    platform   NVARCHAR(20)  NOT NULL,
    createdAt  DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    lastSeenAt DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_DeviceToken_User FOREIGN KEY (userId) REFERENCES AppUser(id),
    CONSTRAINT UQ_DeviceToken_Token UNIQUE (token)
);

-- -----------------------------------------------------------------------
-- 2. OrbitEvent
--    type: 'sphere_created' | 'sphere_landed' | 'sphere_assigned' | 'log_added'
--    body: fertiger Anzeigetext (z.B. 'Steven hat "Test" zu "Schlali privat" hinzugefügt')
--    actorUserId: Auslöser – wird beim Abruf herausgefiltert (sieht eigene Aktion nicht).
-- -----------------------------------------------------------------------
CREATE TABLE OrbitEvent (
    id          NVARCHAR(100)  NOT NULL PRIMARY KEY,
    orbitId     NVARCHAR(100)  NOT NULL,
    actorUserId NVARCHAR(100)  NULL,
    actorName   NVARCHAR(200)  NULL,
    type        NVARCHAR(30)   NOT NULL,
    sphereId    NVARCHAR(100)  NULL,
    sphereTitle NVARCHAR(200)  NULL,
    orbitName   NVARCHAR(200)  NULL,
    body        NVARCHAR(1000) NOT NULL,
    createdAt   DATETIME2      NOT NULL DEFAULT GETUTCDATE()
);

CREATE INDEX IX_OrbitEvent_Orbit_CreatedAt ON OrbitEvent (orbitId, createdAt DESC);
