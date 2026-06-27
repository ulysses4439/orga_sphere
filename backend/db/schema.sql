-- TaskDomain table
CREATE TABLE TaskDomain (
    id NVARCHAR(100) PRIMARY KEY,
    name NVARCHAR(100) NOT NULL,
    description NVARCHAR(500),
    color NVARCHAR(7) NOT NULL DEFAULT '#F5F5F5',
    notificationEmails NVARCHAR(1000)
);

-- Task table (unified: replaces TaskTemplate + TaskInstance)
-- Each row is one "Kapsel" (capsule). Recurring tasks form a chain via previousTaskId.
CREATE TABLE Task (
    id NVARCHAR(100) PRIMARY KEY,
    domainId NVARCHAR(100) NOT NULL,
    title NVARCHAR(200) NOT NULL,
    description NVARCHAR(1000),
    startDate DATETIME2 NOT NULL,
    dueDate DATETIME2 NOT NULL,
    recurrenceFrequency NVARCHAR(50) NOT NULL DEFAULT 'none',
    recurrenceInterval INT NOT NULL DEFAULT 1,
    status NVARCHAR(50) NOT NULL DEFAULT 'open',
    createdAt DATETIME2 DEFAULT GETUTCDATE(),
    completedAt DATETIME2,
    reminderAt DATETIME2,
    reminderEmailSentAt DATETIME2,
    previousTaskId NVARCHAR(100),
    FOREIGN KEY (domainId) REFERENCES TaskDomain(id),
    FOREIGN KEY (previousTaskId) REFERENCES Task(id)
);

-- TaskLogEntry table
CREATE TABLE TaskLogEntry (
    id NVARCHAR(100) PRIMARY KEY,
    taskId NVARCHAR(100) NOT NULL,
    [user] NVARCHAR(100),
    [text] NVARCHAR(1000) NOT NULL,
    timestamp DATETIME2 DEFAULT GETUTCDATE(),
    FOREIGN KEY (taskId) REFERENCES Task(id)
);

-- DeviceToken table (v9) — registrierte Push-Tokens je Nutzer
-- platform: 'android' | 'windows' | 'ios'
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

-- OrbitEvent table (v9) — Feed der Team-Ereignisse je Orbit
-- type: 'sphere_created' | 'sphere_landed' | 'sphere_assigned' | 'log_added'
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
