import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'api_service.dart';

/// Holt einen Anhang aus der App heraus – auf jeder Plattform auf dem Weg, den
/// die Leute dort kennen.
///
/// Ein Bild schaut man an, eine Datei will man haben: Ein PDF oder eine
/// Tabelle nützt nichts, solange sie nur in der Sphere liegt. Auf dem Rechner
/// führt der Weg über einen „Speichern unter"-Dialog, auf dem Handy über die
/// Teilen-Funktion des Systems – dort gibt es keinen Speichern-Dialog, und
/// `file_selector` bietet auf Android folgerichtig auch keinen an.
///
/// Der Dienst gibt ein [AnhangErgebnis] zurueck, statt selbst Meldungen
/// anzuzeigen. So muss kein BuildContext über die Wartezeiten hinweg
/// festgehalten werden – die Anzeige macht der Aufrufer, wenn er noch da ist.
class AttachmentFiles {
  /// Auf dem Rechner gibt es einen Speichern-Dialog, auf dem Handy nicht.
  static bool get istRechner =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// Speichert (Rechner) bzw. reicht weiter (Handy).
  ///
  /// Gibt `null` zurueck, wenn der Nutzer den Dialog abgebrochen hat – das ist
  /// kein Fehler und braucht keine Meldung.
  static Future<AnhangErgebnis?> herausgeben(SphereAttachment anhang) async {
    if (anhang.isExpired) {
      return AnhangErgebnis.fehler(
        '„${anhang.fileName}" wurde nach einem Jahr entfernt.',
      );
    }

    try {
      if (istRechner) {
        // Erst fragen, wohin – dann erst laden. Wer den Dialog abbricht, soll
        // nicht vorher eine 8-MB-Datei heruntergeladen bekommen.
        final ziel = await getSaveLocation(suggestedName: anhang.fileName);
        if (ziel == null) return null;

        final bytes = await ApiService.downloadAttachment(anhang.id);
        await File(ziel.path).writeAsBytes(bytes);
        return AnhangErgebnis.gespeichert(ziel.path);
      }

      // Handy: in den Zwischenspeicher der App schreiben und dem System
      // uebergeben. Von dort aus entscheidet der Nutzer, wohin es geht –
      // Dateien-App, Drive, Messenger.
      final bytes = await ApiService.downloadAttachment(anhang.id);
      final ordner = await getTemporaryDirectory();
      final datei = File('${ordner.path}${Platform.pathSeparator}${_sicher(anhang.fileName)}');
      await datei.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(datei.path)], fileNameOverrides: [anhang.fileName]),
      );
      return AnhangErgebnis.geteilt();
    } catch (e) {
      debugPrint('[Anhänge] Herausgeben fehlgeschlagen: $e');
      return AnhangErgebnis.fehler('Die Datei konnte nicht bereitgestellt werden: $e');
    }
  }

  /// Zeigt die gespeicherte Datei im Explorer an (nur Windows).
  ///
  /// Der Komma-Aufbau ist keine Schludrigkeit, sondern die Erwartung des
  /// Explorers: `/select,C:\Pfad\Datei` muss als EIN Argument ankommen.
  static Future<void> imOrdnerZeigen(String pfad) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await Process.run('explorer.exe', ['/select,$pfad']);
    } catch (e) {
      debugPrint('[Anhänge] Ordner öffnen fehlgeschlagen: $e');
    }
  }

  /// Entfernt aus einem Dateinamen alles, was in einem Pfad nichts zu suchen
  /// hat. Der Name kommt vom Server und damit urspruenglich von einem Menschen.
  static String _sicher(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

/// Was beim Herausgeben herausgekommen ist.
class AnhangErgebnis {
  final String meldung;
  final bool erfolg;

  /// Nur beim Speichern auf dem Rechner gesetzt – erlaubt „Ordner öffnen".
  final String? pfad;

  const AnhangErgebnis._(this.meldung, this.erfolg, this.pfad);

  factory AnhangErgebnis.gespeichert(String pfad) =>
      AnhangErgebnis._('Gespeichert unter ${_dateiname(pfad)}', true, pfad);

  factory AnhangErgebnis.geteilt() =>
      const AnhangErgebnis._('Datei bereitgestellt.', true, null);

  factory AnhangErgebnis.fehler(String meldung) =>
      AnhangErgebnis._(meldung, false, null);

  static String _dateiname(String pfad) => pfad.split(RegExp(r'[\\/]')).last;
}
