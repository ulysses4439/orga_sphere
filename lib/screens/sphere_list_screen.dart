import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';
import '../widgets/notification_bell.dart';
import '../widgets/orbit_members_bar.dart';
import '../widgets/simple_list_widgets.dart';
import '../widgets/task_list_item.dart';

/// Mobile-only: zeigt die Sphere-Liste eines bestimmten Orbits.
/// Wird aufgerufen wenn der Nutzer auf der Orbit-Übersicht einen Orbit antippt.
class SphereListScreen extends StatefulWidget {
  final String? orbitId;
  final String orbitName;

  const SphereListScreen({
    super.key,
    this.orbitId,
    required this.orbitName,
  });

  @override
  State<SphereListScreen> createState() => _SphereListScreenState();
}

class _SphereListScreenState extends State<SphereListScreen> {
  final TaskService _taskService = TaskService();

  @override
  void initState() {
    super.initState();
    // Live-Sync: auf Änderungen anderer (Co-)Piloten reagieren, die der
    // Hintergrund-Poll (alle 30s) in den TaskService lädt.
    _taskService.addListener(_onServiceChanged);
    // Beim Öffnen sofort den aktuellen Stand holen, statt bis zum
    // nächsten Poll-Intervall zu warten.
    _taskService.refresh();
  }

  @override
  void dispose() {
    _taskService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  List<Task> _filtered(List<Task> tasks) {
    if (widget.orbitId == null) return tasks;
    return tasks.where((t) => t.domainId == widget.orbitId).toList();
  }

  /// Orbit im Einkaufslisten-Modus? Steuert die abgespeckte Darstellung.
  bool get _isSimpleList {
    final id = widget.orbitId;
    if (id == null) return false;
    return _taskService.getDomainById(id)?.isShoppingList ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final orbit = widget.orbitId != null
        ? _taskService.getDomainById(widget.orbitId!)
        : null;
    final description = orbit?.description ?? '';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.orbitName),
          actions: const [
            NotificationBell(),
            SizedBox(width: 8),
          ],
        ),
        // Dunkler Hintergrund wie in der Desktop-Ansicht eines Orbits;
        // die Orbit-Beschreibung steht oben unterhalb des Titels.
        body: Theme(
          data: Theme.of(context).copyWith(
            tabBarTheme: const TabBarThemeData(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: AppColors.teal,
              dividerColor: Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Teilnehmer (Pilot + Co-Piloten) direkt unter dem Orbit-Titel –
              // analog zur Desktop-Ansicht. Pilot kann hier Co-Piloten einladen.
              if (widget.orbitId != null && orbit != null)
                OrbitMembersBar(
                  key: ValueKey('members_${widget.orbitId}'),
                  orbitId: widget.orbitId!,
                  onInvite: () => showInviteCoPilotDialog(context, orbit),
                ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              // Schnelleingabe: tippen, Enter, nächste Position – ohne Dialog
              // und ohne Seitenwechsel. Nur im Einkaufslisten-Modus.
              if (_isSimpleList && widget.orbitId != null)
                SimpleListQuickAdd(
                  orbitId: widget.orbitId!,
                  onAdded: () => setState(() {}),
                ),
              ColoredBox(
                color: const Color(0xFF2D2D2D),
                child: TabBar(
                  // „Archiv" wäre in einer Einkaufsliste irreführend – die
                  // erledigten Positionen verschwinden nach 24 Stunden.
                  tabs: _isSimpleList
                      ? const [Tab(text: 'Offen'), Tab(text: 'Erledigt')]
                      : const [Tab(text: 'Aktiv'), Tab(text: 'Archiv')],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildList(
                      _filtered(_taskService.getActiveTasks()),
                      'Keine aktiven Spheres vorhanden',
                    ),
                    _buildList(
                      _filtered(_taskService.getArchivedTasks()),
                      'Keine archivierten Spheres vorhanden',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Im Listen-Modus überflüssig: neue Positionen entstehen über das
        // Eingabefeld oben, ein zusätzliches Formular gibt es dort nicht.
        floatingActionButton: _isSimpleList
            ? null
            : FloatingActionButton(
                onPressed: () async {
                  await Navigator.of(context)
                      .pushNamed('/create-task', arguments: widget.orbitId);
                  setState(() {});
                },
                child: const Icon(Icons.add),
              ),
      ),
    );
  }

  Widget _buildList(List<Task> tasks, String emptyMessage) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final isSimpleList = _isSimpleList;

    return ListView.builder(
      // Reserve unten: Systemleiste (Samsung-Navigationstasten) plus der
      // schwebende Plus-Button – sonst liegen beide auf der letzten Sphere.
      // Im Listen-Modus gibt es keinen Plus-Button, dort genügt weniger Luft.
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        MediaQuery.of(context).viewPadding.bottom + (isSimpleList ? 16 : 88),
      ),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final domain = _taskService.getDomainById(task.domainId);
        return TaskListItem(
          task: task,
          domainColor: domain?.color,
          simpleList: isSimpleList,
          onTap: () async {
            // Listenpositionen brauchen keine Detailseite – ein kleiner
            // Dialog zum Umbenennen und Löschen genügt.
            if (isSimpleList) {
              await showSimpleListItemDialog(context, task);
            } else {
              await Navigator.of(context)
                  .pushNamed('/task-detail', arguments: task.id);
            }
            if (mounted) setState(() {});
          },
        );
      },
    );
  }
}
