import 'api_service.dart';
import 'notification_center.dart';
import 'push_service.dart';

/// Holt Team-Ereignisse vom Backend und füttert das [NotificationCenter].
/// Auf Plattformen ohne FCM (Windows/Desktop) werden dabei OS-Toasts ausgelöst;
/// auf Android übernimmt FCM die Toasts (hier nur stilles Aktualisieren der Liste).
///
/// Wird in den bestehenden 30s-Poll-Zyklus des TaskListScreen eingehängt –
/// es gibt bewusst keinen eigenen Timer.
class EventPollService {
  static final EventPollService _instance = EventPollService._internal();
  factory EventPollService() => _instance;
  EventPollService._internal();

  final NotificationCenter _center = NotificationCenter();
  final PushService _push = PushService();
  bool _primed = false;
  bool _busy = false;

  /// Setzt den Zustand beim Logout zurück, damit nach erneutem Login die
  /// vorhandenen Ereignisse nicht fälschlich als „neu" getoastet werden.
  void reset() => _primed = false;

  Future<void> poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final events =
          await ApiService.getEvents(since: _center.latestEventTime);
      final fresh = await _center.addEvents(events);

      // Erster Lauf (App-Start): nur Liste befüllen, keine Toast-Flut für
      // historische Ereignisse.
      if (_primed && _push.usesPollingToasts) {
        for (final e in fresh) {
          await _push.showLocal(e.body, payload: e.sphereId);
        }
      }
      _primed = true;
    } catch (_) {
      // Netzwerkfehler ignorieren – nächster Poll versucht es erneut.
    } finally {
      _busy = false;
    }
  }
}
