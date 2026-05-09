-- Migration v5: Authentifizierung und Nutzermodell (Pilot / Co-Pilot)
-- Neue Tabellen: AppUser, OrbitMember
-- Entfernt: TaskDomain.notificationEmails (wird durch OrbitMember ersetzt)
-- Bestehende Orbits: steven.dieckmann@flow-it-up.de wird als Pilot vorgemerkt (userId NULL
--   bis zum ersten Login – der Backend-Code verknüpft den Account dann automatisch).

-- -----------------------------------------------------------------------
-- 1. AppUser
-- -----------------------------------------------------------------------
CREATE TABLE AppUser (
    id           NVARCHAR(100) NOT NULL PRIMARY KEY,
    email        NVARCHAR(255) NOT NULL,
    passwordHash NVARCHAR(255) NOT NULL,
    createdAt    DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_AppUser_Email UNIQUE (email)
);

-- -----------------------------------------------------------------------
-- 2. OrbitMember
--    userId ist NULL solange der eingeladene Nutzer sich noch nicht registriert hat.
--    status: 'active' | 'suspended' | 'pending'
--    role:   'pilot'  | 'copilot'
-- -----------------------------------------------------------------------
CREATE TABLE OrbitMember (
    id          NVARCHAR(100) NOT NULL PRIMARY KEY,
    orbitId     NVARCHAR(100) NOT NULL,
    userId      NVARCHAR(100) NULL,
    email       NVARCHAR(255) NOT NULL,
    role        NVARCHAR(20)  NOT NULL,
    status      NVARCHAR(20)  NOT NULL DEFAULT 'active',
    inviteToken NVARCHAR(255) NULL,
    invitedAt   DATETIME2     NULL,
    joinedAt    DATETIME2     NULL,
    CONSTRAINT FK_OrbitMember_Orbit FOREIGN KEY (orbitId) REFERENCES TaskDomain(id),
    CONSTRAINT FK_OrbitMember_User  FOREIGN KEY (userId)  REFERENCES AppUser(id),
    CONSTRAINT UQ_OrbitMember_Email UNIQUE (orbitId, email)
);

-- -----------------------------------------------------------------------
-- 3. Bestehende Orbits: Admin als Pilot vormerken
--    userId bleibt NULL, wird beim ersten Login von steven.dieckmann@flow-it-up.de gesetzt.
-- -----------------------------------------------------------------------
INSERT INTO OrbitMember (id, orbitId, userId, email, role, status, joinedAt)
SELECT
    NEWID(),
    id,
    NULL,
    'steven.dieckmann@flow-it-up.de',
    'pilot',
    'active',
    GETUTCDATE()
FROM TaskDomain;

-- -----------------------------------------------------------------------
-- 4. notificationEmails-Spalte aus TaskDomain entfernen
--    (wird jetzt durch OrbitMember abgebildet)
-- -----------------------------------------------------------------------
ALTER TABLE TaskDomain DROP COLUMN notificationEmails;
