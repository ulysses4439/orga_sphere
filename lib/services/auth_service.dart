import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _emailKey = 'user_email';
  static const _displayNameKey = 'user_display_name';
  static const baseUrl =
      'https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net';

  static String? _token;
  static String? _email;
  static String? _displayName;

  static Future<void> init() async {
    _token = await _storage.read(key: _tokenKey);
    _email = await _storage.read(key: _emailKey);
    _displayName = await _storage.read(key: _displayNameKey);
  }

  static bool get isLoggedIn => _token != null;
  static String? get token => _token;
  static String? get email => _email;
  static String? get displayName => _displayName;

  static Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<void> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Login fehlgeschlagen');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveSession(
        body['token'] as String, body['email'] as String, body['displayName'] as String?);
  }

  static Future<void> register(String email, String password, String? displayName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
      }),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Registrierung fehlgeschlagen');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveSession(
        body['token'] as String, body['email'] as String, body['displayName'] as String?);
  }

  static Future<void> _saveSession(String token, String userEmail, String? name) async {
    _token = token;
    _email = userEmail;
    _displayName = name;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _emailKey, value: userEmail);
    if (name != null) {
      await _storage.write(key: _displayNameKey, value: name);
    } else {
      await _storage.delete(key: _displayNameKey);
    }
  }

  static Future<void> updateProfile({String? displayName, String? email}) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (email != null) body['email'] = email;
    final response = await http.patch(
      Uri.parse('$baseUrl/auth/profile'),
      headers: authHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      final b = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(b['error'] ?? 'Aktualisierung fehlgeschlagen');
    }
    final b = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveSession(b['token'] as String, b['email'] as String, b['displayName'] as String?);
  }

  static Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/auth/password'),
      headers: authHeaders,
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    if (response.statusCode != 200) {
      final b = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(b['error'] ?? 'Passwortänderung fehlgeschlagen');
    }
  }

  static Future<void> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );
    if (response.statusCode != 200) {
      final b = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(b['error'] ?? 'Anfrage fehlgeschlagen');
    }
  }

  static Future<void> logout() async {
    _token = null;
    _email = null;
    _displayName = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _displayNameKey);
  }
}
