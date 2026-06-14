-- Migration v8: Aufgaben-Zuweisung an eine Person innerhalb eines Orbits
-- Eine Sphere (Task) kann optional einem OrbitMember (Pilot/Co-Pilot) zugewiesen werden.
-- Kein FK-Constraint, damit das Entfernen eines Mitglieds nicht blockiert wird;
-- die Aufräumung erfolgt im Backend (DELETE /domains/:id/members/:memberId).

ALTER TABLE Task ADD assignedToMemberId NVARCHAR(100) NULL;
