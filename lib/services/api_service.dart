import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import '../models/models.dart';
import 'auth_service.dart';

/// Alles, was die App zum Start braucht – Ergebnis eines einzigen Abrufs.
class SyncData {
  final List<TaskDomain> domains;
  final List<Task> tasks;

  const SyncData({required this.domains, required this.tasks});
}

class ApiService {
  static String get _baseUrl => AuthService.baseUrl;

  static Map<String, String> get _headers => AuthService.authHeaders;

  // Alle Aufrufe laufen ueber den gemeinsamen Client aus [AuthService] – siehe
  // die ausfuehrliche Begruendung dort. Kurz: eine offene Verbindung statt
  // eines neuen TLS-Handshakes pro Anfrage.
  static http.Client get _client => AuthService.client;

  static Future<http.Response> _get(String path) => _client
      .get(Uri.parse('$_baseUrl$path'), headers: _headers)
      .timeout(AuthService.timeout);

  static Future<http.Response> _post(String path, [Object? body]) => _client
      .post(Uri.parse('$_baseUrl$path'),
          headers: _headers, body: body == null ? null : jsonEncode(body))
      .timeout(AuthService.timeout);

  static Future<http.Response> _patch(String path, [Object? body]) => _client
      .patch(Uri.parse('$_baseUrl$path'),
          headers: _headers, body: body == null ? null : jsonEncode(body))
      .timeout(AuthService.timeout);

  static Future<http.Response> _delete(String path, [Object? body]) => _client
      .delete(Uri.parse('$_baseUrl$path'),
          headers: _headers, body: body == null ? null : jsonEncode(body))
      .timeout(AuthService.timeout);

  /// Führt einen Aufruf aus und übersetzt Netzprobleme in [OfflineException].
  ///
  /// Ohne diese Übersetzung sind „kein Netz" und „Server sagt nein" für den
  /// Aufrufer nicht auseinanderzuhalten — beides käme als nackte `Exception`
  /// an. Genau daran hing bisher, dass eine Änderung im Funkloch verworfen
  /// wurde, statt in die Warteschlange zu gehen.
  static Future<T> mitNetzpruefung<T>(Future<T> Function() aufruf) async {
    try {
      return await aufruf();
    } on SocketException catch (e) {
      throw OfflineException(e.osError?.message ?? e.message);
    } on http.ClientException catch (e) {
      throw OfflineException(e.message);
    } on TimeoutException {
      throw const OfflineException('Zeitüberschreitung');
    } on HandshakeException catch (e) {
      throw OfflineException(e.message);
    }
  }

  /// POST mit Auftragskennung, damit ein Wiedergänger beim Server nur einmal
  /// wirkt. Netzfehler kommen als [OfflineException] heraus.
  static Future<http.Response> _postMitKennung(
      String path, String? commandId, Object? body) {
    return mitNetzpruefung(() => _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: {..._headers, 'X-Command-Id': ?commandId},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(AuthService.timeout));
  }

  /// Führt einen beliebigen Auftrag aus der Warteschlange aus.
  ///
  /// Absichtlich allgemein: Die Warteschlange kennt nur Methode, Pfad und
  /// Rumpf und braucht kein Wissen über die fünfzehn Auftragsarten. Die
  /// Auftragskennung geht als `X-Command-Id` mit — daran erkennt der Server
  /// einen Wiedergänger und führt ihn nicht ein zweites Mal aus.
  static Future<Map<String, dynamic>> ausfuehren({
    required String method,
    required String path,
    required String commandId,
    Map<String, dynamic>? body,
  }) async {
    return mitNetzpruefung(() async {
      final uri = Uri.parse('$_baseUrl$path');
      final headers = {..._headers, 'X-Command-Id': commandId};
      final rumpf = body == null ? null : jsonEncode(body);

      final http.Response response;
      switch (method) {
        case 'POST':
          response = await _client.post(uri, headers: headers, body: rumpf)
              .timeout(AuthService.timeout);
        case 'PATCH':
          response = await _client.patch(uri, headers: headers, body: rumpf)
              .timeout(AuthService.timeout);
        case 'DELETE':
          response = await _client.delete(uri, headers: headers, body: rumpf)
              .timeout(AuthService.timeout);
        default:
          throw ArgumentError('Unbekannte Methode: $method');
      }
      _checkStatus(response);
      if (response.body.isEmpty) return <String, dynamic>{};
      final gelesen = jsonDecode(response.body);
      return gelesen is Map<String, dynamic> ? gelesen : <String, dynamic>{};
    });
  }

  static void _checkStatus(http.Response response) {
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
    }
    // Der Server ist da, kann aber gerade nicht: Neustart nach einer
    // Auslieferung, Überlastung, Wartung. Für die Warteschlange ist das
    // dasselbe wie kein Netz – erneut versuchen, nichts verwerfen.
    if (response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      throw OfflineException('Server vorübergehend nicht verfügbar '
          '(${response.statusCode})');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String msg = 'API-Fehler ${response.statusCode}';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        msg = body['error'] as String? ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
  }

  // -----------------------------------------------------------------------
  // Abgleich
  // -----------------------------------------------------------------------

  /// Holt Orbits, offene und erledigte Spheres in EINEM Abruf.
  ///
  /// Ersetzt die frueheren drei nacheinander abgewarteten Aufrufe. Die
  /// Verlaufseintraege sind bewusst NICHT dabei – die holt [getLogs] erst,
  /// wenn jemand eine Sphere oeffnet. Vorher lud die App sie fuer jede
  /// einzelne Sphere im Voraus, was den Start um einen Abruf pro Sphere
  /// verlaengerte.
  static Future<SyncData> sync() async {
    final response = await _get('/sync');

    // Rueckfallweg auf die drei Einzelabrufe, falls der Server /sync noch nicht
    // kennt. App und Backend werden getrennt ausgeliefert – ohne diesen Weg
    // stuende die App vor einem leeren Bildschirm, sollte die Bereitstellung
    // des Backends einmal fehlschlagen oder zurueckgerollt werden.
    if (response.statusCode == 404) return _syncViaSingleEndpoints();

    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final domains = (body['domains'] as List<dynamic>)
        .map((j) => TaskDomain.fromJson(j as Map<String, dynamic>))
        .toList();
    final tasks = <Task>[
      for (final j in body['tasks'] as List<dynamic>)
        Task.fromJson(j as Map<String, dynamic>),
      for (final j in body['archived'] as List<dynamic>)
        Task.fromJson(j as Map<String, dynamic>),
    ];
    return SyncData(domains: domains, tasks: tasks);
  }

  /// Notweg fuer ein Backend ohne `/sync` – siehe [sync].
  ///
  /// Immerhin parallel statt nacheinander: Ueber die offene Verbindung laufen
  /// die drei Abrufe gleichzeitig. Die Verlaufseintraege bleiben auch hier
  /// aussen vor, die Anzahl fehlt dann eben (aeltere Backends liefern kein
  /// `logCount`, dann steht in der Liste kein „N Eintraege").
  static Future<SyncData> _syncViaSingleEndpoints() async {
    final results = await Future.wait([
      getDomains(),
      getActiveTasks(),
      getArchivedTasks(),
    ]);
    return SyncData(
      domains: results[0] as List<TaskDomain>,
      tasks: [
        ...results[1] as List<Task>,
        ...results[2] as List<Task>,
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Auth
  // -----------------------------------------------------------------------

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await _post('/auth/login', {
      'email': email,
      'password': password,
    });
    _checkStatus(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> register(
      String email, String password) async {
    final response = await _post('/auth/register', {
      'email': email,
      'password': password,
    });
    _checkStatus(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // -----------------------------------------------------------------------
  // Domains
  // -----------------------------------------------------------------------

  static Future<List<TaskDomain>> getDomains() async {
    final response = await _get('/domains');
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskDomain.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<TaskDomain> createDomain(
      String name, String description, String color,
      {required String id,
      bool isShoppingList = false,
      String? icon,
      int? keepLandedCount,
      String? commandId}) async {
    final response = await _postMitKennung('/domains', commandId, {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'isShoppingList': isShoppingList,
      'icon': icon,
      'keepLandedCount': ?keepLandedCount,
    });
    _checkStatus(response);
    return TaskDomain.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Symbol setzen oder – mit leerem Text – wieder entfernen.
  static Future<void> updateDomainIcon(String domainId, String? icon) async {
    final response = await _patch('/domains/$domainId/icon', {'icon': icon ?? ''});
    _checkStatus(response);
  }

  /// Wie viele gelandete Ausgaben je Wiederholungsserie aufgehoben werden.
  static Future<void> updateDomainKeepLanded(String domainId, int anzahl) async {
    final response = await _patch(
        '/domains/$domainId/keep-landed', {'keepLandedCount': anzahl});
    _checkStatus(response);
  }

  static Future<void> renameDomain(String domainId, String name) async {
    final response = await _patch('/domains/$domainId/name', {'name': name});
    _checkStatus(response);
  }

  static Future<void> updateDomainDescription(
      String domainId, String description) async {
    final response = await _patch(
        '/domains/$domainId/description', {'description': description});
    _checkStatus(response);
  }

  static Future<void> deleteDomain(String domainId) async {
    final response = await _delete('/domains/$domainId');
    _checkStatus(response);
  }

  // -----------------------------------------------------------------------
  // OrbitMembers
  // -----------------------------------------------------------------------

  static Future<List<OrbitMember>> getOrbitMembers(String orbitId) async {
    final response = await _get('/domains/$orbitId/members');
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => OrbitMember.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<String> inviteCoPilot(String orbitId, String email) async {
    final response = await _post('/domains/$orbitId/members', {'email': email});
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['status'] as String; // 'invited'
  }

  // -----------------------------------------------------------------------
  // Einladungen (offene Mitgliedschaften des angemeldeten Nutzers)
  // -----------------------------------------------------------------------

  static Future<List<OrbitInvitation>> getInvitations() async {
    final response = await _get('/invitations');
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((j) => OrbitInvitation.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static Future<void> acceptInvitation(String invitationId) async {
    final response = await _post('/invitations/$invitationId/accept');
    _checkStatus(response);
  }

  static Future<void> declineInvitation(String invitationId) async {
    final response = await _post('/invitations/$invitationId/decline');
    _checkStatus(response);
  }

  static Future<void> suspendCoPilot(String orbitId, String memberId) async {
    final response =
        await _patch('/domains/$orbitId/members/$memberId/suspend');
    _checkStatus(response);
  }

  static Future<void> reactivateCoPilot(
      String orbitId, String memberId) async {
    final response =
        await _patch('/domains/$orbitId/members/$memberId/reactivate');
    _checkStatus(response);
  }

  static Future<void> removeCoPilot(String orbitId, String memberId) async {
    final response = await _delete('/domains/$orbitId/members/$memberId');
    _checkStatus(response);
  }

  // -----------------------------------------------------------------------
  // Dateianhaenge
  // -----------------------------------------------------------------------

  static Future<List<SphereAttachment>> getAttachments(String taskId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/tasks/$taskId/attachments'),
      headers: _headers,
    );
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((j) => SphereAttachment.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Lädt eine Datei zu einer Sphere hoch.
  ///
  /// Der Anhang liegt danach beim Server, gehört aber noch zu keinem
  /// Verlaufseintrag – den gibt es zu diesem Zeitpunkt ja noch nicht. Die
  /// Zuordnung macht [addLogEntry] beim Absenden über `attachmentIds`.
  static Future<SphereAttachment> uploadAttachment(
    String taskId, {
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String? attachmentId,
    String? commandId,
  }) async {
    return mitNetzpruefung(() => _uploadAttachment(taskId,
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        attachmentId: attachmentId,
        commandId: commandId));
  }

  static Future<SphereAttachment> _uploadAttachment(
    String taskId, {
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String? attachmentId,
    String? commandId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/tasks/$taskId/attachments'),
    );
    // Beide Kennungen als Formularfeld: Bei einer mehrteiligen Uebertragung
    // gibt es keinen JSON-Koerper, in den sie sonst passen wuerden.
    if (attachmentId != null) request.fields['id'] = attachmentId;
    if (commandId != null) request.fields['commandId'] = commandId;
    // Content-Type muss hier weg: Bei einer mehrteiligen Übertragung setzt ihn
    // das Paket selbst, samt der Trennmarke zwischen den Teilen. Ein von Hand
    // gesetztes application/json würde die Übertragung unlesbar machen.
    request.headers.addAll(
      Map<String, String>.from(_headers)..remove('Content-Type'),
    );
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
      contentType: MediaType.parse(contentType),
    ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkStatus(response);
    return SphereAttachment.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Holt die Datei als Bytes – zum Speichern oder Weiterreichen.
  static Future<Uint8List> downloadAttachment(String attachmentId) async {
    final response = await http.get(
      Uri.parse(attachmentContentUrl(attachmentId)),
      headers: _headers,
    );
    _checkStatus(response);
    return response.bodyBytes;
  }

  static Future<void> deleteAttachment(String attachmentId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/attachments/$attachmentId'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  /// Adresse, unter der die Datei selbst liegt.
  ///
  /// Sie zeigt bewusst auf das Backend und nicht in den Speicher: So gilt für
  /// jede Datei dieselbe Zugriffsprüfung wie für die Sphere. Der Aufruf braucht
  /// deshalb den Anmeldekopf – [attachmentHeaders] liefert ihn, etwa für
  /// `Image.network`.
  static String attachmentContentUrl(String attachmentId) =>
      '$_baseUrl/attachments/$attachmentId/content';

  static Map<String, String> get attachmentHeaders => _headers;

  // -----------------------------------------------------------------------
  // Tasks
  // -----------------------------------------------------------------------

  static Future<List<Task>> getActiveTasks() async {
    final response = await _get('/tasks');
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => Task.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<Task>> getArchivedTasks() async {
    final response = await _get('/tasks/archived');
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => Task.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Legt eine Sphere an.
  ///
  /// [id] wird vom Gerät vergeben, damit eine offline angelegte Sphere von
  /// Anfang an ihre endgültige Kennung trägt. Ohne das müsste sie zunächst mit
  /// einer Ersatzkennung leben und beim Abgleich umgehängt werden – samt
  /// allem, was inzwischen daran hängt.
  static Future<Task> createTask({
    required String id,
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    DateTime? dueDate,
    required String recurrenceFrequency,
    required int recurrenceInterval,
    String? commandId,
  }) async {
    final response = await _postMitKennung('/tasks', commandId, {
      'id': id,
      'domainId': domainId,
      'title': title,
      'description': description,
      // Auf Mitternacht normalisiert: Sonst landet beim Anlegen die
      // Uhrzeit des Erfassungsmoments in der Datenbank.
      'startDate': _dateOnly(startDate),
      'dueDate': dueDate == null ? null : _dateOnly(dueDate),
      'recurrenceFrequency': recurrenceFrequency,
      'recurrenceInterval': recurrenceInterval,
    });
    _checkStatus(response);
    return Task.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Hakt eine Sphere ab.
  ///
  /// [commandId] und [occurredAt] gehören zusammen: Scheitert der Aufruf am
  /// Netz, wandert derselbe Auftrag mit derselben Kennung in die Warteschlange
  /// und wird später erneut gesendet — der Server führt ihn dann nur einmal
  /// aus. [occurredAt] sorgt dafür, dass im Verlauf der Zeitpunkt des Abhakens
  /// steht und nicht der des Abgleichs.
  static Future<Task?> markAsDone(String taskId,
      {String? commandId, DateTime? occurredAt}) async {
    return mitNetzpruefung(() async {
      final response = await _client
          .patch(
            Uri.parse('$_baseUrl/tasks/$taskId/done'),
            headers: {..._headers, 'X-Command-Id': ?commandId},
            // UTC ist Pflicht: `toIso8601String()` einer lokalen Zeit hat KEINE
            // Zeitzonenangabe, und der Server liest sie dann als seine eigene
            // Zeit (Azure läuft in UTC). Aus 09:23 deutscher Zeit wurden dort
            // 09:23 UTC – zwei Stunden in der Zukunft, worauf die Begrenzung
            // im Backend sie auf „jetzt" kappte. Offline erfasste Zeitpunkte
            // gingen so verloren.
            body: jsonEncode(
                {'occurredAt': ?occurredAt?.toUtc().toIso8601String()}),
          )
          .timeout(AuthService.timeout);
      _checkStatus(response);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final next = body['nextTask'];
      return next != null ? Task.fromJson(next as Map<String, dynamic>) : null;
    });
  }

  static Future<void> startTask(String taskId) async {
    final response = await _patch('/tasks/$taskId/start');
    _checkStatus(response);
  }

  static Future<void> reopenTask(String taskId) async {
    final response = await _patch('/tasks/$taskId/reopen');
    _checkStatus(response);
  }

  static Future<void> deleteTask(String taskId) async {
    final response = await _delete('/tasks/$taskId');
    _checkStatus(response);
  }

  static Future<void> moveTask(String taskId, String domainId) async {
    final response = await _patch('/tasks/$taskId/domain', {'domainId': domainId});
    _checkStatus(response);
  }

  static Future<void> assignTask(String taskId, String? memberId) async {
    final response = await _patch('/tasks/$taskId/assignee', {'memberId': memberId});
    _checkStatus(response);
  }

  static Future<void> updateTaskTitle(String taskId, String title) async {
    final response = await _patch('/tasks/$taskId/title', {'title': title});
    _checkStatus(response);
  }

  static Future<void> updateTaskDescription(
      String taskId, String description) async {
    final response =
        await _patch('/tasks/$taskId/description', {'description': description});
    _checkStatus(response);
  }

  /// Kalenderdatum ohne Uhrzeit und ohne Zeitzonenangabe, z. B.
  /// `2026-08-09T00:00:00.000`. Start- und Fälligkeitsdatum bezeichnen einen
  /// Tag, keinen Zeitpunkt – eine Umrechnung in UTC würde sie je nach
  /// Sommer-/Winterzeit auf den Vortag verschieben.
  ///
  /// Nicht zu verwechseln mit `reminderAt`: Das ist ein echter Zeitpunkt und
  /// wird bewusst als UTC übertragen.
  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String();

  static Future<void> updateTaskSchedule(
      String taskId, {
      DateTime? startDate,
      DateTime? dueDate,
      bool clearDueDate = false,
      String? recurrenceFrequency,
      int? recurrenceInterval,
  }) async {
    final body = <String, dynamic>{};
    // Start- und Fälligkeitsdatum sind reine Kalenderdaten ohne Uhrzeit und
    // werden deshalb OHNE Zeitzonenumrechnung übertragen – genau wie beim
    // Anlegen in [createTask].
    //
    // Ein `.toUtc()` hier hat Mitternacht deutscher Sommerzeit in 22:00 des
    // Vortages verwandelt, wodurch das Datum nach dem nächsten Abgleich mit
    // dem Server einen Tag zurücksprang.
    if (startDate != null) body['startDate'] = _dateOnly(startDate);
    if (clearDueDate) {
      body['dueDate'] = null;
    } else if (dueDate != null) {
      body['dueDate'] = _dateOnly(dueDate);
    }
    if (recurrenceFrequency != null) body['recurrenceFrequency'] = recurrenceFrequency;
    if (recurrenceInterval != null) body['recurrenceInterval'] = recurrenceInterval;
    final response = await _patch('/tasks/$taskId/schedule', body);
    _checkStatus(response);
  }

  static Future<void> setReminder(String taskId, DateTime? reminderAt) async {
    final response = await _patch('/tasks/$taskId/reminder',
        {'reminderAt': reminderAt?.toUtc().toIso8601String()});
    _checkStatus(response);
  }

  // -----------------------------------------------------------------------
  // Logs
  // -----------------------------------------------------------------------

  static Future<List<TaskLogEntry>> getLogs(String taskId) async {
    final response = await _get('/logs/$taskId');
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskLogEntry.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<({TaskLogEntry entry, String? newTaskStatus})> addLogEntry(
      String taskId, String text,
      {List<String> attachmentIds = const [],
      String? entryId,
      String? commandId,
      DateTime? occurredAt}) async {
    final response = await _postMitKennung('/logs', commandId, {
      'id': ?entryId,
      'occurredAt': ?occurredAt?.toUtc().toIso8601String(),
      'taskId': taskId,
      'text': text,
      // Bereits hochgeladene Anhänge, die dieser Eintrag übernehmen soll. Der
      // Server prüft dabei, dass es die eigenen und noch freien Anhänge
      // derselben Sphere sind.
      if (attachmentIds.isNotEmpty) 'attachmentIds': attachmentIds,
    });
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      entry: TaskLogEntry.fromJson(body),
      newTaskStatus: body['taskStatus'] as String?,
    );
  }

  // -----------------------------------------------------------------------
  // Devices (Push-Token) & Events (Team-Aktivitäten)
  // -----------------------------------------------------------------------

  static Future<void> registerDevice(String token, String platform) async {
    final response =
        await _post('/devices', {'token': token, 'platform': platform});
    _checkStatus(response);
  }

  static Future<void> deleteDevice(String token) async {
    final response = await _delete('/devices', {'token': token});
    _checkStatus(response);
  }

  static Future<List<OrbitEvent>> getEvents({DateTime? since}) async {
    final query = since != null
        ? '?since=${Uri.encodeQueryComponent(since.toUtc().toIso8601String())}'
        : '';
    final response = await _get('/events$query');
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((j) => OrbitEvent.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Blendet eine Meldung für den eigenen Account aus. Das Ereignis selbst
  /// bleibt bestehen – andere Mitglieder des Orbits sehen es weiterhin.
  static Future<void> dismissEvent(String eventId) async {
    final response = await _delete('/events/$eventId');
    _checkStatus(response);
  }

  /// Blendet alle derzeit sichtbaren Meldungen auf einmal aus.
  static Future<void> dismissAllEvents() async {
    final response = await _delete('/events');
    _checkStatus(response);
  }
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
  @override
  String toString() => 'Sitzung abgelaufen. Bitte erneut anmelden.';
}

/// Der Server war nicht erreichbar – Funkloch, Flugmodus, Zeitüberschreitung
/// oder ein gerade neu startender App Service.
///
/// Streng zu unterscheiden von einer echten Ablehnung: Eine Änderung, die
/// hieran scheitert, ist **nicht verloren**. Sie muss nur später erneut
/// gesendet werden. Genau diese Unterscheidung fehlte bisher — deshalb sprang
/// ein Häkchen im Funkloch zurück, statt in die Warteschlange zu wandern.
class OfflineException implements Exception {
  final String grund;
  const OfflineException(this.grund);
  @override
  String toString() => 'Keine Verbindung zum Server ($grund)';
}
