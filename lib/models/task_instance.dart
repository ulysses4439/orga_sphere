import 'task_status.dart';
import 'task_log_entry.dart';

/// A specific instance of a recurring task
/// Represents one year's "capsule" of a task template
class TaskInstance {
  final String id;
  final String templateId;
  final int year;
  final String title;
  final String description;
  final int startMonth;
  final int dueDay;
  final int dueMonth;
  
  TaskStatus status;
  final DateTime createdAt;
  DateTime? completedAt;
  
  /// Activity log for this task instance
  final List<TaskLogEntry> logEntries;

  TaskInstance({
    required this.id,
    required this.templateId,
    required this.year,
    required this.title,
    required this.description,
    required this.startMonth,
    required this.dueDay,
    required this.dueMonth,
    this.status = TaskStatus.open,
    required this.createdAt,
    this.completedAt,
    List<TaskLogEntry>? logEntries,
  }) : logEntries = logEntries ?? [];

  /// Calculate the due date for this instance
  DateTime getDueDate() {
    return DateTime(year, dueMonth, dueDay);
  }

  /// Check if this task is overdue
  bool get isOverdue {
    if (status == TaskStatus.done) return false;
    return DateTime.now().isAfter(getDueDate());
  }

  /// Check if this task is upcoming (within next 30 days)
  bool get isUpcoming {
    final dueDate = getDueDate();
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
    int? year,
    String? title,
    String? description,
    int? startMonth,
    int? dueDay,
    int? dueMonth,
    TaskStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    List<TaskLogEntry>? logEntries,
  }) {
    return TaskInstance(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      year: year ?? this.year,
      title: title ?? this.title,
      description: description ?? this.description,
      startMonth: startMonth ?? this.startMonth,
      dueDay: dueDay ?? this.dueDay,
      dueMonth: dueMonth ?? this.dueMonth,
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
