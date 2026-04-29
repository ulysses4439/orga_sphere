/// A log entry for task activity timeline
/// Records progress, comments, and changes
class TaskLogEntry {
  final String id;
  final String user;
  final DateTime timestamp;
  final String text;

  TaskLogEntry({
    required this.id,
    required this.user,
    required this.timestamp,
    required this.text,
  });

  /// Create a copy with modified fields
  TaskLogEntry copyWith({
    String? id,
    String? user,
    DateTime? timestamp,
    String? text,
  }) {
    return TaskLogEntry(
      id: id ?? this.id,
      user: user ?? this.user,
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskLogEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
