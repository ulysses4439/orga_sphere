import 'dart:async';
import '../models/models.dart';
import 'task_service.dart';

/// Fired when a reminder becomes due while the app is running.
class ReminderEvent {
  final Task task;
  ReminderEvent(this.task);
}

/// Checks reminders every minute and exposes a stream of due events.
/// Also detects reminders that fired while the app was closed (missed).
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final TaskService _taskService = TaskService();
  final _controller = StreamController<ReminderEvent>.broadcast();
  final _notifiedIds = <String>{};
  Timer? _timer;

  Stream<ReminderEvent> get onReminderDue => _controller.stream;

  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final now = DateTime.now();
    for (final task in _taskService.getTasks()) {
      final reminder = task.reminderAt;
      if (reminder == null) continue;
      if (reminder.isAfter(now)) continue;
      if (_notifiedIds.contains(task.id)) continue;
      _notifiedIds.add(task.id);
      _controller.add(ReminderEvent(task));
    }
  }

  /// Tasks whose reminder time has passed but were never shown in this session.
  List<Task> getMissedReminders() {
    final now = DateTime.now();
    return _taskService
        .getTasks()
        .where((t) =>
            t.reminderAt != null &&
            t.reminderAt!.isBefore(now) &&
            !_notifiedIds.contains(t.id))
        .toList()
      ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
  }

  /// Call after showing a reminder so it is not re-shown in this session.
  void markShown(String taskId) => _notifiedIds.add(taskId);
}
