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
    '${formatDate(d)}, ${formatTime(d)}';

/// Nur die Uhrzeit als HH:mm Uhr, z. B. 09:00 Uhr. Für Stellen, an denen
/// Datum und Uhrzeit getrennt dargestellt werden.
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)} Uhr';

/// Wie lange etwas her ist, in Alltagssprache: „gerade eben", „vor 5 Minuten",
/// „vor 2 Stunden". Ab einem Tag wird es unhandlich – dann steht wieder das
/// Datum da, damit niemand „vor 37 Stunden" im Kopf umrechnen muss.
///
/// Gedacht für die Anzeige, wie alt der angezeigte Datenstand ist.
String formatAge(DateTime d) {
  final minutes = DateTime.now().difference(d).inMinutes;
  if (minutes < 1) return 'gerade eben';
  if (minutes == 1) return 'vor 1 Minute';
  if (minutes < 60) return 'vor $minutes Minuten';
  final hours = minutes ~/ 60;
  if (hours == 1) return 'vor 1 Stunde';
  if (hours < 24) return 'vor $hours Stunden';
  return 'vom ${formatDateTime(d)}';
}
