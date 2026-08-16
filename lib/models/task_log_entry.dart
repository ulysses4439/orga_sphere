/// A log entry for task activity timeline
/// Records progress, comments, and changes
class TaskLogEntry {
  final String id;
  final String user;
  final DateTime timestamp;
  final String text;

  /// Konto-ID des Verfassers. Nur wer hier steht, darf den Eintrag ändern oder
  /// löschen – der Anzeigename in [user] taugt dafür nicht, weil er nicht
  /// eindeutig ist und sich ändern lässt.
  ///
  /// Bei Einträgen aus der Zeit vor der Umstellung ist das Feld leer. Sie
  /// gehören dann niemandem und bleiben unveränderlich.
  final String? createdBy;

  /// Gesetzt, sobald der Text nachträglich geändert wurde. Die Anzeige weist
  /// darauf hin: Wer etwas liest, soll erkennen, dass es nicht mehr der
  /// ursprüngliche Wortlaut ist.
  final DateTime? editedAt;

  TaskLogEntry({
    required this.id,
    required this.user,
    required this.timestamp,
    required this.text,
    this.createdBy,
    this.editedAt,
  });

  /// Darf [userId] diesen Eintrag ändern oder löschen?
  bool istVon(String? userId) =>
      userId != null && createdBy != null && createdBy == userId;

  static DateTime? _datumOderNull(dynamic wert) {
    if (wert is! String || wert.isEmpty) return null;
    return DateTime.tryParse(wert);
  }

  factory TaskLogEntry.fromJson(Map<String, dynamic> json) {
    return TaskLogEntry(
      id: json['id'] as String,
      user: json['user'] as String? ?? 'Unbekannt',
      timestamp: DateTime.parse(json['timestamp'] as String),
      text: json['text'] as String,
      createdBy: json['createdBy'] as String?,
      editedAt: _datumOderNull(json['editedAt']),
    );
  }

  /// Fuer den lokalen Zwischenspeicher – Feldnamen wie in der Server-Antwort,
  /// damit [TaskLogEntry.fromJson] beide Quellen liest.
  Map<String, dynamic> toJson() => {
        'id': id,
        'user': user,
        'timestamp': timestamp.toIso8601String(),
        'text': text,
        if (createdBy != null) 'createdBy': createdBy,
        if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
      };

  /// Create a copy with modified fields
  TaskLogEntry copyWith({
    String? id,
    String? user,
    DateTime? timestamp,
    String? text,
    String? createdBy,
    DateTime? editedAt,
  }) {
    return TaskLogEntry(
      id: id ?? this.id,
      user: user ?? this.user,
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      createdBy: createdBy ?? this.createdBy,
      editedAt: editedAt ?? this.editedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskLogEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          editedAt == other.editedAt;

  @override
  int get hashCode => Object.hash(id, text, editedAt);
}
