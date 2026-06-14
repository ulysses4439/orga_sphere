import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/task_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import 'reminder_picker_dialog.dart';

/// Reusable sphere detail body – used as embedded panel (desktop) and
/// as the body of TaskDetailScreen (mobile).
class SphereDetailContent extends StatefulWidget {
  final String taskId;
  final VoidCallback? onDeleted;
  final VoidCallback? onClose;
  final VoidCallback? onChanged;
  final VoidCallback? onMarkedDone;
  final VoidCallback? onReopened;

  const SphereDetailContent({
    super.key,
    required this.taskId,
    this.onDeleted,
    this.onClose,
    this.onChanged,
    this.onMarkedDone,
    this.onReopened,
  });

  @override
  State<SphereDetailContent> createState() => _SphereDetailContentState();
}

class _SphereDetailContentState extends State<SphereDetailContent> {
  final TaskService _taskService = TaskService();
  late Task? _task;
  final _logTextController = TextEditingController();
  late final TextEditingController _descriptionController;
  late final FocusNode _descriptionFocusNode;
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late final ScrollController _outerScrollController;
  String _lastSavedDescription = '';
  String _lastSavedTitle = '';
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _task = _taskService.getTaskById(widget.taskId);
    _lastSavedDescription = _task?.description ?? '';
    _lastSavedTitle = _task?.title ?? '';
    _descriptionController = TextEditingController(text: _lastSavedDescription);
    _descriptionFocusNode = FocusNode()
      ..addListener(_onDescriptionFocusChange);
    _titleController = TextEditingController(text: _lastSavedTitle);
    _titleFocusNode = FocusNode()..addListener(_onTitleFocusChange);
    _outerScrollController = ScrollController();
    _taskService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _taskService.removeListener(_onServiceChanged);
    _logTextController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _titleController.dispose();
    _titleFocusNode.dispose();
    _outerScrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final updated = _taskService.getTaskById(widget.taskId);
    if (updated == null) return;
    setState(() => _task = updated);
    // Nur aktualisieren wenn das Feld gerade nicht bearbeitet wird
    if (!_titleFocusNode.hasFocus) {
      final newTitle = updated.title;
      if (newTitle != _lastSavedTitle) {
        _lastSavedTitle = newTitle;
        _titleController.text = newTitle;
      }
    }
    if (!_descriptionFocusNode.hasFocus) {
      final newDesc = updated.description;
      if (newDesc != _lastSavedDescription) {
        _lastSavedDescription = newDesc;
        _descriptionController.text = newDesc;
      }
    }
  }

  void _onTitleFocusChange() {
    if (!_titleFocusNode.hasFocus) _saveTitle();
  }

  Future<void> _saveTitle() async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle == _lastSavedTitle) return;
    _lastSavedTitle = newTitle;
    try {
      await _taskService.updateTaskTitle(widget.taskId, newTitle);
      if (mounted) {
        setState(() => _task = _taskService.getTaskById(widget.taskId));
        widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _onDescriptionFocusChange() {
    if (!_descriptionFocusNode.hasFocus) _saveDescription();
  }

  Future<void> _saveDescription() async {
    final newDesc = _descriptionController.text;
    if (newDesc == _lastSavedDescription) return;
    _lastSavedDescription = newDesc;
    try {
      await _taskService.updateTaskDescription(widget.taskId, newDesc);
      if (mounted) setState(() => _task = _taskService.getTaskById(widget.taskId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
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
    // .toLocal() fixes UTC-stored reminderAt showing wrong time in the picker.
    final initial = _task?.reminderAt?.toLocal();

    final result = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => ReminderPickerDialog(initialDateTime: initial),
    );
    if (result == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await _taskService.setReminder(widget.taskId, result);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
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
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _pickAssignee(Task task) async {
    setState(() => _isBusy = true);
    List<OrbitMember> members;
    try {
      members = await ApiService.getOrbitMembers(task.domainId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _isBusy = false);

    // Zuweisung nur an aktive (Co-)Piloten dieses Orbits.
    final active = members.where((m) => m.status == 'active').toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Zuweisen an'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _assign(task, null);
            },
            child: Row(
              children: [
                Icon(Icons.person_off_outlined, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 12),
                const Text('Niemand'),
              ],
            ),
          ),
          ...active.map(
            (m) => SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _assign(task, m);
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: m.isPilot ? AppColors.teal : Colors.blueGrey,
                    child: Text(
                      m.displayLabel.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.displayLabel, overflow: TextOverflow.ellipsis),
                        Text(
                          m.isPilot ? 'Pilot' : 'Co-Pilot',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (task.assignedToMemberId == m.id)
                    const Icon(Icons.check, size: 18, color: AppColors.teal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(Task task, OrbitMember? member) async {
    setState(() => _isBusy = true);
    try {
      await _taskService.assignTask(
        task.id,
        member?.id,
        displayName: member?.displayName,
        email: member?.email,
      );
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  void _startTask() {
    final logCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setSt) => AlertDialog(
          title: const Text('In Bearbeitung setzen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Was ist der aktuelle Stand oder nächste Schritt?'),
              const SizedBox(height: 12),
              TextField(
                controller: logCtrl,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ersten Eintrag eingeben…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setSt(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                logCtrl.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: logCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      final text = logCtrl.text.trim();
                      logCtrl.dispose();
                      Navigator.pop(dialogContext);
                      setState(() => _isBusy = true);
                      try {
                        await _taskService.startTask(widget.taskId);
                        await _taskService.addLogEntry(widget.taskId, text);
                        if (!mounted) return;
                        setState(() {
                          _task = _taskService.getTaskById(widget.taskId);
                          _isBusy = false;
                        });
                      } catch (e) {
                        if (!mounted) return;
                        setState(() => _isBusy = false);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                      }
                    },
              child: const Text('In Bearbeitung'),
            ),
          ],
        ),
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
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sphere erledigt')),
                );
                widget.onMarkedDone?.call();
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
                setState(() => _isBusy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sphere wieder geöffnet')),
                );
                widget.onReopened?.call();
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
        Scrollbar(
          controller: _outerScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _outerScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kasten 1: Sphere-Titel (variable Höhe, navyPale)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.navyPale,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              focusNode: _titleFocusNode,
                              style: Theme.of(context).textTheme.headlineSmall,
                              maxLines: null,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: (_) => _saveTitle(),
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
                            _periodLabel(task),
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

                const Divider(height: 1, thickness: 1, color: Colors.black),

                // Kasten 2: Beschreibung + Metadaten + Aktionen (variable Höhe)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDescriptionField(),
                      const SizedBox(height: 16),
                      _buildInfoRow('Orbit', domain?.name ?? 'Allgemein'),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Zugewiesen an',
                        task.assignedToLabel ?? 'Niemand',
                        valueColor: task.assignedToLabel == null ? Colors.grey[500] : null,
                        onTap: _isBusy ? null : () => _pickAssignee(task),
                        onClear: task.assignedToMemberId != null && !_isBusy
                            ? () => _assign(task, null)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Wiederholung',
                        task.recurrence.germanLabel,
                        onTap: _isBusy ? null : _pickRecurrence,
                      ),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Startdatum',
                        formatDate(task.startDate),
                        onTap: _isBusy ? null : _pickStartDate,
                      ),
                      const SizedBox(height: 8),
                      _buildTappableInfoRow(
                        'Fällig am',
                        dueDate != null ? formatDate(dueDate) : 'Kein Datum',
                        valueColor: dueDate != null && dueDate.isBefore(DateTime.now()) && !isDone
                            ? Colors.red
                            : null,
                        onTap: _isBusy ? null : _pickDueDate,
                        onClear: dueDate != null && !_isBusy ? _clearDueDate : null,
                      ),
                      const SizedBox(height: 8),
                      _buildReminderRow(task),
                      if (task.completedAt != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Abgeschlossen am',
                          formatDate(task.completedAt!),
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

                const Divider(height: 1, thickness: 1, color: Colors.black),

                // Kasten 3: Neuer Eintrag (fixe Höhe, Textbox scrollt intern, navyPale)
                if (!isDone) ...[
                  _buildAddLogEntryForm(),
                  const Divider(height: 1, thickness: 1, color: Colors.black),
                ],

                // Kasten 4: Aktivitätsverlauf (variable Höhe, weißer Hintergrund)
                _buildActivityLog(task),
              ],
            ),
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

  Widget _buildActivityLog(Task task) {
    return Container(
      width: double.infinity,
      color: AppColors.appWhite,
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
              ),
            )
          else
            _buildTimeline(task.logEntries),
        ],
      ),
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

    final reminderExpired =
        task.reminderAt!.isBefore(DateTime.now()) && task.status != TaskStatus.done;
    final reminderColor = reminderExpired ? Colors.red : AppColors.teal;

    if (reminderExpired) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.notifications_active, color: reminderColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _formatReminderDate(task.reminderAt!),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: reminderColor,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: _isBusy ? null : _clearReminder,
              icon: const Icon(Icons.notifications_off_outlined, size: 16),
              label: const Text('Erinnerung löschen'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
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
            Icon(Icons.notifications_active, color: reminderColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _formatReminderDate(task.reminderAt!),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: reminderColor,
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

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Beschreibung',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          focusNode: _descriptionFocusNode,
          maxLines: null,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Beschreibung hinzufügen…',
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.lightGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.teal, width: 2),
            ),
            filled: true,
            fillColor: AppColors.appWhite,
          ),
        ),
      ],
    );
  }

  String _periodLabel(Task task) {
    final d = task.startDate;
    final months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    switch (task.recurrence.frequency) {
      case RecurrenceFrequency.none:
        return 'Einmalig';
      case RecurrenceFrequency.daily:
        return 'Datum: ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      case RecurrenceFrequency.weekly:
        final monday = d.subtract(Duration(days: d.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        String fmt(DateTime x) =>
            '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
        return 'Woche: ${fmt(monday)} – ${fmt(sunday)}';
      case RecurrenceFrequency.monthly:
        return 'Monat: ${months[d.month - 1]} ${d.year}';
      case RecurrenceFrequency.yearly:
        return 'Jahr: ${d.year}';
    }
  }

  Future<void> _pickStartDate() async {
    final task = _task;
    if (task == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: task.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(widget.taskId, startDate: picked);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _pickDueDate() async {
    final task = _task;
    if (task == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(widget.taskId, dueDate: picked);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _clearDueDate() async {
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(widget.taskId, clearDueDate: true);
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _pickRecurrence() async {
    final task = _task;
    if (task == null) return;
    String frequencyLabel(RecurrenceFrequency f) {
      switch (f) {
        case RecurrenceFrequency.none:    return 'Einmalig';
        case RecurrenceFrequency.daily:   return 'Täglich';
        case RecurrenceFrequency.weekly:  return 'Wöchentlich';
        case RecurrenceFrequency.monthly: return 'Monatlich';
        case RecurrenceFrequency.yearly:  return 'Jährlich';
      }
    }
    final picked = await showDialog<RecurrenceFrequency>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Wiederholung'),
        children: RecurrenceFrequency.values.map((f) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, f),
          child: Text(frequencyLabel(f)),
        )).toList(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _isBusy = true);
    try {
      await _taskService.updateTaskSchedule(
        widget.taskId,
        recurrenceFrequency: picked.name,
        recurrenceInterval: picked == RecurrenceFrequency.none ? 1 : task.recurrence.interval,
      );
      if (!mounted) return;
      setState(() {
        _task = _taskService.getTaskById(widget.taskId);
        _isBusy = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Widget _buildTappableInfoRow(
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor)),
                if (onClear != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(12),
                    child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 14, color: Colors.grey[400]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
        Text(value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor)),
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
    return SizedBox(
      height: 210,
      child: Material(
        elevation: 0,
        color: AppColors.navyPale,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Neuer Eintrag', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    AuthService.displayName ?? AuthService.email ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _logTextController,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: 'Beschreiben Sie den Fortschritt...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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

  String _formatDate(DateTime date) => formatDateTime(date);

  String _formatReminderDate(DateTime date) => formatDateTime(date.toLocal());
}
