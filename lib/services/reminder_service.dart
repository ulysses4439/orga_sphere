import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import '../models/models.dart';
import 'task_service.dart';

/// Fired when a reminder becomes due while the app is running.
class ReminderEvent {
  final Task task;
  ReminderEvent(this.task);
}

/// Checks reminders and exposes a stream of due events.
/// Uses both a JS setInterval (reliable in Flutter web idle state) and a
/// Dart Timer as fallback. Reminders already past at startup appear only
/// in the sidebar (missed); reminders that become due afterwards show a dialog.
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final TaskService _taskService = TaskService();
  final _controller = StreamController<ReminderEvent>.broadcast();
  final _notifiedIds = <String>{};
  Timer? _timer;
  DateTime? _startedAt;
  bool _stopped = false;

  Stream<ReminderEvent> get onReminderDue => _controller.stream;

  void start() {
    if (_timer != null) return;
    _stopped = false;
    _startedAt = DateTime.now();

    // Register with JS so setInterval in index.html can call us directly.
    // This fires even when Flutter's Dart event loop is throttled at idle.
    globalContext['_orgaCheck'] = (() => _check()).toJS;

    // Dart timer as additional fallback.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());

    // Initial check after brief delay so caller can attach stream listener.
    Future.delayed(const Duration(milliseconds: 200), _check);
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    globalContext['_orgaCheck'] = null.jsify();
  }

  /// Call when the tab/app regains focus.
  void checkNow() => _check();

  void _check() {
    if (_stopped) return;
    final now = DateTime.now();
    for (final task in _taskService.getTasks()) {
      final reminder = task.reminderAt;
      if (reminder == null) continue;
      if (reminder.isAfter(now)) continue;
      if (_notifiedIds.contains(task.id)) continue;
      _notifiedIds.add(task.id);
      // Dialog only for reminders that became due AFTER the app started.
      // Older reminders (app was closed) appear silently in the sidebar.
      final isLive = _startedAt != null && reminder.isAfter(_startedAt!);
      if (isLive) {
        _controller.add(ReminderEvent(task));
      }
    }
  }

  /// All reminders whose time has already passed (for sidebar display).
  List<Task> getMissedReminders() {
    final now = DateTime.now();
    return _taskService
        .getTasks()
        .where((t) => t.reminderAt != null && t.reminderAt!.isBefore(now))
        .toList()
      ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
  }

  /// Prevents re-dialog for this task in the current session.
  void markShown(String taskId) => _notifiedIds.add(taskId);
}
