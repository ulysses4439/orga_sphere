import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'api_service.dart';

class TaskService extends ChangeNotifier {
  static TaskService? _instance;

  final List<TaskDomain> _domains = [];
  final List<Task> _tasks = [];

  late final Future<void> _ready;
  bool _isRefreshing = false;

  TaskService._internal() {
    _ready = _loadAll();
  }

  factory TaskService() {
    _instance ??= TaskService._internal();
    return _instance!;
  }

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  Future<void> get ready => _ready;

  Future<void> _loadAll() async {
    final domains = await ApiService.getDomains();
    final active = await ApiService.getActiveTasks();
    final archived = await ApiService.getArchivedTasks();

    _domains
      ..clear()
      ..addAll(domains);
    _tasks
      ..clear()
      ..addAll(active)
      ..addAll(archived);

    await Future.wait(_tasks.map((task) async {
      try {
        final logs = await ApiService.getLogs(task.id);
        task.logEntries.addAll(logs);
      } catch (_) {}
    }));
  }

  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await _loadAll();
      notifyListeners();
    } finally {
      _isRefreshing = false;
    }
  }

  List<TaskDomain> getDomains() => List.unmodifiable(_domains);
  List<Task> getTasks() => List.unmodifiable(_tasks);

  TaskDomain? getDomainById(String id) {
    try {
      return _domains.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  Task? getTaskById(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Task> getActiveTasks() =>
      (_tasks.where((t) => t.status != TaskStatus.done).toList()
        ..sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        }));

  List<Task> getArchivedTasks() =>
      (_tasks.where((t) => t.status == TaskStatus.done).toList()
        ..sort((a, b) {
          final bDate = b.completedAt ?? b.dueDate;
          final aDate = a.completedAt ?? a.dueDate;
          if (bDate == null && aDate == null) return 0;
          if (bDate == null) return 1;
          if (aDate == null) return -1;
          return bDate.compareTo(aDate);
        }));

  Future<Task> createTask({
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    DateTime? dueDate,
    required RecurrencePattern recurrence,
  }) async {
    final task = await ApiService.createTask(
      domainId: domainId,
      title: title,
      description: description,
      startDate: startDate,
      dueDate: dueDate,
      recurrenceFrequency: recurrence.frequency.name,
      recurrenceInterval: recurrence.interval,
    );
    _tasks.add(task);
    return task;
  }

  Future<void> markAsDone(String taskId) async {
    final nextTask = await ApiService.markAsDone(taskId);
    final task = getTaskById(taskId);
    if (task != null) task.markAsDone();
    if (nextTask != null) _tasks.add(nextTask);
    notifyListeners();
  }

  Future<void> reopenTask(String taskId) async {
    await ApiService.reopenTask(taskId);
    final task = getTaskById(taskId);
    if (task != null) {
      task.status = TaskStatus.open;
      task.completedAt = null;
    }
  }

  Future<void> deleteTask(String taskId) async {
    await ApiService.deleteTask(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
  }

  Future<void> startTask(String taskId) async {
    await ApiService.startTask(taskId);
    final task = getTaskById(taskId);
    if (task != null) task.status = TaskStatus.inProgress;
    notifyListeners();
  }

  Future<void> addLogEntry(String taskId, String text) async {
    final result = await ApiService.addLogEntry(taskId, text);
    final task = getTaskById(taskId);
    task?.addLogEntry(result.entry);
    if (result.newTaskStatus != null) {
      final newStatus = TaskStatus.values.firstWhere(
        (s) => s.name == result.newTaskStatus,
        orElse: () => task?.status ?? TaskStatus.open,
      );
      task?.status = newStatus;
    }
  }

  Future<void> updateTaskTitle(String taskId, String title) async {
    await ApiService.updateTaskTitle(taskId, title);
    final task = getTaskById(taskId);
    if (task != null) task.title = title;
  }

  Future<void> updateTaskDescription(String taskId, String description) async {
    await ApiService.updateTaskDescription(taskId, description);
    final task = getTaskById(taskId);
    if (task != null) task.description = description;
  }

  Future<void> updateTaskSchedule(
      String taskId, {
      DateTime? startDate,
      DateTime? dueDate,
      bool clearDueDate = false,
      String? recurrenceFrequency,
      int? recurrenceInterval,
  }) async {
    await ApiService.updateTaskSchedule(
      taskId,
      startDate: startDate,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceInterval: recurrenceInterval,
    );
    final task = getTaskById(taskId);
    if (task == null) return;
    if (startDate != null) task.startDate = startDate;
    if (clearDueDate) {
      task.dueDate = null;
    } else if (dueDate != null) {
      task.dueDate = dueDate;
    }
    if (recurrenceFrequency != null || recurrenceInterval != null) {
      final freq = RecurrenceFrequency.values.firstWhere(
        (f) => f.name == (recurrenceFrequency ?? task.recurrence.frequency.name),
        orElse: () => task.recurrence.frequency,
      );
      task.recurrence = RecurrencePattern(
        frequency: freq,
        interval: recurrenceInterval ?? task.recurrence.interval,
      );
    }
  }

  /// Weist die Sphere einem OrbitMember zu (oder hebt die Zuweisung mit
  /// [memberId] == null auf). [displayName]/[email] dienen der sofortigen
  /// Anzeige; beim nächsten Refresh kommen sie ohnehin vom Backend-JOIN.
  Future<void> assignTask(
    String taskId,
    String? memberId, {
    String? displayName,
    String? email,
  }) async {
    await ApiService.assignTask(taskId, memberId);
    final task = getTaskById(taskId);
    if (task != null) {
      task.assignedToMemberId = memberId;
      task.assignedToName = memberId != null ? displayName : null;
      task.assignedToEmail = memberId != null ? email : null;
    }
    notifyListeners();
  }

  Future<void> setReminder(String taskId, DateTime? reminderAt) async {
    await ApiService.setReminder(taskId, reminderAt);
    final task = getTaskById(taskId);
    if (task != null) task.reminderAt = reminderAt;
  }

  Future<TaskDomain> createDomain(
      String name, String description, String color) async {
    final domain = await ApiService.createDomain(name, description, color);
    _domains.add(domain);
    return domain;
  }

  Future<void> renameDomain(String domainId, String name) async {
    await ApiService.renameDomain(domainId, name);
    final idx = _domains.indexWhere((d) => d.id == domainId);
    if (idx != -1) {
      final d = _domains[idx];
      _domains[idx] = TaskDomain(
        id: d.id,
        name: name,
        description: d.description,
        colorHex: d.colorHex,
      );
    }
  }

  Future<void> deleteDomain(String domainId) async {
    await ApiService.deleteDomain(domainId);
    _domains.removeWhere((d) => d.id == domainId);
    _tasks.removeWhere((t) => t.domainId == domainId);
  }

  Future<void> moveTask(String taskId, String domainId) async {
    await ApiService.moveTask(taskId, domainId);
    final task = getTaskById(taskId);
    if (task != null) task.domainId = domainId;
  }
}
