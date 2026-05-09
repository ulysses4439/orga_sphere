import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const SettingsScreen({super.key, required this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          const _SectionHeader('Profil'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Name ändern'),
            subtitle: Text(AuthService.displayName ?? '(kein Name gesetzt)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangeNameDialog(context),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('E-Mail ändern'),
            subtitle: Text(AuthService.email ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangeEmailDialog(context),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Sicherheit'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Passwort ändern'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangePasswordDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeNameDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: AuthService.displayName ?? '');
    final formKey = GlobalKey<FormState>();
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Name ändern'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Vor- und Nachname',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name erforderlich' : null,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Colors.red[700], fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final nav = Navigator.of(ctx);
                try {
                  await AuthService.updateProfile(displayName: ctrl.text.trim());
                  nav.pop();
                  _rebuild();
                } catch (e) {
                  setSt(() =>
                      error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showChangeEmailDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: AuthService.email ?? '');
    final formKey = GlobalKey<FormState>();
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('E-Mail ändern'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Neue E-Mail-Adresse',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofocus: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'E-Mail erforderlich';
                    if (!v.contains('@')) return 'Ungültige E-Mail-Adresse';
                    return null;
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Colors.red[700], fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final nav = Navigator.of(ctx);
                try {
                  await AuthService.updateProfile(email: ctrl.text.trim());
                  nav.pop();
                  _rebuild();
                } catch (e) {
                  setSt(() =>
                      error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Passwort ändern'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentCtrl,
                  decoration: InputDecoration(
                    labelText: 'Aktuelles Passwort',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                  obscureText: obscure,
                  autofocus: true,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Erforderlich' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Neues Passwort',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: obscure,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Erforderlich';
                    if (v.length < 8) return 'Mindestens 8 Zeichen';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Neues Passwort wiederholen',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: obscure,
                  validator: (v) => v != newCtrl.text
                      ? 'Passwörter stimmen nicht überein'
                      : null,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Colors.red[700], fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final nav = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await AuthService.changePassword(
                      currentCtrl.text, newCtrl.text);
                  nav.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Passwort erfolgreich geändert')),
                  );
                } catch (e) {
                  setSt(() =>
                      error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Ändern'),
            ),
          ],
        ),
      ),
    );
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
