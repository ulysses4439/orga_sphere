-- Migration: TaskTemplate + TaskInstance -> Task
-- Run this once against the Azure SQL database.

-- 1. Create new Task table
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
    previousTaskId NVARCHAR(100),
    FOREIGN KEY (domainId) REFERENCES TaskDomain(id)
);

-- Self-referencing FK added separately
ALTER TABLE Task ADD CONSTRAINT FK_Task_PreviousTask
    FOREIGN KEY (previousTaskId) REFERENCES Task(id);

-- 2. Migrate existing instances (recurrence settings copied from their template)
INSERT INTO Task (id, domainId, title, description, startDate, dueDate,
                  recurrenceFrequency, recurrenceInterval, status, createdAt, completedAt)
SELECT
    i.id,
    i.domainId,
    i.title,
    ISNULL(i.description, ''),
    i.startDate,
    i.dueDate,
    ISNULL(t.recurrenceFrequency, 'none'),
    ISNULL(t.recurrenceInterval, 1),
    i.status,
    i.createdAt,
    i.completedAt
FROM TaskInstance i
LEFT JOIN TaskTemplate t ON i.templateId = t.id;

-- 3. Add taskId column to TaskLogEntry and populate from instanceId
ALTER TABLE TaskLogEntry ADD taskId NVARCHAR(100);
UPDATE TaskLogEntry SET taskId = instanceId;
ALTER TABLE TaskLogEntry ALTER COLUMN taskId NVARCHAR(100) NOT NULL;
ALTER TABLE TaskLogEntry ADD CONSTRAINT FK_TaskLogEntry_Task
    FOREIGN KEY (taskId) REFERENCES Task(id);

-- 4. Drop old FK on instanceId (constraint name may differ – check with sp_help 'TaskLogEntry')
DECLARE @fkName NVARCHAR(200);
SELECT @fkName = name FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('TaskLogEntry')
  AND name LIKE '%insta%';
IF @fkName IS NOT NULL
    EXEC('ALTER TABLE TaskLogEntry DROP CONSTRAINT ' + @fkName);

ALTER TABLE TaskLogEntry DROP COLUMN instanceId;

-- 5. Drop old tables (order matters due to FKs)
DROP TABLE TaskInstance;
DROP TABLE TaskTemplate;
