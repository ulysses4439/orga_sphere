import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';
import '../services/auth_service.dart';

/// Initialen des angemeldeten Nutzers (für Avatare).
String userInitials() {
  final name = AuthService.displayName;
  if (name != null && name.isNotEmpty) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
  return (AuthService.email ?? '?')[0].toUpperCase();
}

/// Gemeinsames Konto-Menü (Einstellungen / Ausloggen).
///
/// [child] ist der sichtbare Auslöser – auf dem Desktop die volle Zeile mit
/// Name/E-Mail in der Sidebar, auf dem Handy ein kompakter Avatar in der AppBar.
class UserAccountMenu extends StatelessWidget {
  final VoidCallback? onLogout;
  final Widget child;
  final Offset offset;

  const UserAccountMenu({
    super.key,
    this.onLogout,
    required this.child,
    this.offset = const Offset(8, 0),
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: offset,
      color: const Color(0xFF1C1C2E),
      onSelected: (value) async {
        if (value == 'settings') {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsScreen(onLogout: onLogout ?? () {}),
            ),
          );
        } else if (value == 'logout') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Abmelden'),
              content: const Text('Möchtest du dich wirklich abmelden?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await AuthService.logout();
            onLogout?.call();
          }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'settings',
          child: Row(children: [
            Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
            SizedBox(width: 12),
            Text('Einstellungen', style: TextStyle(color: Colors.white)),
          ]),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: Row(children: [
            Icon(Icons.logout, color: Colors.white70, size: 20),
            SizedBox(width: 12),
            Text('Ausloggen', style: TextStyle(color: Colors.white)),
          ]),
        ),
      ],
      child: child,
    );
  }
}
