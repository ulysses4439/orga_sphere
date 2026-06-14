import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'auth_service.dart';

class ApiService {
  static String get _baseUrl => AuthService.baseUrl;

  static Map<String, String> get _headers => AuthService.authHeaders;

  static void _checkStatus(http.Response response) {
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
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
  // Auth
  // -----------------------------------------------------------------------

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    _checkStatus(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> register(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    _checkStatus(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // -----------------------------------------------------------------------
  // Domains
  // -----------------------------------------------------------------------

  static Future<List<TaskDomain>> getDomains() async {
    final response = await http.get(Uri.parse('$_baseUrl/domains'),
        headers: _headers);
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskDomain.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<TaskDomain> createDomain(
      String name, String description, String color) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/domains'),
      headers: _headers,
      body: jsonEncode({'name': name, 'description': description, 'color': color}),
    );
    _checkStatus(response);
    return TaskDomain.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> renameDomain(String domainId, String name) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/domains/$domainId/name'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    _checkStatus(response);
  }

  static Future<void> deleteDomain(String domainId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/domains/$domainId'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  // -----------------------------------------------------------------------
  // OrbitMembers
  // -----------------------------------------------------------------------

  static Future<List<OrbitMember>> getOrbitMembers(String orbitId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/domains/$orbitId/members'),
      headers: _headers,
    );
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => OrbitMember.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<String> inviteCoPilot(String orbitId, String email) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/domains/$orbitId/members'),
      headers: _headers,
      body: jsonEncode({'email': email}),
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['status'] as String; // 'added' or 'invited'
  }

  static Future<void> suspendCoPilot(String orbitId, String memberId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/domains/$orbitId/members/$memberId/suspend'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  static Future<void> reactivateCoPilot(
      String orbitId, String memberId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/domains/$orbitId/members/$memberId/reactivate'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  static Future<void> removeCoPilot(String orbitId, String memberId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/domains/$orbitId/members/$memberId'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  // -----------------------------------------------------------------------
  // Tasks
  // -----------------------------------------------------------------------

  static Future<List<Task>> getActiveTasks() async {
    final response =
        await http.get(Uri.parse('$_baseUrl/tasks'), headers: _headers);
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => Task.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<Task>> getArchivedTasks() async {
    final response = await http.get(
        Uri.parse('$_baseUrl/tasks/archived'), headers: _headers);
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => Task.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<Task> createTask({
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    DateTime? dueDate,
    required String recurrenceFrequency,
    required int recurrenceInterval,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/tasks'),
      headers: _headers,
      body: jsonEncode({
        'domainId': domainId,
        'title': title,
        'description': description,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'recurrenceFrequency': recurrenceFrequency,
        'recurrenceInterval': recurrenceInterval,
      }),
    );
    _checkStatus(response);
    return Task.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<Task?> markAsDone(String taskId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/done'),
      headers: _headers,
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final next = body['nextTask'];
    return next != null ? Task.fromJson(next as Map<String, dynamic>) : null;
  }

  static Future<void> startTask(String taskId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/start'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  static Future<void> reopenTask(String taskId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/reopen'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  static Future<void> deleteTask(String taskId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/tasks/$taskId'),
      headers: _headers,
    );
    _checkStatus(response);
  }

  static Future<void> moveTask(String taskId, String domainId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/domain'),
      headers: _headers,
      body: jsonEncode({'domainId': domainId}),
    );
    _checkStatus(response);
  }

  static Future<void> assignTask(String taskId, String? memberId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/assignee'),
      headers: _headers,
      body: jsonEncode({'memberId': memberId}),
    );
    _checkStatus(response);
  }

  static Future<void> updateTaskTitle(String taskId, String title) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/title'),
      headers: _headers,
      body: jsonEncode({'title': title}),
    );
    _checkStatus(response);
  }

  static Future<void> updateTaskDescription(
      String taskId, String description) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/description'),
      headers: _headers,
      body: jsonEncode({'description': description}),
    );
    _checkStatus(response);
  }

  static Future<void> updateTaskSchedule(
      String taskId, {
      DateTime? startDate,
      DateTime? dueDate,
      bool clearDueDate = false,
      String? recurrenceFrequency,
      int? recurrenceInterval,
  }) async {
    final body = <String, dynamic>{};
    if (startDate != null) body['startDate'] = startDate.toUtc().toIso8601String();
    if (clearDueDate) {
      body['dueDate'] = null;
    } else if (dueDate != null) {
      body['dueDate'] = dueDate.toUtc().toIso8601String();
    }
    if (recurrenceFrequency != null) body['recurrenceFrequency'] = recurrenceFrequency;
    if (recurrenceInterval != null) body['recurrenceInterval'] = recurrenceInterval;
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/schedule'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkStatus(response);
  }

  static Future<void> setReminder(String taskId, DateTime? reminderAt) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/reminder'),
      headers: _headers,
      body: jsonEncode({'reminderAt': reminderAt?.toUtc().toIso8601String()}),
    );
    _checkStatus(response);
  }

  // -----------------------------------------------------------------------
  // Logs
  // -----------------------------------------------------------------------

  static Future<List<TaskLogEntry>> getLogs(String taskId) async {
    final response = await http.get(
        Uri.parse('$_baseUrl/logs/$taskId'), headers: _headers);
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskLogEntry.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<({TaskLogEntry entry, String? newTaskStatus})> addLogEntry(
      String taskId, String text) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/logs'),
      headers: _headers,
      body: jsonEncode({'taskId': taskId, 'text': text}),
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      entry: TaskLogEntry.fromJson(body),
      newTaskStatus: body['taskStatus'] as String?,
    );
  }
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
  @override
  String toString() => 'Sitzung abgelaufen. Bitte erneut anmelden.';
}
