-- Migration v6: Passwort-Reset-Felder für AppUser
-- Einmalig in Azure SQL ausführen (Query-Editor im Azure Portal)

ALTER TABLE AppUser ADD resetToken NVARCHAR(255) NULL;
ALTER TABLE AppUser ADD resetTokenExpiry DATETIME2 NULL;
