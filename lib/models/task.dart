import 'task_status.dart';
import 'task_recurrence.dart';
import 'task_log_entry.dart';

class Task {
  final String id;
  final String domainId;
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime dueDate;
  final RecurrencePattern recurrence;
  TaskStatus status;
  final DateTime createdAt;
  DateTime? completedAt;
  final String? previousTaskId;
  final List<TaskLogEntry> logEntries;

  Task({
    required this.id,
    required this.domainId,
    required this.title,
    required this.description,
    required this.startDate,
    required this.dueDate,
    required this.recurrence,
    this.status = TaskStatus.open,
    required this.createdAt,
    this.completedAt,
    this.previousTaskId,
    List<TaskLogEntry>? logEntries,
  }) : logEntries = logEntries ?? [];

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      domainId: json['domainId'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      startDate: DateTime.parse(json['startDate'] as String),
      dueDate: DateTime.parse(json['dueDate'] as String),
      recurrence: RecurrencePattern(
        frequency: RecurrenceFrequency.values.firstWhere(
          (f) => f.name == (json['recurrenceFrequency'] as String? ?? 'none'),
          orElse: () => RecurrenceFrequency.none,
        ),
        interval: (json['recurrenceInterval'] as int?) ?? 1,
      ),
      status: TaskStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String? ?? 'open'),
        orElse: () => TaskStatus.open,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      previousTaskId: json['previousTaskId'] as String?,
    );
  }

  bool get isRecurring => recurrence.isRecurring;

  int get year => dueDate.year;

  bool get isOverdue {
    if (status == TaskStatus.done) return false;
    return DateTime.now().isAfter(dueDate);
  }

  bool get isUpcoming {
    final now = DateTime.now();
    final inThirtyDays = now.add(const Duration(days: 30));
    return !isOverdue && dueDate.isBefore(inThirtyDays);
  }

  void addLogEntry(TaskLogEntry entry) {
    logEntries.add(entry);
    logEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void markAsDone() {
    status = TaskStatus.done;
    completedAt = DateTime.now();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Task && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
