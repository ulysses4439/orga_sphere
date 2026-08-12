import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/notification_center.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';

/// Glocken-Icon mit Ungelesen-Badge für die AppBar (Desktop & Mobile).
/// Tippen öffnet die Liste der letzten Team-Aktivitäten und markiert sie gelesen.
class NotificationBell extends StatefulWidget {
  final Color? iconColor;
  const NotificationBell({super.key, this.iconColor});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final NotificationCenter _center = NotificationCenter();

  @override
  void initState() {
    super.initState();
    _center.addListener(_onChanged);
  }

  @override
  void dispose() {
    _center.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _NotificationList(),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 64, right: 12),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 380,
                height: 480,
                child: _NotificationList(),
              ),
            ),
          ),
        ),
      );
    }
    await _center.markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final count = _center.unreadCount;
    return IconButton(
      tooltip: 'Benachrichtigungen',
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            count > 0 ? Icons.notifications_active : Icons.notifications_none,
            color: widget.iconColor,
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatefulWidget {
  const _NotificationList();

  @override
  State<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<_NotificationList> {
  final NotificationCenter _center = NotificationCenter();

  @override
  void initState() {
    super.initState();
    // Ohne Listener bliebe eine ausgeblendete Meldung stehen, bis der Dialog
    // geschlossen und neu geöffnet wird.
    _center.addListener(_onChanged);
  }

  @override
  void dispose() {
    _center.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _dismiss(OrbitEvent event) async {
    try {
      await _center.dismiss(event);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
      return false;
    }
  }

  Future<void> _dismissAll() async {
    try {
      await _center.dismissAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'sphere_created':
        return Icons.add_circle_outline;
      case 'sphere_landed':
        return Icons.check_circle_outline;
      case 'sphere_assigned':
        return Icons.person_outline;
      case 'log_added':
        return Icons.edit_note;
      case 'reminder':
        return Icons.alarm;
      case 'member_joined':
        return Icons.group_add_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Color _colorFor(String type) =>
      type == 'reminder' ? Colors.red : AppColors.teal;

  @override
  Widget build(BuildContext context) {
    final events = _center.events;
    // Auf dem Handy wird gewischt, auf dem Desktop gibt es ein kleines X –
    // Wischgesten sind mit der Maus unüblich.
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Team-Aktivitäten',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (events.isNotEmpty)
                TextButton(
                  onPressed: _dismissAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Alle ausblenden'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('Noch keine Aktivitäten')),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = events[i];
                    final tile = ListTile(
                      leading: Icon(_iconFor(e.type), color: _colorFor(e.type)),
                      title: Text(e.body),
                      subtitle: Text(
                        formatDateTime(e.createdAt.toLocal()),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      trailing: isMobile
                          ? null
                          : IconButton(
                              icon: Icon(Icons.close,
                                  size: 18, color: Colors.grey[600]),
                              tooltip: 'Meldung ausblenden',
                              onPressed: () => _dismiss(e),
                            ),
                      onTap: e.sphereId == null
                          ? null
                          : () {
                              Navigator.pop(context);
                              Navigator.of(context).pushNamed(
                                '/task-detail',
                                arguments: e.sphereId,
                              );
                            },
                    );

                    if (!isMobile) return tile;

                    return Dismissible(
                      key: ValueKey(e.id),
                      direction: DismissDirection.startToEnd,
                      // Server zuerst fragen: Schlägt es fehl, bleibt der
                      // Eintrag stehen, statt nur optisch zu verschwinden.
                      confirmDismiss: (_) => _dismiss(e),
                      background: Container(
                        color: Colors.red.shade700,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        child: const Icon(Icons.visibility_off_outlined,
                            color: Colors.white),
                      ),
                      child: tile,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
