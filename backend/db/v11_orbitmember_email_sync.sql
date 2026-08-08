-- v11: OrbitMember-Adressen mit dem Konto abgleichen
--
-- Hintergrund: Eine E-Mail-Aenderung im Profil hat frueher nur AppUser
-- aktualisiert. Die zugehoerigen OrbitMember-Zeilen behielten die alte
-- Adresse. Folgen:
--   * Der Einladen-Knopf verschwand, weil die App den Piloten ueber die
--     E-Mail erkannt hat (ab v1.0.14 laeuft das ueber die userId).
--   * Erinnerungsmails gehen an OrbitMember.email - also an die alte Adresse.
--
-- Der Auslöser ist ab v1.0.14 im Backend behoben (PATCH /auth/profile zieht
-- OrbitMember mit). Dieses Skript raeumt bereits entstandene Abweichungen auf.
--
-- Ausfuehren im Azure-Portal: SQL-DB orgaSphereDb -> Query-Editor -> Run.

-- 1. ERST PRUEFEN: Welche Zeilen weichen ab? (nur Anzeige, aendert nichts)
SELECT
    om.id            AS orbitMemberId,
    d.name           AS orbit,
    om.role,
    om.status,
    om.email         AS alteAdresse,
    u.email          AS aktuelleAdresse
FROM OrbitMember om
JOIN AppUser u     ON u.id = om.userId
JOIN TaskDomain d  ON d.id = om.orbitId
WHERE om.userId IS NOT NULL
  AND om.email <> u.email;

-- 2. DANN KORRIGIEREN: Adressen aus dem Konto uebernehmen.
--    Nur Zeilen mit verknuepftem Konto - Einladungen ohne Konto (userId NULL,
--    status 'pending') behalten ihre Adresse, sie ist dort der einzige Bezug.
UPDATE om
SET om.email = u.email
FROM OrbitMember om
JOIN AppUser u ON u.id = om.userId
WHERE om.userId IS NOT NULL
  AND om.email <> u.email;

-- 3. KONTROLLE: sollte 0 Zeilen liefern.
SELECT COUNT(*) AS verbleibendeAbweichungen
FROM OrbitMember om
JOIN AppUser u ON u.id = om.userId
WHERE om.userId IS NOT NULL
  AND om.email <> u.email;
