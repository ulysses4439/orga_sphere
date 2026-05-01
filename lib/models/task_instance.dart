import 'task_status.dart';
import 'task_log_entry.dart';

/// A specific instance of a task.
/// Contains a single occurrence with due date and timeline.
class TaskInstance {
  final String id;
  final String templateId;
  final String domainId;
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime dueDate;

  TaskStatus status;
  final DateTime createdAt;
  DateTime? completedAt;

  /// Activity log for this task instance
  final List<TaskLogEntry> logEntries;

  TaskInstance({
    required this.id,
    required this.templateId,
    required this.domainId,
    required this.title,
    required this.description,
    required this.startDate,
    required this.dueDate,
    this.status = TaskStatus.open,
    required this.createdAt,
    this.completedAt,
    List<TaskLogEntry>? logEntries,
  }) : logEntries = logEntries ?? [];

  factory TaskInstance.fromJson(Map<String, dynamic> json) {
    return TaskInstance(
      id: json['id'] as String,
      templateId: json['templateId'] as String,
      domainId: json['domainId'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      startDate: DateTime.parse(json['startDate'] as String),
      dueDate: DateTime.parse(json['dueDate'] as String),
      status: TaskStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String? ?? 'open'),
        orElse: () => TaskStatus.open,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  int get year => dueDate.year;

  /// Check if this task is overdue
  bool get isOverdue {
    if (status == TaskStatus.done) return false;
    return DateTime.now().isAfter(dueDate);
  }

  /// Check if this task is upcoming (within next 30 days)
  bool get isUpcoming {
    final now = DateTime.now();
    final inThirtyDays = now.add(const Duration(days: 30));
    return !isOverdue && dueDate.isBefore(inThirtyDays);
  }

  /// Add a log entry to the timeline
  void addLogEntry(TaskLogEntry entry) {
    logEntries.add(entry);
    logEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Mark this task as done
  void markAsDone() {
    status = TaskStatus.done;
    completedAt = DateTime.now();
  }

  /// Create a copy with modified fields
  TaskInstance copyWith({
    String? id,
    String? templateId,
    String? domainId,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? dueDate,
    TaskStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    List<TaskLogEntry>? logEntries,
  }) {
    return TaskInstance(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      domainId: domainId ?? this.domainId,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      logEntries: logEntries ?? this.logEntries,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskInstance &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
