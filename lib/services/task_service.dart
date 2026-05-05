import '../models/models.dart';
import 'api_service.dart';

class TaskService {
  static final TaskService _instance = TaskService._internal();

  final List<TaskDomain> _domains = [];
  final List<Task> _tasks = [];

  late final Future<void> _ready;

  TaskService._internal() {
    _ready = _loadAll();
  }

  factory TaskService() => _instance;

  Future<void> get ready => _ready;

  Future<void> _loadAll() async {
    final domains = await ApiService.getDomains();
    final active   = await ApiService.getActiveTasks();
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
    _domains.clear();
    _tasks.clear();
    await _loadAll();
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
      _tasks.where((t) => t.status != TaskStatus.done).toList();

  List<Task> getArchivedTasks() =>
      _tasks.where((t) => t.status == TaskStatus.done).toList();

  Future<Task> createTask({
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    required DateTime dueDate,
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
    if (task != null) {
      task.markAsDone();
    }
    if (nextTask != null) {
      _tasks.add(nextTask);
    }
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

  Future<void> addLogEntry(String taskId, String user, String text) async {
    final entry = await ApiService.addLogEntry(taskId, user, text);
    getTaskById(taskId)?.addLogEntry(entry);
  }

  Future<TaskDomain> createDomain(String name, String description) async {
    final domain = await ApiService.createDomain(name, description);
    _domains.add(domain);
    return domain;
  }
}
