import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _password2Ctrl = TextEditingController();

  bool _isRegister = false;
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  Future<void> _showForgotPassword() async {
    final emailCtrl = TextEditingController();
    String? dialogError;
    bool sent = false;
    bool loading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Passwort vergessen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gib deine E-Mail-Adresse ein. Wir schicken dir einen Link zum Zurücksetzen deines Passworts.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (!sent) ...[
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofocus: true,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ] else
                const Text(
                  'E-Mail verschickt! Prüfe dein Postfach und klicke auf den Link.',
                  style: TextStyle(color: Colors.green, fontSize: 13),
                ),
            ],
          ),
          actions: sent
              ? [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Schließen'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: loading
                        ? null
                        : () async {
                            final mail = emailCtrl.text.trim();
                            if (!mail.contains('@')) {
                              setDialogState(() => dialogError = 'Bitte gib eine gültige E-Mail ein.');
                              return;
                            }
                            setDialogState(() { loading = true; dialogError = null; });
                            try {
                              await AuthService.forgotPassword(mail);
                              setDialogState(() { sent = true; loading = false; });
                            } catch (e) {
                              setDialogState(() {
                                loading = false;
                                dialogError = e.toString().replaceFirst('Exception: ', '');
                              });
                            }
                          },
                    child: loading
                        ? const SizedBox(
                            height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Link senden'),
                  ),
                ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _password2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (_isRegister) {
        await AuthService.register(
            _emailCtrl.text.trim(), _passwordCtrl.text, _nameCtrl.text.trim());
      } else {
        await AuthService.login(_emailCtrl.text.trim(), _passwordCtrl.text);
      }
      widget.onSuccess();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo_full.png', height: 80),
                const SizedBox(height: 32),
                Text(
                  _isRegister ? 'Konto erstellen' : 'Anmelden',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (_isRegister) ...[
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Vor- und Nachname',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Name erforderlich';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'E-Mail',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'E-Mail erforderlich';
                          if (!v.contains('@')) return 'Ungültige E-Mail-Adresse';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        decoration: InputDecoration(
                          labelText: 'Passwort',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        obscureText: _obscure,
                        textInputAction: _isRegister
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: _isRegister ? null : (_) => _submit(),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Passwort erforderlich';
                          if (_isRegister && v.length < 8) {
                            return 'Mindestens 8 Zeichen';
                          }
                          return null;
                        },
                      ),
                      if (_isRegister) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password2Ctrl,
                          decoration: const InputDecoration(
                            labelText: 'Passwort wiederholen',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) {
                            if (v != _passwordCtrl.text) {
                              return 'Passwörter stimmen nicht überein';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            border: Border.all(color: Colors.red.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red[800]),
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(_isRegister ? 'Registrieren' : 'Anmelden'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_isRegister)
                        TextButton(
                          onPressed: _loading ? null : _showForgotPassword,
                          child: const Text(
                            'Passwort vergessen?',
                            style: TextStyle(color: AppColors.teal),
                          ),
                        ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() {
                                  _isRegister = !_isRegister;
                                  _error = null;
                                  _nameCtrl.clear();
                                  _formKey.currentState?.reset();
                                }),
                        child: Text(
                          _isRegister
                              ? 'Bereits ein Konto? Anmelden'
                              : 'Noch kein Konto? Jetzt registrieren',
                          style: const TextStyle(color: AppColors.teal),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
