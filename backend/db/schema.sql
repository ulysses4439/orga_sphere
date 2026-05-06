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
