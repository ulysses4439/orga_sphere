import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  static const String _baseUrl =
      'https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net';

  static Future<List<TaskDomain>> getDomains() async {
    final response = await http.get(Uri.parse('$_baseUrl/domains'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskDomain.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<Task>> getActiveTasks() async {
    final response = await http.get(Uri.parse('$_baseUrl/tasks'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => Task.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<Task>> getArchivedTasks() async {
    final response = await http.get(Uri.parse('$_baseUrl/tasks/archived'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => Task.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<Task> createTask({
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    required DateTime dueDate,
    required String recurrenceFrequency,
    required int recurrenceInterval,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/tasks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'domainId': domainId,
        'title': title,
        'description': description,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
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
      headers: {'Content-Type': 'application/json'},
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final next = body['nextTask'];
    return next != null ? Task.fromJson(next as Map<String, dynamic>) : null;
  }

  static Future<void> startTask(String taskId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/start'),
      headers: {'Content-Type': 'application/json'},
    );
    _checkStatus(response);
  }

  static Future<void> reopenTask(String taskId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/reopen'),
      headers: {'Content-Type': 'application/json'},
    );
    _checkStatus(response);
  }

  static Future<void> deleteTask(String taskId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/tasks/$taskId'),
      headers: {'Content-Type': 'application/json'},
    );
    _checkStatus(response);
  }

  static Future<TaskDomain> createDomain(String name, String description, String color) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/domains'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'description': description, 'color': color}),
    );
    _checkStatus(response);
    return TaskDomain.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<TaskLogEntry>> getLogs(String taskId) async {
    final response = await http.get(Uri.parse('$_baseUrl/logs/$taskId'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskLogEntry.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Returns the new log entry and optionally the new task status if it changed.
  static Future<({TaskLogEntry entry, String? newTaskStatus})> addLogEntry(
      String taskId, String user, String text) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/logs'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'taskId': taskId, 'user': user, 'text': text}),
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      entry: TaskLogEntry.fromJson(body),
      newTaskStatus: body['taskStatus'] as String?,
    );
  }

  static Future<void> setReminder(String taskId, DateTime? reminderAt) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/tasks/$taskId/reminder'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'reminderAt': reminderAt?.toUtc().toIso8601String()}),
    );
    _checkStatus(response);
  }

  static void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API-Fehler ${response.statusCode}: ${response.body}');
    }
  }
}
