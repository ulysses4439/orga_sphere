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

  static Future<List<TaskTemplate>> getTemplates() async {
    final response = await http.get(Uri.parse('$_baseUrl/templates'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskTemplate.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<TaskInstance>> getActiveInstances() async {
    final response = await http.get(Uri.parse('$_baseUrl/instances'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskInstance.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<TaskInstance>> getArchivedInstances() async {
    final response = await http.get(Uri.parse('$_baseUrl/instances/archived'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskInstance.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<List<TaskLogEntry>> getLogs(String instanceId) async {
    final response = await http.get(Uri.parse('$_baseUrl/logs/$instanceId'));
    _checkStatus(response);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((j) => TaskLogEntry.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<TaskLogEntry> addLogEntry(String instanceId, String user, String text) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/logs'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'instanceId': instanceId, 'user': user, 'text': text}),
    );
    _checkStatus(response);
    return TaskLogEntry.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<TaskDomain> createDomain(String name, String description) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/domains'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'description': description}),
    );
    _checkStatus(response);
    return TaskDomain.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<TaskTemplate> createTemplate({
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    required DateTime dueDate,
    required String recurrenceFrequency,
    required int recurrenceInterval,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/templates'),
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
    return TaskTemplate.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<TaskInstance> createInstance({
    required String templateId,
    required String domainId,
    required String title,
    required String description,
    required DateTime startDate,
    required DateTime dueDate,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/instances'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'templateId': templateId,
        'domainId': domainId,
        'title': title,
        'description': description,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
      }),
    );
    _checkStatus(response);
    return TaskInstance.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> markAsDone(String instanceId) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/instances/$instanceId/done'),
      headers: {'Content-Type': 'application/json'},
    );
    _checkStatus(response);
  }

  static void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API-Fehler ${response.statusCode}: ${response.body}');
    }
  }
}
