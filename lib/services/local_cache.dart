import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Der zuletzt vom Server geholte Datenstand, wie er auf dem Geraet liegt.
class CachedSnapshot {
  final List<TaskDomain> domains;
  final List<Task> tasks;

  /// Wann dieser Stand vom Server geholt wurde. Die Oberflaeche zeigt daraus
  /// „Stand: vor X Minuten", solange noch keine frischen Daten da sind.
  final DateTime savedAt;

  const CachedSnapshot({
    required this.domains,
    required this.tasks,
    required this.savedAt,
  });
}

/// Spiegelt den Datenbestand als JSON-Datei auf dem Geraet.
///
/// Zweck ist ausschliesslich die Startgeschwindigkeit: Die App zeigt beim
/// Start sofort den zuletzt bekannten Stand und aktualisiert ihn im
/// Hintergrund. Ohne Netz bleibt der gespeicherte Stand sichtbar, statt dass
/// ein leerer Bildschirm erscheint.
///
/// Bewusst eine schlichte Datei und keine lokale Datenbank: Es geht um wenige
/// hundert Kilobyte, die immer komplett gelesen und komplett geschrieben
/// werden. Eine SQLite-Ebene braechte hier nur Schema-Migrationen mit sich.
///
/// Der Zwischenspeicher ist NICHT die Wahrheit – geaendert wird weiterhin
/// ausschliesslich ueber den Server. Bearbeiten ohne Netz ist bewusst noch
/// nicht moeglich; das waere der naechste Ausbauschritt.
class LocalCache {
  static const _fileName = 'orga_sphere_cache.json';

  /// Format der Datei. Bei einer Aenderung an den gespeicherten Feldern hier
  /// hochzaehlen: Ein alter Stand wird dann verworfen statt halb gelesen.
  ///
  /// 2: Verlaufseintraege haben createdBy und editedAt bekommen. Ein Stand aus
  ///    Version 1 kennt beide nicht - die Eintraege saehen dann aus, als
  ///    gehoerten sie niemandem, und ihr Verfasser bekaeme kein Menue zum
  ///    Bearbeiten. Genau das war zu sehen: alte Eintraege ohne Drei-Punkte-
  ///    Menue, waehrend derselbe Eintrag auf dem anderen Geraet eines hatte.
  static const _formatVersion = 2;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Liest den gespeicherten Stand.
  ///
  /// [userId] ist der gerade angemeldete Nutzer: Gehoert die Datei zu einem
  /// anderen Konto, wird sie ignoriert. Sonst saehe man nach einem Kontowechsel
  /// fuer einen Moment die Spheres des Vorgaengers.
  ///
  /// Gibt `null` zurueck, wenn nichts Brauchbares da ist – der Aufrufer zeigt
  /// dann wie bisher einen Ladezustand.
  static Future<CachedSnapshot?> load(String? userId) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;

      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['formatVersion'] != _formatVersion) return null;
      if (json['userId'] != userId) return null;

      return CachedSnapshot(
        domains: (json['domains'] as List<dynamic>)
            .map((j) => TaskDomain.fromJson(j as Map<String, dynamic>))
            .toList(),
        tasks: (json['tasks'] as List<dynamic>)
            .map((j) => Task.fromJson(j as Map<String, dynamic>))
            .toList(),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
    } catch (e) {
      // Beschaedigte oder unlesbare Datei ist kein Grund, den Start zu
      // verweigern – der naechste erfolgreiche Abgleich schreibt sie neu.
      debugPrint('Zwischenspeicher nicht lesbar: $e');
      return null;
    }
  }

  /// Laufende Schreibvorgaenge, damit sie sich nicht ueberholen.
  ///
  /// Die Aufrufer warten das Schreiben bewusst nicht ab (eine Aenderung soll
  /// nicht auf die Festplatte warten). Zwei schnell aufeinanderfolgende
  /// Aenderungen wuerden sonst gleichzeitig dieselbe Nebendatei beschreiben und
  /// koennten sie zerlegen. Hier haengt jeder Schreibvorgang hinten an.
  static Future<void> _writes = Future.value();

  /// Schreibt den uebergebenen Stand – siehe [_save] fuer das Wie.
  static Future<void> save({
    required String? userId,
    required List<TaskDomain> domains,
    required List<Task> tasks,
  }) {
    _writes = _writes.then(
        (_) => _save(userId: userId, domains: domains, tasks: tasks));
    return _writes;
  }

  /// Erst in eine Nebendatei, dann umbenennen: Wird die App mitten im
  /// Schreiben beendet, liegt entweder der alte oder der neue Stand da – nie
  /// eine halbe Datei.
  static Future<void> _save({
    required String? userId,
    required List<TaskDomain> domains,
    required List<Task> tasks,
  }) async {
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'formatVersion': _formatVersion,
        'userId': userId,
        'savedAt': DateTime.now().toIso8601String(),
        'domains': domains.map((d) => d.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
      }));
      await tmp.rename(file.path);
    } catch (e) {
      // Ein nicht geschriebener Zwischenspeicher kostet beim naechsten Start
      // Ladezeit, mehr nicht. Kein Grund, den laufenden Abgleich zu stoeren.
      debugPrint('Zwischenspeicher nicht schreibbar: $e');
    }
  }

  /// Loescht den Stand – beim Abmelden, damit auf einem geteilten Geraet keine
  /// Spheres des Vorgaengers zurueckbleiben.
  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Zwischenspeicher nicht loeschbar: $e');
    }
  }
}
