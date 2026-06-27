import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';

/// Hält die letzten Team-Ereignisse für die In-App-Glocke und verwaltet den
/// Ungelesen-Zähler. Der „gelesen bis"-Zeitpunkt wird lokal persistiert, sodass
/// das Badge einen App-Neustart übersteht.
class NotificationCenter extends ChangeNotifier {
  static final NotificationCenter _instance = NotificationCenter._internal();
  factory NotificationCenter() => _instance;
  NotificationCenter._internal();

  static const _storage = FlutterSecureStorage();
  static const _lastSeenKey = 'notif_last_seen';
  static const int _maxEvents = 100;

  final List<OrbitEvent> _events = [];
  DateTime? _lastSeen;
  bool _loaded = false;

  List<OrbitEvent> get events => List.unmodifiable(_events);

  /// Zeitpunkt des neuesten bekannten Ereignisses – als `since` fürs Polling.
  DateTime? get latestEventTime => _events.isEmpty ? null : _events.first.createdAt;

  int get unreadCount {
    final seen = _lastSeen;
    if (seen == null) return _events.length;
    return _events.where((e) => e.createdAt.isAfter(seen)).length;
  }

  bool isUnread(OrbitEvent e) =>
      _lastSeen == null || e.createdAt.isAfter(_lastSeen!);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _storage.read(key: _lastSeenKey);
    if (raw != null) _lastSeen = DateTime.tryParse(raw);
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

  /// Markiert alles als gelesen (Badge zurücksetzen).
  Future<void> markAllRead() async {
    _lastSeen = DateTime.now();
    await _storage.write(key: _lastSeenKey, value: _lastSeen!.toIso8601String());
    notifyListeners();
  }

  /// Beim Logout: Liste leeren (gelesen-Marke bleibt erhalten).
  void clear() {
    _events.clear();
    notifyListeners();
  }
}
