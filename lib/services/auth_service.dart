import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _emailKey = 'user_email';
  static const baseUrl =
      'https://orga-sphere-api-dev-f5a0dtenanhefwb2.westeurope-01.azurewebsites.net';

  static String? _token;
  static String? _email;

  static Future<void> init() async {
    _token = await _storage.read(key: _tokenKey);
    _email = await _storage.read(key: _emailKey);
  }

  static bool get isLoggedIn => _token != null;
  static String? get token => _token;
  static String? get email => _email;

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
    await _saveSession(body['token'] as String, body['email'] as String);
  }

  static Future<void> register(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Registrierung fehlgeschlagen');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveSession(body['token'] as String, body['email'] as String);
  }

  static Future<void> _saveSession(String token, String userEmail) async {
    _token = token;
    _email = userEmail;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _emailKey, value: userEmail);
  }

  static Future<void> logout() async {
    _token = null;
    _email = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _emailKey);
  }
}
