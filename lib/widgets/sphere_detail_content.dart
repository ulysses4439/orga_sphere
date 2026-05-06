import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';

/// Reusable sphere detail body – used as embedded panel (desktop) and
/// as the body of TaskDetailScreen (mobile).
class SphereDetailContent extends StatefulWidget {
  final String taskId;
  final VoidCallback? onDeleted;
  final VoidCallback? onClose;

  const SphereDetailContent({
    super.key,
    required this.taskId,
    this.onDeleted,
    this.onClose,
  });

  @override
  State<SphereDetailContent> createState() => _SphereDetailContentState();
}

class _SphereDetailContentState extends State<SphereDetailContent> {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _task?.reminderAt ?? now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      helpText: 'Erinnerungsdatum wählen',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Erinnerungszeit wählen',
    );
    if (time == null || !mounted) return;

    final reminderAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _isBusy = true);
    try {
      await _taskService.setReminder(widget.taskId, reminderAt);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _clearReminder() async {
    setState(() => _isBusy = true);
    try {
      await _taskService.setReminder(widget.taskId, null);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  void _startTask() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('In Bearbeitung setzen?'),
        content: const Text('Die Sphere wird als "In Bearbeitung" markiert.'),
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
                await _taskService.startTask(widget.taskId);
                if (!mounted) return;
                setState(() {
                  _task = _taskService.getTaskById(widget.taskId);
                  _isBusy = false;
                });
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
              }
            },
            child: const Text('In Bearbeitung'),
          ),
        ],
      ),
    );
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
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
                widget.onDeleted?.call();
              } catch (e) {
                if (!mounted) return;
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
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
      return const Center(child: Text('Sphere nicht gefunden'));
    }

    final task = _task!;
    final dueDate = task.dueDate;
    final domain = _taskService.getDomainById(task.domainId);
    final isDone = task.status == TaskStatus.done;

    return Stack(
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        if (widget.onClose != null)
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: widget.onClose,
                            tooltip: 'Schließen',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Jahr: ${task.year}',
                          style: Theme.of(context).textTheme.titleMedium,
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
                    _buildInfoRow('Orbit', domain?.name ?? 'Allgemein'),
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
                    const SizedBox(height: 8),
                    _buildReminderRow(task),
                    if (task.completedAt != null) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Abgeschlossen am',
                        '${task.completedAt!.day}. ${_monthName(task.completedAt!.month)} ${task.completedAt!.year}',
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (task.status == TaskStatus.open) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isBusy ? null : _startTask,
                              icon: const Icon(Icons.timelapse),
                              label: const Text('In Bearbeitung'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
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
                        ],
                      ),
                    ],
                    if (task.status == TaskStatus.inProgress)
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
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _deleteTask,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text(
                          'Sphere löschen',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }

  Widget _buildReminderRow(Task task) {
    if (task.reminderAt == null) {
      return InkWell(
        onTap: _isBusy ? null : _pickReminder,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.notifications_none, color: Colors.grey[400], size: 20),
              const SizedBox(width: 8),
              Text(
                'Erinnerung hinzufügen',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.grey[400],
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: _isBusy ? null : _pickReminder,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.notifications_active, color: AppColors.teal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _formatReminderDate(task.reminderAt!),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.teal,
                    ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: Colors.grey[500]),
              tooltip: 'Erinnerung entfernen',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _isBusy ? null : _clearReminder,
            ),
          ],
        ),
      ),
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
      case TaskStatus.open:
        return Colors.grey;
      case TaskStatus.inProgress:
        return AppColors.teal;
      case TaskStatus.done:
        return Colors.green;
    }
  }

  String _monthName(int month) {
    const months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    return '${date.day}. ${_monthName(date.month)} ${date.year}, '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatReminderDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day}. ${_monthName(local.month)} ${local.year}, '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} Uhr';
  }
}
