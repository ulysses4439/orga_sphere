import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TaskService _taskService = TaskService();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('OrgaSphere'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Aktiv'),
              Tab(text: 'Archiv'),
            ],
          ),
        ),
        body: FutureBuilder<void>(
          future: _taskService.ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Verbindungsfehler',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            return TabBarView(
              children: [
                _buildTaskList(
                  _taskService.getActiveTasks(),
                  'Keine aktiven Spheres vorhanden',
                ),
                _buildTaskList(
                  _taskService.getArchivedTasks(),
                  'Keine archivierten Spheres vorhanden',
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showCreateMenu,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showCreateMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Bereich anlegen'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Navigator.of(context).pushNamed('/create-domain');
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Sphere anlegen'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Navigator.of(context).pushNamed('/create-task');
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(List<Task> tasks, String emptyMessage) {
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
        final domainName = _taskService.getDomainById(task.domainId)?.name ?? 'Allgemein';

        return _TaskListItem(
          task: task,
          domainName: domainName,
          onTap: () async {
            await Navigator.of(context).pushNamed('/task-detail', arguments: task.id);
            setState(() {});
          },
        );
      },
    );
  }
}

class _TaskListItem extends StatelessWidget {
  final Task task;
  final String domainName;
  final VoidCallback onTap;

  const _TaskListItem({
    required this.task,
    required this.domainName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dueDate = task.dueDate;
    final isOverdue = task.isOverdue;
    final isUpcoming = task.isUpcoming;

    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.radio_button_unchecked;

    if (task.status == TaskStatus.done) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
    } else if (isUpcoming) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning_amber;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      child: ListTile(
        onTap: onTap,
        leading: Icon(statusIcon, color: statusColor),
        title: Text(task.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Bereich: $domainName', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Fällig: ${dueDate.day}. ${_monthName(dueDate.month)} ${dueDate.year}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              task.recurrence.germanLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(
                    task.status.germanLabelShort,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: _statusBackgroundColor(task.status),
                  labelStyle: const TextStyle(color: Colors.white),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                const SizedBox(width: 8),
                if (task.logEntries.isNotEmpty)
                  Text(
                    '${task.logEntries.length} Einträge',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    return months[month - 1];
  }

  Color _statusBackgroundColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.open:       return Colors.grey;
      case TaskStatus.inProgress: return AppColors.teal;
      case TaskStatus.done:       return Colors.green;
    }
  }
}
