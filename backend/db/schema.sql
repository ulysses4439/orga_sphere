-- Create database if not exists
-- (Assuming database is already created in Azure)

-- TaskDomain table
CREATE TABLE TaskDomain (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    name NVARCHAR(100) NOT NULL,
    description NVARCHAR(500)
);

-- TaskTemplate table
CREATE TABLE TaskTemplate (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    title NVARCHAR(200) NOT NULL,
    description NVARCHAR(1000),
    recurrence NVARCHAR(50) NOT NULL, -- e.g., 'none', 'daily', etc.
    domainId UNIQUEIDENTIFIER,
    createdAt DATETIME2 DEFAULT GETUTCDATE(),
    FOREIGN KEY (domainId) REFERENCES TaskDomain(id)
);

-- TaskInstance table
CREATE TABLE TaskInstance (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    templateId UNIQUEIDENTIFIER NOT NULL,
    status NVARCHAR(50) NOT NULL, -- 'open', 'inProgress', 'done'
    dueDate DATETIME2,
    createdAt DATETIME2 DEFAULT GETUTCDATE(),
    completedAt DATETIME2,
    isArchived BIT DEFAULT 0,
    FOREIGN KEY (templateId) REFERENCES TaskTemplate(id)
);

-- TaskLogEntry table
CREATE TABLE TaskLogEntry (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    instanceId UNIQUEIDENTIFIER NOT NULL,
    user NVARCHAR(100),
    timestamp DATETIME2 DEFAULT GETUTCDATE(),
    text NVARCHAR(1000) NOT NULL,
    FOREIGN KEY (instanceId) REFERENCES TaskInstance(id)
);