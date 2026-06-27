/// Ein Team-Ereignis innerhalb eines Orbits (Feed für Push + In-App-Glocke).
/// Wird vom Backend-Endpoint GET /events geliefert.
class OrbitEvent {
  final String id;
  final String orbitId;
  final String? actorName;
  final String type; // sphere_created | sphere_landed | sphere_assigned | log_added
  final String? sphereId;
  final String? sphereTitle;
  final String? orbitName;
  final String body; // fertiger Anzeigetext
  final DateTime createdAt;

  OrbitEvent({
    required this.id,
    required this.orbitId,
    required this.type,
    required this.body,
    required this.createdAt,
    this.actorName,
    this.sphereId,
    this.sphereTitle,
    this.orbitName,
  });

  factory OrbitEvent.fromJson(Map<String, dynamic> json) {
    return OrbitEvent(
      id: json['id'] as String,
      orbitId: json['orbitId'] as String,
      actorName: json['actorName'] as String?,
      type: json['type'] as String,
      sphereId: json['sphereId'] as String?,
      sphereTitle: json['sphereTitle'] as String?,
      orbitName: json['orbitName'] as String?,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrbitEvent && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
