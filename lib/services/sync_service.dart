import 'dart:io' show File;

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'outbox.dart';

/// Bringt die wartenden Änderungen zum Server.
///
/// Trennt zwei Dinge sauber: Die [Outbox] kennt Reihenfolge und Ablage, dieser
/// Dienst kennt das Netz. Die entscheidende Arbeit ist die **Einordnung** einer
/// gescheiterten Übertragung — davon hängt ab, ob eine Änderung erhalten bleibt
/// oder verloren geht.
class SyncService {
  static final SyncService _instance = SyncService._();
  factory SyncService() => _instance;
  SyncService._();

  final Outbox _outbox = Outbox();

  /// Arbeitet die Warteschlange ab. Gefahrlos mehrfach aufrufbar – die Outbox
  /// lässt nur einen Durchlauf gleichzeitig zu.
  Future<void> abgleichen() => _outbox.abarbeiten(_senden);

  Future<OutboxErgebnis> _senden(OutboxCommand befehl) async {
    try {
      final staged = befehl.stagedFilePath;
      if (staged != null) {
        // Anhang: mehrteilige Übertragung mit der zwischengelagerten Datei.
        final datei = File(staged);
        if (!await datei.exists()) {
          // Die Datei ist weg – ohne sie ist der Auftrag nicht mehr
          // ausführbar. Verwerfen statt ewig scheitern zu lassen.
          befehl.letzterFehler = 'Zwischengelagerte Datei nicht mehr vorhanden';
          return OutboxErgebnis.abgelehnt;
        }
        await ApiService.uploadAttachment(
          befehl.body?['taskId'] as String? ?? '',
          bytes: await datei.readAsBytes(),
          fileName: befehl.body?['fileName'] as String? ?? 'datei',
          contentType: befehl.body?['contentType'] as String? ?? 'application/octet-stream',
          attachmentId: befehl.body?['id'] as String?,
          commandId: befehl.id,
        );
        return OutboxErgebnis.erledigt;
      }

      await ApiService.ausfuehren(
        method: befehl.method,
        path: befehl.path,
        commandId: befehl.id,
        body: {
          ...?befehl.body,
          // Der Server übernimmt diesen Zeitpunkt statt „jetzt" zu setzen.
          'occurredAt': befehl.occurredAt.toIso8601String(),
        },
      );
      return OutboxErgebnis.erledigt;
    } on OfflineException catch (e) {
      befehl.letzterFehler = e.grund;
      return OutboxErgebnis.offline;
    } on UnauthorizedException {
      // Sitzung abgelaufen. NICHT verwerfen: Die Änderung ist gültig, es fehlt
      // nur die Anmeldung. Nach dem nächsten Login geht es weiter – ein
      // Verwerfen wäre hier der schlimmstmögliche Ausgang.
      befehl.letzterFehler = 'Anmeldung abgelaufen';
      return OutboxErgebnis.offline;
    } catch (e) {
      // Der Server hat geantwortet und abgelehnt. Wiederholen würde daran
      // nichts ändern – etwa weil die Sphere in einen fremden Orbit verschoben
      // wurde oder die Eingabe ungültig ist.
      befehl.letzterFehler = e.toString();
      debugPrint('[Sync] ${befehl.kind} endgueltig abgelehnt: $e');
      return OutboxErgebnis.abgelehnt;
    }
  }
}
