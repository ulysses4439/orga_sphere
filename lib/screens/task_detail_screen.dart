import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';

class TaskDetailScreen extends StatefulWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final TaskService _taskService = TaskService();
  late TaskInstance? _task;
  final _logTextController = TextEditingController();
  final _userNameController = TextEditingController(text: 'Steven');
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _task = _taskService.getInstanceById(widget.taskId);
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
        _task = _taskService.getInstanceById(widget.taskId);
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
    final template = _task != null ? _taskService.getTemplateById(_task!.templateId) : null;
    final isRecurring = template?.recurrence.isRecurring ?? false;
    final confirmationText = isRecurring
        ? 'Dies markiert die Aufgabe als abgeschlossen und erstellt automatisch eine neue Wiederholung.'
        : 'Dies markiert die Aufgabe als abgeschlossen. Es wird keine neue Aufgabe erstellt.';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aufgabe als fertig markieren?'),
        content: Text(confirmationText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isBusy = true);
              try {
                await _taskService.markAsDone(widget.taskId);
                if (!mounted) return;
                setState(() {
                  _task = _taskService.getInstanceById(widget.taskId);
                  _isBusy = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aufgabe als fertig markiert')),
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler: $e')),
                );
              }
            },
            child: const Text('Ja, fertig stellen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aufgabe nicht gefunden')),
        body: const Center(child: Text('Diese Aufgabe konnte nicht gefunden werden')),
      );
    }

    final task = _task!;
    final dueDate = task.dueDate;
    final domain = _taskService.getDomainById(task.domainId);
    final template = _taskService.getTemplateById(task.templateId);
    final recurrenceLabel = template?.recurrence.germanLabel ?? 'Einmalig';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgabendetails'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color.fromRGBO(94, 53, 177, 0.1),
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
                      Text('Jahr: ${task.year}', style: Theme.of(context).textTheme.titleMedium),
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
                      _buildInfoRow('Wiederholung', recurrenceLabel),
                      const SizedBox(height: 8),
                      _buildInfoRow('Fällig am', '${dueDate.day}. ${_monthName(dueDate.month)} ${dueDate.year}'),
                      const SizedBox(height: 8),
                      _buildInfoRow('Startdatum', '${task.startDate.day}. ${_monthName(task.startDate.month)} ${task.startDate.year}'),
                      const SizedBox(height: 8),
                      _buildInfoRow('Erstellt am', '${task.createdAt.day}. ${_monthName(task.createdAt.month)} ${task.createdAt.year}'),
                      if (task.completedAt != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Abgeschlossen am',
                          '${task.completedAt!.day}. ${_monthName(task.completedAt!.month)} ${task.completedAt!.year}',
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Aktivitätsverlauf', style: Theme.of(context).textTheme.titleLarge),
                          if (task.status != TaskStatus.done)
                            TextButton.icon(
                              onPressed: _isBusy ? null : _markAsDone,
                              icon: const Icon(Icons.check),
                              label: const Text('Als fertig markieren'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (task.logEntries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Noch keine Einträge',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      else
                        _buildTimeline(task.logEntries),
                      const SizedBox(height: 24),
                      if (task.status != TaskStatus.done) _buildAddLogEntryForm(),
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
    );
  }

  Widget _buildInfoSection(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(content),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
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
                        color: Colors.deepPurple,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                    if (!isLast) Container(width: 2, height: 60, color: Colors.grey[300]),
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
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _formatDate(entry.timestamp),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
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
      case TaskStatus.inProgress: return Colors.blue;
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
