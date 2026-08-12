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
    await ApiService.inviteCoPilot(domain.id, result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Einladung an $result gesendet. Der Avatar bleibt '
              'grau, bis sie angenommen wurde.'),
        ),
      );
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

  /// Der eigene Eintrag in der Teilnehmerliste – oder `null`, wenn er sich
  /// nicht zuordnen laesst. Daraus ergibt sich die eigene Rolle im Orbit.
  ///
  /// Primaer ueber die Nutzer-ID, die ist stabil. Die E-Mail dient nur als
  /// Rueckfallebene fuer Eintraege ohne userId – etwa eingeladene Personen, die
  /// ihr Konto noch nicht angelegt haben. Dann zeichenunabhaengig, damit
  /// Gross-/Kleinschreibung nichts kaputt macht. Ein reiner E-Mail-Vergleich
  /// waere unzuverlaessig: Die Adresse laesst sich im Profil aendern.
  OrbitMember? _findMe(List<OrbitMember> members) {
    final myId = AuthService.userId;
    if (myId != null) {
      for (final m in members) {
        if (m.userId == myId) return m;
      }
    }
    final myMails = <String>{
      if (AuthService.email != null) AuthService.email!.trim().toLowerCase(),
      if (AuthService.tokenEmail != null)
        AuthService.tokenEmail!.trim().toLowerCase(),
    };
    if (myMails.isEmpty) return null;
    for (final m in members) {
      if (myMails.contains(m.email.trim().toLowerCase())) return m;
    }
    return null;
  }

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

  /// Infodialog zu einem Teilnehmer. Fuer Co-Piloten der einzige Weg an diese
  /// Angaben: Verwalten duerfen sie nichts, und auf dem Handy gibt es keinen
  /// Mauszeiger, der einen Tooltip auslösen koennte.
  Future<void> _showMemberInfo(OrbitMember member) async {
    final status = member.isSuspended
        ? 'gesperrt'
        : member.isPending
            ? 'eingeladen – noch nicht angenommen'
            : 'aktiv';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(member.displayLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.email),
            const SizedBox(height: 8),
            Text(member.isPilot ? 'Pilot dieses Orbits' : 'Co-Pilot'),
            Text('Status: $status'),
            if (member.isPilot) ...[
              const SizedBox(height: 8),
              const Text(
                'Umbenennen, Löschen und Einladungen laufen über den Piloten.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  /// Rechte Seite der Leiste fuer Co-Piloten: die eigene Rolle UND der Name des
  /// Piloten. Ohne den Namen weiss ein Co-Pilot zwar, dass er nichts aendern
  /// darf, aber nicht, wen er dafuer ansprechen muss.
  Widget _buildCoPilotHint(List<OrbitMember> members) {
    OrbitMember? pilot;
    for (final m in members) {
      if (m.isPilot) {
        pilot = m;
        break;
      }
    }
    final pilotLabel = pilot?.displayLabel;
    return Tooltip(
      message: 'Du bist Co-Pilot dieses Orbits.\n'
          '${pilot == null ? 'Nur der Pilot kann ihn verwalten.' : 'Verwaltet wird er von ${pilot.displayLabel} (${pilot.email}).'}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: GestureDetector(
          onTap: pilot == null ? null : () => _showMemberInfo(pilot!),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.badge_outlined, color: Colors.white38, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  pilotLabel == null ? 'Co-Pilot' : 'Pilot: $pilotLabel',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        final me = _findMe(members);
        final isPilot = me?.isPilot ?? false;

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
                      final tooltipName = m.displayName?.isNotEmpty == true
                          ? '${m.displayName}\n${m.email}'
                          : m.email;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: '$tooltipName'
                              '${m.isPilot ? '\nPilot' : '\nCo-Pilot'}'
                              '${m.isSuspended ? ' – gesperrt' : ''}'
                              '${m.isPending ? '\nEinladung noch nicht angenommen' : ''}',
                          child: GestureDetector(
                            // Der Pilot verwaltet per Tippen, alle anderen
                            // bekommen die Angaben zum Teilnehmer zu sehen.
                            onTap: isPilot && !m.isPilot
                                ? () => _manageMember(m)
                                : () => _showMemberInfo(m),
                            child: _MemberAvatar(member: m),
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
                )
              // Statt einer wortlosen Luecke: die eigene Rolle benennen und
              // sagen, wer der Pilot ist. Sonst ist am fehlenden Einladen-Knopf
              // weder zu erkennen, ob man keine Rechte hat oder ob etwas nicht
              // funktioniert, noch an wen man sich wenden muss.
              else if (me != null)
                _buildCoPilotHint(members),
            ],
          ),
        );
      },
    );
  }
}

/// Avatar eines Orbit-Teilnehmers.
///
/// Der Zustand einer Einladung muss man sehen koennen: Wer eingeladen ist, die
/// Einladung aber noch nicht angenommen hat, erscheint NICHT als vollwertiger
/// Teilnehmer. Statt gefuellter Farbe bekommt er auf dem schwarzen Grund der
/// Leiste nur einen grauen Ring mit grauer Schrift – sichtbar vorhanden, aber
/// erkennbar noch nicht dabei. Die kleine Uhr macht den Unterschied auch
/// unabhaengig von Farbe deutlich.
class _MemberAvatar extends StatelessWidget {
  final OrbitMember member;

  const _MemberAvatar({required this.member});

  static const double _size = 26;

  @override
  Widget build(BuildContext context) {
    final initials = (member.displayName?.isNotEmpty == true
            ? member.displayName!
            : member.email)
        .substring(0, 1)
        .toUpperCase();

    if (member.isPending) {
      return SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          children: [
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Kein Fuellton: Der schwarze Hintergrund der Leiste bleibt
                // stehen, der Ring setzt die Kontur.
                border: Border.all(color: Colors.white38, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.schedule,
                    size: 9, color: Colors.white38),
              ),
            ),
          ],
        ),
      );
    }

    final Color background = member.isPilot
        ? AppColors.teal
        : member.isSuspended
            ? Colors.red.shade800
            : Colors.blueGrey.shade600;

    return CircleAvatar(
      radius: _size / 2,
      backgroundColor: background,
      child: Text(
        initials,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
