import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';

/// Main screen displaying all task instances
/// Tasks are sorted by relevance (overdue first, then upcoming, then by due date)
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TaskService _taskService = TaskService();

  @override
  Widget build(BuildContext context) {
    final activeTasks = _taskService.getActiveInstances();
    final archivedTasks = _taskService.getArchivedInstances();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('OrgaSphere'),
          elevation: 0,
          backgroundColor: Colors.deepPurple,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Aktiv'),
              Tab(text: 'Archiv'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTaskList(activeTasks, 'Keine aktiven Aufgaben vorhanden'),
            _buildTaskList(archivedTasks, 'Keine archivierten Aufgaben vorhanden'),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Neue Aufgabe hinzufügen (kommt bald)')),
            );
          },
          backgroundColor: Colors.deepPurple,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildTaskList(List<TaskInstance> tasks, String emptyMessage) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.task_alt,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.titleLarge,
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
        final template = _taskService.getTemplateById(task.templateId);
        final recurrenceLabel = template?.recurrence.germanLabel ?? 'Unbekannt';
        final domainName = _taskService.getDomainById(task.domainId)?.name ?? 'Allgemein';

        return _TaskListItem(
          task: task,
          domainName: domainName,
          recurrenceLabel: recurrenceLabel,
          onTap: () {
            Navigator.of(context).pushNamed('/task-detail', arguments: task.id);
          },
        );
      },
    );
  }
}

/// Individual task list item widget
class _TaskListItem extends StatelessWidget {
  final TaskInstance task;
  final String domainName;
  final String recurrenceLabel;
  final VoidCallback onTap;

  const _TaskListItem({
    required this.task,
    required this.domainName,
    required this.recurrenceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dueDate = task.dueDate;
    final isOverdue = task.isOverdue;
    final isUpcoming = task.isUpcoming;

    // Determine the color accent based on status
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
            Text(
              'Bereich: $domainName',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Jahr: ${task.year} | Fällig: ${dueDate.day}. ${_monthName(dueDate.month)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              recurrenceLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
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

  /// Get German month name
  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mär',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez'
    ];
    return months[month - 1];
  }

  /// Get background color for status chip
  Color _statusBackgroundColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.open:
        return Colors.grey;
      case TaskStatus.inProgress:
        return Colors.blue;
      case TaskStatus.done:
        return Colors.green;
    }
  }
}
