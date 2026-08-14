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

  /// EIN Client fuer die gesamte App – [ApiService] benutzt denselben.
  ///
  /// Die Kurzformen `http.get(...)`/`http.post(...)` legen intern fuer jeden
  /// einzelnen Aufruf einen eigenen Client an und schliessen ihn danach wieder.
  /// Jede Anfrage zahlt dadurch DNS-Aufloesung, TCP-Verbindung und
  /// TLS-Handshake von vorn – am Schreibtisch kaum messbar, im Mobilfunk mit
  /// dreistelligen Laufzeiten aber rund eine Sekunde pro Anfrage.
  ///
  /// Ein durchgehend benutzter Client haelt die Verbindung offen
  /// (HTTP/1.1 Keep-Alive) und wickelt alle weiteren Anfragen darueber ab. Dass
  /// der Login hier mit drin haengt, ist Absicht: Danach steht die Verbindung
  /// bereits, und der erste Datenabgleich startet ohne Handshake.
  ///
  /// Bewusst ohne `close()` – der Client lebt so lange wie die App.
  static final http.Client client = http.Client();

  /// Reissleine fuer haengende Verbindungen. Ohne Zeitlimit wartet eine Anfrage
  /// im Funkloch, bis das Betriebssystem sie irgendwann aufgibt; die App stuende
  /// bis dahin im Ladezustand. Mit dem lokalen Zwischenspeicher im Ruecken ist
  /// ein zuegiger Abbruch klar besser – dann zeigt die App eben den zuletzt
  /// bekannten Stand statt eines Drehkreisels.
  static const Duration timeout = Duration(seconds: 20);

  static String? _token;
  static String? _email;
  static String? _displayName;

  static Future<void> init() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      _email = await _storage.read(key: _emailKey);
      _displayName = await _storage.read(key: _displayNameKey);
    } catch (_) {
      // Verschluesselte Session laesst sich nicht mehr entschluesseln
      // (z. B. BadPaddingException nach Neuinstallation / Keystore-Reset).
      // Kaputte Daten verwerfen und bereinigen -> sauberer Login statt Haenger.
      _token = null;
      _email = null;
      _displayName = null;
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }
  }

  static bool get isLoggedIn => _token != null;
  static String? get token => _token;
  static String? get email => _email;
  static String? get displayName => _displayName;

  /// Eigene Nutzer-ID, gelesen aus dem JWT.
  ///
  /// Die ID ist der einzige stabile Bezug auf den eigenen Account: Die E-Mail
  /// lässt sich im Profil ändern, wobei bestehende `OrbitMember`-Zeilen ihre
  /// alte Adresse behalten. Ein Vergleich über die E-Mail hielte einen Piloten
  /// dann faelschlich fuer einen Co-Piloten.
  ///
  /// Wird aus dem Token gelesen statt zusaetzlich gespeichert, damit auch
  /// Sitzungen funktionieren, die vor dieser Aenderung angelegt wurden.
  static String? get userId => _claimFromToken('userId');

  /// E-Mail aus dem Token – kann von [email] abweichen, wenn die Adresse in
  /// einer anderen Sitzung geaendert wurde.
  static String? get tokenEmail => _claimFromToken('email');

  static String? _claimFromToken(String claim) {
    final token = _token;
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      // base64url ohne Padding – normalize() ergaenzt die fehlenden '='.
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final value = payload[claim];
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<void> login(String email, String password) async {
    final response = await client.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    ).timeout(timeout);
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Login fehlgeschlagen');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveSession(
        body['token'] as String, body['email'] as String, body['displayName'] as String?);
  }

  static Future<void> register(String email, String password, String? displayName) async {
    final response = await client.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
      }),
    ).timeout(timeout);
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
    final response = await client.patch(
      Uri.parse('$baseUrl/auth/profile'),
      headers: authHeaders,
      body: jsonEncode(body),
    ).timeout(timeout);
    if (response.statusCode != 200) {
      final b = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(b['error'] ?? 'Aktualisierung fehlgeschlagen');
    }
    final b = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveSession(b['token'] as String, b['email'] as String, b['displayName'] as String?);
  }

  static Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final response = await client.patch(
      Uri.parse('$baseUrl/auth/password'),
      headers: authHeaders,
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    ).timeout(timeout);
    if (response.statusCode != 200) {
      final b = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(b['error'] ?? 'Passwortänderung fehlgeschlagen');
    }
  }

  static Future<void> forgotPassword(String email) async {
    final response = await client.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    ).timeout(timeout);
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
