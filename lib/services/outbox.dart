import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Ein Auftrag, der zum Server gebracht werden muss.
///
/// Bewusst allgemein gehalten (Methode, Pfad, Rumpf) statt für jede Aktion ein
/// eigenes Format: So gibt es **eine** Abarbeitungsschleife für alle dreizehn
/// Auftragsarten. Käme für jede eine eigene Behandlung hinzu, wäre die
/// Warteschlange schnell die fehleranfälligste Stelle der App.
class OutboxCommand {
  /// Auftragskennung. Geht als `X-Command-Id` mit und sorgt dafür, dass ein
  /// zweimal gesendeter Auftrag beim Server nur einmal wirkt.
  final String id;

  /// Wofür der Auftrag steht – nur für Protokoll und Anzeige.
  final String kind;

  final String method;
  final String path;
  final Map<String, dynamic>? body;

  /// Wann die Änderung auf dem Gerät geschah. Der Server übernimmt diesen
  /// Zeitpunkt, statt „jetzt" zu setzen – sonst stünde im Verlauf der
  /// Dienstagabend des Abgleichs statt des Samstagvormittags im Laden.
  final DateTime occurredAt;

  /// Datei, die mitgeschickt werden muss (nur bei Anhängen). Liegt im
  /// Zwischenlager der App und wird nach erfolgreichem Senden gelöscht.
  final String? stagedFilePath;

  int versuche;
  DateTime? letzterVersuch;

  /// Warum es zuletzt nicht geklappt hat – für die Anzeige bei hartnäckigen
  /// Fällen.
  String? letzterFehler;

  OutboxCommand({
    required this.id,
    required this.kind,
    required this.method,
    required this.path,
    required this.occurredAt,
    this.body,
    this.stagedFilePath,
    this.versuche = 0,
    this.letzterVersuch,
    this.letzterFehler,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'method': method,
        'path': path,
        'body': body,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'stagedFilePath': stagedFilePath,
        'versuche': versuche,
        'letzterVersuch': letzterVersuch?.toIso8601String(),
        'letzterFehler': letzterFehler,
      };

  factory OutboxCommand.fromJson(Map<String, dynamic> json) => OutboxCommand(
        id: json['id'] as String,
        kind: json['kind'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        body: (json['body'] as Map<String, dynamic>?),
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        stagedFilePath: json['stagedFilePath'] as String?,
        versuche: (json['versuche'] as num?)?.toInt() ?? 0,
        letzterVersuch: json['letzterVersuch'] != null
            ? DateTime.parse(json['letzterVersuch'] as String)
            : null,
        letzterFehler: json['letzterFehler'] as String?,
      );
}

/// Die Warteschlange der noch nicht gesendeten Änderungen.
///
/// Sie liegt als Datei auf dem Gerät und überlebt damit einen Neustart der App
/// — genau der Fall, für den sie da ist: Wer im Funkloch abhakt, schließt die
/// App und macht sie zwei Tage später wieder auf, soll seine Änderung nicht
/// verloren haben.
///
/// **Reihenfolge ist Pflicht.** Wird „Sphere anlegen" nach „Sphere erledigen"
/// gesendet, läuft das Erledigen ins Leere. Die Schlange arbeitet deshalb
/// strikt von vorn und bleibt beim ersten Auftrag stehen, der wegen fehlender
/// Verbindung scheitert.
class Outbox extends ChangeNotifier {
  static final Outbox _instance = Outbox._();
  factory Outbox() => _instance;
  Outbox._();

  static const _fileName = 'orga_sphere_outbox.json';
  static const _formatVersion = 1;
  static const _uuid = Uuid();

  /// Ab so vielen Fehlversuchen gilt ein Auftrag als hängend und wird dem
  /// Nutzer gemeldet, statt still weiter versucht zu werden.
  static const int hartnaeckigAb = 20;

  final List<OutboxCommand> _wartend = [];
  bool _geladen = false;
  bool _laeuft = false;

  /// Zuletzt beobachteter Zustand – für die Anzeige „Offline, X Änderungen
  /// warten".
  bool _offline = false;

  List<OutboxCommand> get wartend => List.unmodifiable(_wartend);
  int get anzahl => _wartend.length;
  bool get istOffline => _offline;
  bool get hatHartnaeckige => _wartend.any((c) => c.versuche >= hartnaeckigAb);

  static Future<File> _datei() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Zwischenlager für Dateien, die noch hochgeladen werden müssen.
  static Future<Directory> stagingOrdner() async {
    final dir = await getApplicationSupportDirectory();
    final ordner = Directory('${dir.path}/outbox_dateien');
    if (!await ordner.exists()) await ordner.create(recursive: true);
    return ordner;
  }

  Future<void> laden() async {
    if (_geladen) return;
    _geladen = true;
    try {
      final file = await _datei();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['formatVersion'] != _formatVersion) return;
      _wartend
        ..clear()
        ..addAll((json['commands'] as List<dynamic>)
            .map((j) => OutboxCommand.fromJson(j as Map<String, dynamic>)));
      notifyListeners();
    } catch (e) {
      // Eine unlesbare Warteschlange darf den Start nicht verhindern. Der
      // Verlust waere aergerlich, ein nicht startendes Programm schlimmer.
      debugPrint('[Outbox] nicht lesbar: $e');
    }
  }

  Future<void> _speichern() async {
    try {
      final file = await _datei();
      await file.writeAsString(jsonEncode({
        'formatVersion': _formatVersion,
        'commands': _wartend.map((c) => c.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('[Outbox] nicht schreibbar: $e');
    }
  }

  /// Neue Auftragskennung. Wird beim Einreihen vergeben und ändert sich bei
  /// Wiederholungen NICHT – daran erkennt der Server den Wiedergänger.
  static String neueKennung() => _uuid.v4();

  /// Auftrag einreihen. Der Aufrufer hat die Änderung lokal bereits angewandt.
  Future<void> einreihen(OutboxCommand befehl) async {
    await laden();
    _wartend.add(befehl);
    await _speichern();
    notifyListeners();
  }

  /// Auftrag als erledigt entfernen – samt zwischengelagerter Datei.
  Future<void> _entfernen(OutboxCommand befehl) async {
    _wartend.removeWhere((c) => c.id == befehl.id);
    await _aufraeumenDatei(befehl);
    await _speichern();
    notifyListeners();
  }

  Future<void> _aufraeumenDatei(OutboxCommand befehl) async {
    final pfad = befehl.stagedFilePath;
    if (pfad == null) return;
    try {
      final datei = File(pfad);
      if (await datei.exists()) await datei.delete();
    } catch (e) {
      debugPrint('[Outbox] Zwischenlager nicht aufraeumbar: $e');
    }
  }

  /// Arbeitet die Schlange von vorn ab.
  ///
  /// [senden] bekommt einen Auftrag und meldet zurück, wie es lief. Die
  /// Netzwerkkenntnis bleibt damit im ApiService, die Reihenfolgen- und
  /// Ablagelogik hier.
  Future<void> abarbeiten(
    Future<OutboxErgebnis> Function(OutboxCommand) senden,
  ) async {
    await laden();
    if (_laeuft || _wartend.isEmpty) return;
    _laeuft = true;
    try {
      while (_wartend.isNotEmpty) {
        final befehl = _wartend.first;
        final ergebnis = await senden(befehl);

        if (ergebnis == OutboxErgebnis.erledigt) {
          await _entfernen(befehl);
          if (_offline) {
            _offline = false;
            notifyListeners();
          }
          continue;
        }

        if (ergebnis == OutboxErgebnis.offline) {
          // Stehenbleiben, nicht überspringen: Die Reihenfolge muss halten.
          befehl.versuche++;
          befehl.letzterVersuch = DateTime.now();
          _offline = true;
          await _speichern();
          notifyListeners();
          return;
        }

        // Endgültig abgelehnt – der Auftrag ist nicht mehr zustellbar. Er wird
        // verworfen, sonst blockierte er die Schlange für immer.
        debugPrint('[Outbox] verworfen: ${befehl.kind} (${befehl.letzterFehler})');
        await _entfernen(befehl);
      }
      _offline = false;
      notifyListeners();
    } finally {
      _laeuft = false;
    }
  }

  /// Räumt Dateien im Zwischenlager weg, zu denen kein Auftrag mehr existiert.
  ///
  /// Nötig, weil ein Absturz zwischen „Datei kopiert" und „Auftrag gespeichert"
  /// sonst Müll zurückließe, den niemand mehr findet.
  Future<void> verwaisteDateienAufraeumen() async {
    await laden();
    try {
      final ordner = await stagingOrdner();
      final bekannt = _wartend
          .map((c) => c.stagedFilePath)
          .whereType<String>()
          .toSet();
      await for (final eintrag in ordner.list()) {
        if (eintrag is File && !bekannt.contains(eintrag.path)) {
          await eintrag.delete();
          debugPrint('[Outbox] verwaiste Datei entfernt: ${eintrag.path}');
        }
      }
    } catch (e) {
      debugPrint('[Outbox] Aufraeumen fehlgeschlagen: $e');
    }
  }

  /// Beim Abmelden: alles wegwerfen. Die Aufträge gehören zum vorherigen Konto.
  Future<void> leeren() async {
    await laden();
    for (final befehl in List<OutboxCommand>.from(_wartend)) {
      await _aufraeumenDatei(befehl);
    }
    _wartend.clear();
    _offline = false;
    await _speichern();
    notifyListeners();
  }
}

/// Wie das Senden eines Auftrags ausgegangen ist.
enum OutboxErgebnis {
  /// Angekommen (oder beim Server bereits bekannt) – Auftrag ist erledigt.
  erledigt,

  /// Kein Netz. Auftrag bleibt stehen, Reihenfolge bleibt gewahrt.
  offline,

  /// Der Server hat abgelehnt und wird es immer tun (fehlende Rechte,
  /// ungültige Daten). Wiederholen wäre sinnlos.
  abgelehnt,
}
