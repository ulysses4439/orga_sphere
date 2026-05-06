import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
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

  List<Task> _filtered(List<Task> tasks) {
    if (widget.orbitId == null) return tasks;
    return tasks.where((t) => t.domainId == widget.orbitId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.orbitName),
          bottom: const TabBar(
            tabs: [Tab(text: 'Aktiv'), Tab(text: 'Archiv')],
          ),
        ),
        body: TabBarView(
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
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await Navigator.of(context).pushNamed('/create-task');
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
            Icon(Icons.task_alt, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: Theme.of(context).textTheme.titleLarge),
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
          domainName: domain?.name ?? 'Allgemein',
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
