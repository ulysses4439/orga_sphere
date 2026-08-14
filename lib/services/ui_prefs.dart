import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Merkt sich Einstellungen der Oberflaeche ueber Neustarts hinweg.
///
/// Liegt im selben Speicher wie Token und Glocken-Zustand – nicht weil die
/// Breite eines Fensters schuetzenswert waere, sondern weil die App damit ohne
/// zusaetzliches Paket auskommt (dasselbe macht [NotificationCenter] fuer den
/// „gelesen bis"-Zeitpunkt).
///
/// Alle Zugriffe schlucken ihre Fehler: Eine nicht gemerkte Fensterbreite ist
/// kein Grund, irgendetwas abzubrechen – im schlimmsten Fall steht die Pane
/// nach dem Neustart wieder auf dem Standardwert.
class UiPrefs {
  static const _storage = FlutterSecureStorage();
  static const _detailPaneWidthKey = 'ui_detail_pane_width';

  /// Zuletzt eingestellte Breite der Detailansicht, oder `null` fuer „nie
  /// verstellt". Die Grenzen prueft der Aufrufer – sie haengen an der
  /// Fensterbreite und koennen sich zwischen zwei Starts geaendert haben.
  static Future<double?> loadDetailPaneWidth() async {
    try {
      final raw = await _storage.read(key: _detailPaneWidthKey);
      if (raw == null) return null;
      return double.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDetailPaneWidth(double width) async {
    try {
      await _storage.write(
        key: _detailPaneWidthKey,
        value: width.toStringAsFixed(0),
      );
    } catch (_) {
      // bewusst still – siehe Klassenkommentar
    }
  }
}
