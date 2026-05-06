import 'dart:async';
import '../models/models.dart';
import 'task_service.dart';

/// Fired when a reminder becomes due while the app is running.
class ReminderEvent {
  final Task task;
  ReminderEvent(this.task);
}

/// Checks reminders every 30 seconds and exposes a stream of due events.
/// Reminders that were already past when start() was called appear only in
/// the sidebar (missed); reminders that become due afterwards trigger a dialog.
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final TaskService _taskService = TaskService();
  final _controller = StreamController<ReminderEvent>.broadcast();
  final _notifiedIds = <String>{};
  Timer? _timer;
  DateTime? _startedAt;

  Stream<ReminderEvent> get onReminderDue => _controller.stream;

  void start() {
    if (_timer != null) return;
    _startedAt = DateTime.now();
    // Delay the first check by 100ms so the caller can attach a listener first.
    Future.delayed(const Duration(milliseconds: 100), _check);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Call when the tab/app regains focus.
  void checkNow() => _check();

  void _check() {
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
