import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';
import 'api_service.dart';

/// Hält die letzten Team-Ereignisse für die In-App-Glocke und verwaltet den
/// Ungelesen-Zähler. Der „gelesen bis"-Zeitpunkt wird lokal persistiert, sodass
/// das Badge einen App-Neustart übersteht.
///
/// Zusätzlich zum Zeitstempel gibt es einzeln als gelesen markierte Ereignisse
/// ([markSphereRead]): Wer eine Sphere direkt öffnet, hat deren Meldungen
/// gesehen – auch ohne die Glockenliste anzutippen.
class NotificationCenter extends ChangeNotifier {
  static final NotificationCenter _instance = NotificationCenter._internal();
  factory NotificationCenter() => _instance;
  NotificationCenter._internal();

  static const _storage = FlutterSecureStorage();
  static const _lastSeenKey = 'notif_last_seen';
  static const _readIdsKey = 'notif_read_ids';
  static const int _maxEvents = 100;

  /// Obergrenze für einzeln gemerkte Gelesen-Markierungen. Greift nur in dem
  /// Ausnahmefall, dass jemand sehr viele Spheres öffnet, ohne je die
  /// Glockenliste zu öffnen (die räumt das Set per [markAllRead] wieder ab).
  static const int _maxReadIds = 300;

  final List<OrbitEvent> _events = [];

  /// Einfügereihenfolge zählt – beim Überlauf fliegen die ältesten Einträge.
  final Set<String> _readIds = <String>{};
  DateTime? _lastSeen;
  bool _loaded = false;

  List<OrbitEvent> get events => List.unmodifiable(_events);

  /// Zeitpunkt des neuesten bekannten Ereignisses – als `since` fürs Polling.
  DateTime? get latestEventTime => _events.isEmpty ? null : _events.first.createdAt;

  int get unreadCount => _events.where(isUnread).length;

  bool isUnread(OrbitEvent e) {
    if (_readIds.contains(e.id)) return false;
    return _lastSeen == null || e.createdAt.isAfter(_lastSeen!);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _storage.read(key: _lastSeenKey);
    if (raw != null) _lastSeen = DateTime.tryParse(raw);
    final rawIds = await _storage.read(key: _readIdsKey);
    if (rawIds != null && rawIds.isNotEmpty) {
      _readIds.addAll(rawIds.split(',').where((s) => s.isNotEmpty));
    }
  }

  Future<void> _persistReadIds() async {
    if (_readIds.length > _maxReadIds) {
      final keep = _readIds.skip(_readIds.length - _maxReadIds).toList();
      _readIds
        ..clear()
        ..addAll(keep);
    }
    await _storage.write(key: _readIdsKey, value: _readIds.join(','));
  }

  /// Fügt neue Ereignisse hinzu (dedupliziert per id) und gibt die tatsächlich
  /// neuen Ereignisse zurück – z.B. um dafür OS-Toasts anzuzeigen.
  Future<List<OrbitEvent>> addEvents(List<OrbitEvent> incoming) async {
    await _ensureLoaded();
    final existingIds = _events.map((e) => e.id).toSet();
    final fresh = incoming.where((e) => !existingIds.contains(e.id)).toList();
    if (fresh.isEmpty) return const [];
    _events.addAll(fresh);
    _events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
    notifyListeners();
    return fresh;
  }

  /// Markiert alle Ereignisse einer Sphere als gelesen – wird beim Öffnen der
  /// Sphere-Detailansicht aufgerufen (Desktop-Panel wie Mobile-Seite).
  ///
  /// Ohne das bliebe das rote Badge stehen, obwohl der Nutzer die betroffene
  /// Sphere gerade angesehen hat, nur weil er nicht über die Glockenliste
  /// hineinnavigiert ist.
  Future<void> markSphereRead(String sphereId) async {
    await _ensureLoaded();
    final ids = _events
        .where((e) => e.sphereId == sphereId && isUnread(e))
        .map((e) => e.id)
        .toList();
    if (ids.isEmpty) return;
    _readIds.addAll(ids);
    await _persistReadIds();
    notifyListeners();
  }

  /// Markiert alles als gelesen (Badge zurücksetzen).
  Future<void> markAllRead() async {
    await _ensureLoaded();
    _lastSeen = DateTime.now();
    await _storage.write(key: _lastSeenKey, value: _lastSeen!.toIso8601String());
    // Der Zeitstempel deckt ab jetzt alles Ältere ab – die Einzelmarkierungen
    // werden damit überflüssig.
    _readIds.clear();
    await _persistReadIds();
    notifyListeners();
  }

  /// Blendet eine Meldung dauerhaft aus – nur für den eigenen Account.
  ///
  /// Der Server merkt sich das kontobezogen, nicht geräteweise: Wer am Desktop
  /// aufräumt, ist die Meldung auch am Handy los. Die Ereigniszeile selbst
  /// bleibt bestehen, andere Mitglieder des Orbits sehen sie unverändert.
  ///
  /// Die Anzeige wird sofort aktualisiert; scheitert der Server, kommt der
  /// Eintrag beim nächsten Abgleich zurück.
  Future<void> dismiss(OrbitEvent event) async {
    final index = _events.indexWhere((e) => e.id == event.id);
    if (index == -1) return;
    _events.removeAt(index);
    notifyListeners();
    try {
      await ApiService.dismissEvent(event.id);
    } catch (_) {
      _events.insert(index, event);
      notifyListeners();
      rethrow;
    }
  }

  /// Blendet alle derzeit angezeigten Meldungen aus.
  Future<void> dismissAll() async {
    if (_events.isEmpty) return;
    final backup = List<OrbitEvent>.from(_events);
    _events.clear();
    notifyListeners();
    try {
      await ApiService.dismissAllEvents();
    } catch (_) {
      _events.addAll(backup);
      notifyListeners();
      rethrow;
    }
  }

  /// Beim Logout: Liste leeren (gelesen-Marke bleibt erhalten).
  void clear() {
    _events.clear();
    notifyListeners();
  }
}
