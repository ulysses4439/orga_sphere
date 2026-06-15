import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// Einladedialog für einen Co-Piloten. Gibt `true` zurück, wenn eine Einladung
/// versendet bzw. ein bestehender Nutzer direkt hinzugefügt wurde.
Future<bool> showInviteCoPilotDialog(
    BuildContext context, TaskDomain domain) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Co-Pilot einladen – ${domain.name}'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'E-Mail-Adresse',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_add_outlined),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Einladen'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (result == null || result.isEmpty) return false;
  try {
    final status = await ApiService.inviteCoPilot(domain.id, result);
    if (context.mounted) {
      final msg = status == 'invited'
          ? 'Einladung an $result gesendet'
          : '$result wurde als Co-Pilot hinzugefügt';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
    return false;
  }
}

/// Teilnehmerleiste eines Orbits (Pilot + Co-Piloten als farbige Avatare).
/// Ein Pilot kann über die Avatare Co-Piloten verwalten und neue einladen.
class OrbitMembersBar extends StatefulWidget {
  final String orbitId;
  final Future<void> Function() onInvite;

  const OrbitMembersBar({
    super.key,
    required this.orbitId,
    required this.onInvite,
  });

  @override
  State<OrbitMembersBar> createState() => _OrbitMembersBarState();
}

class _OrbitMembersBarState extends State<OrbitMembersBar> {
  late Future<List<OrbitMember>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getOrbitMembers(widget.orbitId);
  }

  void _reload() {
    setState(() {
      _future = ApiService.getOrbitMembers(widget.orbitId);
    });
  }

  bool _isPilot(List<OrbitMember> members) =>
      members.any((m) => m.email == AuthService.email && m.isPilot);

  Future<void> _manageMember(OrbitMember member) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(member.email),
        children: [
          if (!member.isSuspended)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'suspend'),
              child: const Row(children: [
                Icon(Icons.block, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Text('Sperren'),
              ]),
            ),
          if (member.isSuspended)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'reactivate'),
              child: const Row(children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text('Wieder aktivieren'),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Row(children: [
              Icon(Icons.person_remove_outlined, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Text('Entfernen', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'suspend') {
        await ApiService.suspendCoPilot(widget.orbitId, member.id);
      } else if (action == 'reactivate') {
        await ApiService.reactivateCoPilot(widget.orbitId, member.id);
      } else if (action == 'remove') {
        await ApiService.removeCoPilot(widget.orbitId, member.id);
      }
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrbitMember>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 36,
            child: Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final members = snapshot.data ?? [];
        final isPilot = _isPilot(members);

        return Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.group_outlined, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: members.map((m) {
                      final initials = (m.displayName?.isNotEmpty == true
                              ? m.displayName!
                              : m.email)
                          .substring(0, 1)
                          .toUpperCase();
                      Color bg = m.isPilot
                          ? AppColors.teal
                          : m.isSuspended
                              ? Colors.red.shade800
                              : m.isPending
                                  ? Colors.orange.shade700
                                  : Colors.blueGrey.shade600;
                      final tooltipName = m.displayName?.isNotEmpty == true
                          ? '${m.displayName}\n${m.email}'
                          : m.email;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: '$tooltipName'
                              '${m.isPilot ? '\nPilot' : '\nCo-Pilot'}'
                              '${m.isSuspended ? ' – gesperrt' : ''}'
                              '${m.isPending ? ' – ausstehend' : ''}',
                          child: GestureDetector(
                            onTap: isPilot && !m.isPilot
                                ? () => _manageMember(m)
                                : null,
                            child: CircleAvatar(
                              radius: 13,
                              backgroundColor: bg,
                              child: Text(
                                initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (isPilot)
                IconButton(
                  icon: const Icon(Icons.person_add_outlined,
                      color: Colors.white54, size: 18),
                  tooltip: 'Co-Pilot einladen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    await widget.onInvite();
                    _reload();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
