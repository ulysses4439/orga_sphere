import '../models/models.dart';
import 'api_service.dart';

class TaskService {
  static final TaskService _instance = TaskService._internal();

  final List<TaskDomain> _domains = [];
  final List<TaskTemplate> _templates = [];
  final List<TaskInstance> _instances = [];

  late final Future<void> _ready;

  TaskService._internal() {
    _ready = _loadAll();
  }

  factory TaskService() => _instance;

  Future<void> get ready => _ready;

  Future<void> _loadAll() async {
    final domains = await ApiService.getDomains();
    final templates = await ApiService.getTemplates();
    final active = await ApiService.getActiveInstances();
    final archived = await ApiService.getArchivedInstances();

    _domains
      ..clear()
      ..addAll(domains);
    _templates
      ..clear()
      ..addAll(templates);
    _instances
      ..clear()
      ..addAll(active)
      ..addAll(archived);

    // Load log entries for all instances in parallel
    await Future.wait(_instances.map((inst) async {
      try {
        final logs = await ApiService.getLogs(inst.id);
        inst.logEntries.addAll(logs);
      } catch (_) {}
    }));
  }

  Future<void> refresh() async {
    _domains.clear();
    _templates.clear();
    _instances.clear();
    await _loadAll();
  }

  // --- Read (synchronous after initialization) ---

  List<TaskDomain> getDomains() => List.unmodifiable(_domains);
  List<TaskTemplate> getTemplates() => List.unmodifiable(_templates);
  List<TaskInstance> getInstances() => List.unmodifiable(_instances);

  TaskDomain? getDomainById(String id) {
    try {
      return _domains.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  TaskTemplate? getTemplateById(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  TaskInstance? getInstanceById(String id) {
    try {
      return _instances.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  List<TaskInstance> getActiveInstances() =>
      _instances.where((i) => i.status != TaskStatus.done).toList();

  List<TaskInstance> getArchivedInstances() =>
      _instances.where((i) => i.status == TaskStatus.done).toList();

  // --- Write (async, calls API then updates local cache) ---

  Future<void> markAsDone(String instanceId) async {
    await ApiService.markAsDone(instanceId);

    final instance = getInstanceById(instanceId);
    if (instance != null) {
      instance.markAsDone();
      // The backend creates the next recurring instance automatically.
      // It will appear in the list after the next refresh / app restart.
    }
  }

  Future<void> addLogEntry(String instanceId, String user, String text) async {
    final entry = await ApiService.addLogEntry(instanceId, user, text);
    getInstanceById(instanceId)?.addLogEntry(entry);
  }
}
