-- Migration v7: dueDate in Task optional machen
-- Einmalig in Azure SQL ausführen (Query-Editor im Azure Portal)

ALTER TABLE Task ALTER COLUMN dueDate DATETIME2 NULL;
