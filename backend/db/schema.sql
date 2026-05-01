-- TaskDomain table
CREATE TABLE TaskDomain (
    id NVARCHAR(100) PRIMARY KEY,
    name NVARCHAR(100) NOT NULL,
    description NVARCHAR(500)
);

-- TaskTemplate table
CREATE TABLE TaskTemplate (
    id NVARCHAR(100) PRIMARY KEY,
    domainId NVARCHAR(100) NOT NULL,
    title NVARCHAR(200) NOT NULL,
    description NVARCHAR(1000),
    startDate DATETIME2 NOT NULL,
    dueDate DATETIME2 NOT NULL,
    recurrenceFrequency NVARCHAR(50) NOT NULL DEFAULT 'none',
    recurrenceInterval INT NOT NULL DEFAULT 1,
    createdAt DATETIME2 DEFAULT GETUTCDATE(),
    FOREIGN KEY (domainId) REFERENCES TaskDomain(id)
);

-- TaskInstance table
CREATE TABLE TaskInstance (
    id NVARCHAR(100) PRIMARY KEY,
    templateId NVARCHAR(100) NOT NULL,
    domainId NVARCHAR(100) NOT NULL,
    title NVARCHAR(200) NOT NULL,
    description NVARCHAR(1000),
    startDate DATETIME2 NOT NULL,
    dueDate DATETIME2 NOT NULL,
    status NVARCHAR(50) NOT NULL DEFAULT 'open',
    createdAt DATETIME2 DEFAULT GETUTCDATE(),
    completedAt DATETIME2,
    FOREIGN KEY (templateId) REFERENCES TaskTemplate(id),
    FOREIGN KEY (domainId) REFERENCES TaskDomain(id)
);

-- TaskLogEntry table
CREATE TABLE TaskLogEntry (
    id NVARCHAR(100) PRIMARY KEY,
    instanceId NVARCHAR(100) NOT NULL,
    [user] NVARCHAR(100),
    [text] NVARCHAR(1000) NOT NULL,
    timestamp DATETIME2 DEFAULT GETUTCDATE(),
    FOREIGN KEY (instanceId) REFERENCES TaskInstance(id)
);
