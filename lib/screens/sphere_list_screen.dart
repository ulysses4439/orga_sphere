import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';
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
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              const ColoredBox(
                color: Color(0xFF2D2D2D),
                child: TabBar(
                  tabs: [Tab(text: 'Aktiv'), Tab(text: 'Archiv')],
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
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await Navigator.of(context).pushNamed('/create-task', arguments: widget.orbitId);
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

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final domain = _taskService.getDomainById(task.domainId);
        return TaskListItem(
          task: task,
          domainColor: domain?.color,
          onTap: () async {
            await Navigator.of(context).pushNamed('/task-detail', arguments: task.id);
            setState(() {});
          },
        );
      },
    );
  }
}
