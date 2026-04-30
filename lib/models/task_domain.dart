/// Domain or area for task grouping.
/// Examples: Verein, Arbeit, Privat.
class TaskDomain {
  final String id;
  final String name;
  final String description;

  TaskDomain({
    required this.id,
    required this.name,
    required this.description,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskDomain &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
