import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';

class TaskDetailScreen extends StatefulWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final TaskService _taskService = TaskService();
  late Task? _task;
  final _logTextController = TextEditingController();
  final _userNameController = TextEditingController(text: 'Steven');
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _task = _taskService.getTaskById(widget.taskId);
  }

  @override
  void dispose() {
    _logTextController.dispose();
    _userNameController.dispose();
    super.dispose();
  }

  Future<void> _addLogEntry() async {
    if (_logTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte geben Sie einen Text ein')),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _taskService.addLogEntry(
        widget.taskId,
        _userNameController.text.trim(),
        _logTextController.text.trim(),
      );
      _logTextController.clear();
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag hinzugefügt')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  void _markAsDone() {
    final task = _task;
    if (task == null) return;

    final confirmationText = task.isRecurring
        ? 'Sphere wird als erledigt markiert. Die nächste Sphere wird automatisch angelegt.'
        : 'Die Sphere wird als erledigt markiert und ins Archiv verschoben.';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sphere erledigt?'),
        content: Text(confirmationText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isBusy = true);
              try {
                await _taskService.markAsDone(widget.taskId);
                if (!mounted) return;
                setState(() {
                  _task = _taskService.getTaskById(widget.taskId);
                  _isBusy = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sphere erledigt')),
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler: $e')),
                );
              }
            },
            child: const Text('Erledigt'),
          ),
        ],
      ),
    );
  }

  void _reopenTask() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abschluss rückgängig machen?'),
        content: const Text(
          'Die Sphere wird wieder als aktiv markiert. Eine bereits angelegte Folge-Sphere bleibt erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isBusy = true);
              try {
                await _taskService.reopenTask(widget.taskId);
                if (!mounted) return;
                setState(() {
                  _task = _taskService.getTaskById(widget.taskId);
                  _isBusy = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sphere wieder geöffnet')),
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler: $e')),
                );
              }
            },
            child: const Text('Ja, wieder öffnen'),
          ),
        ],
      ),
    );
  }

  void _deleteTask() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sphere löschen?'),
        content: const Text(
          'Diese Sphere und alle zugehörigen Einträge werden dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isBusy = true);
              try {
                await _taskService.deleteTask(widget.taskId);
                if (!mounted) return;
                Navigator.of(context).pop();
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler: $e')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sphere nicht gefunden')),
        body: const Center(child: Text('Diese Sphere konnte nicht gefunden werden')),
      );
    }

    final task = _task!;
    final dueDate = task.dueDate;
    final domain = _taskService.getDomainById(task.domainId);
    final isDone = task.status == TaskStatus.done;

    return PopScope(
      canPop: !_isBusy,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Sphere'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Sphere löschen',
            onPressed: _isBusy ? null : _deleteTask,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppColors.navyPale,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              task.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          Chip(
                            label: Text(
                              task.status.germanLabel,
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: _statusColor(task.status),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Jahr: ${task.year}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection('Beschreibung', task.description),
                      const SizedBox(height: 16),
                      _buildInfoRow('Bereich', domain?.name ?? 'Allgemein'),
                      const SizedBox(height: 8),
                      _buildInfoRow('Wiederholung', task.recurrence.germanLabel),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Startdatum',
                        '${task.startDate.day}. ${_monthName(task.startDate.month)} ${task.startDate.year}',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Fällig am',
                        '${dueDate.day}. ${_monthName(dueDate.month)} ${dueDate.year}',
                      ),
                      if (task.completedAt != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Abgeschlossen am',
                          '${task.completedAt!.day}. ${_monthName(task.completedAt!.month)} ${task.completedAt!.year}',
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (!isDone)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isBusy ? null : _markAsDone,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Erledigt'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      if (isDone)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isBusy ? null : _reopenTask,
                            icon: const Icon(Icons.undo),
                            label: const Text('Abschluss rückgängig'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Aktivitätsverlauf', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      if (task.logEntries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Noch keine Einträge',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      else
                        _buildTimeline(task.logEntries),
                      const SizedBox(height: 24),
                      if (!isDone) _buildAddLogEntryForm(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isBusy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color.fromRGBO(0, 0, 0, 0.15),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      ), // PopScope
    );
  }

  Widget _buildInfoSection(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightGrey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(content.isEmpty ? '–' : content),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }

  Widget _buildTimeline(List<TaskLogEntry> entries) {
    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final isLast = index == entries.length - 1;

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.teal,
                        border: Border.all(color: AppColors.appWhite, width: 2),
                      ),
                    ),
                    if (!isLast) Container(width: 2, height: 60, color: AppColors.lightGrey),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.user,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _formatDate(entry.timestamp),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(entry.text, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            if (!isLast) const SizedBox(height: 16),
          ],
        );
      }),
    );
  }

  Widget _buildAddLogEntryForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Neuer Eintrag', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            TextField(
              controller: _userNameController,
              decoration: InputDecoration(
                labelText: 'Ihr Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _logTextController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Eintrag',
                hintText: 'Beschreiben Sie den Fortschritt...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _addLogEntry,
                icon: const Icon(Icons.add),
                label: const Text('Eintrag hinzufügen'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.open:       return Colors.grey;
      case TaskStatus.inProgress: return AppColors.teal;
      case TaskStatus.done:       return Colors.green;
    }
  }

  String _monthName(int month) {
    const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
                    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    return '${date.day}. ${_monthName(date.month)} ${date.year}, '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
