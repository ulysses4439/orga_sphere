import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';

/// Screen showing detailed information about a task instance
/// Displays task info, timeline of log entries, and ability to add new entries
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

  void _addLogEntry() {
    if (_logTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte geben Sie einen Text ein')),
      );
      return;
    }

    _taskService.addLogEntry(
      widget.taskId,
      _userNameController.text.trim(),
      _logTextController.text.trim(),
    );

    _logTextController.clear();
    setState(() {
      _task = _taskService.getInstanceById(widget.taskId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Eintrag hinzugefügt')),
    );
  }

  void _markAsDone() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aufgabe als fertig markieren?'),
        content: Text(
          'Dies markiert die Aufgabe als abgeschlossen und erstellt automatisch eine neue Instanz für ${_task!.year + 1}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              _taskService.markAsDone(widget.taskId);
              setState(() {
                _task = _taskService.getInstanceById(widget.taskId);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Aufgabe als fertig markiert')),
              );
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
    final dueDate = task.getDueDate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgabendetails'),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task header with title and year
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.deepPurple.withOpacity(0.1),
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

            // Task info section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoSection('Beschreibung', task.description),
                  const SizedBox(height: 16),
                  _buildInfoRow('Fällig am', '${dueDate.day}. ${_monthName(dueDate.month)} ${dueDate.year}'),
                  const SizedBox(height: 8),
                  _buildInfoRow('Startmonat', _monthName(task.startMonth)),
                  const SizedBox(height: 8),
                  _buildInfoRow('Erstellt am', '${task.createdAt.day}. ${_monthName(task.createdAt.month)} ${task.createdAt.year}'),
                  if (task.completedAt != null) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow('Abgeschlossen am', '${task.completedAt!.day}. ${_monthName(task.completedAt!.month)} ${task.completedAt!.year}'),
                  ],
                ],
              ),
            ),

            const Divider(),

            // Activity timeline section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Aktivitätsverlauf',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (task.status != TaskStatus.done)
                        TextButton.icon(
                          onPressed: _markAsDone,
                          icon: const Icon(Icons.check),
                          label: const Text('Als fertig markieren'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Log entries timeline
                  if (task.logEntries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Noch keine Einträge',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ),
                    )
                  else
                    _buildTimeline(task.logEntries),

                  const SizedBox(height: 24),

                  // Add log entry form
                  if (task.status != TaskStatus.done) _buildAddLogEntryForm(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build info section with label and content
  Widget _buildInfoSection(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[700],
              ),
        ),
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

  /// Build info row with label and value
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[700],
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }

  /// Build activity timeline
  Widget _buildTimeline(List<TaskLogEntry> entries) {
    return Column(
      children: List.generate(
        entries.length,
        (index) {
          final entry = entries[index];
          final isLast = index == entries.length - 1;

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline dot and line
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
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 60,
                          color: Colors.grey[300],
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // Entry content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.user,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              _formatDate(entry.timestamp),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.text,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!isLast) const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  /// Build form to add new log entry
  Widget _buildAddLogEntryForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Neuer Eintrag',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),

            // User name field
            TextField(
              controller: _userNameController,
              decoration: InputDecoration(
                labelText: 'Ihr Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),

            // Log text field
            TextField(
              controller: _logTextController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Eintrag',
                hintText: 'Beschreiben Sie den Fortschritt...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addLogEntry,
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

  /// Get color for task status
  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.open:
        return Colors.grey;
      case TaskStatus.inProgress:
        return Colors.blue;
      case TaskStatus.done:
        return Colors.green;
    }
  }

  /// Get German month name
  String _monthName(int month) {
    const months = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember'
    ];
    return months[month - 1];
  }

  /// Format date and time
  String _formatDate(DateTime date) {
    return '${date.day}. ${_monthName(date.month)} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
