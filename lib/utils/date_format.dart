/// Einheitliche Datumsformatierung für die gesamte App.
///
/// Regel: Ein Datum wird IMMER als TT.MM.JJJJ dargestellt (z. B. 01.07.2026).
/// Datum mit Uhrzeit als TT.MM.JJJJ, HH:mm Uhr.
///
/// Hinweis zu Zeitzonen: Diese Funktionen formatieren den übergebenen Wert
/// unverändert. Zeitstempel, die in UTC vorliegen (z. B. reminderAt), vorher
/// mit `.toLocal()` umwandeln.
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// Datum als TT.MM.JJJJ, z. B. 01.07.2026.
String formatDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// Datum + Uhrzeit als TT.MM.JJJJ, HH:mm Uhr, z. B. 01.07.2026, 09:00 Uhr.
String formatDateTime(DateTime d) =>
    '${formatDate(d)}, ${_two(d.hour)}:${_two(d.minute)} Uhr';
