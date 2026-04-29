/// Template for a recurring task
/// Defines the structure and rules for yearly recurring tasks
class TaskTemplate {
  final String id;
  final String title;
  final String description;
  
  /// Month when the task becomes relevant (1-12)
  final int startMonth;
  
  /// Day of the due date (1-31)
  final int dueDay;
  
  /// Month of the due date (1-12)
  final int dueMonth;

  /// Timestamp when this template was created
  final DateTime createdAt;

  TaskTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.startMonth,
    required this.dueDay,
    required this.dueMonth,
    required this.createdAt,
  }) : assert(startMonth >= 1 && startMonth <= 12),
       assert(dueDay >= 1 && dueDay <= 31),
       assert(dueMonth >= 1 && dueMonth <= 12);

  /// Create a copy with modified fields
  TaskTemplate copyWith({
    String? id,
    String? title,
    String? description,
    int? startMonth,
    int? dueDay,
    int? dueMonth,
    DateTime? createdAt,
  }) {
    return TaskTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startMonth: startMonth ?? this.startMonth,
      dueDay: dueDay ?? this.dueDay,
      dueMonth: dueMonth ?? this.dueMonth,
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
