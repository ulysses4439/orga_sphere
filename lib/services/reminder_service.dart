import 'dart:async';
import '../models/models.dart';
import 'task_service.dart';

class ReminderEvent {
  final Task task;
  ReminderEvent(this.task);
}

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
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    Future.delayed(const Duration(milliseconds: 200), _check);
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

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
      final isLive = _startedAt != null && reminder.isAfter(_startedAt!);
      if (isLive) _controller.add(ReminderEvent(task));
    }
  }

  List<Task> getMissedReminders() {
    final now = DateTime.now();
    return _taskService
        .getTasks()
        .where((t) => t.reminderAt != null && t.reminderAt!.isBefore(now))
        .toList()
      ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
  }

  void markShown(String taskId) => _notifiedIds.add(taskId);
}
