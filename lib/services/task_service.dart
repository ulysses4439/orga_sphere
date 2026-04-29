import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// Service for managing task templates and instances
/// Handles business logic like creating instances and auto-generation
class TaskService {
  static final TaskService _instance = TaskService._internal();

  /// Templates that define recurring tasks
  final List<TaskTemplate> _templates = [];

  /// Instances (year-specific task capsules)
  final List<TaskInstance> _instances = [];

  TaskService._internal() {
    _initializeMockData();
  }

  factory TaskService() {
    return _instance;
  }

  /// Initialize with mock data
  void _initializeMockData() {
    // Clear any existing data
    _templates.clear();
    _instances.clear();

    // Create sample templates
    final template1 = TaskTemplate(
      id: 'template-1',
      title: 'Finalisiere Theatervertrag',
      description:
          'Überprüfe und aktualisiere den jährlichen Theatervertrag mit der lokalen Bühne.',
      startMonth: 1,
      dueDay: 31,
      dueMonth: 3,
      createdAt: DateTime(2024, 1, 15),
    );

    final template2 = TaskTemplate(
      id: 'template-2',
      title: 'Jahresabrechnung erstellen',
      description:
          'Erstelle die finanzielle Jahresabrechnung und bereite den Bericht vor.',
      startMonth: 1,
      dueDay: 28,
      dueMonth: 2,
      createdAt: DateTime(2024, 1, 20),
    );

    final template3 = TaskTemplate(
      id: 'template-3',
      title: 'Mitgliederverwaltung aktualisieren',
      description:
          'Aktualisiere die Kontaktdaten aller aktiven Mitglieder und überprüfe Zugehörigkeiten.',
      startMonth: 3,
      dueDay: 15,
      dueMonth: 4,
      createdAt: DateTime(2024, 1, 10),
    );

    final template4 = TaskTemplate(
      id: 'template-4',
      title: 'Halbjahrestreffen planen',
      description:
          'Organisiere das halbjährliche Team-Treffen und versende Einladungen.',
      startMonth: 6,
      dueDay: 30,
      dueMonth: 6,
      createdAt: DateTime(2024, 1, 25),
    );

    _templates.addAll([template1, template2, template3, template4]);

    // Create instances for 2026
    _createInstancesForTemplate(template1, 2026);
    _createInstancesForTemplate(template2, 2026);
    _createInstancesForTemplate(template3, 2026);
    _createInstancesForTemplate(template4, 2026);

    // Create instances for 2027
    _createInstancesForTemplate(template1, 2027);
    _createInstancesForTemplate(template2, 2027);

    // Add some sample log entries to demonstrate the timeline
    final instance1 = _instances.firstWhere(
      (i) => i.templateId == 'template-1' && i.year == 2026,
    );

    instance1.addLogEntry(TaskLogEntry(
      id: 'log-1',
      user: 'Steven',
      timestamp: DateTime(2026, 1, 15, 10, 30),
      text: 'E-Mail an das Theater gesendet mit Anfrage zum neuen Vertrag',
    ));

    instance1.addLogEntry(TaskLogEntry(
      id: 'log-2',
      user: 'Berni',
      timestamp: DateTime(2026, 1, 20, 14, 0),
      text: 'Antwort vom Theater erhalten. Überprüfe die neuen Klauseln.',
    ));

    instance1.addLogEntry(TaskLogEntry(
      id: 'log-3',
      user: 'Steven',
      timestamp: DateTime(2026, 2, 5, 9, 15),
      text: 'Vertrag mit Anmerkungen weitergeleitet',
    ));

    // Add log entry to another task
    final instance2 = _instances.firstWhere(
      (i) => i.templateId == 'template-2' && i.year == 2026,
    );

    instance2.status = TaskStatus.inProgress;
    instance2.addLogEntry(TaskLogEntry(
      id: 'log-4',
      user: 'Maria',
      timestamp: DateTime(2026, 1, 25, 11, 0),
      text: 'Zahlen vom Buchhaltungssystem exportiert',
    ));
  }

  /// Create an instance from a template for a specific year
  void _createInstancesForTemplate(TaskTemplate template, int year) {
    final instance = TaskInstance(
      id: 'instance-${template.id}-$year',
      templateId: template.id,
      year: year,
      title: template.title,
      description: template.description,
      startMonth: template.startMonth,
      dueDay: template.dueDay,
      dueMonth: template.dueMonth,
      createdAt: DateTime.now(),
    );
    _instances.add(instance);
  }

  /// Get all templates
  List<TaskTemplate> getTemplates() => List.unmodifiable(_templates);

  /// Get all instances
  List<TaskInstance> getInstances() => List.unmodifiable(_instances);

  /// Get instances for a specific year
  List<TaskInstance> getInstancesByYear(int year) {
    return _instances.where((i) => i.year == year).toList();
  }

  /// Get instances sorted by due date (with overdue/upcoming first)
  List<TaskInstance> getInstancesSorted() {
    final sorted = List<TaskInstance>.from(_instances);
    sorted.sort((a, b) {
      // Completed tasks go to the bottom
      if (a.status == TaskStatus.done && b.status != TaskStatus.done) return 1;
      if (a.status != TaskStatus.done && b.status == TaskStatus.done) return -1;

      // Overdue tasks first
      if (a.isOverdue && !b.isOverdue) return -1;
      if (!a.isOverdue && b.isOverdue) return 1;

      // Then upcoming tasks
      if (a.isUpcoming && !b.isUpcoming) return -1;
      if (!a.isUpcoming && b.isUpcoming) return 1;

      // Then sort by due date
      return a.getDueDate().compareTo(b.getDueDate());
    });
    return sorted;
  }

  /// Get a specific instance by ID
  TaskInstance? getInstanceById(String id) {
    try {
      return _instances.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Update an instance
  void updateInstance(TaskInstance instance) {
    final index = _instances.indexWhere((i) => i.id == instance.id);
    if (index >= 0) {
      _instances[index] = instance;
    }
  }

  /// Mark an instance as done and auto-create next year's instance
  void markAsDone(String instanceId) {
    final instance = getInstanceById(instanceId);
    if (instance != null && instance.status != TaskStatus.done) {
      instance.markAsDone();

      // Auto-create next year's instance
      final template = _templates.firstWhere(
        (t) => t.id == instance.templateId,
      );
      _createInstancesForTemplate(template, instance.year + 1);

      updateInstance(instance);
    }
  }

  /// Add a log entry to an instance
  void addLogEntry(String instanceId, String user, String text) {
    final instance = getInstanceById(instanceId);
    if (instance != null) {
      instance.addLogEntry(TaskLogEntry(
        id: const Uuid().v4(),
        user: user,
        timestamp: DateTime.now(),
        text: text,
      ));
      updateInstance(instance);
    }
  }

  /// Reset all data (useful for testing)
  void reset() {
    _templates.clear();
    _instances.clear();
    _initializeMockData();
  }
}
