-- ============================================================================
-- OrgaSphere - vollstaendiges Datenbankschema (Azure SQL, DB "orgaSphereDb")
--
-- Stand: App v1.0.15 / Migrationsstand v13.
-- Diese Datei ist die EINZIGE Beschreibung des Schemas: Alle frueheren
-- Einzelmigrationen (migrate_v2 ... v13) sind hier eingearbeitet und wurden
-- danach entfernt. Sie baut eine leere Datenbank komplett neu auf.
--
-- Reihenfolge der CREATE-Statements ist wegen der Fremdschluessel bindend.
--
-- ARBEITSWEISE bei kuenftigen Schema-Aenderungen:
--   1. Migrations-Skript (ALTER TABLE ...) im Azure-Portal ausfuehren:
--      SQL-DB orgaSphereDb -> Query-Editor -> Run
--   2. Die Aenderung SOFORT hier eintragen, damit diese Datei nicht veraltet.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- TaskDomain - ein "Orbit"
-- isShoppingList = 1: Orbit verhaelt sich wie eine Einkaufsliste (Positionen
--   nur mit Titel, ein Klick landet direkt, gelandete Eintraege werden nach
--   24 h geloescht, keine Team-Benachrichtigungen).
-- ----------------------------------------------------------------------------
CREATE TABLE TaskDomain (
    id             NVARCHAR(100) NOT NULL PRIMARY KEY,
    name           NVARCHAR(100) NOT NULL,
    description    NVARCHAR(500) NULL,
    color          NVARCHAR(7)   NOT NULL DEFAULT '#F5F5F5',
    isShoppingList BIT           NOT NULL DEFAULT 0
);


-- ----------------------------------------------------------------------------
-- AppUser - Konto (E-Mail + Passwort)
-- displayName: Klarname fuer Anzeige; faellt auf email zurueck, wenn leer.
-- resetToken/-Expiry: Passwort-zuruecksetzen-Flow.
-- ----------------------------------------------------------------------------
CREATE TABLE AppUser (
    id               NVARCHAR(100) NOT NULL PRIMARY KEY,
    email            NVARCHAR(255) NOT NULL,
    passwordHash     NVARCHAR(255) NOT NULL,
    displayName      NVARCHAR(200) NULL,
    createdAt        DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    resetToken       NVARCHAR(255) NULL,
    resetTokenExpiry DATETIME2     NULL,
    CONSTRAINT UQ_AppUser_Email UNIQUE (email)
);


-- ----------------------------------------------------------------------------
-- OrbitMember - Mitgliedschaft eines Nutzers in einem Orbit
-- userId ist NULL, solange die eingeladene Person sich noch nicht
--   registriert hat (status 'pending'); der Bezug laeuft dann ueber email.
-- role:   'pilot' | 'copilot'
-- status: 'active' | 'suspended' | 'pending'
-- Hinweis: email wird bei einer Profil-Aenderung aus AppUser mitgezogen
--   (PATCH /auth/profile) - der Erinnerungs-Scheduler verschickt an diese
--   Adresse, nicht an AppUser.email.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Task - eine "Sphere" (Kapsel). Wiederkehrende Aufgaben bilden ueber
--   previousTaskId eine Kette.
-- startDate/dueDate sind reine KALENDERDATEN - die Uhrzeit ist immer
--   00:00:00. Keine UTC-Umrechnung beim Speichern, sonst rutscht das Datum
--   einen Tag zurueck (der Fehler, den v13 einmalig geradegerueckt hat).
-- dueDate ist optional.
-- assignedToMemberId: bewusst OHNE FK-Constraint, damit das Entfernen eines
--   Mitglieds nicht blockiert; das Aufraeumen macht das Backend
--   (DELETE /domains/:id/members/:memberId).
-- reminderEmailSentAt: verhindert Doppelversand durch den Scheduler.
-- ----------------------------------------------------------------------------
CREATE TABLE Task (
    id                  NVARCHAR(100)  NOT NULL PRIMARY KEY,
    domainId            NVARCHAR(100)  NOT NULL,
    title               NVARCHAR(200)  NOT NULL,
    description         NVARCHAR(1000) NULL,
    startDate           DATETIME2      NOT NULL,
    dueDate             DATETIME2      NULL,
    recurrenceFrequency NVARCHAR(50)   NOT NULL DEFAULT 'none',
    recurrenceInterval  INT            NOT NULL DEFAULT 1,
    status              NVARCHAR(50)   NOT NULL DEFAULT 'open',
    createdAt           DATETIME2      NULL DEFAULT GETUTCDATE(),
    completedAt         DATETIME2      NULL,
    reminderAt          DATETIME2      NULL,
    reminderEmailSentAt DATETIME2      NULL,
    previousTaskId      NVARCHAR(100)  NULL,
    assignedToMemberId  NVARCHAR(100)  NULL,
    CONSTRAINT FK_Task_Domain       FOREIGN KEY (domainId)       REFERENCES TaskDomain(id),
    CONSTRAINT FK_Task_PreviousTask FOREIGN KEY (previousTaskId) REFERENCES Task(id)
);


-- ----------------------------------------------------------------------------
-- TaskLogEntry - Aktivitaetsverlauf einer Sphere
-- [user] haelt den Namen zum Zeitpunkt des Eintrags; die Anzeige bevorzugt
--   den aktuellen AppUser.displayName (COALESCE in GET /tasks/:id/log).
-- ----------------------------------------------------------------------------
CREATE TABLE TaskLogEntry (
    id        NVARCHAR(100)  NOT NULL PRIMARY KEY,
    taskId    NVARCHAR(100)  NOT NULL,
    [user]    NVARCHAR(100)  NULL,
    [text]    NVARCHAR(1000) NOT NULL,
    timestamp DATETIME2      NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_TaskLogEntry_Task FOREIGN KEY (taskId) REFERENCES Task(id)
);


-- ----------------------------------------------------------------------------
-- DeviceToken - registrierte Push-Tokens je Nutzer
-- Ein Nutzer kann mehrere Geraete haben; token ist global eindeutig.
-- platform: 'android' | 'windows' | 'ios'
-- ----------------------------------------------------------------------------
CREATE TABLE DeviceToken (
    id         NVARCHAR(100) NOT NULL PRIMARY KEY,
    userId     NVARCHAR(100) NOT NULL,
    token      NVARCHAR(500) NOT NULL,
    platform   NVARCHAR(20)  NOT NULL,
    createdAt  DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    lastSeenAt DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_DeviceToken_User  FOREIGN KEY (userId) REFERENCES AppUser(id),
    CONSTRAINT UQ_DeviceToken_Token UNIQUE (token)
);


-- ----------------------------------------------------------------------------
-- OrbitEvent - Feed der Team-Ereignisse je Orbit
--   (In-App-Glocke + Windows-Toast-Polling)
-- type: 'sphere_created' | 'sphere_landed' | 'sphere_assigned' | 'log_added'
--       | 'reminder' | 'member_joined' | 'member_declined'
-- body: fertiger Anzeigetext
-- actorUserId: Ausloeser - wird beim Abruf herausgefiltert (niemand sieht
--   die eigene Aktion).
-- targetUserId: NULL = Meldung fuer alle aktiven Mitglieder des Orbits (der
--   Normalfall). Ist ein Wert gesetzt, sieht nur dieser Nutzer die Meldung und
--   nur sein Geraet bekommt den Push. Gedacht fuer Vorgaenge, die genau einen
--   etwas angehen - etwa 'member_declined': Dass eine Einladung abgelehnt
--   wurde, ist Sache des Piloten; fuer die uebrigen Co-Piloten ist jemand, der
--   nie dabei war, keine Nachricht wert.
-- ----------------------------------------------------------------------------
CREATE TABLE OrbitEvent (
    id           NVARCHAR(100)  NOT NULL PRIMARY KEY,
    orbitId      NVARCHAR(100)  NOT NULL,
    actorUserId  NVARCHAR(100)  NULL,
    actorName    NVARCHAR(200)  NULL,
    type         NVARCHAR(30)   NOT NULL,
    sphereId     NVARCHAR(100)  NULL,
    sphereTitle  NVARCHAR(200)  NULL,
    orbitName    NVARCHAR(200)  NULL,
    body         NVARCHAR(1000) NOT NULL,
    createdAt    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    targetUserId NVARCHAR(100)  NULL
);

CREATE INDEX IX_OrbitEvent_Orbit_CreatedAt ON OrbitEvent (orbitId, createdAt DESC);


-- ----------------------------------------------------------------------------
-- OrbitEventDismissed - je Nutzer ausgeblendete Meldungen
-- OrbitEvent haelt EINE Zeile pro Ereignis, geteilt von allen Mitgliedern des
-- Orbits. Ein echtes DELETE wuerde die Meldung deshalb bei allen entfernen.
-- Bewusst serverseitig statt im Geraetespeicher: Wer am Desktop aufraeumt,
-- soll die Meldung auch am Handy los sein.
-- ----------------------------------------------------------------------------
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

-- Der Filter in GET /events fragt immer nach userId + eventId; das deckt der
-- Primaerschluessel ab. Zusaetzlicher Index fuer das Aufraeumen aller
-- Meldungen eines Nutzers ("alle ausblenden").
CREATE INDEX IX_OrbitEventDismissed_User ON OrbitEventDismissed (userId);
