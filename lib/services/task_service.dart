import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// Service for managing task domains, templates and instances.
/// Supports flexible recurrence, one-time tasks, and an archive of completed work.
class TaskService {
  static final TaskService _instance = TaskService._internal();

  /// Domains that group tasks.
  final List<TaskDomain> _domains = [];

  /// Templates that define tasks.
  final List<TaskTemplate> _templates = [];

  /// Task instances, including completed archive items.
  final List<TaskInstance> _instances = [];

  TaskService._internal() {
    _initializeMockData();
  }

  factory TaskService() {
    return _instance;
  }

  /// Initialize with mock data
  void _initializeMockData() {
    _domains.clear();
    _templates.clear();
    _instances.clear();

    final domainClub = TaskDomain(
      id: 'domain-club',
      name: 'Verein',
      description: 'Aufgaben rund um den Vereinsbetrieb',
    );

    final domainWork = TaskDomain(
      id: 'domain-work',
      name: 'Arbeit',
      description: 'Team- und Projektaufgaben aus dem Job',
    );

    final domainPrivate = TaskDomain(
      id: 'domain-private',
      name: 'Privat',
      description: 'Persönliche Aufgaben und Dokumentationsaufgaben',
    );

    _domains.addAll([domainClub, domainWork, domainPrivate]);

    final template1 = TaskTemplate(
      id: 'template-1',
      domainId: domainClub.id,
      title: 'Finalisiere Theatervertrag',
      description:
          'Überprüfe und aktualisiere den jährlichen Theatervertrag mit der lokalen Bühne.',
      startDate: DateTime(2026, 1, 1),
      dueDate: DateTime(2026, 3, 31),
      recurrence: const RecurrencePattern(
        frequency: RecurrenceFrequency.yearly,
      ),
      createdAt: DateTime(2024, 1, 15),
    );

    final template2 = TaskTemplate(
      id: 'template-2',
      domainId: domainClub.id,
      title: 'Jahresabrechnung erstellen',
      description:
          'Erstelle die finanzielle Jahresabrechnung und bereite den Bericht vor.',
      startDate: DateTime(2026, 1, 1),
      dueDate: DateTime(2026, 2, 28),
      recurrence: const RecurrencePattern(
        frequency: RecurrenceFrequency.yearly,
      ),
      createdAt: DateTime(2024, 1, 20),
    );

    final template3 = TaskTemplate(
      id: 'template-3',
      domainId: domainClub.id,
      title: 'Mitgliederverwaltung aktualisieren',
      description:
          'Aktualisiere die Kontaktdaten aller aktiven Mitglieder und überprüfe Zugehörigkeiten.',
      startDate: DateTime(2026, 3, 1),
      dueDate: DateTime(2026, 4, 15),
      recurrence: const RecurrencePattern(
        frequency: RecurrenceFrequency.monthly,
        interval: 6,
      ),
      createdAt: DateTime(2024, 1, 10),
    );

    final template4 = TaskTemplate(
      id: 'template-4',
      domainId: domainWork.id,
      title: 'Halbjahrestreffen planen',
      description:
          'Organisiere das halbjährliche Team-Treffen und versende Einladungen.',
      startDate: DateTime(2026, 6, 1),
      dueDate: DateTime(2026, 6, 30),
      recurrence: const RecurrencePattern(
        frequency: RecurrenceFrequency.monthly,
        interval: 6,
      ),
      createdAt: DateTime(2024, 1, 25),
    );

    final template5 = TaskTemplate(
      id: 'template-5',
      domainId: domainPrivate.id,
      title: 'Einmalige Hausübung erledigen',
      description: 'Bereite die Präsentation für den privaten Workshop vor.',
      startDate: DateTime(2026, 5, 1),
      dueDate: DateTime(2026, 5, 15),
      recurrence: const RecurrencePattern(
        frequency: RecurrenceFrequency.none,
      ),
      createdAt: DateTime(2026, 4, 20),
    );

    _templates.addAll([template1, template2, template3, template4, template5]);

    _createInstanceForTemplate(template1);
    _createInstanceForTemplate(template2);
    _createInstanceForTemplate(template3);
    _createInstanceForTemplate(template4);
    _createInstanceForTemplate(template5);

    final instance1 = _instances.firstWhere(
      (i) => i.templateId == 'template-1' && i.dueDate.year == 2026,
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

    final instance2 = _instances.firstWhere(
      (i) => i.templateId == 'template-2' && i.dueDate.year == 2026,
    );

    instance2.status = TaskStatus.inProgress;
    instance2.addLogEntry(TaskLogEntry(
      id: 'log-4',
      user: 'Maria',
      timestamp: DateTime(2026, 1, 25, 11, 0),
      text: 'Zahlen vom Buchhaltungssystem exportiert',
    ));
  }

  void _createInstanceForTemplate(TaskTemplate template) {
    final instance = TaskInstance(
      id: 'instance-${template.id}-${template.dueDate.toIso8601String()}',
      templateId: template.id,
      domainId: template.domainId,
      title: template.title,
      description: template.description,
      startDate: template.startDate,
      dueDate: template.dueDate,
      createdAt: DateTime.now(),
    );
    _instances.add(instance);
  }

  List<TaskDomain> getDomains() => List.unmodifiable(_domains);
  List<TaskTemplate> getTemplates() => List.unmodifiable(_templates);
  TaskTemplate? getTemplateById(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  List<TaskInstance> getInstances() => List.unmodifiable(_instances);

  List<TaskInstance> getActiveInstances() {
    return _instances.where((i) => i.status != TaskStatus.done).toList();
  }

  List<TaskInstance> getArchivedInstances() {
    return _instances.where((i) => i.status == TaskStatus.done).toList();
  }

  List<TaskInstance> getInstancesByDomain(String domainId) {
    return _instances.where((i) => i.domainId == domainId).toList();
  }

  List<TaskInstance> getInstancesSorted({bool includeDone = true}) {
    final sorted = List<TaskInstance>.from(_instances);
    sorted.sort((a, b) {
      if (!includeDone) {
        if (a.status == TaskStatus.done && b.status != TaskStatus.done) return 1;
        if (a.status != TaskStatus.done && b.status == TaskStatus.done) return -1;
      }

      if (a.status == TaskStatus.done && b.status != TaskStatus.done) return 1;
      if (a.status != TaskStatus.done && b.status == TaskStatus.done) return -1;

      if (a.isOverdue && !b.isOverdue) return -1;
      if (!a.isOverdue && b.isOverdue) return 1;

      if (a.isUpcoming && !b.isUpcoming) return -1;
      if (!a.isUpcoming && b.isUpcoming) return 1;

      return a.dueDate.compareTo(b.dueDate);
    });
    return sorted;
  }

  TaskDomain? getDomainById(String id) {
    try {
      return _domains.firstWhere((d) => d.id == id);
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

  void updateInstance(TaskInstance instance) {
    final index = _instances.indexWhere((i) => i.id == instance.id);
    if (index >= 0) {
      _instances[index] = instance;
    }
  }

  void markAsDone(String instanceId) {
    final instance = getInstanceById(instanceId);
    if (instance != null && instance.status != TaskStatus.done) {
      instance.markAsDone();
      updateInstance(instance);

      final template = _templates.firstWhere((t) => t.id == instance.templateId);
      if (template.recurrence.isRecurring) {
        final newStartDate = template.recurrence.nextDate(instance.startDate);
        final newDueDate = template.recurrence.nextDate(instance.dueDate);
        final nextInstance = TaskInstance(
          id: 'instance-${template.id}-${newDueDate.toIso8601String()}',
          templateId: template.id,
          domainId: template.domainId,
          title: template.title,
          description: template.description,
          startDate: newStartDate,
          dueDate: newDueDate,
          createdAt: DateTime.now(),
        );
        _instances.add(nextInstance);
      }
    }
  }

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

  void reset() {
    _domains.clear();
    _templates.clear();
    _instances.clear();
    _initializeMockData();
  }
}
