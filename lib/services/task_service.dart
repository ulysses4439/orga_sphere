import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'local_cache.dart';

class TaskService extends ChangeNotifier {
  static TaskService? _instance;

  final List<TaskDomain> _domains = [];
  final List<Task> _tasks = [];

  late final Future<void> _ready;
  bool _isRefreshing = false;

  /// Zeitpunkt des zuletzt erfolgreichen Abgleichs – bei Daten aus dem
  /// Zwischenspeicher der Zeitpunkt, an dem dieser geschrieben wurde.
  DateTime? _lastSyncAt;

  /// Stammt der aktuelle Anzeigestand aus dem Zwischenspeicher bzw. ist der
  /// letzte Abgleich fehlgeschlagen? Die Oberflaeche zeigt dann „Stand: vor
  /// X Minuten" statt so zu tun, als waeren die Daten frisch.
  bool _isStale = true;

  /// Fehler des letzten Abgleichversuchs, sonst `null`.
  Object? _lastError;

  TaskService._internal() {
    _ready = _init();
  }

  factory TaskService() {
    _instance ??= TaskService._internal();
    return _instance!;
  }

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  Future<void> get ready => _ready;

  DateTime? get lastSyncAt => _lastSyncAt;

  /// Zeigt die App gerade einen aelteren Stand? Trifft zu, solange nur der
  /// Zwischenspeicher gelesen wurde oder der letzte Abgleich scheiterte.
  bool get isStale => _isStale;

  /// Laeuft gerade ein Abgleich? Die Oberflaeche unterscheidet damit „noch am
  /// Laden" von „fehlgeschlagen" – waehrend des ersten Abgleichs nach dem Start
  /// darf nicht „Keine Verbindung" dastehen.
  bool get isRefreshing => _isRefreshing;

  /// Der letzte Abgleich scheiterte an einer abgelaufenen Sitzung. Damit ist
  /// die App unbrauchbar, bis neu angemeldet wird – die Oberflaeche zeigt
  /// dafuer den Fehlerbildschirm statt eines blossen Hinweisbalkens.
  bool get hasAuthError => _lastError is UnauthorizedException;

  /// Startablauf: erst der gespeicherte Stand, dann der Abgleich.
  ///
  /// Der Kniff steckt in der letzten Zeile: Auf den Server gewartet wird nur,
  /// wenn es nichts anzuzeigen gibt. Liegt ein Stand auf dem Geraet, ist die
  /// App sofort bedienbar und die frischen Daten schieben sich nach, sobald
  /// sie da sind.
  Future<void> _init() async {
    final snapshot = await LocalCache.load(AuthService.userId);
    if (snapshot != null) {
      _apply(snapshot.domains, snapshot.tasks);
      _lastSyncAt = snapshot.savedAt;
      _isStale = true;
      notifyListeners();
    }

    final firstRefresh = refresh();
    if (snapshot == null) {
      await firstRefresh;
      // Ohne gespeicherten Stand ist ein gescheiterter Abgleich das Ende der
      // Fahnenstange – der Fehler muss den Aufrufer erreichen, damit die
      // Oberflaeche den Fehlerbildschirm zeigt (bei 401 mit Abmelden-Angebot).
      final error = _lastError;
      if (error != null) throw error;
    }
  }

  /// Holt den kompletten Stand in EINEM Abruf und legt ihn lokal ab.
  ///
  /// Wirft bewusst nicht: Der Aufruf steckt auch im 30-Sekunden-Takt, und ein
  /// kurzer Funkloch-Aussetzer darf dort nichts umwerfen. Was schiefging,
  /// steht in [isStale] und [hasAuthError].
  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    // Sofort melden, damit ein Tippen auf „Erneut versuchen" sichtbar wirkt.
    notifyListeners();
    try {
      final data = await ApiService.sync();
      _apply(data.domains, data.tasks);
      _lastSyncAt = DateTime.now();
      _isStale = false;
      _lastError = null;
      notifyListeners();
      await LocalCache.save(
        userId: AuthService.userId,
        domains: _domains,
        tasks: _tasks,
      );
    } catch (e) {
      _lastError = e;
      _isStale = true;
      notifyListeners();
    } finally {
      _isRefreshing = false;
    }
  }

  /// Uebernimmt einen frischen Stand und rettet dabei bereits geladene
  /// Verlaeufe hinueber.
  ///
  /// Ohne diese Rettung waere der Aktivitaetsverlauf einer geoeffneten Sphere
  /// alle 30 Sekunden wieder leer: Der Abgleich liefert die Eintraege nicht
  /// mit, und die Task-Objekte werden komplett ersetzt.
  ///
  /// Weicht die Anzahl laut Server von der geladenen ab, hat jemand anderes
  /// etwas ergaenzt. Dann gilt der Verlauf als nicht geladen und die
  /// Detailansicht holt ihn beim naechsten Aufbau neu.
  void _apply(List<TaskDomain> domains, List<Task> tasks) {
    final previous = {for (final t in _tasks) t.id: t};
    for (final task in tasks) {
      final old = previous[task.id];
      if (old == null) continue;
      if (old.logsLoaded && old.logCount == task.logCount) {
        task.setLogEntries(old.logEntries);
      }
      // Ein Statuswechsel, der noch beim Server liegt, hat Vorrang vor dem
      // Stand aus der Antwort: Die Antwort kann aelter sein als das Antippen.
      // Ohne das taucht eine gerade abgehakte Position wieder auf, wenn der
      // 30-Sekunden-Abgleich zufaellig dazwischenfunkt.
      if (_statusChangePending.contains(task.id)) {
        task.status = old.status;
        task.completedAt = old.completedAt;
      }
    }
    _domains
      ..clear()
      ..addAll(domains);
    _tasks
      ..clear()
      ..addAll(tasks);
  }

  /// Holt den Aktivitaetsverlauf einer einzelnen Sphere – beim Oeffnen der
  /// Detailansicht, nicht mehr im Voraus fuer alle Spheres.
  ///
  /// Genau hier lag die Hauptlast des alten Startvorgangs: ein eigener Abruf
  /// je Sphere, jeder mit eigenem Verbindungsaufbau.
  Future<void> loadLogs(String taskId, {bool force = false}) async {
    final task = getTaskById(taskId);
    if (task == null) return;
    if (task.logsLoaded && !force) return;
    try {
      final logs = await ApiService.getLogs(taskId);
      task.setLogEntries(logs);
      notifyListeners();
    } catch (_) {
      // Ohne Netz bleibt der Verlauf eben leer; die uebrigen Angaben der
      // Sphere sind trotzdem sichtbar. Der naechste Aufbau versucht es erneut.
    }
  }

  List<TaskDomain> getDomains() => List.unmodifiable(_domains);
  List<Task> getTasks() => List.unmodifiable(_tasks);

  TaskDomain? getDomainById(String id) {
    try {
      return _domains.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  Task? getTaskById(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Task> getActiveTasks() =>
      (_tasks.where((t) => t.status != TaskStatus.done).toList()
        ..sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        }));

  List<Task> getArchivedTasks() =>
      (_tasks.where((t) => t.status == TaskStatus.done).toList()
        ..sort((a, b) {
          final bDate = b.completedAt ?? b.dueDate;
          final aDate = a.completedAt ?? a.dueDate;
          if (bDate == null && aDate == null) return 0;
          if (bDate == null) return 1;
          if (aDate == null) return -1;
          return bDate.compareTo(aDate);
        }));

  Future<Task> createTask({
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    DateTime? dueDate,
    required RecurrencePattern recurrence,
  }) async {
    final task = await ApiService.createTask(
      domainId: domainId,
      title: title,
      description: description,
      startDate: startDate,
      dueDate: dueDate,
      recurrenceFrequency: recurrence.frequency.name,
      recurrenceInterval: recurrence.interval,
    );
    // Frisch angelegt heisst: garantiert ohne Verlaufseintraege. Das gleich
    // festhalten spart der Detailansicht einen Abruf ins Leere.
    task.logsLoaded = true;
    _tasks.add(task);
    _touch();
    return task;
  }

  /// Spheres, deren Statuswechsel gerade beim Server liegt.
  ///
  /// Verhindert, dass ein zweites Antippen dieselbe Sphere noch einmal auf den
  /// Weg schickt, solange die erste Antwort aussteht.
  final Set<String> _statusChangePending = {};

  /// Hakt eine Sphere ab – sichtbar sofort, beim Server im Hintergrund.
  ///
  /// Der Statuswechsel wird zuerst lokal gesetzt und angezeigt und erst danach
  /// gesendet. Vorher lief es andersherum: Die Sphere blieb stehen, bis der
  /// Server geantwortet hatte. Bei gutem Empfang faellt das nicht auf, bei
  /// schlechtem steht man sekundenlang vor einer scheinbar toten Liste – und
  /// tippt erfahrungsgemaess ein zweites Mal.
  ///
  /// Geht das Senden schief, springt die Sphere zurueck und der Aufrufer
  /// bekommt den Fehler zum Anzeigen.
  Future<void> markAsDone(String taskId) async {
    final task = getTaskById(taskId);
    if (task == null || !_statusChangePending.add(taskId)) return;

    final previousStatus = task.status;
    final previousCompletedAt = task.completedAt;
    task.markAsDone();
    notifyListeners();

    try {
      final nextTask = await ApiService.markAsDone(taskId);
      if (nextTask != null) _tasks.add(nextTask);
      _touch();
    } catch (e) {
      // Neu nachschlagen: Zwischenzeitlich kann ein Abgleich die Task-Objekte
      // ausgetauscht haben, und dann zeigt `task` auf eine verworfene Kopie.
      final current = getTaskById(taskId) ?? task;
      current.status = previousStatus;
      current.completedAt = previousCompletedAt;
      notifyListeners();
      rethrow;
    } finally {
      _statusChangePending.remove(taskId);
    }
  }

  /// Holt eine erledigte Sphere zurueck – wie [markAsDone] sofort sichtbar.
  Future<void> reopenTask(String taskId) async {
    final task = getTaskById(taskId);
    if (task == null || !_statusChangePending.add(taskId)) return;

    final previousStatus = task.status;
    final previousCompletedAt = task.completedAt;
    task.status = TaskStatus.open;
    task.completedAt = null;
    notifyListeners();

    try {
      await ApiService.reopenTask(taskId);
      _touch();
    } catch (e) {
      // Neu nachschlagen: Zwischenzeitlich kann ein Abgleich die Task-Objekte
      // ausgetauscht haben, und dann zeigt `task` auf eine verworfene Kopie.
      final current = getTaskById(taskId) ?? task;
      current.status = previousStatus;
      current.completedAt = previousCompletedAt;
      notifyListeners();
      rethrow;
    } finally {
      _statusChangePending.remove(taskId);
    }
  }

  Future<void> deleteTask(String taskId) async {
    await ApiService.deleteTask(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    _touch();
  }

  Future<void> startTask(String taskId) async {
    await ApiService.startTask(taskId);
    final task = getTaskById(taskId);
    if (task != null) task.status = TaskStatus.inProgress;
    _touch();
  }

  Future<void> addLogEntry(String taskId, String text,
      {List<String> attachmentIds = const []}) async {
    final result =
        await ApiService.addLogEntry(taskId, text, attachmentIds: attachmentIds);
    final task = getTaskById(taskId);
    task?.addLogEntry(result.entry);
    if (result.newTaskStatus != null) {
      final newStatus = TaskStatus.values.firstWhere(
        (s) => s.name == result.newTaskStatus,
        orElse: () => task?.status ?? TaskStatus.open,
      );
      task?.status = newStatus;
    }
    _touch();
  }

  Future<void> updateTaskTitle(String taskId, String title) async {
    await ApiService.updateTaskTitle(taskId, title);
    final task = getTaskById(taskId);
    if (task != null) task.title = title;
    _touch();
  }

  Future<void> updateTaskDescription(String taskId, String description) async {
    await ApiService.updateTaskDescription(taskId, description);
    final task = getTaskById(taskId);
    if (task != null) task.description = description;
    _touch();
  }

  Future<void> updateTaskSchedule(
      String taskId, {
      DateTime? startDate,
      DateTime? dueDate,
      bool clearDueDate = false,
      String? recurrenceFrequency,
      int? recurrenceInterval,
  }) async {
    await ApiService.updateTaskSchedule(
      taskId,
      startDate: startDate,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceInterval: recurrenceInterval,
    );
    final task = getTaskById(taskId);
    if (task == null) return;
    if (startDate != null) task.startDate = startDate;
    if (clearDueDate) {
      task.dueDate = null;
    } else if (dueDate != null) {
      task.dueDate = dueDate;
    }
    if (recurrenceFrequency != null || recurrenceInterval != null) {
      final freq = RecurrenceFrequency.values.firstWhere(
        (f) => f.name == (recurrenceFrequency ?? task.recurrence.frequency.name),
        orElse: () => task.recurrence.frequency,
      );
      task.recurrence = RecurrencePattern(
        frequency: freq,
        interval: recurrenceInterval ?? task.recurrence.interval,
      );
    }
    _touch();
  }

  /// Weist die Sphere einem OrbitMember zu (oder hebt die Zuweisung mit
  /// [memberId] == null auf). [displayName]/[email] dienen der sofortigen
  /// Anzeige; beim nächsten Refresh kommen sie ohnehin vom Backend-JOIN.
  Future<void> assignTask(
    String taskId,
    String? memberId, {
    String? displayName,
    String? email,
  }) async {
    await ApiService.assignTask(taskId, memberId);
    final task = getTaskById(taskId);
    if (task != null) {
      task.assignedToMemberId = memberId;
      task.assignedToName = memberId != null ? displayName : null;
      task.assignedToEmail = memberId != null ? email : null;
    }
    _touch();
  }

  Future<void> setReminder(String taskId, DateTime? reminderAt) async {
    await ApiService.setReminder(taskId, reminderAt);
    final task = getTaskById(taskId);
    if (task != null) task.reminderAt = reminderAt;
    _touch();
  }

  Future<TaskDomain> createDomain(
      String name, String description, String color,
      {bool isShoppingList = false}) async {
    final domain = await ApiService.createDomain(name, description, color,
        isShoppingList: isShoppingList);
    _domains.add(domain);
    _touch();
    return domain;
  }

  Future<void> renameDomain(String domainId, String name) async {
    await ApiService.renameDomain(domainId, name);
    final idx = _domains.indexWhere((d) => d.id == domainId);
    if (idx != -1) {
      _domains[idx] = _domains[idx].copyWith(name: name);
    }
    _touch();
  }

  Future<void> updateDomainDescription(
      String domainId, String description) async {
    await ApiService.updateDomainDescription(domainId, description);
    final idx = _domains.indexWhere((d) => d.id == domainId);
    if (idx != -1) {
      _domains[idx] = _domains[idx].copyWith(description: description);
    }
    _touch();
  }

  Future<void> deleteDomain(String domainId) async {
    await ApiService.deleteDomain(domainId);
    _domains.removeWhere((d) => d.id == domainId);
    _tasks.removeWhere((t) => t.domainId == domainId);
    _touch();
  }

  Future<void> moveTask(String taskId, String domainId) async {
    await ApiService.moveTask(taskId, domainId);
    final task = getTaskById(taskId);
    if (task != null) task.domainId = domainId;
    _touch();
  }

  /// Nach einer lokal nachgezogenen Aenderung: Oberflaeche benachrichtigen und
  /// den Zwischenspeicher nachziehen.
  ///
  /// Der Server hat die Aenderung an dieser Stelle bereits bestaetigt – ohne
  /// das Schreiben hier zeigte ein Neustart kurz wieder den Stand von vorher,
  /// bis der erste Abgleich durch ist.
  void _touch() {
    notifyListeners();
    LocalCache.save(
      userId: AuthService.userId,
      domains: _domains,
      tasks: _tasks,
    );
  }
}
