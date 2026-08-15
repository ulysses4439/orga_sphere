import 'task_status.dart';
import 'task_recurrence.dart';
import 'task_log_entry.dart';

class Task {
  final String id;
  String domainId;
  String title;
  String description;
  DateTime startDate;
  DateTime? dueDate;
  RecurrencePattern recurrence;
  TaskStatus status;
  final DateTime createdAt;
  DateTime? completedAt;
  DateTime? reminderAt;
  final String? previousTaskId;

  /// Klammert alle Ausgaben einer Wiederholung zusammen – die id der ERSTEN
  /// Sphere der Serie.
  ///
  /// Das Gerät braucht sie, um ohne Netz die Kennung der nächsten Ausgabe
  /// selbst zu berechnen (siehe utils/recurrence.dart). Ohne sie könnte es die
  /// Folge-Sphere nicht so benennen, wie der Server es täte – und beim
  /// Abgleich entstünden zwei Zeilen für denselben Termin.
  final String? seriesId;

  // Zuweisung an ein OrbitMember (Pilot/Co-Pilot). Name/E-Mail kommen
  // zur Anzeige aus dem Backend-JOIN und werden nur lesend genutzt.
  String? assignedToMemberId;
  String? assignedToName;
  String? assignedToEmail;
  final List<TaskLogEntry> logEntries;

  /// Anzahl der Verlaufseintraege laut Server.
  ///
  /// Die Liste zeigt „N Eintraege" an, ohne die Eintraege selbst zu kennen –
  /// die holt erst die Detailansicht. Frueher lud die App beim Start fuer jede
  /// Sphere den kompletten Verlauf, nur um diese Zahl anzeigen zu koennen.
  int logCount;

  /// Wurde der Verlauf fuer diese Sphere schon vom Server geholt?
  ///
  /// Unterscheidet „noch nicht geladen" von „geladen und tatsaechlich leer" –
  /// sonst zeigt die Detailansicht beim Oeffnen faelschlich „Noch keine
  /// Eintraege", bevor die Antwort da ist.
  bool logsLoaded = false;

  String? get assignedToLabel {
    final name = assignedToName;
    if (name != null && name.isNotEmpty) return name;
    final email = assignedToEmail;
    if (email != null && email.isNotEmpty) return email;
    return null;
  }

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
    this.reminderAt,
    this.previousTaskId,
    this.seriesId,
    this.assignedToMemberId,
    this.assignedToName,
    this.assignedToEmail,
    this.logCount = 0,
    List<TaskLogEntry>? logEntries,
  }) : logEntries = logEntries ?? [];

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      domainId: json['domainId'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      startDate: DateTime.parse(json['startDate'] as String),
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate'] as String) : null,
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
      reminderAt: json['reminderAt'] != null
          ? DateTime.parse(json['reminderAt'] as String)
          : null,
      previousTaskId: json['previousTaskId'] as String?,
      seriesId: json['seriesId'] as String?,
      assignedToMemberId: json['assignedToMemberId'] as String?,
      assignedToName: json['assignedToName'] as String?,
      assignedToEmail: json['assignedToEmail'] as String?,
      logCount: (json['logCount'] as int?) ?? 0,
    );
  }

  /// Fuer den lokalen Zwischenspeicher. Die Feldnamen entsprechen genau denen
  /// der Server-Antwort, damit [Task.fromJson] beide Quellen lesen kann und es
  /// keine zweite, leicht abweichende Leseroutine gibt.
  ///
  /// Der Verlauf bleibt aussen vor: Er wird ohnehin beim Oeffnen der Sphere
  /// frisch geholt, und im Zwischenspeicher wuerde er die Datei unnoetig
  /// aufblaehen. Die Anzahl [logCount] reicht fuer die Listenanzeige.
  Map<String, dynamic> toJson() => {
        'id': id,
        'domainId': domainId,
        'title': title,
        'description': description,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'recurrenceFrequency': recurrence.frequency.name,
        'recurrenceInterval': recurrence.interval,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'previousTaskId': previousTaskId,
        'seriesId': seriesId,
        'assignedToMemberId': assignedToMemberId,
        'assignedToName': assignedToName,
        'assignedToEmail': assignedToEmail,
        'logCount': logCount,
      };

  bool get isRecurring => recurrence.isRecurring;

  int get year => dueDate?.year ?? 9999;

  bool get isOverdue {
    if (status == TaskStatus.done) return false;
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  bool get isUpcoming {
    if (dueDate == null) return false;
    final now = DateTime.now();
    final inThirtyDays = now.add(const Duration(days: 30));
    return !isOverdue && dueDate!.isBefore(inThirtyDays);
  }

  void addLogEntry(TaskLogEntry entry) {
    logEntries.add(entry);
    logEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    logCount = logEntries.length;
  }

  /// Uebernimmt den vom Server geholten Verlauf.
  ///
  /// Setzt [logCount] gleich mit: Solange der Verlauf nicht geladen war, kam
  /// die Zahl aus dem Abgleich; ab jetzt ist die geladene Liste die genauere
  /// Quelle (jemand anderes kann in der Zwischenzeit etwas ergaenzt haben).
  void setLogEntries(List<TaskLogEntry> entries) {
    logEntries
      ..clear()
      ..addAll(entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    logCount = logEntries.length;
    logsLoaded = true;
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
