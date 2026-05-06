-- Migration v4: E-Mail-Benachrichtigungen für Erinnerungen
-- reminderEmailSentAt: verhindert Doppelversand durch den Scheduler
-- notificationEmails:  komma-getrennte E-Mail-Liste pro Orbit
ALTER TABLE Task       ADD reminderEmailSentAt DATETIME2     NULL;
ALTER TABLE TaskDomain ADD notificationEmails  NVARCHAR(1000) NULL;
