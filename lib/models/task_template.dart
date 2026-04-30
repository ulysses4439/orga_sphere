import 'task_recurrence.dart';

/// Template for a task.
/// Supports domains, one-time tasks and flexible recurrence rhythms.
class TaskTemplate {
  final String id;
  final String domainId;
  final String title;
  final String description;

  /// Date when the task becomes relevant.
  final DateTime startDate;

  /// Due date for the task item.
  final DateTime dueDate;

  final RecurrencePattern recurrence;

  /// Timestamp when this template was created.
  final DateTime createdAt;

  TaskTemplate({
    required this.id,
    required this.domainId,
    required this.title,
    required this.description,
    required this.startDate,
    required this.dueDate,
    required this.recurrence,
    required this.createdAt,
  }) : assert(startDate.isBefore(dueDate) || startDate.isAtSameMomentAs(dueDate));

  bool get isOneTime => recurrence.frequency == RecurrenceFrequency.none;

  /// Create a copy with modified fields.
  TaskTemplate copyWith({
    String? id,
    String? domainId,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? dueDate,
    RecurrencePattern? recurrence,
    DateTime? createdAt,
  }) {
    return TaskTemplate(
      id: id ?? this.id,
      domainId: domainId ?? this.domainId,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      recurrence: recurrence ?? this.recurrence,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskTemplate &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
