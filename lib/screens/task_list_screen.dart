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
  String? _selectedDomainId;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _taskService.ready.then((_) => setState(() => _isReady = true));
  }

  List<Task> _filtered(List<Task> tasks) {
    if (_selectedDomainId == null) return tasks;
    return tasks.where((t) => t.domainId == _selectedDomainId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          centerTitle: true,
          title: Image.asset(
            'assets/images/logo_full.png',
            height: 52,
            fit: BoxFit.contain,
          ),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              (_isReady ? 72.0 : 0.0) + kTextTabBarHeight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isReady) _buildFilterBar(),
                const TabBar(
                  tabs: [
                    Tab(text: 'Aktiv'),
                    Tab(text: 'Archiv'),
                  ],
                ),
              ],
            ),
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
                  _filtered(_taskService.getActiveTasks()),
                  'Keine aktiven Spheres vorhanden',
                ),
                _buildTaskList(
                  _filtered(_taskService.getArchivedTasks()),
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

  Widget _buildFilterBar() {
    final domains = _taskService.getDomains();
    final foreground = Theme.of(context).appBarTheme.foregroundColor;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foreground?.withValues(alpha: 0.8),
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        );
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Orbits', style: labelStyle),
            const SizedBox(width: 10),
            ChoiceChip(
              label: const Text('Alle'),
              selected: _selectedDomainId == null,
              onSelected: (_) => setState(() => _selectedDomainId = null),
              visualDensity: VisualDensity.compact,
            ),
            ...domains.map((d) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                label: Text(d.name),
                selected: _selectedDomainId == d.id,
                selectedColor: d.color,
                onSelected: (_) => setState(
                  () => _selectedDomainId =
                      _selectedDomainId == d.id ? null : d.id,
                ),
                visualDensity: VisualDensity.compact,
              ),
            )),
          ],
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
              title: const Text('Orbit anlegen'),
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

        final domain = _taskService.getDomainById(task.domainId);
        return _TaskListItem(
          task: task,
          domainName: domainName,
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

class _TaskListItem extends StatelessWidget {
  final Task task;
  final String domainName;
  final Color? domainColor;
  final VoidCallback onTap;

  const _TaskListItem({
    required this.task,
    required this.domainName,
    this.domainColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dueDate = task.dueDate;
    final now = DateTime.now();
    final daysUntilDue = dueDate.difference(now).inDays;

    // Traffic light: urgency based on due date
    final Color urgencyColor;
    if (task.status == TaskStatus.done) {
      urgencyColor = Colors.grey[400]!;
    } else if (dueDate.isBefore(now)) {
      urgencyColor = Colors.red;
    } else if (daysUntilDue <= 14) {
      urgencyColor = Colors.amber;
    } else {
      urgencyColor = Colors.green;
    }

    // Status icon
    final IconData statusIcon;
    final Color statusColor;
    switch (task.status) {
      case TaskStatus.open:
        statusIcon = Icons.radio_button_unchecked;
        statusColor = Colors.grey[600]!;
      case TaskStatus.inProgress:
        statusIcon = Icons.sync;
        statusColor = AppColors.teal;
      case TaskStatus.done:
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      color: domainColor,
      child: ListTile(
        onTap: onTap,
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, color: urgencyColor, size: 14),
            const SizedBox(height: 6),
            Icon(statusIcon, color: statusColor, size: 22),
          ],
        ),
        title: Text(task.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Orbit: $domainName', style: Theme.of(context).textTheme.bodySmall),
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
