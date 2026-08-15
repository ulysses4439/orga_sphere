/// Wiederholungsrechnung — gespiegelt zum Backend.
///
/// Zweck: Ein Gerät ohne Netz muss die nächste Ausgabe einer wiederkehrenden
/// Sphere selbst anlegen können. Wer zwei Tage im Flugzeug sitzt und täglich
/// „Medikamente nehmen" abhakt, braucht am zweiten Tag die Sphere für den
/// zweiten Tag — die entsteht sonst erst beim Abgleich.
///
/// **Was hier gerechnet wird und was nicht**, ist eine bewusste Grenze:
///
/// Nur das START- und Fälligkeitsdatum, und das ist reine Kalenderarithmetik:
/// Tag plus N, Monat plus N. Dieselben Überläufe wie im Backend (Tag 35 wird
/// zum Folgemonat), weil `DateTime` genau wie `Date` in JavaScript umrollt.
/// Deshalb kommen beide Seiten zuverlässig auf dasselbe Ergebnis — und damit
/// auf dieselbe Kennung.
///
/// Die **Erinnerungsuhrzeit** wird hier nur grob mitgeführt. Sie hängt an der
/// Zeitzone und der Sommerzeitumstellung, und diese Rechnung bleibt beim
/// Server, wo sie erprobt ist. Der Server korrigiert die Uhrzeit beim
/// Abgleich; bis dahin ist der lokale Wert eine Vorschau. Eine Abweichung
/// führt dort zu einer falschen Uhrzeit, nicht zu einer doppelten Sphere.
library;

/// Nächstes Datum im Rhythmus. `null` bleibt `null` — eine Sphere ohne
/// Fälligkeitsdatum bekommt auch in der nächsten Ausgabe keines.
///
/// Entspricht `nextDate` im Backend.
DateTime? naechstesDatum(DateTime? aktuell, String frequenz, int intervall) {
  if (aktuell == null) return null;
  switch (frequenz) {
    case 'daily':
      return DateTime.utc(aktuell.year, aktuell.month, aktuell.day + intervall,
          aktuell.hour, aktuell.minute, aktuell.second);
    case 'weekly':
      return DateTime.utc(aktuell.year, aktuell.month,
          aktuell.day + 7 * intervall, aktuell.hour, aktuell.minute, aktuell.second);
    case 'monthly':
      return DateTime.utc(aktuell.year, aktuell.month + intervall, aktuell.day,
          aktuell.hour, aktuell.minute, aktuell.second);
    case 'yearly':
      return DateTime.utc(aktuell.year + intervall, aktuell.month, aktuell.day,
          aktuell.hour, aktuell.minute, aktuell.second);
    default:
      return null;
  }
}

/// Kennung der Ausgabe einer Serie zu einem Termin.
///
/// Muss **zeichengenau** dasselbe liefern wie `seriesOccurrenceId` im Backend.
/// Weicht sie ab, entstehen zwei Zeilen für denselben Termin — genau das, was
/// die berechenbare Kennung verhindern soll. Deshalb hier wie dort: UTC-Datum,
/// zweistellig aufgefüllt, mit Doppelpunkt getrennt.
String serienAusgabeId(String seriesId, DateTime startDatum) {
  final d = startDatum.toUtc();
  final tag = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  return '$seriesId:$tag';
}
